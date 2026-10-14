#!/usr/bin/env python3
"""Composed field/editor and real slide/reversal across edges, sizes and routes."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(os.environ.get("HADALIS_DASHBOARD_TEST_ROOT",str(Path(__file__).resolve().parents[1]))).resolve()
CAPTURE=Path(os.environ["ALIS_DASHBOARD_FIELD_CAPTURE_DIR"]).resolve() if os.environ.get("ALIS_DASHBOARD_FIELD_CAPTURE_DIR") else None
if CAPTURE:CAPTURE.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix="hadalis-dashboard-editor-field-") as name:
 folder=Path(name)
 for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:(folder/entry).symlink_to(ROOT/entry)
 (folder/"shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.services
import qs.modules.abyss
import qs.modules.abyss.looks
ShellRoot {
 id:root
 property bool shown:false
 property string route:"Dashboard"
 property string edge:"bottom"
 property real surfaceWidth:1280
 property real surfaceHeight:900
 property string caseName:""
 property int capturedFrames:0
 property int motionSamples:0
 property string captureDirectory:Quickshell.env("ALIS_DASHBOARD_FIELD_CAPTURE_DIR")
 property string savedCase:""
 property int savedCaseFrames:0
 property int savedFrames:0
 property var slideTrace:[]
 property var observedPopup:null
 property var observedCanvas:null
 property var layoutTrace:[]
 property double slideStarted:0
 property string slidePhase:""
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;implicitWidth:1280;implicitHeight:900;color:"#111820"
  // A compositor may retain the native window size. Exercise the allocated
  // field dimensions explicitly instead of treating a resize request as proof.
  Item {
  id:surface;width:root.surfaceWidth;height:root.surfaceHeight
  AbyssSurfaceController {id:liquid;outputWidth:surface.width;outputHeight:surface.height;presentationItem:surface;edgeInsets:({top:16,left:16,right:16,bottom:16})}
  AbyssField {id:field;anchors.fill:parent;records:liquid.records;waveTexture:liquid.waves.texture;edgeInsets:liquid.edgeInsets}
  AbyssBodyHost {
   id:body;anchors.fill:parent;controller:liquid;identity:"dashboard";edge:root.edge
   open:root.shown;animatePresentation:false;animatePlacementChanges:false
   stableContentSize:true;largeSurface:true;edgeInsets:liquid.edgeInsets
   span: ["top","bottom"].includes(edge) ? width*.76 : height*.70
   depth:["top","bottom"].includes(edge) ? height*.70 : width*.76
   along:((["top","bottom"].includes(edge)?width:height)-span)/2
   source:Qt.resolvedUrl("modules/abyss/content/Abyss"+root.route+"Content.qml")
  }
  }
 }
 Connections {
  target:root.observedCanvas
  function onWidthChanged(){test.recordLayout("width-signal")}
  function onHeightChanged(){test.recordLayout("height-signal")}
 }
 Connections {
  target:root.observedPopup
  function onRevealProgressChanged(){
   root.slideTrace.push({phase:"signal/"+root.slidePhase,ms:Date.now()-root.slideStarted,p:root.observedPopup.revealProgress,requested:root.observedPopup.revealRequested,animations:Appearance.animationsEnabled})
   if(root.slideTrace.length>80)root.slideTrace.shift()
  }
 }
 TestCase {
  id:test;when:false;optional:true
  SignalSpy {id:clickSpy;signalName:"clicked"}
  function recordLayout(phase){
   const canvas=root.observedCanvas
   const parents=[]
   let item=canvas
   for(let i=0;item && i<9;i++,item=item.parent)
    parents.push({type:String(item),width:item.width,height:item.height,implicitWidth:item.implicitWidth,implicitHeight:item.implicitHeight})
   root.layoutTrace.push({phase,ms:Date.now(),caseName:root.caseName,editing:canvas?.editMode,
    bodyProgress:body.progress,placement:body.placement,targetContent:body.targetRecord?.content,
    requestedAlong:body.requestedAlong,minimumInward:body.minimumInward,parents})
   if(root.layoutTrace.length>100)root.layoutTrace.shift()
  }
  function check(v,m){if(!v){recordLayout("failure");console.info("DASHBOARD_LAYOUT_TRACE",JSON.stringify(root.layoutTrace));throw new Error(root.caseName+": "+m)}}
  function find(item,p){if(p(item))return item;for(const c of item.children??[]){const x=find(c,p);if(x)return x}return null}
  function flushFrame(){
   const before=root.capturedFrames
   check(surface.grabToImage(result=>{
    root.capturedFrames++
    if(root.savedCase!==root.caseName){root.savedCase=root.caseName;root.savedCaseFrames=0}
    const p=root.observedPopup?.revealProgress ?? 0
    if(root.captureDirectory.length && root.slidePhase.length && p>0 && p<1 && root.savedCaseFrames<3){
     const path=root.captureDirectory+"/slide-"+root.savedFrames+".png"
     check(result.saveToFile(path),"could not save captured slide frame")
     root.savedCaseFrames++;root.savedFrames++
     console.info("SLIDE_IMAGE",root.caseName,root.slidePhase,p,path)
    }
   }),"editor field capture refused")
   tryVerify(()=>root.capturedFrames>before,3000)
  }
  function sampleSlide(popup,canvas,dimensions){
   const toolbar=popup.children.find(i=>i.canvasController===canvas)
   check(toolbar?.visible,"toolbar content vanished during slide")
   check(canvas.width===dimensions[0] && canvas.height===dimensions[1],"slide resized widget canvas")
   check(toolbar.width===popup.width && toolbar.height===popup.height,"slide scaled/repacked toolbar")
   check(popup.opacity===1 && toolbar.opacity===1 && popup.scale===1 && toolbar.scale===1,"toolbar must translate without fade/scale")
   const top=popup.y+toolbar.y,bottom=popup.y+popup.height
   check(top>=popup.y-.1 && top<=bottom+.1,"toolbar moved outside reveal viewport")
   check(popup.clip && toolbar.y>=0,"toolbar did not slide under its attachment")
   const participant=liquid.participants.dashboardEditor
   check(Math.abs(participant.geometry.content.y-top)<.1,"field detached from sliding controls")
   check(Math.abs(participant.geometry.content.height-(bottom-top))<.1,"field did not follow clipped content")
   if(canvas.editMode){
    check(Math.abs(participant.inputBounds.y-top)<.1 && Math.abs(participant.inputBounds.height-(bottom-top))<.1,"input not limited to visible controls")
   }else check(participant.inputBounds.width===0 && !popup.enabled,"closing editor retained input")
   root.motionSamples++
  }
  function advanceSlide(popup,canvas,dimensions,opening,partial){
   root.observedPopup=popup;root.slideStarted=Date.now();root.slidePhase=(opening?"open":"close")+(partial?"-partial":"-full");root.slideTrace=[]
   const deadline=root.slideStarted+3000
   console.info("SLIDE_PHASE",root.caseName,root.slidePhase,popup.revealProgress)
   let previous=popup.revealProgress,intermediate=0
   while(Date.now()<deadline){
    root.slideTrace.push({phase:"before-grab",ms:Date.now()-root.slideStarted,p:popup.revealProgress,requested:popup.revealRequested,animations:Appearance.animationsEnabled,edit:canvas.editMode,body:body.progress,captures:root.capturedFrames})
    if(root.slideTrace.length>80)root.slideTrace.shift()
    flushFrame()
    const progress=popup.revealProgress
    root.slideTrace.push({phase:"after-grab",ms:Date.now()-root.slideStarted,p:progress,captures:root.capturedFrames})
    if(root.slideTrace.length>80)root.slideTrace.shift()
    check(opening?progress>=previous-.001:progress<=previous+.001,"slide reversed unexpectedly")
    if(progress>0 && progress<1){sampleSlide(popup,canvas,dimensions);intermediate++}
    previous=progress
    if(partial && progress>=.20 && progress<.85)return progress
    if(!partial && progress===(opening?1:0)){
     check(intermediate>0,"toolbar appeared/disappeared without intermediate movement "+JSON.stringify(root.slideTrace))
     return progress
    }
    wait(8)
   }
   throw new Error(root.caseName+": toolbar slide did not reach "+(partial?"partial reveal":opening?"open":"closed")+" "+JSON.stringify(root.slideTrace))
  }
  function checkSlide(popup,canvas,dimensions){
   Config.setNestedValue("performance.reduceAnimations",false)
   canvas.beginEditMode()
   const partial=advanceSlide(popup,canvas,dimensions,true,true)
   const resting=[popup.x,popup.y,popup.width,popup.height]
   canvas.cancelEditMode()
   check(Math.abs(popup.revealProgress-partial)<.001,"close snapped reveal progress")
   check(JSON.stringify([popup.x,popup.y,popup.width,popup.height])===JSON.stringify(resting),"close lost retained toolbar footprint: "+JSON.stringify([resting,[popup.x,popup.y,popup.width,popup.height]]))
   check(liquid.participants.dashboardEditor.inputBounds.width===0,"Cancel did not immediately release input")
   flushFrame();sampleSlide(popup,canvas,dimensions)
   const reversing=popup.revealProgress
   check(reversing>0 && reversing<=partial,"toolbar vanished before reversal")
   canvas.beginEditMode()
   check(Math.abs(popup.revealProgress-reversing)<.001,"reopen snapped reveal progress")
   advanceSlide(popup,canvas,dimensions,true,false)
   check(popup.visible && popup.revealProgress===1,"toolbar failed to finish entry")
   sampleSlide(popup,canvas,dimensions)
   canvas.cancelEditMode()
   check(liquid.participants.dashboardEditor.inputBounds.width===0,"exit retained editor input")
   advanceSlide(popup,canvas,dimensions,false,false)
   check(!popup.visible && liquid.participants.dashboardEditor.geometry===null,"closed editor retained paint")
   Config.setNestedValue("performance.reduceAnimations",true)
   canvas.beginEditMode();check(popup.revealProgress===1,"reduced motion must open immediately")
   canvas.cancelEditMode();check(popup.revealProgress===0,"reduced motion must close immediately")
  }
  function clickAction(popup,name){
   const button=findChild(popup,name)
   check(button?.visible && button.enabled,"action unavailable: "+name)
   // An unfocused nested compositor can throttle onscreen frame callbacks.
   // Render this owned field into an image to flush the real scene/layout
   // before mapping input, without taking focus from the owner's application.
   if(name==="dashboardEditDone"){
    const before=root.capturedFrames
    check(surface.grabToImage(result=>{root.capturedFrames++}),"editor field capture refused")
    tryVerify(()=>root.capturedFrames>before,3000)
   }
   check(waitForPolish(button.parent,1500),"pending editor action row: "+name)
   clickSpy.target=button;clickSpy.clear()
   mouseClick(button)
   tryCompare(clickSpy,"count",1,1000)
  }
  function runChecks(){try{
   console.info("CHECKS_START");tryCompare(Config,"ready",true,4000);console.info("CONFIG_READY")
   Config.setNestedValues({"performance.reduceAnimations":true,"dashboard.showHeader":false})
   GlobalStates.deferredPanelsReady=true;GlobalStates.overviewMode="dashboard"
   tryCompare(field,"ready",true,4000)
   let count=0
   for(const size of [[1280,900],[720,650]])for(const route of ["Dashboard","Overview"])for(const edge of ["top","right","bottom","left"]){
    root.caseName=JSON.stringify([size,route,edge]);console.info("CASE_START",root.caseName)
    root.shown=false;wait(100);root.surfaceWidth=size[0];root.surfaceHeight=size[1];root.route=route;root.edge=edge;root.shown=true
    check(surface.width===size[0] && surface.height===size[1],"field allocation did not resize")
    tryVerify(()=>body.contentItem.item!==null,5000)
    const canvas=find(body.contentItem.item,i=>typeof i.beginResize==="function")
    check(canvas!==null,"missing canvas "+route)
    root.observedCanvas=canvas;root.layoutTrace=[];recordLayout("loaded")
    Config.setNestedValue("dashboard.canvas.widgets",canvas.defaultEntries().map(p=>Object.assign({},p,{visible:p.id==="notes",x:.15,y:.15,w:.3,h:.35})))
    wait(80)
    // Empty placeholders and long drafts must not drive card width or lose
    // vertical scrolling as the real hosts resize/reload the notes editor.
    tryCompare(Notepad,"ready",true,4000)
    const note=find(canvas,i=>typeof i.placeholderText==="string" && typeof i.cursorPosition==="number" && typeof i.wrapMode==="number")
    check(note!==null,"notes editor missing")
    const draft=note.text
    note.text="";wait(40)
    check(note.placeholderText.length>0,"empty notes lost their placeholder")
    note.text=("A wrapped note remains editable throughout Dashboard resizing. ").repeat(12)+"\n"+("A separate draft line.\n").repeat(60)
    wait(60)
    let viewport=note.parent
    while(viewport && typeof viewport.contentY!=="number")viewport=viewport.parent
    check(viewport!==null && viewport.contentHeight>viewport.height,"long notes cannot scroll")
    check(viewport.contentHeight>=note.contentHeight && viewport.contentWidth<=viewport.width+1,"notes have clipped text or a horizontal scroll extent")
    viewport.contentY=Math.max(0,viewport.contentHeight-viewport.height);wait(20)
    check(viewport.contentY+viewport.height>=note.contentHeight,"last note line is unreachable")
    note.text=draft;wait(40)
    const dimensions=[canvas.width,canvas.height],saved=JSON.stringify(Config.options.dashboard.canvas.widgets)
    recordLayout("before-edit")
    canvas.beginEditMode();wait(120);flushFrame();recordLayout("after-edit")
    const popup=find(surface,i=>i.objectName==="abyssDashboardEditPopup" && i.canvasController===canvas)
    check(popup?.visible,"editor did not join output field")
    check(canvas.width===dimensions[0] && canvas.height===dimensions[1],"Edit resized widgets "+route+edge+" "+JSON.stringify({before:dimensions,after:[canvas.width,canvas.height]}))
    const origin=canvas.mapToItem(surface,0,0)
    check(popup.y+popup.height<=origin.y+1,"controls overlap widget canvas "+route+edge+" "+JSON.stringify([popup.y,popup.height,origin.y,body.targetRecord.content]))
    check(popup.x>=0 && popup.y>=0 && popup.x+popup.width<=surface.width && popup.y+popup.height<=surface.height,"editor outside output")
    check(liquid.participants.dashboardEditor?.inputBounds.width>0,"editor lacks native field input")
    check(liquid.records.some(r=>r.content.width===popup.width && r.content.height===popup.height),"editor lacks shared field paint")
    canvas.setWidgetVisible("notes",false);wait(50)
    check(canvas.canUndo && canvas.visibleIds.length===0 && popup.visible,"empty dashboard lost controls")
    clickAction(popup,"dashboardEditUndo");wait(50)
    check(canvas.visibleIds.includes("notes"),"Undo did not restore module")
    canvas.setWidgetVisible("notes",false);clickAction(popup,"dashboardEditCancel");wait(50)
    check(!canvas.editMode && JSON.stringify(Config.options.dashboard.canvas.widgets)===saved,"Cancel changed saved layout")
    canvas.beginEditMode();wait(80);canvas.setWidgetVisible("notes",false);clickAction(popup,"dashboardEditDone");wait(80)
    check(!canvas.editMode && !canvas.visibleIds.includes("notes"),"Done did not save layout")
    check(!popup.visible && liquid.participants.dashboardEditor?.inputBounds.width===0,"editor did not release input")
    checkSlide(popup,canvas,dimensions);console.info("CASE_DONE",root.caseName)
    count++
   }
   console.info("DASHBOARD_FIELD_PASS",count,"composed routes/edges/sizes: dimensions above-field Add Undo Cancel Done input-release",root.motionSamples,"native slide/reversal samples")
  }catch(e){console.error("DASHBOARD_FIELD_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder,capture_focus=CAPTURE is not None) as env:
  if env is None:print("SKIP: Dashboard field requires private Niri");raise SystemExit(0)
  config=folder/"config/illogical-impulse";config.mkdir(parents=True,exist_ok=True)
  value=json.loads((ROOT/"defaults/config.json").read_text());value["panelFamily"]="abyss";value["abyss"]["companion"]["enabled"]=False
  (config/"config.json").write_text(json.dumps(value));env["QSG_RHI_BACKEND"]="opengl"
  if CAPTURE:env["ALIS_DASHBOARD_FIELD_CAPTURE_DIR"]=str(CAPTURE)
  result=run_qs(folder,env,timeout=80)
  if CAPTURE:
   (CAPTURE/"native.log").write_text(result.stdout)
   (CAPTURE/"process.json").write_text(json.dumps({"exit_code":result.returncode,"captures":len(list(CAPTURE.glob("slide-*.png")))},indent=2)+"\n")
   focus=folder/"native-test-capture-focus.json"
   if focus.exists():(CAPTURE/"focus.json").write_bytes(focus.read_bytes())
  if result.returncode or "DASHBOARD_FIELD_PASS" not in result.stdout or any(s in result.stdout for s in ["DASHBOARD_FIELD_FAIL","ReferenceError:","TypeError:","Binding loop","Failed to load configuration"]):
   print("Dashboard native process exit:",result.returncode);print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if "DASHBOARD_FIELD_PASS" in line:print(line)
  print("DASHBOARD_FIELD_PASS 16 composed route/edge/size cases; stable workspace; native Undo Cancel Done; full-size slide/reversal/reduced motion; field paint/input")
