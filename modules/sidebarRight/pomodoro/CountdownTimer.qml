import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool compactMode: false
    property bool centerMode: true

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    property bool editMode: !TimerService.countdownRunning && TimerService.countdownSecondsLeft === TimerService.countdownDuration

    readonly property color _colAccent: Appearance.angelEverywhere ? Appearance.angel.colPrimary
        : Appearance.alisEverywhere ? Appearance.alis.colPrimary
        : Appearance.colors.colPrimary
    readonly property color _colText: Appearance.angelEverywhere ? Appearance.angel.colText
        : Appearance.alisEverywhere ? Appearance.alis.colText
        : Appearance.colors.colOnSurface
    readonly property color _colSubtext: Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
        : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colSubtext
    readonly property color _colTrack: ColorUtils.transparentize(root._colSubtext, 0.76)

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        // Vertical spacer — center content when there's extra space
        Item {
            Layout.fillHeight: root.centerMode
            Layout.minimumHeight: 0
            visible: root.centerMode && root.height > contentColumn.implicitHeight
        }

        Item {
            id: timerDeck
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.compactMode ? 126 : 138

            readonly property real progress:
                TimerService.countdownDuration > 0
                    ? Math.max(0, Math.min(1,
                        TimerService.countdownSecondsLeft
                            / TimerService.countdownDuration))
                    : 0

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (!root.editMode)
                        return
                    const delta = wheel.angleDelta.y > 0 ? 60 : -60
                    const newDuration = Math.max(60, Math.min(
                        5940, TimerService.countdownDuration + delta))
                    TimerService.setCountdownDuration(newDuration)
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 24, 310)
                spacing: 5

                // Editable time display with separate minutes and seconds.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2
                    opacity: root.editMode ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }

                    Rectangle {
                        width: 52
                        height: 50
                        color: minutesInput.activeFocus
                            ? ColorUtils.transparentize(root._colAccent, 0.82)
                            : "transparent"
                        radius: Appearance.rounding.small
                        border.width: minutesInput.activeFocus ? 1 : 0
                        border.color: root._colAccent

                        TextInput {
                            id: minutesInput
                            anchors.centerIn: parent
                            width: parent.width - 8
                            text: Math.floor(
                                TimerService.countdownDuration / 60)
                                .toString().padStart(2, '0')
                            font.pixelSize: Math.round(
                                36 * Appearance.fontSizeScale)
                            font.family: Appearance.font.family.numbers
                            color: root._colText
                            horizontalAlignment: Text.AlignHCenter
                            validator: IntValidator { bottom: 0; top: 99 }
                            selectByMouse: true
                            onEditingFinished: {
                                const mins = parseInt(text) || 0
                                const secs = parseInt(secondsInput.text) || 0
                                TimerService.setCountdownDuration(
                                    mins * 60 + secs)
                            }
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    selectAll()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: wheel => {
                                const delta = wheel.angleDelta.y > 0 ? 1 : -1
                                const currentMins =
                                    parseInt(minutesInput.text) || 0
                                const newMins = Math.max(
                                    0, Math.min(99, currentMins + delta))
                                const secs =
                                    parseInt(secondsInput.text) || 0
                                TimerService.setCountdownDuration(
                                    newMins * 60 + secs)
                            }
                        }
                    }

                    StyledText {
                        text: ":"
                        font.pixelSize: Math.round(
                            34 * Appearance.fontSizeScale)
                        font.family: Appearance.font.family.numbers
                        color: root._colSubtext
                    }

                    Rectangle {
                        width: 52
                        height: 50
                        color: secondsInput.activeFocus
                            ? ColorUtils.transparentize(root._colAccent, 0.82)
                            : "transparent"
                        radius: Appearance.rounding.small
                        border.width: secondsInput.activeFocus ? 1 : 0
                        border.color: root._colAccent

                        TextInput {
                            id: secondsInput
                            anchors.centerIn: parent
                            width: parent.width - 8
                            text: Math.floor(
                                TimerService.countdownDuration % 60)
                                .toString().padStart(2, '0')
                            font.pixelSize: Math.round(
                                36 * Appearance.fontSizeScale)
                            font.family: Appearance.font.family.numbers
                            color: root._colText
                            horizontalAlignment: Text.AlignHCenter
                            validator: IntValidator { bottom: 0; top: 59 }
                            selectByMouse: true
                            onEditingFinished: {
                                const mins =
                                    parseInt(minutesInput.text) || 0
                                const secs = Math.min(
                                    59, parseInt(text) || 0)
                                TimerService.setCountdownDuration(
                                    mins * 60 + secs)
                            }
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    selectAll()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: wheel => {
                                const delta = wheel.angleDelta.y > 0 ? 1 : -1
                                const mins =
                                    parseInt(minutesInput.text) || 0
                                const currentSecs =
                                    parseInt(secondsInput.text) || 0
                                const newSecs = Math.max(
                                    0, Math.min(59, currentSecs + delta))
                                TimerService.setCountdownDuration(
                                    mins * 60 + newSecs)
                            }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    opacity: !root.editMode ? 1 : 0
                    visible: opacity > 0
                    text: {
                        const totalSeconds =
                            TimerService.countdownSecondsLeft
                        const minutes = Math.floor(totalSeconds / 60)
                            .toString().padStart(2, '0')
                        const seconds = Math.floor(totalSeconds % 60)
                            .toString().padStart(2, '0')
                        return `${minutes}:${seconds}`
                    }
                    font.pixelSize: Math.round(
                        (root.compactMode ? 39 : 42)
                            * Appearance.fontSizeScale)
                    font.weight: Font.Medium
                    font.family: Appearance.font.family.numbers
                    color: root._colText

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                // Countdown uses a segmented runway instead of a circular dial.
                // Segments extinguish from right to left as time elapses.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    Layout.topMargin: 5

                    Row {
                        id: segmentRow
                        anchors.fill: parent
                        spacing: 3

                        Repeater {
                            model: 16

                            Rectangle {
                                required property int index
                                readonly property bool activeSegment:
                                    root.editMode
                                    || index < Math.ceil(
                                        timerDeck.progress * 16)
                                width: Math.max(3,
                                    (segmentRow.width - 45) / 16)
                                height: 6
                                radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: activeSegment
                                    ? root._colAccent : root._colTrack
                                opacity: activeSegment ? 1 : 0.7

                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.editMode
                            ? Translation.tr("Set duration")
                            : TimerService.countdownRunning
                                ? Translation.tr("Running")
                                : Translation.tr("Paused")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: root._colSubtext
                    }

                    StyledText {
                        visible: !root.editMode
                        text: Math.round(timerDeck.progress * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: root._colSubtext
                    }
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            spacing: 6
            opacity: root.editMode ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            Repeater {
                model: [
                    { label: "1m", seconds: 60 },
                    { label: "5m", seconds: 300 },
                    { label: "10m", seconds: 600 },
                    { label: "15m", seconds: 900 },
                    { label: "30m", seconds: 1800 }
                ]

                RippleButton {
                    required property var modelData
                    implicitHeight: 30
                    implicitWidth: 45
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                        : Appearance.auroraEverywhere ? "transparent" : Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover : Appearance.colors.colLayer2Hover
                    colRipple: Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive : Appearance.colors.colLayer2Active
                    onClicked: TimerService.setCountdownDuration(modelData.seconds)

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.editMode ? 8 : 0
            spacing: 10

            RippleButton {
                Layout.preferredHeight: 35
                Layout.preferredWidth: 90
                buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full
                onClicked: TimerService.toggleCountdown()
                enabled: TimerService.countdownDuration > 0
                colBackground: TimerService.countdownRunning
                    ? (Appearance.zzzEverywhere ? Appearance.zzz.sticker
                        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colSecondaryContainer)
                    : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.countdownRunning
                    ? (Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover
                        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurfaceHover : Appearance.colors.colSecondaryContainerHover)
                    : Appearance.colors.colPrimaryHover
                colRipple: TimerService.countdownRunning
                    ? (Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive
                        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive : Appearance.colors.colSecondaryContainerActive)
                    : Appearance.colors.colPrimaryActive

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    color: TimerService.countdownRunning
                        ? (Appearance.zzzEverywhere ? Appearance.zzz.onSticker
                            : Appearance.angelEverywhere ? Appearance.angel.colText
                            : Appearance.alisEverywhere ? Appearance.alis.colText
                            : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSecondaryContainer)
                        : Appearance.colors.colOnPrimary
                    text: TimerService.countdownRunning ? Translation.tr("Pause") : TimerService.countdownSecondsLeft === TimerService.countdownDuration ? Translation.tr("Start") : Translation.tr("Resume")
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                }
            }

            RippleButton {
                Layout.preferredHeight: 35
                Layout.preferredWidth: 90
                onClicked: TimerService.resetCountdown()
                enabled: TimerService.countdownSecondsLeft < TimerService.countdownDuration || TimerService.countdownRunning
                colBackground: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                    : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                    : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface
                    : Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                    : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                    : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurfaceHover
                    : Appearance.colors.colErrorContainerHover
                colRipple: Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                    : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
                    : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive
                    : Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.angelEverywhere ? Appearance.angel.colText
                        : Appearance.alisEverywhere ? Appearance.alis.colText
                        : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer2
                        : Appearance.colors.colOnErrorContainer
                }
            }
        }

        // Bottom spacer — balance vertical centering
        Item {
            Layout.fillHeight: root.compactMode
            Layout.minimumHeight: 0
        }
    }
}
