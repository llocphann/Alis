#!/usr/bin/env python3
"""Forward recurrence on real private Events JSON, retry, legacy rollover/reload."""
import calendar
from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import tempfile
from zoneinfo import ZoneInfo
from native_test_session import run_qs

ROOT = Path(os.environ.get('ALIS_PLANNER_SOURCE_ROOT', Path(__file__).resolve().parents[1]))
QML = r'''
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "services/EventFutureSchedule.js" as Future
import "modules/dashboard/WeeklyPlannerPolicy.js" as Planner
ShellRoot {
 id:root
 property int phase:0
 property int checks:0
 property int ticks:0
 property int receipts:0
 property int previousReceipts:0
 property string beforeFailure:""
 property string beforeMetadata:""
 property var cases:JSON.parse(Quickshell.env("ALIS_FORWARD_CASES"))
 property var history:JSON.parse(Quickshell.env("ALIS_FORWARD_HISTORY"))
 Component.onCompleted:Quickshell.watchFiles=false
 function check(ok,message){checks++;if(!ok)throw new Error(message)}
 function record(id){return Events.list.find(event=>event.id===id)}
 function operation(c){return {id:c.id,occurrenceIndex:c.index,recurring:true,
  future:true,startIso:c.start,endIso:c.end}}
 function rows(at){return Planner.project(Events.list,[],new Date(at),1,Future)
  .reduce((all,day)=>all.concat(day.timed),[])}
 function verify(finalState){
  const group=record(101)
  check(JSON.stringify(group.occurrences.slice(0,2))===JSON.stringify(history),"past history rewritten")
  check(group.owner.keep===7 && group.todoLink.key==="retain","group user metadata lost")
  check(group.occurrences[2].startDate===cases[0].start
   && group.occurrences[4].startDate===cases[0].savedNext,"saved future Tuesday did not follow")
  check(group.occurrences[3].startDate===(finalState?cases[0].thursdayChanged:cases[0].thursday),
   "another weekday changed or failed its independent edit")
  const projected=rows(cases[0].projectDate)
  check(projected.some(row=>row.event.id===101 && row.startDate.toISOString()===cases[0].projectDate),
   "virtual Tuesday lost forward rule")
  check(projected.some(row=>row.event.id===101 && row.startDate.toISOString()
   ===(finalState?cases[0].projectThursdayChanged:cases[0].projectThursday)),
   "virtual Thursday lost its separate clock")
  check(group.repeatTemplate[0].startDate===history[0].startDate,"immutable template changed")
  for(const c of cases.slice(1)){
   const event=record(c.id)
   check(Future.has(event) && !event.occurrences && event.owner.keep===c.mode,"legacy shape/metadata changed")
   check(event.startDate===c.start && event.dateTime===c.start,"legacy compatibility timestamp stale")
   const next=Future.nextCycle(event,new Date(c.end).getTime()+60000)
   check(next.length===1 && next[0].startDate===c.next,"legacy "+c.mode+" next clock lost")
   if(finalState){
    const children=Events.list.filter(child=>child.title===c.mode && child.id!==c.id)
    check(children.length===1 && children[0].startDate===c.next
     && Future.has(children[0]),"legacy generation lost its forward schedule or duplicated child")
    check(rows(c.start).filter(row=>row.event.id===c.id && row.virtual).length===0,
     "notified legacy parent projected beside its child")
   }
  }
 }
 Connections {target:Events;function onEventsPersisted(saved){root.receipts++}}
 Process {
  id:permissions
  command:["/usr/bin/chmod",root.phase===3?"400":"600",Events.filePath]
  onExited:(code,status)=>{try{
   root.check(code===0,"private permission fixture failed")
   if(root.phase===3){
    root.check(Events.applyPlannerOccurrenceBatch([{id:101,occurrenceIndex:3,recurring:true,future:true,
     startIso:root.cases[0].thursdayChanged,endIso:root.cases[0].thursdayEndChanged}]),"retry edit rejected")
    root.phase=4
   }else{Events.saveToFile();root.phase=6}
  }catch(e){console.error("PLANNER_FUTURE_STORAGE_FAIL",e.message,e.stack);Qt.quit()}}
 }
 Timer {interval:30;running:true;repeat:true;onTriggered:{try{
  if(++root.ticks>400)throw new Error("bounded phase timeout "+root.phase)
  if(!Events.ready)return
  root.check(Events.filePath===Quickshell.env("ALIS_FORWARD_STORE"),"escaped private store")
  if(root.phase===0){
   if(Quickshell.env("ALIS_FORWARD_PHASE")!=="initial"){
    if(Events.persistenceBusy)return
    root.verify(true)
    const before=JSON.stringify(Events.list);Events.checkDueEvents()
    root.check(JSON.stringify(Events.list)===before && !Events.persistenceBusy && root.receipts===0,
     "restart ran a duplicate generation or unsolicited write")
    console.info("PLANNER_FUTURE_STORAGE_PASS",Quickshell.env("ALIS_FORWARD_PHASE"),root.checks);Qt.quit();return
   }
   root.check(Events.applyPlannerOccurrenceBatch(root.cases.map(root.operation)),"initial forward batch rejected")
   root.phase=1
  }else if(root.phase===1 && !Events.persistenceBusy){
   root.verify(false)
   const event=root.record(101)
   root.beforeMetadata=JSON.stringify([event.occurrences,event.repeatTemplate,event.plannerFutureSchedule])
   root.check(Events.updateEventGroup(101,{title:"Renamed private group",recurrence:"weekly",allDay:false},
    event.occurrences.slice(2,4),true),"metadata-only save rejected")
   root.phase=2
  }else if(root.phase===2 && !Events.persistenceBusy){
   const event=root.record(101)
   root.check(JSON.stringify([event.occurrences,event.repeatTemplate,event.plannerFutureSchedule])===root.beforeMetadata,
    "metadata save flattened different per-day clocks or changed history")
   root.beforeFailure=JSON.stringify(Events.getDurableEvents());root.previousReceipts=root.receipts
   root.phase=3;permissions.running=true
  }else if(root.phase===4 && Events._saveFailed && !permissions.running){
   root.check(JSON.stringify(Events.getDurableEvents())===root.beforeFailure
    && root.receipts===root.previousReceipts && Events.persistenceBusy,"failed write fabricated durability")
   root.phase=5;permissions.running=true
  }else if(root.phase===6 && !Events.persistenceBusy){
   root.check(root.receipts>root.previousReceipts && Events.errorMessage.length===0,"save retry failed")
   // Exercise the real legacy handoff at a controlled afterTime. No system
   // clock changes: mark only these private fixture parents as already fired.
   for(const c of root.cases.slice(1)){
    const index=Events.list.findIndex(event=>event.id===c.id)
    const event=Object.assign({},Events.list[index],{notified:true,reminderNotified:true})
    Events.list[index]=event
    Events.createNextRecurrence(event,new Date(c.end).getTime()+60000)
   }
   root.phase=7
  }else if(root.phase===7 && !Events.persistenceBusy){
   root.verify(true)
   console.info("PLANNER_FUTURE_STORAGE_PASS","initial",root.checks);Qt.quit()
  }
 }catch(e){console.error("PLANNER_FUTURE_STORAGE_FAIL",e.message,e.stack);Qt.quit()}}}
}
'''


def advance(value, mode):
    if mode == 'daily':
        return value + timedelta(days=1)
    if mode == 'weekly':
        return value + timedelta(days=7)
    if mode == 'yearly':
        return value.replace(year=value.year + 1)
    year, month = value.year + value.month // 12, value.month % 12 + 1
    return value.replace(year=year, month=month, day=min(value.day, calendar.monthrange(year, month)[1]))


def iso(value):
    return value.astimezone(ZoneInfo('UTC')).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def slot(value, notified=False):
    return dict(startDate=iso(value), endDate=iso(value + timedelta(hours=1)),
                notified=notified, reminderNotified=notified, ownerSlot={'keep': value.day})


with tempfile.TemporaryDirectory(prefix='alis-forward-storage-') as temporary:
    folder = Path(temporary)
    for name in ('modules', 'services', 'qmldir', 'GlobalStates.qml', 'assets', 'scripts', 'defaults', 'translations'):
        (folder / name).symlink_to(ROOT / name)
    (folder / 'shell.qml').write_text(QML)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', TZ='America/New_York')
    for key in ('QS_CONFIG_NAME', 'QS_CONFIG_PATH', 'QS_MANIFEST', 'NIRI_SOCKET', 'WAYLAND_DISPLAY'):
        env.pop(key, None)
    for kind in ('config', 'state', 'cache', 'data', 'runtime'):
        path = folder / kind
        path.mkdir(mode=0o700)
        env['XDG_' + kind.upper() + ('_DIR' if kind == 'runtime' else '_HOME')] = str(path)
    config = folder / 'config/alis'
    config.mkdir()
    (config / 'config.json').write_bytes((ROOT / 'defaults/config.json').read_bytes())
    now = datetime.now(ZoneInfo('America/New_York'))
    tuesday = (now + timedelta(days=2)).replace(hour=9, minute=0, second=0, microsecond=0)
    while tuesday.weekday() != 1:
        tuesday += timedelta(days=1)
    thursday = (tuesday + timedelta(days=2)).replace(hour=18, minute=30)
    history = [slot(tuesday - timedelta(days=14), True), slot(thursday - timedelta(days=14), True)]
    group = dict(id=101, title='Private group', recurrence='weekly',
                 occurrences=history + [slot(tuesday), slot(thursday),
                    slot(tuesday + timedelta(days=7)), slot(thursday + timedelta(days=7))],
                 repeatTemplate=history, repeatCycleStart=2, owner={'keep': 7}, todoLink={'key': 'retain'})
    cases = [dict(id=101, index=2, start=iso(tuesday.replace(hour=17)), end=iso(tuesday.replace(hour=18)),
                  savedNext=iso((tuesday + timedelta(days=7)).replace(hour=17)),
                  thursday=iso(thursday), thursdayChanged=iso(thursday.replace(hour=19, minute=0)),
                  thursdayEndChanged=iso(thursday.replace(hour=20, minute=30)),
                  projectDate=iso((tuesday + timedelta(days=14)).replace(hour=17)),
                  projectThursday=iso(thursday + timedelta(days=14)),
                  projectThursdayChanged=iso((thursday + timedelta(days=14)).replace(hour=19, minute=0)))]
    events = [group]
    base = advance(now.replace(day=15, hour=9, minute=0, second=0, microsecond=0), 'monthly')
    for index, mode in enumerate(('daily', 'weekly', 'monthly', 'yearly'), 201):
        events.append(dict(slot(base), id=index, title=mode, recurrence=mode, owner={'keep': mode}))
        changed = base.replace(hour=10, minute=30)
        cases.append(dict(id=index, index=0, mode=mode, start=iso(changed),
                          end=iso(changed + timedelta(hours=1)), next=iso(advance(changed, mode))))
    fixture = dict(schemaVersion=1, nextId=900, events=events, unknownRoot={'keep': 1}, todoUnlinks=[])
    store = folder / 'state/quickshell/user/events.json'
    store.parent.mkdir(parents=True)
    store.write_text(json.dumps(fixture))
    env.update(ALIS_FORWARD_STORE=str(store), ALIS_FORWARD_CASES=json.dumps(cases),
               ALIS_FORWARD_HISTORY=json.dumps(history))
    previous = None
    for phase in ('initial', 'restart', 'repeat-restart'):
        env['ALIS_FORWARD_PHASE'] = phase
        result = run_qs(folder, env, timeout=35)
        if evidence := os.environ.get('ALIS_PLANNER_EVIDENCE'):
            path = Path(evidence)
            path.mkdir(parents=True, exist_ok=True)
            (path / (phase + '.log')).write_text(result.stdout)
        if result.returncode or 'PLANNER_FUTURE_STORAGE_PASS' not in result.stdout or any(
                word in result.stdout for word in ('PLANNER_FUTURE_STORAGE_FAIL', 'ReferenceError:',
                    'TypeError:', 'Binding loop', 'Unable to assign', 'Failed to load configuration')):
            print(result.stdout)
            raise SystemExit(1)
        raw = store.read_bytes()
        data = json.loads(raw)
        assert data['unknownRoot'] == fixture['unknownRoot'] and data['nextId'] == 904
        assert len(data['events']) == 9 and data['events'][0]['occurrences'][:2] == history
        if previous is not None:
            assert raw == previous, 'restart wrote or duplicated forward schedules'
        previous = raw
        print(next(line for line in result.stdout.splitlines() if 'PLANNER_FUTURE_STORAGE_PASS' in line))
