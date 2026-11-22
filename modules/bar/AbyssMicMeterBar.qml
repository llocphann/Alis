pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id: root

    property bool expanded: false
    property bool pinned: false
    property bool isMuted: Audio.micMuted
    property bool isInUse: false
    property real contentRotation: 0
    property real anchorX: 0
    property real anchorWidth: 26 * Appearance.sizes.barModuleScale
    property real fullWidth: width
    property real levelOverride: -1
    property real peakOverride: -1

    readonly property real progress: _progress
    readonly property bool hovered: pillHover.hovered || micMouse.containsMouse || pinMouse.containsMouse

    signal micClicked()
    signal pinToggled()

    readonly property real barScale: Appearance.sizes.barModuleScale
    readonly property bool darkMode: Appearance.m3colors.darkmode
    readonly property color inkColor: root.darkMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1
    readonly property color mutedInkColor: root.darkMode ? AbyssStyle.textColorMuted : Appearance.colors.colSubtext

    readonly property real effectiveLevel: root.isMuted
        ? 0
        : Math.max(0, Math.min(1, root.levelOverride >= 0 ? root.levelOverride : MicLevelService.level))
    readonly property real effectivePeak: root.isMuted
        ? 0
        : Math.max(root.effectiveLevel, Math.max(0, Math.min(1, root.peakOverride >= 0 ? root.peakOverride : MicLevelService.peak)))
    readonly property bool clipping: !root.isMuted && root.effectivePeak >= 0.86

    property bool _subscribed: false
    readonly property bool wantsSamples: root.expanded && root.visible && root.enabled
        && (root.QsWindow.window?.visible ?? true) && root.levelOverride < 0

    function _syncSubscription(): void {
        if (root.wantsSamples && !root._subscribed) {
            root._subscribed = true
            MicLevelService.subscribe()
        } else if (!root.wantsSamples && root._subscribed) {
            root._subscribed = false
            MicLevelService.unsubscribe()
        }
    }

    onWantsSamplesChanged: root._syncSubscription()
    Component.onCompleted: root._syncSubscription()
    Component.onDestruction: {
        if (root._subscribed) {
            root._subscribed = false
            MicLevelService.unsubscribe()
        }
    }

    property real _progress: root.expanded ? 1 : 0
    Behavior on _progress {
        enabled: AbyssStyle.motionEnabled
        NumberAnimation {
            duration: AbyssStyle.motionNormal
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: pillFrame
        objectName: "abyssMicMeterPill"
        visible: root._progress > 0.001

        readonly property real targetW: Math.max(root.anchorWidth, root.fullWidth)
        readonly property bool tightWidth: targetW < 78 * root.barScale
        readonly property real iconSlotWidth: Math.round((tightWidth ? 20 : 24) * root.barScale)
        readonly property real sidePad: Math.max(2, Math.round(2 * root.barScale))
        readonly property real trackGap: Math.max(2, Math.round(4 * root.barScale))
        readonly property real contentReveal: Math.max(0, Math.min(1, (root._progress - 0.22) / 0.65))

        x: root.anchorX * (1 - root._progress)
        width: root.anchorWidth + (targetW - root.anchorWidth) * root._progress
        height: Math.min(root.height > 0 ? root.height : Math.round(26 * root.barScale), Math.round(26 * root.barScale))
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        HoverHandler {
            id: pillHover
        }

        Rectangle {
            id: pillBackground
            anchors.fill: parent
            radius: height / 2
            color: root.darkMode
                ? Qt.alpha(ColorUtils.mix(AbyssStyle.surfaceDeep, AbyssStyle.accent, root.pinned ? 0.84 : 0.90),
                    Math.max(0.84, AbyssStyle.contentOpacity))
                : Qt.alpha(ColorUtils.mix(Appearance.colors.colLayer1Base, AbyssStyle.accent, root.pinned ? 0.86 : 0.92),
                    Math.max(0.88, AbyssStyle.contentOpacity))
            border.width: 1
            border.color: root.clipping
                ? Qt.alpha(Appearance.colors.colError, 0.65)
                : root.isMuted
                    ? Qt.alpha(root.mutedInkColor, 0.22)
                    : root.pinned
                        ? Qt.alpha(AbyssStyle.accent, 0.55)
                        : Qt.alpha(AbyssStyle.accent, 0.28)

            Behavior on border.color {
                enabled: AbyssStyle.motionEnabled
                ColorAnimation { duration: AbyssStyle.motionFast }
            }

            Rectangle {
                visible: AbyssStyle.highlightStrength > 0
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 1
                    leftMargin: Math.max(6, parent.radius * 0.6)
                    rightMargin: Math.max(6, parent.radius * 0.6)
                }
                height: 1
                color: Qt.alpha(AbyssStyle.specular, Math.min(0.28, 0.24 * AbyssStyle.highlightStrength))
            }
        }

        MouseArea {
            id: micMouse
            objectName: "abyssMicMeterMicButton"
            anchors {
                left: parent.left
                leftMargin: pillFrame.sidePad
                verticalCenter: parent.verticalCenter
            }
            width: Math.min(pillFrame.iconSlotWidth, Math.max(16 * root.barScale, pillFrame.width - pillFrame.sidePad * 2))
            height: Math.max(16, pillFrame.height - Math.round(2 * root.barScale))
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            Accessible.role: Accessible.Button
            Accessible.name: root.isMuted
                ? Translation.tr("Unmute microphone")
                : Translation.tr("Mute microphone")
            onClicked: root.micClicked()

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                radius: width / 2
                color: micMouse.containsMouse
                    ? Qt.alpha(AbyssStyle.accent, micMouse.pressed ? 0.24 : 0.14)
                    : Qt.alpha(AbyssStyle.accent, 0)

                Behavior on color {
                    enabled: AbyssStyle.motionEnabled
                    ColorAnimation { duration: AbyssStyle.motionFast }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                rotation: -root.contentRotation
                horizontalAlignment: Qt.AlignHCenter
                fill: root.isInUse && !root.isMuted ? 1 : 0
                animateFill: true
                text: root.isMuted ? "mic_off" : "mic"
                iconSize: Math.round(Appearance.font.pixelSize.large * root.barScale)
                color: root.isMuted
                    ? root.mutedInkColor
                    : (root.isInUse || root.clipping)
                        ? Appearance.colors.colError
                        : root.inkColor
            }

            Rectangle {
                scale: root.isInUse && !root.isMuted ? 1 : 0
                visible: scale > 0
                width: 5 * root.barScale
                height: 5 * root.barScale
                radius: 2.5 * root.barScale
                color: Appearance.colors.colError
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 2
                    rightMargin: 2
                }

                Behavior on scale {
                    enabled: AbyssStyle.motionEnabled
                    NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
                }
            }

            StyledToolTip {
                text: micMouse.Accessible.name
                delay: 700
            }
        }

        Rectangle {
            id: meterTrack
            objectName: "abyssMicMeterTrack"
            anchors {
                left: micMouse.right
                right: pinMouse.left
                leftMargin: pillFrame.trackGap
                rightMargin: pillFrame.trackGap
                verticalCenter: parent.verticalCenter
            }
            height: Math.max(8, Math.round(pillFrame.height - 10 * root.barScale))
            radius: Math.min(height / 2, Math.round(4 * root.barScale))
            clip: true
            visible: pillFrame.contentReveal > 0.01 && width >= 6
            opacity: (root.isMuted ? 0.45 : 1.0) * pillFrame.contentReveal
            color: root.darkMode
                ? Qt.alpha(AbyssStyle.surfaceDeep, 0.68)
                : Qt.alpha(root.inkColor, 0.10)
            border.width: 1
            border.color: root.darkMode
                ? Qt.alpha(AbyssStyle.accent, 0.16)
                : Qt.alpha(root.inkColor, 0.14)

            Rectangle {
                visible: root.isMuted
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 3
                    rightMargin: 3
                    verticalCenter: parent.verticalCenter
                }
                height: 1
                color: Qt.alpha(root.mutedInkColor, 0.35)
            }

            Item {
                id: levelClip
                objectName: "abyssMicMeterLevelFill"
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                    margins: 1
                }
                readonly property real maxFillWidth: Math.max(0, parent.width - 2)
                width: root.isMuted ? 0 : Math.round(maxFillWidth * root.effectiveLevel)
                clip: true

                Behavior on width {
                    enabled: AbyssStyle.motionEnabled && root.levelOverride < 0
                    NumberAnimation { duration: 48; easing.type: Easing.OutQuad }
                }

                Rectangle {
                    width: Math.max(1, levelClip.maxFillWidth)
                    height: levelClip.height
                    radius: Math.max(0, meterTrack.radius - 1)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: ColorUtils.mix("#4CC36B", Appearance.colors.colSuccess, 0.65) }
                        GradientStop { position: 0.58; color: ColorUtils.mix("#4CC36B", Appearance.colors.colSuccess, 0.65) }
                        GradientStop { position: 0.78; color: ColorUtils.mix("#E8B948", Appearance.colors.colWarning, 0.75) }
                        GradientStop { position: 0.94; color: ColorUtils.mix("#E5534B", Appearance.colors.colError, 0.55) }
                        GradientStop { position: 1.00; color: ColorUtils.mix("#E5534B", Appearance.colors.colError, 0.55) }
                    }

                    Rectangle {
                        visible: AbyssStyle.highlightStrength > 0
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Qt.alpha(AbyssStyle.specular, 0.28)
                    }
                }
            }

            Rectangle {
                id: peakMarker
                objectName: "abyssMicMeterPeakMarker"
                z: 2
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    topMargin: 1
                    bottomMargin: 1
                }
                width: Math.max(2, Math.round(2.5 * root.barScale))
                radius: width / 2
                visible: !root.isMuted && root.effectivePeak > 0.015 && meterTrack.width > width + 2
                readonly property real travelWidth: Math.max(0, meterTrack.width - 2 - width)
                x: 1 + Math.max(0, Math.min(travelWidth, Math.round(travelWidth * root.effectivePeak)))
                color: root.clipping ? Appearance.colors.colError : AbyssStyle.specular

                Behavior on x {
                    enabled: AbyssStyle.motionEnabled && root.peakOverride < 0
                    NumberAnimation { duration: 45; easing.type: Easing.OutQuad }
                }
                Behavior on color {
                    enabled: AbyssStyle.motionEnabled
                    ColorAnimation { duration: AbyssStyle.motionFast }
                }
            }
        }

        MouseArea {
            id: pinMouse
            objectName: "abyssMicMeterPinButton"
            anchors {
                right: parent.right
                rightMargin: pillFrame.sidePad
                verticalCenter: parent.verticalCenter
            }
            width: pillFrame.iconSlotWidth
            height: micMouse.height
            opacity: pillFrame.contentReveal
            visible: pillFrame.contentReveal > 0.01 && pillFrame.width > pillFrame.iconSlotWidth * 1.8
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            Accessible.role: Accessible.Button
            Accessible.name: root.pinned
                ? Translation.tr("Unpin microphone meter")
                : Translation.tr("Pin microphone meter")
            onClicked: root.pinToggled()

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                radius: width / 2
                color: root.pinned
                    ? Qt.alpha(AbyssStyle.accent, pinMouse.containsMouse ? 0.28 : 0.20)
                    : pinMouse.containsMouse
                        ? Qt.alpha(AbyssStyle.accent, 0.12)
                        : Qt.alpha(AbyssStyle.accent, 0)
                border.width: root.pinned ? 1 : 0
                border.color: Qt.alpha(AbyssStyle.accent, 0.45)

                Behavior on color {
                    enabled: AbyssStyle.motionEnabled
                    ColorAnimation { duration: AbyssStyle.motionFast }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                rotation: -root.contentRotation
                horizontalAlignment: Qt.AlignHCenter
                fill: root.pinned ? 1 : 0
                animateFill: true
                text: "keep"
                iconSize: Math.round(Appearance.font.pixelSize.normal * root.barScale)
                color: root.pinned
                    ? AbyssStyle.accent
                    : pinMouse.containsMouse ? root.inkColor : root.mutedInkColor
            }

            StyledToolTip {
                text: pinMouse.Accessible.name
                delay: 700
            }
        }
    }
}
