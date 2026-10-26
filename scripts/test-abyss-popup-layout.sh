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
//@ pragma ShellId alis-abyss-popup-layout-test
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.abyss.content
import qs.services
ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    function check(value,message): bool {
        if (value) return true
        console.error("ABYSS_POPUP_LAYOUT_FAIL",message);root.finished=true;return false
    }
    function findOrbit(item) {
        if(typeof item?.angle==="function" && item?.selectedHour!==undefined) return item
        for(const child of Array.from(item?.children ?? [])) {
            const orbit=root.findOrbit(child)
            if(orbit) return orbit
        }
        return null
    }
    FloatingWindow {
        color: "#111820"
        visible: true; implicitWidth: 1200; implicitHeight: 900
        AbyssPopupContent { id: popup; width:desiredWidth; height:desiredHeight }
    }
    Timer {
        interval: 350; running: !root.finished; repeat: true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) { Config.setNestedValue("panelFamily","abyss");popup.kind="clock" }
            else if(root.step===1 || root.step===6) {
                const calendar=popup.feature.contentItem.children.find(c=>c.calendarCells!==undefined)
                if(!root.check(calendar && calendar.calendarCells.length===42,"mature calendar keeps six weeks")) return
                if(!root.check(popup.desiredWidth>=600 && calendar.width===popup.width && calendar.height<=popup.height,"Events and Calendar retain full shared layout")) return
                if(root.step===6) { console.info("ABYSS_POPUP_LAYOUT_PASS");root.finished=true;return }
                popup.kind="resources"
            } else if(root.step===2) {
                if(!root.check(popup.feature.presentationActive && !popup.feature.active && popup.feature.thinkFanCanApply!==undefined,"shared resources/fan controls active without another popup host")) return
                popup.kind="battery"
            } else if(root.step===3) {
                if(!root.check(popup.desiredWidth>100 && popup.desiredHeight>50 && !popup.feature.active,"mature battery content-sized layout")) return
                Weather.data={temp:"31°",description:"Cloudy",wCode:"119",hourly:Array.from({length:8},(_,i)=>({label:String(i*3).padStart(2,"0")+":00",temp:String(23+i)+"°",code:"119",isNight:i<2}))}
                popup.kind="weather"
            } else if(root.step===4) {
                if(!root.check(popup.desiredWidth===390 && popup.desiredHeight===300,"shared two-tab weather dimensions")) return
                const orbit=root.findOrbit(popup.feature)
                if(!root.check(orbit && orbit.hours.length===8,"Abyss loads its forecast orbit using shared Weather data")) return
                const nodes=Array.from(orbit.children).filter(c=>c.orbitAngle!==undefined)
                if(!root.check(nodes.length===8 && nodes.every(n=>n.x>=0 && n.y>=0 && n.x+n.width<=orbit.width && n.y+n.height<=orbit.height),"all hourly controls fit inside the popup")) return
                orbit.activeIndex=4
                if(!root.check(orbit.selectedHour.temp==="27°","selected forecast updates the central summary")) return
                popup.kind="media"
            } else if(root.step===5) {
                if(!root.check(popup.feature.tabCount!==undefined && popup.desiredHeight>0,"shared player tabs and Equalizer")) return
                Config.setNestedValue("appearance.typography.sizeScale",1.5)
                popup.kind="clock"
            }
            root.step++
        }
    }
}
QML
status=0
QT_QPA_PLATFORM=wayland XDG_CONFIG_HOME="$popup_test_root/config" XDG_STATE_HOME="$popup_test_root/state" XDG_CACHE_HOME="$popup_test_root/cache" timeout 20s qs -p "$popup_test_root" --no-color > "$popup_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q 'ABYSS_POPUP_LAYOUT_PASS' "$popup_test_root/runtime.log" || rg -q 'ABYSS_POPUP_LAYOUT_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$popup_test_root/runtime.log"; then
    cat "$popup_test_root/runtime.log"
    exit 1
fi
printf 'PASS: mature popup content/layout retained across Calendar, Resources, Battery, Weather and Media\n'
