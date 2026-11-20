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
    property bool settingsOpen: false

    Connections {
        target: TimerService
        function onCountdownRunningChanged(): void {
            if (TimerService.countdownRunning)
                root.settingsOpen = false
        }
    }

    readonly property color _colLayer: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface
        : Appearance.colors.colLayer2
    readonly property color _colLayerHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurfaceHover
        : Appearance.colors.colLayer2Hover
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
            visible: !root.settingsOpen || TimerService.countdownRunning
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.compactMode ? 128 : 160

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

            RowLayout {
                id: countdownDeckRow
                anchors.centerIn: parent
                width: Math.min(parent.width - 12, 318)
                spacing: root.compactMode ? 8 : 14

                HourglassVisual {
                    id: countdownHourglass
                    objectName: "countdownHourglass"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: root.compactMode ? 78 : 104
                    Layout.preferredHeight: root.compactMode ? 96 : 126
                    visualStyle: TimerService.visualStyle
                    progress: timerDeck.progress
                    running: TimerService.countdownRunning
                    paused: TimerService.countdownPaused
                    accentColor: root._colAccent
                    textColor: root._colText
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 130
                    Layout.alignment: Qt.AlignVCenter
                    spacing: root.compactMode ? 4 : 5

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
                        height: root.compactMode ? 44 : 50
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
                                (root.compactMode ? 33 : 36) * Appearance.fontSizeScale)
                            font.family: Appearance.font.family.numbers
                            color: root._colText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
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
                        Layout.alignment: Qt.AlignVCenter
                        Layout.bottomMargin: 3
                        text: ":"
                        font.pixelSize: Math.round(
                            (root.compactMode ? 31 : 34) * Appearance.fontSizeScale)
                        font.family: Appearance.font.family.numbers
                        verticalAlignment: Text.AlignVCenter
                        color: root._colSubtext
                    }

                    Rectangle {
                        width: 52
                        height: root.compactMode ? 44 : 50
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
                                (root.compactMode ? 33 : 36) * Appearance.fontSizeScale)
                            font.family: Appearance.font.family.numbers
                            color: root._colText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
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
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
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
                        (root.compactMode ? 37 : 42)
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
        }

        // Inline Style Customize card (Turned, Matrix, Square)
        Item {
            id: countdownSettingsCard
            objectName: "countdownSettingsCard"
            readonly property bool active: root.settingsOpen && !TimerService.countdownRunning
            readonly property real targetHeight: active ? settingsInner.implicitHeight + (root.compactMode ? 16 : 20) : 0
            visible: active || Layout.maximumHeight > 0
            Layout.fillWidth: true
            Layout.maximumWidth: Math.max(0, root.width - 16)
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: active ? 4 : 0
            Layout.bottomMargin: active ? (root.compactMode ? 6 : 8) : 0
            Layout.preferredHeight: targetHeight
            Layout.maximumHeight: targetHeight
            clip: true

            Behavior on Layout.maximumHeight {
                enabled: Appearance.animationsEnabled && !root.compactMode
                animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
                    : Appearance.alisEverywhere ? Appearance.alis.roundingNormal
                    : Appearance.rounding.normal
                color: root._colLayer
                border.width: 1
                border.color: Appearance.angelEverywhere ? Appearance.angel.colBorder
                    : Appearance.alisEverywhere ? Appearance.alis.colBorder
                    : Appearance.colors.colLayer0Border
            }

            ColumnLayout {
                id: settingsInner
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: root.compactMode ? 10 : 12
                }
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Style")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root._colSubtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: TimerService.visualStyles

                        RippleButton {
                            required property string modelData
                            readonly property bool selected: TimerService.visualStyle === modelData
                            readonly property color _chipActiveInk: ColorUtils.ensureReadable(Appearance.colors.colOnPrimary, root._colAccent, 5.0)
                            objectName: "countdownStyleChip_" + modelData
                            toggled: selected
                            Layout.fillWidth: true
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: root._colLayerHover
                            colBackgroundToggled: root._colAccent
                            colBackgroundToggledHover: Qt.lighter(root._colAccent, 1.08)
                            onClicked: TimerService.setVisualStyle(modelData)

                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: TimerService.visualStyleLabel(modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: selected ? Font.DemiBold : Font.Medium
                                color: selected ? _chipActiveInk : root._colText
                            }
                        }
                    }
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.compactMode ? 4 : 10
            spacing: 6
            opacity: root.editMode && !root.settingsOpen ? 1 : 0
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
                    readonly property bool selected: root.editMode && TimerService.countdownDuration === modelData.seconds
                    readonly property color _presetInk: ColorUtils.ensureReadable(Appearance.colors.colOnPrimary, root._colAccent, 5.0)
                    toggled: selected
                    implicitHeight: root.compactMode ? 28 : 30
                    implicitWidth: 45
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                        : Appearance.auroraEverywhere ? "transparent" : Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover : Appearance.colors.colLayer2Hover
                    colBackgroundToggled: root._colAccent
                    colBackgroundToggledHover: Qt.lighter(root._colAccent, 1.08)
                    colRipple: Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive : Appearance.colors.colLayer2Active
                    onClicked: TimerService.setCountdownDuration(modelData.seconds)

                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: selected ? Font.DemiBold : Font.Medium
                        color: selected
                            ? _presetInk
                            : (Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer2)
                    }
                }
            }
        }

        RowLayout {
            id: countdownControlsRow
            readonly property bool tightControls: root.width > 0 && root.width < 300
            Layout.fillWidth: true
            Layout.maximumWidth: Math.max(0, root.width - 12)
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.topMargin: (root.editMode && !root.settingsOpen) ? (root.compactMode ? 6 : 8) : 0
            spacing: tightControls ? 6 : 10

            // Mirror trailing Customize button so Start/Reset stay centered.
            Item {
                Layout.preferredWidth: Math.max(0, Math.min(
                    countdownCustomizeButton.implicitWidth,
                    root.width - (countdownStartButton.implicitWidth + countdownResetButton.implicitWidth + countdownCustomizeButton.implicitWidth + (countdownControlsRow.tightControls ? 36 : 48))))
                Layout.preferredHeight: 1
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                id: countdownStartButton
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 35
                implicitWidth: countdownControlsRow.tightControls ? 78 : 90
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
                    verticalAlignment: Text.AlignVCenter
                    font.weight: Font.Medium
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
                id: countdownResetButton
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 35
                implicitWidth: countdownControlsRow.tightControls ? 74 : 90
                buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full
                onClicked: {
                    TimerService.resetCountdown()
                    countdownHourglass.triggerFlip()
                }
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

                contentItem: Item {
                    Rectangle {
                        anchors.fill: parent
                        radius: countdownResetButton.buttonRadius
                        visible: !countdownResetButton.enabled
                        color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                            : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                            : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface
                            : Appearance.colors.colLayer2
                    }
                    StyledText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.weight: Font.Medium
                        text: Translation.tr("Reset")
                        color: !countdownResetButton.enabled
                            ? root._colText
                            : Appearance.angelEverywhere ? Appearance.angel.colText
                                : Appearance.alisEverywhere ? Appearance.alis.colText
                                : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer2
                                : Appearance.colors.colOnErrorContainer
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                id: countdownCustomizeButton
                objectName: "countdownCustomizeButton"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.compactMode ? 34 : 36
                implicitHeight: root.compactMode ? 34 : 36
                buttonRadius: height / 2
                enabled: !TimerService.countdownRunning
                toggled: root.settingsOpen
                colBackground: root._colLayer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colBackgroundToggled: Appearance.colors.colPrimaryContainer
                colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                onClicked: root.settingsOpen = !root.settingsOpen

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.settingsOpen ? "close" : "tune"
                        iconSize: 20
                        color: root.settingsOpen
                            ? Appearance.colors.colOnPrimaryContainer
                            : root._colText
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Customize timer")
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
