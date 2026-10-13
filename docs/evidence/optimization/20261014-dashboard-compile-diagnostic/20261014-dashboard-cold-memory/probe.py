from pathlib import Path
import tempfile,sys,json,threading,time,subprocess
r=Path('/tmp/alis-panel-exact-4d8ea01bb');sys.path.insert(0,str(r/'scripts'))
from native_test_session import private_wayland,run_qs
out=Path.cwd()/'.git/maintainer-validation/20261014-dashboard-cold-memory'
with tempfile.TemporaryDirectory(prefix='alis-dashboard-residency-trace-')as name:
 f=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(f/entry).symlink_to(r/entry)
 (f/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root;property bool shown:false;property bool collect:false
 property string stage:"boot";property var frames:[];property var events:[]
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true}
 PanelWindow {
  visible:true;color:"#111820";anchors {top:true;bottom:true;left:true;right:true}
  exclusionMode:ExclusionMode.Ignore
  AbyssBodyHost {
   id:body;identity:"dashboard";anchors.fill:parent;edge:"bottom";open:root.shown
   stableContentSize:true;warmContent:true;largeSurface:true
   span:width*.88;depth:height*.88;along:width*.06
   source:Qt.resolvedUrl("modules/abyss/content/AbyssDashboardContent.qml")
   onReadyChanged:if(root.collect)root.events.push({stage:root.stage,kind:"ready",time:Date.now(),ready:ready})
  }
 }
 Connections {
  target:body.Window.window;enabled:root.collect
  function onFrameSwapped(){if(root.frames.length<600)root.frames.push({stage:root.stage,time:Date.now(),progress:body.progress,ready:body.ready,width:body.contentItem.item?.width??0,height:body.contentItem.item?.height??0})}
 }
 TestCase {
  id:test;when:false;optional:true
  function toggle(stage,opened){root.stage=stage;const before=Date.now();root.shown=opened;root.events.push({stage:stage,kind:"request",before:before,after:Date.now(),open:opened})}
  function run(){try{
   tryCompare(Config,"ready",true,5000);wait(700);root.collect=true
   toggle("cold-open",true);tryVerify(()=>body.ready,7000);const initial=body.contentItem.item;wait(1400)
   toggle("warm-close",false);wait(700)
   toggle("warm-open",true);wait(1100);if(body.contentItem.item!==initial)throw new Error("warm reopen recreated content")
   toggle("expire-close",false);wait(2400);if(body.ready)throw new Error("closed tree failed to expire")
   toggle("expired-open",true);tryVerify(()=>body.ready,5000);wait(1400)
   root.collect=false
   console.info("DASHBOARD_RESIDENCY_TRACE_PASS",JSON.stringify({events:root.events,frames:root.frames}))
  }catch(e){console.error("DASHBOARD_RESIDENCY_TRACE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {running:true;interval:120;onTriggered:test.run()}
}''')
 with private_wayland(f)as env:
  assert env
  cfg=f/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  v=json.loads((r/'defaults/config.json').read_text());v['panelFamily']='abyss';v['abyss']['companion']['enabled']=False;v['abyss']['waves']['enabled']=False
  (cfg/'config.json').write_text(json.dumps(v))
  stopped=threading.Event();memory=[]
  def monitor():
   pid=None
   while not stopped.is_set():
    try:
     if pid is None:
      instances=json.loads(subprocess.check_output(['qs','list','--all','--json'],text=True))
      candidates=[a for a in instances if a['config_path']==str(f/'shell.qml')]
      if candidates:pid=candidates[0]['pid']
     if pid:
      rollup=(Path('/proc')/str(pid)/'smaps_rollup').read_text()
      memory.append({'time':round(time.time()*1000),'kib':{line.split(':')[0]:int(line.split()[1])for line in rollup.splitlines()if line.startswith(('Rss:','Pss:','Private_Dirty:'))}})
    except (OSError,ValueError,subprocess.SubprocessError):pass
    stopped.wait(.2)
  watcher=threading.Thread(target=monitor);watcher.start()
  try:result=run_qs(f,env,30)
  finally:stopped.set();watcher.join(timeout=4)
  (out/'memory.json').write_text(json.dumps(memory,indent=2)+'\n');(out/'native.log').write_text(result.stdout)
  for line in result.stdout.splitlines():
   if 'DASHBOARD_RESIDENCY_TRACE_PASS'in line:
    data=json.loads(line.split('DASHBOARD_RESIDENCY_TRACE_PASS ',1)[1]);(out/'result.json').write_text(json.dumps({'source_sha':'4d8ea01bb40c7c30a0ec28f3c2d276d5c52da45c','scope':'production BodyHost and actual Dashboard content; private no-focus full-output window, programmatic cold/warm/expiry; no shared Field shader or owner performance claim',**data},indent=2)+'\n')
    print(data['events']);print('frames',len(data['frames']))
  assert result.returncode==0 and 'DASHBOARD_RESIDENCY_TRACE_PASS'in result.stdout and 'DASHBOARD_RESIDENCY_TRACE_FAIL'not in result.stdout
