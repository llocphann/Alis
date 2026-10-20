#!/usr/bin/env python3
"""Opt-in production Popup wl_pointer matrix. Run from repository root.
Use --focus for a temporarily focused private Niri window (focus is restored);
--corners additionally enables auto-hide and near-corner source positions.
No owner config, shell, audio or notification data is changed.
"""
import ast,sys,os,tempfile,json,subprocess,time,signal
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland
from native_wayland_input import native_input
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
  function quit():void {Qt.quit()}
  function dimensions():string {return JSON.stringify({screens:Quickshell.screens.map(s=>({name:s.name,width:s.width,height:s.height}))})}
  function configure(value:string):string {const p=JSON.parse(value);Config.setNestedValues({"performance.reduceAnimations":p.reduce,"bar.autoHide.enable":p.autoHide,"abyss.modules.placements":[{id:"subject",kind:p.kind,edge:p.edge,position:Number(p.position ?? .35)}]});return JSON.stringify(p)}
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
base=Path(tempfile.mkdtemp(prefix='alis-production-hover-'));os.chmod(base,0o700);folder=base/'fixture';folder.mkdir()
for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(root/entry)
(folder/'shell.qml').write_text(qml)
records=[];cases=[]
with private_wayland(folder,capture_focus="--focus" in sys.argv) as env:
 assert env is not None
 config=folder/'config/alis';config.mkdir(parents=True)
 data=json.loads((root/'defaults/config.json').read_text());data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup'];data['panelFamily']='abyss';data['abyss']['companion']['enabled']=False;data['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':'subject','kind':'clock','edge':'top','position':.35}]);data['bar']['autoHide']['enable']=False;data['bar'].setdefault('visualizer',{})['enable']=False;data['sounds']['notifications']=False
 (config/'config.json').write_text(json.dumps(data));log=(base/'native.log').open('w');proc=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 def ipc(target,name,*args):
  r=subprocess.run(['qs','-p',str(folder),'ipc','call',target,name,*args],env=env,capture_output=True,text=True,timeout=5)
  if r.returncode:raise RuntimeError(r.stderr[-350:])
  return json.loads(r.stdout) if name!='quit' else None
 def snapshot(stage):
  value=ipc('abyssHoverProbe','snapshot');out=value['outputs'][0];records.append({'stage':stage,'t':time.monotonic(),'snapshot':out});return out
 try:
  deadline=time.monotonic()+18
  while time.monotonic()<deadline:
   try:s=snapshot('boot')
   except Exception:time.sleep(.2);continue
   if s.get('fieldReady') and s.get('modules'):break
   time.sleep(.2)
  else:raise RuntimeError('no production field')
  time.sleep(2)
  dims=ipc('pointerDiagnostic','dimensions')['screens'][0];w,h=dims['width'],dims['height']
  with native_input(folder,env) as pointer:
   assert pointer is not None
   def move(stage,x,y,seconds=.9):
    pointer.move(max(0,min(w-1,x)),max(0,min(h-1,y)),w,h);time.sleep(seconds);return snapshot(stage)
   for edge in ['top','right','bottom','left']:
    move('outside',w*.8,h*.8)
    ipc('pointerDiagnostic','configure',json.dumps({'kind':'clock','edge':edge,'reduce':False,'autoHide':('--corners' in sys.argv),'position':(.06 if edge in ['top','right'] else .94) if '--corners' in sys.argv else .35}));time.sleep(.4)

    if '--corners' in sys.argv:move('reveal-top',w*.5,2,.35)
    o=snapshot('configured');m=next(m for m in o['modules'] if m['id']=='subject');r=m['input'];sx=r['x']+r['w']/2;sy=r['y']+r['h']/2
    o=move('source',sx,sy,1);slots=[s for s in o['popupSlots'] if s and s['requestedVisible']];case={'edge':edge,'source_open':bool(slots),'phases':[]};cases.append(case)
    if not slots:print(json.dumps(case),flush=True);continue
    slot=slots[0];c=slot['content'];bx=c['x']+c['w']/2;by=c['y']+c['h']/2
    point=ipc('pointerDiagnostic','shoulder',json.dumps(o));case['shoulder']=point
    phases=[('bridge',(sx+bx)/2,(sy+by)/2,.9),('body',bx,by,1.0)]
    if point.get('point'):
     p=point['point'];phases.append(('shoulder',p['x'],p['y'],1.0))
    outside={'top':(w*.5,h-64),'bottom':(w*.5,64),'left':(w-64,h*.5),'right':(64,h*.5)}[edge]
    phases += [('reverse',sx,sy,.8),('leave',*outside,1.0)]
    for stage,x,y,seconds in phases:
     o=move(stage,x,y,seconds);case['phases'].append({'stage':stage,'requested':any(s and s['requestedVisible'] for s in o['popupSlots']),'body_owned':any(s and s['contentHover'] for s in o['popupSlots']),'source_owned':any(s and(s['anchorHover']or s['moduleHover']) for s in o['popupSlots'])})
    print(json.dumps(case),flush=True)
  ipc('pointerDiagnostic','quit');code=proc.wait(timeout=4)
 except Exception as error:
  print('DIAGNOSTIC_ERROR',str(error),flush=True);code=None
 finally:
  if proc.poll() is None:
   os.killpg(proc.pid,signal.SIGTERM)
   try:proc.wait(timeout=3)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
  log.close();(base/'result.json').write_text(json.dumps({'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'actual_native_exit':proc.returncode,'cases':cases,'records':records},indent=2));Path('/tmp/alis-production-hover-focused-path').write_text(str(base));print('EVIDENCE',base,'ACTUAL_EXIT',proc.returncode,flush=True)

valid=proc.returncode==0 and len(cases)==4 and all(case["source_open"] and all(p["requested"]==(p["stage"]!="leave") for p in case["phases"]) for case in cases)
print("NATIVE_POPUP_PASS" if valid else "NATIVE_POPUP_FAIL",flush=True)
raise SystemExit(0 if valid else 1)
