#!/usr/bin/env bash
# Lay out the real popup in a rendered Qt window through content-kind changes.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss dock content (Quickshell unavailable)\n'
    exit 0
fi
popup_test_root="$(mktemp -d)"
trap 'rm -rf -- "$popup_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$popup_test_root/$entry"
done
mkdir -p "$popup_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$popup_test_root/config/illogical-impulse/config.json"
cat > "$popup_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-abyss-dock-content-test
import QtQuick
import Quickshell
import qs.modules.abyss.content
ShellRoot {
    id: root
    property int step: 0
    function check(value,message): bool {
        if (value) return true
        console.error("ABYSS_DOCK_CONTENT_FAIL",message);Qt.quit();return false
    }
    FloatingWindow {
        color: "#111820"
        visible: true; implicitWidth: 1000; implicitHeight: 700
        AbyssDockContent { id: dock; width: 800; height: 50 }
    }
    Timer {
        interval: 350; running: true; repeat: true
        onTriggered: {
            if(root.step===0) {
                if(!root.check(dock.appContent._sortingConsumerAcquired,"shared Dock sorting lease")) return
                if(!root.check(dock.desiredSpan>=74,"content-sized Dock and launcher")) return
                dock.edge="left";dock.width=50;dock.height=600
            } else {
                if(!root.check(dock.appContent.vertical && dock.appContent.dockPosition==="left" && dock.desiredSpan>=74,"same Dock supports cross-edge placement")) return
                console.info("ABYSS_DOCK_CONTENT_PASS");Qt.quit();return
            }
            root.step++
        }
    }
}
QML
if ! QT_QPA_PLATFORM=wayland XDG_CONFIG_HOME="$popup_test_root/config" XDG_STATE_HOME="$popup_test_root/state" XDG_CACHE_HOME="$popup_test_root/cache" timeout 8s qs -p "$popup_test_root" --no-color > "$popup_test_root/runtime.log" 2>&1; then
    cat "$popup_test_root/runtime.log"
    exit 1
fi
if ! rg -q 'ABYSS_DOCK_CONTENT_PASS' "$popup_test_root/runtime.log" || rg -q 'ABYSS_DOCK_CONTENT_FAIL|ReferenceError:|TypeError:|Binding loop' "$popup_test_root/runtime.log"; then
    cat "$popup_test_root/runtime.log"
    exit 1
fi
printf 'PASS: mature Dock sorting and cross-edge presentation\n'
