#!/usr/bin/env python3
"""Actual acknowledged Agenda snapshots, coalescing, denied save and restart."""
import json, os, tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT=Path(__file__).resolve().parents[1]
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 id:root
 property int phase:0
 property int ticks:0
 property int checks:0
 property int acknowledgements:0
 property var snapshots:[]
 property int beforeFailure:0
 property bool runningCheck:true
 property bool finished:false
 property string action:Quickshell.env("EVENTS_ACTION")
 Component.onCompleted:Quickshell.watchFiles=false
 function check(ok,message){checks++;if(!ok)throw new Error(message)}
 function finish(){finished=true;console.info("EVENTS_DURABLE_PASS",action,checks,JSON.stringify(snapshots));Qt.quit()}
 Connections {
  target:Events
  function onEventsPersisted(savedEvents){
   root.acknowledgements++
   root.snapshots=root.snapshots.concat([savedEvents.map(event=>event.title)])
   if(savedEvents.length) {
    const title=Events.getDurableEvents()[0].title
    savedEvents[0].title="consumer mutation"
    root.check(Events.getDurableEvents()[0].title===title,"signal consumer mutated the durable source")
   }
  }
 }
 Process {
  id:permissions
  command:["/usr/bin/chmod",root.phase===3?"600":"400",Events.filePath]
  onExited:(code,status)=>{
   if(code!==0){console.error("EVENTS_DURABLE_FAIL","private chmod failed",code);Qt.quit();return}
   if(root.phase===2) {
    root.beforeFailure=root.acknowledgements
    Events.addEvent("Denied","","2099-01-02T09:00:00Z","general","normal",0,"none","",false)
    root.phase=3
   } else if(root.phase===3) {Events.saveToFile();root.phase=4}
  }
 }
 Timer {
  interval:30;running:true;repeat:true
  onTriggered:{try{
   if(root.finished)return
   root.ticks++;if(root.ticks>400)throw new Error("bounded phase timeout "+root.phase)
   if(root.phase===0 && Events.ready) {
    if(root.action==="restart") {
     const expected=Quickshell.env("EVENTS_EXPECTED").split("|")
     root.check(JSON.stringify(Events.getDurableEvents().map(event=>event.title))===JSON.stringify(expected),"restart durable readback lost saved events")
     root.check(root.acknowledgements===0,"startup read emitted a new mutation acknowledgement")
     root.finish();return
    }
    root.check(Events.getDurableEvents().length===0,"private seed was not empty")
    const first=Events.addEvent("Alpha","","2099-01-01T09:00:00Z","general","normal",0,"none","",false)
    Events.addEvent("Beta","","2099-01-01T10:00:00Z","general","normal",0,"none","",false)
    Events.updateEvent(first.id,{title:"Alpha updated"})
    root.check(Events._saving && Events._saveQueued,"fixture did not overlap saves")
    root.check(Events.getDurableEvents().length===0,"unsaved event appeared durable")
    Events.loadFromFile()
    root.check(Events.ready && Events.list.length===2,"refresh discarded unsaved edits")
    root.phase=1
   } else if(root.phase===1 && Events.ready && !Events.persistenceBusy) {
    root.check(JSON.stringify(Events.getDurableEvents().map(event=>event.title))===JSON.stringify(["Alpha updated","Beta"]),"latest coalesced snapshot lost edits")
    root.check(root.snapshots.some(titles=>titles.length===1 && titles[0]==="Alpha"),"first acknowledgement leaked a later in-memory edit")
    root.check(root.snapshots.some(titles=>titles.length===2 && titles[0]==="Alpha updated"),"latest snapshot was never acknowledged")
    const count=root.acknowledgements;Events.saveToFile()
    root.check(!Events._saving && root.acknowledgements===count,"acknowledged no-op started or fabricated a write")
    if(root.action==="normal"){root.finish();return}
    if(root.action==="cached") {
     // Fault injection: a write may have failed with FileView's cache equal
     // to requested bytes. Exercise the real fresh writer, not a fake ack.
     Events._lastSavedJson="";Events._saveFailed=true;Events.saveToFile()
     root.check(Events._uncachedWriter!==null && Events._saving,"cached-byte retry did not use an actual uncached writer")
     root.beforeFailure=count;root.phase=5;return
    }
    root.phase=2;permissions.running=true
   } else if(root.phase===3 && Events._saveFailed && !permissions.running) {
    root.check(Events.errorMessage.length>0 && Events.persistenceBusy,"failed write missing pending/error feedback")
    root.check(Events.list.length===3 && Events.getDurableEvents().length===2,"denied write discarded memory or published a phantom event")
    root.check(root.acknowledgements===root.beforeFailure,"failed save emitted a durability acknowledgement")
    permissions.running=true
   } else if(root.phase===4 && !Events.persistenceBusy) {
    root.check(Events.errorMessage.length===0 && Events.getDurableEvents().length===3,"explicit retry failed to acknowledge the retained event")
    root.check(root.acknowledgements>root.beforeFailure,"retry emitted no real acknowledgement")
    root.finish()
   } else if(root.phase===5 && !Events.persistenceBusy) {
    root.check(root.acknowledgements===root.beforeFailure+1 && Events.getDurableEvents().length===2,"cached-byte retry fabricated/duplicated completion")
    root.finish()
   }
  }catch(error){console.error("EVENTS_DURABLE_FAIL",root.action,error.message,error.stack);Qt.quit()}}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='alis-events-durable-') as name:
 base=Path(name)
 evidence=Path(os.environ.get('ALIS_EVENTS_EVIDENCE',base/'evidence'));evidence.mkdir(parents=True,exist_ok=True)
 for action in ['normal','failure','cached']:
  folder=base/action;folder.mkdir()
  for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
  (folder/'shell.qml').write_text(QML)
  env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
  for key in ['QS_CONFIG_NAME','QS_CONFIG_PATH','QS_MANIFEST','NIRI_SOCKET','WAYLAND_DISPLAY']:env.pop(key,None)
  for kind in ['config','state','cache','data','runtime']:
   path=folder/kind;path.mkdir(mode=0o700);env['XDG_'+kind.upper()+('_DIR' if kind=='runtime' else '_HOME')]=str(path)
  config=folder/'config/alis';config.mkdir();(config/'config.json').write_bytes((ROOT/'defaults/config.json').read_bytes())
  file=folder/'state/quickshell/user/events.json';file.parent.mkdir(parents=True);file.write_text(json.dumps({'nextId':1,'events':[]},indent=2))
  for stage in [action,'restart']:
   expected='Alpha updated|Beta'+('|Denied' if action=='failure' else '')
   result=run_qs(folder,dict(env,EVENTS_ACTION=stage,EVENTS_EXPECTED=expected),timeout=16)
   (evidence/(action+'-'+stage+'.log')).write_text(result.stdout)
   bad=['EVENTS_DURABLE_FAIL','ReferenceError:','TypeError:','Binding loop','Unable to assign','Failed to load configuration']
   if result.returncode or 'EVENTS_DURABLE_PASS' not in result.stdout or any(word in result.stdout for word in bad):print(result.stdout);raise SystemExit(1)
   disk=json.loads(file.read_text());assert [event['title'] for event in disk['events']]==expected.split('|'),(stage,disk)
   (evidence/(action+'-'+stage+'-disk.json')).write_text(json.dumps(disk,indent=2)+'\n')
   for line in result.stdout.splitlines():
    if 'EVENTS_DURABLE_PASS' in line:print(line)
