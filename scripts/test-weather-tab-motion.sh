#!/usr/bin/env bash
# Actual Qt layout/reveal regression: height changes must not animate tab choice.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || ! command -v niri >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]];then printf 'SKIP: Weather tab motion requires Quickshell/Wayland\n';exit 0;fi
weather_tab_test="$(mktemp -d)"
trap 'rm -rf -- "$weather_tab_test"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations;do ln -s "$repo_root/$entry" "$weather_tab_test/$entry";done
mkdir -p "$weather_tab_test/config/illogical-impulse"
python3 - "$repo_root/defaults/config.json" "$weather_tab_test/config/illogical-impulse/config.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]));data['panelFamily']='abyss';data['bar']['weather']['enable']=False
json.dump(data,open(sys.argv[2],'w'))
PY
cat > "$weather_tab_test/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.bar.weather
ShellRoot {
 id: root
 property bool finished:false
 property int frame:0
 property int inBetween:0
 property real bodyHeight:0
 property int settledFrame:0
 function check(ok,message):bool {
  if(ok)return true
  console.error("WEATHER_TABS_FAIL",message,JSON.stringify({
   frame:root.frame,verticalLayout:weather.verticalLayout,
   width:weather.width,height:weather.height,viewportWidth:weather.children[0]?.width,viewportHeight:weather.children[0]?.height,
   orbit:weather.children[0]?.children[0] ? {x:weather.children[0].children[0].x,y:weather.children[0].children[0].y,w:weather.children[0].children[0].width,h:weather.children[0].children[0].height} : null,
   detail:weather.children[0]?.children[2] ? {x:weather.children[0].children[2].x,y:weather.children[0].children[2].y,w:weather.children[0].children[2].width,h:weather.children[0].children[2].height} : null
  }));root.finished=true;return false
 }
 FloatingWindow {
     color: "#111820"
  visible:true;implicitWidth:900;implicitHeight:700
  WeatherPopupContent { id:weather;width:implicitWidth;height:implicitHeight }
 }
 Timer {
  interval:16;running:!root.finished;repeat:true
  onTriggered:{
   if(!Config.ready)return
   const vp=weather.children[0], orbit=vp.children[0], divider=vp.children[1], detail=vp.children[2]
   if(root.frame===0){
    Config.setNestedValue("performance.reduceAnimations",false)
    weather.verticalLayout=false
   }
   if(root.frame===4){
    if(!root.check(orbit.x===0 && orbit.y===0 && detail.x>=orbit.width+10 && divider.width===1,"horizontal mode must place Orbital left and Detailed right"))return
    if(!root.check(Math.abs(orbit.y-detail.y)<0.5 && weather.implicitWidth>700,"horizontal panels misaligned or narrow"))return
    weather.verticalLayout=true
   }
   if(root.frame===8){
    if(!root.check(orbit.x===0 && orbit.y===0 && detail.x===0 && detail.y>=orbit.height+10 && divider.height===1,"vertical mode must place Orbital top and Detailed bottom"))return
    if(!root.check(weather.implicitWidth<420 && weather.implicitHeight>orbit.height+detail.height,"vertical dimensions incorrect"))return
    console.info("WEATHER_TABS_PASS");root.finished=true
   }
   root.frame++
  }
 }
}
QML
status=0
# Use the existing private Niri/session helper: never host this FloatingWindow
# in the owner's compositor or reuse owner service/config/data paths.
python3 - "$repo_root" "$weather_tab_test" > "$weather_tab_test/runtime.log" 2>&1 <<'PYTHON' || status=$?
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/"scripts"))
from native_test_session import private_wayland,run_qs
folder=Path(sys.argv[2])
with private_wayland(folder) as env:
    if env is None:
        raise SystemExit("Private Niri unavailable")
    result=run_qs(folder,env,timeout=20)
    print(result.stdout,end="")
    raise SystemExit(result.returncode)
PYTHON
if [[ "$status" != 124 ]] || ! rg -q WEATHER_TABS_PASS "$weather_tab_test/runtime.log" || rg -q 'WEATHER_TABS_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$weather_tab_test/runtime.log";then cat "$weather_tab_test/runtime.log";exit 1;fi
printf 'PASS: Weather initial reveal, synchronized tab slide, resize, rehost/reopen and reduced motion\n'
