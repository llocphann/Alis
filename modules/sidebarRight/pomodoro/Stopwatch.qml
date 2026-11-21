import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: stopwatchTab
    Layout.fillWidth: true
    Layout.fillHeight: true
    property bool compactMode: false
    property bool centerMode: true

    readonly property real _viewportWidth: Math.max(0, stopwatchTab.width)
    readonly property real _viewportHeight: Math.max(0, stopwatchTab.height)
    readonly property real _sideInset: _viewportWidth > 0 && _viewportWidth < 300 ? 8
        : (_viewportWidth < 420 ? 12 : 16)
    readonly property real _contentWidth: _viewportWidth > 0
        ? Math.min(Math.max(0, _viewportWidth - _sideInset * 2), 520)
        : 0
    readonly property bool _tightWidth: _viewportWidth > 0 && _viewportWidth < 305
    readonly property bool _wideLayout: _viewportWidth >= 460
    readonly property bool _tallLayout: _viewportHeight >= 280
    readonly property bool _hasLaps: TimerService.stopwatchLaps.length > 0
    readonly property real _controlHeight: _tallLayout && !_tightWidth ? 38 : (stopwatchTab.compactMode ? 34 : 35)
    readonly property real _bottomPadding: _viewportHeight > 220
        ? Math.min(14, Math.max(2, Math.round((_viewportHeight - 200) * 0.05)))
        : (stopwatchTab.compactMode ? 2 : 6)
    readonly property int _mainFontSize: {
        const base = _hasLaps
            ? Math.max(30, Math.min(44, Math.round(Math.min(_contentWidth * 0.13, _viewportHeight * 0.16))))
            : Math.max(34, Math.min(56, Math.round(Math.min(_contentWidth * 0.16, _viewportHeight * 0.22))))
        const scaled = Math.round(base * Appearance.fontSizeScale)
        const widthCap = _contentWidth > 0 ? Math.max(24, Math.floor(_contentWidth / 4.7)) : scaled
        return Math.min(scaled, widthCap)
    }

    Item {
        id: stageRoot
        objectName: "stopwatchStage"
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: stopwatchTab._contentWidth

        Item {
            id: heroArea
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: controlButtons.top
                topMargin: stopwatchTab._tallLayout ? 8 : 4
                bottomMargin: 8
            }

            RowLayout { // Elapsed
                id: elapsedIndicator
                objectName: "stopwatchElapsed"

                anchors {
                    top: stopwatchTab.centerMode ? undefined : parent.top
                    topMargin: stopwatchTab.centerMode ? 0 : 6
                    verticalCenter: stopwatchTab.centerMode ? parent.verticalCenter : undefined
                    horizontalCenter: parent.horizontalCenter
                }

                states: State {
                    name: "hasLaps"
                    when: stopwatchTab.centerMode && stopwatchTab._hasLaps
                    AnchorChanges {
                        target: elapsedIndicator
                        anchors.top: parent.top
                        anchors.verticalCenter: undefined
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    PropertyChanges {
                        target: elapsedIndicator
                        anchors.topMargin: 4
                    }
                }

                transitions: Transition {
                    AnchorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                spacing: 2
                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    font.pixelSize: stopwatchTab._mainFontSize
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    text: {
                        let totalSeconds = Math.floor(TimerService.stopwatchTime) / 100
                        let minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                        let seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                        return `${minutes}:${seconds}`
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    font.pixelSize: Math.max(16, Math.round(stopwatchTab._mainFontSize * 0.58))
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                    text: `.${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}`
                }
            }

            // Laps
            StyledListView {
                id: lapsList
                visible: stopwatchTab._hasLaps
                anchors {
                    top: elapsedIndicator.bottom
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 10
                    bottomMargin: 4
                }
                spacing: 4
                clip: true
                popin: true

                model: ScriptModel {
                    values: TimerService.stopwatchLaps.map((v, i, arr) => arr[arr.length - 1 - i])
                }

                delegate: Rectangle {
                    id: lapItem
                    required property int index
                    required property var modelData
                    property var horizontalPadding: 10
                    property var verticalPadding: 6
                    width: lapsList.width
                    implicitHeight: lapRow.implicitHeight + verticalPadding * 2
                    implicitWidth: lapRow.implicitWidth + horizontalPadding * 2
                    color: Appearance.colors.colLayer2
                    radius: Appearance.rounding.small

                    RowLayout {
                        id: lapRow
                        anchors {
                            fill: parent
                            leftMargin: lapItem.horizontalPadding
                            rightMargin: lapItem.horizontalPadding
                            topMargin: lapItem.verticalPadding
                            bottomMargin: lapItem.verticalPadding
                        }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            text: `${TimerService.stopwatchLaps.length - lapItem.index}.`
                        }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: {
                                const lapTime = lapItem.modelData
                                const _10ms = (Math.floor(lapTime) % 100).toString().padStart(2, '0')
                                const totalSeconds = Math.floor(lapTime) / 100
                                const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                                const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                                return `${minutes}:${seconds}.${_10ms}`
                            }
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colPrimary
                            text: {
                                const originalIndex = TimerService.stopwatchLaps.length - lapItem.index - 1
                                const lastTime = originalIndex > 0 ? TimerService.stopwatchLaps[originalIndex - 1] : 0
                                const lapTime = lapItem.modelData - lastTime
                                const _10ms = (Math.floor(lapTime) % 100).toString().padStart(2, '0')
                                const totalSeconds = Math.floor(lapTime) / 100
                                const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                                const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                                return `+${minutes == "00" ? "" : minutes + ":"}${seconds}.${_10ms}`
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            id: controlButtons
            objectName: "stopwatchControlsRow"
            readonly property int _btnFontSize: stopwatchTab._tightWidth
                ? Math.min(Appearance.font.pixelSize.normal, 15)
                : Appearance.font.pixelSize.normal
            readonly property real _baseBtnWidth: stopwatchTab._tightWidth ? 78 : (stopwatchTab._wideLayout ? 102 : 90)
            readonly property real _maxBtnWidth: Math.max(64, Math.floor((stopwatchTab._contentWidth - spacing) / 2))
            readonly property real _btnWidth: Math.min(_maxBtnWidth, Math.max(
                _baseBtnWidth,
                Math.ceil(Math.max(stopwatchStartLabel.implicitWidth, stopwatchResetLabel.implicitWidth)) + (stopwatchTab._tightWidth ? 20 : 24)))
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: stopwatchTab._bottomPadding
            }
            spacing: stopwatchTab._tightWidth ? 6 : (stopwatchTab._wideLayout ? 10 : 8)

            RippleButton {
                id: stopwatchStartButton
                objectName: "stopwatchStartButton"
                Layout.preferredHeight: stopwatchTab._controlHeight
                Layout.preferredWidth: controlButtons._btnWidth
                leftPadding: 6
                rightPadding: 6
                buttonRadius: Appearance.rounding.full
                font.pixelSize: Appearance.font.pixelSize.larger

                onClicked: {
                    TimerService.toggleStopwatch()
                }

                colBackground: (TimerService.stopwatchRunning && !TimerService.stopwatchPaused)
                    ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colPrimary
                colBackgroundHover: (TimerService.stopwatchRunning && !TimerService.stopwatchPaused)
                    ? Appearance.colors.colSecondaryContainerHover
                    : Appearance.colors.colPrimaryHover
                colRipple: (TimerService.stopwatchRunning && !TimerService.stopwatchPaused)
                    ? Appearance.colors.colSecondaryContainerActive
                    : Appearance.colors.colPrimaryActive

                contentItem: StyledText {
                    id: stopwatchStartLabel
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: controlButtons._btnFontSize
                    font.weight: Font.Medium
                    color: (TimerService.stopwatchRunning && !TimerService.stopwatchPaused)
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnPrimary
                    text: (TimerService.stopwatchRunning && !TimerService.stopwatchPaused) ? Translation.tr("Pause")
                        : TimerService.stopwatchTime === 0 ? Translation.tr("Start") : Translation.tr("Resume")
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                }
            }

            RippleButton {
                id: stopwatchResetButton
                objectName: "stopwatchResetButton"
                Layout.preferredHeight: stopwatchTab._controlHeight
                Layout.preferredWidth: controlButtons._btnWidth
                implicitHeight: stopwatchTab._controlHeight
                implicitWidth: controlButtons._btnWidth
                buttonRadius: Appearance.rounding.full
                font.pixelSize: Appearance.font.pixelSize.larger

                onClicked: {
                    if (TimerService.stopwatchRunning && !TimerService.stopwatchPaused)
                        TimerService.stopwatchRecordLap()
                    else
                        TimerService.stopwatchReset()
                }
                enabled: TimerService.stopwatchTime > 0 || TimerService.stopwatchLaps.length > 0

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active

                contentItem: Item {
                    Rectangle {
                        anchors.fill: parent
                        radius: stopwatchResetButton.buttonRadius
                        visible: !stopwatchResetButton.enabled
                        color: Appearance.colors.colLayer2
                    }
                    StyledText {
                        id: stopwatchResetLabel
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: controlButtons._btnFontSize
                        font.weight: Font.Medium
                        text: (TimerService.stopwatchRunning && !TimerService.stopwatchPaused) ? Translation.tr("Lap") : Translation.tr("Reset")
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
