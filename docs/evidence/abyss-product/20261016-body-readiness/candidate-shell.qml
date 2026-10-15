
import QtQuick
import QtQuick.Window
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.looks
ShellRoot {
 id:root
 property bool shown:false
 property bool retainWarm:true
 property string route:"Dashboard"
 property string edge:"bottom"
 property string phase:"boot"
 property double phaseStart:0
 property int caseIndex:-1
 property var cases:[]
 property var results:[]
 property var current:null
 property var heldItem:null
 property var heldCanvas:null
 property var fullSize:[]
 property int loadCount:0
 property int expiredLoadCount:0
 property int partialSamples:0
 property int partialSwaps:0
 property var trace:[]
 property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 function check(value,label){checks++;if(!value)throw new Error(label)}
 function sample(event){
  if(trace.length<16000)trace.push({event,ms:Date.now(),caseIndex,phase,ready:body.ready,open:shown,p:body.progress,inputWidth:body.inputBounds.width})
  if(body.progress>.001&&body.progress<.999){if(event==="progress")partialSamples++;if(event==="swap")partialSwaps++}
 }
 function phaseTo(value){phase=value;phaseStart=Date.now();partialSamples=0;partialSwaps=0;sample("phase")}
 function finish(error){console.info(error?"BODY_REVEAL_FAIL":"BODY_REVEAL_PASS",JSON.stringify({error,checks,completed:results.length,caseIndex,phase,results,trace}));Qt.quit()}
 function find(item,predicate){if(!item)return null;if(predicate(item))return item;for(const child of item.children??[]){const found=find(child,predicate);if(found)return found}return null}
 function beginCase(){
  caseIndex++
  if(caseIndex>=cases.length){finish(null);return}
  current={route:cases[caseIndex].route,edge:cases[caseIndex].edge,reduced:cases[caseIndex].reduced,openings:[]}
  route=current.route;edge=current.edge;retainWarm=true
  heldItem=null;heldCanvas=null;fullSize=[]
  GlobalStates.deferredPanelsReady=false
  Config.setNestedValue("performance.reduceAnimations",current.reduced)
  check(!body.ready&&body.contentItem.item===null,"case did not begin unloaded")
  phaseTo("delayed-ready");shown=true;sample("open-deferred")
 }
 function openingDuration(){const factor=1+Math.min(.5,Math.sqrt(body.mass)*.1);return Math.round(AbyssStyle.motionNormal*factor)+Math.round(AbyssStyle.motionSettle*factor)+80}
 function closingDuration(){return Math.round(AbyssStyle.motionNormal*(1+Math.min(.5,Math.sqrt(body.mass)*.1)))+40}
 function captureContent(){
  if(!body.ready||heldItem)return
  heldItem=body.contentItem.item
  heldCanvas=find(heldItem,item=>typeof item.beginEditMode==="function")
  check(heldCanvas!==null,"real Dashboard/Overview canvas missing")
  fullSize=[body.contentItem.width,body.contentItem.height]
  check(fullSize[0]>0&&fullSize[1]>0,"ready content has no full-size canvas")
 }
 function checkStable(){
  if(!heldItem||!body.ready)return
  check(body.contentItem.item===heldItem,"reveal replaced a live content tree")
  check(body.contentItem.width===fullSize[0]&&body.contentItem.height===fullSize[1],"reveal resized content")
  check(body.contentItem.width===body.targetRecord.content.width&&body.contentItem.height===body.targetRecord.content.height,"content lost resting target dimensions")
 }
 function noUnreadyPlate(){
  check(!body.ready&&body.contentItem.item===null,"deferred gate did not delay content")
  check(body.inputBounds.width===0&&body.inputBounds.height===0,"unready content accepted input")
  check(body.progress===0,"EMPTY_PLATE_BEFORE_CONTENT_READY")
 }
 function openingDone(){
  captureContent();checkStable()
  if(Date.now()-phaseStart<openingDuration())return false
  check(body.ready&&Math.abs(body.progress-1)<.000001,"ready reveal did not settle")
  check(body.inputBounds.width>0&&body.inputBounds.height>0,"ready open body has no input")
  if(current.reduced){check(partialSamples===0&&partialSwaps===0,"reduced motion retained intermediate reveal")}
  else{check(partialSamples>0,"normal reveal skipped actual availability Behavior");check(partialSwaps>0,"normal reveal had no actual intermediate window swap")}
  current.openings.push({phase,partialSamples,partialSwaps})
  if(route==="Overview")check(heldItem.heldLease!=="","open Overview lost sorting lease")
  return true
 }
 function closedDone(){
  check(body.inputBounds.width===0&&body.inputBounds.height===0,"semantic close retained input")
  checkStable()
  if(Date.now()-phaseStart<closingDuration())return false
  check(body.progress===0&&!body.visualResident,"close did not finish")
  check(body.ready&&body.contentItem.item===heldItem&&body.warmHeld,"warm close lost retained identity")
  check(!heldItem.visible,"warm closed content retained paint")
  check(ResourceUsage._persistentConsumers===0,"hidden system widget retained sampling")
  if(route==="Overview")check(heldItem.heldLease==="","hidden Overview retained sorting lease")
  return true
 }
 FloatingWindow {
  id:window;visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {id:scene;width:1000;height:740
   AbyssSurfaceController {id:liquid;outputWidth:scene.width;outputHeight:scene.height;presentationItem:scene}
   AbyssField {id:field;anchors.fill:parent;records:liquid.records;waveTexture:liquid.waves.texture;edgeInsets:liquid.edgeInsets}
   AbyssBodyHost {
    id:body;anchors.fill:parent;identity:"dashboard";controller:liquid;edge:root.edge
    open:root.shown;animatePresentation:true;animatePlacementChanges:false
    stableContentSize:true;warmContent:root.retainWarm;largeSurface:true
    span:["top","bottom"].includes(edge)?720:540
    depth:["top","bottom"].includes(edge)?540:720
    along:((["top","bottom"].includes(edge)?width:height)-span)/2
    source:Qt.resolvedUrl("modules/abyss/content/Abyss"+root.route+"Content.qml")
   }
  }
 }
 Connections {target:body;function onProgressChanged(){root.sample("progress")}function onReadyChanged(){if(body.ready)root.loadCount++;root.sample("ready")}}
 Connections {target:scene.Window.window;function onFrameSwapped(){root.sample("swap")}}
 Timer {
  interval:8;repeat:true;running:true
  onTriggered:{try{
   if(root.phase==="boot"){
    if(!Config.ready||!field.ready)return
    GlobalStates.overviewMode="dashboard"
    GlobalStates.deferredPanelsReady=false
    root.check(!body.ready,"closed body eagerly loaded")
    for(const reduced of [false,true])for(const route of ["Dashboard","Overview"])for(const edge of ["top","right","bottom","left"])root.cases.push({route,edge,reduced})
    root.beginCase()
    return
   }
   const age=Date.now()-root.phaseStart
   root.check(age<8000,"functional phase deadline: "+root.phase)
   if(root.phase==="delayed-ready"){
    if(age<180)return
    root.noUnreadyPlate();root.shown=false;root.phaseTo("delayed-cancel");return
   }
   if(root.phase==="delayed-cancel"){
    if(age<40)return
    root.noUnreadyPlate();GlobalStates.deferredPanelsReady=true;root.phaseTo("cancelled-ready");return
   }
   if(root.phase==="cancelled-ready"){
    if(age<140)return
    root.noUnreadyPlate();root.check(!root.shown,"cancelled deferred body reopened")
    root.phaseTo("opening");root.shown=true;return
   }
   if(["opening","reversed-opening","warm-opening","expired-opening"].includes(root.phase)){
    if(!root.openingDone())return
    if(root.phase==="opening"){root.shown=false;root.phaseTo("reverse-close");return}
    if(root.phase==="reversed-opening"){root.shown=false;root.phaseTo("warm-close");return}
    if(root.phase==="warm-opening"){root.shown=false;root.phaseTo("expiry-close");return}
    root.check(root.loadCount===root.expiredLoadCount+1,"expired reopen failed to load one new tree")
    root.shown=false;root.phaseTo("final-close");return
   }
   if(root.phase==="reverse-close"){
    root.check(body.inputBounds.width===0,"close before reversal retained input");root.checkStable()
    if(root.current.reduced?age>=20:body.progress>.15&&body.progress<.8){
     const before=body.progress;root.phaseTo("reversed-opening");root.shown=true
     if(!root.current.reduced)root.check(Math.abs(body.progress-before)<.000001,"reversal snapped reveal progress")
    }
    return
   }
   if(["warm-close","expiry-close","final-close"].includes(root.phase)){
    if(!root.closedDone())return
    if(root.phase==="warm-close"){root.phaseTo("warm-hold");return}
    if(root.phase==="expiry-close"){root.phaseTo("expiry-hold");return}
    root.results.push(root.current);root.retainWarm=false;root.phaseTo("case-drain");return
   }
   if(root.phase==="warm-hold"){
    if(age<200)return
    root.check(body.ready&&body.contentItem.item===root.heldItem,"sub-1200ms warm hold rebuilt content")
    root.phaseTo("warm-opening");root.shown=true;return
   }
   if(root.phase==="expiry-hold"){
    if(age<1350)return
    root.check(!body.ready&&body.contentItem.item===null&&!body.warmHeld,"bounded warm expiry retained tree")
    root.heldItem=null;root.heldCanvas=null;root.fullSize=[];root.expiredLoadCount=root.loadCount
    GlobalStates.deferredPanelsReady=false;root.phaseTo("expired-delayed");root.shown=true;return
   }
   if(root.phase==="expired-delayed"){
    if(age<180)return
    root.noUnreadyPlate();root.phaseTo("expired-opening");GlobalStates.deferredPanelsReady=true;return
   }
   if(root.phase==="case-drain"){
    if(age<20)return
    root.check(!body.ready&&body.contentItem.item===null,"cleanup retained warm tree")
    root.beginCase()
   }
  }catch(error){root.finish(String(error))}}
 }
 Timer {interval:180000;running:true;onTriggered:root.finish("functional deadline")}
}
