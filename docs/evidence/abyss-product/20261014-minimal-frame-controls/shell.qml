import QtQuick
import QtQuick.Window
import Quickshell
ShellRoot {
 id:root
 property double start:Date.now()
 property var swaps:[]
 property var grabs:[]
 property var states:[]
 property bool pending:false
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:640;implicitHeight:360;color:"#111820"
  Item {
   id:area;anchors.fill:parent
   Rectangle {id:card;width:96;height:80;y:140;color:"#78dce8";radius:16}
  }
 }
 NumberAnimation {id:motion;target:card;property:"x";from:40;to:450;duration:800;running:true;loops:Animation.Infinite}
 Connections {
  target:area.Window.window
  function onFrameSwapped(){root.swaps.push({ms:Date.now()-root.start,x:card.x})}
 }
 Timer {
  interval:16;running:true;repeat:true
  onTriggered:{
   root.states.push({ms:Date.now()-root.start,x:card.x})
   if(!root.pending){
    root.pending=true
    const requested=Date.now()-root.start,position=card.x
    const accepted=area.grabToImage(result=>{
     root.grabs.push({requested,requestX:position,ms:Date.now()-root.start,x:card.x,width:result.image.width,height:result.image.height})
     root.pending=false
    })
    if(!accepted){console.error("ASYNC_FRAME_CONTROL_FAIL capture rejected");Qt.quit()}
   }
  }
 }
 Timer {interval:2500;running:true;onTriggered:{console.info("ASYNC_FRAME_CONTROL",JSON.stringify({swaps:root.swaps,grabs:root.grabs,states:root.states,pending:root.pending}));Qt.quit()}}
}
