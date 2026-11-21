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

    readonly property real _viewportWidth: Math.max(0, flickable.width)
    readonly property real _viewportHeight: Math.max(0, flickable.height)
    readonly property real _sideInset: _viewportWidth > 0 && _viewportWidth < 300 ? 6
        : (_viewportWidth < 420 ? 10 : 14)
    readonly property real _contentWidth: _viewportWidth > 0
        ? Math.min(Math.max(0, _viewportWidth - _sideInset * 2), 520)
        : 0
    readonly property bool _tightWidth: _viewportWidth > 0 && _viewportWidth < 305
    readonly property bool _wideLayout: _viewportWidth >= 460
    readonly property bool _tallLayout: _viewportHeight >= 280
    readonly property bool _stackedDeck: _viewportWidth > 0 && _viewportWidth < 295 && _viewportHeight >= 290
    readonly property real _controlHeight: _tallLayout && !_tightWidth ? 38 : (root.compactMode ? 34 : 35)
    readonly property real _presetHeight: _tallLayout ? 32 : (root.compactMode ? 28 : 30)
    readonly property real _bottomPadding: _viewportHeight > 220
        ? Math.min(14, Math.max(2, Math.round((_viewportHeight - 200) * 0.05)))
        : (root.compactMode ? 2 : 4)
    readonly property bool _presetsVisible: root.editMode && !root.settingsOpen
    readonly property real _stageAvailHeight: Math.max(
        100,
        _viewportHeight - (_presetsVisible ? (_presetHeight + 10) : 0) - (_controlHeight + _bottomPadding + 10))
    readonly property real _hourglassHeight: {
        if (_viewportWidth <= 0 || _viewportHeight <= 0)
            return root.compactMode ? 96 : 126
        if (_stackedDeck)
            return Math.max(82, Math.min(164, Math.round(Math.min(_stageAvailHeight * 0.46, _contentWidth * 0.58))))
        return Math.max(74, Math.min(176, Math.round(Math.min(_stageAvailHeight * 0.78, _contentWidth * 0.36))))
    }
    readonly property real _hourglassWidth: Math.round(_hourglassHeight * 120 / 144)
    readonly property real _stageSpacing: _stackedDeck
        ? Math.max(8, Math.min(14, Math.round(_stageAvailHeight * 0.04)))
        : (_tightWidth ? 8 : (_wideLayout ? 20 : 14))
    readonly property real _readoutMaxWidth: _stackedDeck
        ? Math.max(120, _contentWidth - 8)
        : Math.max(114, _contentWidth - _hourglassWidth - _stageSpacing)
    readonly property int _timeBoxWidth: Math.min(
        _tightWidth ? 46 : (_wideLayout ? 62 : 52),
        Math.max(42, Math.floor((_readoutMaxWidth - 18) / 2)))
    readonly property int _timeBoxHeight: _tallLayout ? 52 : (root.compactMode ? 44 : 50)
    readonly property int _editFontSize: {
        const baseSize = Math.max(26, Math.min(40, Math.round(_hourglassHeight * 0.30)))
        const scaled = Math.round(baseSize * Appearance.fontSizeScale)
        return Math.min(scaled, Math.max(22, Math.floor(_timeBoxWidth * 0.72)))
    }
    readonly property int _runningFontSize: {
        const baseSize = Math.max(26, Math.min(48, Math.round(_hourglassHeight * 0.32)))
        const scaled = Math.round(baseSize * Appearance.fontSizeScale)
        const widthCap = _viewportWidth > 0 ? Math.max(22, Math.floor(_readoutMaxWidth / 2.95)) : scaled
        return Math.min(scaled, widthCap)
    }

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentColumn.height
        clip: true
        interactive: contentColumn.implicitHeight > flickable.height

        ColumnLayout {
            id: contentColumn
            width: flickable.width
            height: Math.max(implicitHeight, flickable.height)
            spacing: 0

            Item {
                id: timerDeck
                objectName: "countdownTimerDeck"
                visible: !root.settingsOpen || TimerService.countdownRunning
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root._contentWidth
                Layout.maximumWidth: root._contentWidth
                Layout.fillHeight: true
                Layout.minimumHeight: Math.max(
                    100,
                    root._stackedDeck
                        ? (root._hourglassHeight + root._stageSpacing + countdownReadoutColumn.implicitHeight + 8)
                        : Math.max(root._hourglassHeight, countdownReadoutColumn.implicitHeight) + 8)

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

                GridLayout {
                    id: countdownDeckRow
                    objectName: "countdownDeckRow"
                    anchors.centerIn: parent
                    width: Math.min(parent.width, implicitWidth)
                    columns: root._stackedDeck ? 1 : 2
                    columnSpacing: root._stageSpacing
                    rowSpacing: root._stageSpacing

                    HourglassVisual {
                        id: countdownHourglass
                        objectName: "countdownHourglass"
                        Layout.alignment: root._stackedDeck ? Qt.AlignHCenter : Qt.AlignVCenter
                        Layout.preferredWidth: root._hourglassWidth
                        Layout.preferredHeight: root._hourglassHeight
                        visualStyle: TimerService.visualStyle
                        progress: timerDeck.progress
                        running: TimerService.countdownRunning
                        paused: TimerService.countdownPaused
                        accentColor: root._colAccent
                        textColor: root._colText
                    }

                    ColumnLayout {
                        id: countdownReadoutColumn
                        Layout.alignment: root._stackedDeck ? Qt.AlignHCenter : Qt.AlignVCenter
                        Layout.maximumWidth: root._readoutMaxWidth
                        spacing: root._tallLayout ? 6 : 4

                        // Share one fixed slot for edit & running displays so
                        // opacity cross-fades never double readout height.
                        Item {
                            id: countdownTimeSlot
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: Math.min(root._readoutMaxWidth,
                                Math.max(editTimeRow.implicitWidth, runningTimeText.implicitWidth))
                            implicitHeight: Math.max(root._timeBoxHeight, runningTimeText.implicitHeight)

                            // Editable time display with separate minutes and seconds.
                            RowLayout {
                                id: editTimeRow
                                anchors.centerIn: parent
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
                                    implicitWidth: root._timeBoxWidth
                                    implicitHeight: root._timeBoxHeight
                                    width: root._timeBoxWidth
                                    height: root._timeBoxHeight
                                    color: minutesInput.activeFocus
                                        ? ColorUtils.transparentize(root._colAccent, 0.82)
                                        : "transparent"
                                    radius: Appearance.rounding.small
                                    border.width: minutesInput.activeFocus ? 1 : 0
                                    border.color: root._colAccent

                                    TextInput {
                                        id: minutesInput
                                        anchors.centerIn: parent
                                        width: parent.width - 6
                                        text: Math.floor(
                                            TimerService.countdownDuration / 60)
                                            .toString().padStart(2, '0')
                                        font.pixelSize: root._editFontSize
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
                                    font.pixelSize: Math.max(20, root._editFontSize - 2)
                                    font.family: Appearance.font.family.numbers
                                    verticalAlignment: Text.AlignVCenter
                                    color: root._colSubtext
                                }

                                Rectangle {
                                    implicitWidth: root._timeBoxWidth
                                    implicitHeight: root._timeBoxHeight
                                    width: root._timeBoxWidth
                                    height: root._timeBoxHeight
                                    color: secondsInput.activeFocus
                                        ? ColorUtils.transparentize(root._colAccent, 0.82)
                                        : "transparent"
                                    radius: Appearance.rounding.small
                                    border.width: secondsInput.activeFocus ? 1 : 0
                                    border.color: root._colAccent

                                    TextInput {
                                        id: secondsInput
                                        anchors.centerIn: parent
                                        width: parent.width - 6
                                        text: Math.floor(
                                            TimerService.countdownDuration % 60)
                                            .toString().padStart(2, '0')
                                        font.pixelSize: root._editFontSize
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
                                id: runningTimeText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, root._readoutMaxWidth)
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
                                font.pixelSize: root._runningFontSize
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
                        }

                        Row {
                            id: countdownStatusRow
                            objectName: "countdownStatusRow"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 2
                            spacing: 6

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(
                                    implicitWidth,
                                    Math.max(40, root._readoutMaxWidth
                                        - (countdownPercentText.visible ? countdownPercentText.implicitWidth + 6 : 0)))
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: root.editMode
                                    ? Translation.tr("Set duration")
                                    : TimerService.countdownRunning
                                        ? Translation.tr("Running")
                                        : Translation.tr("Paused")
                                font.pixelSize: root._tallLayout
                                    ? Appearance.font.pixelSize.small
                                    : (root.compactMode
                                        ? Appearance.font.pixelSize.smaller
                                        : Appearance.font.pixelSize.small)
                                font.weight: Font.Medium
                                color: root._colSubtext
                            }

                            StyledText {
                                id: countdownPercentText
                                anchors.verticalCenter: parent.verticalCenter
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

            // Center inline style customize card vertically on tall Edgebars
            Item {
                visible: countdownSettingsCard.active
                Layout.fillHeight: true
                Layout.minimumHeight: 0
            }

            // Inline Style Customize card (Turned, Matrix, Square)
            Item {
                id: countdownSettingsCard
                objectName: "countdownSettingsCard"
                readonly property bool active: root.settingsOpen && !TimerService.countdownRunning
                readonly property real targetHeight: active ? settingsInner.implicitHeight + (root.compactMode ? 16 : 20) : 0
                visible: active || Layout.maximumHeight > 0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root._contentWidth
                Layout.maximumWidth: root._contentWidth
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
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
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
                                elide: Text.ElideRight
                                maximumLineCount: 1
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

            // Balance vertical centering for inline style card on tall Edgebars
            Item {
                visible: countdownSettingsCard.active
                Layout.fillHeight: true
                Layout.minimumHeight: 0
            }

            RowLayout {
                id: countdownPresetsRow
                objectName: "countdownPresetsRow"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(root._contentWidth, root._wideLayout ? 360 : 284)
                Layout.maximumWidth: root._contentWidth
                Layout.topMargin: root.compactMode ? 4 : 8
                spacing: root._tightWidth ? 4 : 6
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
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        implicitHeight: root._presetHeight
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
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: modelData.label
                            font.pixelSize: root._tightWidth
                                ? Math.min(Appearance.font.pixelSize.smaller, 12)
                                : Appearance.font.pixelSize.smaller
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
                objectName: "countdownControlsRow"
                readonly property bool tightControls: root._tightWidth
                readonly property int _btnFontSize: tightControls
                    ? Math.min(Appearance.font.pixelSize.normal, 15)
                    : Appearance.font.pixelSize.normal
                readonly property real _iconBtnSize: tightControls ? 32 : root._controlHeight
                readonly property real _desiredStartW: Math.max(
                    tightControls ? 76 : (root._wideLayout ? 102 : 90),
                    Math.ceil(countdownStartLabel.implicitWidth) + (tightControls ? 18 : 24))
                readonly property real _desiredResetW: Math.max(
                    tightControls ? 72 : (root._wideLayout ? 96 : 86),
                    Math.ceil(countdownResetLabel.implicitWidth) + (tightControls ? 16 : 22))
                readonly property real _availTextBtnsW: Math.max(
                    80, root._contentWidth - _iconBtnSize - spacing * 2)
                readonly property real _textScale: (_desiredStartW + _desiredResetW) > _availTextBtnsW
                    ? (_availTextBtnsW / (_desiredStartW + _desiredResetW))
                    : 1.0
                readonly property real _startW: Math.floor(_desiredStartW * _textScale)
                readonly property real _resetW: Math.floor(_desiredResetW * _textScale)
                readonly property real _buttonsTotalWidth: _startW + _resetW + _iconBtnSize
                readonly property bool _canMirrorCustomize:
                    (root._contentWidth - _buttonsTotalWidth - spacing * 5) >= _iconBtnSize
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root._contentWidth
                Layout.maximumWidth: root._contentWidth
                Layout.topMargin: (root.editMode && !root.settingsOpen) ? (root.compactMode ? 6 : 8) : 2
                Layout.bottomMargin: root._bottomPadding
                spacing: tightControls ? 6 : (root._wideLayout ? 10 : 8)

                // Mirror trailing Customize button only when full symmetry fits;
                // on narrow (280px) popups, center the entire control cluster cleanly.
                Item {
                    visible: countdownControlsRow._canMirrorCustomize
                    Layout.preferredWidth: countdownControlsRow._iconBtnSize
                    Layout.preferredHeight: 1
                }

                Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }

                RippleButton {
                    id: countdownStartButton
                    objectName: "countdownStartButton"
                    Layout.alignment: Qt.AlignVCenter
                    leftPadding: 6
                    rightPadding: 6
                    implicitHeight: root._controlHeight
                    implicitWidth: countdownControlsRow._startW
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
                        id: countdownStartLabel
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: countdownControlsRow._btnFontSize
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
                    objectName: "countdownResetButton"
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: root._controlHeight
                    implicitWidth: countdownControlsRow._resetW
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
                            id: countdownResetLabel
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.pixelSize: countdownControlsRow._btnFontSize
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

                Item {
                    visible: countdownControlsRow._canMirrorCustomize
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }

                RippleButton {
                    id: countdownCustomizeButton
                    objectName: "countdownCustomizeButton"
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: countdownControlsRow._iconBtnSize
                    implicitHeight: root._controlHeight
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

                Item {
                    visible: !countdownControlsRow._canMirrorCustomize
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
            }
        }
    }
}
