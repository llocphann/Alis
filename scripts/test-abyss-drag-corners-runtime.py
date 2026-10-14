#!/usr/bin/env python3
"""Native Qt input: off-center grab, primary tracking, neighbor motion and pins."""
import os,json,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(os.environ['ALIS_DRAG_CAPTURE_DIR']).resolve() if os.environ.get('ALIS_DRAG_CAPTURE_DIR') else None
if OUTPUT:OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='alis-drag-corners-') as name:
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
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssLayout.js" as Layout
ShellRoot {
 id:root;property int checks:0;property int frames:0;property var samples:[]
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {id:liquid}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;anchors.fill:parent
   AbyssBar {id:layer;anchors.fill:parent;outputName:"A";edge:"top";editing:editor.visible;draggedIds:editor._dragging?editor.targetIds:[];draftPlacements:!Config.ready?[]:editor.visible?editor.draft:null;draftOptions:editor.visible?editor.draftOptions:null;liquidController:liquid}
   AbyssEdgeEditor {id:editor;anchors.fill:parent;outputName:"A";moduleLayer:layer;controller:liquid;visible:GlobalStates.abyssEditing}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function rec(id){return layer.layoutRecords.find(r=>r.id===id)}
  function frame(label){let done=false;check(scene.grabToImage(result=>{root.frames++;if(label&&Quickshell.env("ALIS_DRAG_CAPTURE_DIR"))check(result.saveToFile(Quickshell.env("ALIS_DRAG_CAPTURE_DIR")+"/"+label+".png"),"capture write");done=true}),"frame refused");tryVerify(()=>done,4000)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":false,"abyss.modules.configured":true,"abyss.modules.edgeWidthAffectsModules":{top:false,right:false,bottom:false,left:false},"abyss.modules.placements":[{id:"a",kind:"clock",edge:"top",position:.2},{id:"b",kind:"clock",edge:"top",position:.42},{id:"pin",kind:"clock",edge:"top",position:.82}]})
   GlobalStates.deferredPanelsReady=true;GlobalStates.abyssEditing=true;wait(250);frame("before")
   const a=layer.itemForId("a"),b=layer.itemForId("b"),types=[a.feature,b.feature],initial=rec("a")
   editor.toggleLock("pin");const pin=layer.itemForId("pin"),pinX=pin.x
   let grab={x:a.x+17,y:a.y+9};let offset=grab.x-a.x-a.width/2
   const handle=findChild(editor,"abyssModuleHandle");check(handle.modelData==="a","first actual editor handle changed");mousePress(handle,17,9);check(editor._dragging&&editor._dragContext!==null,"native press did not capture grab point");grab={x:editor._dragContext.originX,y:editor._dragContext.originY};offset=grab.x-a.x-a.width/2;editor.snapEnabled=false
   editor.move("a",grab.x,grab.y,false);frame()
   check(Math.abs(a.x-initial.content.x)<.1,"off-center press recenters primary "+JSON.stringify({x:a.x,before:initial.content.x,grab:grab,ctx:editor._dragContext}))
   const neighborStart=b.x;let intermediate=false
   const started=Date.now()
   for(let i=1;i<=12;i++){
    const px=grab.x+(scene.width*.4-(a.width/2+initial.content.x))*i/12
    mouseMove(scene,px,grab.y,0)
    const target=rec("a");frame(i===12?"during":null)
    check(!editor.feedback&&Math.abs(a.x-target.content.x)<.1,"drag target lags its computed position")
    check(Math.abs(a.x+a.width/2-(px-offset))<1,"dragged module loses grab point")
    check(pin.x===pinX,"neighbor animation moves pinned module")
    const shown=layer.renderedRecords.find(r=>r.id==="b")
    check(shown.content.x===b.x&&shown.along===b.x,"paint/handle geometry jumps ahead of displayed neighbor")
    const end=rec("b").content.x
    if(b.x>neighborStart+.01&&b.x<end-.01)intermediate=true
    root.samples=root.samples.concat([{elapsedMs:Date.now()-started,primary:a.x,target:target.content.x,neighbor:b.x,neighborTarget:end}])
   }
   check(intermediate,"neighbor teleports without intermediate motion")
   mouseRelease(scene,grab.x+scene.width*.4-(a.width/2+initial.content.x),grab.y);tryVerify(()=>Math.abs(b.x-rec("b").content.x)<.1,2000);frame("settled")
   check(a.feature===types[0]&&b.feature===types[1],"drag reloaded mature components")
   Config.setNestedValue("performance.reduceAnimations",true);editor.selectedId="b"
   editor.change("position",.64);frame();check(Math.abs(b.x-rec("b").content.x)<.1,"reduced motion retains an unexpected tween")
   editor.toggleLock("pin");Config.setNestedValue("performance.reduceAnimations",false)
   editor.selectedId="b";editor.change("position",.98);tryVerify(()=>Math.abs(b.x-rec("b").content.x)<.1,2000)
   editor.change("customSize",true);editor.change("size",1.1);frame("resize")
   check(b.x+b.width<=rec("b").edgeEnd+.1,"resize animation clips full content through corner bounds")
   editor.change("edge","right");frame("edge-transfer")
   check(Math.abs(b.x-rec("b").content.x)<.1&&Math.abs(b.y-rec("b").content.y)<.1,"orientation transfer animates detached through workspace")
   editor.clearSelection();editor.draft=Layout.normalize([{id:"a",kind:"clock",edge:"top",position:0,enabled:true},{id:"b",kind:"clock",edge:"left",position:0,enabled:true}],"top");editor.refreshHandles();wait(80);frame("corner")
   const x=rec("a").content,y=rec("b").content
   check(x.x+x.width+8<=y.x+.1||y.x+y.width+8<=x.x+.1||x.y+x.height+8<=y.y+.1||y.y+y.height+8<=x.y+.1,"corner controls overlap")
   const saved=JSON.stringify(editor.draft);editor.finish(true);wait(100);GlobalStates.abyssEditing=true;wait(100)
   check(JSON.stringify(editor.draft)===saved,"Done/reopen drifts saved centers")
   editor.selectedId="a";editor.change("position",.5);editor.finish(false);wait(100);GlobalStates.abyssEditing=true;wait(100)
   check(JSON.stringify(editor.draft)===saved,"Cancel rewrites source layout")
   console.info("ABYSS_DRAG_CORNERS_NATIVE_PASS",root.checks,"checks",root.frames,"frames;",JSON.stringify(root.samples))
  }catch(e){console.error("ABYSS_DRAG_CORNERS_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
 with private_wayland(folder,capture_focus=OUTPUT is not None) as env:
  if env is None:raise SystemExit('SKIP: native drag requires private Niri')
  config=folder/'config/alis';config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['panelFamily']='abyss';data['abyss']['companion']['enabled']=False
  (config/'config.json').write_text(json.dumps(data))
  if OUTPUT:env['ALIS_DRAG_CAPTURE_DIR']=str(OUTPUT)
  result=run_qs(folder,env,timeout=65)
  if OUTPUT:
   (OUTPUT/'native.log').write_text(result.stdout);(OUTPUT/'process.json').write_text(json.dumps({'exit_code':result.returncode,'pngs':len(list(OUTPUT.glob('*.png')))},indent=2)+'\n')
   focus=folder/'native-test-capture-focus.json'
   if focus.exists():(OUTPUT/'focus.json').write_bytes(focus.read_bytes())
  bad=['ABYSS_DRAG_CORNERS_NATIVE_FAIL','TypeError:','ReferenceError:','Binding loop','Unable to assign','Failed to load configuration']
  if result.returncode or 'ABYSS_DRAG_CORNERS_NATIVE_PASS' not in result.stdout or any(t in result.stdout for t in bad):print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if 'ABYSS_DRAG_CORNERS_NATIVE_PASS' in line:print(line)
