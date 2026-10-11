#!/usr/bin/env python3
"""Actual weekly grid, imports, slot activation, responsive tasks and notes."""
import json,os,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.dashboard
Window {
 id:root;visible:true;width:1180;height:740;color:"#111820"
 property real allocatedWidth:1180
 property real allocatedHeight:740
 property int calls:0
 property var last:null
 property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 QtObject {
  id:local;property var list:[]
  signal eventAdded(var event);signal eventUpdated(var event);signal eventRemoved(int id)
 }
 QtObject {id:external;property var events:[];signal eventsUpdated()}
 Item {
  id:scene;width:root.allocatedWidth;height:root.allocatedHeight
  Rectangle {anchors.fill:parent;color:Appearance.colors.colLayer0Base}
  DashboardWeeklyPlanner {
   id:planner;anchors.fill:parent;presentationActive:true;localBackend:local;externalBackend:external
   onRequestEventsDialog:event=>{root.calls++;root.last=event}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  property int checks:0
  function check(ok,message){checks++;if(!ok)throw new Error(message)}
  function find(item,name){if(item.objectName===name)return item;for(const child of item.children ?? []){const found=find(child,name);if(found)return found}return null}
  function all(item,name){let result=item.objectName===name?[item]:[];for(const child of item.children ?? [])result=result.concat(all(child,name));return result}
  function capture(name){const count=root.frames;check(scene.grabToImage(image=>{image.saveToFile(Quickshell.env("PLANNER_CAPTURES")+"/"+name+".png");root.frames++}),"capture refused");tryVerify(()=>root.frames>count,2500)}
  function run(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true})
   planner.selectedDate=new Date(2024,11,31,12);wait(100)
   check(planner.days.length===7,"missing day columns")
   check(planner.days.every(day=>day.timed.length===0 && day.allDay.length===0),"empty source created events")
   capture("empty")
   const day=planner.days[0].date
   function instant(hour){const date=new Date(day);date.setHours(Math.floor(hour),(hour%1)*60,0,0);return date.toISOString()}
   local.list=[{id:1,title:"Local morning",startDate:instant(9),endDate:instant(10)},
    {id:2,title:"Overlapping meeting",startDate:instant(9.5),endDate:instant(11)},
    {id:3,title:"All-day local",startDate:instant(0),endDate:new Date(day.getFullYear(),day.getMonth(),day.getDate()+2).toISOString(),allDay:true}]
   external.events=[{uid:"private-import",title:"Read-only import",startDate:instant(14),endDate:instant(15),color:"#65b8c4"}];external.eventsUpdated();wait(100)
   check(planner.days[0].timed.length===3 && planner.days[0].allDay.length===1 && planner.days[1].allDay.length===1,"source projection lost data")
   const viewport=find(planner,"weeklyPlannerViewport")
   viewport.contentY=12*planner.hourHeight;wait(50)
   const imported=all(planner,"plannerTimedEvent").find(item=>item.modelData.source==="external")
   const count=root.calls;mouseClick(imported,imported.width/2,imported.height/2);check(root.calls===count,"import opened a mutating editor")
   capture("import-read-only")
   viewport.contentY=8*planner.hourHeight;wait(50)
   check(planner.panHorizontally(-40)===false,"wide week consumed unnecessary horizontal navigation")
   const timed=all(planner,"plannerTimedEvent").find(item=>item.modelData.event.id===1)
   mouseClick(timed,timed.width/2,timed.height/2);check(root.calls===count+1 && root.last.id===1,"local event failed to open canonical editor")
   const slot=all(planner,"plannerCreateSlot")[2]
   mouseClick(slot,slot.width/2,planner.hourHeight*9.25);check(root.last.plannerDate instanceof Date && root.last.plannerDate.getHours()===9 && root.last.plannerDate.getMinutes()===15,"slot lost clicked date/time")
   capture("overlap-slots")
   const weekDate=planner.days[0].date.getTime();planner.changeWeek(1);check(planner.days[0].date.getTime()>weekDate,"Next week failed");planner.changeWeek(-1);check(planner.days[0].date.getTime()===weekDate,"Previous week failed")
   planner.forceActiveFocus();keyClick(Qt.Key_PageDown);check(planner.days[0].date.getTime()>weekDate,"keyboard week navigation failed");keyClick(Qt.Key_PageUp)
   root.allocatedWidth=480;root.allocatedHeight=410;wait(100)
   capture("narrow-resized")
   check(viewport.contentWidth>viewport.width && viewport.height>0,"narrow view clipped seven columns: "+JSON.stringify({scene:scene.width,planner:planner.width,viewport:viewport.width,content:viewport.contentWidth,height:viewport.height}))
   check(planner.panHorizontally(-40) && viewport.contentX===40,"narrow week failed to pan")
   viewport.contentX=viewport.contentWidth-viewport.width;capture("narrow-end-of-week")
   planner.sideView="todo";wait(150);check(find(planner,"plannerSharedSidePanel").item!==null,"shared Todo pane failed to load");check(viewport.height>=110 && find(planner,"plannerSharedSidePanel").height<=root.allocatedHeight*.4,"Todo removed the usable week viewport")
   capture("narrow-todo")
   planner.sideView="notes";wait(150);check(find(planner,"plannerSharedSidePanel").item!==null,"shared Quick Notes pane failed to load");check(viewport.height>=110 && find(planner,"plannerSharedSidePanel").height<=root.allocatedHeight*.4,"Notes removed the usable week viewport")
   capture("narrow-notes")
   planner.sideView="";root.allocatedWidth=1180;root.allocatedHeight=740;wait(100)
   planner.selectedDate=new Date(2024,2,10,12);wait(50)
   check(planner.days.some(day=>day.minutes===1380),"native spring week lost the 23-hour civil day")
   local.list=[{id:4,title:"Spring clock change",startDate:"2024-03-10T01:30:00-05:00",endDate:"2024-03-10T03:30:00-04:00"}];external.events=[];wait(50)
   const spring=planner.days.reduce((rows,day)=>rows.concat(day.timed),[])[0];check(spring.end-spring.start===60,"native spring duration changed");capture("spring-clock-change")
   planner.selectedDate=new Date(2024,10,3,12);local.list=[{id:5,title:"Repeated hour",startDate:"2024-11-03T01:30:00-04:00",endDate:"2024-11-03T01:30:00-05:00"}];wait(50)
   check(planner.maximumMinutes===1500,"native fall week lost the 25-hour civil day")
   const fall=planner.days.reduce((rows,day)=>rows.concat(day.timed),[])[0];check(fall.end-fall.start===60,"native repeated hour disappeared");capture("fall-clock-change")
   planner.showToday();check(planner.days.some(day=>Qt.formatDate(day.date,"yyyy-MM-dd")===Qt.formatDate(new Date(),"yyyy-MM-dd")),"Today navigation failed")
   console.info("WEEKLY_PLANNER_NATIVE_PASS",checks,root.frames)
  }catch(error){console.error("WEEKLY_PLANNER_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
with tempfile.TemporaryDirectory(prefix='alis-weekly-planner-') as name:
 folder=Path(name)
 for entry in ['modules','services','qmldir','GlobalStates.qml','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(QML)
 with private_wayland(folder) as env:
  if not env:print('SKIP: native weekly planner needs private Niri');raise SystemExit(0)
  config=folder/'config/illogical-impulse';config.mkdir(parents=True,exist_ok=True)
  raw=json.loads((ROOT/'defaults/config.json').read_text());raw['panelFamily']='abyss';(config/'config.json').write_text(json.dumps(raw))
  dest=Path(os.environ.get('ALIS_PLANNER_EVIDENCE',folder/'captures'));dest.mkdir(parents=True,exist_ok=True)
  env.update(PLANNER_CAPTURES=str(dest),QT_QUICK_BACKEND='software',TZ='America/New_York')
  result=run_qs(folder,env,timeout=40);(dest/'native.log').write_text(result.stdout)
  if result.returncode or 'WEEKLY_PLANNER_NATIVE_PASS' not in result.stdout or any(word in result.stdout for word in ['WEEKLY_PLANNER_NATIVE_FAIL','ReferenceError:','TypeError:','Binding loop','Failed to load configuration','Unable to assign']):print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if 'WEEKLY_PLANNER_NATIVE_PASS' in line:print(line)
