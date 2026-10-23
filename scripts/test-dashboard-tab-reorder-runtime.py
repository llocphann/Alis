#!/usr/bin/env python3
"""Actual edit-only pointer/keyboard page ordering and saved Config restart."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT=Path(__file__).resolve().parents[1]
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.dashboard
Window {
 id:root;visible:true;width:1100;height:720;color:"#111820"
 property int captures:0
 FileView {
  id:disk;path:Config.filePath;watchChanges:true
  property var snapshot:null
  onLoaded:{try{snapshot=JSON.parse(text())}catch(error){snapshot=null}}
 }
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
 Item {
  id:scene;width:1100;height:720
  Rectangle {anchors.fill:parent;color:Appearance.colors.colLayer0Base}
  DashboardContent {id:dashboard;anchors.fill:parent;embeddedSurface:true;presentationActive:true;musicBackend:fakeMusic}
 }
 TestCase {
  id:test;when:false;optional:true
  property int checks:0
  function check(ok,message){checks++;if(!ok)throw new Error(message)}
  function same(a,b,message){check(JSON.stringify(a)===JSON.stringify(b),message+": "+JSON.stringify(a))}
  function frame(name){const before=root.captures;check(scene.grabToImage(image=>{if(name)image.saveToFile(Quickshell.env("REORDER_CAPTURES")+"/"+name+".png");root.captures++}),"frame request refused");tryVerify(()=>root.captures>before,2500)}
  function dot(index){return findChild(dashboard,"dashboardPage"+index)}
  function drag(from,to,preview){
   const source=dot(from),target=dot(to),end=target.mapToItem(source,target.width/2,target.height/2)
   mousePress(source,source.width/2,source.height/2)
   mouseMove(source,end.x,end.y,20)
   if(preview)preview()
   mouseRelease(source,end.x,end.y)
   frame("")
  }
  function run(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValue("performance.reduceAnimations",true)
   check(Math.abs(Screen.devicePixelRatio-Number(Quickshell.env("QT_SCALE_FACTOR") || "1"))<.01,"private fractional DPR was not applied")
   console.info("DASHBOARD_TAB_REORDER_DPR",Screen.devicePixelRatio)
   frame("initial")
   const canvas=dashboard.canvasController,header=findChild(dashboard,"dashboardPageDots").parent
   const saved=Array.from(Config.options.dashboard.pageOrder),cards=JSON.stringify(Config.options.dashboard.canvas.widgets)
   same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"legacy two-page order did not append Planner")
   canvas.beginEditMode();frame("edit")
   mouseClick(dot(1));same(dashboard.currentPageId,"dashboard","edit click navigated away")
   mousePress(dot(0),12,16);mouseMove(dot(0),13,16,20)
   check(!header.draggingPage,"sub-threshold press began a drag")
   mouseRelease(dot(0),13,16);same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"small click changed order")
   const beforeChangedOrder=Array.from(canvas.effectivePageOrder)
   const changedSource=dot(0),changedTarget=dot(2)
   const changedPoint=changedTarget.mapToItem(changedSource,12,16)
   mousePress(changedSource,12,16);mouseMove(changedSource,changedPoint.x,changedPoint.y,20)
   check(header.draggingPage,"changed-order control never began its drag")
   canvas._draftPageOrder=["weeklyPlanner","music","dashboard"]
   check(!header.draggingPage,"actual changed order retained a stale drag")
   mouseRelease(changedSource,changedPoint.x,changedPoint.y)
   canvas._draftPageOrder=beforeChangedOrder
   drag(2,0,()=>{
    check(header.draggingPage && header.dragTarget===0,"real pointer failed drag threshold/target")
    canvas._draftPageOrder=Array.from(canvas.effectivePageOrder)
    check(header.draggingPage && header.dragPageId==="weeklyPlanner",
     "equal page-order republish cancelled a live pointer drag")
    check(findChild(dashboard,"dashboardTabDragGhost").visible && findChild(dashboard,"dashboardTabInsertion").visible,"drag feedback absent")
    same(Array.from(Config.options.dashboard.pageOrder),saved,"pointer preview wrote Config")
    same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"preview reordered before drop")
    frame("drag-preview")
   })
   same(dashboard.pageIds,["weeklyPlanner","dashboard","music"],"left drop selected wrong tab order")
   same(dashboard.currentPageId,"dashboard","drop changed selected tab identity")
   check(dashboard.currentPage===1 && findChild(dashboard,"dashboardPages").slideProgress===1,"content order or edit workspace did not follow tabs")
   same(Array.from(Config.options.dashboard.pageOrder),saved,"drop saved before Done")
   canvas.setWidgetVisible("clock",true)
   check(canvas.visibleIds.includes("clock"),"shared card edit failed")
   canvas.undoLastEdit();same(dashboard.pageIds,["weeklyPlanner","dashboard","music"],"card Undo reverted a different page edit")
   check(!canvas.visibleIds.includes("clock"),"card Undo missed widget state")
   canvas.undoLastEdit();same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"page Undo failed")
   check(JSON.stringify(Config.options.dashboard.canvas.widgets)===cards,"joint Undo wrote saved cards")
   drag(0,2)
   same(dashboard.pageIds,["music","weeklyPlanner","dashboard"],"right drop failed")
   canvas.resetLayout();same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"Reset did not restore last Done tab order")
   canvas.undoLastEdit();same(dashboard.pageIds,["music","weeklyPlanner","dashboard"],"Reset was not undoable")
   canvas.cancelEditMode();same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"Cancel leaked draft order")
   same(Array.from(Config.options.dashboard.pageOrder),saved,"Cancel saved a draft")
   canvas.beginEditMode();frame("")
   const first=dot(0),last=dot(2),end=last.mapToItem(first,12,16)
   mousePress(first,12,16);mouseMove(first,end.x,end.y,20);check(header.draggingPage,"cancel probe never started")
   keyClick(Qt.Key_Escape);check(!header.draggingPage && dashboard.editMode,"Escape closed editor instead of cancelling drag")
   mouseRelease(first,end.x,end.y);same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"cancelled drag applied on release")
   mousePress(first,12,16);mouseMove(first,-200,-100,20);mouseRelease(first,-200,-100)
   same(dashboard.pageIds,["dashboard","music","weeklyPlanner"],"outside drop changed order")
   mousePress(first,12,16);mouseMove(first,end.x,end.y,20)
   dashboard.presentationActive=false
   check(!dashboard.editMode && !header.draggingPage && !canvas.canUndo,"closing host retained page edit/ghost")
   mouseRelease(first,end.x,end.y)
   same(Array.from(Config.options.dashboard.pageOrder),saved,"closing host saved an unfinished drag")
   dashboard.presentationActive=true;canvas.beginEditMode();frame("")
   dot(2).forceActiveFocus();keyClick(Qt.Key_Left,Qt.AltModifier);frame("")
   same(dashboard.pageIds,["dashboard","weeklyPlanner","music"],"keyboard alternative failed")
   keyClick(Qt.Key_Left,Qt.AltModifier);frame("")
   same(dashboard.pageIds,["weeklyPlanner","dashboard","music"],"keyboard repeat lost moved tab focus")
   canvas.cancelEditMode()
   // A hidden page and future IDs keep their literal saved positions.
   Config.setNestedValues({"dashboard.pageOrder":["dashboard","future","music","weeklyPlanner"],"dashboard.music.enable":false})
   canvas.beginEditMode();frame("");drag(1,0)
   same(Array.from(canvas.effectivePageOrder),["weeklyPlanner","future","music","dashboard"],"hidden/future identities erased")
   same(dashboard.currentPageId,"dashboard","hidden-page reorder changed active identity")
   // A concurrent save must not be silently overwritten by the draft.
   Config.setNestedValue("dashboard.pageOrder",["music","dashboard","future","weeklyPlanner"])
   canvas.commitEditMode();check(canvas.editMode && canvas.layoutMessage.length>0,"concurrent tab save was overwritten")
   same(Array.from(Config.options.dashboard.pageOrder),["music","dashboard","future","weeklyPlanner"],"conflict mutated saved order")
   canvas.resetLayout();same(Array.from(canvas.effectivePageOrder),Array.from(Config.options.dashboard.pageOrder),"Reset did not accept current saved baseline")
   canvas.undoLastEdit();canvas.commitEditMode()
   check(canvas.editMode && canvas.layoutMessage.length>0,"Undo Reset lost the original conflict baseline")
   same(Array.from(Config.options.dashboard.pageOrder),["music","dashboard","future","weeklyPlanner"],"Undo Reset overwrote concurrent order")
   canvas.resetLayout()
   canvas.cancelEditMode()
   Config.setNestedValues({"dashboard.pageOrder":["dashboard","future","music","weeklyPlanner"],"dashboard.music.enable":true})
   canvas.beginEditMode();frame("");drag(2,0);canvas.commitEditMode();frame("done")
   check(!canvas.editMode && !header.draggingPage,"Done kept edit input/ghost alive")
   same(Array.from(Config.options.dashboard.pageOrder),["weeklyPlanner","future","dashboard","music"],"Done did not commit draft")
   check(Config.options.dashboard.pageOrderVersion===1,"Done did not version the saved order")
   canvas.beginEditMode();same(Array.from(canvas.effectivePageOrder),Array.from(Config.options.dashboard.pageOrder),"reopen lost last Done order");canvas.cancelEditMode()
   mouseClick(dot(0));same(dashboard.currentPageId,"weeklyPlanner","normal reordered dot opened wrong content")
   tryVerify(()=>findChild(dashboard,"dashboardWeeklyPlanner")!==null,3000)
   mouseClick(dot(1));same(dashboard.currentPageId,"dashboard","normal Dashboard dot opened wrong content")
   header.forceActiveFocus();keyClick(Qt.Key_Right);same(dashboard.currentPageId,"music","normal navigation ignored saved order")
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,3000)
   Config.setNestedValue("dashboard.music.enable",false)
   same(Array.from(Config.options.dashboard.pageOrder),["weeklyPlanner","future","dashboard","music"],"disable Music erased persisted order")
   Config.setNestedValue("dashboard.music.enable",true)
   tryVerify(()=>{
    disk.reload()
    const saved=disk.snapshot?.dashboard
    return JSON.stringify(saved?.pageOrder)===JSON.stringify(["weeklyPlanner","future","dashboard","music"])
     && saved?.pageOrderVersion===1 && saved?.music?.enable===true
   },5000)
   console.info("DASHBOARD_TAB_REORDER_NATIVE_PASS",checks,root.captures)
  }catch(error){console.error("DASHBOARD_TAB_REORDER_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
RESTART=r'''
import QtQuick
import Quickshell
import qs.modules.common
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 Timer {interval:100;running:true;repeat:true;onTriggered:{
  if(!Config.ready)return
  const order=Array.from(Config.options.dashboard.pageOrder)
  if(JSON.stringify(order)!==JSON.stringify(["weeklyPlanner","future","dashboard","music"]) || Config.options.dashboard.pageOrderVersion!==1)
   console.error("DASHBOARD_TAB_REORDER_RESTART_FAIL",JSON.stringify(order))
  else console.info("DASHBOARD_TAB_REORDER_RESTART_PASS")
  Qt.quit()
 }}
}
'''
with tempfile.TemporaryDirectory(prefix='alis-dashboard-tab-reorder-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(QML)
 with private_wayland(folder) as env:
  if not env:raise SystemExit('SKIP: Dashboard tab reorder needs private Niri')
  config=folder/'config/alis';config.mkdir(parents=True,exist_ok=True)
  raw=json.loads((ROOT/'defaults/config.json').read_text());raw['panelFamily']='abyss';raw['dashboard']['pageOrderVersion']=0;raw['dashboard']['pageOrder']=['dashboard','music']
  ids=['welcome','clock','system','github','notifications','todo','media','weather','calendar','agenda','notes']
  raw['dashboard']['canvas']['widgets']=[dict(id=item,x=.1,y=.1,w=.3,h=.3,visible=False) for item in ids]
  file=config/'config.json';file.write_text(json.dumps(raw))
  dest=Path(os.environ.get('ALIS_REORDER_EVIDENCE',folder/'evidence'));dest.mkdir(parents=True,exist_ok=True)
  env.update(REORDER_CAPTURES=str(dest),QSG_RENDER_LOOP='basic',QT_QUICK_BACKEND='software')
  result=run_qs(folder,env,timeout=40);(dest/'native.log').write_text(result.stdout)
  failures=['DASHBOARD_TAB_REORDER_NATIVE_FAIL','ReferenceError:','TypeError:','Binding loop','Unable to assign','Cannot assign to non-existent property','Failed to load configuration']
  if result.returncode or 'DASHBOARD_TAB_REORDER_NATIVE_PASS' not in result.stdout or any(word in result.stdout for word in failures):print(result.stdout);raise SystemExit(1)
  disk=json.loads(file.read_text());assert disk['dashboard']['pageOrder']==['weeklyPlanner','future','dashboard','music'];assert disk['dashboard']['pageOrderVersion']==1
  (dest/'disk.json').write_text(json.dumps(disk['dashboard'],indent=2)+'\n')
  (folder/'shell.qml').write_text(RESTART)
  restarted=run_qs(folder,dict(env,QT_QPA_PLATFORM='offscreen'),timeout=12);(dest/'restart.log').write_text(restarted.stdout)
  if restarted.returncode or 'DASHBOARD_TAB_REORDER_RESTART_PASS' not in restarted.stdout:print(restarted.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines()+restarted.stdout.splitlines():
   if '_PASS' in line:print(line)
