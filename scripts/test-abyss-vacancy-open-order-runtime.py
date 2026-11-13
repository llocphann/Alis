#!/usr/bin/env python3
"""Verify real BodyHost content dimensions follow activation order."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-vacancy-order-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    config = folder / "config/alis"
    config.mkdir(parents=True)
    data = json.loads((ROOT / "defaults/config.json").read_text())
    data["abyss"]["companion"]["enabled"] = False
    (config / "config.json").write_text(json.dumps(data))
    (folder / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root;property int stage:0;property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 function check(value,label){checks++;if(!value)throw new Error(label)}
 AbyssSurfaceController {id:liquid;outputWidth:1800;outputHeight:1000;edgeInsets:({left:16,right:16,top:16,bottom:16})}
 Item {id:canvas;width:1800;height:1000}
 Item {id:sideContent;implicitWidth:412;implicitHeight:692}
 Item {id:noteContent;implicitWidth:352;implicitHeight:312}
 AbyssBodyHost {id:sidebar;parent:canvas;anchors.fill:parent;controller:liquid;identity:"leftPanel";edge:"left";
  along:110;span:720;depth:440;padding:14;edgeInsets:liquid.edgeInsets;vacancyRole:"featureSidebar";embeddedItem:sideContent;
  animatePresentation:false;animatePlacementChanges:false;stableContentSize:true;open:false}
 AbyssBodyHost {id:notes;parent:canvas;anchors.fill:parent;controller:liquid;identity:"styledPopup0";edge:"bottom";
  along:510;span:380;depth:340;padding:14;edgeInsets:liquid.edgeInsets;placementPriority:2;vacancyRole:"quickNotes";embeddedItem:noteContent;
  stackPolicy:"pyramid";externalProgress:1;animatePresentation:false;animatePlacementChanges:false;stableContentSize:true;open:false}
 Timer {interval:180;running:true;repeat:true;onTriggered:{if(!Config.ready)return;try{
  GlobalStates.deferredPanelsReady=true
  if(stage===0)sidebar.open=true
  if(stage===1)notes.open=true
  if(stage===2){
   check(notes.activationOrder>sidebar.activationOrder,"popup did not receive later order")
   check(notes.placement.vacancyBorrowed===true,"later Edgebar did not borrow")
   check(notes.contentParent.width>352,"Edgebar content stayed at original width")
   check(Math.abs(sidebar.contentParent.width-412)<.1,"earlier Sidebar changed content size")
   notes.open=false;sidebar.open=false
  }
  if(stage===3)notes.open=true
  if(stage===4)sidebar.open=true
  if(stage===5){
   check(sidebar.activationOrder>notes.activationOrder,"Sidebar did not receive later order")
   check(sidebar.placement.vacancyBorrowed===true,"later Sidebar did not borrow")
   check(sidebar.contentParent.width>412,"Sidebar content did not expand")
   check(Math.abs(notes.contentParent.width-352)<.1,"earlier Edgebar retained old expansion")
   notes.open=false
  }
  if(stage===6){
   check(!sidebar.placement.vacancyBorrowed,"closing peer left stale borrow")
   check(Math.abs(sidebar.contentParent.width-412)<.1,"Sidebar size did not restore")
   console.info("VACANCY_ORDER_RUNTIME_PASS",checks);Qt.quit()
  }
  stage++
 }catch(e){console.error("VACANCY_ORDER_RUNTIME_FAIL",e.message,e.stack);Qt.quit()}}}
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_CONFIG_HOME=str(folder / "config"),
               XDG_STATE_HOME=str(folder / "state"), XDG_CACHE_HOME=str(folder / "cache"))
    for key in ["QS_CONFIG_NAME", "QS_CONFIG_PATH"]:
        env.pop(key, None)
    result = run_qs(folder, env, timeout=15)
    print(result.stdout)
    assert result.returncode == 0 and "VACANCY_ORDER_RUNTIME_PASS" in result.stdout
    assert not any(token in result.stdout for token in ["VACANCY_ORDER_RUNTIME_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"])
