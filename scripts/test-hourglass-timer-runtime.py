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

                // 1. Default style contract & legacy "classic" migration fallback
                check(TimerService.visualStyle === "turned", "Expected default style 'turned', got: " + TimerService.visualStyle)
                check(TimerService.visualStyles.length === 3 && TimerService.visualStyles.indexOf("classic") === -1,
                    "visualStyles must contain only turned, matrix, square")
                Config.setNestedValue("time.visualStyle", "classic")
                wait(30)
                check(TimerService.visualStyle === "turned", "Legacy 'classic' config must fall back to 'turned', got: " + TimerService.visualStyle)

                const pHourglass = findChildByObjectName(pomodoroPanel, "pomodoroHourglass")
                const cHourglass = findChildByObjectName(countdownPanel, "countdownHourglass")
                const pBtn = findChildByObjectName(pomodoroPanel, "pomodoroStyleButton")
                const cBtn = findChildByObjectName(countdownPanel, "countdownStyleButton")
                const cCustBtn = findChildByObjectName(countdownPanel, "countdownCustomizeButton")

                check(!!pHourglass && pHourglass.visible === true, "pomodoroHourglass should always exist and be visible")
                check(!!cHourglass && cHourglass.visible === true, "countdownHourglass should always exist and be visible")
                check(!pBtn && !cBtn, "Outer style switcher buttons must be completely removed")
                check(!!cCustBtn, "Countdown Customize button must exist")

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

                // 3. Key_T must NOT cycle styles; Customize chips switch & are horizontally centered
                widget.forceActiveFocus()
                keyClick(Qt.Key_T)
                wait(30)
                check(TimerService.visualStyle === "turned", "Key_T must not switch visualStyle, got " + TimerService.visualStyle)

                pomodoroPanel.settingsOpen = true
                wait(40)
                const chipMatrix = findChildByObjectName(pomodoroPanel, "pomodoroStyleChip_matrix")
                check(!!chipMatrix, "Pomodoro Customize style chip 'matrix' must exist")
                check(chipMatrix.contentItem.horizontalAlignment === Text.AlignHCenter, "Pomodoro style chip text must be HCenter aligned")
                chipMatrix.clicked()
                wait(30)
                check(TimerService.visualStyle === "matrix", "Expected 'matrix' after Pomodoro Customize chip click, got " + TimerService.visualStyle)
                check(Config.options.time.visualStyle === "matrix", "Config.options.time.visualStyle should persist 'matrix'")

                cCustBtn.clicked()
                wait(40)
                check(countdownPanel.settingsOpen === true, "Clicking Countdown Customize button must open style card")
                const cChipSquare = findChildByObjectName(countdownPanel, "countdownStyleChip_square")
                check(!!cChipSquare, "Countdown Customize style chip 'square' must exist")
                check(cChipSquare.contentItem.horizontalAlignment === Text.AlignHCenter, "Countdown style chip text must be HCenter aligned")
                cChipSquare.clicked()
                wait(30)
                check(TimerService.visualStyle === "square", "Expected 'square' after Countdown Customize chip click, got " + TimerService.visualStyle)

                const chipTurned = findChildByObjectName(pomodoroPanel, "pomodoroStyleChip_turned")
                check(!!chipTurned, "Settings style chip 'turned' must exist")
                chipTurned.clicked()
                wait(30)
                pomodoroPanel.settingsOpen = false
                cCustBtn.clicked()
                wait(30)
                check(countdownPanel.settingsOpen === false, "Toggling Customize closes Countdown style card")
                check(TimerService.visualStyle === "turned" && pHourglass.visible === true && cHourglass.visible === true, "Settings chip restores turned and closes back to hourglass")

                TimerService.cycleVisualStyle()
                TimerService.cycleVisualStyle()
                TimerService.cycleVisualStyle()
                check(TimerService.visualStyle === "turned", "cycleVisualStyle must loop 3 styles back to turned")

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
assert "hourglassStyleActive" not in ti_src, "TimerIndicator.qml must always use HourglassBarIcon (no Classic branch)"
for req in (
    "HourglassBarIcon {",
    'objectName: "barHourglassIcon"',
    "(root.pomodoroActive || root.countdownActive)",
    "visualStyle: TimerService?.visualStyle",
):
    assert req in ti_src, f"TimerIndicator.qml missing hourglass contract: {req}"

tb_src = (ROOT / "modules" / "waffle" / "bar" / "TimerButton.qml").read_text()
assert "hourglassStyleActive" not in tb_src, "TimerButton.qml must always use HourglassBarIcon (no Classic branch)"
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
