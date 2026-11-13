#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${ALIS_SILENT_WL_WRAPPED:-0}" != "1" ]]; then
    export ALIS_SILENT_WL_WRAPPED=1
    exec bash "$repo_root/scripts/lib/silent-wayland-run.sh" -- "$0" "$@"
fi
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]];then printf 'SKIP: Abyss choices (Quickshell/Wayland unavailable)\n';exit 0;fi
choice_test_root="$(mktemp -d)"
trap 'rm -rf -- "$choice_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations;do ln -s "$repo_root/$entry" "$choice_test_root/$entry";done
mkdir -p "$choice_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$choice_test_root/config/illogical-impulse/config.json"
cat > "$choice_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
    id:root;property int step:0;property bool finished:false
    function check(ok,message): bool { if(ok)return true;console.error("CHOICE_FAIL",message);finished=true;return false }
    FloatingWindow {
        color: "#111820"
        visible:true;implicitWidth:400;implicitHeight:160
        SelectionGroupButton { id:choice;width:160;height:40;buttonText:"Deep";toggled:true }
        RippleButton { id:tab;x:180;width:160;height:40;buttonText:"Settings" }
    }
    Timer {
        interval:120;running:!root.finished;repeat:true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("abyss.waves.enabled",true)
                Config.setNestedValue("abyss.waves.preset","deep")
                Config.setNestedValue("abyss.waves.strength",1)
                Config.setNestedValue("performance.reduceAnimations",false)
            } else if(root.step===1) {
                if(!root.check(choice.waveFaceItem!==null && tab.background.border.width===0,"secondary choices have wave faces and main tabs have no idle border")) return
                choice.down=true
                if(!root.check(choice.waveFaceItem.pulseRunning,"press starts one local pulse")) return
            } else if(root.step===2) {
                if(!root.check(choice.waveFaceItem.phase>0 && choice.waveFaceItem.phase<1,"wave advances during press")) return
                choice.down=false
            } else if(root.step===6) {
                if(!root.check(!choice.waveFaceItem.pulseRunning && choice.waveFaceItem.phase===1,"pulse settles and sleeps")) return
                Config.setNestedValue("performance.reduceAnimations",true)
                choice.down=true
                if(!root.check(!choice.waveFaceItem.pulseRunning,"reduced motion is instant")) return
                choice.down=false
                Config.setNestedValue("performance.reduceAnimations",false)
                Config.setNestedValue("abyss.waves.enabled",false)
                choice.down=true
                if(!root.check(!choice.waveFaceItem.pulseRunning && choice.waveFaceItem.lift(.34)===0,"disabled waves have a flat resting face")) return
                choice.down=false
                Config.setNestedValue("panelFamily","waffle")
            } else if(root.step===8) {
                if(!root.check(!choice.waveFace && choice.waveFaceItem===null,"Waffle retains its existing choice renderer")) return
                console.info("CHOICE_PASS");root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland XDG_CONFIG_HOME="$choice_test_root/config" XDG_STATE_HOME="$choice_test_root/state" XDG_CACHE_HOME="$choice_test_root/cache" timeout 15s qs -p "$choice_test_root" --no-color > "$choice_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q CHOICE_PASS "$choice_test_root/runtime.log" || rg -q 'CHOICE_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$choice_test_root/runtime.log";then cat "$choice_test_root/runtime.log";exit 1;fi
printf 'PASS: choice wave press/settle, reduced motion, disabled waves, borderless tabs and Waffle isolation\n'
