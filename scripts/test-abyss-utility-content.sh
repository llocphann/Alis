#!/usr/bin/env bash
# Lay out the real popup in a rendered Qt window through content-kind changes.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss popup layout (Quickshell unavailable)\n'
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
//@ pragma ShellId alis-abyss-utility-content-test
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.content
ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    function check(value,message): bool {
        if(value) return true
        console.error("ABYSS_UTILITY_FAIL",message);root.finished=true;return false
    }
    FloatingWindow {
        color: "#111820"
        id: window
        visible:true;implicitWidth:1200;implicitHeight:900
        AbyssUtilityContent { id: content;anchors.fill:parent }
    }
    Timer {
        interval:400;running:!root.finished;repeat:true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) { Config.setNestedValue("panelFamily","abyss");GlobalStates.sessionOpen=true }
            else if(root.step===1 || root.step===2 || root.step===3) {
                if(!root.check(content.feature.presentationContent.parent===content,"mature content is hosted by the shared field adapter")) return
                if(!root.check(content.feature.presentationContent.QsWindow.window===window,"actual output window owns feature input")) return
                if(!root.check(content.desiredWidth>=500 && content.desiredHeight>200,"content has usable mature dimensions")) return
                if(root.step===1) { GlobalStates.sessionOpen=false;GlobalStates.cheatsheetOpen=true;content.kind="cheatsheet" }
                else if(root.step===2) { GlobalStates.cheatsheetOpen=false;ShellUpdates.overlayOpen=true;content.kind="update" }
                else { ShellUpdates.overlayOpen=false;console.info("ABYSS_UTILITY_PASS");root.finished=true;return }
            }
            root.step++
        }
    }
}
QML
status=0
dbus-run-session -- env -u QS_CONFIG_NAME -u QS_CONFIG_PATH -u QS_MANIFEST QT_QPA_PLATFORM=wayland XDG_CONFIG_HOME="$popup_test_root/config" XDG_STATE_HOME="$popup_test_root/state" XDG_CACHE_HOME="$popup_test_root/cache" timeout 20s qs -p "$popup_test_root" --no-color > "$popup_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q 'ABYSS_UTILITY_PASS' "$popup_test_root/runtime.log" || rg -q 'ABYSS_UTILITY_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$popup_test_root/runtime.log"; then
    cat "$popup_test_root/runtime.log"
    exit 1
fi
printf 'PASS: mature Session, Cheatsheet and Shell Update share the actual output content host\n'
