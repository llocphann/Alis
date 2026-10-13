from pathlib import Path
import json,os,sys,tempfile,time,subprocess,signal,hashlib
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland
OUT=ROOT/'.git/maintainer-validation/20261013-notification-depth-before';CLIENT=ROOT/'.git/maintainer-validation/pop-native-stack/client'
rows=[];traces=[]
with tempfile.TemporaryDirectory(prefix='alis-common-popups-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(r'''import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
ShellRoot {
 id:root
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true;Notifications.ensureInitialized()}
 Loader {active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 Process {id:sender}
 IpcHandler {
  target:"notificationQA"
  function notify(kind:string):string {
   if(sender.running)return JSON.stringify({accepted:false})
   sender.command=["notify-send","-a","Presentation QA","-t","15000","--hint=boolean:transient:true","--hint=boolean:suppress-sound:true",kind,kind==="Recording saved"?"file:///tmp/Synthetic-recording-with-a-deliberately-long-name-to-exercise-the-shared-notification-layout-20261013.mp4":"Synthetic presentation-only event; no recording or audio captured"]
   sender.running=true
   return JSON.stringify({accepted:true,synthetic:true})
  }
 }
}''')
 with private_wayland(folder) as env:
  assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  v=json.loads((ROOT/'defaults/config.json').read_text());v['panelFamily']='abyss';v['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup','abyssNotificationCenter','abyssNotificationPopup'];v['sounds']['notifications']=False;v['performance']['reduceAnimations']=False;v['abyss']['companion']['enabled']=False;v['abyss']['waves']['enabled']=False
  v['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':k,'kind':k,'edge':'top','position':p}for k,p in [('resources',.18),('clock',.50),('weather',.78)]])
  v['bar']['autoHide']['enable']=False;v['bar'].setdefault('visualizer',{})['enable']=False
  (cfg/'config.json').write_text(json.dumps(v))
  log=(OUT/'native.log').open('w');process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  pointer=None
  def ipc(method):
   r=subprocess.run(['qs','-p',str(folder),'ipc','call','abyssHoverProbe',method],env=env,capture_output=True,text=True,timeout=5)
   if r.returncode:raise RuntimeError(r.stderr[-200:])
   return json.loads(r.stdout)
  try:
   deadline=time.monotonic()+18
   while time.monotonic()<deadline:
    try:s=ipc('snapshot')
    except Exception:time.sleep(.1);continue
    if s.get('outputs') and s['outputs'][0].get('fieldReady') and len(s['outputs'][0].get('modules',[]))==3:break
    time.sleep(.1)
   else:raise RuntimeError('no ready production field')
   time.sleep(1.5)
   pointer=subprocess.Popen([str(CLIENT),env['WAYLAND_DISPLAY'],os.environ['WAYLAND_DISPLAY']],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
   assert pointer.stdout.readline().startswith('READY')
   def dims():
    outputs=json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True));return next(iter(outputs.values()))['logical']
   def move(x,y):
    d=dims();pointer.stdin.write(f'M {round(max(0,x)*64)} {round(max(0,y)*64)} {d["width"]*64} {d["height"]*64}\n');pointer.stdin.flush();assert pointer.stdout.readline().strip()=='ACK'
   def record(stage):rows.append({'stage':stage,'t':time.monotonic(),'snapshot':ipc('snapshot')})
   record('ready')
   def sample(stage,action=None,seconds=1.4):
    ipc('startFrames')
    if action:action()
    start=time.monotonic()
    while time.monotonic()-start<seconds:
     record(stage);time.sleep(.10)
    trace=ipc('stopFrames');traces.append({'stage':stage,'frames':trace})
    print(stage,json.dumps(trace),flush=True)
   def notify(kind):
    result=subprocess.run(['qs','-p',str(folder),'ipc','call','notificationQA','notify',kind],env=env,capture_output=True,text=True,timeout=5)
    assert result.returncode==0,result.stderr
   size=dims();move(size['width']*.15,size['height']*.5)
   sample('baseline',seconds=1)
   for cycle in range(2):
    sample(f'{cycle}/toast-open',lambda:notify('Starting recording'))
    sample(f'{cycle}/toast-to-center',lambda:move(size['width']-5,size['height']-5),seconds=2)
    sample(f'{cycle}/center-exit',lambda:move(size['width']*.15,size['height']*.5),seconds=2)
    sample(f'{cycle}/saved-toast',lambda:notify('Recording saved'),seconds=2)
   (OUT/'result.json').write_text(json.dumps({'classification':'private production notification presentation on local GPU; actual wl_pointer and real isolated D-Bus synthetic notifications; no real video encoder, installed/owner acceptance or optimization claim','source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'rows':rows,'traces':traces},indent=2))
  finally:
   try:ipc('stopFrames')
   except Exception:pass
   if pointer:pointer.stdin.close();pointer.wait(timeout=3)
   if process.poll()is None:
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=4)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   log.close()
