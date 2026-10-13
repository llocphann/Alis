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
     for(const name of ["abyssLayoutUndo","abyssLayoutCancel","abyssLayoutDone","abyssEditorConfirmAdd","abyssModulePositionLock","abyssSelectionEnabled","abyssSelectionRemove"])
      control(name)
     // The selected-module dropdown was intentionally removed. The only
     // module picker is the add-module palette; module selection remains on
     // Screen Edge handles. Scope controls stay available in both tabs.
     check(!findChild(editor,"abyssEditorSelection"),"duplicate module dropdown returned")
     const header=item("abyssEditorModeHeader")
     const tabs=control("abyssEditorModeTabs")
     const scope=control("abyssEditorOutputScope")
     const sharedOutput=control("abyssEditorIpcOutput")
     const outputCheckbox=control("abyssEditorOutputOnly")
     const origin=(item)=>item.mapToItem(scroll.contentItem,0,0)
     if(header.columns===2) {
      check(Math.abs(origin(tabs).y-origin(scope).y)<1,
          "tabs and output scope do not share the first row")
      check(origin(tabs).x<origin(sharedOutput).x
          && origin(sharedOutput).x<origin(outputCheckbox).x,
          "first row is not tabs-left / dropdown-checkbox-right")
     } else {
      check(origin(scope).y>=origin(tabs).y+tabs.height-1,
          "narrow scope controls should stack below the tabs")
     }
     check(outputCheckbox.checked===editor.outputOnly,
         "scope checkbox differs from shared output value")
     // Two grouped columns begin with their own text-only dropdowns.
     // The short dividing line only appears when the panel has room.
     const modulePicker=control("abyssModuleDropdown")
     const edgePicker=control("abyssEditingEdgeDropdown")
     const grouped=item("abyssEditorFineControls")
     const divider=item("abyssEditorColumnDivider")
     const moduleColumn=item("abyssEditorModuleColumn")
     const edgeColumn=item("abyssEditorEdgeColumn")
     check(modulePicker.visible && edgePicker.visible, "missing Module/Editing Edge dropdown")
     const inScroll=(item)=>item.mapToItem(scroll.contentItem,0,0)
     // Regression: the prior self-referential GridLayout.width condition
     // silently collapsed TOP/BOTTOM toolbars to one column on startup.
     const expectedTwo=editor.toolbarOnHorizontalEdge
         && scroll.width>=520*scale
     check(grouped.columns===(expectedTwo?3:1),
         "horizontal toolbar has enough viewport width but collapsed to one column")
     if(expectedTwo) {
      const left=inScroll(modulePicker),right=inScroll(edgePicker)
      check(left.x<right.x && Math.abs(left.y-right.y)<1.5,
          "Module and Editing Edge dropdowns are not aligned as column headers")
      const middle=inScroll(divider)
      check(divider.visible && divider.width<=2*scale
          && divider.height<=70*scale,"divider must remain narrow, short and visible")
      check(middle.x>left.x && middle.x<right.x,
          "divider is not between the two columns")
     } else {
      check(grouped.columns===1 && !divider.visible,
          "narrow side editor should stack columns and hide divider")
      check(inScroll(edgeColumn).y>=inScroll(moduleColumn).y+moduleColumn.height-1,
          "stacked edge controls should follow module controls")
     }
     // Related Module/Edge controls must share the same physical toolbar row.
     const sameRow=(a,b,label)=>check(
       Math.abs(inScroll(control(a)).y-inScroll(control(b)).y)<1.5,
       label+" controls should occupy one row")
     sameRow("abyssModuleDropdown","abyssModulePositionLock","Module header")
     sameRow("abyssModuleDropdown","abyssModuleJoinCorner","Module corner")
     sameRow("abyssEditingEdgeDropdown","abyssJoinNearbyModules","Edge header")
     sameRow("abyssModuleRoundingAction","abyssModuleRounding","Rounding")
     const round0=control("abyssRoundZeroCorners")
     check(round0.checkable && round0.width<=editor.editorActionSize+.6,
           "Round at 0px should be an icon toggle")
     check(control("abyssModuleRoundingAction").checkable,
           "Inherited module rounding should be a toggle")
     check(!editor.toolbarOnHorizontalEdge || body.span<=660*scale+.6,
           "Horizontal Edit Abyss Layout width was not reduced")
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
     const outputPicker=control("abyssEditorIpcOutput")
     const placement=item("abyssEditorIpcPlacement")
     const ipcNote=findChild(placement,"abyssIpcPlacementHelpNote")
     check(!!ipcNote && !ipcNote.visible,
         "compact IPC explanatory text should not occupy layout space")
     check(sharedOutput.visible && outputCheckbox.visible,
         "shared output scope should stay visible in IPC")
     check(chooser.count===7,"quick IPC selector exposes popup relocation")
     check(outputPicker.count===2,"IPC scope selector must offer current and all outputs")
     check(outputPicker.currentIndex===(editor.outputOnly?1:0),
         "IPC scope picker not synced with checkbox")
     check(!placement.showKindSelector && !placement.showOutputSelector
         && placement.compactIpcEditor,"redundant IPC position dropdowns are not hidden")
     check(placement.outputName===(editor.outputOnly?editor.outputName:""),
         "IPC placement scope differs from the header")
     editor.outputOnly=false;wait(60)
     check(outputPicker.currentIndex===0 && placement.outputName==="",
         "global IPC scope did not reach placement")
     editor.outputOnly=true;wait(60)
     check(outputPicker.currentIndex===1 && placement.outputName===editor.outputName,
         "output-local IPC scope not restored")
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
