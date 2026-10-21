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
     const modeHeader=item("abyssEditorModeHeader")
     const tabs=control("abyssEditorModeTabs")
     const title=control("abyssEditorTitle")
     const actions=control("abyssEditorHeaderActions")
     const headerOrigin=(item)=>item.mapToItem(scroll.contentItem,0,0)
     if(!editor.toolbarOnHorizontalEdge && scroll.width>=205*scale) {
      check(Math.abs(centerY(title,scroll.contentItem)-centerY(actions,scroll.contentItem))<1.5,
        "side title and Undo/Reset/Cancel/Done must share the first line")
      check(headerOrigin(title).x+title.width<=headerOrigin(actions).x+1,
        "side editor title overlaps header actions")
      check(done.width<=26*scale+1,"side header actions did not shrink")
     }
     const scope=control("abyssEditorOutputScope")
     const sharedOutput=control("abyssEditorIpcOutput")
     const outputCheckbox=control("abyssEditorOutputOnly")
     const origin=(item)=>item.mapToItem(scroll.contentItem,0,0)
     if(modeHeader.columns===2) {
      // GridLayout centers controls of different heights within the row.
      // Comparing their top edges rejects the intended 28px/30px pairing.
      check(Math.abs(centerY(tabs,scroll.contentItem)-centerY(scope,scroll.contentItem))<1,
          "tabs and output scope are not centered on the same row")
      check(origin(tabs).x+tabs.width<=origin(scope).x+.5,
          "tabs overlap the output scope")
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
      const actions=item("abyssModuleHeaderActions")
      const end=actions.mapToItem(scroll.contentItem,actions.width,0).x
      check(middle.x-end<=19*scale,
          "Module column still has excess blank space before the divider")
      check(moduleColumn.width <= actions.implicitWidth+1,
          "Module column must stop near its actual action-row width")
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
     const moduleHeader=item("abyssModuleHeaderActions")
     const selectionActions=control("abyssModuleSelectionActions")
     const pickerPoint=inScroll(modulePicker),selectionPoint=inScroll(selectionActions)
     if(moduleHeader.columns===2) {
      check(Math.abs(centerY(modulePicker,scroll.contentItem)-centerY(selectionActions,scroll.contentItem))<1.5,
        "Module picker and selection actions do not share the wide header row")
      check(pickerPoint.x+modulePicker.width<=selectionPoint.x+.5,
        "Module picker overlaps the selection actions")
     } else {
      check(selectionPoint.y>=pickerPoint.y+modulePicker.height-1,
        "narrow Module selection actions should stack below the picker")
     }
     sameRow("abyssModulePositionLock","abyssModuleJoinCorner","Module selection")
     sameRow("abyssEditingEdgeDropdown","abyssJoinNearbyModules","Edge header")
     sameRow("abyssModuleRoundingAction","abyssModuleRounding","Rounding")
     const round0=control("abyssRoundZeroCorners")
     check(round0.checkable && round0.width<=editor.editorActionSize+.6,
           "Round at 0px should be an icon toggle")
     check(control("abyssModuleRoundingAction").checkable,
           "Inherited module rounding should be a toggle")
     if(editor.toolbarOnHorizontalEdge && scene.width>720*scale)
      check(body.span < 650*scale,
        "Horizontal Module toolbar retains avoidable blank span")
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
     check(scaleSlider.width>=75*scale-.5 && scaleSlider.width<=edgeColumn.width+1,
         "scale slider is not bounded by its Edge column")
     // Check physical endpoints, not hardcoded widths. Lower rows stretch to
     // the last Module action and last Edge value label independently.
     const rightIn=(target,column)=>target.mapToItem(column,target.width,0).x
     const alignPicker=control("abyssModulePositionDropdown")
     const moduleRound=control("abyssModuleRounding")
     const moduleSize=control("abyssModuleCustomSizeSlider")
     const moduleRight=moduleColumn.controlsSpan
     check(Math.abs(rightIn(alignPicker,moduleColumn)-moduleRight)<2*scale,
         "Module position dropdown misses the module controls endpoint")
     check(Math.abs(rightIn(moduleRound,moduleColumn)-moduleRight)<2*scale
         && Math.abs(rightIn(moduleSize,moduleColumn)-moduleRight)<2*scale,
         "Module sliders do not end at the module controls endpoint")
     const edgeWidthSlider=control("abyssEdgeWidthSlider")
     const edgeGapSlider=control("abyssEdgeGapSlider")
     const edgeSizeSlider=control("abyssEdgeSizeSlider")
     check(Math.abs(rightIn(edgeWidthSlider,edgeColumn)-edgeColumn.width)<2*scale
         && Math.abs(rightIn(scaleSlider,edgeColumn)-edgeColumn.width)<2*scale,
         "bottom Edge slider values do not share the column's right boundary")
     const paired=item("abyssEdgeGapAndSizeRow")
     const firstEndpoint=paired.columns===2
         ? (edgeColumn.width-paired.columnSpacing)/2 : edgeColumn.width
     check(Math.abs(rightIn(edgeGapSlider,edgeColumn)-firstEndpoint)<2*scale,
         "first Edge slider does not end on its balanced column boundary")
     check(Math.abs(rightIn(edgeSizeSlider,edgeColumn)-edgeColumn.width)<2*scale,
         "second Edge slider does not align with bottom value labels")
     if(edgeColumn.width>=170*scale)
       check(edgePicker.width>=100*scale-.5 && edgePicker.width<=108*scale+.5,
           "Edge selector should be slightly wider than its former 88px width")
     const header=item("abyssModuleHeaderActions")
     if(grouped.columns===3 && moduleColumn.width>=header.implicitWidth-1) {
       const finalAction=control("abyssModuleJoinCorner")
       check(Math.abs(rightIn(finalAction,moduleColumn)-moduleRight)<2*scale,
           "Module fields do not end at the last Module action icon")
     }
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
     const selectorRow=item("abyssIpcSelectorsRow")
     const edgeCombo=control("abyssIpcEdgeDropdown")
     const alignCombo=control("abyssIpcAlignmentDropdown")
     const ipcJoin=control("abyssIpcJoinCornerToggle")
     check(ipcJoin.checkable,"IPC join nearby corner must be a toggle")
     if(!editor.toolbarOnHorizontalEdge) {
      check(Math.abs(centerY(ipcJoin,scroll.contentItem)-centerY(tabs,scroll.contentItem))<1.5,
        "side IPC Join icon must move next to the IPC tab")
      if(scroll.width>=200*scale)
       check(Math.abs(centerY(outputPicker,scroll.contentItem)-centerY(outputCheckbox,scroll.contentItem))<1.5,
         "side output dropdown and checkbox must share a line")
      for(const [item,limit] of [[chooser,placement.compactKindWidth],
          [edgeCombo,placement.compactEdgeWidth],
          [alignCombo,placement.compactAlignmentWidth]]) {
       check(Math.abs(item.width-editor.sideIpcSelectorWidth)<1.5
           && item.width<scroll.width-10*scale,
         "side IPC triggers do not share the bounded scope width")
       check(item.popup.width>=limit-1,
         "side IPC popup should reveal full choice labels")
      }
     }
     const coords=item=>item.mapToItem(scroll.contentItem,0,0)
     if(!placement.compactVertical) {
      check(selectorRow.columns===4,"IPC horizontal row must contain three dropdowns plus corner toggle")
      const controls=[chooser,edgeCombo,alignCombo]
      const ys=controls.map(c=>coords(c).y),widths=controls.map(c=>c.width)
      check(Math.max(...ys)-Math.min(...ys)<1.5,"IPC dropdowns not on one line")
      const fitted=[placement.compactKindWidth,placement.compactEdgeWidth,
                    placement.compactAlignmentWidth]
      for(let i=0;i<widths.length;i++)
       check(Math.abs(widths[i]-fitted[i])<1.5,
         "IPC dropdown is not content-sized "+JSON.stringify({actual:widths,expected:fitted}))
      check(placement.compactKindWidth>0
            && placement.compactEdgeWidth>0
            && placement.compactAlignmentWidth>0,
        "IPC selectors must measure their actual options")
      check(edgeCombo.model[0].label==="Source edge"
            && alignCombo.model[0].label==="Source position",
        "IPC inline labels should be shorter without changing their saved values")
      if(scene.width>720*scale)
       check(item("abyssEdgeEditorBody").span<600*scale,
         "IPC toolbar retains avoidable empty horizontal width")
      check(Math.abs(centerY(ipcJoin,scroll.contentItem)-centerY(chooser,scroll.contentItem))<1.5,
        "IPC corner toggle not centered with the dropdown row")
      check(coords(alignCombo).x+alignCombo.width<=coords(ipcJoin).x+.5,
        "IPC corner toggle overlaps the dropdown row")
      if(scene.width-48>=editor.ipcToolbarSpan)
       check(Math.abs(item("abyssEdgeEditorBody").span-editor.ipcToolbarSpan)<1.5,
         "IPC toolbar span includes avoidable blank width")
     } else check(selectorRow.columns===1,"narrow IPC selectors should stack")
     const moduleDraft=JSON.stringify(editor.draft)
     placement.change("edge","right");wait(60)
     check(editor.positionEdits.some(e=>e.kind===editor.previewKind && e.values?.edge==="right"),
         "IPC draft position edit did not register")
     click("abyssLayoutReset");wait(60)
     check(editor.positionEdits.some(e=>e.kind===editor.previewKind && e.values===null),
         "header reset did not reset selected IPC kind and output")
     check(JSON.stringify(editor.draft)===moduleDraft,"IPC reset should not touch Module draft")
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
