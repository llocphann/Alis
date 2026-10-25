#!/usr/bin/env python3
"""Real Qt pointer gestures + Events save/restart, using synthetic private JSON."""
import json
import os
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(os.environ.get("ALIS_PLANNER_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.dashboard
Window {
 id: root; visible: true; width: 1180; height: 780; color: "#111820"
 Component.onCompleted: Quickshell.watchFiles=false
 DashboardWeeklyPlanner { id: planner; anchors.fill: parent; localBackend: Events
  externalBackend: QtObject { property var events: []; signal eventsUpdated() }
 }
 TestCase {
  id: test; when: false; optional: true
  property int checks: 0
  function check(ok,msg) { checks++; if(!ok) throw new Error(msg) }
  function all(item,name) { let out=item.objectName===name?[item]:[];
   for(const c of item.children ?? [])out=out.concat(all(c,name));return out }
  function first(item,name) { return all(item,name)[0] }
  function cards() { return all(planner,"plannerTimedEvent") }
  function card(id,index=0) { return cards().find(c=>c.modelData.event.id===id
   && c.modelData.occurrenceIndex===index) }
  function settle() { tryVerify(()=>!Events.persistenceBusy,4000);wait(40) }
  function held(item,dx,dy) {
   const p=item.mapToItem(planner,item.width/2,item.height/2)
   mousePress(planner,p.x,p.y,Qt.LeftButton)
   mouseMove(planner,p.x+dx,p.y+dy,80)
   wait(40);return {x:p.x+dx,y:p.y+dy}
  }
  function drag(id,index,areaName,mode,dx,dy,cancel=false) {
   const target=card(id,index);check(!!target && target.canReschedule,"missing eligible multi-date card "+id
     +" date="+planner.selectedDate.toISOString()+" cards="+JSON.stringify(cards().map(c=>({
       id:c.modelData.event.id,index:c.modelData.occurrenceIndex,eligible:c.canReschedule,
       integer:Number.isInteger(c.modelData.occurrenceIndex),source:c.modelData.source,
       virtual:c.modelData.virtual,event:c.modelData.event}))))
   const before=JSON.stringify(Events.list),durable=JSON.stringify(Events.getDurableEvents())
   // Plain drag now owns the visible ID group. Explicitly Ctrl-select one
   // occurrence to retain the original isolated-instance pointer oracle.
   planner.clearEventSelection()
   mouseClick(first(target,"plannerEventMoveArea"),target.width/2,20,
    Qt.LeftButton,Qt.ControlModifier)
   check(planner.selectedEventRows.length===1
    && planner.selectedEventRows[0].occurrenceIndex===index,"Ctrl single selection lost")
   const p=held(first(target,areaName),dx,dy)
   check(target.gestureMoved && target.effectiveMode===mode,"pointer did not start "+mode)
   check(cards().filter(c=>c.effectiveMode.length>0).length===1,
     "drag preview leaked to another event/slot/cycle")
   check(JSON.stringify(Events.list)===before && JSON.stringify(Events.getDurableEvents())===durable,
     "gesture wrote before release")
   if(cancel)target.cancelGesture()
   mouseRelease(planner,p.x,p.y,Qt.LeftButton);settle()
   check(cards().every(c=>c.effectiveMode.length===0),"stale preview after release/cancel")
   if(cancel)check(JSON.stringify(Events.list)===before,"Cancel changed stored event")
  }
  function run() { try {
   tryCompare(Config,"ready",true,5000);tryCompare(Events,"ready",true,5000)
   check(Events.filePath===Quickshell.env("ALIS_PLANNER_TEST_EVENTS"),"escaped private store")
   Config.setNestedValues({"panelFamily":Quickshell.env("PLANNER_PANEL_FAMILY") || "abyss",
     "performance.reduceAnimations":true})
   planner.followToday=false;planner.selectedDate=new Date('2032-10-19T12:00:00Z');wait(100)
   const viewport=first(planner,"weeklyPlannerViewport");viewport.contentY=3*planner.hourHeight
   const phase=Quickshell.env("PLANNER_EDIT_PHASE")
   if(phase==="interrupted") {
    const durable=JSON.stringify(Events.getDurableEvents())
    held(first(card(401),"plannerEventMoveArea"),0,planner.hourHeight/4)
    check(JSON.stringify(Events.getDurableEvents())===durable && !Events.persistenceBusy,
      "interrupted gesture wrote before release")
    console.info("PLANNER_MULTIDATE_GESTURES_NATIVE_PASS",phase,checks);Qt.quit();return
   }
   if(phase==="initial") {
    // First test the visual leak on a modern series (also reproducible before
    // the patch), then the older multi-slot schema without repeatTemplate.
    drag(402,0,"plannerEventMoveArea","move",0,planner.hourHeight/4,true)
    drag(401,0,"plannerEventMoveArea","move",0,planner.hourHeight/4,true)
    const original=Events.list.find(e=>e.id===401)
    const start=new Date(original.occurrences[0].startDate).getTime()
    drag(401,0,"plannerEventMoveArea","move",0,planner.hourHeight/4)
    check(new Date(Events.list.find(e=>e.id===401).occurrences[0].startDate).getTime()
      ===start+15*60000,"legacy body did not move exactly one slot")
    drag(401,0,"plannerResizeStart","top",0,planner.hourHeight/4)
    drag(401,0,"plannerResizeEnd","bottom",0,planner.hourHeight/4)
    const edited=Events.list.find(e=>e.id===401)
    check(new Date(edited.occurrences[0].startDate).getTime()===start+30*60000,
      "legacy top resize lost")
    check(new Date(edited.occurrences[0].endDate).getTime()===start+90*60000,
      "legacy bottom resize lost")
    check(JSON.stringify(edited.occurrences[1])===JSON.stringify(original.occurrences[1]),
      "another saved day changed")
    check(edited.occurrences[0].ownerSlot.value===3 && edited.todoLink.key==="retained",
      "legacy metadata lost during persistence")
    // Reopen the same data, with original cadence preserved in the next week.
    Events.loadFromFile();tryCompare(Events,"ready",true,4000);wait(80)
    planner.changeWeek(1);wait(80)
    check(card(401).modelData.virtual && card(401).modelData.startDate.toISOString()
      ==='2032-10-26T09:30:00.000Z',"future weekday did not follow the edited clock")
    drag(401,0,"plannerResizeEnd","bottom",0,planner.hourHeight/4)
    check(Events.list.find(e=>e.id===401).plannerFutureSchedule.length===4,
      "virtual legacy edit did not persist one forward branch rule")
    planner.changeWeek(-1);wait(80)
    // Preserve Owner-accepted Ctrl selection and genuine group movement.
    const selected=[card(403),card(405)]
    for(const c of selected)mouseClick(first(c,"plannerEventMoveArea"),c.width/2,20,
      Qt.LeftButton,Qt.ControlModifier)
    check(planner.selectedEventKeys.length===2,"Ctrl selection lost "+JSON.stringify({
     selected:planner.selectedEventKeys,width:root.width,height:root.height,
     viewportWidth:viewport.width,viewportHeight:viewport.height,
     cards:selected.map(c=>({id:c.modelData.event.id,point:c.mapToItem(planner,0,0),width:c.width,height:c.height}))}))
    let p=held(first(card(403),"plannerEventMoveArea"),0,planner.hourHeight/4)
    check(cards().filter(c=>c.effectiveMode==="move").length===2,"explicit batch preview lost")
    mouseRelease(planner,p.x,p.y,Qt.LeftButton);settle()
    check(planner.selectedEventKeys.length===0,"selection not cleared after batch save")
    // Owner regression: recurring cards participate in an explicit mixed
    // selection, while a lone drag continues to preview only one instance.
    for(const c of [card(401),card(403)])mouseClick(first(c,"plannerEventMoveArea"),c.width/2,20,
      Qt.LeftButton,Qt.ControlModifier)
    check(planner.selectedEventKeys.length===2,"saved recurring Ctrl selection unavailable")
    check(!planner.canDeleteSelection,"recurring selection exposed series batch deletion")
    const oneBefore=JSON.stringify(Events.list.find(e=>e.id===401).occurrences[1])
    p=held(first(card(401),"plannerEventMoveArea"),0,planner.hourHeight/4)
    check(cards().filter(c=>c.effectiveMode==="move").length===2,"mixed recurring group preview lost")
    mouseRelease(planner,p.x,p.y,Qt.LeftButton);settle()
    check(JSON.stringify(Events.list.find(e=>e.id===401).occurrences[1])===oneBefore,
      "mixed group movement changed an unselected recurring slot")
    // Modified background drag selects a region without stealing ordinary
    // background scrolling or the event's own move/resize pointer owners.
    // Use the actual local-time card bounds: UTC fixture hours and the
    // locale's first weekday are not native screen coordinates.
    const boxes=[card(401),card(402),card(403)].map(c=>{
      const point=c.mapToItem(planner,0,0)
      return {x:point.x,y:point.y,w:c.width,h:c.height}
    })
    const from={x:Math.min.apply(null,boxes.map(b=>b.x))-2,
      y:Math.min.apply(null,boxes.map(b=>b.y))-8}
    const to={x:Math.max.apply(null,boxes.map(b=>b.x+b.w))+2,
      y:Math.max.apply(null,boxes.map(b=>b.y+b.h))+8}
    mousePress(planner,from.x,from.y,Qt.LeftButton,Qt.ControlModifier)
    mouseMove(planner,to.x,to.y,80);wait(40)
    check(first(planner,"plannerSelectionRegion").visible,"selection rectangle never appeared")
    mouseRelease(planner,to.x,to.y,Qt.LeftButton,Qt.ControlModifier);wait(40)
    check(planner.selectedEventRows.length===3,"region did not select its three intersecting cards")
    check(planner.selectedEventRows.every(row=>[401,402,403].includes(row.event.id)),
      "region selected an unrelated occurrence")
    planner.clearEventSelection()
    // The existing all-day civil-day move must still reach its backend.
    const day=all(planner,"plannerAllDayEvent").find(c=>c.modelData.event.id===404)
    const old=new Date(day.modelData.startDate).getTime()
    p=held(day,planner.columnWidth,0)
    mouseRelease(planner,p.x,p.y,Qt.LeftButton);settle()
    check(new Date(Events.list.find(e=>e.id===404).startDate).getTime()===old+86400000,
      "all-day single move did not persist")
   }
   const durable=Events.getDurableEvents(),old=durable.find(e=>e.id===401)
   check(old.occurrences[0].ownerSlot.value===3 && old.ownerExtra.value===7,"restart metadata lost")
   check(old.plannerFutureSchedule.length===5,"restart lost/duplicated forward rules")
   check(old.occurrences[0].plannerSeriesStartDate==='2032-10-19T09:00:00.000Z',"original anchor lost")
   check(durable.length===5 && Events.nextId===500,"stable IDs changed")
   console.info("PLANNER_MULTIDATE_GESTURES_NATIVE_PASS",phase,checks)
  } catch(e) {console.error("PLANNER_MULTIDATE_GESTURES_NATIVE_FAIL",e.message,e.stack)}Qt.quit() }
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''


def slot(day):
    return {"startDate": f"2032-10-{day}T09:00:00.000Z",
            "endDate": f"2032-10-{day}T10:00:00.000Z",
            "notified": False, "reminderNotified": True}


with tempfile.TemporaryDirectory(prefix="alis-multidate-gestures-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "services", "qmldir", "GlobalStates.qml", "assets",
                 "scripts", "defaults", "translations"):
        (folder / name).symlink_to(ROOT / name)
    (folder / "shell.qml").write_text(QML)
    with private_wayland(folder) as env:
        if not env:
            print("SKIP: multi-date gestures require private Niri")
            raise SystemExit(0)
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        (config / "config.json").write_bytes((ROOT / "defaults/config.json").read_bytes())
        storage = folder / "state/quickshell/user/events.json"
        storage.parent.mkdir(parents=True)
        old = {"id": 401, "title": "Synthetic old multi-date", "recurrence": "weekly",
               "occurrences": [dict(slot("19"), ownerSlot={"value": 3}), slot("21")],
               "todoLink": {"key": "retained"}, "ownerExtra": {"value": 7}}
        modern = {"id": 402, "title": "Synthetic modern series", "recurrence": "weekly",
                  "occurrences": [slot("20"), slot("22")],
                  "repeatTemplate": [slot("20"), slot("22")], "repeatCycleStart": 0}
        if os.environ.get("ALIS_PLANNER_SINGLE_SERIES_CONTROL") == "1":
            modern = dict(slot("20"), id=402, title="Synthetic single-series control", recurrence="weekly")
        fixture = {"schemaVersion": 1, "nextId": 500, "events": [old, modern,
            dict(slot("20"), id=403, title="Synthetic batch one"),
            dict(slot("19"), id=404, title="Synthetic all-day", allDay=True),
            dict(slot("21"), id=405, title="Synthetic batch two")],
            "todoUnlinks": [{"key": "retain-unlink"}], "unknownRoot": {"keep": 1}}
        storage.write_text(json.dumps(fixture))
        env.update(ALIS_PLANNER_TEST_EVENTS=str(storage), QT_QUICK_BACKEND="software", TZ="America/New_York")
        previous = None
        for phase in ("initial", "interrupted", "restart", "repeat-restart"):
            env["PLANNER_EDIT_PHASE"] = phase
            result = run_qs(folder, env, timeout=35)
            evidence = os.environ.get("ALIS_PLANNER_EVIDENCE")
            if evidence:
                Path(evidence).mkdir(parents=True, exist_ok=True)
                (Path(evidence) / (phase + ".log")).write_text(result.stdout)
            marker = "PLANNER_MULTIDATE_GESTURES_NATIVE_PASS"
            if result.returncode or marker not in result.stdout or any(token in result.stdout for token in
                ("PLANNER_MULTIDATE_GESTURES_NATIVE_FAIL", "ReferenceError:", "TypeError:",
                 "Binding loop", "Failed to load configuration", "Unable to assign")):
                print(result.stdout)
                raise SystemExit(1)
            raw = storage.read_bytes()
            data = json.loads(raw)
            assert data["unknownRoot"] == fixture["unknownRoot"]
            assert data["todoUnlinks"] == fixture["todoUnlinks"]
            assert data["events"][1] == modern, "Cancel altered the modern series"
            if previous is not None:
                assert previous == raw, "restart/observation rewrote persisted records"
            previous = raw
            print(next(line for line in result.stdout.splitlines() if marker in line))
