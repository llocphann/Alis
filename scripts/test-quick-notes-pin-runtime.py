#!/usr/bin/env python3
"""Exercise the real shared Notes/Timers pin lifecycle in a private Qt scene."""
from pathlib import Path
import os, shutil, subprocess, tempfile
from native_test_session import private_wayland

ROOT = Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: Notes pin runtime requires Quickshell")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="alis-notes-pin-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    config = folder / "config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy(ROOT / "defaults/config.json", config / "config.json")
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.screenCorners
import qs.modules.abyss
import qs.services
ShellRoot {
 id: root
 Component.onCompleted: Quickshell.watchFiles=false
 property int step: 0
 property int ticks: 0
 property bool hovering: false
 function check(ok, message): bool {
  if (ok) return true
  console.error("NOTES_PIN_FAIL", message); Qt.quit(); return false
 }
 function find(item, predicate) {
  if (predicate(item)) return item
  for (const child of item.children ?? []) {
   const found = find(child, predicate)
   if (found) return found
  }
  return null
 }
 AbyssSurfaceController {
  id: controller
  presentationItem: scene
  outputWidth: scene.width; outputHeight: scene.height
  edgeInsets: ({left:16, right:16, top:16, bottom:16})
 }
 FloatingWindow {
  visible: true; implicitWidth: 900; implicitHeight: 750; color: "#111820"
  Item {
   id: scene; anchors.fill: parent
   Item {
    id: anchor; x: 0; y: scene.height - 16; width: 16; height: 16
    property bool containsMouse: root.hovering
    property var liquidController: controller
    property string kind: "quickNotes"
    property string popupAttachmentEdge: "bottom"
   }
   AbyssBodyHost {
    id: host; anchors.fill: parent; identity: "styledPopup0"; edge: "bottom"
    controller: controller; open: popup.presentationActive
    externalProgress: popup.revealProgress; embeddedItem: popup.contentItem
    span: 420; depth: 300; padding: 14; along: 16
    edgeInsets: controller.edgeInsets
    Component.onCompleted: controller.registerPopupHost(0, host)
   }
  }
 }
 QuickNotesPopup { id: popup; anchorItem: anchor }
 Timer {
  interval: 180; running: true; repeat: true
  onTriggered: {
   if (++root.ticks > 90) { root.check(false, "scene did not settle"); return }
   if (!Config.ready) return
   if (root.step === 0) {
    Config.setNestedValue("panelFamily", "abyss"); root.hovering = true
   } else if (root.step === 3) {
    const pin = root.find(popup.contentItem, item => item.text === "push_pin")
    if (!root.check(pin && pin.width >= 24 && pin.height >= 24, "Pin has a usable hit target")) return
    pin.clicked()
    if (!root.check(popup.popupPinned, "Notes Pin click holds the popup")) return
    root.hovering = false
   } else if (root.step === 9) {
    if (!root.check(popup.presentationActive && popup.requestedVisible, "Pin survives pointer departure")) return
    const group = root.find(popup.contentItem, item => item.objectName === "quickNotesIndicatorGroup")
    const add = root.find(group, item => item.objectName === "quickNotesAdd")
    const remove = root.find(group, item => item.objectName === "quickNotesRemove")
    if (!root.check(group && add && remove && add.visible, "note lifecycle actions share the indicator group")) return
    const count = Notepad.tabs.length
    add.clicked()
    if (!root.check(Notepad.tabs.length === count + 1, "grouped Add creates a note")) return
    remove.clicked()
    if (!root.check(Notepad.tabs.length === count, "grouped Remove removes only the selected note")) return
    popup.editorFocused = true
    popup.requestClose()
    if (!root.check(popup.popupPinned && !popup.editorFocused, "outside click releases editing while retaining Pin")) return
    popup.selectedMainTab = 1
   } else if (root.step === 12) {
    if (!root.check(popup.popupPinned && popup.presentationActive, "Timers uses the same held popup")) return
    popup.dismissPresentation()
    if (!root.check(!popup.popupPinned && !popup.requestedVisible, "explicit dismissal releases Pin")) return
   } else if (root.step === 16) {
    root.hovering = true
   } else if (root.step === 20) {
    const pin = root.find(popup.contentItem, item => item.text === "push_pin")
    pin.clicked()
    if (!root.check(popup.popupPinned && popup.presentationActive, "Timers can pin after a dismissed lease")) return
    pin.clicked(); root.hovering = false
   } else if (root.step === 26) {
    if (!root.check(!popup.popupPinned && !popup.presentationActive, "Unpin returns to normal hover lifetime")) return
    console.info("NOTES_PIN_PASS notes timers hover editing dismissal reopen unpin grouped-add-remove"); Qt.quit()
   }
   root.step++
  }
 }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Notes pin runtime requires a private Niri Wayland session")
            raise SystemExit(0)
        result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(folder), "--no-color"],
                                env=env, text=True, capture_output=True, timeout=25)
    output = result.stdout + result.stderr
    errors = ["NOTES_PIN_FAIL", "ReferenceError:", "TypeError:", "Binding loop",
              "Unable to assign", "is not a type"]
    if result.returncode or "NOTES_PIN_PASS" not in output or any(error in output for error in errors):
        print(output)
        raise SystemExit(1)
    for line in output.splitlines():
        if "NOTES_PIN_PASS" in line:
            print(line)
