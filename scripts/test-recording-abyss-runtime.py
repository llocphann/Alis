#!/usr/bin/env python3
"""Real Recording controls in the shared field and the retained native window."""
import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-recording-field-") as name:
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
import qs.modules.abyss
import qs.modules.abyss.looks
import qs.modules.recordingOsd
ShellRoot {
 id:root
 property int stopped:0
 property int rendered:0
 readonly property var legacy: legacyLoader.item
 Component.onCompleted:Quickshell.watchFiles=false
 QtObject {
  id:status;property bool isRecording:false;property int elapsedSeconds:59
  property string effectiveAudioMode:"both"
  function scheduleQuickCheck(){throw new Error("fixture reached production stop path")}
 }
 QtObject {id:systemAudio;property bool muted:false}
 QtObject {
  id:audio;property var sink:({audio:systemAudio});property bool micMuted:false
  function toggleMute(){systemAudio.muted=!systemAudio.muted}
  function toggleMicMute(){micMuted=!micMuted}
 }
 AbyssSurfaceController {
  id:controller;presentationItem:scene;outputWidth:scene.width;outputHeight:scene.height
  edgeInsets:({left:16,right:16,top:16,bottom:16})
 }
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:760;color:"#111820"
  Item {
   id:scene;anchors.fill:parent
   AbyssField {anchors.fill:parent;records:controller.records;edgeInsets:controller.edgeInsets;z:-1}
   AbyssRecordingBody {
    id:body;anchors.fill:parent;controller:controller;edgeInsets:controller.edgeInsets
    recordingStatus:status;audioService:audio;stopAction:()=>root.stopped++
   }
   AbyssRecordingBody {
    id:otherOutput;anchors.fill:parent;targetOutput:false;identity:"otherRecording"
    recordingStatus:status;audioService:audio
   }
   Rectangle {id:tick;width:1;height:1;color:"#01000000";opacity:0.01}
  }
 }
 LazyLoader {
  id:legacyLoader;active:legacyStatus.isRecording
  component:RecordingOsd {
   recordingStatus:legacyStatus;audioService:audio
   stopAction:()=>root.stopped++
  }
 }
 QtObject {
  id:legacyStatus;property bool isRecording:false;property int elapsedSeconds:61
  property string effectiveAudioMode:"both"
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,message){if(!ok)throw new Error(message)}
  function find(item,name){
   if(item.objectName===name && item.visible)return item
   for(const child of item.children ?? []){const result=find(child,name);if(result)return result}
   return null
  }
  function settle(){
   // Unfocused nested Niri throttles animation frames. Drive bounded render
   // turns before sending input to a body whose orientation/size just changed.
   for(let i=0;i<2;i++){
    const before=root.rendered
    tick.opacity=(before%2)?0.01:0.02
    check(scene.grabToImage(result=>root.rendered++),"frame request refused")
    tryVerify(()=>root.rendered>before,3000)
    if(i===0)wait(220)
   }
  }
  function click(name){const item=find(body.recorder.controls,name);check(item,"missing "+name);check(item.enabled && item.width>0 && item.height>0,"inactive "+name);mouseClick(item,item.width/2,item.height/2);wait(80)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   GlobalStates.deferredPanelsReady=true
   Config.setNestedValue("performance.reduceAnimations",false)
   Config.setNestedValue("abyss.waves.enabled",false)
   Config.setNestedValue("screenRecord.recordingOsd.autoHide",false)
   check(!body.recorder && !root.legacy,"idle Recording allocated controls/window")
   status.isRecording=true
   tryVerify(()=>body.recorder?.controls!==null && body.ready,4000);settle()
   check(body.recorder.embeddedMode && !body.recorder.nativeWindow,"Abyss allocated a second native Recording window")
   check(!otherOutput.recorder,"Recording controls were duplicated on another output")
   check(controller.records.some(record=>record.id==="recording" || record.identity==="recording" || record.kind==="recording") || controller.participants.recording,
     "Recording absent from the existing field")
   check(body.recorder.formatTime(59)==="00:59" && body.recorder.formatTime(3601)==="01:00:01","elapsed timer format changed")
   const width=body.recorder.controls.width
   status.elapsedSeconds=60;settle()
   check(body.recorder.controls.width===width,"minute boundary shifted buttons")
   for(const edge of ["top","right","bottom","left"]){
    body.edge=edge;body.alongCenter=-1;settle()
    check(body.recorder.isVertical===["left","right"].includes(edge),"incorrect Recording orientation on "+edge)
    check(body.inputBounds.width>0 && body.inputBounds.height>0,"Recording lost connected input")
    check(controller.nativeInputRegions.includes(body.nativeInputRegion),"Recording controls did not reach native input mask")
    const mask=body.nativeInputRegion.regions[0]
    check(mask.x<=body.inputBounds.x && mask.y<=body.inputBounds.y
      && mask.x+mask.width>=body.inputBounds.x+body.inputBounds.width
      && mask.y+mask.height>=body.inputBounds.y+body.inputBounds.height,"Recording native mask clips control footprint")
    click("recordingSystemAudio");check(systemAudio.muted,"system audio did not mute on "+edge+" open="+body.open+" progress="+body.progress+" content="+JSON.stringify(body.record.content)+" controls="+body.recorder.controls.width+"x"+body.recorder.controls.height)
    click("recordingSystemAudio");check(!systemAudio.muted,"system audio did not unmute")
    click("recordingMicrophone");check(audio.micMuted,"mic did not mute")
    click("recordingMicrophone");check(!audio.micMuted,"mic did not unmute")
    const span=body.span;click("recordingCollapse")
    check(body.recorder.collapsed,"Minimize did not persist its choice")
    mouseMove(scene,80,80);settle()
    let dot=find(body.recorder.controls,"recordingMinimizedDot")
    check(dot && body.span<span && body.recorder.controls.width===14 && body.recorder.controls.height===14,
      "Minimize did not retain a small dot-only footprint on "+edge)
    for(const name of ["recordingTimer","recordingStop","recordingSystemAudio","recordingMicrophone","recordingDragHandle","recordingCollapse"])
     check(!find(body.recorder.controls,name),"minimized mode exposed "+name)
    Config.setNestedValue("screenRecord.recordingOsd.autoHide",true);wait(2300)
    check(body.open && body.recorder.revealed && !body.recorder.controlsExpanded,
      "auto-hide removed the minimized recording dot")
    mouseMove(dot,dot.width/2,dot.height/2)
    tryVerify(()=>body.recorder.controlsExpanded,2000);settle()
    check(body.recorder.collapsed && !find(body.recorder.controls,"recordingMinimizedDot")
      && find(body.recorder.controls,"recordingSystemAudio") && find(body.recorder.controls,"recordingStop"),
      "dot hover did not temporarily reveal all controls")
    click("recordingCollapse");check(!body.recorder.collapsed,"Expand controls did not persist expanded mode")
    Config.setNestedValue("screenRecord.recordingOsd.autoHide",false)
    mouseMove(scene,80,80);settle()
    check(body.recorder.controlsExpanded && find(body.recorder.controls,"recordingStop"),"explicit expansion collapsed on leave")
    click("recordingCollapse");mouseMove(scene,80,80);settle()
    dot=find(body.recorder.controls,"recordingMinimizedDot")
    check(dot,"second minimization lost its recovery dot")
    dot.forceActiveFocus();keyClick(Qt.Key_Space);settle()
    check(!body.recorder.collapsed && body.recorder.controlsExpanded,"keyboard could not expand the minimized recording dot")
    const rect=body.targetRecord.content
    const hx=edge==="left"?body.edgeInsets.left+2:edge==="right"?scene.width-body.edgeInsets.right-2:rect.x+rect.width/2
    const hy=edge==="top"?body.edgeInsets.top+2:edge==="bottom"?scene.height-body.edgeInsets.bottom-2:rect.y+rect.height/2
    Config.setNestedValue("screenRecord.recordingOsd.autoHide",true)
    mouseMove(scene,hx,hy);settle();wait(2200)
    check(body.open && body.recorder.osdTargetHovered,"drawn connection lost Recording hover")
    mouseMove(scene,80,80);tryVerify(()=>!body.recorder.revealed,3500);settle()
    check(!body.open && body.inputBounds.width===0,"hidden Recording retained body input on "+edge+": open="+body.open+" revealed="+body.recorder.revealed+" input="+body.inputBounds)
    const wake=controller.participants.recordingWake.inputBounds
    check(wake.width*wake.height===432,"auto-hide recovery captured excess input")
    mouseMove(scene,wake.x+wake.width/2,wake.y+wake.height/2)
    tryVerify(()=>body.recorder.revealed,2000);settle();check(body.open,"auto-hide could not recover by hover")
    Config.setNestedValue("screenRecord.recordingOsd.autoHide",false)
   }
   status.effectiveAudioMode="none";settle()
   check(!find(body.recorder.controls,"recordingSystemAudio") && !find(body.recorder.controls,"recordingMicrophone"),"none-mode kept inactive audio controls")
   status.effectiveAudioMode="microphone";settle()
   check(find(body.recorder.controls,"recordingMicrophone") && !find(body.recorder.controls,"recordingSystemAudio"),"mic mode showed system control")
   body.edge="top";body.alongCenter=-1;settle()
   const handle=find(body.recorder.controls,"recordingDragHandle")
   mousePress(handle,12,12)
   mouseMove(handle,35,25,20);wait(50)
   mouseMove(scene,scene.width-30,scene.height/2,20);wait(80)
   mouseRelease(scene,scene.width-30,scene.height/2);settle()
   check(body.edge==="right" && !body.dragging,"pointer drag did not snap Recording to right Edge")
   click("recordingStop");check(root.stopped===1,"stop callback not exactly once")
   GlobalStates.screenLocked=true;settle()
   check(!body.open && body.inputBounds.width===0 && !body.recoverable,"lock retained Recording input")
   GlobalStates.screenLocked=false;settle()
   body.available=false;settle();check(!body.open && body.inputBounds.width===0,"unmapped output kept Recording input")
   body.available=true;settle()
   status.isRecording=false;settle();tryVerify(()=>body.recorder===null,3000)
   legacyStatus.isRecording=true;tryVerify(()=>root.legacy?.controls && root.legacy?.nativeWindow,3000);settle()
   check(legacy.controls.parent===legacy.nativeWindow.pill,"native ii/Waffle controls failed reparent")
   check(legacy.nativeWindow.pill.x>=0 && legacy.nativeWindow.pill.y>=0,"legacy placement left the screen: "+legacy.nativeWindow.width+"x"+legacy.nativeWindow.height+" pill="+legacy.nativeWindow.pill.x+","+legacy.nativeWindow.pill.y)
   legacy.nativeWindow.pill.x=0;legacy.nativeWindow.pill.y=200;legacy.nativeWindow.snapToNearestEdge();settle()
   check(legacy.isVertical,"legacy drag snap lost vertical mode")
   legacy.stopRecording();check(root.stopped===2,"legacy stop callback failed")
   legacyStatus.isRecording=false;tryVerify(()=>!root.legacy,3000)
   console.info("RECORDING_ABYSS_PASS shared field, four Edges, modes, mute, timer, collapse, connection, auto-hide wake, pointer drag, stop, lock, idle and ii/Waffle window")
  }catch(e){console.error("RECORDING_ABYSS_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: Recording presentation requires private Niri")
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        (config / "config.json").write_text(json.dumps(data))
        result = run_qs(folder, env, timeout=180)
        if result.returncode or "RECORDING_ABYSS_PASS" not in result.stdout or any(token in result.stdout for token in
                ["RECORDING_ABYSS_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration", "Unable to assign"]):
            print(result.stdout)
            raise SystemExit("FAIL: native connected Recording controls")
        print("PASS: actual connected Recording controls and retained ii/Waffle presenter")
