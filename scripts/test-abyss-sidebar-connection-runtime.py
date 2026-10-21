#!/usr/bin/env python3
"""Opt-in native production Sidebar connection, full-size reveal and hover lease."""
from pathlib import Path
import os,json,sys,subprocess,hashlib,argparse,tempfile
parser=argparse.ArgumentParser();parser.add_argument('--scale',type=float,default=1.0);parser.add_argument('--edge-pair',default='left,right');args=parser.parse_args()
assert args.edge_pair in ['left,right','right,left','top,bottom','bottom,top']
root=Path(os.environ.get('ALIS_SIDEBAR_CONNECTION_TEST_ROOT',Path(__file__).resolve().parents[1])).resolve();sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland,run_qs
temporary=None if os.environ.get('ALIS_SIDEBAR_CONNECTION_EVIDENCE') else tempfile.TemporaryDirectory(prefix='alis-sidebar-connection-')
out=Path(os.environ.get('ALIS_SIDEBAR_CONNECTION_EVIDENCE',temporary.name if temporary else '')).resolve();out.mkdir(mode=0o700,parents=True,exist_ok=True)
folder=out/'fixture';folder.mkdir()
for name in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/name).symlink_to(root/name)
qml=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
ShellRoot {
 id:root
 property int checks:0
 property int swaps:0
 property var samples:[]
 property var captures:[]
 property var watching:null
 property var canvasSize:null
 property string phase:"boot"
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true;GlobalStates.abyssColdPerimeterRecreatePending=true}
 Loader {id:critical;active:Config.ready;source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 Connections {target:test.host ? test.host.Window.window : null
  function onFrameSwapped(){root.swaps++;if(root.watching)test.sample("swap")}
 }
 FileView {id:report;path:Quickshell.env("SIDEBAR_CONNECTION_REPORT")}
 TestCase {
  id:test;when:false;optional:true
  property var win:null
  property var host:null
  property var field:null
  property var reveal:null
  function check(v,label){root.checks++;if(!v)throw Error(label)}
  function find(item,pred){if(!item)return null;if(pred(item))return item;for(const c of item.children??[]){const f=find(c,pred);if(f)return f}return null}
  function rect(r){return r?{x:r.x,y:r.y,width:r.width,height:r.height}:null}
  function sample(event){
   const h=root.watching;if(!h)return
   if(root.samples.length<5000)root.samples.push({event,phase:root.phase,ms:Date.now(),open:h.open,p:h.progress,edge:h.edge,
    canvas:[h.contentItem.width,h.contentItem.height],target:rect(h.targetRecord.content),surface:rect(h.record.surface),
    bounds:rect(h.inputBounds),bodyHover:reveal?.bodyHovered,edgeHover:reveal?.edgeHovered})
  }
  function capture(label){let done=false;check(field.grabToImage(image=>{done=image.saveToFile(Quickshell.env("SIDEBAR_CONNECTION_IMAGES")+"/"+label+".png")}),"capture refused");tryVerify(()=>done,4000);root.captures.push(label)}
  function move(x,y){mouseMove(win.contentItem,x,y);wait(70);sample("pointer")}
  function run(){let error=null;try{
   tryCompare(Config,"ready",true,6000)
   tryVerify(()=>critical.item!==null,6000)
   const loader=findChild(critical.item,"abyssPerimeterLoader")
   tryVerify(()=>loader.item?.nativeInputFramesReady,8000);wait(1500)
   const perimeter=loader.item
   win=perimeter.outputHosts[0]
   check(win!==null&&win.width>0&&win.height>0,"no production output")
   for(const identity of ["leftPanel","rightPanel"]){
    host=find(win.contentItem,item=>item.identity===identity)
    check(!!host,"missing production "+identity)
    field=find(win.contentItem,item=>item.boundInterior!==undefined&&item.framePresented!==undefined)
    check(!!field,"missing production field")
    reveal=find(win.contentItem,item=>item.bodyItem!==undefined&&item.bodyItem!==null&&item.bodyItem===host.contentParent)
    // The fixed source may bind the body's complete painted hover plane.
    if(!reveal)reveal=find(win.contentItem,item=>item.bodyItem!==undefined&&item.bodyItem===host.hoverParent)
    check(!!reveal,"missing production hover lease "+identity)
    root.watching=host;root.phase=identity+":edge-open"
    const edge=host.edge,horizontal=["top","bottom"].includes(edge)
    const x=horizontal?win.width/2:(edge==="left"?2:win.width-2)
    const y=horizontal?(edge==="top"?2:win.height-2):win.height/2
    const expectedSource=horizontal
      ? (edge==="top"?reveal.y===0:Math.abs(reveal.y+reveal.height-win.height)<1)
      : (edge==="left"?reveal.x===0:Math.abs(reveal.x+reveal.width-win.width)<1)
    check(expectedSource,"SIDEBAR_TRIGGER_EDGE_MISMATCH "+identity+" edge="+edge+" trigger="+reveal.x+","+reveal.y)
    move(x,y);tryVerify(()=>host.open,2000);tryVerify(()=>host.ready&&Math.abs(host.progress-1)<.000001,6000)
    root.canvasSize=[host.contentItem.width,host.contentItem.height]
    check(root.canvasSize[0]>0&&root.canvasSize[1]>0,"empty production content")
    check(Math.abs(horizontal?host.record.content.x+host.record.content.width/2-win.width/2:host.record.content.y+host.record.content.height/2-win.height/2)<1,"physical Sidebar not centered")
    capture(identity+"-rest")
    const content=host.record.content
    const seamX=horizontal?x:(edge==="left"?(reveal.width+content.x)/2:(reveal.x+content.x+content.width)/2)
    const seamY=horizontal?(edge==="top"?(reveal.height+content.y)/2:(reveal.y+content.y+content.height)/2):y
    field=find(win.contentItem,item=>item.boundInterior!==undefined&&item.framePresented!==undefined)
    check(!!field,"missing actual field")
    check(Geometry.distance(seamX,seamY,win.width,win.height,host.connectionInsets,AbyssStyle.perimeterRadius,[host.record],AbyssStyle.connectionDepth,AbyssStyle.neckRadius)<0,"probe seam is unpainted")
    root.phase=identity+":painted-seam";move(seamX,seamY);wait(reveal.closeDelay+140);sample("seam-held")
    check(host.open&&reveal.bodyHovered,"PAINTED_SIDEBAR_SEAM_LOST_HOVER "+identity+" x="+seamX+" content="+content.x+" edge="+reveal.width)
    check(host.includeEdgeConnection&&host.controller.nativeInputRegions.includes(host.nativeInputRegion),"painted Sidebar connection absent from native mask")
    check(host.contentItem.width===root.canvasSize[0]&&host.contentItem.height===root.canvasSize[1],"handoff resized real content")
    root.phase=identity+":body";move(content.x+content.width/2,content.y+content.height/2);wait(reveal.closeDelay+100);check(host.open&&reveal.bodyHovered,"body did not own hover")
    // Painted curved shoulders outside the main body also own the lease.
    const shoulder=host.connectionRects.find(r=>r.width>0&&r.height>0&&Math.max(r.width,r.height)>1&&!Geometry.rectContains(host.inputBounds,r.x+r.width/2,r.y+r.height/2))
    check(!!shoulder,"missing actual painted shoulder")
    root.phase=identity+":shoulder";move(shoulder.x+shoulder.width/2,shoulder.y+shoulder.height/2);wait(reveal.closeDelay+100)
    check(host.open&&reveal.bodyHovered,"painted shoulder lost Sidebar")
    root.phase=identity+":reverse";move(seamX,seamY);wait(reveal.closeDelay+100);check(host.open,"reverse seam lost Sidebar")
    root.phase=identity+":leave";move(horizontal?win.width-50:win.width/2,horizontal?win.height/2:win.height-30);tryVerify(()=>!host.open&&host.progress===0,5000)
    check(host.inputBounds.width===0&&host.inputBounds.height===0&&host.connectionRects.length===0,"closed Sidebar retained input")
    capture(identity+"-closed")
    root.phase=identity+":explicit-open"
    if(identity==="leftPanel")GlobalStates.openSidebarLeft(win.outputName,false)
    else GlobalStates.openSidebarRight(win.outputName,false)
    tryVerify(()=>host.open&&host.ready&&Math.abs(host.progress-1)<.000001,5000);wait(reveal.closeDelay+100)
    check(host.open,"explicit Sidebar open became hover-owned")
    if(identity==="leftPanel")GlobalStates.closeSidebarLeft()
    else GlobalStates.closeSidebarRight()
    tryVerify(()=>!host.open&&host.progress===0,5000);root.watching=null
   }
  }catch(e){error=String(e.message)+" "+String(e.stack)}
   report.setText(JSON.stringify({error,checks:root.checks,swaps:root.swaps,samples:root.samples,captures:root.captures,output:win?{width:win.width,height:win.height}:null}));report.waitForJob()
   console.info(error?"SIDEBAR_CONNECTION_FAIL":"SIDEBAR_CONNECTION_PASS",root.checks,root.swaps,error??"");Qt.quit()
  }
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
(folder/'shell.qml').write_text(qml)
# Presentation qualification uses real read-only NetworkManager queries, with
# rescan disabled and a one-second wait. Reject radio/profile mutations.
guard=folder/'guard-bin';guard.mkdir()
(guard/'nmcli').write_text("""#!/usr/bin/python3
import os,sys
args=sys.argv[1:]
allowed=[['monitor'],['radio','wifi'],['-t','-f','TYPE,STATE','d','status'],['-t','-f','CONNECTIVITY','g'],['-t','-f','NAME','c','show','--active'],['-f','IN-USE,SIGNAL,SSID','device','wifi'],['-g','ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY,RATE','d','w']]
if args not in allowed:raise SystemExit(125)
if args[-2:] in [['device','wifi'],['d','w']]:args+=['--rescan','no']
os.execv('/usr/bin/nmcli',['/usr/bin/nmcli','--wait','1',*args])
""")
(guard/'nmcli').chmod(0o700)
with private_wayland(folder,capture_focus=True) as env:
 if not env:print('SKIP: Sidebar connection requires private Niri');raise SystemExit(0)
 outputs=json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=env,text=True,timeout=4));name=next(iter(outputs.values()))['name']
 subprocess.run(['niri','msg','output',name,'scale',str(args.scale)],env=env,check=True,capture_output=True,timeout=4)
 cfg=folder/'config/alis';cfg.mkdir(parents=True);data=json.loads((root/'defaults/config.json').read_text())
 data['panelFamily']='abyss';data['enabledPanels']=['abyssPerimeter','abyssBar','abyssPopup','abyssSidebarLeft','abyssSidebarRight'];data['abyss']['companion']['enabled']=False
 data['abyss']['modules'].update(configured=True,outputLayouts=[],placements=[{'id':'subject','kind':'clock','edge':'top','position':.15}]);data['bar']['autoHide']['enable']=False;data['bar'].setdefault('visualizer',{})['enable']=False;data['sounds']['notifications']=False
 data['sidebar']['news']['enable']=False;data['bar']['weather']['enable']=False
 data['abyss']['positions']=[{'kind':kind,'edge':edge,'alignment':'center'} for kind,edge in zip(['leftPanel','rightPanel'],args.edge_pair.split(','))]
 for key in ['feature','system']:data['sidebar']['shellLayout'][key].update(sizeMode='custom',customHeight=400,width=360)
 (cfg/'config.json').write_text(json.dumps(data));env.update(PATH=str(guard)+os.pathsep+os.environ['PATH'],SIDEBAR_CONNECTION_REPORT=str(out/'trace.json'),SIDEBAR_CONNECTION_IMAGES=str(out),QSG_RHI_BACKEND='opengl')
 r=run_qs(folder,env,timeout=50);(out/'native.log').write_text(r.stdout)
 report={'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'scale':args.scale,'edge_pair':args.edge_pair,'runtime_changes_from_head':subprocess.check_output(['git','diff','--name-only','HEAD','--','modules','services'],text=True).splitlines(),'fixture_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'actual_native_exit':r.returncode,'trace':json.loads((out/'trace.json').read_text()) if(out/'trace.json').exists() else None,'scope':'Production Perimeter/Sidebar content; QtTest mouse events on native QQuickWindow, not physical wl_pointer or Owner acceptance'}
 (out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
 print('\n'.join(line for line in r.stdout.splitlines() if 'SIDEBAR_CONNECTION_' in line));print('EVIDENCE',out,'NATIVE_EXIT',r.returncode)
 raise SystemExit(0 if r.returncode==0 and report['trace'] and report['trace']['error'] is None and 'SIDEBAR_CONNECTION_PASS' in r.stdout else 1)
