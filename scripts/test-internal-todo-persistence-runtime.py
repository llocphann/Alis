#!/usr/bin/env python3
"""Real private Todo JSON/TXT saves, overlap, no-op, restart and failed retry."""
import json, os, sys, tempfile
from pathlib import Path

ROOT = Path(os.environ.get('ALIS_TODO_TEST_ROOT', Path(__file__).resolve().parents[1])).resolve()
sys.path.insert(0, str(ROOT / 'scripts'))
from native_test_session import run_qs

QML = r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 InternalTodoBackend {id:todo;filePath:Quickshell.env("TODO_JSON");txtFilePath:Quickshell.env("TODO_TXT")}
 FileView {id:disk;path:todo.filePath;blockAllReads:true}
 FileView {id:mirror;path:todo.txtFilePath;blockAllReads:true}
 FileView {id:external;path:todo.txtFilePath;preload:false;blockWrites:true}
 Process {id:permission;property int completed:0;onExited:completed++}
 TestCase {
  id:test;when:false;optional:true
  property int checks:0
  function check(value,message){checks++;if(!value)throw new Error(message)}
  function jsonDisk(){disk.reload();return JSON.parse(disk.text())}
  function txtDisk(){mirror.reload();return mirror.text()}
  function settle(stage){
   wait(50);tryVerify(()=>!todo.persistenceBusy,1800,"Todo write did not settle: "+stage)
   check(JSON.stringify(jsonDisk())===JSON.stringify(todo.list),"disk lost latest list: "+stage)
  }
  function mode(value){const count=permission.completed+1;permission.command=["/usr/bin/chmod",value,todo.filePath];permission.running=true;tryCompare(permission,"completed",count,1500)}
  function run(){try{
   tryCompare(todo,"ready",true,4000);settle("startup");wait(850)
   const action=Quickshell.env("ACTION")
   if(action==="restart"){
    check(JSON.stringify(todo.list)===JSON.stringify([{content:"external private task",done:true}]),"restart lost canonical task")
    check(txtDisk()==="- [x] external private task\n","restart TXT mismatch")
   }else{
    while(todo.list.length)check(todo.deleteItem(0),"initial cleanup rejected")
    settle("empty")
    check(todo.addTask("first private task"),"first add rejected")
    check(todo.addTask("second private task"),"second add rejected")
    todo.refresh()
    check(todo.markDone(0),"mark done rejected during overlapping write")
    check(todo.markUnfinished(0),"mark unfinished rejected")
    check(todo.deleteItem(1),"delete rejected")
    settle("overlap/refresh");tryCompare(todo,"ready",true,1800)
    check(todo.list.length===1 && todo.list[0].content==="first private task" && !todo.list[0].done,"refresh restored stale list")
    check(txtDisk()==="- [ ] first private task\n","TXT lost latest task")
    for(let index=0;index<3;index++){check(todo.markUnfinished(0),"unchanged mutation rejected");settle("unchanged "+index)}
    check(todo.addTask("later private task"),"edit after unchanged write rejected");settle("later add")
    if(action==="failure"){
     const before=JSON.stringify(jsonDisk());mode("400")
     check(todo.markDone(1),"failed save discarded mutation")
     tryVerify(()=>!todo._jsonSaving,1800,"failed save never acknowledged")
     check(todo.persistenceBusy && todo.errorCode==="INTERNAL_SAVE_FAILED" && todo.errorMessage.length>0,"failure was not visible or migration became unsafe")
     check(JSON.stringify(jsonDisk())===before,"failed save changed disk")
     check(todo.list[1].done,"failure reverted memory")
     mode("600");todo.refresh();settle("explicit refresh retry");tryCompare(todo,"ready",true,1800)
     check(todo.list[1].done && todo.errorMessage.length===0,"retry lost desired change/error did not clear")
     // A second denied-write interval must coalesce several distinct edits,
     // rather than replaying a stale first failure on recovery.
     const beforeBatch=JSON.stringify(jsonDisk());mode("400")
     check(todo.markUnfinished(1),"denied-write unfinished rejected")
     check(todo.markDone(0),"denied-write done rejected")
     check(todo.deleteItem(1),"denied-write delete rejected")
     check(todo.addTask("recovered private task"),"denied-write add rejected")
     tryVerify(()=>!todo._jsonSaving,1800,"batched failed save never acknowledged")
     check(todo.persistenceBusy && todo.errorCode==="INTERNAL_SAVE_FAILED","batched failure was hidden")
     check(JSON.stringify(jsonDisk())===beforeBatch,"batched denied writes changed disk")
     check(todo.list.length===2 && todo.list[0].done && todo.list[1].content==="recovered private task" && !todo.list[1].done,
           "batched failed edits lost in-memory state")
     mode("600");check(todo.retrySave(),"explicit retry rejected");settle("batched explicit retry")
     check(todo.errorMessage.length===0 && !todo.persistenceBusy,"batched retry failed to acknowledge durability")
    }
    external.setText("# external edit\n- [x] external private task\n")
    tryVerify(()=>todo.list.length===1 && todo.list[0].content==="external private task" && todo.list[0].done,2500,"external TXT did not synchronize")
    settle("external text")
    check(txtDisk()==="# external edit\n- [x] external private task\n","external TXT was rewritten")
   }
   console.info("INTERNAL_TODO_PERSISTENCE_PASS",action,Quickshell.env("STORE_KIND"),checks)
  }catch(error){console.error("INTERNAL_TODO_PERSISTENCE_FAIL",error.message,JSON.stringify({list:todo.list,saving:todo._jsonSaving,queued:todo._jsonSaveQueued,busy:todo.persistenceBusy}),error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''

records=[]
with tempfile.TemporaryDirectory(prefix='alis-internal-todo-') as name:
 folder=Path(name)
 for entry in ['modules','services','qmldir','GlobalStates.qml','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(QML)
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
 for key in ['WAYLAND_DISPLAY','DISPLAY','NIRI_SOCKET','QS_CONFIG_NAME','QS_CONFIG_PATH','QS_MANIFEST','HYPRLAND_INSTANCE_SIGNATURE']:env.pop(key,None)
 for kind in ['config','state','cache','data','runtime']:
  path=folder/kind;path.mkdir(mode=0o700);env['XDG_'+kind.upper()+('_DIR' if kind=='runtime' else '_HOME')]=str(path)
 for action,kind in [('normal','missing'),('normal','existing'),('failure','existing')]:
  if os.environ.get('ALIS_TODO_TEST_CASE') and os.environ['ALIS_TODO_TEST_CASE']!=action:continue
  store=folder/(action+'-'+kind);store.mkdir()
  json_path=store/'todo.json';txt_path=store/'todo.txt'
  if kind=='existing':json_path.write_text(json.dumps([{'content':'existing private task','done':True}]))
  for stage in [action,'restart']:
   result=run_qs(folder,dict(env,TODO_JSON=str(json_path),TODO_TXT=str(txt_path),ACTION=stage,STORE_KIND=kind),timeout=20)
   evidence=os.environ.get('ALIS_TODO_EVIDENCE')
   if evidence:
    dest=Path(evidence);dest.mkdir(parents=True,exist_ok=True);(dest/(action+'-'+kind+'-'+stage+'.log')).write_text(result.stdout)
   if result.returncode or 'INTERNAL_TODO_PERSISTENCE_PASS' not in result.stdout or any(x in result.stdout for x in ['INTERNAL_TODO_PERSISTENCE_FAIL','ReferenceError:','TypeError:','Binding loop','Failed to load configuration']):print(result.stdout);raise SystemExit(1)
   assert json.loads(json_path.read_text())==[{'content':'external private task','done':True}]
   records.append({'action':stage,'store':kind,'exit_code':result.returncode,'json_readback':True})
   print(result.stdout[result.stdout.index('INTERNAL_TODO_PERSISTENCE_PASS'):].splitlines()[0])
 if os.environ.get('ALIS_TODO_EVIDENCE'):(Path(os.environ['ALIS_TODO_EVIDENCE'])/'native-results.json').write_text(json.dumps(records,indent=2)+'\n')
