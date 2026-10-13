#!/usr/bin/env python3
"""Real private D-Bus ingress and production banner closing geometry."""
import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-notification-closing-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets",
                  "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root
 property int checks:0
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true;GlobalStates.shellEntryReady=true}
 Loader {id:perimeter;active:Config.ready;sourceComponent:AbyssPerimeter {}}
 Process {id:sender}
 TestCase {
  id:test;when:false;optional:true
  function check(value,label){root.checks++;if(!value)throw new Error(label)}
  function snapshot(){return JSON.parse(perimeter.item.hoverProbeSnapshot()).outputs[0]}
  function banner(){return snapshot().notificationPresentation}
  function send(summary){
   tryVerify(()=>!sender.running,5000)
   sender.command=["notify-send","-a","Closing QA","-t","15000","--hint=boolean:transient:true","--hint=boolean:suppress-sound:true",summary,"Synthetic recording notification"]
   sender.running=true
  }
  function settle(){tryVerify(()=>{const n=banner();return n.toastOpen&&Math.abs(n.toastRevealProgress-1)<.001&&Math.abs(n.toastPaintDepth-n.toastTargetDepth)<.01},5000)}
  function run(){try{
   tryCompare(Config,"ready",true,5000)
   tryVerify(()=>perimeter.item?.outputHosts?.length>0&&perimeter.item.outputHosts[0].nativeFieldReady,7000)
   send("Starting recording");settle()
   const single=banner().toastTargetDepth
   send("Recording saved");tryVerify(()=>banner().toastCount===2,5000)
   // Ingress precedes the existing 75ms ListView measurement commit.
   tryVerify(()=>banner().toastTargetDepth>single,5000);settle()
   const before=banner();check(before.toastTargetDepth>single,"grouped banner did not exercise a taller geometry")
   GlobalStates.openNotificationCenter(snapshot().output)
   tryVerify(()=>banner().centerOpen&&banner().toastCount===0,3000)
   const closing=banner()
   check(closing.toastRevealProgress>.001,"missed the real closing animation")
   check(closing.toastLayoutReady===false,"empty list kept reveal readiness")
   check(closing.toastTargetDepth===before.toastTargetDepth,"empty list snapped the closing target depth")
   check(closing.toastDesiredHeight===before.toastDesiredHeight,"empty list erased closing content dimensions")
   check(Math.abs(closing.toastPaintDepth-before.toastTargetDepth*Math.min(1.035,closing.toastRevealProgress))<.05,"closing surface no longer follows its reveal fraction")
   tryVerify(()=>!banner().toastResident&&banner().toastRevealProgress<=.001,5000)
   GlobalStates.closeNotificationCenter();wait(80)
   send("Starting recording again");settle()
   check(banner().toastCount===1,"fresh banner reused dismissed group")
   check(banner().toastTargetDepth===single,"fresh content retained the former larger height")
   check(banner().toastDesiredHeight<before.toastDesiredHeight,"old measurement survived content destruction")
   console.info("NOTIFICATION_CLOSING_PASS",root.checks,"checks",JSON.stringify({single:single,expanded:before.toastTargetDepth,closingTarget:closing.toastTargetDepth,closingPaint:closing.toastPaintDepth,progress:closing.toastRevealProgress}))
  }catch(error){console.error("NOTIFICATION_CLOSING_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:150;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("Private local Niri is required")
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        values = json.loads((ROOT / "defaults/config.json").read_text())
        values["panelFamily"] = "abyss"
        values["enabledPanels"] = ["abyssPerimeter", "abyssNotificationPopup",
                                   "abyssNotificationCenter", "abyssPopup"]
        values["sounds"]["notifications"] = False
        values["abyss"]["waves"]["enabled"] = False
        values["abyss"]["companion"]["enabled"] = False
        values["abyss"]["modules"].update(configured=True, placements=[], outputLayouts=[])
        (config / "config.json").write_text(json.dumps(values))
        result = run_qs(folder, env, timeout=35)
        errors = ["NOTIFICATION_CLOSING_FAIL", "Binding loop", "ReferenceError:",
                  "TypeError:", "Failed to load configuration"]
        if result.returncode or "NOTIFICATION_CLOSING_PASS" not in result.stdout or any(e in result.stdout for e in errors):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "NOTIFICATION_CLOSING_PASS" in line:
                print(line)
