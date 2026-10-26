#!/usr/bin/env bash
# Exercise the production normalization/pinning methods with actual Qt sequences.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null; then
    printf 'SKIP: taskbar Qt list runtime (Quickshell unavailable)\n'
    exit 0
fi
taskbar_test_root="$(mktemp -d)"
trap 'rm -rf -- "$taskbar_test_root"' EXIT
python3 - "$repo_root" "$taskbar_test_root" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1])/'services/TaskbarApps.qml').read_text()
methods = []
for name in ('_stringArray', 'togglePin'):
    start = source.index('    function '+name+'(')
    opening = source.index('{', start)
    depth, end = 1, opening+1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    methods.append(source[start:end])
(Path(sys.argv[2])/'Controller.qml').write_text('import QtQuick\nQtObject {\n id: root\n'+ '\n'.join(methods)+'\n}\n')
PY
cat > "$taskbar_test_root/qmldir" <<'QML'
singleton Config 1.0 Config.qml
QML
cat > "$taskbar_test_root/Config.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    property QtObject options: QtObject {
        property QtObject dock: QtObject {
            property list<string> pinnedApps: [" kitty ", "", "Dolphin"]
            property list<string> ignoredAppRegexes: ["^portal$", " scratchpad "]
        }
    }
    function setNestedValue(keys, value) { options.dock.pinnedApps = value }
}
QML
cat > "$taskbar_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-taskbar-list-test
import QtQuick
import Quickshell
ShellRoot {
    id: root
    Loader { id: controller; source: "Controller.qml" }
    function check(value, message): bool {
        if (value) return true
        console.error("TASKBAR_LIST_FAIL",message);Qt.quit();return false
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            const model = controller.item
            if (!root.check(!!model,"controller loads")) return
            if (!root.check(JSON.stringify(model._stringArray(Config.options.dock.pinnedApps)) === '["kitty","Dolphin"]',"Qt pins preserved and normalized")) return
            if (!root.check(JSON.stringify(model._stringArray(Config.options.dock.ignoredAppRegexes)) === '["^portal$","scratchpad"]',"Qt filters preserved")) return
            model.togglePin("KITTY")
            if (!root.check(JSON.stringify(Array.from(Config.options.dock.pinnedApps)) === '["Dolphin"]',"case-insensitive unpin retains other pins")) return
            model.togglePin("firefox")
            if (!root.check(JSON.stringify(Array.from(Config.options.dock.pinnedApps)) === '["Dolphin","firefox"]',"pin appends without losing existing pins")) return
            if (!root.check(model._stringArray(null).length === 0 && model._stringArray("kitty").length === 0,"reject non-sequence config")) return
            console.info("TASKBAR_LIST_PASS");Qt.quit()
        }
    }
}
QML
QT_QPA_PLATFORM=offscreen timeout 5s qs -p "$taskbar_test_root" --no-color > "$taskbar_test_root/runtime.log" 2>&1
if ! rg -q 'TASKBAR_LIST_PASS' "$taskbar_test_root/runtime.log" || rg -q 'TASKBAR_LIST_FAIL|ReferenceError:|TypeError:|Binding loop' "$taskbar_test_root/runtime.log"; then
    cat "$taskbar_test_root/runtime.log"
    exit 1
fi
printf 'PASS: actual Qt list pins/filter normalization and pin/unpin retain existing entries\n'
