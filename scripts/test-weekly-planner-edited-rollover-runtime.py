#!/usr/bin/env python3
"""Persist edited legacy multi-date cycles, denied writes/retry and restart."""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import tempfile
from zoneinfo import ZoneInfo
from native_test_session import run_qs

ROOT=Path(os.environ.get("ALIS_PLANNER_SOURCE_ROOT",Path(__file__).resolve().parents[1]))
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "modules/dashboard/WeeklyPlannerPolicy.js" as Planner
ShellRoot {
 id:root
 property int phase:0
 property int checks:0
 property int ticks:0
 property int receipts:0
 property int receiptsBefore:0
 property string beforeFailure:""
 Component.onCompleted:Quickshell.watchFiles=false
 function check(ok,msg){checks++;if(!ok)throw new Error(msg)}
 Connections { target:Events;function onEventsPersisted(saved){root.receipts++} }
 Process {
  id:permissions
  command:["/usr/bin/chmod",root.phase===2?"400":"600",Events.filePath]
  onExited:(code,status)=>{
   if(code!==0){console.error("PLANNER_EDITED_ROLLOVER_FAIL","fixture permissions",code);Qt.quit();return}
   if(root.phase===2) {
    root.beforeFailure=JSON.stringify(Events.getDurableEvents());root.receiptsBefore=root.receipts
    const slot=Events.list.find(e=>e.id===601).occurrences[2]
    root.check(Events.rescheduleRecurringOccurrence(601,2,slot.startDate,
      new Date(new Date(slot.endDate).getTime()+15*60000).toISOString()),"pending edit rejected")
    root.phase=3
   } else {Events.saveToFile();root.phase=4}
  }
 }
 Timer {interval:30;running:true;repeat:true;onTriggered:{try{
  if(++root.ticks>400)throw new Error("bounded phase timeout "+root.phase)
  if(!Events.ready)return
  root.check(Events.filePath===Quickshell.env("ALIS_PLANNER_TEST_EVENTS"),"escaped private store")
  if(root.phase===0){Events.checkDueEvents();root.phase=1;return}
  if(root.phase===1 && !Events.persistenceBusy) {
   const rows=Events.getDurableEvents(),group=rows.find(e=>e.id===601)
   root.check(rows.length===3 && Events.nextId===701,"legacy IDs changed/duplicated")
   root.check(group.occurrences.length===4 && group.repeatCycleStart===2,"bad cycle boundary")
   root.check(group.occurrences[0].ownerSlot.value===3 && group.ownerExtra.keep,"legacy metadata lost")
   root.check(group.repeatTemplate[0].startDate===group.occurrences[0].plannerSeriesStartDate,
     "recovered template drifted to edited date")
   const next=Quickshell.env("PLANNER_NEXT_START"),future=Quickshell.env("PLANNER_FUTURE_START")
   const current=Planner.project(rows,[],new Date(next),1).reduce((a,d)=>a.concat(d.timed),[])
   root.check(current.filter(r=>r.startDate.toISOString()===next).length===2,
     "rollover lost or duplicated group/legacy exceptions")
   const later=Planner.project(rows,[],new Date(future),1).reduce((a,d)=>a.concat(d.timed),[])
   root.check(later.filter(r=>r.startDate.toISOString()===future).length===2,"pending exception lost")
   root.check(Events.getAllEventOccurrencesForDate(new Date(next)).length===2,"calendar indicator mismatch")
   const snapshot=JSON.stringify(Events.list);Events.checkDueEvents()
   root.check(JSON.stringify(Events.list)===snapshot && !Events.persistenceBusy,"repeated tick rewrote cycle")
   if(Quickshell.env("PLANNER_ROLLOVER_PHASE")==="restart") {
    root.check(root.receipts===0,"restart emitted an unsolicited write")
    console.info("PLANNER_EDITED_ROLLOVER_PASS","restart",root.checks);Qt.quit();return
   }
   root.phase=2;permissions.running=true
  } else if(root.phase===3 && Events._saveFailed && !permissions.running) {
   root.check(Events.errorMessage.length>0 && Events.persistenceBusy,"failed write hidden")
   root.check(JSON.stringify(Events.getDurableEvents())===root.beforeFailure
     && root.receipts===root.receiptsBefore,"failed write fabricated durability")
   permissions.running=true
  } else if(root.phase===4 && !Events.persistenceBusy) {
   root.check(root.receipts>root.receiptsBefore && Events.errorMessage.length===0,"retry not durable")
   const event=Events.getDurableEvents().find(e=>e.id===601)
   root.check(event.occurrences[0].ownerSlot.value===3 && event.occurrences.length===4,"retry damaged history")
   console.info("PLANNER_EDITED_ROLLOVER_PASS","initial-failed-save-retry",root.checks);Qt.quit()
  }
 }catch(e){console.error("PLANNER_EDITED_ROLLOVER_FAIL",e.message,e.stack);Qt.quit()}}}
}
'''

with tempfile.TemporaryDirectory(prefix="alis-edited-rollover-") as name:
    folder=Path(name)
    for entry in ("modules","services","qmldir","GlobalStates.qml","assets","scripts","defaults","translations"):
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    env=dict(os.environ,QT_QPA_PLATFORM="offscreen",QT_QUICK_BACKEND="software",TZ="America/New_York")
    for key in ("QS_CONFIG_NAME","QS_CONFIG_PATH","QS_MANIFEST","NIRI_SOCKET","WAYLAND_DISPLAY"):
        env.pop(key,None)
    for kind in ("config","state","cache","data","runtime"):
        p=folder/kind;p.mkdir(mode=0o700)
        env["XDG_"+kind.upper()+("_DIR" if kind=="runtime" else "_HOME")]=str(p)
    config=folder/"config/alis";config.mkdir()
    (config/"config.json").write_bytes((ROOT/"defaults/config.json").read_bytes())
    now=datetime.now(ZoneInfo("America/New_York"))
    monday=now.replace(hour=9,minute=0,second=0,microsecond=0)-timedelta(days=now.weekday()+14)
    nxt=monday+timedelta(days=1)
    while nxt<=now:nxt+=timedelta(days=7)
    def iso(date):return date.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z")
    def slot(date):return {"startDate":iso(date),"endDate":iso(date+timedelta(hours=1)),"notified":False,"reminderNotified":True}
    original=slot(monday+timedelta(days=1));moved=slot(monday+timedelta(days=2))
    moved.update(plannerSeriesStartDate=original["startDate"],plannerSeriesEndDate=original["endDate"],ownerSlot={"value":3})
    overrides=[dict(occurrenceIndex=0,originalStartDate=iso(date),startDate=iso(date+timedelta(minutes=delta)),
                    endDate=iso(date+timedelta(hours=1,minutes=delta)),ownerReceipt={"keep":True})
               for date,delta in ((nxt,15),(nxt+timedelta(days=7),30))]
    fixture={"schemaVersion":1,"nextId":700,"events":[
        {"id":601,"title":"Synthetic old group","recurrence":"weekly","occurrences":[moved,slot(monday+timedelta(days=3))],
         "plannerOverrides":overrides,"ownerExtra":{"keep":True}},
        dict(original,id=602,title="Synthetic old single",recurrence="weekly",plannerOverrides=overrides)],
        "unknownRoot":{"keep":1},"todoUnlinks":[{"key":"retained"}]}
    storage=folder/"state/quickshell/user/events.json";storage.parent.mkdir(parents=True)
    storage.write_text(json.dumps(fixture))
    env.update(ALIS_PLANNER_TEST_EVENTS=str(storage),PLANNER_NEXT_START=iso(nxt+timedelta(minutes=15)),
               PLANNER_FUTURE_START=iso(nxt+timedelta(days=7,minutes=30)))
    previous=None
    for phase in ("initial","restart","restart"):
        result=run_qs(folder,dict(env,PLANNER_ROLLOVER_PHASE=phase),timeout=18)
        storage.chmod(0o600)
        if os.environ.get("ALIS_PLANNER_EVIDENCE"):
            dest=Path(os.environ["ALIS_PLANNER_EVIDENCE"]);dest.mkdir(parents=True,exist_ok=True)
            (dest/(phase+"-rollover.log")).write_text(result.stdout)
        if result.returncode or "PLANNER_EDITED_ROLLOVER_PASS" not in result.stdout or any(word in result.stdout for word in
            ("PLANNER_EDITED_ROLLOVER_FAIL","ReferenceError:","TypeError:","Binding loop","Unable to assign")):
            print(result.stdout);raise SystemExit(1)
        raw=storage.read_bytes();data=json.loads(raw)
        assert data["unknownRoot"]==fixture["unknownRoot"] and data["todoUnlinks"]==fixture["todoUnlinks"]
        assert data["events"][0]["plannerOverrides"][0]["ownerReceipt"]=={"keep":True}
        if previous is not None:assert raw==previous,"restart rewrote/duplicated existing records"
        previous=raw
        print(next(line for line in result.stdout.splitlines() if "PLANNER_EDITED_ROLLOVER_PASS" in line))
