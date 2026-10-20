#!/usr/bin/env python3
"""Opt-in private Niri native-pointer family matrix; no clicks or device changes."""
import argparse,ast,hashlib,json,os,signal,subprocess,sys,tempfile,time
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--scale',type=float,default=1.0);parser.add_argument('--kinds',default='clock');parser.add_argument('--edges',default='top,right,bottom,left');parser.add_argument('--capture',action='store_true');args=parser.parse_args()
root=Path.cwd();sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland
from native_wayland_input import native_input
node=ast.parse((root/'docs/evidence/native-surfaces/20261020-popup-hover/probe.py').read_text());qml=next(n.value.value for n in node.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='qml' for t in n.targets))
host_focus=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
base=Path(tempfile.mkdtemp(prefix='alis-popup-family-'));os.chmod(base,0o700);folder=base/'fixture';folder.mkdir()
for name in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/name).symlink_to(root/name)
(folder/'shell.qml').write_text(qml)
cases=[];records=[];errors=[];process=None
with private_wayland(folder,capture_focus=False) as env:
 assert env
 outputs=json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True,timeout=4));output=next(iter(outputs.values()))['name']
 subprocess.run(['niri','msg','output',output,'scale',str(args.scale)],env=env,check=True,capture_output=True,timeout=4)
 cfg=folder/'config/alis';cfg.mkdir(parents=True);data=json.loads((root/'defaults/config.json').read_text());data['panelFamily']='abyss';data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup'];data['abyss']['companion']['enabled']=False;data['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':'subject','kind':'clock','edge':'top','position':.35}]);data['bar']['autoHide']['enable']=False;data['bar'].setdefault('visualizer',{})['enable']=False;data['sounds']['notifications']=False
 for k in data['bar']['utilButtons']:
  if k.startswith('show'):data['bar']['utilButtons'][k]=k=='showUtilitiesLauncher'
 (cfg/'config.json').write_text(json.dumps(data))
 log=(base/'native.log').open('w');process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 def ipc(target,method,*values):
  p=subprocess.run(['qs','-p',str(folder),'ipc','call',target,method,*values],env=env,capture_output=True,text=True,timeout=5)
  if p.returncode:raise RuntimeError('private IPC '+method+' failed: '+p.stderr[-200:])
  return json.loads(p.stdout) if method!='quit' else None
 def snap(stage):
  value=ipc('abyssHoverProbe','snapshot')['outputs'][0];records.append({'stage':stage,'t':time.monotonic(),'snapshot':value});return value
 def current(o,kind):
  if kind=='utilButtons':
   g=o['genericPopup'];return g if g['activeKind']=='utilities' and g['requestedOpen'] else None
  expected=kind
  return next((v for v in o['popupSlots'] if v and v['kind']==expected and v['requestedVisible']),None)
 def box(slot,kind):return slot['inputBounds'] if kind=='utilButtons' else slot['content']
 try:
  end=time.monotonic()+25
  while time.monotonic()<end:
   try:o=snap('boot')
   except Exception:time.sleep(.2);continue
   if o['fieldReady'] and o['modules']:break
   time.sleep(.2)
  else:raise RuntimeError('private field not ready')
  time.sleep(2);dims=ipc('pointerDiagnostic','dimensions')['screens'][0];w,h=dims['width'],dims['height']
  with native_input(folder,env) as pointer:
   assert pointer
   # The nested window must not receive the owner's normal pointer stream.
   parent=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
   child_socket=env['NIRI_SOCKET'];child_pid=int(child_socket.rsplit('.',2)[-2])
   if host_focus and parent and parent.get('pid')==child_pid:
    subprocess.run(['niri','msg','action','focus-window','--id',str(host_focus['id'])],check=True,capture_output=True,timeout=4)
   def pulse():
    before=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
    wins=json.loads(subprocess.check_output(['niri','msg','--json','windows'],text=True,timeout=4));owned=next(v for v in wins if v.get('pid')==child_pid)
    subprocess.run(['niri','msg','action','focus-window','--id',str(owned['id'])],check=True,capture_output=True,timeout=4);time.sleep(.25)
    now=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
    if before and now and now['id']==owned['id']:subprocess.run(['niri','msg','action','focus-window','--id',str(before['id'])],check=True,capture_output=True,timeout=4)
   def move(stage,x,y,delay):
    pointer.move(max(0,min(w-1,x)),max(0,min(h-1,y)),w,h);time.sleep(delay)
    if stage.startswith('source:'):pulse();pointer.move(x,y,w,h);time.sleep(.1)
    return snap(stage)
   for kind in args.kinds.split(','):
    for edge in args.edges.split(','):
     case={'kind':kind,'edge':edge,'scale':args.scale,'phases':[]};cases.append(case)
     outside={'top':(w*.5,h-64),'bottom':(w*.5,64),'left':(w-64,h*.5),'right':(64,h*.5)}[edge]
     move('before:'+kind+':'+edge,*outside,1.1)
     ipc('pointerDiagnostic','configure',json.dumps({'kind':kind,'edge':edge,'reduce':False,'autoHide':False,'position':.35}));time.sleep(.6);pulse()
     o=snap('configured');m=next((m for m in o['modules'] if m['id']=='subject' and m['kind']==kind),None)
     if m is None:m=next((m for m in o['modules'] if m['kind']==kind),None)
     if not m or not m.get('visible') or not m.get('input') or min(m['input']['w'],m['input']['h'])<2:
      case.update(status='UNAVAILABLE_SOURCE',module=m);print(json.dumps(case),flush=True);continue
     r=m['input'];sx,sy=r['x']+r['w']/2,r['y']+r['h']/2
     o=move('source:'+kind+':'+edge,sx,sy,1.4);slot=current(o,kind)
     if not slot:case.update(status='FAIL',reason='source did not open expected popup');print(json.dumps(case),flush=True);continue
     deadline=time.monotonic()+8
     while slot and (min(box(slot,kind)['w'],box(slot,kind)['h'])<=0
            or (slot.get('progress',1)<.999 if kind=='utilButtons' else not slot.get('bodyReady',False))):
      if time.monotonic()>=deadline:break
      time.sleep(.15);o=snap('waiting-ready:'+kind+':'+edge);slot=current(o,kind)
     if not slot or min(box(slot,kind)['w'],box(slot,kind)['h'])<=0 or (kind=='utilButtons' and slot.get('progress',0)<.999):
      case.update(status='UNREADY_PRESENTATION',reason='no qualified resting geometry; handoff not tested');print(json.dumps(case),flush=True);continue
     case['source_open']=True
     case['source_point']=slot.get('anchorScenePoint') or slot.get('contentScenePoint')
     (base/(kind+'-'+edge+'-source.json')).write_text(json.dumps(o,indent=2))
     if args.capture:
      try:
       cap=subprocess.run(['grim',str(base/(kind+'-'+edge+'-source.png'))],env=env,capture_output=True,timeout=4);case['capture_exit']=cap.returncode
      except subprocess.TimeoutExpired:case['capture_status']='TIMED_OUT_NO_IMAGE'
     c=box(slot,kind);bx,by=c['x']+c['w']/2,c['y']+c['h']/2
     # Approach the body through the physical source-side seam. For Styled
     # Popup, bounds is the visible body; generic input includes its bridge.
     bounds=slot.get('bounds',c)
     if edge=='top':seam=(sx,(r['y']+r['h']+bounds['y'])/2)
     elif edge=='bottom':seam=(sx,(r['y']+bounds['y']+bounds['h'])/2)
     elif edge=='left':seam=((r['x']+r['w']+bounds['x'])/2,sy)
     else:seam=((r['x']+bounds['x']+bounds['w'])/2,sy)
     for stage,x,y,delay in [('seam',*seam,.9),('body',bx,by,1.0),('reverse',sx,sy,.8),('leave',*outside,1.2)]:
      o=move(stage+':'+kind+':'+edge,x,y,delay);active=current(o,kind);actual=(active.get('anchorScenePoint') or active.get('contentScenePoint')) if active else None;case['phases'].append({'stage':stage,'point':[x,y],'actual_point':actual,'point_matches':bool(actual and abs(actual['x']-x)<2 and abs(actual['y']-y)<2),'active':bool(active),'source_hover':any(m['kind']==kind and m['hovered'] for m in o['modules']),'generic_trigger':o['genericPopup']['triggerHover']})
     case['status']='PASS' if all(p['active']==(p['stage']!='leave') for p in case['phases']) else 'FAIL'
     if any(p['active'] and not p['point_matches'] for p in case['phases']):case['status']='INCONCLUSIVE_INPUT'
     print(json.dumps(case),flush=True)
  ipc('pointerDiagnostic','quit');process.wait(timeout=5)
 except Exception as error:errors.append(type(error).__name__+': '+str(error));print('PROBE_ERROR',errors[-1],flush=True)
 finally:
  if process.poll() is None:
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=4)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=3)
  log.close();value={'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'runtime_changes_from_head':subprocess.check_output(['git','diff','--name-only','HEAD','--','modules','services'],text=True).splitlines(),'fixture_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Production popup presentations on private Niri with original host focus restored before pointer driving, actual wl_pointer; no owner desktop/physical multi-output acceptance, no device actions','actual_native_exit':process.returncode,'cases':cases,'errors':errors,'records':records};(base/'result.json').write_text(json.dumps(value,indent=2)+'\n');Path('/tmp/alis-popup-family-active').write_text(str(base));print('EVIDENCE',base,'ACTUAL_EXIT',process.returncode,flush=True)
raise SystemExit(0 if not errors and process.returncode==0 and all(c['status']=='PASS' for c in cases) else 1)
