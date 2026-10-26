#!/usr/bin/env python3
"""Selected GGUF folder: direct argv, queued discovery, typed persistence.

Only owned sparse fixture headers are read. No model is inferred or downloaded.
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

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/ai/local_models.py'
spec = importlib.util.spec_from_file_location('folder_inventory', SCRIPT)
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)

QML = '''
import QtQuick
import Quickshell
import qs.modules.common
import qs.services
ShellRoot {
    id: root
    property int stage: 0
    property int ticks: 0
    property int settle: 0
    property int updates: 0
    function require(ok,label) { if(!ok){console.error("LOCAL_FOLDER_FAIL:"+label);Qt.exit(1)} }
    Connections {
        target: LocalModels
        function onUpdated() {
            ++root.updates
            root.require(LocalModels.error === "", "discovery error")
            root.require(LocalModels.models.length === 1 && LocalModels.models[0].name === "B", "latest folder only")
            root.require(LocalModels.models[0].path === Quickshell.env("MODEL_B") + "/B.gguf", "direct argument preserved")
            root.stage = 3
        }
    }
    Timer {
        interval:100;running:true;repeat:true
        onTriggered: {
            root.require(++root.ticks < 100, "finite scan deadline")
            if(!Config.ready)return
            if(root.stage === 0) {
                root.require(!LocalModels.initialized && !LocalModels.refreshing, "discovery remains lazy")
                Config.setNestedValue("ai.localModelFolder", Quickshell.env("MODEL_A"))
                LocalModels.ensureInitialized()
                root.stage = 1
            } else if(root.stage === 1 && LocalModels.refreshing) {
                Config.setNestedValue("ai.localModelFolder", Quickshell.env("MODEL_B"))
                LocalModels.refresh()
                root.stage = 2
            } else if(root.stage === 3 && ++root.settle >= 6) {
                root.require(root.updates === 1 && !LocalModels.refreshing, "stale job did not publish")
                root.require(Config.options.ai.localModelFolder === Quickshell.env("MODEL_B"), "typed folder")
                console.log("LOCAL_MODEL_FOLDER_QML_QUEUE_AND_PERSISTENCE_PASS")
                Qt.quit()
            }
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix='local-model-folder-') as temporary:
    private = Path(temporary)
    a = private / 'slow A'; b = private / "Unsloth's models (B)"
    for folder, name in ((a, 'A'), (b, 'B')):
        folder.mkdir()
        with (folder / (name + '.gguf')).open('wb') as output:
            output.write(struct.pack('<4sIQQ', b'GGUF', 3, 1, 1))
            output.truncate(21 * 1024 * 1024)
    env = dict(os.environ, ALIS_GGUF_ROOTS='[]', PYTHONDONTWRITEBYTECODE='1')
    result = subprocess.run(['python3', str(SCRIPT), '--extra-root', str(b)], env=env, capture_output=True, text=True, check=True)
    found = json.loads(result.stdout)
    assert len(found['models']) == 1 and found['models'][0]['path'] == str(b / 'B.gguf')
    for invalid in ('relative/model-folder', 'x' * 4097):
        result = subprocess.run(['python3', str(SCRIPT), '--extra-root', invalid], env=env, capture_output=True, text=True, check=True)
        assert json.loads(result.stdout)['models'] == [] and json.loads(result.stdout).get('error')
    with patch.dict(os.environ, ALIS_GGUF_ROOTS=json.dumps([str(a)])):
        assert inventory.roots(str(b)) == [b, a]
        assert inventory.roots(str(a)) == [a]
        assert inventory.roots() == [a]
    with patch.dict(os.environ):
        for key in ('ALIS_GGUF_ROOTS','HF_HUB_CACHE','HUGGINGFACE_HUB_CACHE','HF_HOME','XDG_CACHE_HOME'):
            os.environ.pop(key,None)
        assert inventory.roots()[0]==Path.home()/'.cache/huggingface/hub'
        os.environ['XDG_CACHE_HOME']=str(private/'xdg-cache')
        assert inventory.roots()[0]==private/'xdg-cache/huggingface/hub'
        os.environ['HF_HOME']=str(private/'hub-home')
        assert inventory.roots()[0]==private/'hub-home/hub'
        os.environ['HUGGINGFACE_HUB_CACHE']=str(a)
        assert inventory.roots()[0]==a
        os.environ['HF_HUB_CACHE']=str(b)
        assert inventory.roots()[0]==b
        cached=inventory.inventory(inventory.roots()[:1])
        assert [m['name'] for m in cached['models']]==['B'],'modern cache must beat stale alias'
        assert inventory.roots(str(a))[:2]==[a,b],'explicit extra root remains first'
        assert inventory.roots(str(b)).count(b)==1,'selected cache root is not duplicated'
        os.environ['ALIS_GGUF_ROOTS']='[]'
        assert inventory.roots()==[],'fixture override must isolate all standard caches'
    result = subprocess.run(['python3', str(SCRIPT), '--extra-root', str(private / 'missing')], env=env, capture_output=True, text=True, check=True)
    assert json.loads(result.stdout)['error'] == 'Model folder not found'

    shell = private / 'shell'; shell.mkdir()
    for name in ('modules','services','defaults','translations','assets','sdata','qmldir'):
        (shell / name).symlink_to(ROOT / name)
    for source in ROOT.glob('*.qml'):
        if source.name != 'shell.qml': (shell / source.name).symlink_to(source)
    # Delay only the first owned fixture so a real in-flight folder change is
    # deterministic; the unmodified inventory is then executed for both jobs.
    scripts = shell / 'scripts'
    shutil.copytree(ROOT / 'scripts', scripts, ignore=shutil.ignore_patterns('__pycache__'))
    wrapper = 'import runpy,sys,time\nif "--extra-root" in sys.argv and "slow A" in sys.argv[-1]:time.sleep(.4)\nrunpy.run_path(' + repr(str(SCRIPT)) + ',run_name="__main__")\n'
    (scripts / 'ai/local_models.py').write_text(wrapper)
    (shell / 'shell.qml').write_text(QML)
    config = private / 'config/illogical-impulse'; config.mkdir(parents=True)
    options = json.loads((ROOT / 'defaults/config.json').read_text())
    options['abyss']['companion']['enabled'] = False
    options['ai']['localModelFolder'] = ''
    (config / 'config.json').write_text(json.dumps(options))
    for key in ('DISPLAY','WAYLAND_DISPLAY','QS_CONFIG_NAME','QS_CONFIG_PATH','QML_IMPORT_PATH','QML2_IMPORT_PATH'):
        env.pop(key,None)
    for kind in ('CONFIG','DATA','CACHE','STATE'):
        folder = private / kind.lower(); folder.mkdir(exist_ok=True)
        env['XDG_' + kind + '_HOME'] = str(folder)
    env.update(QT_QPA_PLATFORM='offscreen',QT_NO_XDG_DESKTOP_PORTAL='1',QT_QPA_PLATFORMTHEME='generic',
               NIRI_SOCKET=str(private/'unavailable-niri.sock'),MODEL_A=str(a),MODEL_B=str(b))
    log = private / 'qml.log'
    with log.open('w') as output:
        process = subprocess.Popen(['dbus-run-session','--','qs','--path',str(shell/'shell.qml'),'--no-color'],env=env,
                                   stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
        try: code = process.wait(timeout=15)
        finally:
            if process.poll() is None: os.killpg(process.pid,signal.SIGTERM);process.wait(timeout=5)
    text = log.read_text()
    assert code == 0 and 'LOCAL_MODEL_FOLDER_QML_QUEUE_AND_PERSISTENCE_PASS' in text, text[-6000:]
    assert not any(e in text for e in ('ReferenceError:','TypeError:','Binding loop')),text[-6000:]
    saved = json.loads((config/'config.json').read_text())
    assert saved['ai']['localModelFolder'] == str(b)
    assert saved['abyss']['companion']['enabled'] is False
print('LOCAL_MODEL_FOLDER_DIRECT_ARGV_HF_CACHE_PRECEDENCE_LAZY_QUEUE_AND_PERSISTENCE_PASS')
