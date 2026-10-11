#!/usr/bin/env python3
"""Actual optional worker/host bridge, private sources, no installed deployment."""
import hashlib,json,os,tempfile
from pathlib import Path
from native_test_session import run_qs
ROOT=Path(__file__).resolve().parents[1]
integration=Path(os.environ.get('ALIS_INTEGRATION_SOURCE',ROOT.parent/'Alis-Intergration'))
if not (integration/'services/AgendaTaskMutation.qml').exists():
 print('SKIP: optional Agenda integration source not supplied');raise SystemExit(0)
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
ShellRoot {
 id:root
 property int phase:0
 property int ticks:0
 property int checks:0
 property bool finished:false
 property string action:Quickshell.env("AGENDA_ACTION")
 readonly property string observedPackage:Hadalird.packageRoot
 Connections {
  target:Todo.obsidianBackend
  function onAgendaMutationFinished(success,payload){console.info("AGENDA_BRIDGE_RECEIPT",root.action,success,JSON.stringify(payload))}
 }
 function check(ok,label){checks++;if(!ok)throw new Error(label)}
 function finish(){finished=true;console.info("AGENDA_OBSIDIAN_PASS",Quickshell.env("AGENDA_MODE"),action,checks);Qt.quit()}
 Component.onCompleted:Quickshell.watchFiles=false
 Timer {interval:30;repeat:true;running:true
  onTriggered:{try{
   if(root.finished)return
   root.ticks++;if(root.ticks>600)throw new Error("bounded timeout phase"+root.phase+" "+Todo.errorMessage+" "+Todo.agendaError)
   if(root.phase===0 && Config.ready && root.ticks>=60) {
    // The private probe has completed. Mount source through the actual adapter,
    // without installing/enabling anything in the owner's package/data roots.
    Hadalird.packageRoot=Quickshell.env("INTEGRATION_SOURCE");Hadalird.available=true;Hadalird.loadFailed=false
    root.phase=1
   } else if(root.phase===1 && Todo.ready && !Todo.busy && Events.ready && !Events.persistenceBusy) {
    if(root.action==="create") {
     root.check(Todo.list.length===1,"private existing task missing")
     Events.addEvent("From Agenda","detail","2099-01-03T10:00:00Z","meeting","normal",0,"none","2099-01-03T11:00:00Z",false);root.phase=2
    } else if(root.action==="edit") {
     const task=Todo.list.find(value=>value.agenda)
     root.check(task?.done===true,"external completion lost before event sync")
     Events.updateEvent(Events.list[0].id,{title:"Synced name",description:"changed detail"});root.phase=2
    } else if(root.action==="remove") {Events.removeEvent(Events.list[0].id);root.phase=3}
    else if(root.action==="delete-task") {
     const task=Todo.list.find(value=>value.agenda)
     root.check(Todo.deleteTask(task.id),"linked task deletion rejected")
     root.check(Todo.list.some(value=>value.id===task.id),"task deleted before durable Agenda detach")
     root.phase=4
    } else if(root.action==="restart-deleted") {root.phase=4}
    else {root.phase=2}
   } else if(root.phase===2 && Todo.ready && !Todo.busy && !Events.persistenceBusy) {
    const event=Events.list[0];const task=Todo.list.find(value=>value.agenda)
    if(event?.todoLink.state!=="linked" || !task)return
    if(root.action==="edit" && !task.content.includes("Synced name"))return
    root.check(Todo.list.length===2,"duplicate task after retry/restart")
    root.check(task.agenda.key===event.todoLink.key,"canonical source lost stable occurrence key")
    root.check(Todo.agendaStatus(event)==="Linked To-do","host did not acknowledge helper's actual write")
    if(root.action==="edit")root.check(task.done && task.content.includes("extra notes"),"owned sync changed external completion/notes")
    root.finish()
   } else if(root.phase===4 && Todo.ready && !Todo.busy && !Events.persistenceBusy) {
    if(Events.list[0]?.todoLink.state!=="detached" || Events.getDurableTodoUnlinks().length || Todo.list.length!==1)return
    root.check(Todo.list[0].content==="Existing" && Events.list.length===1,"task deletion removed Agenda or unrelated task")
    root.finish()
   } else if(root.phase===3 && Todo.ready && !Todo.busy && !Events.persistenceBusy) {
    if(Todo.list.some(value=>value.agenda) || Events.getDurableTodoUnlinks().length)return
    root.check(Todo.list.length===2 && Todo.list.some(value=>value.done && value.content.includes("Synced name")),"unlink destroyed/changed the independent task")
    root.finish()
   }
  }catch(error){console.error("AGENDA_OBSIDIAN_FAIL",error.message,error.stack,JSON.stringify({events:Events.list,unlinks:Events.todoUnlinks,tasks:Todo.list,backendTasks:Todo.obsidianBackend.list,error:Todo.obsidianErrorCode,requested:Todo.requestedBackend,mode:Todo.obsidianSourceMode,configured:Todo.obsidianConfigured,host:Hadalird.status()}));Qt.quit()}}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='alis-agenda-obsidian-') as name:
 base=Path(name);evidence=Path(os.environ.get('ALIS_AGENDA_OBSIDIAN_EVIDENCE',base/'evidence'));evidence.mkdir(parents=True,exist_ok=True)
 for mode,flow in [(mode,flow) for mode in ['markdown-note','managed-note'] for flow in ['unlink','delete']]:
  folder=base/(mode+'-'+flow);folder.mkdir()
  for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
  (folder/'shell.qml').write_text(QML)
  env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
  for key in ['QS_CONFIG_NAME','QS_CONFIG_PATH','QS_MANIFEST','NIRI_SOCKET','WAYLAND_DISPLAY']:env.pop(key,None)
  for kind in ['config','state','cache','data','runtime']:
   path=folder/kind;path.mkdir(mode=0o700);env['XDG_'+kind.upper()+('_DIR' if kind=='runtime' else '_HOME')]=str(path)
  vault=folder/'Vault';vault.mkdir();note=vault/'Tasks.md'
  start='## Tasks' if mode=='markdown-note' else '<!-- hadalis:todo:start -->'
  end='## Journal' if mode=='markdown-note' else '<!-- hadalis:todo:end -->'
  note.write_text('# Private fixture\n'+start+'\n- [x] Existing\n'+end+'\nIndependent diary\n')
  config=folder/'config/illogical-impulse';config.mkdir();data=json.loads((ROOT/'defaults/config.json').read_text())
  data['integrations']={'hadalird':{'obsidian':True,'tlp':False,'thinkfan':False}}
  data['todo']={'backend':'obsidian','obsidian':{'vaultPath':str(vault),'sourceMode':mode,'notePath':'Tasks.md','preferTasksPlugin':False,'allowBasicOfflineMutation':True,'dailyNote':{'folder':'','format':'Tasks.md','plannerHeading':'Tasks','plannerHeadingLevel':2,'defaultDurationMinutes':30}}}
  data['obsidianTheme']={'enabled':False};(config/'config.json').write_text(json.dumps(data))
  state=folder/'state/quickshell/user';state.mkdir(parents=True);events=state/'events.json';events.write_text('{"nextId":1,"events":[]}')
  for action in (['create','restart','edit','remove'] if flow=='unlink' else ['create','restart','delete-task','restart-deleted']):
   if action=='edit':
    text=note.read_text();lines=text.splitlines(keepends=True)
    for index,line in enumerate(lines):
     if 'alis:agenda:v1:' in line:lines[index]=line.replace('- [ ]','- [x]',1).replace('From Agenda <!--','From Agenda extra notes <!--',1)
    note.write_text(''.join(lines))
   before=note.read_bytes()
   result=run_qs(folder,dict(env,INTEGRATION_SOURCE=str(integration),AGENDA_MODE=mode,AGENDA_ACTION=action),timeout=24)
   (evidence/(mode+'-'+flow+'-'+action+'.log')).write_text(result.stdout)
   (evidence/(mode+'-'+flow+'-'+action+'.md')).write_bytes(note.read_bytes())
   (evidence/(mode+'-'+flow+'-'+action+'-events.json')).write_bytes(events.read_bytes())
   if result.returncode or 'AGENDA_OBSIDIAN_PASS' not in result.stdout or any(word in result.stdout for word in ['AGENDA_OBSIDIAN_FAIL','ReferenceError:','TypeError:','Binding loop','Unable to assign','Failed to load configuration']):print(result.stdout);raise SystemExit(1)
   if action=='restart':assert before==note.read_bytes(),'restart mutated an already linked note'
   for line in result.stdout.splitlines():
    if 'AGENDA_OBSIDIAN_PASS' in line:print(line)
 hashes={str(file.relative_to(integration)):hashlib.sha256(file.read_bytes()).hexdigest() for file in [integration/'services/AgendaTaskMutation.qml',integration/'services/DailyNoteTodoBackend.qml',integration/'services/ObsidianTodoBackend.qml',*integration.glob('scripts/todo/*.py')]}
 (evidence/'integration-source-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
