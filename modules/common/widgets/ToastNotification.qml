import Qt5Compat.GraphicalEffects as GE
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root

    property string title: ""
    property string message: ""
    property string icon: "info"
    property bool isError: false
    property int duration: 3000
    property string source: "system" // "reload", "error", or another system source
    // Successful reload toasts are informational and self-dismiss through the
    // existing progress timer. Errors retain explicit dismissal/copy actions.
    readonly property bool showDismissButton: root.source !== "reload"
    property color accentColor: Appearance.colors.colPrimary
    // Connected hosts provide the outer iRiS plate/shadow. Keep this component
    // as the interactive/content layer so reload toasts can become one attached block.
    property bool connectedSurface: false
    property bool copied: false

    signal dismissed()
    signal copyRequested()

    implicitWidth: card.width
    implicitHeight: card.height
    layer.enabled: Appearance.effectsEnabled && !root.connectedSurface

    GlassBackground {
        id: card

        width: contentLayout.implicitWidth + 32
        height: contentLayout.implicitHeight + 20
        radius: Appearance.rounding.normal
        fallbackColor: root.connectedSurface ? "transparent" : Appearance.colors.colLayer1
        alisColor: root.connectedSurface ? "transparent" : Appearance.alis.colLayer2
        auroraTransparency: Appearance.aurora.popupTransparentize
        wallpaperBackdropEnabled: !root.connectedSurface
        border.width: root.connectedSurface ? 0 : 1
        border.color: root.isError ? Appearance.colors.colError : Appearance.colors.colOutlineVariant
        Component.onCompleted: progressAnim.start()

        MouseArea {
            id: mouseArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.dismissed()
        }

        RowLayout {
            id: contentLayout

            anchors.centerIn: parent
            anchors.leftMargin: 20
            spacing: 10

            Item {
                implicitWidth: 20
                implicitHeight: implicitWidth

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: 20
                    color: root.isError
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnLayer1
                }
            }

            // Content
            ColumnLayout {
                spacing: 2
                Layout.maximumWidth: 400

                StyledText {
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    visible: root.message !== ""
                    text: root.message.length > 100 ? root.message.substring(0, 100) + "..." : root.message
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    Layout.maximumWidth: 350
                }

            }

            // Copy button (only for errors with message)
            RippleButton {
                visible: root.isError && root.message !== ""
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colLayer2Hover
                colRipple: Qt.rgba(0, 0, 0, 0.15)
                onClicked: {
                    if (Quickshell.env("QS_DEBUG") === "1") console.log("[Toast] Copying to clipboard:", root.message.substring(0, 50));
                    copyProcess.running = true;
                    root.copied = true;
                    copyResetTimer.restart();
                }

                Process {
                    id: copyProcess

                    command: ["wl-copy", root.message]
                }

                StyledToolTip {
                    text: root.copied ? "Copied!" : "Copy error"
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.copied ? "check" : "content_copy"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                }

            }

            // Close button. Reload-success toasts intentionally rely on the
            // existing timeout/progress contract instead of an extra X affordance.
            RippleButton {
                visible: root.showDismissButton
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colLayer2Hover
                colRipple: Qt.rgba(0, 0, 0, 0.15)
                onClicked: root.dismissed()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                }

            }

        }

        // Progress bar (centered, shorter)
        Rectangle {
            id: progressBar

            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 6
            height: 3
            radius: Appearance.rounding.unsharpen
            color: root.isError ? Appearance.colors.colError : Appearance.colors.colPrimary

            PropertyAnimation {
                id: progressAnim

                target: progressBar
                property: "width"
                from: Math.min(card.width * 0.5, 120)
                to: 0
                duration: root.duration
                onFinished: root.dismissed()
                paused: mouseArea.containsMouse
            }

        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 6
            height: 3
            radius: Appearance.rounding.unsharpen
            width: Math.min(card.width * 0.5, 120)
            color: Qt.rgba(0, 0, 0, 0.1)
            z: -1
        }

    }

    Timer {
        id: copyResetTimer

        interval: 2000
        onTriggered: root.copied = false
    }

    layer.effect: GE.DropShadow {
        horizontalOffset: 0
        verticalOffset: 4
        radius: Appearance.rounding.small
        samples: 25
        color: Appearance.colors.colShadow
    }

}
