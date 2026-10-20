#!/usr/bin/env python3
"""Real OSK keeps its fitted canvas through reveal, close and reversal.

Private Niri and a fake ydotool: opening/closing cannot release owner keys.
Opt-in --focus restores the previous host window; --scale checks fractional DPI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from native_test_session import private_wayland, run_qs

parser = argparse.ArgumentParser()
parser.add_argument("--scale", type=float, default=1)
parser.add_argument("--focus", action="store_true")
args = parser.parse_args()
ROOT = Path(os.environ.get("ALIS_OSK_REVEAL_SOURCE", Path(__file__).resolve().parents[1])).resolve()
evidence = os.environ.get("ALIS_OSK_REVEAL_EVIDENCE")
QML = r'''
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root
 property var body:null
 property var nativeWindow:null
 property string phase:"boot"
 property var failures:[]
 property var samples:[]
 property var partialFrames:({})
 property bool watching:false
 Component.onCompleted:Quickshell.watchFiles=false
 function host(item){
  if(item?.identity==="keyboard")return item
  for(const child of item?.children??[]){const found=host(child);if(found)return found}
  return null
 }
 function sample(){
  if(!watching || !body?.ready || body.progress<=.001 || body.progress>=.999)return
  const row={phase,p:body.progress,width:body.contentItem.width,height:body.contentItem.height,
   targetWidth:body.targetRecord.content.width,targetHeight:body.targetRecord.content.height,
   input:body.inputBounds.width,open:body.open}
  samples.push(row);partialFrames[phase]=(partialFrames[phase]??0)+1
  if(Math.abs(row.width-row.targetWidth)>.01 || Math.abs(row.height-row.targetHeight)>.01)
   failures.push(row)
 }
 AbyssPerimeter {id:perimeter}
 Connections {target:root.nativeWindow;function onFrameSwapped(){root.sample()}}
 TestCase {
  id:test;when:false;optional:true
  function check(value,label){if(!value)throw new Error(label)}
  function run(){let error=null;try{
   tryCompare(Config,"ready",true,5000)
   Config.setNestedValue("performance.reduceAnimations",false)
   GlobalStates.deferredPanelsReady=true
   tryVerify(()=>perimeter.outputHosts.length>0,8000)
   const window=perimeter.outputHosts[0]
   root.body=root.host(window.contentItem)
   check(root.body!==null,"production keyboard host missing")
   root.nativeWindow=window.contentItem.Window.window
   root.watching=true
   for(const edge of ["top","bottom"]){
    Config.setNestedValue("abyss.positions",[{kind:"keyboard",outputName:window.screen.name,edge,alignment:"center"}])
    root.phase=edge+"-open";GlobalStates.oskOpen=true
    tryVerify(()=>root.body.ready,8000)
    const content=root.body.contentItem.item
    tryCompare(root.body,"progress",1,5000)
    check(root.body.edge===edge,"physical keyboard edge not applied")
    check((root.partialFrames[root.phase]??0)>0,"no intermediate native opening frames")
    check(root.failures.length===0,"keyboard canvas reflows during reveal")
    root.phase=edge+"-reverse-close";GlobalStates.oskOpen=false
    check(root.body.inputBounds.width===0,"closing keyboard retained input")
    tryVerify(()=>root.body.progress>.05 && root.body.progress<.9,3000)
    const before=root.body.progress
    root.phase=edge+"-reopen";GlobalStates.oskOpen=true
    check(root.body.contentItem.item===content,"reversal replaced key layout")
    check(Math.abs(root.body.progress-before)<.001,"reopen snapped progress")
    tryCompare(root.body,"progress",1,5000)
    check((root.partialFrames[root.phase]??0)>0,"no intermediate native reversal frames")
    root.phase=edge+"-close";GlobalStates.oskOpen=false
    tryVerify(()=>!root.body.ready && root.body.progress===0,5000)
    check((root.partialFrames[root.phase]??0)>0,"no intermediate native closing frames")
    check(root.failures.length===0,"keyboard canvas reflows during close/reversal")
   }
  }catch(e){error=String(e)}
  root.watching=false;GlobalStates.oskOpen=false
  console.info(error?"KEYBOARD_REVEAL_FAIL":"KEYBOARD_REVEAL_PASS",JSON.stringify({error,
   failedFrames:root.failures.length,sampleCount:root.samples.length,
   partialFrames:root.partialFrames,samples:root.samples.slice(0,300)}));Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''

with tempfile.TemporaryDirectory(prefix="alis-keyboard-reveal-") as temporary:
    folder = Path(temporary)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets",
                  "scripts", "defaults", "translations"):
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    binary = folder/"bin"
    binary.mkdir()
    stub = binary/"ydotool"
    stub.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$OSK_LOG"\n')
    stub.chmod(0o700)
    with private_wayland(folder, capture_focus=args.focus) as env:
        if env is None:
            print("SKIP: keyboard reveal requires private Niri")
            raise SystemExit(0)
        outputs = json.loads(subprocess.check_output(
            ["niri", "msg", "--json", "outputs"], env=env, text=True, timeout=4))
        output = next(iter(outputs.values()))["name"]
        subprocess.run(["niri", "msg", "output", output, "scale", str(args.scale)],
                       env=env, check=True, capture_output=True, timeout=4)
        config = folder/"config/alis"
        config.mkdir(parents=True)
        data = json.loads((ROOT/"defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["enabledPanels"] = ["iiOnScreenKeyboard"]
        data["abyss"]["companion"]["enabled"] = False
        data["performance"]["reduceAnimations"] = False
        (config/"config.json").write_text(json.dumps(data))
        env.update(PATH=str(binary)+os.pathsep+env["PATH"], OSK_LOG=str(folder/"input.log"))
        result = run_qs(folder, env, timeout=60)
        markers = [line for line in result.stdout.splitlines()
                   if "KEYBOARD_REVEAL_PASS" in line or "KEYBOARD_REVEAL_FAIL" in line]
        payload = json.loads(markers[-1][markers[-1].index("{"):]) if markers else None
        errors = ("KEYBOARD_REVEAL_FAIL", "ReferenceError:", "TypeError:",
                  "Binding loop", "Failed to load configuration")
        passed = result.returncode == 0 and payload is not None and payload["error"] is None \
            and not any(error in result.stdout for error in errors)
        receipt = {"source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
                   text=True).strip(), "status": "PASS" if passed else "FAIL",
                   "runtime_changes_from_head": subprocess.check_output(
                       ["git", "diff", "--name-only", "HEAD", "--", "modules", "services",
                        "GlobalStates.qml", "defaults"], cwd=ROOT, text=True).splitlines(),
                   "perimeter_sha256": hashlib.sha256(
                       (ROOT/"modules/abyss/AbyssPerimeter.qml").read_bytes()).hexdigest(),
                   "actual_native_exit": result.returncode, "scale": args.scale,
                   "fixture_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   "native_log_sha256": hashlib.sha256(result.stdout.encode()).hexdigest(),
                   "result": payload, "owner_input": "fake ydotool only; no owner keys sent"}
        if evidence:
            destination = Path(evidence)
            destination.mkdir(parents=True, exist_ok=True)
            (destination/"receipt.json").write_text(json.dumps(receipt, indent=2)+"\n")
            (destination/"native.log").write_text(result.stdout)
        print(json.dumps({key: value for key, value in receipt.items() if key != "result"}))
        if not passed:
            print(result.stdout[-7000:])
            raise SystemExit(1)
        print("KEYBOARD_REVEAL_PASS", payload["sampleCount"], payload["partialFrames"])
