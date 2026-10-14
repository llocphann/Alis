
import QtQuick
import QtQuick.Window
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

 property string phase:"boot"
 property double epoch:Date.now()
 property double phaseStart:0
 property int caseIndex:0
 property int checks:0
 property var cases:[]
 property var results:[]
 property var current:null
 property var canvas:null
 property var popup:null
 property var dimensions:[]
 property bool pending:false
 property bool ending:false
 property real partial:0
 property real reversing:0
 property var resting:[]
 property int openingFrames:0
 property int closingFrames:0
 function check(value,message){checks++;if(!value)throw new Error(caseIndex+"/"+phase+": "+message)}
 function find(item,predicate){if(!item)return null;if(predicate(item))return item;for(const child of item.children??[]){const found=find(child,predicate);if(found)return found}return null}
 function phaseTo(value){phase=value;phaseStart=Date.now();current?.events.push({phase:value,ms:Date.now()-epoch,p:popup?.revealProgress??null,canvas:canvas?[canvas.width,canvas.height]:null})}
 function finish(error){if(ending)return;ending=true;console.info("COMPOSED_MOTION_RESULT",JSON.stringify({error,checks,completed:results.length,caseIndex,phase,results,current,api:GraphicsInfo.api}));Qt.quit()}
 function beginCase(){
  current={case:cases[caseIndex],events:[],swaps:[],captures:[],signals:[],openingImages:0,closingImages:0,nativeSize:[window.width,window.height],allocatedSize:cases[caseIndex].size}
  root.shown=false;root.canvas=null;root.popup=null
  const c=cases[caseIndex];surfaceWidth=c.size[0];surfaceHeight=c.size[1];route=c.route;edge=c.edge
  openingFrames=0;closingFrames=0;root.shown=true;phaseTo("loading")
 }
 function sample(){
  check(canvas.width===dimensions[0]&&canvas.height===dimensions[1],"editor resized live widget workspace")
  const toolbar=popup.children.find(i=>i.canvasController===canvas)
  check(toolbar?.visible,"live controls missing")
  check(toolbar.width===popup.width&&toolbar.height===popup.height,"controls scaled/repacked")
  check(popup.opacity===1&&toolbar.opacity===1&&popup.scale===1&&toolbar.scale===1,"controls faded/scaled")
  check(popup.clip&&toolbar.y>=0,"controls escaped reveal clip")
  const top=popup.y+toolbar.y,bottom=popup.y+popup.height,p=liquid.participants.dashboardEditor
  check(Math.abs(p.geometry.content.y-top)<.1&&Math.abs(p.geometry.content.height-(bottom-top))<.1,"paint detached from sliding controls")
  if(canvas.editMode)check(Math.abs(p.inputBounds.y-top)<.1&&Math.abs(p.inputBounds.height-(bottom-top))<.1,"input detached from visible controls")
  else check(p.inputBounds.width===0&&!popup.enabled,"closed editor retained input")
 }
 Connections {
  target:surface.Window.window
  function onFrameSwapped(){
   if(!root.current||!root.popup)return
   if(root.phase==="drain"){
    if(!root.pending&&Date.now()-root.phaseStart>100){root.caseIndex++;if(root.caseIndex>=root.cases.length){root.finish(null);return}root.beginCase()}
    return
   }
   const p=root.popup.revealProgress
   root.current.swaps.push({ms:Date.now()-root.epoch,phase:root.phase,p})
   if(p>0&&p<1){if(root.phase==="open-full")root.openingFrames++;if(root.phase==="close-full")root.closingFrames++}
  }
 }
 Connections {
  target:root.popup
  function onRevealProgressChanged(){root.current?.signals.push({ms:Date.now()-root.epoch,phase:root.phase,p:root.popup.revealProgress})}
 }
 function requestCapture(){
  if(pending)return
  pending=true
  const request={phase,ms:Date.now()-epoch,p:popup.revealProgress},entry=current,index=caseIndex
  check(surface.grabToImage(result=>{
   if(ending)return
   const p=popup?.revealProgress??null,kind=phase==="open-full"?"opening":phase==="close-full"?"closing":"other"
   const record={request,phase,ms:Date.now()-epoch,p}
   if(p>0&&p<1&&kind!=="other"&&entry[kind+"Images"]<2){
    const file=Quickshell.env("COMPOSED_CAPTURE")+"/case-"+index+"-"+kind+"-"+entry[kind+"Images"]+".png"
    record.saved=result.saveToFile(file);record.path=file;entry[kind+"Images"]++
   }
   entry.captures.push(record);pending=false
  }),"native field refused capture")
 }
 Timer {
  interval:8;repeat:true;running:true
  onTriggered:{try{
   if(root.ending)return
   if(root.phase==="boot"){
    if(!Config.ready)return
    Config.setNestedValues({"performance.reduceAnimations":true,"dashboard.showHeader":false})
    GlobalStates.deferredPanelsReady=true;GlobalStates.overviewMode="dashboard"
    root.cases.push({size:[720,650],route:"Dashboard",edge:"top"})
    root.beginCase();return
   }
   if(Date.now()-root.phaseStart>6500)throw new Error("phase deadline")
   if(root.phase==="loading"){
    if(!body.ready||!field.ready||!Notepad.ready)return
    root.canvas=root.find(body.contentItem.item,i=>typeof i.beginResize==="function")
    root.check(root.canvas!==null,"actual canvas missing")
    root.current.baselineScene=({workspace:root.canvas.workspace,body:body.targetRecord,toolbarRect:root.find(surface,i=>i.objectName==="abyssDashboardEditPopup")?.targetRect})
    Config.setNestedValue("dashboard.canvas.widgets",root.canvas.defaultEntries().map(p=>Object.assign({},p,{visible:p.id==="notes",x:.15,y:.15,w:.3,h:.35})))
    root.phaseTo("settling");return
   }
   if(root.phase==="settling"){
    if(Date.now()-root.phaseStart<250)return
    const note=root.find(root.canvas,i=>i.objectName==="quickNotesSourceEditor"),shared=root.find(root.canvas,i=>i.objectName==="quickNotesSharedDashboardView")
    root.check(!!note&&!!shared,"actual Notes source missing")
    shared.focusEditor();note.text=("A wrapped note remains editable throughout Dashboard resizing. ").repeat(12)+"\n"+("A separate draft line.\n").repeat(60)
    root.phaseTo("notes");return
   }
   if(root.phase==="notes"){
    if(Date.now()-root.phaseStart<250)return
    root.find(root.canvas,i=>i.objectName==="quickNotesSharedDashboardView").releaseEditorFocus()
    root.dimensions=[root.canvas.width,root.canvas.height]
    root.popup=root.find(surface,i=>i.objectName==="abyssDashboardEditPopup"&&i.canvasController===root.canvas)
    root.check(root.popup!==null,"actual editor missing")
    Config.setNestedValue("performance.reduceAnimations",false)
    root.phaseTo("open-partial");root.canvas.beginEditMode();return
   }
   if(root.phase==="drain"){
    if(!root.pending&&Date.now()-root.phaseStart>100){root.caseIndex++;if(root.caseIndex>=root.cases.length){root.finish(null);return}root.beginCase()}
    return
   }
   const p=root.popup.revealProgress
   if(p>0&&p<1)root.sample()
   if(root.phase==="open-partial"){
    root.requestCapture()
    if(p>=.25&&p<.85){
     root.partial=p;root.resting=[root.popup.x,root.popup.y,root.popup.width,root.popup.height]
     root.canvas.cancelEditMode();root.check(Math.abs(root.popup.revealProgress-p)<.001,"Cancel snapped progress")
     root.check(JSON.stringify([root.popup.x,root.popup.y,root.popup.width,root.popup.height])===JSON.stringify(root.resting),"exit lost retained footprint")
     root.check(liquid.participants.dashboardEditor.inputBounds.width===0,"Cancel retained input")
     root.phaseTo("reverse-close")
    }
    return
   }
   if(root.phase==="reverse-close"){
    root.requestCapture()
    if(Date.now()-root.phaseStart>24){
     root.check(p>0&&p<=root.partial,"reversal vanished/advanced")
     root.reversing=p;root.canvas.beginEditMode();root.check(Math.abs(root.popup.revealProgress-p)<.001,"reopen snapped progress");root.phaseTo("open-full")
    }
    return
   }
   if(root.phase==="open-full"){
    if(p===1&&!root.pending){
     root.check(root.openingFrames>0,"no real intermediate opening swap")
     root.check(root.current.openingImages>0,"no captured partial opening")
     root.sample();root.canvas.cancelEditMode();root.check(liquid.participants.dashboardEditor.inputBounds.width===0,"full exit retained input");root.phaseTo("close-full")
    }else root.requestCapture()
    return
   }
   if(root.phase==="close-full"){
    if(p===0&&!root.pending){
     root.check(root.closingFrames>0,"no real intermediate closing swap")
     root.check(root.current.closingImages>0,"no captured partial closing")
     root.check(!root.popup.visible&&liquid.participants.dashboardEditor.geometry===null,"closed editor retained paint")
     Config.setNestedValue("performance.reduceAnimations",true)
     root.canvas.beginEditMode();root.check(root.popup.revealProgress===1,"reduced-motion entry delayed")
     root.canvas.cancelEditMode();root.check(root.popup.revealProgress===0,"reduced-motion exit delayed")
     root.current.dimensions=root.dimensions;root.current.openingFrames=root.openingFrames;root.current.closingFrames=root.closingFrames
     root.results.push(root.current);root.shown=false;root.phaseTo("drain")
    }else root.requestCapture()
    return
   }
  }catch(error){root.finish(String(error))}}
 }
 Timer {interval:175000;running:true;onTriggered:root.finish("Total diagnostic deadline")}
}
