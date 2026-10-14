
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
 property var snapshots:[]
 property var swaps:[]
 property var grabs:[]
 property var signals:[]
 property bool pending:false
 property var canvas:null
 property var popup:null
 property var dimensions:[]
 property int images:0
 function find(item,predicate){
  if(predicate(item))return item
  for(const child of item.children??[]){const found=find(child,predicate);if(found)return found}
  return null
 }
 function changePhase(value){phase=value;phaseStart=Date.now();snapshots.push({event:value,ms:Date.now()-epoch,p:popup?.revealProgress??null,fieldReady:field.ready,canvas:canvas?[canvas.width,canvas.height]:null})}
 function finish(error){console.info("COMPOSED_ASYNC_RESULT",JSON.stringify({error,phase,dimensions,snapshots,swaps,grabs,signals,images,pending,fieldReady:field.ready}));Qt.quit()}
 Connections {
  target:surface.Window.window
  function onFrameSwapped(){if(root.phase!=="boot")root.swaps.push({ms:Date.now()-root.epoch,phase:root.phase,p:root.popup?.revealProgress??null})}
 }
 Connections {
  target:root.popup
  function onRevealProgressChanged(){root.signals.push({ms:Date.now()-root.epoch,phase:root.phase,p:root.popup.revealProgress})}
 }
 Timer {
  interval:8;repeat:true;running:true
  onTriggered:{try{
   if(root.phase==="boot"){
    if(!Config.ready)return
    Config.setNestedValues({"performance.reduceAnimations":true,"dashboard.showHeader":false})
    GlobalStates.deferredPanelsReady=true;GlobalStates.overviewMode="dashboard"
    root.shown=true;root.changePhase("loading");return
   }
   if(root.phase==="loading"){
    if(!body.ready||!field.ready||!Notepad.ready)return
    root.canvas=root.find(body.contentItem.item,i=>typeof i.beginResize==="function")
    if(!root.canvas)throw new Error("Actual canvas missing")
    Config.setNestedValue("dashboard.canvas.widgets",root.canvas.defaultEntries().map(p=>Object.assign({},p,{visible:p.id==="notes",x:.15,y:.15,w:.3,h:.35})))
    root.changePhase("settling");return
   }
   if(root.phase==="settling"){
    if(Date.now()-root.phaseStart<300)return
    const note=root.find(root.canvas,i=>i.objectName==="quickNotesSourceEditor")
    if(!note)throw new Error("Actual Notes source missing")
    const shared=root.find(root.canvas,i=>i.objectName==="quickNotesSharedDashboardView")
    shared.focusEditor()
    note.text=("A wrapped note remains editable throughout Dashboard resizing. ").repeat(12)+"\n"+("A separate draft line.\n").repeat(60)
    root.changePhase("notes");return
   }
   if(root.phase==="notes"){
    if(Date.now()-root.phaseStart<300)return
    root.find(root.canvas,i=>i.objectName==="quickNotesSharedDashboardView").releaseEditorFocus()
    root.dimensions=[root.canvas.width,root.canvas.height]
    root.popup=root.find(surface,i=>i.objectName==="abyssDashboardEditPopup"&&i.canvasController===root.canvas)
    if(!root.popup)throw new Error("Actual editor missing")
    Config.setNestedValue("performance.reduceAnimations",false)
    root.changePhase("open");root.canvas.beginEditMode();return
   }
   if(root.phase==="open"&&Date.now()-root.phaseStart>1800){root.changePhase("close");root.canvas.cancelEditMode()}
   if(root.phase==="close"&&Date.now()-root.phaseStart>1800){root.finish(null);return}
   if(root.canvas.width!==root.dimensions[0]||root.canvas.height!==root.dimensions[1])throw new Error("Editor changed canvas dimensions")
   if(!root.pending){
    root.pending=true
    const requested=Date.now()-root.epoch,requestP=root.popup.revealProgress,requestPhase=root.phase
    if(!surface.grabToImage(result=>{
     const actual=root.popup?.revealProgress??null
     const record={requested,requestPhase,requestP,ms:Date.now()-root.epoch,phase:root.phase,p:actual,width:result.image.width,height:result.image.height}
     if(actual>0&&actual<1&&root.images<8){
      const path=Quickshell.env("COMPOSED_CAPTURE")+"/partial-"+root.images+".png"
      record.saved=result.saveToFile(path);root.images++
     }
     root.grabs.push(record);root.pending=false
    }))throw new Error("Composed capture rejected")
   }
  }catch(error){root.finish(String(error))}}
 }
 Timer {interval:12000;running:true;onTriggered:root.finish("Diagnostic deadline")}
}
