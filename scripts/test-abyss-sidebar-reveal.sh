#!/usr/bin/env bash
# Execute the real hover lease across handoff, explicit opens and teardown gates.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null; then printf 'SKIP: sidebar reveal (Quickshell unavailable)\n'; exit 0; fi
sidebar_test_root="$(mktemp -d)"
trap 'rm -rf -- "$sidebar_test_root"' EXIT
cp "$repo_root/modules/abyss/AbyssSidebarReveal.qml" "$sidebar_test_root/Reveal.qml"
cat > "$sidebar_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-abyss-sidebar-reveal-test
import QtQuick
import Quickshell
ShellRoot {
    id: root
    property int step: 0
    property int opens: 0
    property int closes: 0
    function check(value,message): bool {
        if(value) return true
        console.error("SIDEBAR_REVEAL_FAIL",message);Qt.quit();return false
    }
    Reveal {
        id: reveal
        revealDelay: 5;closeDelay: 10
        onRevealRequested: { root.opens++;open=true }
        onHideRequested: { root.closes++;open=false }
    }
    Timer {
        interval: 30;running: true;repeat: true
        onTriggered: {
            if(root.step===0) reveal.edgeHovered=true
            if(root.step===1) {
                if(!root.check(reveal.open && root.opens===1,"hover opens once")) return
                reveal.bodyHovered=true;reveal.edgeHovered=false
            }
            if(root.step===2) {
                if(!root.check(reveal.open && root.closes===0,"edge-to-body handoff stays open")) return
                reveal.closeBlocked=true;reveal.bodyHovered=false
            }
            if(root.step===3) {
                if(!root.check(reveal.open,"context menu keeps hover lease")) return
                reveal.closeBlocked=false
            }
            if(root.step===4) {
                if(!root.check(!reveal.open && root.closes===1,"pointer exit closes transient sidebar")) return
                reveal.open=true;reveal.bodyHovered=true
            }
            if(root.step===5) reveal.bodyHovered=false
            if(root.step===6) {
                if(!root.check(reveal.open && root.closes===1,"explicit IPC open remains open after exit")) return
                reveal.open=false;reveal.openingAllowed=false;reveal.edgeHovered=true
            }
            if(root.step===7) {
                if(!root.check(!reveal.open && root.opens===1,"modal gate blocks opening")) return
                reveal.openingAllowed=true
            }
            if(root.step===8) {
                if(!root.check(reveal.open && root.opens===2,"hover opens after modal clears")) return
                reveal.available=false
            }
            if(root.step===9) {
                if(!root.check(!reveal.open && root.closes===2 && !reveal.ownedOpen,"hidden output or editor releases hover state")) return
                console.info("SIDEBAR_REVEAL_PASS");Qt.quit()
            }
            root.step++
        }
    }
}
QML
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen \
    timeout 5s qs -p "$sidebar_test_root" --no-color > "$sidebar_test_root/runtime.log" 2>&1 || { cat "$sidebar_test_root/runtime.log";exit 1; }
if ! rg -q 'SIDEBAR_REVEAL_PASS' "$sidebar_test_root/runtime.log" || rg -q 'SIDEBAR_REVEAL_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign' "$sidebar_test_root/runtime.log"; then cat "$sidebar_test_root/runtime.log";exit 1; fi
printf 'PASS: sidebar hover lease handles content handoff, menus, explicit IPC and presentation gates\n'
