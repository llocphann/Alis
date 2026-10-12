#!/usr/bin/env python3
"""Compact/expanded editor, four edges, small viewports and real Qt controls."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
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
  function item(name){const result=findChild(editor,name);check(!!result,"missing "+name);return result}
  function frame(label){let done=false;check(scene.grabToImage(result=>{root.frames++;if(label&&Quickshell.env("ALIS_COMPACT_EDITOR_EVIDENCE"))check(result.saveToFile(Quickshell.env("ALIS_COMPACT_EDITOR_EVIDENCE")+"/"+label+".png"),"capture write");done=true}),"capture refused");tryVerify(()=>done,4000)}
  function settle(edge){wait(130);editor.toolbarEdge=edge;wait(100);check(waitForPolish(editor.Window.window,3000),"layout polish did not settle")}
  function control(name){
   const target=item(name),scroll=item("abyssEdgeEditorScroll")
   check(target.visible,"hidden control "+name)
   const point=target.mapToItem(scroll.contentItem,0,0)
   scroll.contentY=Math.max(0,Math.min(scroll.contentHeight-scroll.height,point.y-8));wait(35)
   const bounds=target.mapToItem(scroll,0,0)
   check(bounds.x>=-.1&&bounds.y>=-.1&&bounds.x+target.width<=scroll.width+.1&&bounds.y+target.height<=scroll.height+.1,"control outside its real clip "+JSON.stringify({name:name,x:bounds.x,y:bounds.y,w:target.width,h:target.height,clipW:scroll.width,clipH:scroll.height}))
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
   const saved=JSON.stringify(Config.options.abyss.modules.placements)
   const cases=[[800,800,1,true],[420,440,1,true],[320,240,1.5,false]]
   for(let n=0;n<cases.length;n++){
    const [w,h,scale,dark]=cases[n];root.testWidth=w;root.testHeight=h
    Config.setNestedValue("appearance.typography.sizeScale",scale)
    editor.outputName=n===2 ? "Display With A Very Long Name For Layout Editing" : "A"
    Appearance.m3colors.darkmode=dark
    Appearance.m3colors.m3background=dark?"#0b171a":"#edf1ef"
    for(const role of ["m3surfaceDim","m3surfaceBright","m3surfaceContainerLowest","m3surfaceContainerLow","m3surfaceContainerHigh","m3surfaceContainerHighest"])
     Appearance.m3colors[role]=dark?"#10252a":"#dde9e7"
    Appearance.m3colors.m3onBackground=dark?"#d8edef":"#132f34"
    Appearance.m3colors.m3onSurfaceVariant=dark?"#b5d9dc":"#32494d"
    Appearance.m3colors.m3surface=dark?"#0b171a":"#edf1ef"
    Appearance.m3colors.m3surfaceContainer=dark?"#10252a":"#dde9e7"
    Appearance.m3colors.m3primary=dark?"#82d9df":"#236d78"
    Appearance.m3colors.m3onSurface=dark?"#d8edef":"#132f34"
    for(const edge of ["top","right","bottom","left"]){
     editor.editingPopups=false;editor.select("a");settle(edge)
     const body=item("abyssEdgeEditorBody"),scroll=item("abyssEdgeEditorScroll")
     const done=item("abyssLayoutDone")
     const glyph=findChild(done,"abyssButtonCenteredGlyph")
     check(!!glyph,"missing icon-only centered glyph")
     const middle=glyph.mapToItem(done,glyph.width/2,glyph.height/2)
     check(Math.abs(middle.x-done.width/2)<.6 && Math.abs(middle.y-done.height/2)<.6,
         "icon-only glyph not centered in its button")
     check(done.width<=editor.editorActionSize+.6 && done.height<=editor.editorActionSize+.6,
         "editor button exceeds compact square size")
     tryVerify(()=>body.presented&&body.ready,3000)
     check(!editor.layoutConflicts.length,"fixture exceeds actual available module capacity")
     for(const name of ["abyssLayoutUndo","abyssLayoutCancel","abyssLayoutDone","abyssEditorConfirmAdd","abyssEditorSelection","abyssModulePositionLock","abyssSelectionEnabled","abyssSelectionRemove"])
      control(name)
     const layout={span:body.span,depth:body.depth,area:body.span*body.depth,height:scroll.contentHeight}
     frame(n===0||n===2?"layout-"+n+"-"+edge:null)
     click("abyssModulePositionLock");check(editor.allTargetsLocked,"quick lock did not apply")
     click("abyssModulePositionLock");check(!editor.anyTargetLocked,"quick unlock did not apply")
     click("abyssSelectionEnabled");check(editor.allTargetsDisabled,"quick disable did not apply")
     click("abyssSelectionEnabled");check(!editor.allTargetsDisabled,"quick enable did not apply")
     check(editor.expandedControls,"editor options unexpectedly hidden")
     control("abyssRoundZeroCorners");control("abyssModuleJoinCorner");control("abyssModuleRounding")
     control("abyssJoinNearbyModules")
     // All nine fine-control grid cells remain in place when the Width
     // scales modules mode changes, including Join and Module rounding.
     const scaleSlider=control("abyssScaleModulesSlider")
     const scaleToggle=control("abyssScaleModulesToggle")
     const join=control("abyssJoinNearbyModules")
     const rounding=control("abyssModuleRounding")
     check(scaleSlider.width<=editor.editorSliderWidth+.5,"scale slider exceeds shared width")
     const point=(item)=>item.mapToItem(scroll.contentItem,0,0)
     const before=[point(scaleSlider),point(join),point(rounding)]
     const wasScaling=editor.edgeWidthAffectsModules[editor.editingEdge]!==false
     check(join.enabled===!wasScaling && rounding.enabled===!wasScaling,
         "Join/rounding available in wrong width mode")
     click("abyssScaleModulesToggle");wait(100)
     check((editor.edgeWidthAffectsModules[editor.editingEdge]!==false)!==wasScaling,
         "scale toggle did not change draft")
     check(join.enabled===wasScaling && rounding.enabled===wasScaling,
         "Join/rounding state failed to follow width mode")
     const after=[point(scaleSlider),point(join),point(rounding)]
     for(let i=0;i<before.length;i++)
      check(Math.abs(before[i].x-after[i].x)<.6 && Math.abs(before[i].y-after[i].y)<.6,
          "fine control jumped position at index "+i)
     click("abyssScaleModulesToggle");wait(100)
     check((editor.edgeWidthAffectsModules[editor.editingEdge]!==false)===wasScaling,
         "scale toggle did not restore draft")
     frame(n===0?"layout-options-"+edge:null)
     click("abyssEditorIpcMode");settle(edge);check(editor.editingPopups,"IPC mode was lost")
     const chooser=control("abyssEditorIpcKind")
     check(chooser.count===7,"quick IPC selector exposes popup relocation")
     chooser.forceActiveFocus();keyClick(Qt.Key_Home);keyClick(Qt.Key_Down);keyClick(Qt.Key_Down);wait(50)
     check(editor.previewKind==="brightness","keyboard IPC selector did not update real preview")
     tryVerify(()=>editor.previewHost.ready,3000)
     check(editor.previewKind==="brightness","IPC draft changed unexpectedly")
     click("abyssEditorModulesMode");settle(edge)
     check(JSON.stringify(Config.options.abyss.modules.placements)===saved,"controls wrote Config before Done")
     root.measurements.push({viewport:[scene.width,scene.height],fontScale:scale,dark:dark,edge:edge,layout:layout})
    }
   }
   root.testWidth=800;root.testHeight=800;Config.setNestedValue("appearance.typography.sizeScale",1);editor.outputName="A";wait(100)
   editor.editingPopups=false;editor.select("a");settle("bottom")
   const count=editor.draft.length
   check(editor.expandedControls,"module palette hidden by a stale Options mode")
   click("abyssEditorConfirmAdd");wait(100);check(editor.draft.length===count+1,"visible Add did not add a module")
   click("abyssSelectionRemove");wait(100);check(editor.draft.length===count,"quick Remove did not remove selected module")
   click("abyssLayoutUndo");wait(100);check(editor.draft.length===count+1,"Undo did not restore removed module")
   editor.finish(false);wait(100);check(JSON.stringify(Config.options.abyss.modules.placements)===saved,"Cancel mutated placements")
   GlobalStates.abyssEditing=true;wait(150);check(editor.expandedControls,"reopen should always show fine tuning")
   editor.select("a");editor.batch("locked",true);editor.finish(true);wait(250)
   check(Config.options.abyss.modules.outputLayouts.some(p=>p.outputName==="B"),"Done erased another output")
   console.info("ABYSS_COMPACT_EDITOR_PASS",root.checks,"checks",root.frames,"frames",JSON.stringify(root.measurements))
  }catch(error){console.error("ABYSS_COMPACT_EDITOR_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder, capture_focus=OUTPUT is not None) as env:
        if env is None:
            raise SystemExit("SKIP: compact editor requires private Niri")
        config = folder / "config/illogical-impulse"
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
