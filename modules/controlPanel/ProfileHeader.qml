pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects as GE
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    implicitHeight: 56
    Layout.fillWidth: true

    readonly property string greeting: {
        const hour = DateTime.clock.hours
        if (hour < 5) return Translation.tr("Good Night")
        if (hour < 12) return Translation.tr("Good Morning")
        if (hour < 18) return Translation.tr("Good Afternoon")
        return Translation.tr("Good Evening")
    }

    function openAccountSettings(): void {
        AppLauncher.launch("manageUser")
        GlobalStates.controlPanelOpen = false
    }

    function lockScreen(): void {
        GlobalStates.controlPanelOpen = false
        Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "lock", "activate"])
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        Item {
            id: avatarContainer
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Appearance.colors.colPrimary
            }

            Item {
                anchors.centerIn: parent
                width: 42
                height: 42

                Rectangle {
                    id: avatarMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }

                Image {
                    id: avatarImg
                    anchors.fill: parent
                    source: profileAvatarResolver.resolvedSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    sourceSize.width: 84
                    sourceSize.height: 84
                    opacity: status === Image.Ready ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    layer.enabled: status === Image.Ready
                    layer.effect: GE.OpacityMask {
                        maskSource: avatarMask
                    }
                }

                QtObject {
                    id: profileAvatarResolver
                    property int avatarIndex: 0
                    readonly property string resolvedSource: Directories.avatarSourceAt(avatarIndex)
                    readonly property string primaryWatch: Directories.userAvatarSourcePrimary

                    onPrimaryWatchChanged: avatarIndex = 0

                    readonly property int imgStatus: avatarImg.status
                    onImgStatusChanged: {
                        if (imgStatus === Image.Error) {
                            const nextIdx = avatarIndex + 1
                            if (nextIdx < Directories.userAvatarPaths.length)
                                avatarIndex = nextIdx
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colLayer2
                    opacity: avatarImg.status !== Image.Ready ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }

        ColumnLayout {
            spacing: 0

            StyledText {
                text: root.greeting
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: SystemInfo.displayName || SystemInfo.username
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                font.capitalization: Font.Capitalize
                color: Appearance.colors.colOnLayer0
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: 4

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonText: Translation.tr("Lock")
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.lockScreen()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "lock"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer0
                }
                StyledToolTip { text: Translation.tr("Lock") }
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonText: Translation.tr("Manage my account")
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.openAccountSettings()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "manage_accounts"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer0
                }
                StyledToolTip { text: Translation.tr("Manage my account") }
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonText: Translation.tr("Power")
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    GlobalStates.controlPanelOpen = false
                    GlobalStates.sessionOpen = true
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    iconSize: 18
                    color: Appearance.colors.colError
                }
                StyledToolTip { text: Translation.tr("Power") }
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonText: Translation.tr("Close")
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: GlobalStates.controlPanelOpen = false
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Close") }
            }
        }
    }
}
