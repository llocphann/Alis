#!/usr/bin/env bash
# Execute the production clipboard loaders through outgoing Waffle state.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null; then
    printf 'SKIP: Waffle clipboard lifecycle (Quickshell unavailable)\n'
    exit 0
fi
python3 - "$repo_root" <<'PY'
import json, os, pathlib, re, subprocess, sys, tempfile, time
source = (pathlib.Path(sys.argv[1]) / 'modules/waffle/ShellWafflePanelsImpl.qml').read_text()
def block(start):
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
loaders = [block(source.rfind('    LazyLoader {', 0, source.index('id: waffleClipboardLoader')))]
for match in re.finditer(r'    (?:Deferred|OnDemand)PanelLoader \{[^\n]*ClipboardModule\.ClipboardPanel', source):
    loaders.append(block(match.start()))
deferred = block(source.index('    component DeferredPanelLoader:'))
with tempfile.TemporaryDirectory(prefix='hadalis-waffle-clipboard-') as tmp:
    root = pathlib.Path(tmp)
    (root / 'qmldir').write_text('singleton Config 1.0 Config.qml\nsingleton GlobalStates 1.0 GlobalStates.qml\n')
    (root / 'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property var creations: []
    property QtObject options: QtObject {
        property string panelFamily: "waffle"
        property list<string> enabledPanels: ["iiClipboard"]
    }
    function created(name) { creations = [...creations,name] }
}
''')
    (root / 'GlobalStates.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property bool shellEntryReady: true; property bool deferredPanelsReady: true }
''')
    for dirname, typename, name in [('waffle','WaffleClipboard','waffle'),('material','ClipboardPanel','material')]:
        folder = root / dirname
        folder.mkdir()
        (folder / 'qmldir').write_text(f'{typename} 1.0 {typename}.qml\n')
        (folder / f'{typename}.qml').write_text('import QtQuick\nimport ".."\nItem { Component.onCompleted: Config.created("'+name+'") }\n')
    (root / 'shell.qml').write_text('''//@ pragma ShellId hadalis-waffle-clipboard-test
import QtQuick
import Quickshell
import Quickshell.Io
import "waffle" as WaffleClipboardModule
import "material" as ClipboardModule
ShellRoot {
    id: root
''' + deferred + '\n'.join(loaders) + '''
    IpcHandler {
        target: "clipboardLifecycle"
        function choose(family: string): void { Config.options.panelFamily = family }
        function state(): string { return JSON.stringify({loaded:!!waffleClipboardLoader.item,creations:Config.creations}) }
    }
}
''')
    env = os.environ.copy()
    for key in ('QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST'):
        env.pop(key,None)
    env['QT_QPA_PLATFORM'] = 'offscreen'
    env['LC_ALL'] = 'C.UTF-8'
    with (root / 'runtime.log').open('w') as log:
        proc = subprocess.Popen(['qs','-p',str(root),'--no-color'],env=env,stdout=log,stderr=subprocess.STDOUT)
        def ipc(method,*args):
            return subprocess.check_output(['qs','ipc','--pid',str(proc.pid),'call','clipboardLifecycle',method,*args],env=env,text=True,stderr=subprocess.DEVNULL,timeout=3).strip()
        def state_when(loaded):
            deadline = time.monotonic()+4
            while time.monotonic()<deadline:
                try:
                    state = json.loads(ipc('state'))
                    if state['loaded'] == loaded:
                        return state
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    pass
                time.sleep(.02)
            raise AssertionError('clipboard loader did not settle')
        try:
            state_when(True)
            for index in range(4):
                ipc('choose','abyss')
                state_when(False)
                # An outgoing host may still process bindings before disposal.
                time.sleep(.1)
                state = json.loads(ipc('state'))
                assert state['creations'] == ['waffle']*(index+1), state
                ipc('choose','waffle')
                state_when(True)
            diagnostics = (root/'runtime.log').read_text()
            assert not re.search(r'ReferenceError:|TypeError:|Binding loop',diagnostics), diagnostics
            print('PASS: Waffle clipboard releases on exit without constructing a Material clipboard; four re-entries load the native owner')
        except BaseException:
            print((root/'runtime.log').read_text(),file=sys.stderr)
            raise
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill();proc.wait()
PY
