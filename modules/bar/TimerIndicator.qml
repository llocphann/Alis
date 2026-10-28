import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Compact timer indicator for the ii bar.
 * Shows when pomodoro, countdown, or stopwatch is active.
 */
MouseArea {
    id: root
    // A pointer click can retain activeFocus after hover ends. Keep popup
    // keyboard focus affordance without treating pointer focus as hover.
    property bool _pointerFocused: false
    onPressed: root._pointerFocused = true
    onActiveFocusChanged: {
        if (!root.activeFocus)
            root._pointerFocused = false
    }
    property bool vertical: false

    readonly property bool pinnedToBar: Persistent.states?.timer?.pinnedToBar ?? false

    readonly property bool pomodoroRunning: TimerService?.pomodoroRunning ?? false
    readonly property bool countdownRunning: TimerService?.countdownRunning ?? false
    readonly property bool stopwatchRunning: TimerService?.stopwatchRunning ?? false

    readonly property bool pomodoroActive: pomodoroRunning || (TimerService?.pomodoroSecondsLeft ?? 0) < (TimerService?.pomodoroLapDuration ?? 0)
    readonly property bool countdownFinished: !countdownRunning && (TimerService?.countdownSecondsLeft ?? 0) <= 0
        && (TimerService?.countdownDuration ?? 0) > 0

    readonly property bool countdownActive: !countdownFinished && (countdownRunning
        || (TimerService?.countdownSecondsLeft ?? 0) < (TimerService?.countdownDuration ?? 0))
    readonly property bool stopwatchActive: stopwatchRunning || (TimerService?.stopwatchTime ?? 0) > 0 || ((TimerService?.stopwatchLaps?.length ?? 0) > 0)

    readonly property bool anyActive: pomodoroActive || countdownActive || stopwatchActive

    readonly property bool showPinnedIdle: pinnedToBar && !anyActive
    readonly property bool contentAvailable: anyActive || showPinnedIdle

    readonly property bool currentRunning: {
        if (root.pomodoroActive) return root.pomodoroRunning && !(TimerService?.pomodoroPaused ?? false)
        if (root.countdownActive) return root.countdownRunning && !(TimerService?.countdownPaused ?? false)
        if (root.stopwatchActive) return root.stopwatchRunning && !(TimerService?.stopwatchPaused ?? false)
        return false
    }

    readonly property bool paused: root.anyActive && !root.currentRunning

    readonly property string timeText: {
        if (pomodoroActive) {
            const secs = TimerService?.pomodoroSecondsLeft ?? 0
            const mins = Math.floor(secs / 60).toString().padStart(2, '0')
            const s = Math.floor(secs % 60).toString().padStart(2, '0')
            return `${mins}:${s}`
        }
        if (countdownActive) {
            const secs = TimerService?.countdownSecondsLeft ?? 0
            const mins = Math.floor(secs / 60).toString().padStart(2, '0')
            const s = Math.floor(secs % 60).toString().padStart(2, '0')
            return `${mins}:${s}`
        }
        if (stopwatchActive) {
            const total = TimerService?.stopwatchTime ?? 0
            const secs = Math.floor(total / 100)
            const mins = Math.floor(secs / 60)
            const s = secs % 60
            return `${mins.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
        }
        return ""
    }

    readonly property string iconName: {
        if (pomodoroActive)
            return (TimerService?.pomodoroBreak ?? false) ? "coffee" : "target"
        if (countdownActive)
            return "hourglass_top"
        if (stopwatchActive)
            return "timer"
        return "schedule"
    }

    readonly property color accentColor: {
        if (pomodoroActive) {
            return (TimerService?.pomodoroBreak ?? false)
                ? Appearance.colors.colTertiary
                : Appearance.colors.colPrimary
        }
        if (countdownActive)
            return Appearance.colors.colSecondary
        return Appearance.colors.colOnLayer1
    }

    visible: root.contentAvailable
    implicitWidth: root.contentAvailable
        ? (root.vertical ? 34 * Appearance.sizes.barModuleScale : pill.width + 4 * Appearance.sizes.barModuleScale) : 0
    implicitHeight: root.vertical
        ? (root.contentAvailable ? 34 * Appearance.sizes.barModuleScale : 0)
        : Appearance.sizes.barHeight

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    activeFocusOnTab: root.visible

    Accessible.role: Accessible.Button
    Accessible.name: root.showPinnedIdle
        ? Translation.tr("Timer")
        : Translation.tr("Timer %1").arg(root.timeText)
    Accessible.focusable: root.visible

    function openTimerPanel(): void {
        GlobalStates.openSidebarRight(root.QsWindow.window?.screen?.name ?? "")

        if (Persistent?.states?.sidebar?.bottomGroup) {
            Persistent.states.sidebar.bottomGroup.tab = 3
            Persistent.states.sidebar.bottomGroup.collapsed = false
        }

        if (Persistent?.states?.timer) {
            if (root.pomodoroActive) {
                Persistent.states.timer.tab = 0
            } else if (root.countdownActive) {
                Persistent.states.timer.tab = 1
            } else if (root.stopwatchActive) {
                Persistent.states.timer.tab = 2
            }
        }
    }

    function activatePrimary(): void {
        if (!root.anyActive && root.showPinnedIdle) {
            root.openTimerPanel()
            return
        }

        if (root.pomodoroActive)
            TimerService.togglePomodoro()
        else if (root.countdownActive)
            TimerService.toggleCountdown()
        else if (root.stopwatchActive)
            TimerService.toggleStopwatch()
    }

    Keys.onPressed: event => {
        if (event.isAutoRepeat
                || (event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter
                    && event.key !== Qt.Key_Space))
            return
        root.activatePrimary()
        event.accepted = true
    }

    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            root.activatePrimary()
            return
        }

        if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) {
            root.openTimerPanel()
        }
    }

    Behavior on implicitWidth {
        // Closing immediately releases Screen Edge geometry and hit testing.
        enabled: Appearance.animationsEnabled && root.contentAvailable
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // Background pill
    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: root.vertical ? 30 * Appearance.sizes.barModuleScale : contentRow.implicitWidth + 12 * Appearance.sizes.barModuleScale
        height: root.vertical ? 30 * Appearance.sizes.barModuleScale : contentRow.implicitHeight + 8 * Appearance.sizes.barModuleScale
        radius: height / 2
        scale: root.pressed ? 0.95 : 1.0
        color: {
            if (root.pressed)
                return Appearance.colors.colLayer1Active
            if (root.paused)
                return root.containsMouse
                    ? Appearance.colors.colLayer2Active
                    : Appearance.colors.colLayer2Hover
            if (root.containsMouse)
                return Appearance.colors.colLayer1Hover
            return "transparent"
        }

        Behavior on color {
            enabled: Appearance.animationsEnabled
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    KeyboardFocusRing {
        anchors.fill: pill
        focusVisible: root.activeFocus
        radius: pill.radius
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: pill
        spacing: 4 * Appearance.sizes.barModuleScale

        MaterialSymbol {
            text: root.showPinnedIdle ? "schedule" : root.iconName
            iconSize: Math.round(Appearance.font.pixelSize.normal * Appearance.sizes.barModuleScale)
            color: root.paused
                ? Appearance.colors.colOnLayer1Inactive
                : root.accentColor
            Layout.alignment: Qt.AlignVCenter

            SequentialAnimation on opacity {
                running: root.visible && (root.QsWindow.window?.visible ?? true) && root.pomodoroActive && root.pomodoroRunning && !(TimerService?.pomodoroBreak ?? false)
                loops: Animation.Infinite
                NumberAnimation { to: 0.5; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        StyledText {
            visible: !root.vertical
            text: root.showPinnedIdle ? Translation.tr("Timer") : root.timeText
            font.pixelSize: Math.round(Appearance.font.pixelSize.small * Appearance.sizes.barModuleScale)
            color: root.paused
                ? Appearance.colors.colOnLayer1Inactive
                : Appearance.colors.colOnLayer1
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.paused && !root.vertical ? pauseIcon.implicitWidth : 0
            implicitHeight: pauseIcon.implicitHeight
            opacity: root.paused && !root.vertical ? 1 : 0
            visible: opacity > 0
            clip: true

            Behavior on implicitWidth {
                enabled: Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
            }
            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            MaterialSymbol {
                id: pauseIcon
                anchors.centerIn: parent
                text: "pause"
                iconSize: Math.round(Appearance.font.pixelSize.small * Appearance.sizes.barModuleScale)
                color: Appearance.colors.colOnLayer1Inactive
            }
        }
    }

    // Tooltip
    TimerIndicatorTooltip {
        hoverTarget: root
        alternativeVisibleCondition: root.activeFocus && !root._pointerFocused
        pomodoroActive: root.pomodoroActive
        countdownActive: root.countdownActive
        stopwatchActive: root.stopwatchActive
        paused: root.paused
        pinnedIdle: root.showPinnedIdle
    }
}
