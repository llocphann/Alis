import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

FooterRectangle {

    // Battery button
    WBorderlessButton {
        objectName: "waffleActionCenterBatteryButton"
        visible: Battery.available
        implicitWidth: batteryContentRow.implicitWidth + Looks.dp(18)
        implicitHeight: Looks.dp(36)
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Looks.dp(10)
        onClicked: WaffleNavigation.openSettings("system", "Battery")

        contentItem: Item {
            Row {
                id: batteryContentRow
                anchors.centerIn: parent
                spacing: Looks.dp(6)

                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: WIcons.batteryLevelIcon ?? "battery-0"
                    FluentIcon {
                        anchors.fill: parent
                        icon: WIcons.batteryIcon ?? "battery-0"
                    }
                }
                WText {
                    anchors.verticalCenter: parent.verticalCenter
                    verticalAlignment: Text.AlignVCenter
                    text: `${Math.round((Battery?.percentage ?? 0) * 100)}%`
                }
            }
        }

        WToolTip {
            text: Translation.tr("Battery settings")
        }
    }

    // Settings button
    WBorderlessButton {
        objectName: "waffleActionCenterSettingsButton"
        implicitWidth: Looks.dp(36)
        implicitHeight: Looks.dp(36)
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Looks.dp(10)

        onClicked: WaffleNavigation.openSettings()

        contentItem: Item {
            FluentIcon {
                anchors.centerIn: parent
                icon: "settings"
                implicitSize: Looks.dp(18)
            }
        }

        WToolTip {
            text: Translation.tr("All settings")
        }
    }
}
