
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
ShellRoot {
 id:root;property int cycles:0
 Component.onCompleted:Quickshell.watchFiles=false
 Loader {id:critical;active:Config.ready&&Config.options.panelFamily==="abyss";source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 TestCase {
  id:test;when:false;optional:true
  function run(){try{
   tryCompare(Config,"ready",true,5000);GlobalStates.deferredPanelsReady=true
   GlobalStates.abyssColdPerimeterRecreatePending=false
   for(let i=0;i<3;i++){
    Config.setNestedValue("panelFamily","abyss")
    tryVerify(()=>critical.item && findChild(critical.item,"abyssPerimeterLoader")?.item?.nativeInputFramesReady,12000)
    Config.setNestedValue("enabledPanels",[])
    Config.setNestedValue("enabledPanels",["abyssDock","extra-package"])
    Config.setNestedValue("enabledPanels",[])
    Config.setNestedValue("panelFamily","waffle");wait(200)
    if(critical.item!==null)throw new Error("family switch retained critical host")
    root.cycles++
   }
   console.info("PERIMETER_TEARDOWN_DIAGNOSTIC_PASS",root.cycles)
  }catch(e){console.error("PERIMETER_TEARDOWN_DIAGNOSTIC_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:150;running:true;onTriggered:test.run()}
}
