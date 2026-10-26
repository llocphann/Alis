#!/usr/bin/env python3
"""Finite checkpoint hints, GGUF separation and real owned QML diagnostics.

All files are synthetic. Never load tensors, a model, user prompts or a vault.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import tempfile
from unittest.mock import patch
from native_test_session import private_wayland

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('format_inventory', ROOT / 'scripts/ai/local_models.py')
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


def checkpoint(path, raw=None, length=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    header = raw if raw is not None else json.dumps({'weight': {'dtype': 'F16', 'shape': [1], 'data_offsets': [0, 2]},
        '__metadata__': {'note': 'PRIVATE_FIXTURE_METADATA_DO_NOT_EXPOSE'}}).encode()
    path.write_bytes(struct.pack('<Q', len(header) if length is None else length) + header + b'\0\0')


def gguf(path):
    with path.open('wb') as output:
        output.write(struct.pack('<4sIQQ', b'GGUF', 3, 1, 1))
        output.truncate(21*1024*1024)


QML = '''
import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import "modules/settings" as Settings
ShellRoot {
    id: root
    property int phase: 0
    property int ticks: 0
    function require(ok,label) { if(!ok){ console.log("MODEL_FORMAT_FAIL:"+label);Qt.exit(1) } }
    function find(item,name) {
        if(item.objectName===name)return item
        for(const child of item.children ?? []) {const match=find(child,name);if(match)return match}
        return null
    }
    Settings.AiConfig { id: page; width: 600; height: 850; activeSection: "providers" }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            root.require(++root.ticks<100,"finite UI deadline")
            if(!Config.ready)return
            if(root.phase===0) {
                Config.setNestedValue("ai.localModelFolder",Quickshell.env("FORMAT_FOLDER"))
                LocalModels.ensureInitialized()
                root.phase=1
                return
            }
            if(root.phase===2) {
                if(LocalModels.refreshing || LocalModels.error==="")return
                root.require(LocalModels.checkpoints.length===0 && LocalModels.models.length===0,
                    "failed refresh retained stale inventory")
                root.require(LocalModels.runtimePath==="","failed refresh retained runtime")
                root.require(!root.find(page,"localCheckpointStatus").visible,"failed refresh retained hint")
                root.require(Config.options.abyss.companion.enabled===false,"actor enabled")
                console.log("LOCAL_MODEL_FORMAT_QML_PASS checkpointVisible plainText notRunnable noInference staleClear")
                Qt.quit()
                return
            }
            if(LocalModels.refreshing || LocalModels.checkpoints.length!==1)return
            const hint=root.find(page,"localCheckpointStatus")
            const status=root.find(page,"localModelStatus")
            root.require(LocalModels.models.length===0,"checkpoint entered executable GGUF catalog")
            root.require(LocalModels.checkpoints[0].runnable===false,"checkpoint claimed runnable")
            root.require(LocalModels.error==="","format scan error")
            root.require(hint && hint.visible,"checkpoint hint hidden")
            root.require(hint.text==="Unsloth <checkpoint> · Safetensors","checkpoint name")
            root.require(hint.textFormat===Text.PlainText,"filename rendered as markup")
            root.require(status && status.ok===false,"checkpoint claimed chat-ready")
            root.require(status.label==="Downloaded checkpoints detected","checkpoint status")
            root.require(status.detail==="Choose a GGUF export for local chat","conversion guidance")
            root.require(!Ai.modelList.some(id=>id.indexOf("checkpoint:")===0),"checkpoint entered shared AI")
            root.require(Config.options.abyss.companion.enabled===false,"actor enabled")
            root.phase=2
            Config.setNestedValue("ai.localModelFolder",Quickshell.env("FORMAT_BAD_FOLDER"))
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix='local-model-formats-') as temporary:
    private = Path(temporary)
    source = private / 'Unsloth <checkpoint>'
    checkpoint(source / 'model-00001-of-00002.safetensors')
    checkpoint(source / 'model-00002-of-00002.safetensors')
    with patch.object(inventory, 'runtime', return_value=''):
        result = inventory.inventory([source])
    assert result['models'] == [] and len(result['checkpoints']) == 1
    assert result['checkpoints'][0]['name'] == source.name and result['checkpoints'][0]['runnable'] is False
    assert 'PRIVATE_FIXTURE_METADATA' not in json.dumps(result)
    assert 'weight' not in json.dumps(result)
    gguf(source / 'Qwen3-Q4_K_M.gguf')
    mixed = inventory.inventory([source])
    assert len(mixed['models']) == 1 and mixed['models'][0]['id'].startswith('gguf:')
    assert len(mixed['checkpoints']) == 1 and mixed['checkpoints'][0]['id'].startswith('checkpoint:')
    (source / 'Qwen3-Q4_K_M.gguf').unlink()
    hub = private / 'models--unsloth--Tiny-Model/snapshots/012345'
    hub.mkdir(parents=True)
    (hub / 'model.safetensors').symlink_to(source / 'model-00001-of-00002.safetensors')
    found = inventory.inventory([hub,source])
    assert len(found['checkpoints']) == 1 and found['checkpoints'][0]['name'] == 'unsloth/Tiny-Model'
    invalid = private / 'invalid.safetensors'
    for raw, length in [(b'{}',2**60), (b'[]',None), (b'{"__metadata__":{"a":"b"}}',None),
                        (b'{"weight":{},"weight":{}}',None),
                        (b'{"weight":{"dtype":"F16","shape":[1],"data_offsets":[0,99]}}',None),
                        (b'{"weight":{"dtype":"F16","shape":[true],"data_offsets":[0,2]}}',None)]:
        checkpoint(invalid,raw,length)
        recognized,read = inventory.checkpoint_file(invalid,262152)
        assert not recognized and read<=262152
    assert inventory.checkpoint_file(invalid,-1) == (False,0)
    assert inventory.checkpoint_file(source/'model-00001-of-00002.safetensors',8) == (False,8)
    limits = private / 'limits'
    for i in range(20): checkpoint(limits / str(i) / 'model.safetensors')
    assert len(inventory.inventory([limits])['checkpoints']) == 8
    oversized = private / 'headers'
    header = b'{"bad":{}}' + b' '*(262144-len(b'{"bad":{}}'))
    for i in range(12): checkpoint(oversized / str(i) / 'model.safetensors',header)
    reads = []
    actual = inventory.checkpoint_file
    def counted(file,budget):
        pair = actual(file,budget); reads.append(pair[1]); return pair
    with patch.object(inventory,'checkpoint_file',side_effect=counted):
        assert inventory.inventory([oversized])['checkpoints'] == []
    assert sum(reads)<=2*1024*1024, 'header inventory exceeded finite metadata budget'

    if not shutil.which('niri') or not os.environ.get('WAYLAND_DISPLAY'):
        print('SKIP local-model format QML: owned Wayland backend required; inventory contracts passed only')
        raise SystemExit(0)

    # Real settings/service integration uses owned state and no provider network.
    shell = private / 'shell';shell.mkdir()
    for name in ('modules','services','defaults','translations','assets','sdata','qmldir'):
        (shell/name).symlink_to(ROOT/name)
    for file in ROOT.glob('*.qml'):
        if file.name!='shell.qml':(shell/file.name).symlink_to(file)
    shutil.copytree(ROOT/'scripts',shell/'scripts',ignore=shutil.ignore_patterns('__pycache__'))
    # Existing settings initialize provider/voice catalogs; intercept only their
    # external transport helpers in this fixture. Inventory remains unmodified.
    (shell/'scripts/ai/discover-provider-models.py').write_text('import json\nprint(json.dumps({"models":[],"status":"unavailable"}))\n')
    (shell/'scripts/voiceSearch/transcribe-audio.py').write_text('import json\nprint(json.dumps({"available":False}))\n')
    broken=private/'broken-format';broken.mkdir()
    wrapper='import runpy,sys\nif sys.argv[-1].endswith("broken-format"):print("not-json")\nelse:runpy.run_path('+repr(str(ROOT/'scripts/ai/local_models.py'))+',run_name="__main__")\n'
    (shell/'scripts/ai/local_models.py').write_text(wrapper)
    (shell/'shell.qml').write_text(QML)
    options=json.loads((ROOT/'defaults/config.json').read_text())
    options['abyss']['companion']['enabled']=False
    options['ai']['localModelFolder']=str(source)
    env=dict(os.environ,INIR_GGUF_ROOTS='[]',FORMAT_FOLDER=str(source),FORMAT_BAD_FOLDER=str(broken),PYTHONDONTWRITEBYTECODE='1')
    for name in ('CONFIG','DATA','CACHE','STATE'):
        directory=private/name.lower();directory.mkdir(exist_ok=True)
        env['XDG_'+name+'_HOME']=str(directory)
    config=private/'config/illogical-impulse';config.mkdir()
    runtime=private/'runtime';runtime.mkdir(mode=0o700)
    env['XDG_RUNTIME_DIR']=str(runtime)
    (config/'config.json').write_text(json.dumps(options))
    for key in ('DISPLAY','WAYLAND_DISPLAY','QML_IMPORT_PATH','QML2_IMPORT_PATH','QS_CONFIG_NAME','QS_CONFIG_PATH'):
        env.pop(key,None)
    env.update(QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',QT_NO_XDG_DESKTOP_PORTAL='1',QT_QPA_PLATFORMTHEME='generic',
               NIRI_SOCKET=str(private/'unavailable-niri.sock'))
    log=private/'qml.log'
    compositor=private/'compositor';compositor.mkdir()
    with private_wayland(compositor) as display:
        for key in ('WAYLAND_DISPLAY','XDG_RUNTIME_DIR','NIRI_SOCKET'):env[key]=display[key]
        with log.open('w') as output:
            process=subprocess.Popen(['dbus-run-session','--','qs','--path',str(shell/'shell.qml'),'--no-color'],env=env,
                                     stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
            try:code=process.wait(timeout=15)
            finally:
                if process.poll() is None:os.killpg(process.pid,signal.SIGTERM);process.wait(timeout=5)
    text=log.read_text()
    assert code==0 and 'LOCAL_MODEL_FORMAT_QML_PASS' in text,text[-6000:]
    assert not any(e in text for e in ('MODEL_FORMAT_FAIL:','ReferenceError:','TypeError:','Binding loop')),text[-6000:]
    saved=json.loads((config/'config.json').read_text())
    assert saved['abyss']['companion']['enabled'] is False
print('LOCAL_MODEL_FORMATS_PASS finiteHeaders mixedGGUF shardDedup invalidHeaders QMLStatus notRunnable')
