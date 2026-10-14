#!/usr/bin/env python3
"""Native hidden-slot, pin and orientation geometry using the actual controls."""
import json
from pathlib import Path
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalis-indicator-geometry-") as name:
    shell = Path(name)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (shell / entry).symlink_to(ROOT / entry)
    config = shell / "config/alis"
    config.mkdir(parents=True)
    options = json.loads((ROOT / "defaults/config.json").read_text())
    options["shellUpdates"]["enabled"] = False
    options["performance"]["reduceAnimations"] = True
    (config / "config.json").write_text(json.dumps(options))
    (shell / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.bar
import qs.services
ShellRoot {
 Item {
  width:640; height:360
  TimerIndicator {id:timerIndicator}
  ShellUpdateIndicator {id:updateIndicator;y:50}
 }
 TestCase {
  id:test; when:false; optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function slot(control,shown,vertical){
   control.vertical=vertical
   tryCompare(control,"visible",shown,1000)
   if(!shown){
    tryCompare(control,"implicitWidth",0,1000)
    if(vertical)tryCompare(control,"implicitHeight",0,1000)
   }else{
    tryVerify(()=>control.implicitWidth>0,1000)
    tryVerify(()=>control.implicitHeight>0,1000)
    if(vertical){
     tryCompare(control,"implicitWidth",34*Appearance.sizes.barModuleScale,1000)
     tryCompare(control,"implicitHeight",34*Appearance.sizes.barModuleScale,1000)
    }
   }
   if(!vertical)tryCompare(control,"implicitHeight",Appearance.sizes.barHeight,1000)
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   tryCompare(Persistent,"ready",true,4000)
   TimerService.pomodoroRunning=false
   TimerService.pomodoroSecondsLeft=TimerService.pomodoroLapDuration
   TimerService.countdownRunning=false
   TimerService.countdownDuration=0
   TimerService.countdownSecondsLeft=0
   TimerService.stopwatchRunning=false
   TimerService.stopwatchTime=0
   TimerService.stopwatchLaps=[]
   Persistent.states.timer.pinnedToBar=false
   ShellUpdates.hasUpdate=false;ShellUpdates.isUpdating=false
   for(const vertical of [false,true]){
    slot(timerIndicator,false,vertical);slot(updateIndicator,false,vertical)
    Persistent.states.timer.pinnedToBar=true
    slot(timerIndicator,true,vertical)
    check(timerIndicator.showPinnedIdle,"pinned idle timer lost its affordance")
    Persistent.states.timer.pinnedToBar=false
    slot(timerIndicator,false,vertical)
    TimerService.pomodoroSecondsLeft=TimerService.pomodoroLapDuration-1
    slot(timerIndicator,true,vertical)
    check(timerIndicator.paused,"paused timer became unavailable")
    TimerService.pomodoroSecondsLeft=TimerService.pomodoroLapDuration
    slot(timerIndicator,false,vertical)
    TimerService.countdownDuration=30;TimerService.countdownSecondsLeft=20
    slot(timerIndicator,true,vertical)
    TimerService.countdownSecondsLeft=0
    slot(timerIndicator,false,vertical)
    TimerService.countdownDuration=0
    TimerService.stopwatchTime=100
    slot(timerIndicator,true,vertical)
    TimerService.stopwatchTime=0
    slot(timerIndicator,false,vertical)
    ShellUpdates.hasUpdate=true
    slot(updateIndicator,true,vertical)
    ShellUpdates.hasUpdate=false;ShellUpdates.isUpdating=true
    slot(updateIndicator,true,vertical)
    ShellUpdates.isUpdating=false
    slot(updateIndicator,false,vertical)
   }
   console.info("BAR_AUXILIARY_INDICATORS_PASS native hidden/pinned/paused/finished/update slots on both orientations")
  }catch(error){console.error("BAR_AUXILIARY_INDICATORS_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(shell) as env:
        if env is None:
            raise SystemExit("SKIP: native indicators require private Niri")
        result = run_qs(shell, env, timeout=25)
    if result.returncode or "BAR_AUXILIARY_INDICATORS_PASS" not in result.stdout or any(
        token in result.stdout for token in ("BAR_AUXILIARY_INDICATORS_FAIL", "TypeError:",
                "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration")
    ):
        print(result.stdout)
        raise SystemExit(1)
print("BAR_AUXILIARY_INDICATORS_PASS")
