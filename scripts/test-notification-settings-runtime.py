#!/usr/bin/env python3
"""Notification Settings use the actual Abyss editor and retain other families."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
if not shutil.which("qs") or not os.environ.get("WAYLAND_DISPLAY"):
    print("SKIP: notification Settings requires Quickshell/Wayland")
    raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix="alis-notification-settings-") as folder:
    root = Path(folder)
    for name in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (root / name).symlink_to(repo / name)
    config = root / "config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy(repo / "defaults/config.json", config / "config.json")
    (root / "shell.qml").write_text(r'''
//@ pragma ShellId alis-notification-settings-test
import QtQuick
import Quickshell
import qs.modules.common
import "modules/abyss/looks/AbyssPresentation.js" as Presentation
ShellRoot {
 id:root
 property int stage:0
 property int ticks:0
 property bool failed:false
 property string originalAnchor:""
 function check(ok,message): bool {
  if(ok)return true
  console.error("NOTIFICATION_SETTINGS_FAIL",stage,message);failed=true;Qt.quit();return false
 }
 function find(item,predicate) {
  if(!item)return null
  if(predicate(item))return item
  for(const child of item.children ?? []) {const match=find(child,predicate);if(match)return match}
  return null
 }
 function editor() {return root.find(page.item,i=>i.allowedKinds?.length===1 && i.allowedKinds[0]==="notifications")}
 FloatingWindow {visible:true;implicitWidth:1100;implicitHeight:850;color:"#111820"
  Loader {id:page;anchors.fill:parent}
 }
 Timer {interval:150;running:!root.failed;repeat:true;onTriggered:{
  if(root.ticks++>75){root.check(false,"deadline");return}
  if(!Config.ready)return
  if(root.stage===0){
   Config.setNestedValue("panelFamily","abyss")
   Config.setNestedValue("performance.reduceAnimations",true)
   root.originalAnchor=Config.options.notifications.position
   page.source="modules/settings/InterfaceConfig.qml";root.stage++
  } else if(root.stage===1 && page.status===Loader.Ready){page.item.activeSection="notifications";root.stage++
  } else if(root.stage===2){
   const anchor=root.find(page.item,i=>i.title==="Anchor")
   const e=root.editor()
   if(!root.check(anchor!==null && !anchor.visible && e!==null && e.visible,"Abyss replaces corner Anchor with the shared free-position editor"))return
   const ignore=root.find(page.item,i=>i.text==="Ignore app timeout" && i.checked!==undefined)
   if(!root.check(ignore!==null,"configured/app timeout choice is available"))return
   ignore.checked=true
   if(!root.check(Config.options.notifications.ignoreAppTimeout,"choice updates the existing service preference"))return
   e.outputName="QA-output";e.change("edge","left");e.change("alignment","custom");e.change("position",.73)
   root.stage++
  } else if(root.stage===3){
   const p=Presentation.resolve(Config.options.abyss.positions,"notifications","QA-output")
   if(!root.check(p.edge==="left" && p.alignment==="custom" && p.position===.73,"output-specific free position uses the canonical store"))return
   if(!root.check(Config.options.notifications.position===root.originalAnchor,"free placement does not write the other families' anchor"))return
   Config.setNestedValue("panelFamily","waffle");root.stage++
  } else if(root.stage===4){
   if(!root.check(!page.item.isIiActive && !root.editor().visible && Config.options.notifications.position===root.originalAnchor,
      "Waffle keeps its separate Settings and existing anchor preference"))return
   Config.setNestedValue("panelFamily","abyss");root.stage++
  } else if(root.stage===5){
   if(!root.check(root.editor().visible,"returning to Abyss restores its editor"))return
   root.editor().apply(null)
   if(!root.check(!Presentation.resolve(Config.options.abyss.positions,"notifications","QA-output").edge,"reset clears only the chosen override"))return
   console.info("NOTIFICATION_SETTINGS_PASS free-position per-output store reset configured-timeout waffle-family")
   root.failed=true;Qt.quit()
  }
 }}
}
''')
    env = os.environ.copy()
    for name in ("QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST"):
        env.pop(name, None)
    env.update(QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software",
               XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
               XDG_CACHE_HOME=str(root / "cache"))
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root), "--no-color"],
                            env=env, capture_output=True, text=True, timeout=20)
    log = result.stdout + result.stderr
    if result.returncode or "NOTIFICATION_SETTINGS_PASS" not in log or any(word in log for word in (
        "NOTIFICATION_SETTINGS_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign",
        "is not a type", "Failed to load configuration")):
        print(log)
        raise SystemExit(1)
    print(next(line for line in log.splitlines() if "NOTIFICATION_SETTINGS_PASS" in line))
