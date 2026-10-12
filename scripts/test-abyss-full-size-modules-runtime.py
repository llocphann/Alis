#!/usr/bin/env python3
"""One resident full module through four orientations; explicit capacity repair."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(os.environ['ALIS_FULL_MODULE_CAPTURE_DIR']).resolve() if os.environ.get('ALIS_FULL_MODULE_CAPTURE_DIR') else None
if OUTPUT:OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='alis-full-modules-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.bar
import "modules/abyss/looks/AbyssLayout.js" as Layout
ShellRoot {
 id:root
 property string kind:"clock"
 property string edge:"top"
 property real visualSize:1
 property int checks:0
 property int frames:0
 property bool capacityPhase:false
 property var capacityEntries:[]
 property string capturePath:Quickshell.env("ALIS_FULL_MODULE_CAPTURE_DIR")
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;implicitWidth:1000;implicitHeight:720;color:"#111820"
  Item {
   id:scene;anchors.fill:parent
   AbyssBarModule {
    id:module
    kind:root.kind;attachedEdge:root.edge
    vertical:root.edge==="left"||root.edge==="right"
    outputName:window.screen?.name??""
    visible:!root.capacityPhase
    contentScale:root.visualSize
    width:(contentVertical?32*Appearance.fontSizeScale:Math.max(40,naturalSpan))*root.visualSize
    height:(contentVertical?Math.max(40,naturalSpan):32*Appearance.fontSizeScale)*root.visualSize
    x:(scene.width-width)/2;y:(scene.height-height)/2
   }
   AbyssBar {
    id:bar;anchors.fill:parent;visible:root.capacityPhase
    edge:"top";outputName:window.screen?.name??""
    draftPlacements:root.capacityEntries
    draftOptions:({edgeThickness:16,edgeWidthAffectsModules:{top:false,right:false,bottom:false,left:false}})
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  SignalSpy {id:repair;target:bar;signalName:"layoutRepairRequested"}
  function check(v,m){root.checks++;if(!v)throw new Error(m)}
  function frame(save){
   const before=root.frames
   check(scene.grabToImage(result=>{
    root.frames++
    if(save&&root.capturePath.length)check(result.saveToFile(root.capturePath+"/"+root.kind+"-"+root.edge+"-"+root.frames+".png"),"capture write failed")
   }),"native frame refused")
   tryVerify(()=>root.frames>before,3000)
  }
  function run(){try{
   tryCompare(Config,"ready",true,5000)
   Config.setNestedValues({"performance.reduceAnimations":true,"bar.verbose":true})
   ShellUpdates.hasUpdate=true;ShellUpdates.commitsBehind=2
   for(const kind of Layout.catalog){
    root.kind=kind;root.edge="top";root.visualSize=1
    tryVerify(()=>module.feature!==null,5000);frame(false)
    const original=module.feature
    console.info("FULL_MODULE_TYPE",kind,String(original),"available",original.contentAvailable??original.visible)
    for(const edge of ["top","right","bottom","left","top"]){
     root.edge=edge;frame(true)
     check(module.feature===original,"orientation reloaded the feature "+kind+edge)
     check(module.feature.vertical===undefined||module.feature.vertical===false,"vertical substitute mode "+kind+edge)
     check(module.feature.compactRequested===undefined||module.feature.compactRequested===false,"compact substitute mode "+kind+edge)
     const loader=module.children.find(child=>child.item===original)
     check(loader!==undefined,"full-design Loader lost")
     const expected=edge==="left"?-90:edge==="right"?90:0
     check(loader.rotation===expected&&loader.scale===1,"orientation changed configured scale "+kind+edge)
     const a=loader.mapToItem(module,0,0),b=loader.mapToItem(module,loader.width,loader.height)
     check(Math.abs(Math.min(a.x,b.x))<.1&&Math.abs(Math.min(a.y,b.y))<.1&&Math.abs(Math.abs(b.x-a.x)-module.width)<.1&&Math.abs(Math.abs(b.y-a.y)-module.height)<.1,"rotated bounds/pivot mismatch "+kind+edge+" "+JSON.stringify({a:a,b:b,moduleWidth:module.width,moduleHeight:module.height,loaderWidth:loader.width,loaderHeight:loader.height,loaderX:loader.x,loaderY:loader.y,natural:module.naturalSpan}))
     mouseMove(module,module.width/2,module.height/2);wait(30)
     check(module.hovered,"full transformed pointer target lost "+kind+edge)
     mouseMove(scene,2,2);wait(10)
    }
    for(const scale of [.6,1.8]){root.visualSize=scale;root.edge="right";frame(false);check(module.feature===original,"custom size rebuilt feature");check(module.contentScale===scale,"explicit custom size lost")}
   }
   root.capacityPhase=true
   root.capacityEntries=Layout.normalize(Array.from({length:24},(_,i)=>({id:"clock"+i,kind:"clock",edge:"top",position:i/23})),"top")
   tryVerify(()=>bar.capacityNotices.length===1,4000);frame(false)
   check(bar.layoutRecords.length===24&&bar.layoutRecords.every(record=>record.capacityConflict),"invalid saved profile lost members")
   check(bar.moduleIds.every(id=>!bar.itemForId(id).visible&&!bar.itemForId(id).enabled),"rejected modules still paint or intercept input")
   check(bar.inputRegions.filter(region=>region.width>0&&region.height>0).length===1,"capacity rejection creates ghost input")
   const notice=findChild(bar,"abyssCapacityNotice_top")
   check(notice!==null&&notice.width>0,"missing visible capacity repair target")
   mouseClick(notice,notice.width/2,notice.height/2);tryCompare(repair,"count",1,1000)
   root.capacityEntries=root.capacityEntries.map((p,i)=>Object.assign({},p,{enabled:i<2}))
   tryVerify(()=>bar.capacityNotices.length===0&&bar.moduleIds.length===2,4000);frame(false)
   check(bar.moduleIds.every(id=>bar.itemForId(id).visible&&bar.itemForId(id).contentScale===1),"repair failed to restore full configured modules")
   console.info("ABYSS_FULL_MODULE_NATIVE_PASS",root.checks,"checks",root.frames,"frames",Layout.catalog.length,"kinds; resident controls, rotation, input, configured size and capacity repair")
  }catch(e){console.error("ABYSS_FULL_MODULE_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
 with private_wayland(folder,capture_focus=OUTPUT is not None) as env:
  if env is None:raise SystemExit('SKIP: full-module orientation requires private Niri')
  config=folder/'config/illogical-impulse';config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['panelFamily']='abyss';data['abyss']['companion']['enabled']=False
  (config/'config.json').write_text(json.dumps(data))
  if OUTPUT:env['ALIS_FULL_MODULE_CAPTURE_DIR']=str(OUTPUT)
  result=run_qs(folder,env,timeout=90)
  if OUTPUT:
   (OUTPUT/'native.log').write_text(result.stdout)
   (OUTPUT/'process.json').write_text(json.dumps({'exit_code':result.returncode,'saved_pngs':len(list(OUTPUT.glob('*.png')))},indent=2)+'\n')
   focus=folder/'native-test-capture-focus.json'
   if focus.exists():(OUTPUT/'focus.json').write_bytes(focus.read_bytes())
  bad=['ABYSS_FULL_MODULE_NATIVE_FAIL','TypeError:','ReferenceError:','Binding loop','Unable to assign','Failed to load configuration']
  if result.returncode or 'ABYSS_FULL_MODULE_NATIVE_PASS' not in result.stdout or any(token in result.stdout for token in bad):
   print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if 'ABYSS_FULL_MODULE_NATIVE_PASS' in line:print(line)
