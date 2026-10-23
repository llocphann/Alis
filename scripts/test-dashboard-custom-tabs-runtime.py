#!/usr/bin/env python3
"""DASH-F01 isolated Quickshell integration: real Config, no owner file writes.

Requires Quickshell + private Niri. Source-policy tests are separate; this
fixture intentionally does not assert Owner acceptance or live UI behavior.
"""
import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.dashboard
Window {
 id:root
 visible:true
 width:1180;height:780;color:"#171a20"
 Component.onCompleted:Quickshell.watchFiles=false
 QtObject {
  id:fakeMusic
  property var libraryTracks:[]
  property var activeQueue:[]
  property var playlists:[]
  property var localLyricsLines:[]
  property var mprisPlayer:null
  property bool available:false
  property string error:""
 }
 DashboardContent {
  id:dashboard
  anchors.fill:parent
  embeddedSurface:true
  presentationActive:true
  musicBackend:fakeMusic
 }
 DashboardEditToolbar {
  id:tabToolbar
  objectName:"dashboardTestTabToolbar"
  tabController:dashboard
  canvasController:dashboard.canvasController
  width:520
  y:52
  anchors.horizontalCenter:parent.horizontalCenter
  z:300
 }
 FileView {
  id:disk;path:Config.filePath;watchChanges:true
  property var snapshot:null
  onLoaded:{try{snapshot=JSON.parse(text())}catch(error){snapshot=null}}
 }
 TestCase {
  id:test;when:false;optional:true
  property int checks:0
  function check(v,msg){checks++;if(!v)throw new Error(msg)}
  function layouts(){return Array.from(Config.options.dashboard.customTabLayouts)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   if(Quickshell.env("DASH_F01_ACTION")==="restart"){
    const kept=Array.from(Config.options.dashboard.customTabs).find(
     tab=>tab.name==="Keep tab without pending edit")
    check(!!kept,"saved tab definition missing after restart")
    tryCompare(dashboard,"currentPageId",kept.id,3000)
    tryVerify(()=>dashboard.canvasController!==null,3000)
    check(dashboard.customTabs.length===2
     && dashboard.customTabs[0].name==="Keep tab without pending edit"
     && dashboard.customTabs[1].name==="Keep explicit selection",
     "custom definitions/order did not survive actual restart")
    check(dashboard.canvasController.visibleIds.includes("clock"),
     "saved custom widget did not survive actual restart")
    check(Config.options.dashboard.defaultTabId==="dashboard"
     && Config.options.dashboard.inactiveMinutes===5,
     "restart changed opt-in default or inactivity settings")
    check(!dashboard.editMode && !GlobalStates.dashboardOpen,
     "restart restored an unfinished editor or opened global Dashboard")
    console.info("DASH_F01_RESTART_PASS",checks)
    Qt.quit();return
   }
   Config.setNestedValues({
    "performance.reduceAnimations":true,
    "dashboard.music.enable":false
   })
   const primary=JSON.stringify(Array.from(Config.options.dashboard.canvas.widgets))
   const dialog=findChild(dashboard,"dashboardCustomTabDialog")
   check(!!dialog,"delete confirmation dialog not mounted")
   const createButton=findChild(dashboard,"dashboardCreateCustomTab")
   const defaultButton=findChild(dashboard,"dashboardSetDefaultTab")
   const actions=findChild(dashboard,"dashboardCustomTabActions")
   const pageDots=findChild(dashboard,"dashboardPageDots")
   check(!!createButton && !!defaultButton && !!actions && !!pageDots,
    "custom tab action controls missing")
   check(!createButton.visible && !defaultButton.visible && !defaultButton.enabled,
    "custom/default tab actions must be hidden outside Edit")
   check(Math.abs(pageDots.mapToItem(dashboard,pageDots.width/2,0).x
    -dashboard.width/2)<4,"tab controls are not centered as one group")
   dashboard.canvasController.beginEditMode()
   tryVerify(()=>createButton.visible && createButton.enabled,1500)
   check(defaultButton.visible && defaultButton.enabled,
    "set-default button missing in Edit Dashboard Layout")
   let defaultControlPainted=false
   check(dashboard.grabToImage(image=>defaultControlPainted=true),"default-tab frame request refused")
   tryVerify(()=>defaultControlPainted,2000)
   check(defaultControlPainted,"default-tab controls did not render after entering Edit")
   const inactivity=Config.options.dashboard.inactiveMinutes
   mouseClick(defaultButton)
   check(Config.options.dashboard.defaultTabId==="dashboard",
    "default-tab action did not save active page in Edit mode")
   check(Config.options.dashboard.inactiveMinutes===inactivity,
    "set-default action silently changed inactivity duration")
   check(defaultButton.colBackground.a===1 && defaultButton.colBackgroundToggled.a===1
    && defaultButton.colBackground.toString()!==defaultButton.colBackgroundToggled.toString(),
    "default-tab selected/unselected states need distinct opaque backgrounds")
   check(defaultButton.contentItem.color.toString()!==defaultButton.colBackgroundToggled.toString(),
    "default-tab icon has no contrast against selected background")
   check(waitForPolish(root,2000),"Create control layout did not settle")
   mouseClick(createButton)
   tryVerify(()=>tabToolbar.visible && dashboard.tabNamingActive,2000)
   check(!dialog.visible && dashboard.editMode,
    "create click must replace editing controls, not open a centered dialog")
   const name=findChild(tabToolbar,"dashboardToolbarTabName")
   check(!!name,"toolbar text input missing")
   dashboard.setCustomTabName("Research")
   dashboard.acceptCustomTabDialog()
   tryVerify(()=>dashboard.currentPageId==="custom-1",3500)
   tryVerify(()=>dashboard.canvasController && dashboard.canvasController.editMode,3500)
   const canvas=dashboard.canvasController
   check(canvas.visibleIds.length===0,"custom tab not initially empty")
   canvas.setWidgetVisible("clock",true)
   check(canvas.visibleIds.includes("clock"),"widget unavailable to custom canvas")
   canvas.commitEditMode()
   tryVerify(()=>!!layouts().find(x=>x.id==="custom-1"),2500)
   check(layouts().find(x=>x.id==="custom-1").widgets.some(
    x=>x.id==="clock" && x.visible===true),"custom layout not saved")
   check(JSON.stringify(Array.from(Config.options.dashboard.canvas.widgets))===primary,
    "main Dashboard widget geometry changed")
   const orderBefore=Array.from(dashboard.pageIds)
   const savedOrder=JSON.stringify(Array.from(Config.options.dashboard.pageOrder))
   canvas.beginEditMode()
   check(waitForPolish(root,2000),"custom-tab reorder layout did not settle")
   const from=findChild(dashboard,"dashboardPage"+dashboard.pageIds.indexOf("custom-1"))
   const to=findChild(dashboard,"dashboardPage0")
   const drop=to.mapToItem(from,to.width/2,to.height/2)
   mousePress(from,from.width/2,from.height/2)
   mouseMove(from,drop.x,drop.y,20)
   mouseRelease(from,drop.x,drop.y)
   check(dashboard.pageIds[0]==="custom-1","custom canvas pointer reorder failed")
   canvas.undoLastEdit()
   check(JSON.stringify(dashboard.pageIds)===JSON.stringify(orderBefore),
    "custom canvas Undo left navigation in the reordered state")
   dashboard.moveTab("custom-1",0)
   canvas.resetLayout()
   check(JSON.stringify(dashboard.pageIds)===JSON.stringify(orderBefore),
    "custom canvas Reset did not update navigation")
   canvas.undoLastEdit()
   check(dashboard.pageIds[0]==="custom-1","custom canvas Reset was not undoable")
   canvas.cancelEditMode()
   check(JSON.stringify(dashboard.pageIds)===JSON.stringify(orderBefore)
    && JSON.stringify(Array.from(Config.options.dashboard.pageOrder))===savedOrder,
    "custom canvas Cancel changed saved navigation")
   check(dashboard.canvasController===canvas && canvas.visibleIds.includes("clock"),
    "navigation edits changed the selected canvas or its saved widget")
   dashboard.canvasController.beginEditMode()
   dashboard.openCustomTabDialog("rename","custom-1")
   check(tabToolbar.visible,"rename did not open edit toolbar")
   dashboard.setCustomTabName("Research II")
   dashboard.acceptCustomTabDialog()
   tryVerify(()=>Array.from(Config.options.dashboard.customTabs)[0].name==="Research II",2000)
   dashboard.canvasController.beginEditMode()
   dashboard.openCustomTabDialog("create","")
   dashboard.setCustomTabName("research ii")
   dashboard.acceptCustomTabDialog()
   check(dashboard._customDialogShown && dashboard._customDialogError.length>0,
    "duplicate name not rejected")
   dashboard.cancelCustomTabDialog()
   dashboard.canvasController.cancelEditMode()
   Config.setNestedValues({
     "dashboard.defaultTabId":"dashboard",
     "dashboard.inactiveMinutes":5
   })
   dashboard.presentationActive=false
   Config.setNestedValue("dashboard.lastHiddenAtMs",Date.now()-4*60000)
   dashboard.presentationActive=true
   check(dashboard.currentPageId==="custom-1","reopened before timeout lost last page")
   dashboard.presentationActive=false
   Config.setNestedValue("dashboard.lastHiddenAtMs",Date.now()-6*60000)
   dashboard.presentationActive=true
   check(dashboard.currentPageId==="dashboard","inactivity did not select default tab")
   Config.setNestedValue("dashboard.defaultTabId","custom-1")
   dashboard.selectPage("custom-1")
   tryVerify(()=>dashboard.canvasController!==null,2500)
   dashboard.canvasController.beginEditMode()
   dashboard.openCustomTabDialog("delete","custom-1")
   check(dialog.visible && dialog.mode==="delete","delete confirmation not shown")
   dialog.acceptRequested("")
   check(!Array.from(Config.options.dashboard.customTabs).some(x=>x.id==="custom-1"),
    "deleted tab still available")
   check(!layouts().some(x=>x.id==="custom-1"),"deleted layout still saved")
   check(Config.options.dashboard.defaultTabId==="dashboard",
    "deleting default tab did not repair fallback")
   check(JSON.stringify(Array.from(Config.options.dashboard.canvas.widgets))===primary,
    "deleting custom tab erased other Dashboard layout")
   check(GlobalStates.dashboardOpen===false,"tab policy opened global Dashboard")
   dashboard.canvasController.beginEditMode()
   dashboard.openCustomTabDialog("create","")
   dashboard.setCustomTabName("Keep tab without pending edit")
   dashboard.acceptCustomTabDialog()
   const hiddenTab=dashboard.currentPageId
   dashboard.presentationActive=false
   wait(30)
   check(dashboard._pendingNewEditId==="","hidden Dashboard retained pending auto-edit")
   check(dashboard.customTabs.some(t=>t.id===hiddenTab),"cancelled auto-edit removed saved tab")
   dashboard.presentationActive=true
   tryVerify(()=>dashboard.canvasController!==null,2500)
   check(!dashboard.canvasController.editMode,"reopen replayed cancelled auto-edit")
   dashboard.canvasController.beginEditMode()
   dashboard.canvasController.setWidgetVisible("clock",true)
   dashboard.canvasController.commitEditMode()
   dashboard.canvasController.beginEditMode()
   dashboard.openCustomTabDialog("create","")
   dashboard.setCustomTabName("Keep explicit selection")
   dashboard.acceptCustomTabDialog()
   dashboard.selectPage("dashboard")
   wait(30)
   check(dashboard._pendingNewEditId==="","page switch retained pending auto-edit")
   check(dashboard.currentPageId==="dashboard"&&!dashboard.canvasController.editMode,
    "pending auto-edit overrode explicit selection")
   check(JSON.stringify(Array.from(Config.options.dashboard.canvas.widgets))===primary,
    "cancelled auto-edit changed built-in layout")
   dashboard.selectPage(hiddenTab)
   tryVerify(()=>dashboard.canvasController!==null,2500)
   tryVerify(()=>{
    disk.reload()
    const saved=disk.snapshot?.dashboard
    return saved?.lastPageId===hiddenTab && saved?.customTabs?.length===2
     && saved.customTabLayouts?.some(layout=>layout.id===hiddenTab
      && layout.widgets.some(widget=>widget.id==="clock"&&widget.visible===true))
   },5000)
   check(!dashboard.canvasController.editMode,"selecting saved tab reopened an editor")
   console.info("DASH_F01_NATIVE_PASS",checks)
  }catch(e){console.error("DASH_F01_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer{interval:150;running:true;onTriggered:test.run()}
}
'''
with tempfile.TemporaryDirectory(prefix="alis-dash-f01-") as tmp:
    folder = Path(tmp)
    for name in ("modules", "services", "GlobalStates.qml", "qmldir",
                 "assets", "scripts", "defaults", "translations"):
        (folder / name).symlink_to(ROOT / name)
    (folder / "shell.qml").write_text(QML)
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: DASH-F01 needs a private Niri backend")
            raise SystemExit(0)
        file = folder / "config/alis/config.json"
        file.parent.mkdir(parents=True, exist_ok=True)
        sample = json.loads((ROOT / "defaults/config.json").read_text())
        sample["panelFamily"] = "abyss"
        file.write_text(json.dumps(sample))
        result = run_qs(folder, env, timeout=35)
        failures = ("DASH_F01_NATIVE_FAIL", "ReferenceError:", "TypeError:",
                    "Binding loop", "Unable to assign",
                    "Cannot assign to non-existent property", "Failed to load configuration")
        if result.returncode or "DASH_F01_NATIVE_PASS" not in result.stdout \
                or any(phrase in result.stdout for phrase in failures):
            print(result.stdout)
            raise SystemExit(1)
        stored = json.loads(file.read_text())
        assert stored["dashboard"]["canvas"]["widgets"] == sample["dashboard"]["canvas"]["widgets"], \
            "private disk readback changed built-in widget data"
        restarted = run_qs(folder, dict(env, DASH_F01_ACTION="restart"), timeout=20)
    failures = ("DASH_F01_NATIVE_FAIL", "ReferenceError:", "TypeError:",
                "Binding loop", "Unable to assign",
                "Cannot assign to non-existent property", "Failed to load configuration")
    if restarted.returncode or "DASH_F01_RESTART_PASS" not in restarted.stdout \
            or any(phrase in restarted.stdout for phrase in failures):
        print(restarted.stdout)
        raise SystemExit(1)
    for line in (result.stdout+restarted.stdout).splitlines():
        if "DASH_F01_NATIVE_PASS" in line or "DASH_F01_RESTART_PASS" in line:
            print(line)
