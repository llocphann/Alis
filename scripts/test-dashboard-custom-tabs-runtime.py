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
  anchors.top:parent.top
  anchors.horizontalCenter:parent.horizontalCenter
  z:300
 }
 TestCase {
  id:test;when:false;optional:true
  property int checks:0
  function check(v,msg){checks++;if(!v)throw new Error(msg)}
  function layouts(){return Array.from(Config.options.dashboard.customTabLayouts)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({
    "performance.reduceAnimations":true,
    "dashboard.music.enable":false
   })
   const primary=JSON.stringify(Array.from(Config.options.dashboard.canvas.widgets))
   const dialog=findChild(dashboard,"dashboardCustomTabDialog")
   check(!!dialog,"delete confirmation dialog not mounted")
   const createButton=findChild(dashboard,"dashboardCreateCustomTab")
   check(!!createButton && createButton.visible && createButton.enabled,
    "create button must be visible and enabled outside Edit Dashboard Layout")
   mouseClick(createButton)
   tryVerify(()=>tabToolbar.visible && dashboard.tabNamingActive,2000)
   check(!dialog.visible && !dashboard.editMode,
    "create click must show naming toolbar, not a canvas modal or Edit mode")
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
   dashboard.openCustomTabDialog("rename","custom-1")
   check(tabToolbar.visible,"rename did not open edit toolbar")
   dashboard.setCustomTabName("Research II")
   dashboard.acceptCustomTabDialog()
   tryVerify(()=>Array.from(Config.options.dashboard.customTabs)[0].name==="Research II",2000)
   dashboard.openCustomTabDialog("create","")
   dashboard.setCustomTabName("research ii")
   dashboard.acceptCustomTabDialog()
   check(dashboard._customDialogShown && dashboard._customDialogError.length>0,
    "duplicate name not rejected")
   dashboard.cancelCustomTabDialog()
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
    for line in result.stdout.splitlines():
        if "DASH_F01_NATIVE_PASS" in line:
            print(line)
