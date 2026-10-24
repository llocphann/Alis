#!/usr/bin/env python3
"""Opt-in private Niri native-pointer family matrix; no clicks or device changes."""
import argparse,ast,hashlib,json,os,signal,subprocess,sys,tempfile,time
from contextlib import contextmanager
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--scale',type=float,default=1.0);parser.add_argument('--kinds',default='clock');parser.add_argument('--edges',default='top,right,bottom,left');parser.add_argument('--positions',default='.06,.94');parser.add_argument('--join',action='store_true');parser.add_argument('--shoulders',action='store_true');parser.add_argument('--capture',action='store_true');parser.add_argument('--float-owned-window',action='store_true');parser.add_argument('--keep-input-focus',action='store_true');args=parser.parse_args()
root=Path.cwd();sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland
from native_wayland_input import native_input
node=ast.parse((root/'docs/evidence/native-surfaces/20261020-popup-hover/probe.py').read_text());qml=next(n.value.value for n in node.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='qml' for t in n.targets))
qml=qml.replace('import QtQuick\n','import QtQuick\nimport QtTest\n',1)
qml=qml.replace('position:Number(p.position ?? .35)','position:Number(p.position ?? .35),joinCorner:p.joinCorner===true')
qml=qml.replace(' IpcHandler {',r"""
 TestCase {
  id: observer;when:false;optional:true
  function host(kind) {
   if(kind==="distroIcon")kind="launcher"
   const loader=findChild(critical.item,"abyssPerimeterLoader"),win=loader?.item?.outputHosts?.[0]
   function scan(item){if(!item)return null;if(String(item.identity??"").startsWith("styledPopup")&&item.presentationKind===kind)return item;for(const c of item.children??[]){const found=scan(c);if(found)return found}return null}
   return scan(win?.contentItem)
  }
 }
 IpcHandler {""",1)
qml=qml.replace('  function dimensions():string',r"""
  function weld(value:string):string {
   const p=JSON.parse(value),h=observer.host(p.kind)
   if(!h)return JSON.stringify({error:"no popup host"})
   const adjacent=p.adjacent,c=h.record.content,ins=h.connectionInsets
   const x=adjacent==="left"?ins.left+2:adjacent==="right"?h.width-ins.right-2:c.x+c.width/2
   const y=adjacent==="top"?ins.top+2:adjacent==="bottom"?h.height-ins.bottom-2:c.y+c.height/2
   const body=Geometry.rectContains(h.inputBounds,x,y),bridge=Geometry.rectContains(h.sourceBridge,x,y),strip=h.connectionRects.some(r=>Geometry.rectContains(r,x,y))
   const nativeContains=body||bridge||strip
   const plane=h.hoverParent,within=x>=plane.x&&y>=plane.y&&x<plane.x+plane.width&&y<plane.y+plane.height
   const hoverContains=within&&plane.containmentMask.contains(Qt.point(x-plane.x,y-plane.y))
   return JSON.stringify({point:{x,y},expectedAdjacent:adjacent,joinedEdge:h.joinedEdge,appliedJoinedEdge:h.record.joinedEdge??"",distance:Geometry.distance(x,y,h.width,h.height,ins,AbyssStyle.perimeterRadius,[h.record],AbyssStyle.connectionDepth,AbyssStyle.neckRadius),nativeContains,hoverContains,sourceOwns:(h.controller?.sourceInputRegions??[]).some(r=>Geometry.rectContains(r,x,y)),rawSurface:h.rawPresentationRecord.surface,joinedSurface:h.record.surface,inputBounds:h.inputBounds})
  }
  function dimensions():string""",1)
host_focus=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
base=Path(os.environ['ALIS_NATIVE_FAMILY_EVIDENCE_DIR']);base.mkdir(mode=0o700);os.chmod(base,0o700);folder=base/'fixture';folder.mkdir()
for name in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/name).symlink_to(root/name)
(folder/'shell.qml').write_text(qml)
cases=[];records=[];errors=[];process=None
with private_wayland(folder,capture_focus=False) as env:
 assert env
 # Floating only this owned child avoids parent tiling resize on focus restore.
 # Never change a foreign window, window rule or desktop configuration.
 child_pid=int(env['NIRI_SOCKET'].rsplit('.',2)[-2])
 if args.float_owned_window:
  deadline=time.monotonic()+5
  while time.monotonic()<deadline:
   windows=json.loads(subprocess.check_output(['niri','msg','--json','windows'],text=True,timeout=4));owned=[v for v in windows if v.get('pid')==child_pid]
   if len(owned)==1:break
   time.sleep(.1)
  else:raise RuntimeError('cannot identify sole owned Niri window')
  target=owned[0]['id']
  if not owned[0]['is_floating']:subprocess.run(['niri','msg','action','toggle-window-floating','--id',str(target)],check=True,capture_output=True,timeout=4)
  for action,size in [('set-window-width','1700'),('set-window-height','1050')]:
   subprocess.run(['niri','msg','action',action,'--id',str(target),size],check=True,capture_output=True,timeout=4)
  time.sleep(.7)
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
   def pulse(watch_kind=None,point=None):
    before=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
    wins=json.loads(subprocess.check_output(['niri','msg','--json','windows'],text=True,timeout=4));owned=next(v for v in wins if v.get('pid')==child_pid)
    subprocess.run(['niri','msg','action','focus-window','--id',str(owned['id'])],check=True,capture_output=True,timeout=4)
    try:
     if point is None:time.sleep(.25)
     else:
      began=time.monotonic();deadline=began+8;previous_geometry=None;stable=0
      while time.monotonic()<deadline:
       pointer.move(*point,w,h);time.sleep(.12)
       sample=snap('manual-ready-barrier:'+watch_kind);slot=current(sample,watch_kind)
       ready=slot and min(box(slot,watch_kind)['w'],box(slot,watch_kind)['h'])>0 and (abs(slot.get('progress',0)-1)<.001 if watch_kind=='utilButtons' else slot.get('bodyReady',False))
       geometry=json.dumps({'bounds':box(slot,watch_kind),'surface':slot.get('hoverGeometry',{}).get('rawSurface')},sort_keys=True) if ready else None
       stable=stable+1 if geometry is not None and geometry==previous_geometry else 0;previous_geometry=geometry
       if ready and stable>=3 and time.monotonic()-began>=.75:break
      else:raise RuntimeError('native frame readiness barrier expired for '+watch_kind)
    finally:
     now=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
     if before and now and now['id']==owned['id']:subprocess.run(['niri','msg','action','focus-window','--id',str(before['id'])],check=True,capture_output=True,timeout=4)
   def move(stage,x,y,delay):
    pointer.move(max(0,min(w-1,x)),max(0,min(h-1,y)),w,h);time.sleep(delay)
    if stage.startswith('source:'):pulse(stage.split(':')[1],(x,y));pointer.move(x,y,w,h);time.sleep(.1)
    return snap(stage)
   @contextmanager
   def input_focus():
    previous=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
    windows=json.loads(subprocess.check_output(['niri','msg','--json','windows'],text=True,timeout=4))
    owned=next(v for v in windows if v.get('pid')==child_pid)
    if args.keep_input_focus:
     subprocess.run(['niri','msg','action','focus-window','--id',str(owned['id'])],check=True,capture_output=True,timeout=4)
    try:yield
    finally:
     now=json.loads(subprocess.check_output(['niri','msg','--json','focused-window'],text=True,timeout=4))
     if args.keep_input_focus and previous and now and now['id']==owned['id'] and previous['id']!=owned['id']:
      current_windows=json.loads(subprocess.check_output(['niri','msg','--json','windows'],text=True,timeout=4))
      if any(v['id']==previous['id'] for v in current_windows):
       subprocess.run(['niri','msg','action','focus-window','--id',str(previous['id'])],check=True,capture_output=True,timeout=4)
   for kind in args.kinds.split(','):
    for edge in args.edges.split(','):
     for position in [float(v) for v in args.positions.split(',')]:
      with input_focus():
       case={'kind':kind,'edge':edge,'scale':args.scale,'position':position,'joinCorner':args.join,'phases':[]};cases.append(case)
       outside={'top':(w*.5,h-64),'bottom':(w*.5,64),'left':(w-64,h*.5),'right':(64,h*.5)}[edge]
       move('before:'+kind+':'+edge,*outside,1.1)
       ipc('pointerDiagnostic','configure',json.dumps({'kind':kind,'edge':edge,'reduce':False,'autoHide':False,'position':position,'joinCorner':args.join}));time.sleep(.6);pulse()
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
       actual_source=case['source_point'];case['source_point_matches']=bool(actual_source and abs(actual_source['x']-sx)<2 and abs(actual_source['y']-sy)<2)
       (base/(kind+'-'+edge+'-'+str(position)+'-source.json')).write_text(json.dumps(o,indent=2))
       if args.capture:
        try:
         cap=subprocess.run(['grim',str(base/(kind+'-'+edge+'-'+str(position)+'-source.png'))],env=env,capture_output=True,timeout=4);case['capture_exit']=cap.returncode
        except subprocess.TimeoutExpired:case['capture_status']='TIMED_OUT_NO_IMAGE'
       c=box(slot,kind);bx,by=c['x']+c['w']/2,c['y']+c['h']/2
       # Approach the body through the physical source-side seam. For Styled
       # Popup, bounds is the visible body; generic input includes its bridge.
       bounds=slot.get('bounds',c)
       if edge=='top':seam=(sx,(r['y']+r['h']+bounds['y'])/2)
       elif edge=='bottom':seam=(sx,(r['y']+bounds['y']+bounds['h'])/2)
       elif edge=='left':seam=((r['x']+r['w']+bounds['x'])/2,sy)
       else:seam=((r['x']+bounds['x']+bounds['w'])/2,sy)
       phases=[('seam',*seam,.9),('body',bx,by,1.0)]
       if args.shoulders and kind!='utilButtons':
        shoulder=ipc('pointerDiagnostic','shoulder',json.dumps(o));case['shoulder']=shoulder
        if shoulder.get('point'):
         point=shoulder['point'];phases.append(('shoulder',point['x'],point['y'],.9))
       adjacent=('left' if position<.5 else 'right') if edge in ['top','bottom'] else ('top' if position<.5 else 'bottom')
       weld=ipc('pointerDiagnostic','weld',json.dumps({'kind':kind,'adjacent':adjacent}));case['weld']=weld
       if args.join:
        if weld.get('appliedJoinedEdge')!=adjacent or weld.get('distance',0)>=-1 or weld.get('sourceOwns'):
         case.update(status='UNQUALIFIED_JOIN_POINT',reason='requested adjacent weld not safely painted/owned');print(json.dumps(case),flush=True);continue
        point=weld['point'];phases += [('adjacent-weld',point['x'],point['y'],1.0),('body-return',bx,by,.8)]
       phases += [('reverse',sx,sy,.8),('leave',*outside,1.2)]
       for stage,x,y,delay in phases:
        o=move(stage+':'+kind+':'+edge,x,y,delay);active=current(o,kind);actual=(active.get('anchorScenePoint') or active.get('contentScenePoint')) if active else None;case['phases'].append({'stage':stage,'point':[x,y],'actual_point':actual,'point_matches':bool(actual and abs(actual['x']-x)<2 and abs(actual['y']-y)<2),'active':bool(active),'source_hover':any(m['kind']==kind and m['hovered'] for m in o['modules']),'generic_trigger':o['genericPopup']['triggerHover']})
       case['status']='PASS' if all(p['active']==(p['stage']!='leave') for p in case['phases']) else 'FAIL'
       if not case['source_point_matches'] or any(p['active'] and not p['point_matches'] for p in case['phases']):case['status']='INCONCLUSIVE_INPUT'
       print(json.dumps(case),flush=True)
  ipc('pointerDiagnostic','quit');process.wait(timeout=5)
 except Exception as error:errors.append(type(error).__name__+': '+str(error));print('PROBE_ERROR',errors[-1],flush=True)
 finally:
  if process.poll() is None:
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=4)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=3)
  log.close();value={'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'runtime_changes_from_head':subprocess.check_output(['git','diff','--name-only','HEAD','--','modules','services'],text=True).splitlines(),'fixture_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'input_focus_held':args.keep_input_focus,'scope':'Production popup presentations on private Niri with original host focus restored before pointer driving, actual wl_pointer; no owner desktop/physical multi-output acceptance, no device actions','actual_native_exit':process.returncode,'cases':cases,'errors':errors,'records':records};(base/'result.json').write_text(json.dumps(value,indent=2)+'\n');(base.parent/'family-result-path').write_text(str(base));print('EVIDENCE',base,'ACTUAL_EXIT',process.returncode,flush=True)
raise SystemExit(0 if not errors and process.returncode==0 and all(c['status']=='PASS' for c in cases) else 1)
