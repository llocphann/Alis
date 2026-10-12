#!/usr/bin/env python3
"""Actual shader OFF parity, localized ON curves, editor control and JSON restart."""
import os,json,tempfile,subprocess
from pathlib import Path
from PIL import Image,ImageChops
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(os.environ['ALIS_ZERO_CAPTURE_DIR']).resolve() if os.environ.get('ALIS_ZERO_CAPTURE_DIR') else None
with tempfile.TemporaryDirectory(prefix='alis-zero-corners-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 dest=OUTPUT or folder/'evidence';dest.mkdir(parents=True,exist_ok=True)
 original=folder/'original';original.mkdir()
 source=subprocess.check_output(['git','show','05c440e0b:modules/abyss/looks/AbyssField.qml'],cwd=ROOT,text=True).replace('import qs.services','import qs.services\nimport qs.modules.abyss.looks')
 (original/'OriginalField.qml').write_text(source)
 (original/'AbyssField.frag.qsb').write_bytes(subprocess.check_output(['git','show','05c440e0b:modules/abyss/looks/AbyssField.frag.qsb'],cwd=ROOT))
 (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import "original"
ShellRoot {
 id:root;property int checks:0;property int frames:0;property bool original:false
 property var insets:({left:16,top:0,right:16,bottom:16});property var choice:({});property var moduleRecords:[]
 Component.onCompleted:Quickshell.watchFiles=false
 FileView {id:disk;path:Config.filePath;watchChanges:true;property var snapshot:null;onLoaded:{try{snapshot=JSON.parse(text())}catch(error){snapshot=null}}}
 AbyssSurfaceController {id:liquid}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {id:scene;anchors.fill:parent
   Loader {id:field;anchors.fill:parent;sourceComponent:root.original?old:current}
   AbyssBar {id:layer;anchors.fill:parent;outputName:"A";edge:"top";editing:editor.visible;draftPlacements:!Config.ready?[]:editor.visible?editor.draft:null;draftOptions:editor.visible?editor.draftOptions:null;liquidController:liquid}
   AbyssEdgeEditor {id:editor;anchors.fill:parent;outputName:"A";moduleLayer:layer;controller:liquid;visible:GlobalStates.abyssEditing}
  }
 }
 Component {id:old;OriginalField {edgeInsets:root.insets}}
 Component {id:current;AbyssField {edgeInsets:root.insets;roundZeroCorners:root.choice;records:root.moduleRecords}}
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function capture(label){tryVerify(()=>field.item?.ready,5000);wait(40);let done=false;check(field.item.grabToImage(result=>{check(result.saveToFile(Quickshell.env("ZERO_EVIDENCE")+"/"+label+".png"),"write capture");root.frames++;done=true}),"native frame refused");tryVerify(()=>done,5000)}
  function control(){if(!editor.expandedControls){mouseClick(findChild(editor,"abyssEditorOptions"));wait(130)}const item=findChild(editor,"abyssRoundZeroCorners");let view=item.parent;while(view&&view.contentHeight===undefined)view=view.parent;check(!!view,"checkbox scroll viewport");const point=item.mapToItem(view.contentItem,0,0);view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,point.y-view.height/2));wait(60);return item}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"performance.reduceAnimations":true,"abyss.effects.blur.enabled":false,"abyss.content.blurRadius":0,"abyss.effects.refraction.enabled":false})
   if(Quickshell.env("ZERO_ACTION")==="restart"){
    GlobalStates.abyssEditing=true;wait(80)
    check(["top","right","bottom","left"].every(edge=>editor.edgeRoundZeroCorners[edge]===true),"0px flags lost after process restart")
    check(Config.options.abyss.modules.outputLayouts.some(p=>p.outputName==="B"),"other output lost on restart")
   }else{
    for(const edge of ["top","right","bottom","left"]){
     root.insets=Object.assign({left:16,top:16,right:16,bottom:16},{[edge]:0});root.choice={};root.original=true;capture(edge+"-old");root.original=false;capture(edge+"-off")
     root.choice={[edge]:true}
     for(const radius of [12,34,64]){Config.setNestedValue("abyss.perimeter.radius",radius);capture(edge+"-on-"+radius)}
     Config.setNestedValue("abyss.perimeter.radius",34)
    }
    root.insets={left:16,top:16,right:16,bottom:16};root.choice={top:true,right:true,bottom:true,left:true};root.original=true;capture("nonzero-old");root.original=false;capture("nonzero-on")
    root.insets={left:0,top:0,right:0,bottom:0};root.choice={top:true,right:false,bottom:false,left:false};capture("mixed-top");root.choice={top:true,right:true,bottom:false,left:false};capture("mixed-top-right")
    // Two real-size local backings that obscure both top 0px curves in the old shader.
    root.insets={left:0,top:0,right:0,bottom:0};root.moduleRecords=[{surface:{x:-50,y:-50,width:195,height:170},radius:0},{surface:{x:855,y:-50,width:195,height:170},radius:0}]
    root.choice={};capture("modules-top-off");root.choice={top:true};capture("modules-top-on")
    root.moduleRecords=[]
    GlobalStates.deferredPanelsReady=true;GlobalStates.abyssEditing=true;wait(100)
    const initial=JSON.stringify(editor.edgeRoundZeroCorners)
    for(const edge of ["top","right","bottom","left"]){
     editor.editingEdge=edge;const checkbox=control();check(!checkbox.enabled,"0px checkbox active at nonzero width")
     editor.edgeThicknesses=Object.assign({},editor.edgeThicknesses,{[edge]:0});wait(30);check(checkbox.enabled,"0px checkbox not enabled")
     mouseClick(checkbox);wait(30);check(editor.edgeRoundZeroCorners[edge]===true,"actual checkbox failed on "+edge)
    }
    editor.reset();wait(40);check(Object.values(editor.edgeRoundZeroCorners).every(v=>!v),"Reset retains zero-corner choices")
    editor.undo();wait(40);check(Object.values(editor.edgeRoundZeroCorners).every(v=>v),"Undo Reset loses choices")
    editor.finish(false);wait(80);GlobalStates.abyssEditing=true;wait(80);check(JSON.stringify(editor.edgeRoundZeroCorners)===initial,"Cancel rewrites zero-corner choices")
    for(const edge of ["top","right","bottom","left"]){editor.edgeThicknesses=Object.assign({},editor.edgeThicknesses,{[edge]:0});editor.edgeRoundZeroCorners=Object.assign({},editor.edgeRoundZeroCorners,{[edge]:true})}
    editor.finish(true);wait(250);GlobalStates.abyssEditing=true;wait(80)
    check(Object.values(editor.edgeRoundZeroCorners).every(v=>v),"Done/reopen loses choices")
    tryVerify(()=>{disk.reload();wait(60);const profile=disk.snapshot?.abyss?.modules?.outputLayouts?.find(p=>p.outputName==="A");return !!profile && ["top","right","bottom","left"].every(edge=>profile.edgeRoundZeroCorners?.[edge]===true)},6000)
   }
   console.info("ABYSS_ZERO_NATIVE_PASS",Quickshell.env("ZERO_ACTION"),root.checks,"checks",root.frames,"frames")
  }catch(e){console.error("ABYSS_ZERO_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
 with private_wayland(folder,capture_focus=OUTPUT is not None) as env:
  if env is None:raise SystemExit('SKIP: zero-corner native requires private Niri')
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['panelFamily']='abyss';data['abyss']['companion']['enabled']=False;data['abyss']['modules']['configured']=True;data['abyss']['modules']['placements']=[];data['abyss']['modules']['outputLayouts']=[{'outputName':'B','placements':[],'edgeRoundZeroCorners':{'left':True}}]
  (cfg/'config.json').write_text(json.dumps(data))
  for action in ['exercise','restart']:
   result=run_qs(folder,dict(env,ZERO_EVIDENCE=str(dest),ZERO_ACTION=action),timeout=90)
   (dest/(action+'.log')).write_text(result.stdout)
   if result.returncode or 'ABYSS_ZERO_NATIVE_PASS' not in result.stdout or any(t in result.stdout for t in ['ABYSS_ZERO_NATIVE_FAIL','Binding loop','Unable to assign','ReferenceError:','TypeError:','Failed to load configuration','shader preparation failed']):print(result.stdout);raise SystemExit(1)
   receipt=json.loads((cfg/'config.json').read_text());(dest/(action+'-config.json')).write_text(json.dumps(receipt['abyss']['modules'],indent=2)+'\n')
   if action=='exercise':
    profile=next(p for p in receipt['abyss']['modules']['outputLayouts'] if p['outputName']=='A');assert all(profile['edgeRoundZeroCorners'].get(edge) is True for edge in ['top','right','bottom','left'])
   for line in result.stdout.splitlines():
    if 'ABYSS_ZERO_NATIVE_PASS' in line:print(line)
  focus=folder/'native-test-capture-focus.json'
  if focus.exists():(dest/'focus.json').write_bytes(focus.read_bytes())
 images={p.stem:Image.open(p).convert('RGBA') for p in dest.glob('*.png')};checks=0
 for edge in ['top','right','bottom','left']:
  old=images[edge+'-old'];off=images[edge+'-off'];assert ImageChops.difference(old,off).getbbox(alpha_only=False) is None,edge+' OFF changed original RGBA';checks+=1
  for r in [12,34,64]:
   on=images[edge+'-on-'+str(r)];assert ImageChops.difference(off,on).getbbox(alpha_only=False),edge+' ON lacks curve';checks+=1
   w,h=off.size;box=(0,120,w,h-120) if edge in ['left','right'] else (120,0,w-120,h)
   assert ImageChops.difference(off.crop(box),on.crop(box)).getbbox(alpha_only=False) is None,'0px side gained a full strip';checks+=1
 assert ImageChops.difference(images['nonzero-old'],images['nonzero-on']).getbbox(alpha_only=False) is None,'nonzero choice changes original pixels';checks+=1
 # Modules obscure the old top arcs; both left/right inner openings must reappear.
 baseline=images['modules-top-off'];restored=images['modules-top-on'];w,h=baseline.size
 for box in [(0,0,85,85),(w-85,0,w,85)]:
  assert ImageChops.difference(baseline.crop(box),restored.crop(box)).getbbox(alpha_only=False),'module-covered top corner did not change'
  checks+=1
 assert ImageChops.difference(baseline.crop((250,0,w-250,h)),restored.crop((250,0,w-250,h))).getbbox(alpha_only=False) is None,'corner clipping altered middle of output';checks+=1
 # Adding Right owns BR, while already-owned TR remains byte-identical.
 w,h=images['mixed-top'].size;box=(w-100,0,w,100)
 assert ImageChops.difference(images['mixed-top'].crop(box),images['mixed-top-right'].crop(box)).getbbox(alpha_only=False) is None,'shared corner double-draw';checks+=1
 (dest/'pixel-receipt.json').write_text(json.dumps({'checks':checks,'pngs':len(images),'off_or_nonzero_rgba_exact':True,'shared_corner_rgba_exact':True},indent=2)+'\n')
 print('ABYSS_ZERO_GPU_PASS',checks,'pixel comparisons',len(images),'PNG')
