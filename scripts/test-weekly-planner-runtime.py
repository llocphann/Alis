#!/usr/bin/env python3
"""Actual weekly grid, imports, slot activation, responsive tasks and notes."""
import json,os,struct,tempfile,zlib
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
 property int presentedFrames:0
 onFrameSwapped:presentedFrames++
 Component.onCompleted:Quickshell.watchFiles=false
 QtObject {
  id:local;property var list:[]
  property int rescheduleCalls:0
  signal eventAdded(var event);signal eventUpdated(var event);signal eventRemoved(int id)
  // Private in-memory backend: pointer tests must never write owner Agenda.
  function rescheduleOccurrence(id,index,startIso,endIso,metadata) {
   const next=Array.from(list),at=next.findIndex(row=>row.id===id)
   if(at<0 || index!==0) return false
   const changed=Object.assign({},next[at],{startDate:startIso,endDate:endIso})
   next[at]=changed;list=next;rescheduleCalls++
   eventUpdated(changed)
   return true
  }
  property int virtualEditCalls:0
  function rescheduleProjectedRecurring(id,index,originalIso,startIso,endIso) {
   const next=Array.from(list),at=next.findIndex(row=>row.id===id)
   if(at<0 || index!==0 || next[at].recurrence!=="weekly") return false
   const changed=Object.assign({},next[at],{plannerOverrides:[{
    occurrenceIndex:index,originalStartDate:originalIso,
    startDate:startIso,endDate:endIso
   }]})
   next[at]=changed;list=next;virtualEditCalls++
   eventUpdated(changed)
   return true
  }
  property int groupEditCalls:0
  property var lastGroupOperations:[]
  function applyPlannerOccurrenceBatch(operations) {
   // The native fixture is private and in-memory: emulate one atomic
   // persistent writer without touching the real owner's Events.
   if(!operations || !operations.length) return false
   const next=list.map(event=>Object.assign({},event))
   const touched=new Set()
   for(const op of operations) {
    const index=next.findIndex(event=>event.id===op.id)
    if(index<0 || op.remove===true) return false
    const record=next[index]
    if(op.recurring && op.originalStartIso) {
     const current=record.plannerOverrides || []
     record.plannerOverrides=current.concat([{
      occurrenceIndex:op.occurrenceIndex,originalStartDate:op.originalStartIso,
      startDate:op.startIso,endDate:op.endIso
     }])
    } else if(record.occurrences && op.occurrenceIndex>=0
            && op.occurrenceIndex<record.occurrences.length) {
     const slots=record.occurrences.slice()
     slots[op.occurrenceIndex]=Object.assign({},slots[op.occurrenceIndex],{
      startDate:op.startIso,endDate:op.endIso,
      plannerSeriesStartDate:slots[op.occurrenceIndex].plannerSeriesStartDate
       || slots[op.occurrenceIndex].startDate,
      plannerSeriesEndDate:slots[op.occurrenceIndex].plannerSeriesEndDate
       || slots[op.occurrenceIndex].endDate
     })
     record.occurrences=slots
    } else return false
    touched.add(op.id)
   }
   list=next;groupEditCalls++;lastGroupOperations=operations
   for(const id of touched) eventUpdated(next.find(row=>row.id===id))
   return true
  }
  property int recurringEditCalls:0
  function rescheduleRecurringOccurrence(id,index,startIso,endIso) {
   const next=Array.from(list),at=next.findIndex(row=>row.id===id)
   if(at<0 || index!==0 || next[at].recurrence!=="weekly") return false
   const original=next[at]
   const changed=Object.assign({},original,{
    startDate:startIso,dateTime:startIso,endDate:endIso,
    plannerSeriesStartDate:original.plannerSeriesStartDate || original.startDate,
    plannerSeriesEndDate:original.plannerSeriesEndDate || original.endDate
   })
   next[at]=changed;list=next;recurringEditCalls++
   eventUpdated(changed)
   return true
  }
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
  function capture(name){
   // A settled layout need not produce another frame on an idle Wayland
   // window. Request one explicitly, then wait for the actual presentation;
   // windowShown belongs to QtTest's runner and stays false in Quickshell.
   if(!waitForPolish(root,2500))throw new Error(name+": window layout polish deadline")
   const presented=root.presentedFrames
   root.update()
   try {tryVerify(()=>root.presentedFrames>presented,2500,name+": presentation deadline")}
   catch(error){throw new Error(name+": presentation deadline "+JSON.stringify({
    before:presented,after:root.presentedFrames,visible:root.visible,active:root.active,
    width:root.width,height:root.height,sceneVisible:scene.visible}))}
   const count=root.frames
   let finished=false,saved=false
   check(scene.grabToImage(image=>{
    saved=image.saveToFile(Quickshell.env("PLANNER_CAPTURES")+"/"+name+".png")
    if(saved)root.frames++
    finished=true
   }),name+": capture refused")
   root.update()
   try {tryVerify(()=>finished,2500,name+": capture callback deadline")}
   catch(error){throw new Error(name+": capture callback deadline; presented="
     +root.presentedFrames+", saved="+root.frames)}
   check(saved,name+": PNG write failed")
   check(root.frames===count+1,name+": capture did not settle exactly once")
  }
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
   // Owner-critical interactions: simulate real Qt pointer presses/moves/releases
   // on a private, in-memory one-off event. Never write user calendar data.
   function timeOf(id,key) {
    return new Date(local.list.find(row=>row.id===id)[key]).getTime()
   }
   function dragPointer(area,deltaY) {
    check(!!area,"missing gesture hit area")
    // Real pointer input must start inside the fitted viewport, including
    // the bottom handle after a preceding downward group move.
    const point=area.mapToItem(viewport.contentItem,0,0)
    if(point.y-viewport.contentY+area.height+Math.max(0,deltaY)>viewport.height-12)
     viewport.contentY=Math.min(viewport.contentHeight-viewport.height,
       Math.max(0,point.y+area.height+Math.max(0,deltaY)-viewport.height+32))
    waitForPolish(root,2500)
    const presented=root.presentedFrames;root.update()
    tryVerify(()=>root.presentedFrames>presented,2500)
    const screen=area.mapToItem(scene,area.width/2,area.height/2)
    check(screen.y>=0 && screen.y+Math.max(0,deltaY)<scene.height,
      "gesture hit area is outside the presented viewport")
    const x=area.width/2,y=area.height/2
    mousePress(area,x,y,Qt.LeftButton)
    mouseMove(area,x,y+deltaY,80)
    mouseRelease(area,x,y+deltaY,Qt.LeftButton)
    wait(50)
   }
   function eventOne() {
    return all(planner,"plannerTimedEvent").find(item=>item.modelData.event.id===1)
   }
   let movedCard=eventOne()
   check(!!movedCard && movedCard.canReschedule,"one-off event lost gesture eligibility")
   check(!!find(movedCard,"plannerResizeStart")?.visible &&
     !!find(movedCard,"plannerResizeEnd")?.visible,"resize grips no longer visible")
   const resizeBars=["plannerResizeStart","plannerResizeEnd"].map(name=>
     find(movedCard,name).children.find(child=>child.height===2))
   const expectedGrip=String(Qt.lighter(movedCard.eventAccent,1.20))
   check(resizeBars.every(bar=>!!bar && String(bar.color)===expectedGrip),
     "top and bottom resize bars must match the owner Event ID swatch")
   const anotherEvent=all(planner,"plannerTimedEvent").find(item=>
     item.modelData.event.id===2)
   check(!!anotherEvent && String(anotherEvent.eventAccent)!==String(movedCard.eventAccent),
     "two independent Events unexpectedly received the same curated color")
   const otherGrip=find(anotherEvent,"plannerResizeStart").children.find(
     child=>child.height===2)
   check(!!otherGrip && String(otherGrip.color)
     ===String(Qt.lighter(anotherEvent.eventAccent,1.20)),
     "resize handle copied a different Event's accent")
   mouseMove(scene,2,2);wait(160)
   check(!movedCard.showResizeHandles && resizeBars.every(bar=>bar && bar.opacity===0),
     "idle event must hide both bars without disabling resize hit regions")
   mouseMove(movedCard,movedCard.width/2,movedCard.height/2);wait(160)
   check(movedCard.showResizeHandles && resizeBars.every(bar=>bar.opacity>0),
     "hover must reveal both bars on the pointed event")
   check(all(planner,"plannerTimedEvent").filter(item=>item!==movedCard)
     .every(item=>!item.showResizeHandles),"hover leaked resize bars to another event")
   mouseMove(scene,2,2);wait(160)
   check(!movedCard.showResizeHandles && resizeBars.every(bar=>bar.opacity===0),
     "leaving an event must hide both bars again")
   const slotStep=planner.hourHeight/4
   const originalStart=timeOf(1,"startDate"),originalEnd=timeOf(1,"endDate")
   dragPointer(find(movedCard,"plannerEventMoveArea"),slotStep)
   check(local.rescheduleCalls===1 && timeOf(1,"startDate")===originalStart+15*60000
      && timeOf(1,"endDate")===originalEnd+15*60000,
      "body drag must move both endpoints by 15 minutes")
   movedCard=eventOne()
   check(String(find(movedCard,"plannerResizeStart").children.find(
     child=>child.height===2).color)===expectedGrip,
     "moving the Event changed its resize bar color")
   dragPointer(find(movedCard,"plannerResizeStart"),slotStep)
   check(local.rescheduleCalls===2 && timeOf(1,"startDate")===originalStart+30*60000
      && timeOf(1,"endDate")===originalEnd+15*60000,
      "top grip must resize only event start")
   movedCard=eventOne()
   dragPointer(find(movedCard,"plannerResizeEnd"),slotStep)
   check(local.rescheduleCalls===3 && timeOf(1,"startDate")===originalStart+30*60000
      && timeOf(1,"endDate")===originalEnd+30*60000,
      "bottom grip must resize only event end")
   check(root.calls===count+2,"drag/resize opened the Event editor")
   // Legacy saved weekly Events have no occurrences/repeatTemplate array.
   // Qt must route their actual pointer gestures to a single-instance
   // update, without opening the event editor or changing recurrence type.
   const legacy={id:88,title:"Old weekly event",
    startDate:instant(12),dateTime:instant(12),endDate:instant(13),
    recurrence:"weekly",notified:false}
   local.list=local.list.concat([legacy]);local.eventAdded(legacy);wait(80)
   function legacyCard() {
    return all(planner,"plannerTimedEvent").find(item=>item.modelData.event.id===88
      && !item.modelData.virtual)
   }
   let oldCard=legacyCard()
   check(!!oldCard && oldCard.canReschedule && !!find(oldCard,"plannerResizeStart")?.visible,
     "legacy persisted Weekly Event must expose move and resize")
   const originalSwatch=String(oldCard.eventAccent)
   check(originalSwatch===String(planner.eventIdentityColor({
     source:"local",event:{id:88,title:"Completely renamed",recurrence:"none",
       startDate:"2030-01-01T00:00:00Z"}})),
     "same ID changed color when event title/time/recurrence changed")
   check(originalSwatch!==String(planner.eventIdentityColor({
     source:"local",event:{id:89,title:"Old weekly event",recurrence:"weekly",
       startDate:legacy.startDate}})),
     "different Event IDs share the same color")
   const oldStart=new Date(legacy.startDate).getTime()
   dragPointer(find(oldCard,"plannerEventMoveArea"),slotStep)
   check(local.recurringEditCalls===1 && new Date(local.list.find(e=>e.id===88).startDate).getTime()
     ===oldStart+15*60000,"legacy body dragging did not reach recurring controller")
   oldCard=legacyCard()
   check(String(oldCard.eventAccent)===originalSwatch,
     "dragging a saved Event changed its ID color")
   // The preceding body move added 15 minutes to both endpoints; bottom
   // resize adds another 15 to the end, for 30 total against the original.
   dragPointer(find(oldCard,"plannerResizeEnd"),slotStep)
   check(local.recurringEditCalls===2 && new Date(local.list.find(e=>e.id===88).endDate).getTime()
     ===new Date(legacy.endDate).getTime()+30*60000,
     "legacy weekly bottom resize was lost")
   check(local.list.find(e=>e.id===88).plannerSeriesStartDate===legacy.startDate
     && local.list.find(e=>e.id===88).recurrence==="weekly",
     "legacy drag must not rewrite the repeating schedule")
   const weekDate=planner.days[0].date.getTime()
   planner.changeWeek(1);wait(80)
   check(planner.days[0].date.getTime()>weekDate,"Next week failed")
   const virtualCard=all(planner,"plannerTimedEvent").find(item=>item.modelData.event.id===88
     && item.modelData.virtual)
   check(!!virtualCard && virtualCard.canReschedule
     && !!virtualCard.modelData.plannerOriginalStartIso,
     "projected old Weekly Event still missing drag/resize")
   check(String(virtualCard.eventAccent)===originalSwatch,
     "next week's virtual occurrence of the same Event ID changed color")
   const virtualOriginal=virtualCard.modelData.plannerOriginalStartIso
   dragPointer(find(virtualCard,"plannerResizeEnd"),slotStep)
   check(local.virtualEditCalls===1 && local.list.find(e=>e.id===88)
     .plannerOverrides[0].originalStartDate===virtualOriginal,
     "projected old weekly resize must persist only the specific exception")
   planner.changeWeek(-1)
   check(planner.days[0].date.getTime()===weekDate,"Previous week failed")
   planner.forceActiveFocus();keyClick(Qt.Key_PageDown);check(planner.days[0].date.getTime()>weekDate,"keyboard week navigation failed");keyClick(Qt.Key_PageUp)
   root.allocatedWidth=320;root.allocatedHeight=410;wait(100)
   const compactHeading=find(planner,"plannerCompactWeekHeading")
   // Item-only polishing misses a queued descendant Layout. A private
   // nested window reproduced planner.width=320 with toolbar.width=1180.
   // Await the window's layout pass and a real frame before judging reflow.
   if(!waitForPolish(root,2500))throw new Error("compact toolbar: window polish deadline")
   const compactFrame=root.presentedFrames
   root.update()
   tryVerify(()=>root.presentedFrames>compactFrame,2500,"compact toolbar: presentation deadline")
   tryCompare(toolbar,"width",root.allocatedWidth,2500,"compact toolbar: layout width deadline")
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
   // Multi-day eligibility follows a civil calendar hierarchy; the
   // selection must survive both page changes and Repeat interactions.
   const initialDate=Qt.formatDate(inline.eventDate,"yyyy-MM-dd")
   inline.choosePlannerDay(new Date(2025,0,3,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===2
       && inline.plannerSelectedDateKeys.includes(initialDate)
       && inline.plannerSelectedDateKeys.includes("2025-01-03"),
     "Ctrl+Click failed to add a second calendar day")
   // 31 Dec 2024 and 3 Jan 2025 share an ISO week but not month/year.
   check(inline.canSelectRepeat("weekly")
       && !inline.canSelectRepeat("monthly")
       && !inline.canSelectRepeat("yearly"),
     "weekly cross-year boundary eligibility is incorrect")
   inline.choosePlannerDay(new Date(2025,0,5,12),Qt.ShiftModifier)
   check(inline.plannerSelectedCount===3
       && inline.plannerSelectedDateKeys.includes("2025-01-04"),
     "Shift+Click failed to select inclusive days")
   check(inline.hasUnsavedChanges(),"multi-day selection did not mark form dirty")
   const repeatChoices=find(inline,"plannerRepeatChoices")
   check(!!repeatChoices,"Repeat selector missing")
   function repeatItems() {
     return repeatChoices.children.filter(item=>item && item.modelData
       && item.modelData.value !== undefined)
   }
   wait(50)
   let options=repeatItems()
   check(options.length===5 && options[0].enabled && !options[1].enabled
       && options[1].opacity<.5 && options.slice(2).every(item=>item.enabled),
     "same-week dates must gray only Daily")
   const picked=JSON.stringify(inline.plannerSelectedDateKeys)
   inline.setRepeatOption("weekly")
   check(inline.recurrence==="weekly"
       && JSON.stringify(inline.plannerSelectedDateKeys)===picked,
     "compatible Weekly must retain all chosen dates")
   inline.choosePlannerDay(new Date(2025,0,7,12),Qt.ControlModifier)
   check(JSON.stringify(inline.plannerSelectedDateKeys)===picked
       && inline.recurrence==="weekly",
     "incompatible day must not erase Weekly selection or cadence")
   inline.setRepeatOption("monthly")
   inline.choosePlannerDay(new Date(2025,0,7,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===4
       && !inline.canSelectRepeat("weekly")
       && inline.canSelectRepeat("monthly")
       && inline.canSelectRepeat("yearly"),
     "different weeks within month must permit Monthly/Yearly only")
   wait(50)
   options=repeatItems()
   check(options.length===5 && !options[1].enabled && !options[2].enabled
       && options[3].enabled && options[4].enabled,
     "different weeks were not reflected in Repeat button states")
   inline.setRepeatOption("yearly")
   inline.choosePlannerDay(new Date(2025,1,2,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===5 && inline.recurrence==="yearly"
       && !inline.canSelectRepeat("monthly") && inline.canSelectRepeat("yearly"),
     "different months in one year must still permit Yearly")
   const yearDraft=JSON.stringify(inline.plannerSelectedDateKeys)
   inline.choosePlannerDay(new Date(2026,0,2,12),Qt.ControlModifier)
   check(JSON.stringify(inline.plannerSelectedDateKeys)===yearDraft
       && inline.recurrence==="yearly",
     "different years must reject an incompatible Yearly selection")
   inline.setRepeatOption("none")
   inline.choosePlannerDay(new Date(2026,0,2,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===6 && !inline.canSelectRepeat("yearly"),
     "Event with different years must gray Yearly")
   inline.choosePlannerDay(new Date(2025,0,7,12),0)
   wait(50)
   options=repeatItems()
   check(inline.plannerSelectedCount===1
       && options.length===5 && options.every(item=>item.enabled),
     "returning to a single day must re-enable all repeat options")
   // Clicking any occurrence must restore the complete Event ID.
   const firstStart=new Date(2024,11,31,9,15)
   const secondStart=new Date(2025,0,2,9,15)
   const firstEnd=new Date(firstStart.getTime()+3600000)
   const secondEnd=new Date(secondStart.getTime()+3600000)
   const originalGroup=[
     {startDate:firstStart.toISOString(),endDate:firstEnd.toISOString()},
     {startDate:secondStart.toISOString(),endDate:secondEnd.toISOString()}
   ]
   inline.loadEvent({
     id:785,title:"Wake up Tuesday and Thursday",recurrence:"weekly",
     allDay:false,category:"general",priority:"normal",reminderMinutes:15,
     occurrences:originalGroup.map(slot=>Object.assign({},slot,{notified:false})),
     repeatTemplate:originalGroup,repeatCycleStart:0,_editOccurrenceIndex:1
   })
   check(inline.editingEvent.id===785 && inline.isEditing,
     "clicking occurrence did not open owning Event ID")
   check(JSON.stringify(inline.plannerSelectedDateKeys)===
       JSON.stringify(["2024-12-31","2025-01-02"]),
     "calendar did not restore both Tuesday and Thursday dates")
   check(inline.plannerSelectedCount===2 && inline.recurrence==="weekly"
       && inline.canSelectRepeat("weekly") && !inline.canSelectRepeat("daily"),
     "restored two-day weekly cadence was not eligible")
   check(!inline.hasUnsavedChanges(),
     "opening grouped Event ID marked an unchanged draft dirty")
   inline.choosePlannerDay(new Date(2025,0,2,12),Qt.ControlModifier)
   check(inline.plannerSelectedCount===1 && inline.isEditing,
     "editing an Event ID cannot adjust the full date selection")
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
   // DASH-I13: match the reported four weekly groups without reading a
   // personal calendar. Verify actual cards, not only the projection array.
   planner.followToday=false;planner.selectedDate=new Date(2032,9,14,12)
   function recurringSlot(day,hour,notified){
     const start=new Date(2032,9,day,hour,30)
     return {startDate:start.toISOString(),
       endDate:new Date(start.getTime()+90*60000).toISOString(),notified:notified}
   }
   const patterns=[[13,15,18],[14,16,17],[15,17,15],[14,17,17]]
   const recurring=patterns.map((dates,index)=>{
     const slots=[recurringSlot(dates[0],dates[2],true),recurringSlot(dates[1],dates[2],true),
       recurringSlot(dates[0]+7,dates[2],false),recurringSlot(dates[1]+7,dates[2],false)]
     return {id:100+index,title:"Recurring fixture "+index,recurrence:"weekly",
       occurrences:slots,repeatTemplate:slots.slice(0,2).map(value=>({
         startDate:value.startDate,endDate:value.endDate})),repeatCycleStart:2}
   })
   local.list=recurring;external.events=[];wait(100)
   // Clicking a saved Event selects ALL visible occurrences under its
   // stable Event ID. Ctrl-click deselects only one tile from that group.
   // There is no redundant Edit-to-delete control on repeating selections.
   const recurringBefore=JSON.stringify(local.list)
   const recurringRow=planner.selectableEventRows.find(row=>row.event.id===100)
   check(!!recurringRow,"recurring row missing from Qt Planner selection")
   const groupCount=planner.selectableEventRows.filter(row=>row.event.id===100).length
   check(groupCount>=2,"fixture needs at least two saved dates under one ID")
   planner.clickPlannerEvent(recurringRow,Qt.NoModifier);wait(60)
   check(planner.selectedEventRows.length===groupCount
      && planner.selectedEventRows.every(row=>row.event.id===100),
      "click highlighted a recurring ID group without selecting all its dates")
   const recurringAction=find(planner,"plannerDeleteSelected")
   check(!!recurringAction && !recurringAction.visible && !planner.canDeleteSelection,
     "recurring group must not have Delete or Edit-to-delete shortcut")
   planner.clickPlannerEvent(recurringRow,Qt.ControlModifier);wait(60)
   check(planner.selectedEventRows.length===groupCount-1
      && !planner.isEventSelected(recurringRow)
      && planner.selectedEventRows.every(row=>row.event.id===100),
     "Ctrl-click must remove only that one selected recurring tile")
   const member=planner.selectedEventRows[0]
   check(planner.gestureTargets(member).length===groupCount-1,
     "group gesture includes a Ctrl-deselected recurring occurrence")
   planner.clickPlannerEvent(recurringRow,Qt.ControlModifier);wait(60)
   check(planner.selectedEventRows.length===groupCount,
     "Ctrl-click failed to restore a single deselected occurrence")
   // Move/resize a clicked group and require the real pointer path to
   // dispatch ALL selected dates through the one atomic in-memory writer.
   const groupCard=all(planner,"plannerTimedEvent").find(item=>
     item.modelData.event.id===100 && item.modelData.occurrenceIndex===
      recurringRow.occurrenceIndex && !item.modelData.virtual)
   check(!!groupCard && !!find(groupCard,"plannerEventMoveArea"),
     "source card lost the body pointer owner")
   const beforeSlots=local.list.find(e=>e.id===100).occurrences.map(
     entry=>({startDate:entry.startDate,endDate:entry.endDate}))
   dragPointer(find(groupCard,"plannerEventMoveArea"),slotStep)
   check(local.groupEditCalls===1 && local.lastGroupOperations.length===groupCount,
     "dragging a selected recurring ID still moved only one occurrence")
   const afterMove=local.list.find(e=>e.id===100).occurrences
   const movedIndexes=new Set(local.lastGroupOperations.map(op=>op.occurrenceIndex))
   check(local.lastGroupOperations.every(op=>op.id===100 && op.recurring),
     "group update included another Event ID or lost recurrence guard")
   check([...movedIndexes].every(i=>new Date(afterMove[i].startDate).getTime()
      ===new Date(beforeSlots[i].startDate).getTime()+15*60000),
     "drag failed to move all saved dates in the ID group")
   check(local.list.find(e=>e.id===100).repeatTemplate.length===2,
     "group drag must not rewrite the repeat template")
   check(planner.selectedEventKeys.length===0,
     "successful group drag left stale selection")
   // Re-select that same ID and resize all saved instances as one gesture.
   const groupAgain=planner.selectableEventRows.find(row=>row.event.id===100)
   planner.clickPlannerEvent(groupAgain,Qt.NoModifier);wait(40)
   const resizeCard=all(planner,"plannerTimedEvent").find(item=>
     item.modelData.event.id===100 && item.modelData.occurrenceIndex===
       groupAgain.occurrenceIndex && !item.modelData.virtual)
   dragPointer(find(resizeCard,"plannerResizeEnd"),slotStep)
   check(local.groupEditCalls===2 && local.lastGroupOperations.length===groupCount,
     "bottom resize committed only one selected ID-group occurrence")
   const finalSlots=local.list.find(e=>e.id===100).occurrences
   check(local.lastGroupOperations.every(op=>
     new Date(finalSlots[op.occurrenceIndex].endDate).getTime()
       ===new Date(afterMove[op.occurrenceIndex].endDate).getTime()+15*60000),
     "bottom resize did not lengthen every selected occurrence")
   check(recurringBefore!==JSON.stringify(local.list),
     "private fixture did not exercise a real group state transition")
   function verifyRecurringWeek(label){
     const rows=planner.days.reduce((result,day)=>result.concat(day.timed),[])
     const cards=all(planner,"plannerTimedEvent")
     check(rows.length===8,label+": projected recurring dates missing")
     check(cards.length===8,label+": rendered recurring cards missing")
     check(cards.every(card=>card.visible && card.width>0 && card.height>0),
       label+": recurring card has no visible geometry")
     check(cards.every(card=>card.modelData.startDate>=planner.days[0].date
       && card.modelData.startDate<planner.days[6].end),label+": stale card date")
   }
   verifyRecurringWeek("history")
   planner.changeWeek(1);wait(100);verifyRecurringWeek("next week")
   viewport.contentY=14*planner.hourHeight;capture("recurring-next-week")
   planner.changeWeek(1);wait(100);verifyRecurringWeek("projected week")
   planner.changeWeek(-2);wait(100);verifyRecurringWeek("return to history")
   local.list=[];wait(60)
   check(all(planner,"plannerTimedEvent").length===0,"empty source retained cards")
   planner.changeWeek(1);local.list=recurring;wait(100)
   verifyRecurringWeek("late source load")
   planner.presentationActive=false;wait(30);planner.presentationActive=true;wait(100)
   verifyRecurringWeek("reopened")
   planner.showToday();check(planner.days.some(day=>Qt.formatDate(day.date,"yyyy-MM-dd")===Qt.formatDate(new Date(),"yyyy-MM-dd")),"Today navigation failed")
   // Reactivation on the same calendar day must not rebuild the week.
   let redundantDates=0
   const countDateChanges=()=>redundantDates++
   planner.selectedDateChanged.connect(countDateChanges)
   planner.presentationActive=false;wait(30)
   planner.presentationActive=true;wait(100)
   planner.selectedDateChanged.disconnect(countDateChanges)
   check(redundantDates===0,"same-day Planner reactivation rebuilt the week")
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
 # Captures need a presented private output even inside another compositor.
 # The helper identifies only its own Niri window and restores prior focus;
 # a user changing focus takes precedence over the restoration.
 with private_wayland(folder,capture_focus=True) as env:
  if not env:print('SKIP: native weekly planner needs private Niri');raise SystemExit(0)
  config=folder/'config/alis';config.mkdir(parents=True,exist_ok=True)
  raw=json.loads((ROOT/'defaults/config.json').read_text());raw['panelFamily']='abyss';(config/'config.json').write_text(json.dumps(raw))
  dest=Path(os.environ.get('ALIS_PLANNER_EVIDENCE',folder/'captures'));dest.mkdir(parents=True,exist_ok=True)
  env.update(PLANNER_CAPTURES=str(dest),QT_QUICK_BACKEND='software',TZ='America/New_York')
  result=run_qs(folder,env,timeout=40);(dest/'native.log').write_text(result.stdout)
  if result.returncode or 'WEEKLY_PLANNER_NATIVE_PASS' not in result.stdout or any(word in result.stdout for word in ['WEEKLY_PLANNER_NATIVE_FAIL','ReferenceError:','TypeError:','Binding loop','Failed to load configuration','Unable to assign']):print(result.stdout);raise SystemExit(1)
  captures=['empty','import-read-only','overlap-slots','narrow-resized',
    'narrow-end-of-week','narrow-todo','narrow-notes','narrow-inline-events',
    'spring-clock-change','fall-clock-change','recurring-next-week']
  # Check complete PNGs, not just a callback counter or an old file count.
  # This also catches failed/truncated writes after a successful Qt request.
  for capture in captures:
   data=(dest/(capture+'.png')).read_bytes()
   assert data[:8]==b'\x89PNG\r\n\x1a\n',capture+': invalid PNG signature'
   offset=8;compressed=bytearray();size=None;ended=False
   while offset<len(data):
    length=struct.unpack_from('>I',data,offset)[0]
    kind=data[offset+4:offset+8];payload=data[offset+8:offset+8+length]
    assert len(payload)==length and offset+12+length<=len(data),capture+': truncated PNG'
    crc=struct.unpack_from('>I',data,offset+8+length)[0]
    assert zlib.crc32(kind+payload)==crc,capture+': PNG checksum mismatch'
    if kind==b'IHDR':size=struct.unpack_from('>II',payload)
    if kind==b'IDAT':compressed.extend(payload)
    offset+=12+length
    if kind==b'IEND':ended=True;break
   assert ended and offset==len(data) and size and min(size)>0,capture+': incomplete PNG'
   assert zlib.decompress(compressed),capture+': empty PNG pixels'
  print('WEEKLY_PLANNER_PNG_PASS',len(captures))
  for line in result.stdout.splitlines():
   if 'WEEKLY_PLANNER_NATIVE_PASS' in line:print(line)
