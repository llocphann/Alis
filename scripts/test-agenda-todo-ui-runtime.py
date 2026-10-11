#!/usr/bin/env python3
"""Actual shared link state, private Calendar/Planner/Todo controls and stores."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.sidebarRight.events
import qs.modules.sidebarRight.calendar
import qs.modules.dashboard
Window {
 id:root;visible:true;width:1180;height:740;color:"#10242b"
 property int checks:0
 property int frames:0
 property int edits:0
 property int eventId:-1
 readonly property var current:Events.list.find(value=>value.id===root.eventId) || ({title:"Fixture"})
 Component.onCompleted:Quickshell.watchFiles=false
 QtObject {id:imports;property var events:[];signal eventsUpdated()}
 Process {id:permission;property int code:-1;onExited:(code,status)=>permission.code=code}
 Item {
  id:scene;anchors.fill:parent
  Rectangle {anchors.fill:parent;color:Appearance.colors.colLayer0Base}
  EventCard {id:card;x:16;y:16;width:328;height:implicitHeight;event:root.current;onEditClicked:root.edits++}
  CalendarEventRow {id:row;x:16;y:card.y+card.height+20;width:328;height:implicitHeight;event:root.current}
  DashboardWeeklyPlanner {id:planner;x:360;y:16;width:scene.width-x-16;height:scene.height-32;presentationActive:true;sideView:"todo";externalBackend:imports}
 }
 TestCase {
  id:test;when:false;optional:true
  function all(item,predicate){let values=predicate(item)?[item]:[];for(const child of item.children??[])values=values.concat(all(child,predicate));return values}
  function check(ok,label){root.checks++;if(!ok)throw new Error(label)}
  function capture(label){let done=false;scene.grabToImage(result=>{done=result.saveToFile(Quickshell.env("AGENDA_UI_EVIDENCE")+"/"+label+".png")});tryVerify(()=>done,4000);root.frames++}
  function settled(){return Events.ready&&Todo.ready&&!Events.persistenceBusy&&!Todo.internalPersistenceBusy}
  function linked(){return settled()&&Todo.agendaStatus(root.current)==="Linked To-do"}
  function chmod(mode){permission.code=-1;permission.command=["/usr/bin/chmod",mode,Todo.filePath];permission.running=true;tryVerify(()=>permission.code!==-1,3000);check(permission.code===0,"private permission fixture failed")}
  function statusLabel(item,status){return all(item,value=>value.text===status).length>0}
  function run(){try{
   tryCompare(Config,"ready",true,6000);tryVerify(()=>settled(),6000)
   Config.setNestedValue("performance.reduceAnimations",true)
   const date=new Date();date.setDate(date.getDate()+1);date.setHours(9,0,0,0)
   planner.selectedDate=date;planner.followToday=false;planner.sideView="todo"
   tryVerify(()=>all(planner,item=>item.objectName==="plannerSharedSidePanel")[0]?.item!==null,4000)
   const event=Events.addEvent("Linked weekly fixture","Independent scheduled event",date.toISOString(),"meeting","normal",0,"daily",new Date(date.getTime()+3600000).toISOString(),false)
   root.eventId=event.id
   tryVerify(()=>linked(),6000);capture("linked-dark")
   check(planner.width>0&&planner.x+planner.width<=scene.width,"private compositor allocation must contain Planner")
   check(Todo.list.length===1,"projection or UI created duplicate tasks")
   check(statusLabel(card,"Linked To-do")&&statusLabel(row,"Linked To-do"),"Calendar link state did not update")
   check(statusLabel(planner,"Linked To-do"),"Weekly Planner lost the linked relationship")
   check(all(planner,item=>item.text==="link"&&item.visible).length>0,"shared Todo did not show its Agenda icon")
   const timed=all(planner,item=>item.objectName==="plannerTimedEvent")
   check(timed.some(item=>item.modelData.virtual),"daily recurrence did not project")
   for(const item of timed.filter(value=>value.modelData.virtual))check(!statusLabel(item,"Linked To-do"),"virtual recurrence was presented as a saved task")
   const task=Todo.list[0]
   check(Todo.toggleTask(task.id),"linked checkbox failed")
   tryVerify(()=>settled()&&Todo.list[0]?.done,4000)
   check(Events.list[0].id===event.id&&Events.list[0].notified!==true,"task completion canceled/alarmed Agenda")
   chmod("400");Events.updateEvent(event.id,{title:"Retried UI fixture"})
   tryVerify(()=>Todo.errorCode==="INTERNAL_SAVE_FAILED",5000);capture("pending")
   check(statusLabel(card,"To-do pending")&&statusLabel(row,"To-do pending"),"pending state missing across Calendar surfaces")
   const retry=all(card,item=>item.Accessible.name==="Retry To-do link"&&item.visible)[0]
   check(retry!==undefined,"bounded failure missing accessible retry")
   chmod("600");retry.forceActiveFocus();keyClick(Qt.Key_Return)
   tryVerify(()=>linked(),6000)
   check(Todo.list.length===1&&Todo.list[0].done&&Todo.list[0].content==="Retried UI fixture","retry duplicated/reset task")
   for(const dark of [true,false]){
    Appearance.m3colors.darkmode=dark
    for(const scale of [1,1.5]){
     Config.setNestedValue("appearance.typography.sizeScale",scale)
     card.width=scale===1?328:240;wait(80);capture((dark?"dark":"light")+"-"+scale)
     const unlink=all(card,item=>item.Accessible.name==="Unlink To-do"&&item.visible)[0]
     const p=unlink.mapToItem(card,0,0)
     check(p.x>=0&&p.y>=0&&p.x+unlink.width<=card.width&&p.y+unlink.height<=card.height,"link action escapes narrow card")
    }
   }
   const imported={id:"external-fixture",source:"external",title:"Read-only import",startDate:date.toISOString(),endDate:new Date(date.getTime()+1800000).toISOString()}
   imports.events=[imported];imports.eventsUpdated();capture("external-projection")
   check(Todo.list.length===1&&Events.list.length===1,"read-only import auto-created a task/event")
   const unlink=all(card,item=>item.Accessible.name==="Unlink To-do"&&item.visible)[0]
   mouseClick(unlink,unlink.width/2,unlink.height/2)
   tryVerify(()=>settled()&&Events.todoUnlinks.length===0&&!Todo.list[0]?.agenda,6000);capture("unlinked")
   check(root.current.todoLink.state==="detached"&&Todo.list[0].done,"unlink reset completion or event")
   check(root.edits===0,"link control clicked through to Edit")
   check(!statusLabel(card,"Linked To-do")&&!statusLabel(row,"Linked To-do"),"stale relationship after unlink")
   check(Todo.addTask("Independent UI task"),"independent task rejected")
   tryVerify(()=>settled(),4000)
   check(Events.list.length===1&&Todo.list.length===2,"Todo-only created Agenda")
   console.info("AGENDA_UI_PASS",root.checks,"checks",root.frames,"frames")
  }catch(error){console.error("AGENDA_UI_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''

with tempfile.TemporaryDirectory(prefix="alis-agenda-ui-") as name:
    folder=Path(name)
    for entry in ["modules","services","qmldir","GlobalStates.qml","assets","scripts","defaults","translations"]:
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    dest=Path(os.environ.get("ALIS_AGENDA_EVIDENCE",folder/"evidence")).resolve();dest.mkdir(parents=True,exist_ok=True)
    with private_wayland(folder) as env:
        if not env:
            print("SKIP: Agenda UI requires private Niri");raise SystemExit(0)
        cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
        raw=json.loads((ROOT/"defaults/config.json").read_text());raw["panelFamily"]="abyss"
        (cfg/"config.json").write_text(json.dumps(raw))
        env.update(AGENDA_UI_EVIDENCE=str(dest),QT_QUICK_BACKEND="software")
        result=run_qs(folder,env,timeout=35)
        (dest/"native.log").write_text(result.stdout)
        for file in ["events.json","todo.json"]:
            source=folder/"state/quickshell/user"/file
            if source.exists():(dest/file).write_bytes(source.read_bytes())
    bad=["AGENDA_UI_FAIL","ReferenceError:","TypeError:","Binding loop","Unable to assign","is not a type","Failed to load configuration"]
    if result.returncode or "AGENDA_UI_PASS" not in result.stdout or any(word in result.stdout for word in bad):
        print(result.stdout);raise SystemExit(1)
    for line in result.stdout.splitlines():
        if "AGENDA_UI_PASS" in line:print(line)
