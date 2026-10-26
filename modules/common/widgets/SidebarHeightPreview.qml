pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 8

    readonly property var leftState: ShellLayoutController.currentState("featureSidebar", "")
    readonly property var rightState: ShellLayoutController.currentState("systemSidebar", "")
    readonly property real refScreenHeight: Math.max(720, Quickshell.screens?.[0]?.height ?? 1080)
    readonly property bool leftCustom: (leftState?.sizeMode ?? "fit") === "custom"
    readonly property bool rightCustom: (rightState?.sizeMode ?? "fit") === "custom"
    readonly property bool leftFit: !leftCustom
    // The system sidebar is content-sized independently from notification history.
    // Keep the retired notification-fit compatibility key out of presentation state.
    readonly property bool rightFit: !rightCustom
    readonly property real leftRatio: leftCustom
        ? Math.max(0.22, Math.min(1, Number(leftState?.customHeight ?? 700) / refScreenHeight))
        : SidebarGeometry.leftFitPreferredRatio
    readonly property real rightRatio: rightCustom
        ? Math.max(0.22, Math.min(1, Number(rightState?.customHeight ?? 700) / refScreenHeight))
        : SidebarGeometry.rightFitExpandedPreferredRatio
    readonly property int leftBarWidth: Math.round(34 + (Math.max(320, Math.min(900, Number(leftState?.width ?? 460))) - 320) / (900 - 320) * 20)
    readonly property int rightBarWidth: Math.round(34 + (Math.max(320, Math.min(900, Number(rightState?.width ?? 460))) - 320) / (900 - 320) * 20)

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 150
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Item {
            id: monitorPreview
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 360)
            height: 108

            Rectangle {
                id: screenFrame
                anchors.fill: parent
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                Rectangle {
                    id: leftPreview
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 7
                    width: root.leftBarWidth
                    height: Math.max(22, (parent.height - 14) * root.leftRatio)
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colPrimaryContainer
                    border.width: 1
                    border.color: Appearance.colors.colPrimary

                    Behavior on width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    Behavior on height {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                }

                Rectangle {
                    id: rightPreview
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 7
                    width: root.rightBarWidth
                    height: Math.max(22, (parent.height - 14) * root.rightRatio)
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colSecondaryContainer
                    border.width: 1
                    border.color: Appearance.colors.colSecondary

                    Behavior on width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    Behavior on height {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.max(1, parent.height
                            * SidebarGeometry.rightFitCollapsedPreferredRatio
                            / SidebarGeometry.rightFitExpandedPreferredRatio)
                        radius: parent.radius
                        color: "transparent"
                        border.width: root.rightFit ? 1 : 0
                        border.color: Appearance.colors.colOutlineVariant
                        opacity: root.rightFit ? 0.65 : 0
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Left sidebar") + " · "
                + (root.leftCustom
                    ? Math.round(root.leftState?.width ?? 460) + "×" + Math.round(root.leftState?.customHeight ?? 700) + " px"
                    : Translation.tr("Fit") + " " + Math.round(SidebarGeometry.leftFitPreferredRatio * 100) + "% (" + Math.round(root.leftState?.width ?? 460) + " px)")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: Translation.tr("Right sidebar") + " · "
                + (root.rightCustom
                    ? Math.round(root.rightState?.width ?? 460) + "×" + Math.round(root.rightState?.customHeight ?? 700) + " px"
                    : Translation.tr("Fit") + " " + Math.round(SidebarGeometry.rightFitExpandedPreferredRatio * 100) + "% / "
                        + Translation.tr("Compact") + " " + Math.round(SidebarGeometry.rightFitCollapsedPreferredRatio * 100) + "% (" + Math.round(root.rightState?.width ?? 460) + " px)")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
