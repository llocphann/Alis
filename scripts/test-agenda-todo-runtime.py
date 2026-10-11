#!/usr/bin/env python3
"""Actual isolated stores: one-way durable linking, retry/crash and deletion."""
import json,os,tempfile
from pathlib import Path
from native_test_session import run_qs
ROOT=Path(__file__).resolve().parents[1]
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
ShellRoot {
 id:root
 property string action:Quickshell.env("AGENDA_ACTION")
 property int phase:0
 property int ticks:0
 property int checks:0
 property bool finished:false
 property bool restoring:false
 function check(ok,label){checks++;if(!ok)throw new Error(label)}
 function finish(){finished=true;console.info("AGENDA_TODO_PASS",action,checks);Qt.quit()}
 Component.onCompleted:Quickshell.watchFiles=false
 Process {id:permission;command:["/usr/bin/chmod",root.restoring?"600":"400",root.action==="event-failure"?Events.filePath:Todo.filePath]
  onExited:(code,status)=>{
   if(code!==0){console.error("AGENDA_TODO_FAIL","chmod",code);Qt.quit();return}
   if(root.restoring){Todo.retryAgendaLinks();root.phase=3}
   else {Events.addEvent("Retry","detail","2099-01-03T10:00:00Z","meeting","normal",0,"none","2099-01-03T11:00:00Z",false);root.phase=2}
  }
 }
 Timer {interval:30;running:true;repeat:true
  onTriggered:{try{
   if(root.finished)return
   root.ticks++;if(root.ticks>500)throw new Error("bounded timeout phase"+root.phase+" "+Events.errorMessage+" "+Todo.errorMessage+" "+Todo.agendaError)
   if(root.phase===0 && Events.ready && Todo.ready && !Events.persistenceBusy && !Todo.internalPersistenceBusy) {
    if(root.action==="create") {
     root.check(Events.list.length===1&&!Events.list[0].todoLink,"historical seed changed/backfilled")
     root.check(Todo.addTask("Todo only"),"standalone task rejected")
     root.check(Events.list.length===1,"Todo created an Agenda")
     Events.addEvent("Alpha","alpha detail","2099-01-03T10:00:00Z","meeting","normal",0,"none","2099-01-03T11:00:00Z",false)
     Events.addEvent("Beta","beta detail","2099-01-04T00:00:00Z","general","normal",0,"none","",true)
     root.check(Todo.list.length===1,"optimistic unsaved events made phantom Todos")
     root.phase=1
    } else if(root.action==="edit") {
     const event=Events.list.find(value=>value.title==="Alpha")
     const item=Todo.list.find(value=>value.agenda?.key===event.todoLink.key)
     root.check(item.done&&item.notes==="Independent notes","seeded independent fields lost at restart")
     Events.updateEvent(event.id,{title:"Alpha edited",description:"new detail",dateTime:"2099-01-05T12:00:00Z",startDate:"2099-01-05T12:00:00Z",endDate:"2099-01-05T13:00:00Z"})
     Events.saveToFile();Events.saveToFile();root.phase=1
    } else if(root.action==="delete") {
     const alpha=Todo.list.find(value=>value.content==="Alpha edited")
     root.check(Todo.deleteTask(alpha.id),"linked delete not accepted")
     root.check(Todo.list.some(value=>value.id===alpha.id),"task deleted before durable unlink")
     root.phase=1
    } else if(root.action==="task-failure"||root.action==="event-failure") {permission.running=true;root.phase=1}
    else if(root.action==="absent") {
     Config.setNestedValue("todo.backend","obsidian")
     Events.addEvent("Unavailable","","2099-02-01T10:00:00Z","general","normal",0,"none","",false)
     root.phase=1
    } else {root.phase=1}
   } else if(root.phase===1) {
    if(root.action==="absent") {
     if(root.ticks<70||Events.persistenceBusy)return
     const event=Events.list.find(value=>value.title==="Unavailable")
     root.check(event.todoLink.state==="pending"&&Todo.agendaStatus(event)==="To-do pending","optional absent falsely linked")
     root.check(!Todo.ready&&Todo.agendaError.length>0,"unavailable backend missing pending feedback")
     root.finish();return
    }
    if(Events.persistenceBusy||Todo.internalPersistenceBusy||!Events.ready||!Todo.ready)return
    const linked=Events.list.filter(value=>value.todoLink?.state==="linked")
    if(root.action==="create") {
     if(linked.length!==2)return
     root.check(Todo.list.length===3,"not exactly one task per new occurrence")
     root.check(Todo.list.filter(value=>value.agenda).length===2,"historical/independent data linked")
     root.check(new Set(Todo.list.filter(value=>value.agenda).map(value=>value.id)).size===2,"occurrences share identity")
     root.finish()
    } else if(root.action==="edit") {
     const item=Todo.list.find(value=>value.content==="Alpha edited")
     if(!item||linked.find(value=>value.title==="Alpha edited")?.todoLink.fingerprint!==item.agenda.fingerprint)return
     root.check(Todo.list.length===3&&item.done&&item.notes==="Independent notes","event sync duplicated/reset task")
     root.check(item.description==="new detail"&&item.date==="2099-01-05","event details/date not synced")
     root.finish()
    } else if(root.action==="delete") {
     if(Todo.list.some(value=>value.content==="Alpha edited"))return
     const event=Events.list.find(value=>value.title==="Alpha edited")
     root.check(event.todoLink.state==="detached","Todo removal left auto-create intent")
     Events.updateEvent(event.id,{title:"Still scheduled"})
     const beta=Events.list.find(value=>value.title==="Beta");Events.removeEvent(beta.id);root.phase=4
    } else if(root.action==="crash-recovery") {
     if(linked.length!==2)return
     root.check(Todo.list.length===3,"restart between stores duplicated a linked task")
     root.finish()
    } else if(root.action==="restart") {root.check(Todo.list.length===2&&!Todo.list.some(value=>value.agenda),"unlink/data retention did not survive restart");root.finish()}
   } else if(root.phase===2) {
    if(root.action==="task-failure"&&Todo.errorCode==="INTERNAL_SAVE_FAILED") {
     root.check(Events.getDurableEvents()[0].todoLink.state==="pending","failed task save falsely completed event link")
     root.check(Todo.list.length===1&&Todo.agendaError.length>0,"pending task lost/feedback missing")
     root.restoring=true;permission.running=true
    } else if(root.action==="event-failure"&&Events.errorMessage.length) {
     root.check(Todo.list.length===0&&Events.getDurableEvents().length===0,"failed event write created phantom task")
     root.restoring=true;permission.running=true
    }
   } else if(root.phase===3&&!Events.persistenceBusy&&!Todo.internalPersistenceBusy) {
    if(Events.list[0]?.todoLink.state!=="linked")return
    root.check(Todo.list.length===1&&Todo.errorMessage===""&&Events.errorMessage==="","retry lost/duplicated data")
    root.finish()
   } else if(root.phase===4&&!Events.persistenceBusy&&!Todo.internalPersistenceBusy) {
    if(Todo.list.some(value=>value.agenda))return
    root.check(Events.list.some(value=>value.title==="Still scheduled"),"Todo deletion canceled Agenda")
    root.check(Todo.list.length===2&&Todo.list.some(value=>value.content==="Beta"&&value.description==="beta detail"),"Agenda deletion destroyed independent task data")
    root.finish()
   }
  }catch(error){console.error("AGENDA_TODO_FAIL",root.action,error.message,error.stack,JSON.stringify({events:Events.list,durable:Events.getDurableEvents(),tasks:Todo.list}));Qt.quit()}}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='alis-agenda-link-') as name:
 base=Path(name);evidence=Path(os.environ.get('ALIS_AGENDA_EVIDENCE',base/'evidence'));evidence.mkdir(parents=True,exist_ok=True)
 for case in ['normal','task-failure','event-failure','absent']:
  folder=base/case;folder.mkdir()
  for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
  (folder/'shell.qml').write_text(QML)
  env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
  for key in ['QS_CONFIG_NAME','QS_CONFIG_PATH','QS_MANIFEST','NIRI_SOCKET','WAYLAND_DISPLAY']:env.pop(key,None)
  for kind in ['config','state','cache','data','runtime']:
   path=folder/kind;path.mkdir(mode=0o700);env['XDG_'+kind.upper()+('_DIR' if kind=='runtime' else '_HOME')]=str(path)
  config=folder/'config/illogical-impulse';config.mkdir();(config/'config.json').write_bytes((ROOT/'defaults/config.json').read_bytes())
  state=folder/'state/quickshell/user';state.mkdir(parents=True)
  events=state/'events.json';tasks=state/'todo.json'
  historical={'id':50,'title':'Historical','dateTime':'2099-01-01T10:00:00Z','startDate':'2099-01-01T10:00:00Z','notified':False}
  events.write_text(json.dumps({'nextId':51 if case=='normal' else 1,'events':[historical] if case=='normal' else []}));tasks.write_text('[]')
  actions=['create','crash-recovery','edit','delete','restart'] if case=='normal' else [case]
  for action in actions:
   if action=='crash-recovery':
    data=json.loads(events.read_text());data['events'][1]['todoLink']['state']='pending';data['events'][1]['todoLink']['fingerprint']='';events.write_text(json.dumps(data))
   if action=='edit':
    data=json.loads(tasks.read_text());item=next(value for value in data if value['content']=='Alpha');item['done']=True;item['notes']='Independent notes';tasks.write_text(json.dumps(data))
   result=run_qs(folder,dict(env,AGENDA_ACTION=action),timeout=20)
   (evidence/(case+'-'+action+'.log')).write_text(result.stdout)
   if result.returncode or 'AGENDA_TODO_PASS' not in result.stdout or any(word in result.stdout for word in ['AGENDA_TODO_FAIL','ReferenceError:','TypeError:','Binding loop','Unable to assign','Failed to load configuration']):print(result.stdout);raise SystemExit(1)
   for file in [events,tasks]:(evidence/(case+'-'+action+'-'+file.name)).write_bytes(file.read_bytes())
   for line in result.stdout.splitlines():
    if 'AGENDA_TODO_PASS' in line:print(line)
