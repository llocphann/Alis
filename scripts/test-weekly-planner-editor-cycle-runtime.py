#!/usr/bin/env python3
"""Real stored recurrence history -> inline editor -> pointer move -> restart."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(os.environ.get('ALIS_PLANNER_SOURCE_ROOT',Path(__file__).resolve().parents[1]))
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.dashboard
Window {
 id:root;visible:true;width:1180;height:780;color:"#111820"
 Component.onCompleted:Quickshell.watchFiles=false
 DashboardWeeklyPlanner {
  id:planner;anchors.fill:parent;localBackend:Events
  externalBackend:QtObject {property var events:[];signal eventsUpdated()}
  onRequestEventsDialog:event=>planner.openInlineEventEditor(event)
 }
 TestCase {
  id:test;when:false;optional:true;property int checks:0
  function check(value,msg){checks++;if(!value)throw new Error(msg)}
  function all(item,name){let out=item.objectName===name?[item]:[];
   for(const c of item.children || [])out=out.concat(all(c,name));return out}
  function find(item,name){return all(item,name)[0]}
  function card(){return all(planner,"plannerTimedEvent").find(c=>c.modelData.event.id===501
   && c.modelData.occurrenceIndex===2 && !c.modelData.virtual)}
  function open(){const c=card();mouseClick(find(c,"plannerEventMoveArea"),c.width/2,20);
   tryVerify(()=>!!find(planner,"plannerInlineEventsEditor"),3000);wait(80);
   return find(planner,"plannerInlineEventsEditor")}
  function run(){try{
   tryCompare(Config,"ready",true,5000);tryCompare(Events,"ready",true,5000)
   check(Events.filePath===Quickshell.env("PLANNER_CYCLE_STORE"),"escaped private store")
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true})
   planner.followToday=false;planner.selectedDate=new Date('2032-10-19T12:00:00Z');wait(100)
   find(planner,"weeklyPlannerViewport").contentY=8*planner.hourHeight
   const initial=Quickshell.env("PLANNER_CYCLE_PHASE")==="initial"
   let form=open()
   check(JSON.stringify(form.plannerSelectedDateKeys)===JSON.stringify(
    initial?["2032-10-19","2032-10-21"]:["2032-10-20","2032-10-21"]),
    "editor highlighted template/history instead of clicked cycle")
   check(!form.hasUnsavedChanges(),"opening stored cycle dirtied the form")
   if(initial){
    const sibling=all(planner,"plannerTimedEvent").find(c=>
      c.modelData.event.id===501 && c.modelData.occurrenceIndex===3 && !c.modelData.virtual)
    mouseClick(find(sibling,"plannerEventMoveArea"),sibling.width/2,20,
      Qt.LeftButton,Qt.ControlModifier)
    check(planner.selectedEventRows.length===1,"Ctrl must isolate the dragged weekday")
    form.eventTitle="Unsaved private title"
    const target=find(card(),"plannerEventMoveArea")
    const p=target.mapToItem(planner,target.width/2,target.height/2)
    mousePress(planner,p.x,p.y,Qt.LeftButton)
    mouseMove(planner,p.x+planner.columnWidth,p.y,80)
    mouseRelease(planner,p.x+planner.columnWidth,p.y,Qt.LeftButton)
    tryVerify(()=>!Events.persistenceBusy,4000);wait(80)
    check(JSON.stringify(form.plannerSelectedDateKeys)===JSON.stringify(["2032-10-20","2032-10-21"]),
      "successful move highlighted unrelated historical days")
    check(form.eventTitle==="Unsaved private title" && form.hasUnsavedChanges(),
      "drag overwrote a title draft or its dirty baseline")
    form.dismiss();wait(60)
    form=open()
    check(form.eventTitle==="Synthetic cycle history" && !form.hasUnsavedChanges(),
      "Cancel/reopen retained an unsaved title")
    check(JSON.stringify(form.plannerSelectedDateKeys)===JSON.stringify(["2032-10-20","2032-10-21"]),
      "reopening restored historical/template highlights")
    const before=Events.list.find(e=>e.id===501)
    form.eventTitle="Renamed private cycle"
    check(form.plannerScheduleUnchanged(),"title edit was confused with a schedule edit")
    check(form.saveEvent(),"metadata-only Save failed")
    tryVerify(()=>!Events.persistenceBusy,4000);wait(50)
    const after=Events.list.find(e=>e.id===501)
    check(JSON.stringify(after.occurrences)===JSON.stringify(before.occurrences)
     && JSON.stringify(after.repeatTemplate)===JSON.stringify(before.repeatTemplate)
     && JSON.stringify(after.plannerFutureSchedule)===JSON.stringify(before.plannerFutureSchedule),
     "title Save flattened different per-day clocks or modified recurrence history")
   }
   form.dismiss();wait(60)
   console.info("PLANNER_EDITOR_CYCLE_NATIVE_PASS",Quickshell.env("PLANNER_CYCLE_PHASE"),checks)
  }catch(e){console.error("PLANNER_EDITOR_CYCLE_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
def slot(day):
 return dict(startDate=f'2032-10-{day}T09:00:00.000Z',endDate=f'2032-10-{day}T10:00:00.000Z',
             notified=False,reminderNotified=True,ownerSlot={'keep':day})
with tempfile.TemporaryDirectory(prefix='alis-editor-cycle-') as temporary:
 folder=Path(temporary)
 for name in ('modules','services','qmldir','GlobalStates.qml','assets','scripts','defaults','translations'):
  (folder/name).symlink_to(ROOT/name)
 (folder/'shell.qml').write_text(QML)
 with private_wayland(folder) as env:
  if not env:print('SKIP: editor cycle requires private Niri');raise SystemExit(0)
  config=folder/'config/alis';config.mkdir(parents=True)
  (config/'config.json').write_bytes((ROOT/'defaults/config.json').read_bytes())
  store=folder/'state/quickshell/user/events.json';store.parent.mkdir(parents=True)
  slots=[slot(d) for d in ['05','07','19','21']]
  slots[3].update(startDate='2032-10-21T11:30:00.000Z',endDate='2032-10-21T12:30:00.000Z')
  event=dict(id=501,title='Synthetic cycle history',recurrence='weekly',occurrences=slots,
             repeatTemplate=slots[:2],repeatCycleStart=2,ownerExtra={'keep':7})
  fixture=dict(schemaVersion=1,nextId=602,events=[event],unknownRoot={'keep':1},todoUnlinks=[])
  store.write_text(json.dumps(fixture));env.update(PLANNER_CYCLE_STORE=str(store),QT_QUICK_BACKEND='software',TZ='UTC')
  previous=None
  for phase in ['initial','restart','repeat-restart']:
   env['PLANNER_CYCLE_PHASE']=phase;result=run_qs(folder,env,timeout=35)
   evidence=os.environ.get('ALIS_PLANNER_EVIDENCE')
   if evidence:
    dest=Path(evidence);dest.mkdir(parents=True,exist_ok=True);(dest/(phase+'.log')).write_text(result.stdout)
   if result.returncode or 'PLANNER_EDITOR_CYCLE_NATIVE_PASS' not in result.stdout or any(t in result.stdout for t in
     ['PLANNER_EDITOR_CYCLE_NATIVE_FAIL','ReferenceError:','TypeError:','Binding loop','Unable to assign']):
    print(result.stdout);raise SystemExit(1)
   raw=store.read_bytes();data=json.loads(raw);actual=data['events'][0]
   assert data['unknownRoot']==fixture['unknownRoot'] and data['nextId']==602
   assert actual['occurrences'][:2]==slots[:2] and actual['repeatTemplate']==slots[:2]
   assert actual['occurrences'][2]['startDate']==slot('20')['startDate']
   assert actual['occurrences'][3]==slots[3] and actual['ownerExtra']==event['ownerExtra']
   if previous is not None:assert raw==previous,'restart/Cancel rewrote stored data'
   previous=raw;print(next(line for line in result.stdout.splitlines() if 'PLANNER_EDITOR_CYCLE_NATIVE_PASS' in line))
