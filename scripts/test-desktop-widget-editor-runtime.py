#!/usr/bin/env python3
"""Verify the bottom-connected 2-tier Abyss Desktop Widget customization dock in Quickshell."""
from pathlib import Path
import os
import json
import shutil
import subprocess
import tempfile
import sys as _silent_sys
if os.environ.get("ALIS_SILENT_TEST_MODE") != "1":
    raise SystemExit(subprocess.call([_silent_sys.executable, str(Path(__file__).resolve().parent / "native_test_session.py"), "--", _silent_sys.executable, __file__, *_silent_sys.argv[1:]]))

repo = Path(__file__).resolve().parents[1]
if not shutil.which("qs") or not os.environ.get("WAYLAND_DISPLAY"):
    print("SKIP: native widget editor (Quickshell/Wayland unavailable)")
    raise SystemExit(0)
perimeter = (repo / "modules/abyss/AbyssPerimeter.qml").read_text()
start = perimeter.index("            AbyssBodyHost {\n                id: widgetEditorBody")
end = perimeter.index("            AbyssBodyHost {\n                id: leftPanel", start)
host = perimeter[start:end]
with tempfile.TemporaryDirectory(prefix="alis-widget-editor-") as folder:
    root = Path(folder)
    for name in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (root / name).symlink_to(repo / name)
    config = root / "config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy(repo / "defaults/config.json", config / "config.json")
    qml = r'''
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.looks
import qs.modules.background.widgets
ShellRoot {
 id:root
 property int step:0
 property bool failed:false
 property bool capturing:false
 function check(ok,message): bool {
  if(ok) return true
  console.error("WIDGET_EDITOR_FAIL",message);root.failed=true;Qt.quit();return false
 }
 function find(item,predicate) {
  if(!item) return null
  if(predicate(item)) return item
  for(const child of item.children ?? []) { const found=find(child,predicate);if(found)return found }
  return null
 }
 function captureThen(name,action) {
  const directory=CAPTURE_PATH
  if(!directory) {action();return}
  root.capturing=true
  const accepted=painting.grabToImage(result=>{
   if(!root.check(result.saveToFile(directory+"/"+name+".png"),"capture saved"))return
   root.capturing=false;action()
  })
  root.check(accepted,"capture request accepted")
 }
 QtObject {
  id:context
  property string screenName:"A"
  function _widgetEnabled(key,fallback) {
   return DesktopWidgetLayout.enabled(context.screenName,key,fallback)
  }
 }
 QtObject { id:managerState;property bool shown:false }
 AbyssSurfaceController {
  id:liquid;outputWidth:window.width;outputHeight:window.height;edgeInsets:window.nativeInsets
 }
 FloatingWindow {
  id:window;visible:true;implicitWidth:1200;implicitHeight:800;color:"#070f12"
  property string outputName:"A"
  property bool presented:true
  property var nativeInsets:({left:16,top:48,right:16,bottom:16})
  function bodyInsets(edge,along,span) { return nativeInsets }
  Item { id:painting;anchors.fill:parent
  Item {
   id:home;anchors.fill:parent
   property var abyssHost:null
   property real safeLeft:16;property real safeTop:48
   property real safeRight:window.width-16;property real safeBottom:window.height-16
   property real safeWidth:safeRight-safeLeft
   DesktopWidgetEditToolbar {
    id:toolbar;windowContext:context;safeBounds:home;manager:managerState;fallbackParent:home
   }
  }
  AbyssField { id:field;anchors.fill:parent;z:-1;edgeInsets:window.nativeInsets;records:liquid.records }
  HOST
  }
 }
 Timer {
  interval:250;running:!root.failed;repeat:true
  onTriggered: {
   if(!Config.ready || !field.ready || root.capturing) return
   if(root.step===0) {
    Config.setNestedValue("panelFamily","abyss")
    Config.setNestedValue("performance.reduceAnimations",true)
    GlobalStates.deferredPanelsReady=true
    GlobalStates.setWidgetEditMode(true)
   } else if(root.step===1) {
    if(!root.check(toolbar.hosted && toolbar.parent===widgetEditorBody.contentParent,"Abyss field owns toolbar visual parent"))return
    if(!root.check(toolbar.placement.edge==="bottom" && widgetEditorBody.edge==="bottom" && !toolbar.vertical,"dock stays connected to bottom Screen Edge"))return
    if(!root.check(toolbar.placement.depth>=160 && toolbar.placement.depth<=180 && widgetEditorBody.inputBounds.width>500 && widgetEditorBody.inputBounds.height>=145,"expanded 2-tier bottom body and input bounds"))return
    const dock=root.find(toolbar,i=>i.objectName==="abyssCustomizationDock")
    if(!root.check(dock!==null && dock.embeddedSurface===true,"AbyssCustomizationDock runs in embeddedSurface mode"))return
    const rail=root.find(toolbar,i=>i.objectName==="desktopWidgetEditorRail")
    if(!root.check(rail!==null && rail.contentWidth>rail.width && rail.interactive,"horizontal tile gallery is scrollable"))return
    if(!root.check(toolbar.visibleGalleryCount>=15,"all 15 built-in widgets present in gallery"))return

    // Snap & Grid Size quick controls
    const snapBtn=root.find(toolbar,i=>i.objectName==="widgetDockSnapButton")
    if(!root.check(snapBtn!==null,"snap quick button reachable"))return
    const snapBefore=Config.getNestedValue("background.widgets.editGrid.snap",true)
    snapBtn.downAction()
    if(!root.check(Config.getNestedValue("background.widgets.editGrid.snap",true)!==snapBefore,"snap button toggles editGrid.snap"))return
    const sizeBtn=root.find(toolbar,i=>i.objectName==="widgetDockGridSizeButton")
    if(!root.check(sizeBtn!==null,"grid size badge reachable"))return
    const sizeBefore=Config.getNestedValue("background.widgets.editGrid.size",32)
    sizeBtn.downAction()
    if(!root.check(Config.getNestedValue("background.widgets.editGrid.size",32)!==sizeBefore,"grid size badge cycles grid cell size"))return

    // Manage & Page 14 Settings buttons removed in unified Stage dock design
    if(!root.check(root.find(toolbar,i=>i.objectName==="widgetDockManageButton")===null,"Manage Widgets button is retired"))return
    if(!root.check(root.find(toolbar,i=>i.objectName==="widgetDockSettingsButton")===null,"Page 14 settings shortcut button is retired"))return

    // Live search + tile toggle (+ -> check)
    const searchInput=root.find(toolbar,i=>i.objectName==="widgetDockSearchInput")
    if(!root.check(searchInput!==null,"search input reachable"))return
    searchInput.text="weather"
    if(!root.check(toolbar.visibleGalleryCount===1,"search filters widget tiles live"))return
    const weatherTile=root.find(rail,i=>i.objectName==="abyssCustomizationTile" && i.tileId==="weather")
    if(!root.check(weatherTile!==null && weatherTile.visible && weatherTile.active===false,"Weather tile starts inactive (+)"))return
    weatherTile.clicked()
    if(!root.check(DesktopWidgetLayout.enabled("A","weather",false)===true && weatherTile.active===true,"clicking tile toggles widget on immediately (check)"))return
    searchInput.text=""

    // Active, Grid & Style, Power & Displays & Custom tabs
    toolbar.activeTab="active"
    if(!root.check(weatherTile.visible && toolbar.visibleGalleryCount>=2,"Active tab lists newly enabled widget"))return
    toolbar.activeTab="grid"
    const styleIslandChip=root.find(toolbar,i=>i.objectName==="widgetDockStyleIslandChip")
    if(!root.check(styleIslandChip!==null,"Grid & Style tab exposes Widget Style chips"))return
    const resetBtn=root.find(toolbar,i=>i.objectName==="widgetDockResetPositionsButton")
    if(!root.check(resetBtn!==null,"Grid & Style tab exposes position reset control"))return
    toolbar.activeTab="power"
    const powerChip=root.find(toolbar,i=>i.objectName==="widgetDockPowerEnableChip")
    if(!root.check(powerChip!==null,"Power & Displays tab exposes power saving toggle"))return
    toolbar.activeTab="custom"
    const createBtn=root.find(toolbar,i=>i.objectName==="widgetDockCustomCreateButton")
    if(!root.check(createBtn!==null,"Custom tab exposes Create Custom Widget button"))return
    toolbar.activeTab="widgets"

    root.captureThen("bottom",()=>{
     toolbar.obstacles=[{x:920,y:window.height-120,width:240,height:120,key:"corner"}]
    })
   } else if(root.step===2) {
    if(!root.check(widgetEditorBody.edge==="bottom" && !toolbar.vertical,"corner bottom obstacle slides/clamps horizontally on bottom edge"))return
    if(!root.check(toolbar.placement.x+toolbar.placement.width<=920-12+1,"bottom dock clears corner widget horizontally"))return
    toolbar.obstacles=[
     {x:0,y:window.height-120,width:window.width,height:120},
     {x:0,y:0,width:window.width,height:130},
     {x:0,y:0,width:110,height:window.height}
    ]
   } else if(root.step===3) {
    if(!root.check(widgetEditorBody.edge==="bottom" && !toolbar.vertical,"full multi-edge congestion still stays bottom-connected"))return
    const collapseBtn=root.find(toolbar,i=>i.objectName==="widgetDockCollapseButton")
    if(!root.check(collapseBtn!==null,"collapse tray button reachable"))return
    collapseBtn.downAction()
   } else if(root.step===4) {
    if(!root.check(toolbar.trayExpanded===false && toolbar.placement.depth>=50 && toolbar.placement.depth<=62,"collapsed 1-tier bottom dock depth (~54-56px)"))return
    if(!root.check(widgetEditorBody.edge==="bottom" && widgetEditorBody.inputBounds.width>500,"collapsed bottom dock retains input region"))return
    toolbar.trayExpanded=true
    toolbar.obstacles=[]
    window.nativeInsets=({left:16,top:48,right:window.width-400,bottom:16})
   } else if(root.step===5) {
    const rail=root.find(toolbar,i=>i.objectName==="desktopWidgetEditorRail")
    if(!root.check(rail!==null && rail.contentWidth>rail.width && rail.interactive,"narrow outputs keep tile gallery reachable by horizontal scrolling"))return
    const done=root.find(toolbar,i=>i.objectName==="widgetDockDoneButton")
    if(!root.check(done!==null,"Done pill reachable on narrow output"))return
    const point=done.mapToItem(toolbar,0,0)
    if(!root.check(point.x>=0 && point.x+done.width<=toolbar.width+1,"Done pill stays unclipped inside narrow dock"))return
    const dock=root.find(toolbar,i=>i.objectName==="abyssCustomizationDock")
    dock.doneClicked()
    if(!root.check(!GlobalStates.widgetEditMode && !managerState.shown,"Done exits widget edit mode and closes manager"))return
    if(!root.check(widgetEditorBody.inputBounds.width===0 && !toolbar.enabled,"semantic close releases input immediately"))return
    window.nativeInsets=({left:16,top:48,right:16,bottom:16})
    GlobalStates.setWidgetEditMode(true)
    Config.setNestedValue("panelFamily","waffle")
   } else if(root.step===6) {
    const dock=root.find(toolbar,i=>i.objectName==="abyssCustomizationDock")
    if(!root.check(!toolbar.hosted && toolbar.parent===home && dock.embeddedSurface===false,"Waffle uses non-Abyss bottom-connected dock fallback"))return
    if(!root.check(dock.bottomLeftRadius===0 && dock.bottomRightRadius===0 && Math.abs((toolbar.y+toolbar.height)-home.safeBottom)<=1,"non-Abyss fallback anchors flush to bottom of safeBounds"))return
    if(!root.check(toolbar.height>=164 && toolbar.height<=176,"non-Abyss fallback expanded height (~168px)"))return
    toolbar.trayExpanded=false
    if(!root.check(toolbar.height===54,"non-Abyss fallback collapsed height (54px)"))return
    GlobalStates.registerDesktopWidgetEditor("A",home)
    GlobalStates.unregisterDesktopWidgetEditor("A",toolbar)
    if(!root.check(GlobalStates.desktopWidgetEditors.A===home,"retiring item cannot unregister replacement output"))return
    GlobalStates.unregisterDesktopWidgetEditor("A",home)
    console.info("WIDGET_EDITOR_PASS");Qt.quit();return
   }
   root.step++
  }
 }
}
'''.replace("  HOST", host).replace("CAPTURE_PATH", json.dumps(os.environ.get("ALIS_EDITOR_CAPTURE_DIR", "")))
    (root / "shell.qml").write_text(qml)
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", XDG_CONFIG_HOME=str(root / "config"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"))
    for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
        env.pop(key, None)
    result = subprocess.run(["dbus-run-session", "--", "timeout", "15s", "qs", "-p", str(root), "--no-color"],
                            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    errors = ("WIDGET_EDITOR_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign",
              "Cannot anchor", "is not a type", "Type DesktopWidgetEditToolbar unavailable")
    if result.returncode or "WIDGET_EDITOR_PASS" not in result.stdout or any(e in result.stdout for e in errors):
        print(result.stdout)
        raise SystemExit(1)
print("PASS: bottom-connected 2-tier Abyss widget customization dock, search/tiles/tabs/grid, collapse/expand, narrow reachability, and Waffle fallback")
