#!/usr/bin/env python3
"""Quickshell reload success uses notification ingress; Niri success stays silent."""
from pathlib import Path
import os
import shutil
import tempfile
from native_test_session import private_wayland, run_qs

repo = Path(__file__).resolve().parents[1]
if not shutil.which("qs") or not shutil.which("niri") or not shutil.which("notify-send") or not os.environ.get("WAYLAND_DISPLAY"):
    print("SKIP: reload notification requires Quickshell, Niri, notify-send and Wayland")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="alis-reload-notification-") as folder:
    root = Path(folder)
    for name in ("modules", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (root / name).symlink_to(repo / name)
    services = root / "services"
    services.mkdir()
    for entry in (repo / "services").iterdir():
        if entry.name != "Audio.qml":
            (services / entry.name).symlink_to(entry)
    # The actual sound gate runs; only the audio sink is replaced by a receipt.
    (services / "Audio.qml").write_text('''pragma Singleton
import Quickshell
Singleton {
 property int played: 0
 function playEvent(name): void { played++ }
}
''')
    config = root / "config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy(repo / "defaults/config.json", config / "config.json")
    (root / "shell.qml").write_text(r'''
//@ pragma ShellId alis-reload-notification-test
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
 id: root
 property int stage: 0
 property real since: Date.now()
 property bool finished: false
 property var hovered: []
 function check(ok,message): bool {
  if(ok)return true
  console.error("RELOAD_NOTIFICATION_FAIL",stage,message)
  finished=true;Qt.quit();return false
 }
 function advance(next) {stage=next;since=Date.now()}
 function find(title) {return Notifications.list.find(n=>n.summary===title)}
 ToastManager {id: manager}
 NotificationTimeoutHold {notifications:root.hovered;active:root.hovered.length>0}
 Process {id:ordinary;command:["notify-send","-a","Sound QA","-t","300","Audible ordinary","Fixture"]}
 Timer {interval:25;repeat:true;running:!root.finished;onTriggered:{
  const elapsed=Date.now()-root.since
  if(elapsed>4000){root.check(false,"stage deadline");return}
  if(root.stage===0 && Config.ready) {
   Notifications.ensureInitialized()
   Config.setNestedValue("sounds.notifications",true)
   Config.setNestedValue("notifications.silent",false)
   Config.setNestedValue("notifications.quietHours.enable",false)
   Config.setNestedValue("notifications.ignoreAppTimeout",false)
   Config.setNestedValue("reloadToasts.enable",true)
   root.advance(1)
  } else if(root.stage===1 && elapsed>200) {
   manager._pendingReloadSource="niri";manager._showReloadToast()
   root.advance(2)
  } else if(root.stage===2 && elapsed>250) {
   if(!root.check(!root.find("Niri Reloaded") && Notifications.list.filter(n=>n.appName==="Niri").length===0,
      "successful Niri reload remains silent"))return
   if(!root.check(manager.toasts.length===0 && Audio.played===0,
      "silent Niri reload creates no parallel toast or sound"))return
   manager._lastReloadToastTime=0
   manager._pendingReloadSource="quickshell";manager._showReloadToast()
   root.advance(3)
  } else if(root.stage===3 && root.find("Quickshell reloaded")) {
   const q=root.find("Quickshell reloaded")
   if(!root.check(q.isTransient && q.timer?.interval===2000 && q.notification.hints["suppress-sound"]===true,
      "Quickshell reload remains a transient silent notification"))return
   if(!root.check(manager.toasts.length===0 && Audio.played===0,
      "Quickshell reload creates no parallel toast body or sound"))return
   ordinary.running=true;root.advance(4)
  } else if(root.stage===4 && root.find("Audible ordinary")) {
   if(!root.check(Audio.played===1,"ordinary notifications keep their sound"))return
   Notifications.discardAllNotifications()
   Config.setNestedValue("reloadToasts.enable",false)
   manager._lastReloadToastTime=0
   manager._pendingReloadSource="quickshell";manager._showReloadToast()
   root.advance(5)
  } else if(root.stage===5 && elapsed>250) {
   if(!root.check(!root.find("Quickshell reloaded"),"disabled reload notifications stay suppressed"))return
   manager.addToast("Niri config reload failed","copyable error","error",true,6000,"error","red")
   if(!root.check(manager.toasts.length===1 && manager.toasts[0].isError
      && manager.toasts[0].title==="Niri config reload failed"
      && manager.toasts[0].message==="copyable error",
      "Niri failures retain their actionable toast route"))return
   manager.removeToast(manager.toasts[0].id)
   console.info("RELOAD_NOTIFICATION_PASS niri-success-silent quickshell-transient-silent ordinary-sound niri-error")
   root.finished=true;Qt.quit()
  }
 }}
}
''')
    # Owner fullscreen/Game Mode must not suppress this ordinary-ingress
    # fixture. Preserve the production suppression rules on a private output.
    with private_wayland(root) as env:
        if env is None:
            raise RuntimeError("Private Niri did not become available")
        env.update(QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic",
                   QT_QPA_PLATFORMTHEME="generic")
        result = run_qs(root,env,timeout=16)
    log = result.stdout + result.stderr
    if result.returncode or "RELOAD_NOTIFICATION_PASS" not in log or any(word in log for word in (
        "RELOAD_NOTIFICATION_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign",
        "is not a type", "Failed to load configuration")):
        print(log)
        raise SystemExit(1)
    print(next(line for line in log.splitlines() if "RELOAD_NOTIFICATION_PASS" in line))
