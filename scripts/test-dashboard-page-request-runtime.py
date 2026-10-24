#!/usr/bin/env python3
"""Exercise real page Loaders/input in a private Niri session.

Frame samples qualify readiness and continued animation, not physical-display
smoothness. All configuration and service data belong to the temporary session.
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
 id:root;visible:true;width:1180;height:780;color:"#171a20"
 property var samples:[]
 property var selections:[]
 property string phase:""
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
  id:dashboard;anchors.fill:parent;embeddedSurface:true
  presentationActive:true;musicBackend:fakeMusic
 }
 Connections {
  target:dashboard
  function onCurrentPageIdChanged(){
   if(root.phase)root.selections.push({phase:root.phase,id:dashboard.currentPageId,
    ready:test.ready(dashboard.currentPageId)})
  }
 }
 FrameAnimation {
  running:dashboard.presentationActive && root.phase.length>0
  onTriggered:root.samples.push({phase:root.phase,time:Date.now(),
   position:test.pages.pagePosition,id:dashboard.currentPageId,
   ready:test.ready(dashboard.currentPageId)})
 }
 TestCase {
  id:test;optional:true;when:false
  property int checks:0
  property var music:null
  property var planner:null
  property var pages:null
  property var rows:[]
  function check(v,m){checks++;if(!v)throw new Error(m)}
  function button(id){return findChild(dashboard,"dashboardPage"+dashboard.pageIds.indexOf(id))}
  function ready(id){
   if(id==="dashboard")return true
   const loader=id==="music"?music:id==="weeklyPlanner"?planner:
    findChild(dashboard,"dashboardCustomPageLoader-"+id)
   return !!loader && loader.status===Loader.Ready && loader.item!==null
  }
  function painted(){
   let captured=false
   check(dashboard.grabToImage(image=>captured=true),"frame request refused")
   tryVerify(()=>captured,2500)
   check(captured,"no rendered frame")
  }
  function settle(id){
   tryCompare(dashboard,"currentPageId",id,6000)
   check(dashboard.currentPageId===id,"selection did not settle: "+id)
   tryCompare(pages,"pagePosition",dashboard.pageIds.indexOf(id),3000)
   check(ready(id),"selected page has no ready content: "+id)
   painted()
  }
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"dashboard.music.enable":true,"performance.reduceAnimations":false,
    "dashboard.customTabs":[{id:"custom-1",name:"Private request test"}],
    "dashboard.customTabLayouts":[]})
   music=findChild(dashboard,"dashboardMusicPageLoader")
   planner=findChild(dashboard,"dashboardPlannerPageLoader")
   pages=findChild(dashboard,"dashboardPages")
   check(!!music && !!planner && !!pages,"production Loaders/pages unavailable")
   check(dashboard.currentPageId==="dashboard","unexpected starting selection")
   painted()
   check(!music.active && !planner.active,"unvisited heavy pages eagerly loaded")
   const custom=findChild(dashboard,"dashboardCustomPageLoader-custom-1")
   check(!!custom && !custom.active,"unvisited custom page eagerly loaded")

   root.phase="cold-replace-cancel"
   button("music").click()
   check(dashboard.currentPageId==="dashboard" && dashboard._pendingPageId==="music",
    "cold request replaced the current page before deferred commitment")
   check(music.active && music.asynchronous && !planner.active,"request did not isolate asynchronous target")
   check(pages.pagePosition===0,"slide began before cold target readiness")
   button("weeklyPlanner").click()
   check(dashboard.currentPageId==="dashboard" && dashboard._pendingPageId==="weeklyPlanner",
    "replacement committed the abandoned page")
   check(!music.active && planner.active && planner.asynchronous,"abandoned cold Loader remained active")
   button("dashboard").click()
   check(!dashboard._pendingPageId && !music.active && !planner.active,"current-page cancellation retained cold work")
   wait(150)
   check(dashboard.currentPageId==="dashboard","cancelled request replayed later")

   for(const target of ["music","dashboard","weeklyPlanner","dashboard","music","dashboard"]){
    root.phase="switch-"+rows.length+"-"+target
    const before=dashboard.currentPageId,start=Date.now()
    button(target).click()
    const callMs=Date.now()-start
    check(dashboard.currentPageId===before && dashboard._pendingPageId===target,
     "signal request did not retain old selection until commitment: "+target)
    rows.push({target,call_ms:callMs,old:before,pending:dashboard._pendingPageId})
    settle(target)
   }
   check(root.samples.some(row=>row.position>0 && row.position<1),"no intermediate native page-animation frame")

   root.phase="native-click-key-wheel"
   mouseClick(button("music"));settle("music")
   const header=findChild(dashboard,"dashboardPageDots").parent
   header.forceActiveFocus();keyClick(Qt.Key_Right);settle("weeklyPlanner")
   header.forceActiveFocus();keyClick(Qt.Key_Left);settle("music")
   dashboard.resetPageWheel()
   mouseWheel(header,header.width/2,header.height/2,0,-120)
   wait(80)
   check(dashboard.currentPageId==="music" && !dashboard._pendingPageId,"vertical wheel changed pages")
   mouseWheel(header,header.width/2,header.height/2,120,0);settle("dashboard")

   root.phase="hidden-cold-custom"
   button("custom-1").click()
   check(dashboard._pendingPageId==="custom-1" && custom.active && custom.asynchronous,
    "custom request was not incubated separately")
   dashboard.presentationActive=false
   check(!dashboard._pendingPageId,"hidden Dashboard retained a pending request")
   wait(120)
   dashboard.presentationActive=true
   check(dashboard.currentPageId==="dashboard","hidden pending custom request replayed")
   button("custom-1").click();settle("custom-1")
   check(dashboard.canvasController!==null,"ready custom canvas unavailable")
   const savedCustom=JSON.stringify(Array.from(Config.options.dashboard.customTabLayouts))
   const customCanvas=dashboard.canvasController
   customCanvas.beginEditMode()
   customCanvas.setWidgetVisible("clock",true)
   check(customCanvas.editMode && customCanvas.visibleIds.includes("clock"),"custom draft not editable")
   check(dashboard.handleEscape(),"custom draft Escape not consumed")
   check(!customCanvas.editMode && !customCanvas.visibleIds.includes("clock")
    && dashboard.currentPageId==="custom-1","Escape did not cancel the selected custom canvas")
   check(JSON.stringify(Array.from(Config.options.dashboard.customTabLayouts))===savedCustom,
    "custom Escape wrote draft layout to saved settings")
   mouseClick(button("dashboard"));settle("dashboard")
   tryVerify(()=>!custom.active,3000)
   check(!custom.active,"offscreen custom canvas escaped existing unload policy")

   root.phase="remove-pending-custom"
   button("custom-1").click()
   Config.setNestedValue("dashboard.customTabs",[])
   check(!dashboard._pendingPageId,"removed target remained pending")
   wait(120)
   check(dashboard.currentPageId==="dashboard","removed target committed later")
   dashboard.canvasController.beginEditMode()
   button("music").click()
   check(dashboard.currentPageId==="dashboard" && !dashboard._pendingPageId,"Edit admitted page navigation")
   check(dashboard.handleEscape() && !dashboard.canvasController.editMode,"main canvas Escape did not cancel editing")
   dashboard.selectPage("weeklyPlanner")
   check(dashboard.currentPageId==="weeklyPlanner" && ready("weeklyPlanner"),"synchronous restoration lost ready content")
   check(!root.selections.some(row=>!row.ready),"an unready page became selected: "+JSON.stringify(root.selections))
   check(!root.samples.some(row=>!row.ready),"a rendered frame selected an unready page")
   console.info("DASH_PAGE_REQUEST_NATIVE_PASS",checks,JSON.stringify({calls:rows,frames:root.samples.length,selections:root.selections}))
  }catch(error){console.error("DASH_PAGE_REQUEST_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:150;running:true;onTriggered:test.run()}
}
'''

with tempfile.TemporaryDirectory(prefix="alis-dash-request-") as tmp:
    folder = Path(tmp)
    for name in ("modules", "services", "GlobalStates.qml", "qmldir",
                 "assets", "scripts", "defaults", "translations"):
        (folder / name).symlink_to(ROOT / name)
    (folder / "shell.qml").write_text(QML)
    with private_wayland(folder, capture_focus=True) as env:
        if env is None:
            print("SKIP: Dashboard page requests need private Niri")
            raise SystemExit(0)
        file = folder / "config/alis/config.json"
        file.parent.mkdir(parents=True, exist_ok=True)
        sample = json.loads((ROOT / "defaults/config.json").read_text())
        sample["panelFamily"] = "abyss"
        file.write_text(json.dumps(sample))
        result = run_qs(folder, env, timeout=50)
    failures = ("DASH_PAGE_REQUEST_NATIVE_FAIL", "ReferenceError:", "TypeError:",
                "Binding loop", "Unable to assign", "Cannot assign to non-existent property",
                "Failed to load configuration")
    if result.returncode or "DASH_PAGE_REQUEST_NATIVE_PASS" not in result.stdout \
            or any(phrase in result.stdout for phrase in failures):
        print(result.stdout)
        raise SystemExit(1)
    for line in result.stdout.splitlines():
        if "DASH_PAGE_REQUEST_NATIVE_PASS" in line:
            print(line)
