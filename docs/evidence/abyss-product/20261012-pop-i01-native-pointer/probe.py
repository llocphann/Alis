from pathlib import Path
import tempfile,subprocess,sys,json,os,time,signal
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'scripts'));from native_test_session import private_wayland
BASE=ROOT/'.git/maintainer-validation/pop-native';records=[]
with tempfile.TemporaryDirectory(prefix='alis-popup-wl-pointer-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text('''import QtQuick
import Quickshell
import qs
import qs.modules.common
ShellRoot {
 Component.onCompleted: {Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true}
 Loader {active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
}
''')
 with private_wayland(folder) as env:
  assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup'];data['abyss']['companion']['enabled']=False;data['abyss']['modules']['configured']=True;data['abyss']['modules']['placements']=[{'id':'clock','kind':'clock','edge':'top','position':.35}];data['performance']['reduceAnimations']=True
  (cfg/'config.json').write_text(json.dumps(data));log=(BASE/'native-pointer.log').open('w')
  process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  pointer=None
  try:
   def snapshot():
    r=subprocess.run(['qs','-p',str(folder),'ipc','call','abyssHoverProbe','snapshot'],env=env,text=True,capture_output=True,timeout=5)
    return json.loads(r.stdout) if r.returncode==0 and r.stdout.startswith('{') else None
   deadline=time.monotonic()+12;s=None
   while time.monotonic()<deadline:
    s=snapshot()
    if s and s.get('outputs') and s['outputs'][0].get('fieldReady'):break
    time.sleep(.2)
   time.sleep(1.5);s=snapshot();records.append({'stage':'ready','snapshot':s})
   assert s and s['outputs'][0]['modules'],'private field/module never became ready'
   outputs=json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True));output=next(iter(outputs.values()));logical=output['logical'];w,h=logical['width'],logical['height']
   pointer=subprocess.Popen([str(BASE/'client'),env['WAYLAND_DISPLAY']],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
   assert pointer.stdout.readline().startswith('READY')
   module=s['outputs'][0]['modules'][0];rect=module['rect'];x=rect['x']+rect['w']/2;y=rect['y']+rect['h']/2
   def move(stage,x,y,wait=.6):
    pointer.stdin.write(f'{int(x)} {int(y)} {w} {h}\n');pointer.stdin.flush();assert pointer.stdout.readline().strip()=='ACK';time.sleep(wait);records.append({'stage':stage,'sent':[x,y,w,h],'snapshot':snapshot()})
   move('source',x,y,1)
   state=records[-1]['snapshot']['outputs'][0];slots=[slot for slot in state['popupSlots'] if slot];print('module_hover',state['modules'][0]['hovered'],'slots',len(slots),flush=True)
   if slots:
    c=slots[0]['content'];b=slots[0]['bounds'];move('bridge',x,(rect['y']+rect['h']+c['y'])/2,1);move('body',c['x']+c['w']/2,c['y']+c['h']/2,1);move('outside',w/2,h*.8,1)
   (BASE/'pointer-trace.json').write_text(json.dumps({'classification':'diagnostic real private compositor protocol input; not owner acceptance/product repair','source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'records':records},indent=2)+'\n')
  finally:
   if pointer:
    pointer.stdin.close();pointer.wait(timeout=3)
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=4)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   log.close()
