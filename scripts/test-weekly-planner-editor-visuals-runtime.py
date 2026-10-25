#!/usr/bin/env python3
"""Native editor/grid emphasis, stripe removal and identity colors on saved data."""
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
 id:root;visible:true;width:1260;height:820;color:"#111820"
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
  function timed(){return all(planner,"plannerTimedEvent")}
  function cards(){return timed().concat(all(planner,"plannerAllDayEvent"))}
  function card(id,index){return timed().find(c=>c.modelData.event.id===id
   && c.modelData.occurrenceIndex===index && !c.modelData.virtual)}
  function outline(c){return c.objectName==="plannerTimedEvent"
   ? c.border.width : find(c,"plannerAllDaySelection")?.border.width || 0}
  function open(id,index){const c=card(id,index);mouseClick(find(c,"plannerEventMoveArea"),c.width/2,20);
   tryVerify(()=>!!find(planner,"plannerInlineEventsEditor"),3000);wait(100);
   return find(planner,"plannerInlineEventsEditor")}
  function capture(name){
   if(!Quickshell.env("PLANNER_VISUAL_EVIDENCE"))return
   let done=false,saved=false
   check(planner.grabToImage(result=>{saved=result.saveToFile(
    Quickshell.env("PLANNER_VISUAL_EVIDENCE")+"/"+name+".png");done=true}),name+": capture refused")
   root.update();tryVerify(()=>done,2500);check(saved,name+": PNG write failed")
  }
  function run(){try{
   tryCompare(Config,"ready",true,5000);tryCompare(Events,"ready",true,5000)
   check(Events.filePath===Quickshell.env("PLANNER_VISUAL_STORE"),"escaped private store")
   Config.setNestedValues({"panelFamily":Quickshell.env("PLANNER_PANEL_FAMILY") || "abyss",
    "performance.reduceAnimations":true})
   planner.followToday=false;planner.selectedDate=new Date('2032-10-19T12:00:00Z');wait(120)
   find(planner,"weeklyPlannerViewport").contentY=8*planner.hourHeight
   const mode=Quickshell.env("PLANNER_VISUAL_CASE")
   const colors=[1,9,17,25].map(id=>String(cards().find(c=>c.modelData.event.id===id).eventAccent))
   if(mode!=="selection" && mode!=="stripes")
    check(new Set(colors).size===4,"four distinct Event IDs reused the same theme color "+JSON.stringify(colors))
   if(mode!=="selection")
    check(cards().every(c=>!c.children.some(child=>child.width===3 && child.height>8
      && child.x<=3 && String(child.color)===String(c.eventAccent))),"interior accent stripe remains")
   let form=open(1,2)
   check(JSON.stringify(form.plannerSelectedDateKeys)===JSON.stringify(["2032-10-19","2032-10-21"]),
    "stored cycle dates changed")
   check(timed().filter(c=>outline(c)===2).length===2
    && [card(1,2),card(1,3)].every(c=>outline(c)===2),"Edit Event calendar selection is absent from grid")
   check(planner.selectedEventKeys.length===0,"opening editor silently armed a batch gesture")
   capture("editor-group")
   const durable=JSON.stringify(Events.getDurableEvents())
   form.choosePlannerDay(new Date(2032,9,19,12),Qt.ControlModifier);wait(50)
   check(JSON.stringify(form.plannerSelectedDateKeys)===JSON.stringify(["2032-10-21"]),"calendar toggle lost")
   check(outline(card(1,2))!==2 && outline(card(1,3))===2,"calendar toggle did not update grid emphasis")
   check(JSON.stringify(Events.getDurableEvents())===durable,"draft selection wrote Events")
   form.dismiss();wait(60)
   check(timed().every(c=>outline(c)!==2),"Cancel left stale editor outlines")
   form=open(1,2)
   check(!form.hasUnsavedChanges() && [card(1,2),card(1,3)].every(c=>outline(c)===2),
    "reopen did not restore the saved group")
   form.eventTitle="Unsaved private draft"
   const target=find(card(1,2),"plannerEventMoveArea")
   const p=target.mapToItem(planner,target.width/2,target.height/2)
   mousePress(planner,p.x,p.y,Qt.LeftButton)
   mouseMove(planner,p.x+planner.columnWidth,p.y,80);wait(40)
   check(timed().filter(c=>c.effectiveMode==="move").length===1,"editor emphasis armed an implicit group drag")
   card(1,2).cancelGesture();mouseRelease(planner,p.x+planner.columnWidth,p.y,Qt.LeftButton);wait(60)
   check(form.eventTitle==="Unsaved private draft" && JSON.stringify(Events.getDurableEvents())===durable,
    "canceled gesture overwrote form or stored data")
   planner.sideView="todo";wait(70)
   check(timed().every(c=>outline(c)!==2),"hidden editor left grid emphasis")
   planner.sideView="events";wait(70)
   check([card(1,2),card(1,3)].every(c=>outline(c)===2),"restored editor lost group emphasis")
   form.dismiss();wait(60)
   planner.openInlineEventEditor(Object.assign({},Events.list.find(e=>e.id===17),{_editOccurrenceIndex:0}));wait(100)
   const allDay=all(planner,"plannerAllDayEvent").filter(c=>c.modelData.event.id===17)
   check(allDay.length===2 && allDay.every(c=>outline(c)===2),"All-day editor group did not highlight")
   check(timed().every(c=>outline(c)!==2),"same-title different Event inherited editor selection")
   form=find(planner,"plannerInlineEventsEditor");form.dismiss();wait(60)
   // Explicit custom/source colors keep their existing meaning.
   check(String(planner.eventGradientColor({source:"local",event:{id:1,color:"#ff3355"}},["#000000","#ffffff"]))==="#ff3355",
    "explicit Event color changed")
   check(String(planner.eventGradientColor({source:"external",event:{uid:"x",sourceColor:"#336699"}},["#000000","#ffffff"]))==="#336699",
    "external source color changed")
   const distinct=[1,9,17,25].map(id=>planner.eventGradientColor({source:"local",event:{id:id}},["#22ccee","#8844dd"]))
   check(new Set(distinct.map(String)).size===4,"collision resolution did not use theme interpolation")
   const renamed=Events.list.map(e=>e.id===9 ? Object.assign({},e,{title:"Renamed private fixture"}) : e)
   Events.list=renamed;Events.eventUpdated(renamed.find(e=>e.id===9));wait(70)
   check([1,9,17,25].every((id,i)=>String(cards().find(c=>c.modelData.event.id===id).eventAccent)===colors[i]),
    "rename/list refresh changed identity colors")
   check(JSON.stringify(Events.getDurableEvents())===durable,"color observation wrote stored Events")
   capture("after-cancel")
   console.info("PLANNER_EDITOR_VISUALS_NATIVE_PASS",Quickshell.env("PLANNER_VISUAL_PHASE"),checks,JSON.stringify(colors))
  }catch(e){console.error("PLANNER_EDITOR_VISUALS_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
def slot(day):
 return dict(startDate=f'2032-10-{day}T09:00:00.000Z',endDate=f'2032-10-{day}T10:00:00.000Z',
             notified=False,reminderNotified=True,ownerSlot={'keep':day})
with tempfile.TemporaryDirectory(prefix='alis-editor-visuals-') as temporary:
 folder=Path(temporary)
 for name in ('modules','services','qmldir','GlobalStates.qml','assets','scripts','defaults','translations'):
  (folder/name).symlink_to(ROOT/name)
 (folder/'shell.qml').write_text(QML)
 with private_wayland(folder,capture_focus=bool(os.environ.get('ALIS_PLANNER_EVIDENCE'))) as env:
  if not env:print('SKIP: editor visuals require private Niri');raise SystemExit(0)
  config=folder/'config/alis';config.mkdir(parents=True)
  (config/'config.json').write_bytes((ROOT/'defaults/config.json').read_bytes())
  store=folder/'state/quickshell/user/events.json';store.parent.mkdir(parents=True)
  slots=[slot(d) for d in ['05','07','19','21']]
  events=[dict(id=1,title='Same title',recurrence='weekly',occurrences=slots,
    repeatTemplate=slots[:2],repeatCycleStart=2,ownerExtra={'keep':7}),
   dict(id=9,title='Same title',recurrence='weekly',occurrences=[slot('20'),slot('22')],
    repeatTemplate=[slot('20'),slot('22')],repeatCycleStart=0),
   dict(id=17,title='All-day group',occurrences=[slot('19'),slot('21')],allDay=True),
   dict(id=25,title='Unrelated single',**slot('21'))]
  fixture=dict(schemaVersion=1,nextId=100,events=events,unknownRoot={'keep':1},todoUnlinks=[])
  store.write_text(json.dumps(fixture));original=store.read_bytes()
  env.update(PLANNER_VISUAL_STORE=str(store),QT_QUICK_BACKEND='software',TZ='UTC')
  for phase in ['initial','restart','repeat-restart']:
   env['PLANNER_VISUAL_PHASE']=phase;evidence=os.environ.get('ALIS_PLANNER_EVIDENCE')
   if evidence:
    dest=Path(evidence)/phase;dest.mkdir(parents=True,exist_ok=True);env['PLANNER_VISUAL_EVIDENCE']=str(dest)
   result=run_qs(folder,env,timeout=40)
   if evidence:(dest/'native.log').write_text(result.stdout)
   if result.returncode or 'PLANNER_EDITOR_VISUALS_NATIVE_PASS' not in result.stdout or any(t in result.stdout for t in
     ['PLANNER_EDITOR_VISUALS_NATIVE_FAIL','ReferenceError:','TypeError:','Binding loop','Unable to assign']):
    print(result.stdout);raise SystemExit(1)
   assert store.read_bytes()==original,'visual selection/color/Cancel/restart rewrote private persisted Events'
   print(next(line for line in result.stdout.splitlines() if 'PLANNER_EDITOR_VISUALS_NATIVE_PASS' in line))
