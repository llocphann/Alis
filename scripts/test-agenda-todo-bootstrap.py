#!/usr/bin/env python3
"""Events alone wakes linking/recovery; corrupt Agenda never unlinks valid tasks."""
import json,os,tempfile
from pathlib import Path
from native_test_session import run_qs
ROOT=Path(__file__).resolve().parents[1]
QML=r'''
import QtQuick
import Quickshell
import qs.services
ShellRoot {
 property int ticks:0
 property bool added:false
 Component.onCompleted:Quickshell.watchFiles=false
 Timer {interval:30;running:true;repeat:true;onTriggered:{
  ticks++
  if(ticks>400){console.error("AGENDA_BOOTSTRAP_FAIL",Events.errorMessage);Qt.quit();return}
  if(Quickshell.env("ACTION")==="corrupt") {
   if(ticks>40 && !Events.ready && Events.errorMessage.length){console.info("AGENDA_BOOTSTRAP_PASS","corrupt");Qt.quit()}
  } else if(Events.ready&&!Events.persistenceBusy) {
   if(Quickshell.env("ACTION")==="create") {
    if(!added){added=true;Events.addEvent("Service-only","","2099-01-01T10:00:00Z","general","normal",0,"none","",false)}
    else if(Events.list[0]?.todoLink?.state==="linked"){console.info("AGENDA_BOOTSTRAP_PASS","create");Qt.quit()}
   } else if(Events.getDurableTodoUnlinks().length===0){console.info("AGENDA_BOOTSTRAP_PASS","delete-recovery");Qt.quit()}
  }
 }}
}
'''
with tempfile.TemporaryDirectory(prefix='alis-agenda-bootstrap-') as name:
 base=Path(name);dest=Path(os.environ.get('ALIS_AGENDA_EVIDENCE',base/'evidence'));dest.mkdir(parents=True,exist_ok=True)
 for action in ['create','delete-recovery','corrupt']:
  folder=base/action;folder.mkdir()
  for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
  (folder/'shell.qml').write_text(QML)
  env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',ACTION=action)
  for key in ['WAYLAND_DISPLAY','NIRI_SOCKET','QS_CONFIG_NAME','QS_CONFIG_PATH','QS_MANIFEST']:env.pop(key,None)
  for kind in ['config','state','cache','data','runtime']:
   path=folder/kind;path.mkdir(mode=0o700);env['XDG_'+kind.upper()+('_DIR' if kind=='runtime' else '_HOME')]=str(path)
  cfg=folder/'config/illogical-impulse';cfg.mkdir();(cfg/'config.json').write_bytes((ROOT/'defaults/config.json').read_bytes())
  state=folder/'state/quickshell/user';state.mkdir(parents=True)
  link={'version':1,'key':'agenda-bootstrap-delete','state':'detached','provider':'internal','deleteTask':True}
  item={'id':'agenda:'+link['key'],'content':'Explicitly deleted','done':True,'notes':'Independent','agenda':{'version':1,'key':link['key'],'eventId':1}}
  tasks=state/'todo.json';tasks.write_text(json.dumps([item] if action!='create' else []))
  events=state/'events.json';events.write_text('{invalid' if action=='corrupt' else json.dumps({'nextId':2,'events':[],'todoUnlinks':[link] if action=='delete-recovery' else []}))
  before=tasks.read_bytes();result=run_qs(folder,env,timeout=16);(dest/(action+'.log')).write_text(result.stdout)
  if result.returncode or 'AGENDA_BOOTSTRAP_PASS' not in result.stdout or any(value in result.stdout for value in ['AGENDA_BOOTSTRAP_FAIL','ReferenceError:','TypeError:','Binding loop']):print(result.stdout);raise SystemExit(1)
  actual=json.loads(tasks.read_text())
  if action=='create':assert len(actual)==1 and actual[0]['content']=='Service-only' and actual[0]['agenda']
  elif action=='delete-recovery':assert actual==[] and json.loads(events.read_text())['todoUnlinks']==[]
  else:assert tasks.read_bytes()==before and events.read_text()=='{invalid'
  (dest/(action+'-tasks.json')).write_bytes(tasks.read_bytes())
  print('AGENDA_BOOTSTRAP_PASS',action,'actual disk readback')
