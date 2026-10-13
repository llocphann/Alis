from pathlib import Path
import json,os,sys,tempfile,time,subprocess,signal,hashlib
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland
OUT=ROOT/'.git/maintainer-validation/20261013-common-popup';CLIENT=ROOT/'.git/maintainer-validation/pop-native-stack/client'
rows=[];traces=[]
with tempfile.TemporaryDirectory(prefix='alis-common-popups-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text('''import QtQuick
import Quickshell
import qs
import qs.modules.common
ShellRoot {
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true}
 Loader {active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
}''')
 with private_wayland(folder) as env:
  assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  v=json.loads((ROOT/'defaults/config.json').read_text());v['panelFamily']='abyss';v['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup'];v['performance']['reduceAnimations']=False;v['abyss']['companion']['enabled']=False;v['abyss']['waves']['enabled']=False
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
   for run in range(2):
    ipc('startFrames')
    for cycle in range(4):
     for kind in ['resources','clock','weather','clock','resources']:
      state=ipc('snapshot')['outputs'][0];m=next(m for m in state['modules']if m['id']==kind);r=m['rect'];move(r['x']+r['w']/2,r['y']+r['h']/2);time.sleep(.18 if cycle else .6);record(f'{run}/{cycle}/{kind}')
    traces.append(ipc('stopFrames'))
    state=ipc('snapshot')['outputs'][0];slots=[s for s in state['popupSlots']if s and s['requestedVisible']]
    if slots:
     c=slots[-1]['content'];rows.append({'stage':f'{run}/body-target','target':c});move(c['x']+c['w']/2,c['y']+c['h']/2);time.sleep(.5);record(f'{run}/body')
    d=dims();move(d['width']*.8,d['height']*.9);time.sleep(.7);record(f'{run}/outside')
   (OUT/'result.json').write_text(json.dumps({'classification':'private production perimeter on local GPU; actual wl_pointer; no installed/owner acceptance or matched optimization claim','source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'rows':rows,'traces':traces},indent=2))
   for i,trace in enumerate(traces):
    for t in trace:print(json.dumps({'run':i,**{k:t[k]for k in ['count','p50','p95','p99','max','over33ms','popupOpenFrames','heartbeatOver100Ms','heartbeatMaxIntervalMs']}}),flush=True)
   for r in rows:
    if r['stage'].endswith(('body','outside')):print(r['stage'],r['snapshot']['outputs'][0]['liquidPopupsOpen'])
  finally:
   try:ipc('stopFrames')
   except Exception:pass
   if pointer:pointer.stdin.close();pointer.wait(timeout=3)
   if process.poll()is None:
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=4)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   log.close()
