#!/usr/bin/env python3
"""Real hidden-action Header/layout dimensions without the full field capture loop."""
import json,os,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
QML=r'''
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.dashboard
ShellRoot {
 id:root
 property real requestedWidth:900
 property int checks:0
 property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;implicitWidth:1000;implicitHeight:640;color:"#111820"
  Item {
   id:scene;width:Math.min(root.requestedWidth,window.width);height:window.height
   ColumnLayout {
    anchors.fill:parent;spacing:12
    DashboardHeader {id:header;Layout.fillWidth:true;pageCount:3;pageIds:["dashboard","music","weeklyPlanner"];showActions:false;editMode:false}
    Item {id:canvas;Layout.fillWidth:true;Layout.fillHeight:true}
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,label){root.checks++;if(!value)throw new Error(label)}
  function frame(label){let ready=false;header.grabToImage(result=>{if(label)result.saveToFile(Quickshell.env("HEADER_EVIDENCE")+"/"+label+".png");ready=true});tryVerify(()=>ready,3000);root.frames++}
  function run(){try{
   tryCompare(Config,"ready",true,6000);Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true})
   for(const width of [900,600,300]){
    root.requestedWidth=width
    for(const power of [true,false]){
     Config.setNestedValue("dashboard.showPowerButtons",power)
     header.showActions=false;header.editMode=false;frame("before-"+width+"-"+power)
     const before=[canvas.width,canvas.height,header.height]
     check(header.height===32,"hidden actions affected initial dots-only header")
     header.editMode=true;frame("edit-"+width+"-"+power)
     check(JSON.stringify([canvas.width,canvas.height,header.height])===JSON.stringify(before),"Edit resized hidden header or its page canvas")
     header.editMode=false;frame()
     check(JSON.stringify([canvas.width,canvas.height,header.height])===JSON.stringify(before),"Cancel resized hidden header or its page canvas")
     header.showActions=true;frame()
     check(header.height===Math.max(32,Array.from(header.children).find(item=>item.spacing!==undefined&&item.anchors.right!==undefined)?.implicitHeight??32),"visible header action height disagrees with layout")
     check(canvas.width===before[0]&&canvas.height>0,"visible header broke canvas allocation")
     header.showActions=false;frame()
     check(JSON.stringify([canvas.width,canvas.height,header.height])===JSON.stringify(before),"hiding actions did not restore original canvas")
    }
   }
   console.info("DASHBOARD_HIDDEN_HEADER_PASS",root.checks,"checks",root.frames,"rendered frames")
  }catch(error){console.error("DASHBOARD_HIDDEN_HEADER_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
with tempfile.TemporaryDirectory(prefix="alis-hidden-header-") as name:
    folder=Path(name)
    for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:(folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    dest=Path(os.environ.get("ALIS_HEADER_EVIDENCE",folder/"evidence")).resolve();dest.mkdir(parents=True,exist_ok=True)
    with private_wayland(folder) as env:
        if not env:print("SKIP: Header fixture requires private Niri");raise SystemExit(0)
        cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
        data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss"
        (cfg/"config.json").write_text(json.dumps(data))
        # This is a dimensions test, not a 30s rendering performance gate.
        # Match the existing editor's45s process budget for all30 frame readbacks.
        result=run_qs(folder,dict(env,HEADER_EVIDENCE=str(dest),QT_QUICK_BACKEND="software"),timeout=45)
        (dest/"header.log").write_text(result.stdout)
        (dest/"receipt.json").write_text(json.dumps({'exit_code':result.returncode,'passed':'DASHBOARD_HIDDEN_HEADER_PASS' in result.stdout,'process_budget_seconds':45},indent=2)+'\n')
        if result.returncode or "DASHBOARD_HIDDEN_HEADER_PASS" not in result.stdout or any(token in result.stdout for token in ["DASHBOARD_HIDDEN_HEADER_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration"]):print(result.stdout);raise SystemExit(1)
        print(next(line for line in result.stdout.splitlines() if "DASHBOARD_HIDDEN_HEADER_PASS" in line))
