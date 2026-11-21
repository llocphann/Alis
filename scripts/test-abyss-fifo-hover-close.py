#!/usr/bin/env python3
"""Silent regression test for Abyss global FIFO hover-order close sequencer.

Covers:
1. Edgebar -> Left Sidebar hover order: Edgebar closes strictly BEFORE Left Sidebar,
   even when Edgebar has a longer grace/bridge delay than Sidebar.
2. Left Sidebar -> Edgebar reverse order: Left Sidebar closes strictly BEFORE Edgebar,
   even when Edgebar's transfer timer finishes earlier than Sidebar's close delay.
3. 3-surface non-stalling: when Edgebar (order 1) is kept open by pairedSidebarHovered
   via Left Sidebar (order 2), a 3rd popup (order 3) losing hover closes immediately
   without stalling for fifoWaitCapMs.
4. Re-hovering an earlier unhovered surface immediately unblocks a waiting later surface.
5. Source contracts in AbyssPerimeter, AbyssSidebarReveal, QuickNotesPopup, and
   NotificationCenterPopup.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def test_source_contracts() -> None:
    perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    assert "function _syncFifoHover()" in perimeter, "AbyssPerimeter must route styledPopupHost hover through _syncFifoHover()"
    assert "if (directHovered || (open && effectiveContentHovered))" in perimeter, (
        "AbyssPerimeter must preserve active hover in FIFO state when pairedSidebarHovered holds popup open"
    )
    assert "fifoWaitCapMs: Math.max(850," in perimeter, (
        "AbyssPerimeter fifoWaitCapMs must exceed QuickNotes/NotificationCenter grace bridges"
    )

    reveal = (ROOT / "modules/abyss/AbyssSidebarReveal.qml").read_text(encoding="utf-8")
    assert "if (root.directHovered || (root.open && root.hovered))" in reveal, (
        "AbyssSidebarReveal must preserve active hover in FIFO state when peerHovered holds sidebar open"
    )

    qn = (ROOT / "modules/screenCorners/QuickNotesPopup.qml").read_text(encoding="utf-8")
    assert "onPopupHoveredChanged:" in qn and "root.entryBridgeHeld = false" in qn, (
        "QuickNotesPopup must release entryBridgeHeld once pointer enters popup body"
    )

    nc = (ROOT / "modules/notificationCenter/NotificationCenterPopup.qml").read_text(encoding="utf-8")
    assert "onPopupHoveredChanged:" in nc and "root.entryBridgeHeld = false" in nc, (
        "NotificationCenterPopup must release entryBridgeHeld once pointer enters popup body"
    )

    assert "readonly property bool fifoAutoClosable:" in perimeter and "if (dock.fifoAutoClosable)" in perimeter, (
        "AbyssPerimeter Dock hover/close must gate FIFO participation on dock.fifoAutoClosable"
    )
    gen = (ROOT / "modules/abyss/AbyssGenericPopupPresenter.qml").read_text(encoding="utf-8")
    assert "root.controller.clearHoverSurface(identity)" in gen, (
        "AbyssGenericPopupPresenter must clear FIFO surface entry when body closes"
    )
    pc = (ROOT / "modules/abyss/content/AbyssPopupContent.qml").read_text(encoding="utf-8")
    assert "ctrl.noteHoverSurfaceActive(pid, !root.editorFocusHeld)" in pc and "ctrl.cancelHoverSurfaceClose(pid)" in pc, (
        "AbyssPopupContent must cancel pending close on hover and mark editorFocusHeld non-auto-closable"
    )
    print("FIFO_SOURCE_CONTRACT_PASS")


QML_HARNESS = r'''//@ pragma ShellId alis-fifo-hover-close-test
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.modules.abyss

ShellRoot {
    id: root
    property int checks: 0

    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    AbyssSurfaceController {
        id: ctrl
        outputName: "TEST-1"
        fifoCloseStepMs: 80
        fifoWaitCapMs: 850
    }

    // Simulated SidebarReveal wired to the real AbyssSurfaceController
    AbyssSidebarReveal {
        id: leftSidebar
        controller: ctrl
        surfaceId: "leftPanel"
        available: true
        open: true
        ownedOpen: true
        closeDelay: 90
        onHideRequested: {
            open = false
            ctrl.clearHoverSurface("leftPanel")
        }
    }

    TestCase {
        id: tc
        when: false
        optional: true

        function resetCtrl() {
            ctrl._fifoHoverSeq = 0
            ctrl._fifoHoverState = ({})
            ctrl._fifoLastClosedId = ""
            ctrl._fifoStaggerTimer.stop()
            ctrl._fifoWaitTimer.stop()
            ctrl._fifoBatchTimer.stop()
        }

        function run() {
            try {
                // ── Case 1: Edgebar hovered FIRST (order 1), Left Sidebar hovered SECOND (order 2) ──
                // Simulate Edgebar having a longer bridge/grace hold (320ms) than Sidebar (100ms).
                // Sidebar requests close first; FIFO sequencer must wait and close Edgebar BEFORE Sidebar.
                resetCtrl()
                let closed = []
                let times = ({})
                ctrl.noteHoverSurfaceActive("styledPopup0", true)
                ctrl.noteHoverSurfaceLeave("styledPopup0", true) // brief gap crossing
                ctrl.noteHoverSurfaceActive("leftPanel", true)
                // Paired sidebar keeps Edgebar active, preserving order 1!
                ctrl.noteHoverSurfaceActive("styledPopup0", true)
                root.check(ctrl.hoverOrderFor("styledPopup0") === 1, "Edgebar order should stay 1, got " + ctrl.hoverOrderFor("styledPopup0"))
                root.check(ctrl.hoverOrderFor("leftPanel") === 2, "Left Sidebar order should be 2, got " + ctrl.hoverOrderFor("leftPanel"))
                root.check(ctrl._fifoHoverState["styledPopup0"].hovered === true, "Edgebar should be hovered=true while paired sidebar holds it")

                // Pointer leaves both to desktop
                ctrl.noteHoverSurfaceLeave("leftPanel", true)
                ctrl.noteHoverSurfaceLeave("styledPopup0", true)

                // Sidebar finishes its shorter closeDelay first and requests close
                ctrl.requestHoverSurfaceClose("leftPanel", () => {
                    closed.push("leftPanel")
                    times["leftPanel"] = Date.now()
                    ctrl.clearHoverSurface("leftPanel")
                })
                wait(140)
                root.check(closed.length === 0, "Sidebar must wait for earlier-hovered Edgebar, got " + JSON.stringify(closed))

                // Edgebar finishes its longer grace hold and requests close
                ctrl.requestHoverSurfaceClose("styledPopup0", () => {
                    closed.push("styledPopup0")
                    times["styledPopup0"] = Date.now()
                    ctrl.clearHoverSurface("styledPopup0")
                })
                tryVerify(() => closed.length === 2, 1500)
                root.check(closed[0] === "styledPopup0" && closed[1] === "leftPanel",
                    "Case 1 FIFO violated: expected [styledPopup0, leftPanel], got " + JSON.stringify(closed))
                root.check((times["leftPanel"] - times["styledPopup0"]) >= 55,
                    "Case 1 stagger too small: " + (times["leftPanel"] - times["styledPopup0"]) + "ms")

                // ── Case 2: Reverse order — Left Sidebar FIRST (order 1), Edgebar SECOND (order 2) ──
                // Edgebar finishes its 90ms timer before Sidebar's 240ms closeDelay;
                // Left Sidebar MUST close strictly BEFORE Edgebar.
                resetCtrl()
                closed = []
                times = ({})
                ctrl.noteHoverSurfaceActive("leftPanel", true)
                ctrl.noteHoverSurfaceActive("styledPopup0", true)
                root.check(ctrl.hoverOrderFor("leftPanel") < ctrl.hoverOrderFor("styledPopup0"), "Reverse order check failed")
                ctrl.noteHoverSurfaceLeave("styledPopup0", true)
                ctrl.noteHoverSurfaceLeave("leftPanel", true)

                ctrl.requestHoverSurfaceClose("styledPopup0", () => {
                    closed.push("styledPopup0")
                    times["styledPopup0"] = Date.now()
                    ctrl.clearHoverSurface("styledPopup0")
                })
                wait(120)
                root.check(closed.length === 0, "Edgebar must wait for earlier-hovered Left Sidebar")

                ctrl.requestHoverSurfaceClose("leftPanel", () => {
                    closed.push("leftPanel")
                    times["leftPanel"] = Date.now()
                    ctrl.clearHoverSurface("leftPanel")
                })
                tryVerify(() => closed.length === 2, 1500)
                root.check(closed[0] === "leftPanel" && closed[1] === "styledPopup0",
                    "Case 2 Reverse FIFO violated: expected [leftPanel, styledPopup0], got " + JSON.stringify(closed))

                // ── Case 3: 3-surface non-stalling when paired surface holds order-1 open ──
                resetCtrl()
                closed = []
                ctrl.noteHoverSurfaceActive("styledPopup0", true) // order 1
                ctrl.noteHoverSurfaceLeave("styledPopup0", true)
                ctrl.noteHoverSurfaceActive("leftPanel", true)    // order 2
                // Paired sidebar keeps styledPopup0 active (order 1, hovered=true)
                ctrl.noteHoverSurfaceActive("styledPopup0", true)
                ctrl.noteHoverSurfaceActive("styledPopup1", true) // order 3 (unrelated 3rd popup)
                ctrl.noteHoverSurfaceLeave("styledPopup1", true)

                const t0 = Date.now()
                ctrl.requestHoverSurfaceClose("styledPopup1", () => {
                    closed.push("styledPopup1")
                    ctrl.clearHoverSurface("styledPopup1")
                })
                tryVerify(() => closed.length === 1, 500)
                const elapsed = Date.now() - t0
                root.check(closed[0] === "styledPopup1" && elapsed < 260,
                    "Case 3 3rd popup stalled (" + elapsed + "ms) despite earlier surfaces being hovered")

                // ── Case 4: Re-hovering earlier unhovered surface immediately unblocks waiting later surface ──
                resetCtrl()
                closed = []
                ctrl.noteHoverSurfaceActive("styledPopup0", true)
                ctrl.noteHoverSurfaceActive("styledPopup1", true)
                ctrl.noteHoverSurfaceLeave("styledPopup0", true)
                ctrl.noteHoverSurfaceLeave("styledPopup1", true)
                ctrl.requestHoverSurfaceClose("styledPopup1", () => {
                    closed.push("styledPopup1")
                    ctrl.clearHoverSurface("styledPopup1")
                })
                wait(60)
                root.check(closed.length === 0, "Case 4 later popup should initially wait on earlier unhovered popup")
                const tRehover = Date.now()
                ctrl.noteHoverSurfaceActive("styledPopup0", true)
                tryVerify(() => closed.length === 1, 300)
                root.check(closed[0] === "styledPopup1" && (Date.now() - tRehover) < 200,
                    "Case 4 re-hovering earlier surface failed to unblock later popup promptly")

                // ── Case 5: AbyssSidebarReveal peerHovered preserves hovered=true in FIFO state ──
                resetCtrl()
                leftSidebar.open = true
                leftSidebar.ownedOpen = true
                leftSidebar.edgeHovered = true
                wait(20)
                root.check(ctrl.hoverOrderFor("leftPanel") === 1, "SidebarReveal did not register order 1")
                leftSidebar.edgeHovered = false
                wait(20)
                root.check(ctrl._fifoHoverState["leftPanel"].hovered === false, "SidebarReveal did not mark leave")
                leftSidebar.peerHovered = true
                wait(20)
                root.check(ctrl.hoverOrderFor("leftPanel") === 1 && ctrl._fifoHoverState["leftPanel"].hovered === true,
                    "SidebarReveal peerHovered must restore hovered=true while preserving order 1")
                leftSidebar.peerHovered = false

                console.info("FIFO_RUNTIME_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("FIFO_RUNTIME_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 60
        running: true
        repeat: false
        onTriggered: tc.run()
    }
}
'''


def test_runtime() -> None:
    qs = shutil.which("qs")
    if not qs:
        print("SKIP: qs unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-fifo-test-") as tmp:
        root = Path(tmp)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
            (root / entry).symlink_to(ROOT / entry)
        (root / "shell.qml").write_text(QML_HARNESS, encoding="utf-8")

        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(root / "config")
        env["XDG_STATE_HOME"] = str(root / "state")
        env["XDG_CACHE_HOME"] = str(root / "cache")
        env["XDG_DATA_HOME"] = "/nonexistent"
        env["XDG_DATA_DIRS"] = "/nonexistent"
        (root / "config/illogical-impulse").mkdir(parents=True, exist_ok=True)
        (root / "config/illogical-impulse/config.json").write_text(
            (ROOT / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8"
        )

        res = subprocess.run(
            [qs, "-p", str(root / "shell.qml"), "--no-color"],
            env=env,
            capture_output=True,
            text=True,
            timeout=25,
        )
        out = (res.stdout or "") + "\n" + (res.stderr or "")
        if res.returncode != 0 or "FIFO_RUNTIME_PASS" not in out or re.search(r"FIFO_RUNTIME_FAIL|ReferenceError:|TypeError:", out):
            print(out)
            sys.exit(1)
        for line in out.splitlines():
            if "FIFO_RUNTIME_PASS" in line:
                print(line.strip())


if __name__ == "__main__":
    test_source_contracts()
    test_runtime()
