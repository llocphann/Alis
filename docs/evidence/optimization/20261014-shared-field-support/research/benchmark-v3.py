from pathlib import Path
import tempfile,subprocess,os,sys,json,time,re,signal,hashlib
root=Path.cwd();repo=Path('/tmp/alis-dynamic-exact-55b1fd183');base=root/'.git/maintainer-validation/20261014-field-support-research';out=base/'benchmark-v3';out.mkdir()
setup=(base/'offscreen-v2/probe.py').read_text()
start=setup.index(' field=(repo/');end=setup.index(" image=Image.new('RGBA'",start)
setup=setup[start:end]
setup=setup.replace(" (folder/'", " (folder/'")
from PIL import Image
hz=os.sysconf('SC_CLK_TCK')
def metrics(pid):
 p=Path('/proc')/str(pid);a=(p/'stat').read_text().split(') ',1)[1].split();status=(p/'status').read_text();clients={}
 for fd in (p/'fdinfo').iterdir():
  try:s=fd.read_text()
  except (OSError,PermissionError):continue
  client=re.search(r'^drm-client-id:\s*(\d+)',s,re.M);gpu=re.search(r'^drm-engine-gfx:\s*(\d+) ns',s,re.M)
  if client and gpu:clients[client[1]]=max(clients.get(client[1],0),int(gpu[1]))
 return {'time':time.monotonic(),'cpu_seconds':(int(a[11])+int(a[12]))/hz,'gfx_ns':sum(clients.values()),'gpu_clients':list(clients),'rss_kib':int(re.search(r'^VmRSS:\s*(\d+)',status,re.M)[1])}
def target(parent):
 children=(Path('/proc')/str(parent)/'task'/str(parent)/'children').read_text().split()
 for pid in children:
  try:cmd=(Path('/proc')/pid/'cmdline').read_bytes().split(b'\0')
  except OSError:continue
  if cmd and Path(os.fsdecode(cmd[0])).name in ['quickshell','qs']:return int(pid)
  try:r=target(int(pid))
  except OSError:continue
  if r:return r
 return None
rows=[]
for count in [4,16,40]:
 for order in range(4):
  for mode in (['before','after']if order%2==0 else['after','before']):
   name=f'{count}-{order}-{mode}';case=out/name;case.mkdir()
   with tempfile.TemporaryDirectory(prefix='alis-support-bench-')as t:
    folder=Path(t);variants=folder/'variants';variants.mkdir()
    for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(repo/entry)
    exec(__import__('textwrap').dedent(setup))
    (folder/'wave.png').write_bytes((variants/'fixture.png').read_bytes())
    (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.modules.common
import "variants"
ShellRoot {
 id:root;property bool active:false;property int frames:0;property var records:[]
 property int count:COUNT;property int ticks:0
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:win;visible:true;implicitWidth:1600;implicitHeight:1000;color:"#111820"
  Loader {id:field;anchors.fill:parent;source:"variants/FIELD.qml"}
 }
 Connections {target:field.item?.Window.window ?? null;function onFrameSwapped(){if(root.active)root.frames++}}
 FrameAnimation {
  running:true
  onTriggered:{
   let records=[],offset=Math.sin(root.ticks*.07)*3
   for(let i=0;i<root.count;i++){
    const edge=i%4,along=100+(i%7)*150
    const surface=edge===0?{x:along+offset,y:-50,width:160,height:150}:edge===2?{x:along+offset,y:900,width:160,height:150}:edge===3?{x:-50,y:along+offset,width:150,height:160}:{x:1500,y:along+offset,width:150,height:160}
    records.push({surface:surface,radius:29})
   }
   root.records=records;root.ticks++
   if(field.item)field.item.records=root.records
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function run(){try{
   tryCompare(Config,"ready",true,5000);Config.setNestedValue("performance.reduceAnimations",true)
   tryVerify(()=>field.item?.ready&&field.item.wallpaperReady,5000);wait(1500)
   root.frames=0;root.active=true;console.info("SUPPORT_BENCH_START")
   wait(7000);root.active=false
   console.info("SUPPORT_BENCH_END",JSON.stringify({frames:root.frames,ticks:root.ticks,api:field.item.GraphicsInfo.api}))
   wait(250)
  }catch(e){console.error("SUPPORT_BENCH_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''.replace('COUNT',str(count)).replace('FIELD','OriginalField'if mode=='before'else'CandidateField'))
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='rhi',QSG_RHI_BACKEND='opengl',QT_SCALE_FACTOR='1',QT_NO_XDG_DESKTOP_PORTAL='1')
    for k in ['QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST']:env.pop(k,None)
    for k in ['config','state','cache','data']:
     path=folder/k;path.mkdir();env['XDG_'+k.upper()+'_HOME']=str(path)
    cfg=folder/'config/illogical-impulse';cfg.mkdir();(cfg/'config.json').write_text((repo/'defaults/config.json').read_text())
    log=case/'native.log'
    with log.open('wb')as file:process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=env,stdout=file,stderr=subprocess.STDOUT,start_new_session=True)
    before=after=None;pid=None;deadline=time.monotonic()+35
    try:
     while process.poll()is None and time.monotonic()<deadline:
      if pid is None:pid=target(process.pid)
      text=log.read_text()
      if 'SUPPORT_BENCH_START'in text and before is None and pid:before=metrics(pid)
      if 'SUPPORT_BENCH_END'in text and after is None and pid:after=metrics(pid)
      time.sleep(.01)
     if process.poll()is None:os.killpg(process.pid,signal.SIGTERM);process.wait(5)
     text=log.read_text();match=re.search(r'SUPPORT_BENCH_END (\{.+\})',text)
     row={'name':name,'count':count,'mode':mode,'order':order,'pid':pid,'exit':process.returncode,'before':before,'after':after,'native':json.loads(match[1])if match else None,'runtime_source_sha':'55b1fd183876543d51e8d36394c155b5c9c50a35','candidate_qsb_sha256':hashlib.sha256((base/'CandidateField.frag.qsb').read_bytes()).hexdigest()}
     if before and after and row['native'] and row['native']['frames']>0:
      row['cpu_s']=after['cpu_seconds']-before['cpu_seconds'];row['gfx_ms']=(after['gfx_ns']-before['gfx_ns'])/1e6;row['gfx_ms_per_frame']=row['gfx_ms']/row['native']['frames'];row['sample_elapsed']=after['time']-before['time']
     (case/'receipt.json').write_text(json.dumps(row,indent=2)+'\n');rows.append(row);(out/'summary.json').write_text(json.dumps(rows,indent=2)+'\n')
     print(name,'exit',process.returncode,'frames',row['native'],'gpu_ms/frame',row.get('gfx_ms_per_frame'),'cpu_s',row.get('cpu_s'),flush=True)
     if process.returncode or not(row['native']and row['native']['frames']>0 and before and after and row.get('gfx_ms',0)>0):raise SystemExit(1)
    finally:
     if process.poll()is None:os.killpg(process.pid,signal.SIGTERM);process.wait(5)
