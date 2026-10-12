#!/usr/bin/env python3
"""Real private D-Bus notifications, Qt timers and shared hover-hold lifecycle."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
if not shutil.which("qs") or not shutil.which("notify-send"):
    print("SKIP: notification lifetime requires Quickshell and notify-send")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="hadalis-notification-timeout-") as folder:
    root = Path(folder)
    for name in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (root / name).symlink_to(repo / name)
    config = root / "config/illogical-impulse"
    config.mkdir(parents=True)
    fixture_config = json.loads((repo / "defaults/config.json").read_text())
    # This headless lifetime oracle does not exercise fullscreen suppression
    # or change the owner's compositor animations. Those policies have their
    # own coverage; owner fullscreen state must not consume this timer fixture.
    fixture_config["gameMode"]["autoDetect"] = False
    fixture_config["gameMode"]["disableNiriAnimations"] = False
    (config / "config.json").write_text(json.dumps(fixture_config))
    seed = int(os.environ.get("HADALIS_TEST_NOTIFICATION_HISTORY_ID", "0"))
    if seed:
        history = root / "state/quickshell/user/notifications.json"
        history.parent.mkdir(parents=True)
        history.write_text(json.dumps([{"notificationId":seed,"summary":"history seed",
            "appName":"History QA","time":1,"actions":[],"body":"","image":"",
            "appIcon":"","urgency":"normal"}]))
    (root / "shell.qml").write_text(r'''
//@ pragma ShellId hadalis-notification-timeout-test
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
 id:root
 property int stage:0
 property real since:Date.now()
 property real remaining:0
 property var held:[]
 property bool hoverA:false
 property bool hoverB:false
 property bool failed:false
 property var pausedNotification:null
 property var pausedTimer:null
 property int initialOffset:0
 function advance(value) {stage=value;since=Date.now()}
 function check(ok,message): bool {
  if(ok)return true
  console.error("NOTIFICATION_TIMEOUT_FAIL",stage,message)
  root.failed=true;Qt.quit();return false
 }
 function find(title) {return Notifications.list.find(n=>n.summary===title)}
 function send(title,ms,urgency="normal",transient=false) {
  sender.command=["notify-send","-a","Lifetime QA","-t",String(ms),"-u",urgency,
   "-h","boolean:transient:"+(transient ? "true" : "false"),title,"Private fixture"]
  sender.running=true
 }
 Process {id:sender}
 Loader {id:ownerA;active:true;sourceComponent:NotificationTimeoutHold {notifications:root.held;active:root.hoverA}}
 Loader {id:ownerB;active:true;sourceComponent:NotificationTimeoutHold {notifications:root.held;active:root.hoverB}}
 Timer {interval:30;running:!root.failed;repeat:true;onTriggered:{
  const elapsed=Date.now()-root.since
  if(elapsed>4500) {root.check(false,"stage deadline");return}
  if(root.stage===0 && Config.ready) {
   Notifications.ensureInitialized()
   Config.setNestedValue("sounds.notifications",false)
   Config.setNestedValue("notifications.silent",false)
   Config.setNestedValue("notifications.quietHours.enable",false)
   Config.setNestedValue("notifications.useLegacyCounter",false)
   Config.setNestedValue("notifications.ignoreAppTimeout",false)
   Config.setNestedValue("notifications.timeoutNormal",650)
   root.send("paused",1800);root.advance(1)
  } else if(root.stage===1 && root.find("paused")) {
   const n=root.find("paused")
   if(!root.check(Notifications.idOffset===Number(Quickshell.env("HADALIS_TEST_NOTIFICATION_HISTORY_ID") || "0")
      && n.notificationId===n.notification.id+Notifications.idOffset,"cold ingress uses the persisted native ID offset"))return
   if(!root.check(n.popup && n.timer?.interval===1800 && n.notification.expireTimeout===1800,
      "native app timeout preserves 1800 ms; popup="+n.popup+" interval="+n.timer?.interval+" native="+n.notification.expireTimeout))return
   root.pausedNotification=n;root.pausedTimer=n.timer;root.initialOffset=Notifications.idOffset
   root.held=[n];root.advance(2)
  } else if(root.stage===2 && elapsed>300) {
   root.hoverA=true;root.hoverB=true
   const t=root.find("paused").timer
   if(!root.check(!t.running && t.hoverOwners.length===2 && t.remainingMs>1100 && t.remainingMs<1600,
      "two outputs preserve the spent part of the timeout"))return
   root.remaining=t.remainingMs;root.advance(3)
  } else if(root.stage===3 && elapsed>1950) {
   if(!root.check(root.find("paused")?.popup,"hover stays readable beyond its initial deadline"))return
   Notifications.refresh();root.advance(18)
  } else if(root.stage===18 && elapsed>120) {
   if(!root.check(root.find("paused")===root.pausedNotification
      && root.find("paused").timer===root.pausedTimer
      && !root.pausedTimer.running && root.pausedTimer.hoverOwners.length===2
      && Notifications.idOffset===root.initialOffset,"history refresh replaced a live wrapper, timer or ID offset"))return
   ownerA.active=false;root.advance(4)
  } else if(root.stage===4 && elapsed>120) {
   const t=root.find("paused").timer
   if(!root.check(!t.running && t.hoverOwners.length===1,"retiring one output releases only its hold"))return
   root.hoverB=false
   if(!root.check(t.running && t.interval===root.remaining,"leave resumes remaining time without resetting it"))return
   root.advance(5)
  } else if(root.stage===5 && elapsed>250) {
   if(!root.check(root.find("paused")?.popup,"leave does not dismiss immediately"))return
   root.advance(6)
  } else if(root.stage===6 && root.find("paused")?.popup===false) {
   if(!root.check(root.find("paused").timer===null,"expiry clears its timer while history survives"))return
   Config.setNestedValue("notifications.ignoreAppTimeout",true)
   root.hoverB=true;root.held=[]
   root.send("late-arrival",80);root.advance(7)
  } else if(root.stage===7 && root.find("late-arrival")) {
   const n=root.find("late-arrival")
   if(!root.check(n.timer?.interval===650,"ignore-app preference uses configured milliseconds"))return
   root.held=[n]
   if(!root.check(!n.timer.running,"new notification joins an already-hovered group"))return
   root.advance(8)
  } else if(root.stage===8 && elapsed>800) {
   if(!root.check(root.find("late-arrival")?.popup,"new hovered notification keeps its lifetime"))return
   ownerB.active=false;root.advance(9)
  } else if(root.stage===9 && elapsed>100) {
   if(!root.check(root.find("late-arrival")?.timer?.running,"delegate destruction resumes its hold"))return
   Notifications.markAllRead()
   if(!root.check(root.find("late-arrival")?.popup===false && root.find("late-arrival")?.timer===null,
      "mark-read releases timed popup resources"))return
   Config.setNestedValue("notifications.ignoreAppTimeout",false)
   root.send("ordinary",450);root.advance(10)
  } else if(root.stage===10 && root.find("ordinary")) {
   if(!root.check(root.find("ordinary")?.timer?.interval===450,"ordinary popup respects app timeout"))return
   root.advance(11)
  } else if(root.stage===11 && root.find("ordinary")?.popup===false) {
   if(!root.check(elapsed>200,"unhovered popup actually waits rather than confusing seconds and ms"))return
   Config.setNestedValue("notifications.maxPopupLifetime",300)
   root.send("persistent-capped",0);root.advance(12)
  } else if(root.stage===12 && root.find("persistent-capped")) {
   if(!root.check(root.find("persistent-capped")?.timer?.interval===300,"persistent request keeps configured cap"))return
   root.advance(13)
  } else if(root.stage===13 && root.find("persistent-capped")?.popup===false) {
   Config.setNestedValue("notifications.ignoreAppTimeout",true)
   Config.setNestedValue("notifications.maxPopupLifetime",0)
   Config.setNestedValue("notifications.timeoutCritical",0)
   root.send("critical-persistent",0,"critical");root.advance(14)
  } else if(root.stage===14 && root.find("critical-persistent")) {
   if(!root.check(root.find("critical-persistent")?.timer===null,"explicit uncapped critical stays untimed"))return
   root.advance(15)
  } else if(root.stage===15 && elapsed>450) {
   if(!root.check(root.find("critical-persistent")?.popup,"uncapped critical is still visible"))return
   // The render/group cache is deliberately stale. Retract the live
   // notification rather than trusting the last debounced popupList.
   Notifications.popupList=[]
   Notifications.timeoutAll()
   if(!root.check(!root.find("critical-persistent")?.popup,"stale cache left a live popup visible"))return
   if(!root.check(root.find("critical-persistent")?.timer===null,
      "stale cache left a timer after retract"))return
   Config.setNestedValue("notifications.ignoreAppTimeout",false)
   root.send("transient",350,"normal",true);root.advance(16)
  } else if(root.stage===16 && root.find("transient")) {
   if(!root.check(root.find("transient")?.isTransient,"real transient hint reaches the service"))return
   root.advance(17)
  } else if(root.stage===17 && !root.find("transient")) {
   console.info("NOTIFICATION_TIMEOUT_PASS app-ms configured-ms two-output hover remaining lifetime arrival retirement history critical transient")
   Qt.quit();root.failed=true
  }
 }}
}
''')
    env = os.environ.copy()
    for name in ("QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST"):
        env.pop(name, None)
    env.update(QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1", XDG_CONFIG_HOME=str(root / "config"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"))
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root), "--no-color"],
                            env=env, capture_output=True, text=True, timeout=22)
    log = result.stdout + result.stderr
    if result.returncode or "NOTIFICATION_TIMEOUT_PASS" not in log or any(word in log for word in (
        "NOTIFICATION_TIMEOUT_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign",
        "is not a type", "Type .* unavailable", "Failed to load configuration")):
        print(log)
        raise SystemExit(1)
    print(next(line for line in log.splitlines() if "NOTIFICATION_TIMEOUT_PASS" in line))
