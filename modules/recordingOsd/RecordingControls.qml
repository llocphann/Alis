pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks
import qs.services

// Shared actions, independent of the native window or connected-field painter.
Item {
    id: root
    required property var owner
    property Item dragTarget: null
    property real dragWidth: 0
    property real dragHeight: 0
    readonly property bool vertical: owner.isVertical
    readonly property bool connected: owner.embeddedMode
    implicitWidth: owner.controlsExpanded ? controls.implicitWidth : 14
    implicitHeight: owner.controlsExpanded ? controls.implicitHeight : 14

    Item {
        objectName: "recordingMinimizedDot"
        anchors.centerIn: parent
        width: 14; height: 14
        visible: !root.owner.controlsExpanded
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Translation.tr("Expand controls")
        Accessible.onPressAction: root.owner.expandControls()
        Keys.onReturnPressed: root.owner.expandControls()
        Keys.onSpacePressed: root.owner.expandControls()
        RecordingDot { anchors.centerIn: parent }
    }

    GridLayout {
        id: controls
        anchors.centerIn: parent
        visible: root.owner.controlsExpanded
        columns: root.vertical ? 1 : 7
        rowSpacing: 2
        columnSpacing: 2
        Item {
            id: handle
            property point lastTranslation: Qt.point(0,0)
            objectName: "recordingDragHandle"
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignCenter
            opacity: hover.hovered || drag.active ? .8 : .4
            Rectangle {
                anchors.fill: parent
                radius: root.connected ? 12 : Appearance.rounding.full
                color: drag.active ? Qt.alpha(AbyssStyle.accent,.24)
                    : hover.hovered ? Qt.alpha(AbyssStyle.accent,.15) : "transparent"
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "drag_indicator"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }
            HoverHandler {
                id: hover
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }
            DragHandler {
                id: drag
                target: root.dragTarget
                xAxis.minimum: root.connected ? -Infinity : 0
                xAxis.maximum: root.connected ? Infinity : root.dragWidth-(root.dragTarget?.width ?? 0)
                yAxis.minimum: root.connected ? -Infinity : 0
                yAxis.maximum: root.connected ? Infinity : root.dragHeight-(root.dragTarget?.height ?? 0)
                onActiveTranslationChanged: if (active) {
                    handle.lastTranslation = activeTranslation
                    if (root.connected) root.owner.dragMoved(activeTranslation)
                }
                onActiveChanged: {
                    if (active) {
                        handle.lastTranslation = Qt.point(0,0)
                        root.owner.dragStarted()
                    } else root.owner.dragFinished(handle.lastTranslation)
                }
            }
        }
        Item {
            id: indicator
            objectName: "recordingTimer"
            readonly property string timeString: root.owner.formatTime(root.owner.recordingStatus.elapsedSeconds)
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.vertical ? vIndicator.implicitWidth : hIndicator.implicitWidth
            implicitHeight: root.vertical ? vIndicator.implicitHeight : hIndicator.implicitHeight
            RowLayout {
                id: hIndicator
                visible: !root.vertical
                anchors.centerIn: parent
                spacing: 4
                RecordingDot { Layout.alignment: Qt.AlignVCenter }
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: timerMetrics.width
                    implicitHeight: timerText.implicitHeight
                    TextMetrics {
                        id: timerMetrics
                        text: root.owner.recordingStatus.elapsedSeconds >= 3600 ? "00:00:00" : "00:00"
                        font: timerText.font
                    }
                    Text {
                        id: timerText
                        anchors.centerIn: parent
                        text: indicator.timeString
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
            ColumnLayout {
                id: vIndicator
                visible: root.vertical
                anchors.centerIn: parent
                spacing: 1
                RecordingDot { Layout.alignment: Qt.AlignHCenter }
                Repeater {
                    model: indicator.timeString.split(/([:])/)
                    Text {
                        required property string modelData
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData === ":" ? "\u00B7\u00B7" : modelData
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: modelData === ":" ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                        opacity: modelData === ":" ? .5 : 1
                    }
                }
            }
        }
        OsdButton {
            objectName: "recordingStop"
            iconName: "stop"
            filled: true
            iconColor: Appearance.colors.colError
            onClicked: root.owner.stopRecording()
            tooltip: Translation.tr("Stop recording")
        }
        Rectangle {
            visible: root.owner.audioMode !== "none"
            Layout.preferredWidth: root.vertical ? 22 : 1
            Layout.preferredHeight: root.vertical ? 1 : 22
            Layout.alignment: Qt.AlignCenter
            color: Appearance.colors.colOutlineVariant
            opacity: .3
        }
        OsdButton {
            objectName: "recordingSystemAudio"
            visible: root.owner.usesSystemAudio
            iconName: root.owner.audioService.sink?.audio?.muted ? "volume_off" : "volume_up"
            dimmed: root.owner.audioService.sink?.audio?.muted ?? false
            onClicked: root.owner.audioService.toggleMute()
            tooltip: dimmed ? Translation.tr("Unmute system audio") : Translation.tr("Mute system audio")
        }
        OsdButton {
            objectName: "recordingMicrophone"
            visible: root.owner.usesMicrophone
            iconName: root.owner.audioService.micMuted ? "mic_off" : "mic"
            dimmed: root.owner.audioService.micMuted
            onClicked: root.owner.audioService.toggleMicMute()
            tooltip: dimmed ? Translation.tr("Unmute mic") : Translation.tr("Mute mic")
        }
        OsdButton {
            objectName: "recordingCollapse"
            iconName: root.owner.collapsed ? "open_in_full" : "close_fullscreen"
            onClicked: {
                if (root.owner.collapsed) root.owner.expandControls()
                else root.owner.minimizeControls()
            }
            tooltip: root.owner.collapsed ? Translation.tr("Expand controls") : Translation.tr("Minimize")
        }
    }
    component RecordingDot: Rectangle {
        width: 8; height: 8; radius: 4
        color: Appearance.colors.colError
        SequentialAnimation on opacity {
            running: Appearance.animationsEnabled && root.owner.recordingStatus.isRecording && root.owner.presentationVisible
                && root.owner.revealed && parent.visible
            loops: Animation.Infinite
            NumberAnimation { to: .2; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
    }
    component OsdButton: RippleButton {
        id: button
        required property string iconName
        property string tooltip: ""
        property bool dimmed: false
        property bool filled: false
        buttonText: tooltip
        property color iconColor: Appearance.colors.colOnLayer2
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        Layout.alignment: Qt.AlignCenter
        buttonRadius: root.connected ? 12 : Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: root.connected ? Qt.alpha(AbyssStyle.accent,.15)
            : Appearance.zzzEverywhere ? Appearance.zzz.bg3
            : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
            : Appearance.colors.colLayer2Hover ?? Appearance.colors.colLayer1Hover
        colRipple: root.connected ? Qt.alpha(AbyssStyle.accent,.24)
            : Appearance.zzzEverywhere ? Appearance.zzz.bg4
            : Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
            : Appearance.colors.colLayer2Active ?? Appearance.colors.colLayer1Active
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: button.iconName
            iconSize: Appearance.font.pixelSize.larger
            fill: button.filled ? 1 : 0
            animateFill: true
            color: button.iconColor
            opacity: button.dimmed ? .4 : 1
        }
        StyledToolTip {
            text: button.tooltip
            visible: button.tooltip && button.buttonHovered
        }
    }
}
