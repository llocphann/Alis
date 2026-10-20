#!/usr/bin/env python3
"""Run from repo root. --focus temporarily focuses private Niri and restores focus.
--encoder explicitly records ONLY that private display without audio.
Never invokes the production record.sh or stops an existing recorder.
"""
import ast,sys,os,tempfile,json,subprocess,time,signal,importlib.util,hashlib
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland
from native_wayland_input import native_input
spec=importlib.util.spec_from_file_location('frames',root/'scripts/collect-abyss-notification-frames.py');frames=importlib.util.module_from_spec(spec);spec.loader.exec_module(frames)
qml=r'''import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
ShellRoot {
 id:root
 Component.onCompleted: {Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true}
 Loader {id:critical;active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 IpcHandler {
  target:"pointerDiagnostic"
  function dimensions():string {return JSON.stringify({screens:Quickshell.screens.map(s=>({name:s.name,width:s.width,height:s.height}))})}
  function configure(value:string):string {const p=JSON.parse(value);Config.setNestedValues({"performance.reduceAnimations":p.reduce,"bar.autoHide.enable":p.autoHide,"abyss.modules.placements":[{id:"subject",kind:p.kind,edge:p.edge,position:.35}]});return JSON.stringify(p)}
  function shoulder(value:string):string {
   const o=JSON.parse(value),slot=o.popupSlots.find(s=>s?.requestedVisible);if(!slot)return JSON.stringify({error:"no requested slot"})
   const g=slot.hoverGeometry,raw=g.rawSurface,record={surface:Qt.rect(raw.x,raw.y,raw.w,raw.h)}
   const rows=Geometry.popupShoulders(g.outputWidth,g.outputHeight,g.connectionInsets,g.edge,record,AbyssStyle.perimeterRadius,AbyssStyle.connectionDepth,AbyssStyle.neckRadius)
   const outside=rows.filter(r=>r.width>=2&&r.height>=1).map(r=>({x:r.x+r.width/2,y:r.y+r.height/2})).filter(p=>!Geometry.rectContains(Qt.rect(slot.bounds.x,slot.bounds.y,slot.bounds.w,slot.bounds.h),p.x,p.y)&&!o.modules.some(m=>m.input&&Geometry.rectContains(Qt.rect(m.input.x,m.input.y,m.input.w,m.input.h),p.x,p.y)))
   return JSON.stringify({point:outside[Math.floor(outside.length/2)]??null,count:outside.length,stripCount:rows.length,edge:g.edge,radius:AbyssStyle.perimeterRadius,softness:AbyssStyle.connectionDepth})
  }
 }
}
'''
qml=qml.replace('import qs\n','import qs\nimport qs.services\n');qml=qml.replace('GlobalStates.abyssColdPerimeterRecreatePending=true','GlobalStates.abyssColdPerimeterRecreatePending=true;Notifications.ensureInitialized()')
qml=qml.replace(' IpcHandler {',' Process {id:sender}\n IpcHandler {',1)
qml=qml.replace('  function dimensions()',r'''  function quit():void{Qt.quit()}
  function recorder():string{RecorderStatus.refreshStatus();return JSON.stringify({pid:RecorderStatus.recorderPid,recording:RecorderStatus.isRecording})}
  function notify(timeout:int):string{
   if(sender.running || ![1000,2500].includes(timeout))return JSON.stringify({accepted:false})
   sender.command=["notify-send","-a","Alis private fixture","-t",String(timeout),"--hint=boolean:transient:true","--hint=boolean:suppress-sound:true","Starting recording","Synthetic private presentation only"]
   sender.running=true;return JSON.stringify({accepted:true})
  }
  function dimensions()''')
base=Path(tempfile.mkdtemp(prefix='alis-notification-native-'));os.chmod(base,0o700);folder=base/'fixture';folder.mkdir()
for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(root/entry)
(folder/'shell.qml').write_text(qml);results=[];encoder=None;encoder_exit=None;qt_exit=None
with private_wayland(folder,capture_focus="--focus" in sys.argv) as env:
 assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
 cfg=folder/'config/alis';cfg.mkdir(parents=True);data=json.loads((root/'defaults/config.json').read_text());data['panelFamily']='abyss';data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup','abyssNotificationCenter','abyssNotificationPopup','abyssOnScreenDisplay','iiRecordingOsd'];data['abyss']['companion']['enabled']=False;data['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':'subject','kind':'clock','edge':'top','position':.35}]);data['bar']['autoHide']['enable']=False;data['bar'].setdefault('visualizer',{})['enable']=False;data['sounds']['notifications']=False;data['screenRecord']['audioMode']='none';(cfg/'config.json').write_text(json.dumps(data))
 log=(base/'native.log').open('w');proc=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 def ipc(target,method,*args):
  r=subprocess.run(['qs','-p',str(folder),'ipc','call',target,method,*args],env=env,capture_output=True,text=True,timeout=4)
  if r.returncode:raise RuntimeError(r.stderr[-200:])
  return json.loads(r.stdout) if method!='quit' else None
 def snap():return ipc('abyssHoverProbe','snapshot')
 def start():frames.validate_frame_probe_start(ipc('abyssHoverProbe','startFrames'))
 def stop(label,before):
  raw=ipc('abyssHoverProbe','stopFrames');frames.validate_frame_probe_stop(raw);safe=frames.sanitize_frames(raw);after=frames.sanitize_snapshot(snap());status='INCOMPLETE_TRACE' if frames.trace_incomplete({'frames':safe}) else 'CAPTURED'
  results.append({'phase':label,'status':status,'before':before,'after':after,'frames':safe});print(label,status,[{'count':x['metrics']['count'],'p95':x['metrics']['p95'],'heartbeatMax':x['metrics']['heartbeatMaxIntervalMs'],'notificationFrames':len(x['notificationFrames'])} for x in safe],flush=True)
 try:
  deadline=time.monotonic()+18
  while time.monotonic()<deadline:
   try:s=snap()
   except Exception:time.sleep(.2);continue
   if s.get('outputs') and s['outputs'][0]['fieldReady'] and s['outputs'][0]['modules']:break
   time.sleep(.2)
  else:raise RuntimeError('production field not ready')
  time.sleep(2);dims=ipc('pointerDiagnostic','dimensions')['screens'][0];w,h=dims['width'],dims['height']
  with native_input(folder,env) as pointer:
   assert pointer
   pointer.move(w*.45,h*.5,w,h)
   for cycle in range(2):
    before=frames.sanitize_snapshot(snap());start();assert ipc('pointerDiagnostic','notify','1000')['accepted'];time.sleep(2.1);stop('toast-open-close-'+str(cycle),before);time.sleep(.4)
   before=frames.sanitize_snapshot(snap());assert ipc('pointerDiagnostic','notify','2500')['accepted'];time.sleep(.3);start();o=snap()['outputs'][0];m=next(m for m in o['modules'] if m['kind']=='notificationActivity');r=m['input'];pointer.move(r['x']+r['w']/2,r['y']+r['h']/2,w,h);time.sleep(1.5);stop('toast-present-edge-hover',before);pointer.move(w*.45,h*.5,w,h);time.sleep(1.8)
   foreign=subprocess.run(['pgrep','-x','wf-recorder'],capture_output=True)
   if '--encoder' not in sys.argv:results.append({'phase':'record-start','status':'UNRUN','reason':'use --encoder explicitly for private video-only capture'})
   elif foreign.returncode==0:results.append({'phase':'record-start','status':'BLOCKED_EXISTING_RECORDER','side_effect':'no recorder started or stopped'})
   else:
    outputs=json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True));name=next(iter(outputs.values()))['name'];before=frames.sanitize_snapshot(snap());start()
    encoderlog=(base/'encoder.log').open('w');encoder=subprocess.Popen(['wf-recorder','-o',name,'--no-dmabuf','-f',str(base/'synthetic.mp4'),'-r','30','-c','libx264','-p','preset=ultrafast','-p','crf=28'],env=env,stdout=encoderlog,stderr=subprocess.STDOUT,start_new_session=True)
    deadline=time.monotonic()+2
    while time.monotonic()<deadline:
     state=ipc('pointerDiagnostic','recorder')
     if state['pid']==encoder.pid and state['recording']:break
     if encoder.poll() is not None:raise RuntimeError('private encoder failed')
     time.sleep(.1)
    else:raise RuntimeError('private RecorderStatus did not bind exact owned PID')
    time.sleep(.65);assert ipc('pointerDiagnostic','notify','1000')['accepted'];time.sleep(2.1);stop('private-encoder-start-and-toast',before)
    encoder.send_signal(signal.SIGINT);encoder_exit=encoder.wait(timeout=6);encoderlog.close();ipc('pointerDiagnostic','recorder');time.sleep(1)
  ipc('pointerDiagnostic','quit');qt_exit=proc.wait(timeout=4)
 except Exception as error:print('DIAGNOSTIC_ERROR',type(error).__name__,str(error),flush=True)
 finally:
  if encoder and encoder.poll() is None:
   encoder.send_signal(signal.SIGINT)
   try:encoder.wait(timeout=4)
   except subprocess.TimeoutExpired:encoder.kill();encoder.wait()
  if proc.poll() is None:
   os.killpg(proc.pid,signal.SIGTERM)
   try:proc.wait(timeout=3)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
  log.close();receipt={'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'actual_qt_exit':proc.returncode,'actual_encoder_exit':encoder.returncode if encoder else None,'scope':'focused private Niri actual frames and heartbeat; synthetic notifications; optional real encoder captures only this distinct private display without audio; production record.sh not invoked','results':results};(base/'result.json').write_text(json.dumps(receipt,indent=2)+'\n');Path('/tmp/alis-notification-native-path').write_text(str(base));print('EVIDENCE',base,'ACTUAL_QT_EXIT',proc.returncode,flush=True)
