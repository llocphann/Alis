pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks as Waffle

Item {
    id: root
    objectName: "waffleSettingsTitleBar"

    property bool canGoBack: false
    property bool embedded: false
    property bool isOverlay: true
    property string editButtonObjectName: ""

    signal backRequested()
    signal toggleEditLayout()
    signal switchModeRequested()
    signal lockRequested()
    signal closeRequested()

    implicitHeight: Waffle.Looks.dp(38)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: root.embedded ? 6 : 0
        spacing: 4

        Waffle.WBorderlessButton {
            objectName: "waffleSettingsBackButton"
            implicitWidth: Waffle.Looks.dp(36)
            implicitHeight: Waffle.Looks.dp(30)
            Layout.alignment: Qt.AlignVCenter
            enabled: root.canGoBack
            opacity: enabled ? 1.0 : 0.38
            onClicked: root.backRequested()

            contentItem: Item {
                Waffle.FluentIcon {
                    anchors.centerIn: parent
                    monochrome: true
                    icon: "arrow-left"
                    implicitSize: Waffle.Looks.dp(15)
                    color: SettingsMaterialPreset.textColor
                }
            }

            Waffle.WToolTip {
                text: Translation.tr("Back")
            }
        }

        Row {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4
            spacing: 8

            Waffle.FluentIcon {
                anchors.verticalCenter: parent.verticalCenter
                monochrome: true
                icon: "settings"
                implicitSize: Waffle.Looks.dp(16)
                color: SettingsMaterialPreset.accentColor
            }

            Waffle.WText {
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Settings")
                font.pixelSize: Waffle.Looks.font.pixelSize.normal
                color: SettingsMaterialPreset.textColor
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Waffle.WBorderlessButton {
            objectName: root.editButtonObjectName
            implicitWidth: Waffle.Looks.dp(34)
            implicitHeight: Waffle.Looks.dp(30)
            Layout.alignment: Qt.AlignVCenter
            checked: SettingsLayoutManager.editMode
            onClicked: root.toggleEditLayout()

            contentItem: Item {
                Waffle.FluentIcon {
                    anchors.centerIn: parent
                    monochrome: true
                    icon: SettingsLayoutManager.editMode ? "checkmark" : "options"
                    implicitSize: Waffle.Looks.dp(15)
                    color: SettingsLayoutManager.editMode
                        ? Waffle.Looks.colors.accentFg
                        : SettingsMaterialPreset.textColor
                }
            }

            Waffle.WToolTip {
                text: SettingsLayoutManager.editMode
                    ? Translation.tr("Finish editing Settings layout")
                    : Translation.tr("Edit Settings layout & cards")
            }
        }

        Waffle.WBorderlessButton {
            implicitWidth: Waffle.Looks.dp(34)
            implicitHeight: Waffle.Looks.dp(30)
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.switchModeRequested()

            contentItem: Item {
                Waffle.FluentIcon {
                    anchors.centerIn: parent
                    monochrome: true
                    icon: root.isOverlay ? "open" : "panel-left-expand"
                    implicitSize: Waffle.Looks.dp(15)
                    color: SettingsMaterialPreset.textColor
                }
            }

            Waffle.WToolTip {
                text: root.isOverlay
                    ? Translation.tr("Switch to window mode")
                    : Translation.tr("Switch to overlay mode")
            }
        }

        Waffle.WBorderlessButton {
            implicitWidth: Waffle.Looks.dp(34)
            implicitHeight: Waffle.Looks.dp(30)
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.lockRequested()

            contentItem: Item {
                Waffle.FluentIcon {
                    anchors.centerIn: parent
                    monochrome: true
                    icon: "lock-closed"
                    implicitSize: Waffle.Looks.dp(15)
                    color: SettingsMaterialPreset.textColor
                }
            }

            Waffle.WToolTip {
                text: Translation.tr("Lock session")
            }
        }

        Waffle.WBorderlessButton {
            id: closeCaptionBtn
            implicitWidth: root.embedded ? Waffle.Looks.dp(34) : Waffle.Looks.dp(44)
            implicitHeight: root.embedded ? Waffle.Looks.dp(30) : Waffle.Looks.dp(32)
            Layout.alignment: Qt.AlignVCenter
            colBackgroundHover: "#C42B1C"
            colBackgroundActive: "#A82417"
            onClicked: root.closeRequested()

            contentItem: Item {
                Waffle.FluentIcon {
                    anchors.centerIn: parent
                    monochrome: true
                    icon: "dismiss"
                    implicitSize: Waffle.Looks.dp(14)
                    color: closeCaptionBtn.hovered ? "#FFFFFF" : SettingsMaterialPreset.textColor
                }
            }

            Waffle.WToolTip {
                text: Translation.tr("Close Settings")
            }
        }
    }
}
