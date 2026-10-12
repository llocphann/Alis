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
   const dayHeaders=all(planner,"plannerDayHeader")
   const headerCorner=find(planner,"plannerHeaderCorner")
   check(dayHeaders.length===7 && !!headerCorner,"seven-day connected header surface missing")
   check(dayHeaders.every(item=>Math.abs(item.width-planner.columnWidth)<.5),
     "date/all-day header lost shared column geometry")
   check(dayHeaders.every(item=>String(item.color)===String(planner.headerSurface))
     && String(headerCorner.color)===String(planner.headerSurface),
     "day/all-day/corner do not share the timeline surface")
   check(planner.headerSurface.a===0,
     "the pinned date/All-day headings obscure the transparent timeline background")
   check(String(planner.headerInk)===String(planner.ink),
     "heading labels no longer use the timeline's text palette")
   // Heading centres are tested in toolbar space, not just in the space
   // between asymmetrically sized navigation and action groups.
   const toolbar=find(planner,"plannerToolbar")
   const weekHeading=find(planner,"plannerWeekHeading")
   const dayTitles=all(planner,"plannerDayTitle")
   check(!!toolbar && !!weekHeading && dayTitles.length===7,
     "weekly planner header labels missing")
   check(Math.abs(weekHeading.mapToItem(toolbar,weekHeading.width/2,weekHeading.height/2).x-toolbar.width/2)<1,
     "week title is not centred across the toolbar")
   check(weekHeading.horizontalAlignment===Text.AlignHCenter
     && weekHeading.font.weight===Font.Bold
     && String(weekHeading.color)===String(planner.headerTodayInk),
     "week title lost bold, centred theme-accent styling")
   check(dayTitles.every(item=>item.horizontalAlignment===Text.AlignHCenter
     && item.font.weight===Font.Bold
     && Math.abs(item.x+item.width/2-(item.parent.width/2))<1),
     "weekday titles must be bold and centred in their columns")
   for (const name of ["plannerPreviousWeek","plannerNextWeek","plannerTodoAction","plannerNotesAction"]) {
     const button=find(planner,name)
     check(!!button,"missing planner action "+name)
     const glyph=find(button.contentItem,"plannerActionGlyph")
     check(!!glyph && glyph.visible,"missing planner action glyph "+name)
     const middle=glyph.mapToItem(button,glyph.width/2,glyph.height/2)
     check(Math.abs(middle.x-button.width/2)<1 && Math.abs(middle.y-button.height/2)<1,
       "planner action glyph not centred: "+name)
   }
   viewport.contentY=12*planner.hourHeight;wait(50)
   check(dayHeaders.every(item=>Math.abs(item.y-viewport.contentY)<.5)
     && Math.abs(headerCorner.y-viewport.contentY)<.5,
     "header failed to remain pinned during time-axis scrolling")
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
   root.allocatedWidth=320;root.allocatedHeight=410;wait(100)
   const compactHeading=find(planner,"plannerCompactWeekHeading")
   check(!!compactHeading && compactHeading.visible && !weekHeading.visible,
     "compact toolbar must keep the week title visible on a second line")
   check(compactHeading.horizontalAlignment===Text.AlignHCenter
     && compactHeading.font.weight===Font.Bold,
     "compact week title lost centred bold styling")
   root.allocatedWidth=480;root.allocatedHeight=410;wait(100)
   capture("narrow-resized")
   check(viewport.contentWidth>viewport.width && viewport.height>0,"narrow view clipped seven columns: "+JSON.stringify({scene:scene.width,planner:planner.width,viewport:viewport.width,content:viewport.contentWidth,height:viewport.height}))
   check(planner.panHorizontally(-40) && viewport.contentX===40,"narrow week failed to pan")
   viewport.contentX=viewport.contentWidth-viewport.width;capture("narrow-end-of-week")
   planner.sideView="todo";wait(150);check(find(planner,"plannerSharedSidePanel").item!==null,"shared Todo pane failed to load");check(viewport.height>=110 && find(planner,"plannerSharedSidePanel").height<=root.allocatedHeight*.4,"Todo removed the usable week viewport")
   capture("narrow-todo")
   planner.sideView="notes";wait(150);check(find(planner,"plannerSharedSidePanel").item!==null,"shared Quick Notes pane failed to load");check(viewport.height>=110 && find(planner,"plannerSharedSidePanel").height<=root.allocatedHeight*.4,"Notes removed the usable week viewport")
   capture("narrow-notes")
   const slotDate=new Date(2024,11,31,9,15)
   planner.openInlineEventEditor({plannerDate:slotDate});wait(150)
   const inline=find(planner,"plannerInlineEventsEditor")
   check(planner.sideView==="events" && !!inline && inline.embeddedPresentation,
     "Planner did not open an embedded Events column")
   check(inline.show && inline.hideEmbeddedScrollBar,"embedded scrolling presentation lost")
   check(Qt.formatDate(inline.eventDate,"yyyy-MM-dd")==="2024-12-31"
       && inline.eventTime==="09:15" && inline.eventEndTime==="10:15",
     "clicked 09:15 slot lost local date or end-time prefill")
   check(!inline.hasUnsavedChanges(),"slot prefill was marked dirty before any edits")
   // Modifier selection is Add-only and exclusive with Repeat.
   const initialDate=Qt.formatDate(inline.eventDate,"yyyy-MM-dd")
   inline.choosePlannerDay(new Date(2025,0,3,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===2
       && inline.plannerSelectedDateKeys.includes(initialDate)
       && inline.plannerSelectedDateKeys.includes("2025-01-03"),
     "Ctrl+Click failed to add a second calendar day")
   inline.choosePlannerDay(new Date(2025,0,5,12),Qt.ShiftModifier)
   check(inline.plannerSelectedCount===3
       && inline.plannerSelectedDateKeys.includes("2025-01-04"),
     "Shift+Click failed to select the inclusive range")
   check(inline.hasUnsavedChanges(),"multi-day selection did not mark form dirty")
   const preservedDays=JSON.stringify(inline.plannerSelectedDateKeys)
   check(inline.plannerRepeatConflict && !inline.canSelectRepeat("weekly")
     && inline.canSelectRepeat("none"),
     "multi-date must keep Event enabled but disable recurring choices")
   const repeatChoices=find(inline,"plannerRepeatChoices")
   check(!!repeatChoices,"Planner Repeat selector missing")
   // Option models can replace their delegates when enabled flags change.
   function repeatItems() {
     return repeatChoices.children.filter(item=>item && item.modelData
       && item.modelData.value !== undefined)
   }
   wait(50)
   const disabledChoices=repeatItems()
   check(disabledChoices.length===5 && disabledChoices[0].enabled
     && disabledChoices.slice(1).every(item=>!item.enabled && item.opacity<.5),
     "conflicting Repeat buttons must be disabled and grey, not just ignored")
   inline.setRepeatOption("weekly")
   check(inline.recurrence==="none"
     && JSON.stringify(inline.plannerSelectedDateKeys)===preservedDays,
     "disabled Repeat selection erased selected days")
   inline.recurrence="monthly"
   check(inline.recurrence==="none"
     && JSON.stringify(inline.plannerSelectedDateKeys)===preservedDays,
     "invalid direct Repeat assignment erased selected days")
   inline.choosePlannerDay(new Date(2025,0,7,12),0)
   wait(50)
   const enabledChoices=repeatItems()
   check(inline.plannerSelectedCount===1 && !inline.plannerRepeatConflict
     && enabledChoices.length===5
     && enabledChoices.slice(1).every(item=>item.enabled && item.opacity===1),
     "returning to one day must restore all Repeat choices")
   inline.setRepeatOption("weekly")
   check(inline.recurrence==="weekly","Repeat should work with one day")
   const beforeBlocked=JSON.stringify(inline.plannerSelectedDateKeys)
   inline.choosePlannerDay(new Date(2025,0,8,12),Qt.ControlModifier)
   check(JSON.stringify(inline.plannerSelectedDateKeys)===beforeBlocked
     && inline.recurrence==="weekly",
     "multi-day selection while repeating must not mutate the form")
   inline.setRepeatOption("none")
   inline.choosePlannerDay(new Date(2025,0,8,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===2 && inline.recurrence==="none",
     "turning Repeat off must unlock explicit multi-day selection")
   inline.resetForm()
   inline.eventDate=slotDate
   inline.eventTime="09:15"
   inline.eventEndTime="10:15"
   inline.captureFormBaseline()
   check(!inline.hasUnsavedChanges(),
     "Reset after modifier tests failed to restore clean Add Event draft")
   inline.eventTitle="Unsaved private draft"
   check(inline.hasUnsavedChanges(),"unsaved title was not marked dirty")
   const priorWeek=planner.days[0].date.getTime()
   planner.forceActiveFocus();keyClick(Qt.Key_PageDown)
   check(planner.days[0].date.getTime()===priorWeek,
     "PageDown navigated the Planner behind an open Events form")
   planner.sideView="todo";wait(60)
   planner.sideView="events";wait(60)
   check(inline.eventTitle==="Unsaved private draft",
     "switching Events/Todo discarded the unsaved form")
   planner.openInlineEventEditor({plannerDate:new Date(2024,11,31,15,45)});wait(40)
   check(inline.eventTitle==="Unsaved private draft",
     "new slot silently replaced an unsaved event draft")
   check(inline.editorWarning.length>0 && inline.eventTime==="09:15",
     "guard failed to show Save/Cancel warning or preserved time")
   inline.dismiss();wait(50)
   check(planner.sideView==="" && !planner._inlineEventsLoaded,
     "Cancel did not dismiss the Events column")
   capture("narrow-inline-events")
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
