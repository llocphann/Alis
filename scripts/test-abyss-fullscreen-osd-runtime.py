#!/usr/bin/env python3
"""Volume/Brightness on physical edges above a real private Niri fullscreen client."""
import json
import os
import tempfile
from pathlib import Path

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-fullscreen-osd-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id: root
 property int frames: 0
 property int checks: 0
 property string commandError: ""
 Component.onCompleted: Quickshell.watchFiles = false
 AbyssPerimeter { id: perimeter }
 FloatingWindow {
  visible: true; title: "Alis synthetic fullscreen OSD"
  implicitWidth: 640; implicitHeight: 480; color: "#10242b"
 }
 Process {
  id: fullscreenCommand
  onExited: (code, status) => { if (code !== 0) root.commandError = "private fullscreen action failed: " + code }
 }
 TestCase {
  id: test; when: false; optional: true
  function check(value, message) { root.checks++; if (!value) throw new Error(message) }
  function visual(item, predicate) {
   if (predicate(item)) return item
   for (const child of item.children ?? []) { const found = visual(child, predicate); if (found) return found }
   return null
  }
  function frame(item) {
   const before = root.frames
   check(item.grabToImage(() => root.frames++), "private render request refused")
   tryVerify(() => root.frames > before, 3000)
   check(root.frames > before, "private render did not finish")
  }
  function toggleFullscreen(id) {
   fullscreenCommand.command = ["niri", "msg", "action", "fullscreen-window", "--id", String(id)]
   fullscreenCommand.running = true
   tryVerify(() => !fullscreenCommand.running, 4000)
   check(!root.commandError, root.commandError)
  }
  function runChecks() { try {
   tryCompare(Config, "ready", true, 6000)
   GlobalStates.shellEntryReady = true
   GlobalStates.deferredPanelsReady = true
   tryVerify(() => perimeter.outputHosts.length > 0 && perimeter.outputHosts[0].nativeFieldReady, 8000)
   const host = perimeter.outputHosts[0]
   check(host && host.nativeFieldReady, "native perimeter did not become ready")
   const osd = visual(host.contentItem, item => item.identity === "osd")
   const field = visual(host.contentItem, item => typeof item.packed === "function" && item.wallpaperReady !== undefined)
   check(osd && field, "production OSD/field missing")
   Config.setNestedValues({"osd.screenList": [host.outputName], "osd.timeout": 4000})
   wait(1600)
   GlobalStates.osdRequested("volume")
   tryVerify(() => osd.open && osd.ready, 3000)
   frame(field)
   check(osd.open && host.presented && field.visible, "normal Volume OSD did not open")
   check(osd.edgeInsets.top > 0, "normal OSD lost its Screen Edge inset")
   GlobalStates.osdDismissed()
   tryVerify(() => !osd.visualResident, 3000)
   tryVerify(() => NiriService.windows.some(window => window.title === "Alis synthetic fullscreen OSD"), 5000)
   const target = NiriService.windows.find(window => window.title === "Alis synthetic fullscreen OSD")
   check(target, "private client missing from Niri IPC")
   toggleFullscreen(target.id)
   tryVerify(() => host.fullscreenCovered, 5000)
   check(host.fullscreenCovered && !host.presented, "real fullscreen did not suppress ordinary shell surfaces")
   check(!field.visible && !osd.open, "fullscreen idle left an overlay visible")
   for (const kind of ["volume", "brightness"]) {
    for (const edge of ["top", "right", "bottom", "left"]) {
     Config.setNestedValue("abyss.positions", [{kind: kind, outputName: host.outputName, edge: edge, alignment: "center"}])
     GlobalStates.osdRequested(kind)
     tryVerify(() => osd.open && osd.ready, 2000)
     console.info("FULLSCREEN_OSD_RECEIPT", kind, edge, JSON.stringify({fullscreen: host.fullscreenCovered,
      normalSurfaces: host.presented, open: osd.open, fieldVisible: field.visible, insets: osd.edgeInsets}))
     check(osd.open && osd.ready, "fullscreen " + kind + " OSD did not open")
     tryVerify(() => osd.edge === edge && osd.progress >= .999, 3000)
     wait(100)
     frame(field)
     console.info("FULLSCREEN_OSD_GEOMETRY", edge, JSON.stringify({actualEdge: osd.edge, progress: osd.progress, record: osd.record.content, placement: osd.placement}))
     check(field.visible && !host.presented && !host.hoverProbeOutput().barVisible,
       "fullscreen OSD revealed ordinary Screen Edges/Panel")
     check(host.WlrLayershell.layer === WlrLayer.Overlay && host.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None,
       "fullscreen OSD has wrong layer/focus")
     check(field.records.length === 1 && field.records[0] === osd.record, "fullscreen field painted unrelated bodies")
     for (const side of ["top", "right", "bottom", "left"])
      check(osd.edgeInsets[side] === 0 && field.edgeInsets[side] === 0 && osd.controller.edgeInsets[side] === 0,
        "fullscreen OSD retained nonphysical inset " + side)
     const bounds = osd.inputBounds
     check(bounds.width > 0 && bounds.height > 0 && bounds.width * bounds.height < host.width * host.height / 2,
       "fullscreen OSD captured excess input")
     const content = osd.record.content
     const gap = edge === "top" ? content.y : edge === "left" ? content.x
       : edge === "bottom" ? host.height - content.y - content.height : host.width - content.x - content.width
     check(Math.abs(gap - osd.padding) < 1, "OSD detached from its physical edge: " + edge + " gap=" + gap)
     GlobalStates.osdRequested(kind)
     check(osd.open, "rapid repeat dismissed the OSD")
     GlobalStates.osdDismissed()
     tryVerify(() => !osd.visualResident, 3000)
     check(!field.visible && !osd.open && osd.inputBounds.width === 0 && host.WlrLayershell.layer === WlrLayer.Top,
       "fullscreen OSD retained paint/input/layer after close")
    }
   }
   for (const kind of ["mic", "keyboardLayout", "voiceSearch"]) {
    GlobalStates.osdRequested(kind); wait(100)
    check(!osd.open && !field.visible && !host.physicalOsdResident, "unrelated fullscreen OSD revealed the field: " + kind)
    GlobalStates.osdDismissed()
   }
   Config.setNestedValue("osd.screenList", ["fixture-other-output"])
   GlobalStates.osdRequested("volume"); wait(100)
   // Existing target policy falls back when every configured output is absent.
   check(osd.open && field.visible && !host.presented, "disconnected OSD target did not preserve existing fallback")
   GlobalStates.osdDismissed()
   Config.setNestedValue("osd.screenList", [host.outputName])
   Config.setNestedValue("osd.timeout", 300)
   GlobalStates.osdRequested("volume")
   tryVerify(() => osd.open, 1000)
   tryVerify(() => !osd.visualResident, 3000)
   check(!osd.open && !field.visible, "fullscreen OSD timeout stuck")
   GlobalStates.screenLocked = true
   GlobalStates.osdRequested("brightness"); wait(80)
   check(!osd.open && !field.visible && !host.visible, "lock exposed fullscreen OSD")
   GlobalStates.osdDismissed(); GlobalStates.screenLocked = false
   toggleFullscreen(target.id)
   tryVerify(() => !host.fullscreenCovered && host.presented, 5000)
   Config.setNestedValue("osd.timeout", 4000)
   GlobalStates.osdRequested("volume")
   tryVerify(() => osd.open && field.visible, 3000)
   check(osd.open && host.presented && osd.edgeInsets.top > 0, "leaving fullscreen did not restore normal attachment")
   GlobalStates.osdDismissed()
   console.info("FULLSCREEN_OSD_PASS", root.checks)
  } catch (e) { console.error("FULLSCREEN_OSD_FAIL", e.message, e.stack) } Qt.quit() }
 }
 Timer { interval: 100; running: true; onTriggered: test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: physical-edge OSD requires private Niri")
        # No connection to the owner's audio/session runtime during this UI test.
        runtime = folder / "private-runtime"
        runtime.mkdir(mode=0o700)
        env = dict(env, WAYLAND_DISPLAY=str(Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / env["WAYLAND_DISPLAY"]),
                   XDG_RUNTIME_DIR=str(runtime), QSG_RHI_BACKEND="opengl")
        config = folder / "config/alis/config.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["enabledPanels"] = ["abyssPerimeter", "abyssBar", "abyssOnScreenDisplay"]
        data["abyss"]["companion"]["enabled"] = False
        data["abyss"]["perimeter"]["visibleInFullscreen"] = False
        data["abyss"]["waves"]["enabled"] = False
        data["performance"]["reduceAnimations"] = True
        data["gameMode"].update(autoDetect=False, disableDiscoverOverlay=False, disableNiriAnimations=False)
        config.write_text(json.dumps(data))
        result = run_qs(folder, env, timeout=110)
        receipt = os.environ.get("ALIS_FULLSCREEN_OSD_LOG")
        if receipt:
            Path(receipt).write_text(result.stdout)
        if result.returncode or "FULLSCREEN_OSD_PASS" not in result.stdout or any(token in result.stdout for token in
                ["FULLSCREEN_OSD_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]):
            print(result.stdout)
            raise SystemExit(1)
        print("PASS: real private fullscreen Volume/Brightness, four physical edges, timeout/lock/normal restoration")
