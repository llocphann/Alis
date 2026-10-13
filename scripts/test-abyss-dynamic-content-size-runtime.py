#!/usr/bin/env python3
"""Real content adapters and reparented forms retain full size behind the clip.

Private Niri, no parent focus, isolated config/D-Bus. This is adapter/BodyHost
qualification, not installed whole-Perimeter or physical-pointer acceptance.
"""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text()
flags = {}
for name in ["toastBody", "osd", "utility", "dialogBody"]:
    start = perimeter.index("id: " + name + "\n")
    end = perimeter.index("\n            }", start)
    flags[name] = "stableContentSize: true" in perimeter[start:end]

with tempfile.TemporaryDirectory(prefix="alis-dynamic-content-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets",
                  "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss
ShellRoot {
 id:root
 property int checks:0
 property bool shown:false
 property bool fixedSize:false
 property real reveal:1
 property string side:"top"
 property string mode:"toastBody"
 property string selectedKind:"session"
 readonly property var flags:FLAGS
 Component.onCompleted:{
  Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true
  GlobalStates.toastManager=manager
 }
 QtObject {
  id:manager
  property int toastSpacing:8
  property var toasts:[]
  function dismissToast(id){}
 }
 AbyssSurfaceController {
  id:controller;outputWidth:scene.width;outputHeight:scene.height
  dialogHost:body
 }
 FloatingWindow {
  visible:true;implicitWidth:1200;implicitHeight:920;color:"#111820"
  Item {
   // Geometry qualification uses a controlled canvas. A nested compositor
   // may constrain its native window below the requested implicit size; that
   // must not cap both intrinsic-size scenarios to the same allocator target.
   id:scene;width:1200;height:920
   Item {
    id:home;width:500;height:600
    readonly property var liquidController:controller
    WindowDialog {
     id:dialog;anchors.fill:parent;backgroundWidth:350;backgroundHeight:450
     property string draft:"Retained draft"
     WindowDialogTitle {text:"Connected form"}
     StyledText {text:dialog.draft;wrapMode:Text.WordWrap;Layout.fillWidth:true}
     onDismiss:show=false
    }
   }
   AbyssBodyHost {
    id:body;identity:"dynamicQA";anchors.fill:parent;controller:controller
    edge:root.side;padding:14;externalProgress:root.reveal
    animatePresentation:false;animatePlacementChanges:false
    stableContentSize:root.fixedSize
    largeSurface:root.mode==="utility"
    open:root.mode==="dialogBody" ? controller.activeDialog!==null : root.shown
    embeddedItem:root.mode==="dialogBody" ? controller.activeDialog : null
    contentKind:root.mode==="osd" ? "volume" : root.selectedKind
    readonly property real featureWidth:root.mode==="dialogBody" ? dialog.liquidWidth
     : contentItem.item?.desiredWidth ?? 640
    readonly property real featureHeight:root.mode==="dialogBody" ? dialog.liquidHeight
     : contentItem.item?.desiredHeight ?? 500
    span:(edge==="top"||edge==="bottom" ? featureWidth : featureHeight)+padding*2
    depth:(edge==="top"||edge==="bottom" ? featureHeight : featureWidth)+padding*2
    along:100
    source:root.mode==="toastBody" ? "content/AbyssToastContent.qml"
     :root.mode==="osd" ? "content/AbyssOsdContent.qml"
     :root.mode==="utility" ? "content/AbyssUtilityContent.qml" : ""
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function dimensions(){return {width:body.contentParent.width,height:body.contentParent.height}}
  function fullSize(label){
   check(body.contentParent.width===body.targetRecord.content.width
    &&body.contentParent.height===body.targetRecord.content.height,"canvas reflows "+label)
   if(root.mode!=="dialogBody")
    check(body.contentItem.item.width===body.contentParent.width
     &&body.contentItem.item.height===body.contentParent.height,"adapter reflows "+label)
   else check(dialog.width===body.contentParent.width&&dialog.height===body.contentParent.height,"dialog form reflows "+label)
  }
  function toast(id,title,message){return {id:id,title:title,message:message,icon:"info",isError:false,duration:60000,source:"reload",accentColor:"#88ced2"}}
  function run(){try{
   tryCompare(Config,"ready",true,5000);wait(150)
   Config.setNestedValue("panelFamily","abyss")
   manager.toasts=[toast(1,"Reloaded","")]
   for(const mode of ["toastBody","osd","utility","dialogBody"]){
    root.mode=mode;root.fixedSize=root.flags[mode]
    for(const edge of ["top","right","bottom","left"]){
     root.side=edge;root.reveal=1;root.shown=true
     if(mode==="dialogBody")dialog.show=true
     tryVerify(()=>body.ready&&body.acceptsInput,4000);wait(100)
     const item=mode==="dialogBody" ? dialog : body.contentItem.item
     const initial=dimensions()
     check(initial.width>0&&initial.height>0,"empty full canvas "+mode)
     for(const progress of [.01,.08,.2,.42,.7,1,.76,.3,.64,1]){
      root.reveal=progress;wait(0)
      fullSize(mode+" "+edge+" "+progress)
      check(body.contentParent.width===initial.width&&body.contentParent.height===initial.height,"reveal changed target "+mode)
      check((mode==="dialogBody" ? controller.activeDialog : body.contentItem.item)===item,"reveal replaced content "+mode)
      check(body.acceptsInput,"reveal changed semantic input "+mode)
     }
     // Genuine intrinsic changes must still reflow once to their new size.
     const before=dimensions()
     if(mode==="toastBody")manager.toasts=[toast(1,"Reloaded",""),toast(2,"Second message","Synthetic details")]
     if(mode==="osd")GlobalStates.abyssOsdMessage="Synthetic volume message"
     if(mode==="utility")root.selectedKind="cheatsheet"
     if(mode==="dialogBody"){dialog.backgroundWidth=410;dialog.backgroundHeight=510;dialog.draft="Edited draft"}
     tryVerify(()=>body.contentParent.width!==before.width||body.contentParent.height!==before.height,4000)
     fullSize("real resize "+mode)
     check((mode==="dialogBody" ? controller.activeDialog : body.contentItem.item)===item,"real resize replaced content "+mode)
     root.reveal=.3;wait(0);fullSize("resized reveal "+mode)
     if(mode==="toastBody")manager.toasts=[toast(1,"Reloaded","")]
     if(mode==="osd")GlobalStates.abyssOsdMessage=""
     if(mode==="utility")root.selectedKind="session"
     if(mode==="dialogBody"){dialog.backgroundWidth=350;dialog.backgroundHeight=450}
     wait(100);root.reveal=1
     if(mode==="dialogBody"){
      dialog.show=false;wait(0)
      check(controller.activeDialog===null&&dialog.parent===home,"dialog did not restore home")
      check(dialog.draft==="Edited draft","reparenting erased draft")
     }else root.shown=false
     check(!body.acceptsInput,"semantic close retained input "+mode)
     root.reveal=0
     tryVerify(()=>mode==="dialogBody" ? !body.ready : body.contentItem.item===null,3000)
     check(!body.visualResident,"closed body retained visual residency "+mode)
     root.shown=false
    }
   }
   console.info("DYNAMIC_CONTENT_SIZE_PASS",root.checks,"real Toast/OSD/Utility and reparented form, four Edges, reversal, resize and release")
  }catch(error){console.error("DYNAMIC_CONTENT_SIZE_FAIL",error.message,error.stack,
   root.mode,root.side,body.open,body.ready,body.contentItem.status,body.contentItem.source,
   JSON.stringify(body.placement),body.progress)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''.replace("FLAGS", json.dumps(flags)).replace("import QtQuick\n", "import QtQuick\nimport QtQuick.Layouts\n", 1))
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("Private Niri required")
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        (config / "config.json").write_text((ROOT / "defaults/config.json").read_text())
        result = run_qs(folder, env, 45)
        if path := os.environ.get("ALIS_DYNAMIC_CONTENT_SIZE_LOG"):
            Path(path).write_text(result.stdout)
        errors = ["DYNAMIC_CONTENT_SIZE_FAIL", "Binding loop", "ReferenceError:",
                  "TypeError:", "Failed to load configuration"]
        if result.returncode or "DYNAMIC_CONTENT_SIZE_PASS" not in result.stdout or any(e in result.stdout for e in errors):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "DYNAMIC_CONTENT_SIZE_PASS" in line:
                print(line)
