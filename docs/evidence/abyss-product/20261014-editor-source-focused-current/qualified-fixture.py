#!/usr/bin/env python3
"""Native popup ownership across a module's edit/normal input handoff."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(os.environ["ALIS_EDITOR_HOVER_RECEIPT_DIR"]) if os.environ.get("ALIS_EDITOR_HOVER_RECEIPT_DIR") else None
if OUTPUT:
    OUTPUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="alis-editor-popup-source-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.bar
import qs.modules.abyss
ShellRoot {
 id: root; property string edge:"top"; property int checks:0; property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {
  id: liquid; presentationItem:scene; outputWidth:scene.width;outputHeight:scene.height
  edgeInsets:({top:8,right:8,bottom:8,left:8})
  sourceInputRegions:[owner.enabled?scene.source:scene.editorSource]
 }
 FloatingWindow {
  visible:true;implicitWidth:700;implicitHeight:480;color:"#111820"
  Item {
   id:scene;anchors.fill:parent
   Item {
    id:owner;property var liquidController:liquid;property string attachedEdge:root.edge
    property string kind:"resources";property bool staleHover:false
    // Simulate a mature feature retaining a flag after its owner is disabled.
    readonly property bool hovered:staleHover
    x:root.edge==="left"?8:root.edge==="right"?scene.width-40:180
    y:root.edge==="top"?8:root.edge==="bottom"?scene.height-40:180
    width:["top","bottom"].includes(root.edge)?90:32
    height:["top","bottom"].includes(root.edge)?32:90
    Item {id:feature;anchors.fill:parent}
   }
   readonly property Region source:Region {x:owner.x;y:owner.y;width:owner.enabled?owner.width:0;height:owner.height}
   readonly property Region editorSource:Region {x:owner.x;y:owner.y;width:owner.enabled?0:owner.width;height:owner.height}
   Item {
    id:handle;x:owner.x;y:owner.y;width:owner.width;height:owner.height
    visible:!owner.enabled;MouseArea {anchors.fill:parent;hoverEnabled:true}
   }
   AbyssBodyHost {
    id:host;anchors.fill:parent;identity:"styledPopup0";controller:liquid
    readonly property var hostedPopup:liquid.popupSlots[0]?.popup??null
    includeEdgeConnection:true;edge:root.edge;edgeInsets:liquid.edgeInsets
    open:hostedPopup?.presentationActive??false
    externalProgress:hostedPopup?.revealProgress??0
    semanticOpenOverride:hostedPopup?.liquidSemanticVisible??false
    embeddedItem:hostedPopup?.contentItem??null
    span:["top","bottom"].includes(root.edge)?220:150
    depth:["top","bottom"].includes(root.edge)?150:220
    along:160;padding:14
    Component.onCompleted:liquid.registerPopupHost(0,host)
    Component.onDestruction:liquid.unregisterPopupHost(0,host)
    HoverHandler {
     parent:host.hoverParent;enabled:host.open
     onHoveredChanged:if(host.hostedPopup)host.hostedPopup._contentHovered=hovered
    }
   }
  }
 }
 StyledPopup {id:popup;hoverTarget:feature;Rectangle {implicitWidth:190;implicitHeight:120;color:"#28414b"}}
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label+" / "+root.edge)}
  function frame(){let done=false;check(scene.grabToImage(()=>{root.frames++;done=true}),"frame refused");tryVerify(()=>done,3000);check(done,"frame deadline")}
  function outside(){mouseMove(scene,scene.width*.75,scene.height*.65);wait(150);frame()}
  function sourcePoint(){mouseMove(scene,owner.x+owner.width/2,owner.y+owner.height/2);wait(120);frame()}
  function run(){try{
   tryCompare(Config,"ready",true,6000);Config.setNestedValue("performance.reduceAnimations",true);GlobalStates.deferredPanelsReady=true;outside()
   for(const edge of ["top","bottom","left","right"]){
    root.edge=edge;owner.enabled=true;owner.staleHover=false;popup.alternativeVisibleCondition=false;outside();sourcePoint()
    check(popup.requestedVisible&&popup._anchorReady,"normal source hover does not open")
    owner.staleHover=true;owner.enabled=false;sourcePoint();wait(180);frame()
    check(!popup._anchorReady&&!popup.moduleHoverActive&&!popup._anchorHover.hovered,"disabled owner retains a source lease")
    check(!popup.requestedVisible&&!popup.liquidSemanticVisible,"editor handle gives a background popup body hover")
    owner.staleHover=false;owner.enabled=true;outside();sourcePoint();check(popup.requestedVisible,"normal hover not restored")
    const body=host.record.content;mouseMove(scene,body.x+body.width/2,body.y+body.height/2);wait(100);frame()
    check(popup._contentHovered,"body pointer was not acquired")
    wait(180);frame();check(popup.requestedVisible&&popup._contentHovered,"source leave incorrectly suppresses actual body hover")
    outside();wait(180);frame();check(!popup.requestedVisible,"body leave keeps popup open")
    owner.enabled=false;popup.alternativeVisibleCondition=true;sourcePoint();wait(180);frame()
    check(popup.requestedVisible&&!popup._anchorReady,"explicit pin/keyboard request is lost during editor handoff")
    popup.alternativeVisibleCondition=false;outside();wait(180);frame();check(!popup.requestedVisible&&!popup.liquidSemanticVisible,"explicit release leaves stale hold")
   }
   console.info("ABYSS_EDITOR_POPUP_SOURCE_PASS",root.checks,"checks",root.frames,"frames")
  }catch(e){console.error("ABYSS_EDITOR_POPUP_SOURCE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: editor popup source ownership requires private Niri")
        cfg = folder / "config/illogical-impulse"
        cfg.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["abyss"]["companion"]["enabled"] = False
        (cfg / "config.json").write_text(json.dumps(data))
        result = run_qs(folder, env, timeout=60)
        if OUTPUT:
            (OUTPUT / "native.log").write_text(result.stdout)
            (OUTPUT / "process.json").write_text(json.dumps({"exit_code":result.returncode,"explicit_focus_requested":False},indent=2)+"\n")
        bad = ["ABYSS_EDITOR_POPUP_SOURCE_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]
        if result.returncode or "ABYSS_EDITOR_POPUP_SOURCE_PASS" not in result.stdout or any(t in result.stdout for t in bad):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "ABYSS_EDITOR_POPUP_SOURCE_PASS" in line:
                print(line)
