#!/usr/bin/env bash
# Execute production family loaders against shared IPC owners, without desktop services.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null; then
    printf 'SKIP: family mount lifecycle (Quickshell unavailable)\n'
    exit 0
fi
python3 - "$repo_root" <<'PY'
import json, os, pathlib, re, subprocess, sys, tempfile, time
repo = pathlib.Path(sys.argv[1])
source = (repo / 'shell.qml').read_text()
loaders = source[source.index('    LazyLoader {\n        id: iiCriticalHostLoader'):source.index('    // Close confirmation dialog')]
mount = source[source.index('    readonly property string activePanelFamily:'):source.index('    // Direct config edits')]
with tempfile.TemporaryDirectory(prefix='alis-family-mount-') as tmp:
    root = pathlib.Path(tmp)
    for entry in ('modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'scripts', 'defaults', 'translations'):
        (root / entry).symlink_to(repo / entry)
    config = root / 'config/illogical-impulse'
    config.mkdir(parents=True)
    (config / 'config.json').write_text((repo / 'defaults/config.json').read_text())
    for name in ('ii', 'waffle', 'abyss'):
        (root / f'{name}.qml').write_text('''import Quickshell
import Quickshell.Io
Scope {
    IpcHandler {
        target: "sharedFamilyOwner"
        function identity(): string { return "''' + name + '''" }
    }
}
''')
    (root / 'Deferred.qml').write_text('import QtQuick\nItem {}\n')
    replacements = {
        'modules/ii/critical/ShellIiCriticalPanels.qml': 'ii.qml',
        'modules/waffle/critical/ShellWaffleCriticalPanels.qml': 'waffle.qml',
        'modules/abyss/critical/ShellAbyssCriticalPanels.qml': 'abyss.qml',
        'ShellIiPanels.qml': 'Deferred.qml', 'ShellWafflePanels.qml': 'Deferred.qml',
        'ShellAbyssPanels.qml': 'Deferred.qml'
    }
    for old, new in replacements.items():
        loaders = loaders.replace('source: "' + old + '"', 'source: "' + new + '"')
    (root / 'shell.qml').write_text('''//@ pragma ShellId alis-family-mount-test
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import "modules/common/PanelFamilyPolicy.js" as FamilyPolicy
ShellRoot {
    id: root
''' + mount + loaders + '''
    IpcHandler {
        target: "mountProbe"
        function choose(family: string): void {
            GlobalStates.deferredPanelsReady = true
            Config.setNestedValue("panelFamily",family)
        }
        function state(): string {
            return JSON.stringify({family:root.activePanelFamily,
                critical:[iiCriticalHostLoader.active,waffleCriticalHostLoader.active,abyssCriticalHostLoader.active],
                loaded:[!!iiCriticalHostLoader.item,!!waffleCriticalHostLoader.item,!!abyssCriticalHostLoader.item],
                deferred:[!!iiDeferredHostLoader.item,!!waffleDeferredHostLoader.item,!!abyssDeferredHostLoader.item]})
        }
    }
}
''')
    env = os.environ.copy()
    for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME', 'QS_MANIFEST'):
        env.pop(key, None)
    env.update(QT_QPA_PLATFORM='offscreen', LC_ALL='C.UTF-8', XDG_CONFIG_HOME=str(root / 'config'),
               XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'), ALIS_DISABLE_HOT_RELOAD='1')
    with (root / 'runtime.log').open('w') as log:
        proc = subprocess.Popen(['qs', '-p', str(root), '--no-color'], env=env, stdout=log, stderr=subprocess.STDOUT)
        def ipc(target, method, *args):
            return subprocess.check_output(['qs', 'ipc', '--pid', str(proc.pid), 'call', target, method, *args], env=env, stderr=subprocess.DEVNULL, text=True, timeout=3).strip()
        try:
            for index, name in enumerate(['ii'] + ['abyss', 'waffle', 'abyss', 'ii'] * 20):
                deadline = time.monotonic() + 5
                while True:
                    try:
                        ipc('mountProbe', 'choose', name)
                        break
                    except subprocess.CalledProcessError:
                        assert time.monotonic() < deadline, 'shell did not expose its probe'
                        time.sleep(.02)
                effective = 'abyss' if name == 'ii' else name
                expected = [family == effective for family in ('ii', 'waffle', 'abyss')]
                while True:
                    state = json.loads(ipc('mountProbe', 'state'))
                    if all(state[k] == expected for k in ('critical', 'loaded', 'deferred')):
                        break
                    assert time.monotonic() < deadline, state
                    time.sleep(.01)
                assert ipc('sharedFamilyOwner', 'identity') == effective, (index, name, state)
            diagnostics = (root / 'runtime.log').read_text()
            assert not re.search(r'Handler was registered but will not be used|ReferenceError:|TypeError:|Binding loop', diagnostics), diagnostics
            print('PASS: production loaders release shared IPC before 80 family changes; one critical/deferred tree and correct live owner')
        except BaseException:
            print((root / 'runtime.log').read_text(), file=sys.stderr)
            raise
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
PY
