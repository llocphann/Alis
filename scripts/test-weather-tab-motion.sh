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
   frame:root.frame,currentTab:weather.currentTab,tabPosition:weather.tabPosition,
   height:weather.height,viewportHeight:weather.children[0]?.height,
   orbitY:weather.children[0]?.children[0]?.y,detailY:weather.children[0]?.children[1]?.y,
   animations:Appearance.animationsEnabled,slideDuration:weather.slideDuration
  }));root.finished=true;return false
 }
 FloatingWindow {
     color: "#111820"
  visible:true;implicitWidth:700;implicitHeight:500
  WeatherPopupContent { id:weather;width:390;height:root.bodyHeight }
 }
 Timer {
  interval:16;running:!root.finished;repeat:true
  onTriggered:{
   if(!Config.ready)return
   const panels=weather.children[0].children, orbit=panels[0],detail=panels[1]
   if(root.frame===0){console.info("WEATHER_TABS_START",weather.slideDuration,root.settledFrame);Config.setNestedValue("performance.reduceAnimations",false);root.settledFrame=10+Math.ceil(weather.slideDuration/16)+6;root.bodyHeight=300}
   if(root.frame<8 && !root.check(orbit.y===0 && detail.y===weather.height,"initial reveal paints only the selected tab"))return
   if(root.frame===10)weather.selectTab(1)
   if(root.frame>10 && root.frame<28 && detail.y>0 && detail.y<weather.height)root.inBetween++
   if(root.frame>=10 && root.frame<30 && !root.check(Math.abs(detail.y-orbit.y-weather.height)<.01,"both tabs share one animation position"))return
   if(root.frame===root.settledFrame){
    console.info("WEATHER_TABS_SETTLED",root.frame,detail.y,root.inBetween)
    if(!root.check(detail.y===0 && orbit.y===-weather.height && root.inBetween>0,"selection slides and settles: "+JSON.stringify({duration:weather.slideDuration,y:detail.y,frames:root.inBetween})))return
    root.bodyHeight=270
    if(!root.check(detail.y===0 && orbit.y===-270,"responsive resize does not replay a tab slide"))return
   }
   if(root.frame===root.settledFrame+3)root.bodyHeight=0
   if(root.frame===root.settledFrame+5){
    root.bodyHeight=300
    if(!root.check(detail.y===0 && orbit.y===-300,"rehost/reopen retains the selected tab without overlap"))return
    weather.selectTab(0)
   }
   if(root.frame===2*root.settledFrame+5){
    if(!root.check(orbit.y===0 && detail.y===300,"return to orbit"))return
    Config.setNestedValue("performance.reduceAnimations",true);weather.selectTab(1)
   }
   if(root.frame===2*root.settledFrame+7){
    if(!root.check(detail.y===0 && orbit.y===-300,"reduced motion selects without animation"))return
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
