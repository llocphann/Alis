from pathlib import Path
import tempfile,subprocess,sys,json,os,time,signal,hashlib,math
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'scripts'));from native_test_session import private_wayland
BASE=ROOT/'.git/maintainer-validation/r03-native-body-retention';CLIENT=ROOT/'.git/maintainer-validation/pop-native-stack/client';records=[];phases=[]
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
source_start={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [ROOT/'modules/abyss/AbyssPerimeter.qml',ROOT/'modules/bar/StyledPopup.qml']}
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
   def move(x,y):
    logical=next(iter(json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True)).values()))['logical'];w,height=logical['width'],logical['height']
    command(f'M {round(x*64)} {round(y*64)} {w*64} {height*64}');time.sleep(.8);return snapshot()
   o=snapshot()['outputs'][0];m=next(m for m in o['modules']if m['id']=='resources');r=m['rect'];before=move(r['x']+r['w']/2,r['y']+r['h']/2)
   o=before['outputs'][0];slot=next(s for s in o['popupSlots']if s and s['kind']=='resources');c=slot['content'];body=move(c['x']+c['w']/2,c['y']+c['h']/2)
   prepared=ipc('dragDiagnostic','prepare','false');assert prepared and'error'not in prepared,prepared;time.sleep(.5);after=snapshot()
   slot=next((s for s in after['outputs'][0]['popupSlots']if s and s['kind']=='resources'),None)
   assert slot and slot['requestedVisible']and slot['contentHover']and not slot['moduleHover']and not slot['anchorHover'],after
   (BASE/'result.json').write_text(json.dumps({'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'worktree_variant':True,'source_start':source_start,'source_unchanged':all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in source_start.items()),'classification':'private compositor native body dwell while module enters edit input mode; no owner acceptance claim','before':before,'body':body,'prepared':prepared,'after':after},indent=2)+'\n')
   print('NATIVE_BODY_RETENTION_PASS source leases false; body pointer owns requested popup during Edit',flush=True)
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
