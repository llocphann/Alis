#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${ALIS_SILENT_WL_WRAPPED:-0}" != "1" ]]; then
    export ALIS_SILENT_WL_WRAPPED=1
    exec bash "$repo_root/scripts/lib/silent-wayland-run.sh" -- "$0" "$@"
fi
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]];then printf 'SKIP: Dock reveal (Quickshell/Wayland unavailable)\n';exit 0;fi
reveal_test_root="$(mktemp -d)"
trap 'rm -rf -- "$reveal_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations;do ln -s "$repo_root/$entry" "$reveal_test_root/$entry";done
mkdir -p "$reveal_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$reveal_test_root/config/illogical-impulse/config.json"
cat > "$reveal_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
    id:root;property int step:0;property bool finished:false;property var original:null
    property int calls:0;property real lastStrength:0
    AbyssSurfaceController {
        id:controller;outputWidth:viewport.width;outputHeight:viewport.height
        function impulse(edge,along,span,strength,mass,kind) { root.calls++;root.lastStrength=strength }
    }
    function check(ok,message): bool { if(ok)return true;console.error("DOCK_REVEAL_FAIL",message);finished=true;return false }
    FloatingWindow {
        color: "#111820"
        visible:true;implicitWidth:1100;implicitHeight:800
        Item {
        id:viewport;width:1100;height:800
        AbyssBodyHost {
            id:body;anchors.fill:parent;edge:"bottom";identity:"dock";open:true
            controller:controller;stableContentSize:true;animatePresentation:false;span:600;depth:74;padding:12
            edgeInsets:controller.edgeInsets
            source:Qt.resolvedUrl("modules/abyss/content/AbyssDockContent.qml")
        }
        }
    }
    Timer {
        interval:160;running:!root.finished;repeat:true
        onTriggered: {
            if(root.step===0) {
                GlobalStates.deferredPanelsReady=true
                Config.setNestedValue("panelFamily","abyss")
            } else if(root.step===2) {
                root.original=body.contentItem.item
                if(!root.check(root.original!==null,"mature Dock loaded")) return
            } else if(root.step>=3 && root.step<=7) {
                body.progress=[.1,.4,1,.7,.15][root.step-3]
                if(!root.check(body.contentItem.item===root.original && body.contentItem.height===body.targetRecord.content.height && body.contentItem.width===body.targetRecord.content.width,"opening/closing/reversal keeps content size and identity")) return
                if(!root.check(body.inputBounds.height===body.record.content.height && body.contentParent.parent.clip,"input and paint remain inside the animated reveal")) return
            } else if(root.step===8) {
                body.edge="right";body.progress=.2
                if(!root.check(body.contentItem.width===body.targetRecord.content.width && body.contentItem.item===root.original,"vertical Dock keeps stable dimensions too")) return
                Config.setNestedValue("abyss.waves.strength",2)
                Config.setNestedValue("abyss.waves.dock",.1)
                body.contentItem.item.react(Qt.point(10,10),.5)
                if(!root.check(root.lastStrength===1,"Dock interactions use the common wave strength")) return
                body.open=false
                if(!root.check(body.inputBounds.width===0 && !body.contentItem.enabled,"semantic close releases input immediately")) return
                body.progress=0
            } else if(root.step===10) {
                if(!root.check(!body.ready,"closed Dock releases content resources")) return
                console.info("DOCK_REVEAL_PASS");root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland XDG_CONFIG_HOME="$reveal_test_root/config" XDG_STATE_HOME="$reveal_test_root/state" XDG_CACHE_HOME="$reveal_test_root/cache" timeout 12s qs -p "$reveal_test_root" --no-color > "$reveal_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q DOCK_REVEAL_PASS "$reveal_test_root/runtime.log" || rg -q 'DOCK_REVEAL_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$reveal_test_root/runtime.log";then cat "$reveal_test_root/runtime.log";exit 1;fi
printf 'PASS: Dock size is stable across reveal/reversal and edges, clipped input follows the field, shared waves apply and closed content unloads\n'
