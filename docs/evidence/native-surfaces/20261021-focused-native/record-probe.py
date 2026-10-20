#!/usr/bin/env python3
"""Opt-in --focus --producer: real record.sh on a private display and D-Bus.
Producer PATH guards deny pgrep/pkill/pactl; real wf-recorder adds --no-dmabuf.
Captures private video only. Never run this producer without its guards.
No installed/physical/Owner acceptance or unmodified-encoder-argv claim.
"""
import ast,sys,os,tempfile,json,subprocess,time,signal,importlib.util,hashlib,shlex
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
qml=qml.replace(' Process {id:sender}', ' Process {id:sender}\n property int producerExit:-999\n Process {id:producer;onExited:(code,status)=>{root.producerExit=code}}')
qml=qml.replace('  function recorder()', '\n  function startProducer():string{if(producer.running)return JSON.stringify({accepted:false});producer.command=["/usr/bin/bash",Quickshell.env("ALIS_NATIVE_RECORD_LAUNCHER")];producer.running=true;return JSON.stringify({accepted:true})}\n  function producerState():string{return JSON.stringify({running:producer.running,exit:root.producerExit,pid:RecorderStatus.recorderPid,recording:RecorderStatus.isRecording,startToast:Notifications.popupList.some(n=>n.summary==="Starting recording")})}\n  function recorder()')
base=Path(os.environ['ALIS_NATIVE_NOTIFICATION_EVIDENCE_DIR']);base.mkdir(mode=0o700);os.chmod(base,0o700);folder=base/'fixture';folder.mkdir()
for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(root/entry)
(folder/'shell.qml').write_text(qml);results=[];encoder=None;encoder_exit=None;qt_exit=None;owned_pid=None;owned_birth=None;producer_exit=None;errors=[]
with private_wayland(folder,capture_focus="--focus" in sys.argv) as env:
 assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
 cfg=folder/'config/alis';cfg.mkdir(parents=True);data=json.loads((root/'defaults/config.json').read_text());data['panelFamily']='abyss';data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup','abyssNotificationCenter','abyssNotificationPopup','abyssOnScreenDisplay','iiRecordingOsd'];data['abyss']['companion']['enabled']=False;data['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':'subject','kind':'clock','edge':'top','position':.35}]);data['bar']['autoHide']['enable']=False;data['bar'].setdefault('visualizer',{})['enable']=False;data['sounds']['notifications']=False;data['screenRecord'].update(audioMode='none',savePath=str(base/'video'),accelerationMode='software',videoCodec='libx264',fps=30,preset='ultrafast',crf=28,enableFallback=False,showNotifications=True);data['screenRecord']['discordCompress']={'enabled':False};(cfg/'config.json').write_text(json.dumps(data))
 guard=base/'producer-guards';guard.mkdir();pidfile=base/'owned-recorder.pid';guardlog=base/'producer-guards.log'
 for command in ['pgrep','pkill','pactl']:
  path=guard/command;path.write_text('#!/bin/sh\nprintf "%s %s\\n" '+shlex.quote(command)+' "$*" >> "$ALIS_GUARD_LOG"\nexit '+('1' if command=='pgrep' else '125')+'\n');path.chmod(0o700)
 wf=guard/'wf-recorder';wf.write_text('#!/bin/sh\nprintf "%s\\n" "$$" > "$ALIS_TEST_RECORDER_PID"\nexec /usr/bin/wf-recorder --no-dmabuf "$@"\n');wf.chmod(0o700)
 launcher=base/'start-owned-recording.sh';launcher.write_text('#!/usr/bin/bash\nexport PATH='+shlex.quote(str(guard)+os.pathsep+env['PATH'])+'\nexport ALIS_GUARD_LOG='+shlex.quote(str(guardlog))+'\nexport ALIS_TEST_RECORDER_PID='+shlex.quote(str(pidfile))+'\nexec /usr/bin/bash '+shlex.quote(str(root/'scripts/videos/record.sh'))+' --fullscreen\n');launcher.chmod(0o700)
 def owned_alive():
  if not owned_pid or not owned_birth:return False
  try:
   raw=Path('/proc',str(owned_pid),'stat').read_text();parts=raw[raw.rfind(')')+2:].split()
   return parts[19]==owned_birth and Path('/proc',str(owned_pid),'comm').read_text().strip()=='wf-recorder'
  except (OSError,IndexError):return False
 log=(base/'native.log').open('w');proc=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1',ALIS_NATIVE_RECORD_LAUNCHER=str(launcher)),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
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
   foreign=subprocess.run(['/usr/bin/pgrep','-x','wf-recorder'],capture_output=True)
   if '--producer' not in sys.argv:raise RuntimeError('explicit --producer required')
   if foreign.returncode==0:raise RuntimeError('existing recorder: producer was not started')
   before=frames.sanitize_snapshot(snap());start();assert ipc('pointerDiagnostic','startProducer')['accepted']
   deadline=time.monotonic()+8;bound=False
   while time.monotonic()<deadline:
    if pidfile.exists() and owned_pid is None:
     owned_pid=int(pidfile.read_text().strip());raw=Path('/proc',str(owned_pid),'stat').read_text();owned_birth=raw[raw.rfind(')')+2:].split()[19]
    state=ipc('pointerDiagnostic','recorder')
    if owned_pid and owned_alive() and state['pid']==owned_pid and state['recording']:bound=True;break
    time.sleep(.1)
   if not bound:raise RuntimeError('RecorderStatus did not bind exact owned producer PID')
   deadline=time.monotonic()+4;observed=False
   while time.monotonic()<deadline:
    state=ipc('pointerDiagnostic','producerState')
    if state['startToast']:observed=True;break
    if not state['running']:raise RuntimeError('producer exited before startup notification')
    time.sleep(.08)
   if not observed:raise RuntimeError('actual production startup toast not observed')
   time.sleep(.4);stop('guarded-production-record-start',before);results[-1].update(actual_start_toast_observed=True,recorder_binding_exact=True)
   if not owned_alive():raise RuntimeError('owned recorder identity changed before stop')
   os.kill(owned_pid,signal.SIGINT)
   deadline=time.monotonic()+8
   while time.monotonic()<deadline:
    state=ipc('pointerDiagnostic','producerState')
    if not state['running']:producer_exit=state['exit'];break
    time.sleep(.1)
   if producer_exit!=0:raise RuntimeError('producer did not exit cleanly: '+str(producer_exit))
   videos=list((base/'video').glob('*.mp4'))
   if len(videos)!=1:raise RuntimeError('private recording file missing/ambiguous')
   check=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type','-of','json',str(videos[0])],capture_output=True,text=True,timeout=5,check=True)
   types=[x['codec_type'] for x in json.loads(check.stdout)['streams']]
   if 'video' not in types or 'audio' in types:raise RuntimeError('private recording must contain video only')
   results[-1].update(actual_producer_exit=producer_exit,private_media_streams=types)
  ipc('pointerDiagnostic','quit');qt_exit=proc.wait(timeout=4)
 except Exception as error:errors.append(type(error).__name__+': '+str(error));print('DIAGNOSTIC_ERROR',errors[-1],flush=True)
 finally:
  if owned_alive():
   os.kill(owned_pid,signal.SIGINT)
   end=time.monotonic()+4
   while owned_alive() and time.monotonic()<end:time.sleep(.1)
  if encoder and encoder.poll() is None:
   encoder.send_signal(signal.SIGINT)
   try:encoder.wait(timeout=4)
   except subprocess.TimeoutExpired:encoder.kill();encoder.wait()
  if proc.poll() is None:
   os.killpg(proc.pid,signal.SIGTERM)
   try:proc.wait(timeout=3)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
  log.close();receipt={'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'actual_qt_exit':proc.returncode,'actual_producer_exit':producer_exit,'errors':errors,'fixture_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'record_script_sha256':hashlib.sha256((root/'scripts/videos/record.sh').read_bytes()).hexdigest(),'scope':'Private Niri and private D-Bus: actual record.sh control flow and startup toast, video-only private output. PATH guards deny pgrep/pkill/pactl in producer; real wf-recorder uses --no-dmabuf. No installed/physical/Owner acceptance or original-encoder-argv equivalence.','results':results};(base/'result.json').write_text(json.dumps(receipt,indent=2)+'\n');(base.parent/'notification-result-path').write_text(str(base));print('EVIDENCE',base,'ACTUAL_QT_EXIT',proc.returncode,flush=True)

raise SystemExit(0 if proc.returncode==0 and producer_exit==0 and not errors and all(r["status"]=="CAPTURED" for r in results) else 1)
