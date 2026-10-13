from pathlib import Path
import os,sys,json,tempfile,time,subprocess,signal,socket,hashlib
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland
OUT=ROOT/'.git/maintainer-validation/20261013-r09-warm-panel';CLIENT=ROOT/'.git/maintainer-validation/pop-native-stack/client'
rows=[];traces=[]
source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
dirty=subprocess.check_output(['git','status','--porcelain'],text=True)
with tempfile.TemporaryDirectory(prefix='alis-r09-qml-profile-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
ShellRoot {
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true}
 Loader {active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 IpcHandler {
  target:"motionQA"
  function start():string {console.profile();return JSON.stringify({started:Date.now()})}
  function stop():string {console.profileEnd();return JSON.stringify({stopped:Date.now()})}
  function toggleDashboard():string {GlobalStates.dashboardOpen=!GlobalStates.dashboardOpen;return JSON.stringify({open:GlobalStates.dashboardOpen,t:Date.now()})}
  function quit():void {Qt.quit()}
 }
}''')
 with private_wayland(folder) as env:
  assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  v=json.loads((ROOT/'defaults/config.json').read_text());v['panelFamily']='abyss';v['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup','iiDashboard'];v['performance']['reduceAnimations']=False;v['abyss']['companion']['enabled']=False;v['abyss']['waves']['enabled']=False
  v['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':k,'kind':k,'edge':'top','position':p}for k,p in [('resources',.18),('clock',.50),('weather',.78)]])
  v['bar']['autoHide']['enable']=False;v['bar'].setdefault('visualizer',{})['enable']=False
  (cfg/'config.json').write_text(json.dumps(v))
  with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
  log=(OUT/'native.log').open('w');process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color','--debug',str(port)],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  pointer=None;profiler=None
  def ipc(method,target='abyssHoverProbe'):
   r=subprocess.run(['qs','-p',str(folder),'ipc','call',target,method],env=env,capture_output=True,text=True,timeout=5)
   if r.returncode:raise RuntimeError(r.stderr[-200:])
   return json.loads(r.stdout) if r.stdout.strip() else None
  try:
   deadline=time.monotonic()+18
   while time.monotonic()<deadline:
    try:s=ipc('snapshot')
    except Exception:time.sleep(.1);continue
    if s.get('outputs') and s['outputs'][0].get('fieldReady') and len(s['outputs'][0].get('modules',[]))==3:break
    time.sleep(.1)
   else:raise RuntimeError('no ready production field')
   time.sleep(2)
   plog=(OUT/'profiler.log').open('w')
   profiler=subprocess.Popen(['/usr/lib/qt6/bin/qmlprofiler','--attach','127.0.0.1','--port',str(port),'--record','off','--include','binding,creating,scenegraph,animations','--output',str(OUT/'warm-motion.qtd')],env=env,stdout=plog,stderr=subprocess.STDOUT,start_new_session=True)
   time.sleep(.8)
   pointer=subprocess.Popen([str(CLIENT),env['WAYLAND_DISPLAY'],os.environ['WAYLAND_DISPLAY']],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
   assert pointer.stdout.readline().startswith('READY')
   outputs=json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True));size=next(iter(outputs.values()))['logical']
   def move(x,y):
    pointer.stdin.write(f'M {round(max(0,x)*64)} {round(max(0,y)*64)} {size["width"]*64} {size["height"]*64}\n');pointer.stdin.flush();assert pointer.stdout.readline().strip()=='ACK'
   ipc('toggleDashboard','motionQA');time.sleep(.7);ipc('toggleDashboard','motionQA');time.sleep(.3)
   rows.append({'stage':'profile-start','receipt':ipc('start','motionQA')})
   for run in range(1):
    ipc('startFrames')
    for cycle in range(3):
     for kind in ['resources','clock','weather','resources']:
      state=ipc('snapshot')['outputs'][0];m=next(m for m in state['modules']if m['id']==kind);r=m['rect'];move(r['x']+r['w']/2,r['y']+r['h']/2)
      rows.append({'stage':f'{run}/{cycle}/{kind}','timeMs':round(time.time()*1000)});time.sleep(.38)
    traces.append({'stage':f'popups/{run}','trace':ipc('stopFrames')})
    move(size['width']*.1,size['height']*.8);time.sleep(.5)
   ipc('startFrames')
   for cycle in range(6):
    rows.append({'stage':f'dashboard/{cycle}','receipt':ipc('toggleDashboard','motionQA')});time.sleep(.4)
   dashboardTrace=ipc('stopFrames');traces.append({'stage':'dashboard','trace':dashboardTrace})
   assert any(t['panelProgressChangedFrames']>0 for t in dashboardTrace),'Dashboard had no actual active motion'
   rows.append({'stage':'profile-stop','receipt':ipc('stop','motionQA')});time.sleep(.8)
   ipc('quit','motionQA');process.wait(timeout=5);profiler.wait(timeout=8);plog.close()
   (OUT/'result.json').write_text(json.dumps({'source_sha':source,'dirty':dirty,'scope':'local GPU private no-focus Niri; actual popup wl_pointer, programmatic Dashboard; Waves/Companion/Spectrum off; Qt profiler adds overhead; not owner or matched performance acceptance','rows':rows,'traces':traces,'profiler_exit':profiler.returncode},indent=2))
   for trace in traces:
    print(trace['stage'],json.dumps([{k:t[k]for k in ['count','p50','p95','p99','max','panelProgressChangedFrames','popupOpenFrames','heartbeatOver100Ms','heartbeatMaxIntervalMs']}for t in trace['trace']]),flush=True)
   print('TRACE_BYTES', (OUT/'warm-motion.qtd').stat().st_size)
  finally:
   if pointer:pointer.stdin.close();pointer.wait(timeout=3)
   for child in [profiler,process]:
    if child and child.poll()is None:
     os.killpg(child.pid,signal.SIGTERM)
     try:child.wait(timeout=4)
     except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
   log.close()
