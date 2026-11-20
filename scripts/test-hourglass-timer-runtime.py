#!/usr/bin/env python3
"""Silent offscreen Quickshell runtime test for Hourglass timer & bar icons."""
import json
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]

QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sidebarRight.pomodoro

Window {
    id: root
    visible: true
    width: 420
    height: 520

    Component.onCompleted: Quickshell.watchFiles = false

    HourglassBarIcon {
        id: probeBarIcon
        width: 18
        height: 18
        visualStyle: "turned"
        progress: 1.0
    }

    HourglassVisual {
        id: probeVisual
        width: 120
        height: 144
        visualStyle: "turned"
        progress: 0.65
        running: false
    }

    PomodoroWidget {
        id: widget
        anchors.fill: parent
    }

    PomodoroTimer {
        id: pomodoroPanel
        width: 340
        height: 420
        visible: true
    }

    CountdownTimer {
        id: countdownPanel
        width: 340
        height: 360
        visible: true
    }

    TestCase {
        id: test
        when: false
        optional: true
        name: "HourglassTimerRuntime"

        function findChildByObjectName(item, targetName) {
            if (!item)
                return null
            if (item.objectName === targetName)
                return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) {
                const found = findChildByObjectName(kids[i], targetName)
                if (found)
                    return found
            }
            const res = item.resources || []
            for (let j = 0; j < res.length; j++) {
                const found = findChildByObjectName(res[j], targetName)
                if (found)
                    return found
            }
            return null
        }

        function check(cond, msg) {
            if (!cond)
                throw new Error(msg)
        }

        function waitFor(pred, timeoutMs) {
            const deadline = Date.now() + (timeoutMs || 4000)
            while (!pred()) {
                if (Date.now() > deadline)
                    throw new Error("Timed out waiting for readiness")
                wait(25)
            }
        }

        function run() {
            try {
                waitFor(() => Config.ready && Persistent.ready, 4000)

                // 1. Default style contract
                check(TimerService.visualStyle === "turned", "Expected default style 'turned', got: " + TimerService.visualStyle)
                check(TimerService.hourglassStyleActive === true, "Expected hourglassStyleActive true by default")

                const pHourglass = findChildByObjectName(pomodoroPanel, "pomodoroHourglass")
                const cHourglass = findChildByObjectName(countdownPanel, "countdownHourglass")
                const pBtn = findChildByObjectName(pomodoroPanel, "pomodoroStyleButton")
                const cBtn = findChildByObjectName(countdownPanel, "countdownStyleButton")

                check(!!pHourglass && pHourglass.visible === true, "pomodoroHourglass should exist and be visible in 'turned'")
                check(!!cHourglass && cHourglass.visible === true, "countdownHourglass should exist and be visible in 'turned'")
                check(!!pBtn && !!cBtn, "Style cycler buttons should exist on both Pomodoro & Countdown")

                // 2. Quarter-step math & style support on HourglassBarIcon
                probeBarIcon.progress = 1.0
                check(probeBarIcon.stepQuarter === 4, "1.0 -> quarter 4")
                probeBarIcon.progress = 0.76
                check(probeBarIcon.stepQuarter === 4, "0.76 -> quarter 4")
                probeBarIcon.progress = 0.50
                check(probeBarIcon.stepQuarter === 2, "0.50 -> quarter 2")
                probeBarIcon.progress = 0.25
                check(probeBarIcon.stepQuarter === 1, "0.25 -> quarter 1")
                probeBarIcon.progress = 0.0
                check(probeBarIcon.stepQuarter === 0, "0.0 -> quarter 0")
                probeBarIcon.overtime = true
                check(probeBarIcon.stepQuarter === 0, "overtime -> quarter 0")
                probeBarIcon.overtime = false

                for (const s of ["turned", "matrix", "square"]) {
                    probeBarIcon.visualStyle = s
                    check(probeBarIcon.normalizedStyle === s, "Bar icon style normalized: " + s)
                    wait(10)
                }

                // 3. Cycling styles via buttons & Key_T across turned -> matrix -> square -> classic -> turned
                pBtn.clicked()
                wait(30)
                check(TimerService.visualStyle === "matrix", "Expected 'matrix' after Pomodoro click, got " + TimerService.visualStyle)
                check(Config.options.time.visualStyle === "matrix", "Config.options.time.visualStyle should persist 'matrix'")

                cBtn.clicked()
                wait(30)
                check(TimerService.visualStyle === "square", "Expected 'square' after Countdown click, got " + TimerService.visualStyle)

                widget.forceActiveFocus()
                keyClick(Qt.Key_T)
                wait(30)
                check(TimerService.visualStyle === "classic", "Expected 'classic' after Key_T, got " + TimerService.visualStyle)
                check(TimerService.hourglassStyleActive === false, "hourglassStyleActive false in classic")
                check(pHourglass.visible === false && cHourglass.visible === false, "Hourglasses hidden in classic style")

                // Clicking Settings chip restores 'turned'
                const chipTurned = findChildByObjectName(pomodoroPanel, "pomodoroStyleChip_turned")
                check(!!chipTurned, "Settings style chip 'turned' must exist")
                chipTurned.clicked()
                wait(30)
                check(TimerService.visualStyle === "turned" && TimerService.hourglassStyleActive === true, "Settings chip restores turned")

                // 4. Visual flip & overtime/paused states
                for (const s of ["turned", "matrix", "square"]) {
                    probeVisual.visualStyle = s
                    probeVisual.triggerFlip()
                    wait(20)
                }
                probeVisual.progress = 0.0
                probeVisual.overtime = true
                wait(20)
                check(probeVisual.clampedProgress === 0.0, "overtime clamps progress to 0")

                console.info("HOURGLASS_TIMER_RUNTIME_PASS")
            } catch (e) {
                console.error("HOURGLASS_TIMER_RUNTIME_FAIL:", e.message, e.stack || "")
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        onTriggered: test.run()
    }
}
'''

# Verify bar indicator wiring contracts (PanelWindow tooltips require virtual/real Wayland)
ti_src = (ROOT / "modules" / "bar" / "TimerIndicator.qml").read_text()
for req in (
    "HourglassBarIcon {",
    'objectName: "barHourglassIcon"',
    "(root.pomodoroActive || root.countdownActive)",
    "visualStyle: TimerService?.visualStyle",
):
    assert req in ti_src, f"TimerIndicator.qml missing hourglass contract: {req}"

tb_src = (ROOT / "modules" / "waffle" / "bar" / "TimerButton.qml").read_text()
for req in (
    "HourglassBarIcon {",
    'objectName: "waffleBarHourglassIcon"',
    "(root.pomodoroActive || root.countdownActive)",
    "visualStyle: TimerService?.visualStyle",
):
    assert req in tb_src, f"TimerButton.qml missing hourglass contract: {req}"

with tempfile.TemporaryDirectory(prefix="alis-hourglass-test-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(QML)
    config = folder / "config" / "alis"
    config.mkdir(parents=True, exist_ok=True)
    raw = json.loads((ROOT / "defaults" / "config.json").read_text())
    raw["panelFamily"] = "abyss"
    (config / "config.json").write_text(json.dumps(raw))

    env = {
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
        "XDG_CONFIG_HOME": str(folder / "config"),
        "XDG_STATE_HOME": str(folder / "state"),
        "XDG_CACHE_HOME": str(folder / "cache"),
        "XDG_DATA_HOME": str(folder / "data"),
    }
    res = run_qs(folder, env, timeout=25)
    print(res.stdout.strip())
    bad = ["HOURGLASS_TIMER_RUNTIME_FAIL", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign"]
    if res.returncode != 0 or "HOURGLASS_TIMER_RUNTIME_PASS" not in res.stdout or any(b in res.stdout for b in bad):
        raise SystemExit(1)
