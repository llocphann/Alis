#!/usr/bin/env python3
"""Compact/expanded editor, four edges, small viewports and real Qt controls."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(os.environ.get("ALIS_COMPACT_EDITOR_SOURCE", Path(__file__).resolve().parents[1])).resolve()
OUTPUT = Path(os.environ["ALIS_COMPACT_EDITOR_EVIDENCE"]).resolve() if os.environ.get("ALIS_COMPACT_EDITOR_EVIDENCE") else None
if OUTPUT:
    OUTPUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="alis-compact-editor-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
ShellRoot {
 id:root;property int checks:0;property int frames:0;property var measurements:[]
 property real testWidth:800;property real testHeight:800
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {
  id:liquid;outputWidth:scene.width;outputHeight:scene.height;presentationItem:scene
  moduleRecords:layer.deformations;sourceInputRegions:editor.inputRegions
 }
 FloatingWindow {
  id:window;visible:true;implicitWidth:1000;implicitHeight:1000;color:"#111820"
  Item {
   id:scene;width:Math.min(root.testWidth,window.width);height:Math.min(root.testHeight,window.height)
   AbyssField {id:field;anchors.fill:parent;z:-1;edgeInsets:editor.edgeInsets;records:liquid.records;waveTexture:liquid.waves.texture}
   AbyssBar {id:layer;anchors.fill:parent;outputName:"A";edge:"top";editing:editor.visible;draftPlacements:editor.visible?editor.draft:null;draftOptions:editor.visible?editor.draftOptions:null;liquidController:liquid}
   AbyssEdgeEditor {id:editor;anchors.fill:parent;outputName:"A";moduleLayer:layer;controller:liquid;visible:GlobalStates.abyssEditing}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,label){root.checks++;if(!value)throw new Error(label)}
  function centerY(target,ancestor){return target.mapToItem(ancestor,0,target.height/2).y}
  function item(name){const result=findChild(editor,name);check(!!result,"missing "+name);return result}
  function frame(label){let done=false;check(scene.grabToImage(result=>{root.frames++;if(label&&Quickshell.env("ALIS_COMPACT_EDITOR_EVIDENCE"))check(result.saveToFile(Quickshell.env("ALIS_COMPACT_EDITOR_EVIDENCE")+"/"+label+".png"),"capture write");done=true}),"capture refused");tryVerify(()=>done,4000)}
  function settle(edge){wait(130);editor.toolbarEdge=edge;wait(100);check(waitForPolish(editor.Window.window,3000),"layout polish did not settle")}
  function control(name){
   const target=item(name),scroll=item("abyssEdgeEditorScroll")
   check(target.visible,"hidden control "+name)
   const point=target.mapToItem(scroll.contentItem,0,0)
   scroll.contentY=Math.max(0,Math.min(scroll.contentHeight-scroll.height,point.y-8));wait(35)
   const bounds=target.mapToItem(scroll,0,0)
   check(bounds.x>=-.1&&bounds.y>=-.1&&bounds.x+target.width<=scroll.width+.1&&bounds.y+target.height<=scroll.height+.1,"control outside its real clip "+JSON.stringify({edge:editor.toolbarEdge,viewport:[scene.width,scene.height],fontScale:Appearance.fontSizeScale,name:name,x:bounds.x,y:bounds.y,w:target.width,h:target.height,clipW:scroll.width,clipH:scroll.height}))
   return target
  }
  function click(name){const target=control(name);mouseClick(target);wait(40)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true,"abyss.modules.configured":true,
    "abyss.modules.edgeWidthAffectsModules":{top:false,right:false,bottom:false,left:false},
    "abyss.modules.placements":[{id:"a",kind:"clock",edge:"top",position:.2,customSize:true,size:.6},{id:"b",kind:"clock",edge:"top",position:.7,customSize:true,size:.6}],
    "abyss.modules.outputLayouts":[{outputName:"B",placements:[],edgeJoinModules:{left:true}}]})
   GlobalStates.deferredPanelsReady=true;GlobalStates.abyssEditing=true;wait(150)
   check(editor.expandedControls,"editing options must be always visible")
   const names=["abyssLayoutUndo","abyssLayoutReset","abyssLayoutCancel","abyssLayoutDone","abyssEditorModulesMode","abyssEditorIpcMode","abyssEditorConfirmAdd","abyssModuleDropdown","abyssModulePositionLock","abyssSelectionEnabled","abyssSelectionRemove","abyssModuleJoinCorner","abyssEditorIpcOutput","abyssEditorOutputOnly"]
   for(const [w,h,scale] of [[800,800,1],[420,440,1],[320,240,1.5]]) {
    root.testWidth=w;root.testHeight=h;Config.setNestedValue("appearance.typography.sizeScale",scale)
    for(const edge of ["top","right","bottom","left"]) {
     editor.editingPopups=false;editor.select("a");settle(edge)
     tryVerify(()=>item("abyssEdgeEditorBody").ready,3000)
     const controls=[]
     for(const name of names) {
      const target=control(name);controls.push({name:name,width:target.width,height:target.height})
     }
     if(w===800 && edge==="right")frame("side-controls")
     if(scale===1.5)frame("narrow-"+edge)
     root.measurements.push({viewport:[w,h],fontScale:scale,edge:edge,controls:controls})
    }
   }
   console.info("ABYSS_COMPACT_EDITOR_PASS",root.checks,"checks",root.frames,"frames",JSON.stringify(root.measurements))
  }catch(error){frame("failure");console.error("ABYSS_COMPACT_EDITOR_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder, capture_focus=OUTPUT is not None) as env:
        if env is None:
            raise SystemExit("SKIP: compact editor requires private Niri")
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["abyss"]["companion"]["enabled"] = False
        (config / "config.json").write_text(json.dumps(data))
        if OUTPUT:
            env["ALIS_COMPACT_EDITOR_EVIDENCE"] = str(OUTPUT)
        result = run_qs(folder, env, timeout=95)
        if OUTPUT:
            (OUTPUT / "native.log").write_text(result.stdout)
            (OUTPUT / "process.json").write_text(json.dumps({"exit_code": result.returncode}, indent=2) + "\n")
            focus = folder / "native-test-capture-focus.json"
            if focus.exists():
                (OUTPUT / "focus.json").write_bytes(focus.read_bytes())
        bad = ["ABYSS_COMPACT_EDITOR_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]
        if result.returncode or "ABYSS_COMPACT_EDITOR_PASS" not in result.stdout or any(x in result.stdout for x in bad):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "ABYSS_COMPACT_EDITOR_PASS" in line:
                print(line)
