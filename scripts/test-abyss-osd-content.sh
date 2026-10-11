#!/usr/bin/env bash
# Render every mature OSD indicator inside the same output content adapter.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss OSD content (Quickshell/Wayland unavailable)\n'; exit 0
fi
osd_test_root="$(mktemp -d)"
trap 'rm -rf -- "$osd_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$osd_test_root/$entry"
done
mkdir -p "$osd_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$osd_test_root/config/illogical-impulse/config.json"
cat > "$osd_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.content
ShellRoot {
    id: root
    property int step: 0
    property var kinds: ["volume","brightness","mic","media","mediaOsd","keyboardLayout","voiceSearch"]
    function check(ok,message): bool {
        if(ok) return true
        console.error("ABYSS_OSD_FAIL",message);Qt.quit();return false
    }
    FloatingWindow {
        color: "#111820"
        id: window
        visible:true;implicitWidth:700;implicitHeight:300
        AbyssOsdContent { id: content;anchors.centerIn:parent;width:desiredWidth;height:desiredHeight }
    }
    Timer {
        interval:400;running:true;repeat:true
        onTriggered: {
            if(root.step===0) Config.setNestedValue("panelFamily","abyss")
            else {
                if(!root.check(content.feature?.connectedSurface,"mature indicator outer chrome is suppressed")) return
                if(!root.check(content.feature.QsWindow.window===window,"output window owns indicator input")) return
                if(content.indicatorKind==="mediaOsd" && !root.check(String(content.primaryIndicator?.source ?? "").endsWith("/MediaIndicator.qml"),"Media IPC preview must instantiate the media indicator, not volume")) return
                if(!root.check(content.desiredWidth>=Appearance.sizes.osdWidth && content.desiredHeight>=40,"mature usable indicator dimensions: "+content.indicatorKind+" "+content.desiredWidth+"×"+content.desiredHeight)) return
                if(root.step===1) {
                    if(!root.check(content.desiredWidth===Appearance.sizes.osdWidth,"original volume width")) return
                    if(!root.check(content.feature.icon===(Audio.sink?.audio.muted ? "volume_off" : "volume_up"),"real volume icon and mute state")) return
                    if(!root.check(content.desiredHeight===content.feature.implicitHeight,"no artificial empty space in compact volume OSD")) return
                }
            }
            root.step++
            if(root.step>root.kinds.length) { console.info("ABYSS_OSD_PASS");Qt.quit();return }
            content.kind=root.kinds[root.step-1]
        }
    }
}
QML
if ! dbus-run-session -- env -u QS_CONFIG_NAME -u QS_CONFIG_PATH -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$osd_test_root/config" XDG_STATE_HOME="$osd_test_root/state" XDG_CACHE_HOME="$osd_test_root/cache" \
    timeout 9s qs -p "$osd_test_root" --no-color > "$osd_test_root/runtime.log" 2>&1; then
    cat "$osd_test_root/runtime.log";exit 1
fi
if ! rg -q ABYSS_OSD_PASS "$osd_test_root/runtime.log" || rg -q 'ABYSS_OSD_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type|Type .* unavailable' "$osd_test_root/runtime.log"; then
    cat "$osd_test_root/runtime.log";exit 1
fi
printf 'PASS: mature Volume, Brightness, Mic, Media + Media IPC, Keyboard and Voice OSDs share the output content adapter\n'
