from pathlib import Path
import tempfile,subprocess,sys,json,os,time,signal,hashlib,math
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'scripts'));from native_test_session import private_wayland
BASE=ROOT/'.git/maintainer-validation/r03-native-window';CLIENT=ROOT/'.git/maintainer-validation/pop-native-stack/client';records=[];phases=[]
QML='''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
ShellRoot {
 id:root;property var trace:[];property var frames:[];property bool armed:false;property var subject:null;property var editor:null;property var window:null;property int seq:0
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true}
 Loader {id:critical;active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 function seek(node,what,seen) {
  if(!node||seen.includes(node))return null;seen.push(node)
  if(what(node))return node
  const list=[];for(const child of(node.children??[]))list.push(child);for(const child of(node.data??[]))list.push(child)
  if(node.item)list.push(node.item);if(node.contentItem)list.push(node.contentItem)
  for(const child of list){const result=seek(child,what,seen);if(result)return result}return null
 }
 function perimeter(){return root.seek(critical.item,n=>n.objectName==="abyssPerimeterLoader",[])?.item??null}
 function state(){const p=root.perimeter();return p?.hoverProbeSnapshot?JSON.parse(p.hoverProbeSnapshot()):null}
 IpcHandler {
  target:"dragDiagnostic"
  function prepare(hold:bool):string {
   const p=root.perimeter();root.window=p?.outputHosts?.[0]??null
   if(!root.window)return JSON.stringify({error:"no production output"})
   root.editor=root.seek(root.window.contentItem,n=>typeof n.startDrag==="function"&&n.moduleLayer,[])
   if(!root.editor)return JSON.stringify({error:"production editor not found"})
   root.subject=root.editor.moduleLayer.itemForId("resources")
   if(!root.subject)return JSON.stringify({error:"resources not constructed"})
   if(root.subject.companionPopup)root.subject.companionPopup.alternativeVisibleCondition=hold
   GlobalStates.startAbyssEditing(root.window.outputName);root.editor.snapEnabled=false
   return JSON.stringify({output:root.window.outputName,width:root.window.width,height:root.window.height,subject:{x:root.subject.x,y:root.subject.y,width:root.subject.width,height:root.subject.height},state:root.state()})
  }
  function arm():string {
   const handle=root.seek(root.editor,n=>n.objectName==="abyssModuleHandle"&&n.modelData==="resources",[])
   const mouse=handle?root.seek(handle,n=>n.mouseX!==undefined&&n.positionChanged,[]):null
   if(!mouse)return JSON.stringify({error:"native MouseArea not found"})
   root.trace=[];root.frames=[];root.seq=0;root.armed=true
   mouse.positionChanged.connect(function(event){if(!root.armed||root.trace.length>=300)return;const point=mouse.mapToItem(root.window.contentItem,event.x,event.y);root.seq++;root.trace.push({timestamp:Date.now(),seq:root.seq,pressed:mouse.pressed,point:{x:point.x,y:point.y},subject:{x:root.subject.x,y:root.subject.y,width:root.subject.width,height:root.subject.height},dragging:root.editor._dragging,edge:root.editor.selected?.edge??"",feedback:root.editor.feedback})})
   root.subject.Window.window.frameSwapped.connect(function(){if(!root.armed||root.frames.length>=600)return;root.frames.push({timestamp:Date.now(),seq:root.seq,x:root.subject.x,y:root.subject.y,width:root.subject.width,height:root.subject.height})})
   return JSON.stringify({handle:{x:handle.x,y:handle.y,w:handle.width,h:handle.height},state:root.state()})
  }
  function finish():string {root.armed=false;return JSON.stringify({trace:root.trace,frames:root.frames,state:root.state()})}
 }
}
'''
owner=json.loads((Path.home()/'.config/illogical-impulse/config.json').read_text());profile=owner['abyss']['modules']['outputLayouts'][0]
with tempfile.TemporaryDirectory(prefix='alis-r03-native-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(QML)
 with private_wayland(folder)as env:
  assert env and env['WAYLAND_DISPLAY']!=os.environ['WAYLAND_DISPLAY']
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup'];data['abyss']['companion']['enabled']=False;data['abyss']['modules'].update({k:v for k,v in profile.items()if k!='outputName'});data['abyss']['modules']['configured']=True;data['abyss']['modules']['outputLayouts']=[];data['performance']['reduceAnimations']=False;data['bar']['autoHide']['enable']=False
  (cfg/'config.json').write_text(json.dumps(data));log=(BASE/'native.log').open('w')
  process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=dict(env,QT_NO_XDG_DESKTOP_PORTAL='1'),stdout=log,stderr=subprocess.STDOUT,start_new_session=True);pointer=None
  def ipc(target,method,*args):
   r=subprocess.run(['qs','-p',str(folder),'ipc','call',target,method,*args],env=env,text=True,capture_output=True,timeout=8)
   if r.returncode or not r.stdout.startswith('{'):return None
   return json.loads(r.stdout)
  def snapshot():return ipc('abyssHoverProbe','snapshot')
  try:
   deadline=time.monotonic()+15
   while time.monotonic()<deadline:
    s=snapshot()
    if s and s.get('outputs')and s['outputs'][0].get('fieldReady'):break
    time.sleep(.2)
   time.sleep(1.5);assert snapshot()['outputs'][0]['modules']
   pointer=subprocess.Popen([str(CLIENT),env['WAYLAND_DISPLAY'],os.environ['WAYLAND_DISPLAY']],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1);assert pointer.stdout.readline().startswith('READY')
   def command(value):
    before=time.time_ns();pointer.stdin.write(value+'\n');pointer.stdin.flush();assert pointer.stdout.readline().strip()=='ACK';return before
   o=ipc('dragDiagnostic','prepare','false');assert o and 'error'not in o,o;time.sleep(.5);arm=ipc('dragDiagnostic','arm');assert arm and'error'not in arm,arm;h=arm['handle'];sx,sy=h['x']+h['w']/2,h['y']+h['h']/2
   logical=next(iter(json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True)).values()))['logical'];w,height=logical['width'],logical['height']
   def move(x,y,label):
    stamp=command(f'M {round(x*64)} {round(y*64)} {w*64} {height*64}');records.append({'stage':label,'sent':[x,y,w,height],'wall_ns':stamp})
   move(sx,sy,'press-position');time.sleep(.1);command('B 272 1');time.sleep(.04)
   for i in range(1,41):move(sx+340*i/40,sy,'same-edge');time.sleep(.016)
   # Continue over the corner to a long left-edge move without breaking grab.
   ex=sx+340
   for i in range(1,51):move(ex+(24-ex)*i/50,sy+(height*.45-sy)*i/50,'cross-edge');time.sleep(.016)
   command('B 272 0');time.sleep(.7);result=ipc('dragDiagnostic','finish');assert result and'error'not in result,result
   (BASE/'result.json').write_text(json.dumps({'classification':'actual virtual-pointer native drag diagnostic; observations are not physical pointer latency/compositor-present FPS','source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'private_display':env['WAYLAND_DISPLAY'],'parent_display':os.environ['WAYLAND_DISPLAY'],'explicit_focus_requested':False,'copied_profile_keys':['placements','gap','size','edgeThicknesses','edgeWidthAffectsModules'],'hold_popup':False,'native_events':records,'qml':result},indent=2)+'\n')
   print('native_commands',len(records),'observed_motion',len(result['trace']),'frameSwapped_samples',len(result['frames']),'dragging_stages',sum(t['dragging']for t in result['trace']),'errors',sorted(set(t['feedback']for t in result['trace']if t['feedback'])),flush=True)
  finally:
   if pointer:
    pointer.stdin.close()
    try:pointer.wait(timeout=3)
    except subprocess.TimeoutExpired:pointer.kill();pointer.wait()
   if process.poll()is None:
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=4)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   log.close()
