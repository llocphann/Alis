#!/usr/bin/env python3
"""Use the production toolbar and field host in an isolated Qt/Quickshell output."""
from pathlib import Path
import os
import json
import shutil
import subprocess
import tempfile

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
  function _widgetEnabled(key,fallback) { return fallback }
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
    if(!root.check(toolbar.hosted && toolbar.parent===widgetEditorBody.contentParent,"existing field owns toolbar visual parent"))return
    if(!root.check(toolbar.placement.edge==="bottom" && widgetEditorBody.inputBounds.width>500,"bottom connected body and input"))return
    const grid=root.find(toolbar,i=>typeof i.downAction==="function" && i.contentItem?.text==="grid_3x3")
    if(!root.check(grid!==null,"original grid control is reachable"))return
    const before=Config.getNestedValue("background.widgets.editGrid.snap",true)
    grid.downAction()
    if(!root.check(Config.getNestedValue("background.widgets.editGrid.snap",true)!==before,"grid control still changes the original setting"))return
    root.captureThen("bottom",()=>toolbar.obstacles=[{x:0,y:window.height-120,width:window.width,height:120}])
   } else if(root.step===2) {
    if(!root.check(widgetEditorBody.edge==="top" && !toolbar.vertical,"top avoids lower widgets"))return
    root.captureThen("top",()=>toolbar.obstacles=[{x:0,y:window.height-120,width:window.width,height:120},{x:0,y:0,width:window.width,height:130}])
   } else if(root.step===3) {
    if(!root.check(widgetEditorBody.edge==="left" && toolbar.vertical && toolbar.width===52,"left rail with fixed control dimensions"))return
    const rect=widgetEditorBody.record.content
    if(!root.check(rect.x>=0 && rect.y>=0 && rect.x+rect.width<=window.width && rect.y+rect.height<=window.height,"input remains bounded on a vertical edge"))return
    const manage=root.find(toolbar,i=>typeof i.releaseAction==="function" && i.contentItem?.children?.some(c=>c.text==="Manage widgets"))
    if(!root.check(manage!==null,"manager control retains its context"))return
    manage.releaseAction()
    if(!root.check(managerState.shown,"manager action still opens the original manager"))return
    root.captureThen("left",()=>toolbar.obstacles=toolbar.obstacles.concat([{x:0,y:0,width:110,height:window.height}]))
   } else if(root.step===4) {
    if(!root.check(widgetEditorBody.edge==="right" && widgetEditorBody.inputBounds.height>400,"right rail avoids occupied left edge"))return
    root.captureThen("right",()=>{
     GlobalStates.setWidgetEditMode(false)
     root.check(widgetEditorBody.inputBounds.width===0 && !toolbar.enabled,"semantic close releases input immediately")
    })
   } else if(root.step===5) {
    GlobalStates.setWidgetEditMode(true)
    toolbar.obstacles=[]
    window.nativeInsets=({left:16,top:48,right:window.width-400,bottom:16})
   } else if(root.step===6) {
    const rail=root.find(toolbar,i=>i.objectName==="desktopWidgetEditorRail")
    if(!root.check(rail!==null && rail.contentWidth>rail.width && rail.interactive,"narrow outputs keep every control reachable by scrolling"))return
    rail.contentX=rail.contentWidth-rail.width
    const done=root.find(toolbar,i=>typeof i.downAction==="function" && i.contentItem?.text==="check")
    const point=done.mapToItem(rail,0,0)
    if(!root.check(point.x>=0 && point.x+done.width<=rail.width+1,"Done remains reachable on narrow output"))return
    done.downAction()
    GlobalStates.setWidgetEditMode(true)
    Config.setNestedValue("panelFamily","waffle")
   } else if(root.step===7) {
    if(!root.check(!toolbar.hosted && toolbar.parent===home && toolbar.height===52,"Waffle restores existing horizontal controls"))return
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
print("PASS: original widget controls share Abyss painting/input on four edges; semantic close and family/output lifecycle")
