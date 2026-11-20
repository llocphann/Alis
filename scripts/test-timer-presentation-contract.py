#!/usr/bin/env python3
"""Regression contract for the Hourglass-only compact timer visual language."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POMODORO = ROOT / "modules" / "sidebarRight" / "pomodoro" / "PomodoroTimer.qml"
COUNTDOWN = ROOT / "modules" / "sidebarRight" / "pomodoro" / "CountdownTimer.qml"
WIDGET = ROOT / "modules" / "sidebarRight" / "pomodoro" / "PomodoroWidget.qml"
TIMER_SVC = ROOT / "services" / "TimerService.qml"
PILL_TAB = ROOT / "modules" / "common" / "widgets" / "PillTabBar.qml"


def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)


def require(source: str, token: str, message: str) -> None:
    if token not in source:
        fail(message + " (" + token + ")")


def forbid(source: str, token: str, message: str) -> None:
    if token in source:
        fail(message + " (" + token + ")")


pomodoro = POMODORO.read_text(encoding="utf-8")
countdown = COUNTDOWN.read_text(encoding="utf-8")
widget = WIDGET.read_text(encoding="utf-8")
timer_svc = TIMER_SVC.read_text(encoding="utf-8")
pill_tab = PILL_TAB.read_text(encoding="utf-8")

# Classic timer styles, outer style cyclers, and Key_T must be completely removed.
forbid(pomodoro, "CircularProgress {", "Pomodoro must not regress to CircularProgress")
forbid(pomodoro, "import QtQuick.Shapes", "Pomodoro must remove Classic Shape dial")
forbid(pomodoro, "PathAngleArc {", "Pomodoro must remove Classic PathAngleArc")
forbid(pomodoro, "pomodoroStyleButton", "Pomodoro must remove outer style switcher button")
forbid(pomodoro, "hourglassStyleActive", "Pomodoro must not branch on removed hourglassStyleActive")

forbid(countdown, "CircularProgress {", "Countdown must not regress to CircularProgress")
forbid(countdown, "id: segmentRow", "Countdown must remove Classic segmented runway")
forbid(countdown, "countdownStyleButton", "Countdown must remove outer style switcher button")
forbid(countdown, "hourglassStyleActive", "Countdown must not branch on removed hourglassStyleActive")

forbid(widget, "Qt.Key_T", "PomodoroWidget must remove Qt.Key_T outer style shortcut")
forbid(timer_svc, "hourglassStyleActive", "TimerService must remove hourglassStyleActive")
require(timer_svc, 'visualStyles: ["turned", "matrix", "square"]', "TimerService must expose only the 3 Hourglass styles")

for token in (
    'objectName: "pomodoroHourglass"',
    "HourglassVisual {",
    "TimerService.cyclesBeforeLongBreak",
    "index === TimerService.pomodoroCycle",
    'objectName: "pomodoroStyleChip_" + modelData',
    "horizontalAlignment: Text.AlignHCenter",
    "verticalAlignment: Text.AlignVCenter",
):
    require(pomodoro, token, "Pomodoro Hourglass & Customize contract missing")

for token in (
    "id: timerDeck",
    "readonly property real progress:",
    'objectName: "countdownHourglass"',
    'objectName: "countdownSettingsCard"',
    'objectName: "countdownCustomizeButton"',
    'objectName: "countdownStyleChip_" + modelData',
    "horizontalAlignment: Text.AlignHCenter",
    "verticalAlignment: Text.AlignVCenter",
    'Translation.tr("Set duration")',
):
    require(countdown, token, "Countdown Hourglass & Customize contract missing")

# Timer mode pages are lazy: the first Timers reveal constructs only the
# currently selected face, then visited faces stay resident for this widget
# instance so local presentation state is not discarded on mode switches.
for token in (
    "property bool pomodoroMaterialized: false",
    "property bool countdownMaterialized: false",
    "property bool stopwatchMaterialized: false",
    "function ensureCurrentPage(): void",
    "Component.onCompleted: root.ensureCurrentPage()",
    "active: root.pomodoroMaterialized",
    "active: root.countdownMaterialized",
    "active: root.stopwatchMaterialized",
    "sourceComponent: PomodoroTimer {",
    "sourceComponent: CountdownTimer {",
    "sourceComponent: Stopwatch {",
):
    require(widget, token, "Timer mode pages must materialize lazily and remain resident after first use")

# Timer mode tabs should fit inside the existing corner popup without making
# the popup resize or letting long labels cross into adjacent pills.
for token in (
    "anchors.horizontalCenter: parent.horizontalCenter",
    "root.compactMode ? 296 : 260",
    "parent.width - (pinButton.width + 6) * 2",
    "pillHeight: root.compactMode ? 28 : 30",
    "Layout.topMargin: 6",
):
    require(widget, token, "Timer mode tabs must remain compact and centered")

for token in (
    "readonly property bool hasIcon:",
    "readonly property bool hasBadge:",
    "clip: true",
    "width: Math.min(implicitWidth, Math.max(0,",
    "tab.width",
    "horizontalAlignment: Text.AlignHCenter",
):
    require(pill_tab, token,
            "PillTabBar must constrain centered labels to their own tab slot")

print("ok - timer presentation contract")
