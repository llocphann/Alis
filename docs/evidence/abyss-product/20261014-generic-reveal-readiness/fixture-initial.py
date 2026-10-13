#!/usr/bin/env python3
"""A delayed real content loader must not reveal an empty generic Popup plate."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-generic-reveal-") as name:
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
import qs.modules.abyss
ShellRoot {
 id:root;property int checks:0
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=false}
 AbyssSurfaceController {id:controller;outputWidth:800;outputHeight:600}
 FloatingWindow {
  visible:true;implicitWidth:800;implicitHeight:600;color:"#111820"
  Item {width:800;height:600
   AbyssGenericPopupPresenter {
    id:popup;anchors.fill:parent;controller:controller
    outputWidth:800;outputHeight:600;outputName:"readinessQA"
    requestedKind:"utilities";requestedFallbackEdge:"top";requestedAlongCenter:400
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function noEarlyPlate(label){
   check(popup.resident&&!popup.ready,"fixture did not hold a delayed loader "+label)
   check(popup.revealProgress===0&&popup.offsetScale===1,"empty plate began reveal "+label)
   check(popup.record.surface.width===0||popup.record.surface.height===0,"empty content painted a surface "+label)
   check(popup.inputBounds.width===0&&popup.inputBounds.height===0,"delayed content acquired input "+label)
  }
  function run(){try{
   tryCompare(Config,"ready",true,5000);wait(150)
   for(const reduced of [false,true]){
    Config.setNestedValue("performance.reduceAnimations",reduced)
    GlobalStates.deferredPanelsReady=false
    popup.requestedOpen=true;wait(400);noEarlyPlate("normal/reduced="+reduced)
    // Cancel while waiting: readiness arriving later must not resurrect it.
    popup.requestedOpen=false
    tryVerify(()=>!popup.resident,4000)
    GlobalStates.deferredPanelsReady=true;wait(100)
    check(!popup.resident&&!popup.ready&&popup.revealProgress===0,"cancelled delayed owner resurrected")
    GlobalStates.deferredPanelsReady=false
    popup.requestedOpen=true;wait(80);noEarlyPlate("before ready")
    GlobalStates.deferredPanelsReady=true
    tryVerify(()=>popup.ready&&popup.revealProgress>.999,5000)
    const item=popup.contentItem.item
    check(item!==null&&popup.contentKind==="utilities","ready reveal lost feature identity")
    check(popup.inputBounds.width>0&&popup.inputBounds.height>0,"ready content did not acquire input")
    popup.requestedOpen=false;wait(40)
    check(popup.inputBounds.width===0,"semantic close retained input")
    tryVerify(()=>!popup.resident&&!popup.ready,4000)
    check(popup.revealProgress===0,"closed owner retained reveal")
    // Cancel synchronously after onReady schedules the existing callLater.
    GlobalStates.deferredPanelsReady=false;popup.requestedOpen=true;wait(40)
    GlobalStates.deferredPanelsReady=true;popup.requestedOpen=false;wait(40)
    check(popup.revealProgress===0,"queued reveal ignored cancelled request")
    tryVerify(()=>!popup.resident&&!popup.ready,4000)
   }
   console.info("GENERIC_REVEAL_READY_PASS",root.checks,"delayed/cancelled/ready content, normal/reduced motion and release")
  }catch(error){console.error("GENERIC_REVEAL_READY_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("Private Niri required")
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        (config / "config.json").write_text((ROOT / "defaults/config.json").read_text())
        result = run_qs(folder, env, 35)
        if path := os.environ.get("ALIS_GENERIC_REVEAL_LOG"):
            Path(path).write_text(result.stdout)
        errors = ["GENERIC_REVEAL_READY_FAIL", "ReferenceError:", "TypeError:",
                  "Binding loop", "Failed to load configuration"]
        if result.returncode or "GENERIC_REVEAL_READY_PASS" not in result.stdout or any(e in result.stdout for e in errors):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "GENERIC_REVEAL_READY_PASS" in line:
                print(line)
