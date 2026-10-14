#!/usr/bin/env bash
# Exercise real Qt rendering, including QSB cache reuse and fail-closed backends.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss shader lifecycle (Quickshell/display unavailable)\n'
    exit 0
fi
python3 - "$repo_root" <<'PY'
import json, os, pathlib, re, subprocess, sys, tempfile
repo = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hadalis-abyss-shader-') as tmp:
    root = pathlib.Path(tmp)
    for entry in ('modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'scripts', 'defaults', 'translations'):
        (root / entry).symlink_to(repo / entry)
    config = root / 'config/illogical-impulse'
    config.mkdir(parents=True)
    options = json.loads((repo / 'defaults/config.json').read_text())
    options['abyss']['quality'] = 'performance'
    (config / 'config.json').write_text(json.dumps(options))
    broken = (repo / 'modules/abyss/looks/AbyssField.qml').read_text()
    broken = broken.replace('import qs.modules.common', 'import qs.modules.abyss.looks\nimport qs.modules.common')
    broken = broken.replace('Qt.resolvedUrl("AbyssField.frag.qsb")', 'Qt.resolvedUrl("broken.qsb")')
    (root / 'AbyssGeometry.js').symlink_to(repo / 'modules/abyss/looks/AbyssGeometry.js')
    (root / 'BrokenField.qml').write_text(broken)
    (root / 'AbyssField.vert.qsb').symlink_to(repo / 'modules/abyss/looks/AbyssField.vert.qsb')
    (root / 'broken.qsb').write_bytes(b'not a Qt shader package')
    (root / 'shell.qml').write_text('''//@ pragma ShellId hadalis-abyss-shader-test
import QtQuick
import Quickshell
import qs.modules.common
ShellRoot {
    id: root
    readonly property string mode: Quickshell.env("ABYSS_SHADER_TEST_MODE")
    readonly property string fieldSource: mode === "broken" ? "BrokenField.qml" : "modules/abyss/looks/AbyssField.qml"
    property int count: 0
    property int ticks: 0
    FloatingWindow {
        visible: true; implicitWidth: 420; implicitHeight: 260; color: "#202a32"
        Loader { id: field; anchors.fill: parent; source: root.fieldSource }
    }
    Timer {
        running: true; repeat: true; interval: 100
        onTriggered: {
            root.ticks++
            if (field.status === Loader.Error) { console.error("SHADER_TEST_FAIL loader"); Qt.quit(); return }
            if (root.mode !== "valid") {
                if (field.item?.ready) { console.error("SHADER_TEST_FAIL unsafe input gate",root.mode); Qt.quit(); return }
                if (root.ticks >= 10 && field.item?.framePresented) { console.info("SHADER_TEST_PASS",root.mode); Qt.quit() }
            } else if (field.item?.ready) {
                root.count++; root.ticks=0; field.source=""
                if (root.count===5) { console.info("SHADER_TEST_PASS valid five cold/cached creations"); Qt.quit() }
            } else if (!field.item) field.source=root.fieldSource
            if (root.ticks > 40) { console.error("SHADER_TEST_FAIL render timeout",root.mode,root.count); Qt.quit() }
        }
    }
}
''')
    for mode in ('valid', 'broken', 'software'):
        env = os.environ.copy()
        for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME', 'QS_MANIFEST'):
            env.pop(key, None)
        env.update(QT_QPA_PLATFORM='offscreen', QSG_RHI_BACKEND='opengl',
                   QT_QUICK_BACKEND='software' if mode == 'software' else 'rhi',
                   XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                   XDG_CACHE_HOME=str(root / 'cache'), ABYSS_SHADER_TEST_MODE=mode)
        result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8)
        assert result.returncode == 0 and 'SHADER_TEST_PASS' in result.stdout, result.stdout
        assert not re.search(r'SHADER_TEST_FAIL|ReferenceError:|TypeError:|Binding loop', result.stdout), result.stdout
        if mode == 'valid':
            assert 'shader preparation failed' not in result.stdout, result.stdout
        if mode == 'broken':
            assert 'shader preparation failed' in result.stdout, result.stdout
        print('PASS: Abyss shader lifecycle', mode)
PY
