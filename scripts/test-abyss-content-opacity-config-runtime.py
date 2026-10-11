#!/usr/bin/env python3
"""Actual Config raw-mirror opacity migration, disk restart and unknown data."""
import json, os, tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT=Path(__file__).resolve().parents[1]
cases=[({"opacity":0,"cardOpacity":.9,"blurRadius":0},0,0),
       ({"opacity":-1,"cardOpacity":.4,"blurRadius":17},-1,.62),
       ({"cardOpacity":.35,"blurRadius":12},.35,.35),
       ({"blurRadius":-1},-1,.62),
       ({"opacityVersion":2,"opacity":.75,"cardOpacity":.2,"blurRadius":3},.75,.75)]
with tempfile.TemporaryDirectory(prefix="alis-content-opacity-config-") as name:
    folder=Path(name)
    for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.abyss.looks
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,6000)
   const alpha=Number(Quickshell.env("EXPECTED_EFFECTIVE"))
   check(Config.options.abyss.content.opacity===Number(Quickshell.env("EXPECTED_SAVED")),"migration chose wrong raw opacity")
   check(AbyssStyle.contentOpacity===alpha && AbyssStyle.cardOpacity===alpha,"cards and panel diverged")
   check(Math.abs(AbyssStyle.contentLayer.a-alpha)<.005,"card tint squared effective alpha")
   check(AbyssStyle.surfaceOpacity===.62,"migration changed Screen Edge alpha")
   check(Config.options.abyss.content.blurRadius===Number(Quickshell.env("EXPECTED_BLUR")),"migration changed blur")
   check(AbyssStyle.textColor.a===1,"shared alpha faded text")
   // Qualification is the automatic migration save, not an extra unchanged
   // flush (FileView may omit acknowledgement when its cached bytes match).
   wait(200)
   tryVerify(()=>!Config._writeInFlight && !Config._pendingWrite,4000)
   console.info("CONTENT_OPACITY_CONFIG_PASS",Quickshell.env("CASE_ID"),Quickshell.env("RESTART"))
  }catch(error){console.error("CONTENT_OPACITY_CONFIG_FAIL",Quickshell.env("CASE_ID"),error.message,
   JSON.stringify({write:Config._writeInFlight,pending:Config._pendingWrite,mirror:Config._jsonMirror?.abyss?.content}),error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    runtime=folder/"runtime";runtime.mkdir(mode=0o700)
    env=dict(os.environ,QT_QPA_PLATFORM="offscreen",QSG_RHI_BACKEND="software",XDG_RUNTIME_DIR=str(runtime))
    for key in ["WAYLAND_DISPLAY","NIRI_SOCKET","DISPLAY","HYPRLAND_INSTANCE_SIGNATURE","QS_CONFIG_NAME","QS_CONFIG_PATH","QS_MANIFEST"]:env.pop(key,None)
    for kind in ["config","cache","data","state"]:
        (folder/kind).mkdir();env[f"XDG_{kind.upper()}_HOME"]=str(folder/kind)
    config=folder/"config/illogical-impulse/config.json";config.parent.mkdir(parents=True)
    logs=[]
    for index,(content,saved,effective) in enumerate(cases):
        value=json.loads((ROOT/"defaults/config.json").read_text())
        value["panelStyleVersion"]=1;value["abyss"]["companion"]["enabled"]=False
        value["abyss"]["surface"]["opacity"]=.62
        value["abyss"]["content"]={**content,"unknownOpacityData":{"preserve":[0,None,"future"]}}
        value["optionalPackageData"]={"opaqueUnknown":["keep",3]}
        value["appearance"]["screenEdge"]["unrecognizedOutput"]={"left":0,"right":17}
        config.write_text(json.dumps(value))
        for restart in [False,True]:
            result=run_qs(folder,dict(env,CASE_ID=str(index),RESTART=str(int(restart)),
                EXPECTED_EFFECTIVE=str(effective),EXPECTED_SAVED=str(saved),EXPECTED_BLUR=str(content["blurRadius"])),timeout=18)
            logs.append(result.stdout)
            if result.returncode or "CONTENT_OPACITY_CONFIG_PASS" not in result.stdout or any(token in result.stdout for token in ["CONTENT_OPACITY_CONFIG_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration"]):
                print(result.stdout);raise SystemExit(1)
            disk=json.loads(config.read_text())
            assert disk["abyss"]["content"]["opacity"]==saved
            assert disk["abyss"]["content"]["opacityVersion"]==content.get("opacityVersion",1)
            assert disk["abyss"]["content"]["blurRadius"]==content["blurRadius"]
            assert disk["abyss"]["content"]["unknownOpacityData"]==value["abyss"]["content"]["unknownOpacityData"]
            assert disk["optionalPackageData"]==value["optionalPackageData"]
            assert disk["appearance"]["screenEdge"]["unrecognizedOutput"]==value["appearance"]["screenEdge"]["unrecognizedOutput"]
            if "cardOpacity" in content:assert disk["abyss"]["content"]["cardOpacity"]==content["cardOpacity"]
    if os.environ.get("ALIS_CONTENT_OPACITY_LOG"):Path(os.environ["ALIS_CONTENT_OPACITY_LOG"]).write_text("\n".join(logs))
    print("CONTENT_OPACITY_CONFIG_PASS 5 saved cases / 10 actual Config processes and disk readbacks; no windows or owner preferences")
