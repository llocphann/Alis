#!/usr/bin/env bash
# Qualify actual adapter migration before Config.ready and persisted preferences.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null; then printf 'SKIP: style adapter (Quickshell unavailable)\n'; exit 0; fi
python3 - "$repo_root" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile, time
repo=pathlib.Path(sys.argv[1])
for family in ('ii','waffle','abyss'):
    with tempfile.TemporaryDirectory(prefix='hadalis-style-adapter-') as directory:
        root=pathlib.Path(directory)
        for entry in ('modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations'):
            (root/entry).symlink_to(repo/entry)
        config=root/'config/alis/config.json';config.parent.mkdir(parents=True)
        old={'panelFamily':family,'enabledPanels':['iiBar','iiCheatsheet','wBar'],
             'knownPanels':['iiDock','iiBar','iiCheatsheet'],'visitedPanelFamilies':[family],
             'dock':{'iconSize':43},'customExample':{'keep':'unchanged'}}
        config.write_text(json.dumps(old))
        (root/'shell.qml').write_text('''//@ pragma ShellId hadalis-style-adapter-test
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
ShellRoot {
    property bool firstReady: false
    property bool firstReadyMigrated: false
    Connections {
        target: Config
        function onReadyChanged() {
            if(Config.ready && !firstReady) {
                firstReady=true
                firstReadyMigrated=Config.options.panelStyleVersion===1 && Config.options.panelFamily!=="ii"
            }
        }
    }
    IpcHandler {
        target: "migrationProbe"
        function snapshot(): string {
            return JSON.stringify({ready:Config.ready,firstReadyMigrated:firstReadyMigrated,
                family:Config.options.panelFamily,version:Config.options.panelStyleVersion,
                enabled:Array.from(Config.options.enabledPanels),known:Array.from(Config.options.knownPanels),
                iconSize:Config.options.dock.iconSize})
        }
    }
}
''')
        env=os.environ.copy()
        for key in ('QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST','WAYLAND_DISPLAY','DISPLAY'):
            env.pop(key,None)
        env.update(QT_QPA_PLATFORM='offscreen',LC_ALL='C.UTF-8',XDG_CONFIG_HOME=str(root/'config'),
                   XDG_STATE_HOME=str(root/'state'),XDG_CACHE_HOME=str(root/'cache'))
        with (root/'runtime.log').open('w') as log:
            process=subprocess.Popen(['qs','-p',str(root),'--no-color'],env=env,stdout=log,stderr=log)
            try:
                deadline=time.monotonic()+6
                while True:
                    try:
                        data=json.loads(subprocess.check_output(['qs','ipc','--pid',str(process.pid),'call',
                            'migrationProbe','snapshot'],env=env,stderr=subprocess.DEVNULL,text=True,timeout=2))
                        if data['ready']: break
                    except (subprocess.CalledProcessError,json.JSONDecodeError): pass
                    assert time.monotonic()<deadline,(root/'runtime.log').read_text()
                    time.sleep(.02)
                assert data['firstReadyMigrated'],data
                assert data['family']==('waffle' if family=='waffle' else 'abyss'),data
                assert data['version']==1 and data['iconSize']==43,data
                assert 'abyssBar' in data['enabled'] and 'abyssDock' not in data['enabled'],data
                assert 'abyssDock' in data['known'] and 'wBar' in data['enabled'] and 'iiCheatsheet' in data['enabled'],data
                while json.loads(config.read_text()).get('panelStyleVersion')!=1:
                    assert time.monotonic()<deadline,'migration was not persisted'
                    time.sleep(.02)
                saved=json.loads(config.read_text())
                assert saved['customExample']==old['customExample'] and saved['dock']['iconSize']==43,saved
                config.write_text(json.dumps(saved))
                time.sleep(.15)
                assert json.loads(config.read_text())==saved,'reloading must not change migrated preferences'
            finally:
                process.terminate()
                try: process.wait(timeout=3)
                except subprocess.TimeoutExpired: process.kill();process.wait()
print('PASS: adapter migrates before ready, preserves disabled panels/Waffle/custom fields and reloads idempotently')
PY
