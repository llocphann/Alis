import qs
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

BarButton {
    id: root

    readonly property bool pomodoroActive: TimerService?.pomodoroRunning ?? false
    readonly property bool countdownActive: TimerService?.countdownRunning ?? false
    readonly property bool stopwatchActive: TimerService?.stopwatchRunning ?? false
    readonly property bool anyActive: pomodoroActive || countdownActive || stopwatchActive

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
        // Missing Fluent assets render blank without warning.
        if (pomodoroActive) return (TimerService?.pomodoroBreak ?? false) ? "drink-coffee" : "flash-on"
        if (countdownActive) return "timer"
        if (stopwatchActive) return "timer"
        return "drink-coffee"
    }

    visible: anyActive

    onClicked: {
        if (root.pomodoroActive) {
            TimerService.togglePomodoro()
        } else if (root.countdownActive) {
            TimerService.toggleCountdown()
        } else if (root.stopwatchActive) {
            TimerService.toggleStopwatch()
        }
    }

    altAction: () => {
        GlobalStates.waffleWidgetsOpen = true
        if (Persistent?.states?.sidebar?.bottomGroup) {
            Persistent.states.sidebar.bottomGroup.tab = 3
        }
    }

    contentItem: Item {
        anchors.fill: parent
        implicitWidth: timerRow.implicitWidth
        implicitHeight: timerRow.implicitHeight

        Row {
            id: timerRow
            anchors.centerIn: parent
            spacing: 6

            Item {
                id: waffleTimerIconSlot
                readonly property bool useHourglass: (TimerService?.hourglassStyleActive ?? true)
                    && (root.pomodoroActive || root.countdownActive)
                readonly property real activeProgress: root.pomodoroActive
                    ? ((TimerService?.pomodoroSecondsLeft ?? 0) / Math.max(1, TimerService?.pomodoroLapDuration ?? 1))
                    : (root.countdownActive
                        ? ((TimerService?.countdownSecondsLeft ?? 0) / Math.max(1, TimerService?.countdownDuration ?? 1))
                        : 1.0)
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(14, fluentTimerIcon.implicitWidth)
                implicitHeight: Math.max(14, fluentTimerIcon.implicitHeight)

                FluentIcon {
                    id: fluentTimerIcon
                    anchors.centerIn: parent
                    visible: !waffleTimerIconSlot.useHourglass
                    icon: root.iconName
                }

                HourglassBarIcon {
                    id: waffleHourglassIcon
                    objectName: "waffleBarHourglassIcon"
                    anchors.centerIn: parent
                    visible: waffleTimerIconSlot.useHourglass
                    visualStyle: TimerService?.visualStyle ?? "turned"
                    progress: waffleTimerIconSlot.activeProgress
                    paused: root.pomodoroActive
                        ? (TimerService?.pomodoroPaused ?? false)
                        : (TimerService?.countdownPaused ?? false)
                    color: fluentTimerIcon.color
                    iconSize: Math.max(14, Math.round(fluentTimerIcon.implicitHeight))
                }

                SequentialAnimation on opacity {
                    running: root.pomodoroActive && !(TimerService?.pomodoroBreak ?? false)
                        && root.visible && (root.Window.window?.visible ?? true)
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.5; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                }
            }

            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.timeText
            }
        }
    }

    BarToolTip {
        barExtraVisibleCondition: root.shouldShowTooltip
        text: {
            if (root.pomodoroActive) {
                const isLongBreak = TimerService?.pomodoroLongBreak ?? false
                const isBreak = TimerService?.pomodoroBreak ?? false
                const cycle = (TimerService?.pomodoroCycle ?? 0) + 1
                const totalCycles = TimerService?.cyclesBeforeLongBreak ?? 4
                const mode = isLongBreak ? Translation.tr("Long break") : isBreak ? Translation.tr("Break") : Translation.tr("Focus")
                return `Pomodoro: ${mode} (${cycle}/${totalCycles})`
            }
            if (root.countdownActive) return Translation.tr("Countdown timer")
            if (root.stopwatchActive) return Translation.tr("Stopwatch")
            return ""
        }
    }
}
