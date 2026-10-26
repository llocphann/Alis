#!/usr/bin/env python3
"""Actual Background/field coordinates with disabled and active widget parallax."""
import json
import tempfile
from pathlib import Path

from native_test_session import private_wayland, run_qs
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-widget-coordinates-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets",
                  "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    wallpaper = folder / "wallpaper.png"
    Image.new("RGB", (1600, 900), "#19303c").save(wallpaper)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.background
import qs.modules.abyss
import qs.services
ShellRoot {
 id:root
 Component.onCompleted:Quickshell.watchFiles=false
 Background {id:background}
 AbyssPerimeter {}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function close(a,b){return Math.abs(a-b)<.01}
  function layoutSnapshot(){
   return JSON.stringify(Config.options.background.widgets.outputOverrides,(key,value)=>{
    if(!value || typeof value!=="object" || Array.isArray(value))return value
    const sorted={};for(const name of Object.keys(value).sort())sorted[name]=value[name]
    return sorted
   })
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   GlobalStates.deferredPanelsReady=true
   const variants=qtest_results.findChild(background,"desktopBackgroundOutputs")
   tryVerify(()=>variants?.instances.length>0,4000)
   const window=variants.instances[0]
   tryVerify(()=>GlobalStates.desktopWidgetEditors[window.screenName]!==undefined,4000)
   const toolbar=GlobalStates.desktopWidgetEditors[window.screenName]
   const canvas=toolbar.fallbackParent.parent
   const grid=toolbar.safeBounds
   tryVerify(()=>toolbar.hosted && window.wallpaperWidth===1600,5000)
   tryVerify(()=>canvas._loadedDesktopWidgets().some(item=>item.configEntryName==="customImage"),5000)
   const widget=canvas._loadedDesktopWidgets().find(item=>item.configEntryName==="customImage")
   check(window.parallaxTotalX>0 && window.parallaxTotalY>0,"fixture lacks oversized wallpaper")
   // Qualify editor behavior after the normal first-output migration completes.
   tryVerify(()=>DesktopWidgetLayout.outputLayoutMatches(window.screenName,canvas.width,canvas.height),5000)
   wait(500)
   const saved=layoutSnapshot()
   const position=Qt.point(widget.x,widget.y)
   const dimensions=Qt.size(widget.width,widget.height)
   function outputAligned(label){
    const origin=canvas.mapToItem(window.contentItem,0,0)
    check(close(origin.x,0) && close(origin.y,0),label+" canvas displaced: "+JSON.stringify(origin))
    const center=grid.mapToItem(window.contentItem,grid.zoneLeft+grid.zoneWidth/2,grid.zoneTop+grid.zoneHeight/2)
    check(close(center.x,window.width/2) && close(center.y,window.height/2),label+" grid is not output centered: "+JSON.stringify(center))
    const painted=widget.mapToItem(window.contentItem,0,0)
    check(close(painted.x,widget.x) && close(painted.y,widget.y),label+" painted widget differs from stored coordinates")
    const obstacle=toolbar.obstacles.find(item=>item.key===widget.editInstanceKey)
    check(obstacle && close(obstacle.x,painted.x) && close(obstacle.y,painted.y),label+" toolbar avoidance uses another coordinate space")
    check(toolbar.abyssHost.inputBounds.width>0,"connected editor has no input")
    check(widget.x===position.x && widget.y===position.y && widget.width===dimensions.width && widget.height===dimensions.height,"editing changed widget geometry")
    check(layoutSnapshot()===saved,"editing persisted a layout change")
   }
   // An explicit master disable wins even when child flags and zoom/depth are
   // retained from a previously enabled parallax configuration.
   GlobalStates.setWidgetEditMode(true)
   tryVerify(()=>toolbar.abyssHost.acceptsInput,3000)
   outputAligned("parallax disabled")
   GlobalStates.setWidgetEditMode(false)
   Config.setNestedValue("background.parallax.enable",true)
   tryVerify(()=>canvas._parallaxActive,3000)
   wait(700)
   const moving=canvas.mapToItem(window.contentItem,0,0)
   check(Math.abs(moving.x)>.1 || Math.abs(moving.y)>.1,"enabled parallax lost its existing motion")
   // Entering the editor immediately restores the physical output coordinates;
   // no transition frame may move the grid, input or avoidance rectangles.
   for(let i=0;i<3;i++){
    GlobalStates.setWidgetEditMode(true)
    tryVerify(()=>toolbar.abyssHost.acceptsInput,3000)
    outputAligned("active parallax edit "+i)
    wait(80);outputAligned("stable edit "+i)
    GlobalStates.setWidgetEditMode(false)
    tryVerify(()=>canvas._parallaxActive,3000)
    wait(500)
   }
   Config.setNestedValue("background.parallax.enable",false)
   tryVerify(()=>!canvas._parallaxActive,1000)
   tryVerify(()=>{
    const origin=canvas.mapToItem(window.contentItem,0,0)
    return close(origin.x,0) && close(origin.y,0)
   },2500)
   const resting=canvas.mapToItem(window.contentItem,0,0)
   check(close(resting.x,0) && close(resting.y,0),"disabling parallax retained the old offset")
   GlobalStates.setWidgetEditMode(true)
   tryVerify(()=>toolbar.abyssHost.acceptsInput,3000)
   outputAligned("disabled again")
   GlobalStates.setWidgetEditMode(false)
   console.info("WIDGET_COORDINATES_PASS physical grid/widget/input/avoidance; disabled and active parallax; layout preserved")
  }catch(error){console.error("WIDGET_COORDINATES_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:150;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: widget coordinates require private Niri")
            raise SystemExit(0)
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        data["background"]["wallpaperPath"] = str(wallpaper)
        # Internal ownership keeps this fixture off the owner's awww socket.
        data["background"]["transition"]["type"] = "alisMelt"
        data["background"]["effects"]["enableBlur"] = False
        data["background"]["parallax"].update(enable=False, enableWorkspace=True,
            enableSidebar=True, zoom=1.08, workspaceZoom=1.08, widgetDepth=1.38,
            widgetsFactor=1.38)
        data["background"]["widgets"] = {"clock": {"enable": False},
            "customImage": {"enable": True, "path": str(wallpaper),
                "contentWidth": 220, "contentHeight": 160,
                "x": 240, "y": 200, "locked": True}}
        (config / "config.json").write_text(json.dumps(data))
        env.update(QSG_RHI_BACKEND="opengl", QT_QUICK_CONTROLS_STYLE="Basic",
                   QT_QPA_PLATFORMTHEME="generic")
        result = run_qs(folder, env, timeout=35)
        failures = ["WIDGET_COORDINATES_FAIL", "ReferenceError:", "TypeError:",
                    "Binding loop", "Failed to load configuration", "Unable to assign"]
        if result.returncode or "WIDGET_COORDINATES_PASS" not in result.stdout or any(
                message in result.stdout for message in failures):
            print(result.stdout)
            raise SystemExit(1)
        print("WIDGET_COORDINATES_PASS actual desktop and connected field: output-aligned grid, widget paint, input, avoidance; parallax resumes; saved layout unchanged")
