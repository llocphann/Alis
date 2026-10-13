import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell
import Quickshell.Wayland

WindowDialog {
    id: root
    liquidVacancyRole: "connectivityDialog"
    property bool showEmbeddedFooter: true
    backgroundHeight: 450

    WindowDialogTitle {
        text: Translation.tr("Bluetooth devices")
    }
    WindowDialogSeparator {
        visible: !(Bluetooth.defaultAdapter?.discovering ?? false)
    }
    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -(Appearance.angelEverywhere ? Appearance.angel.roundingNormal : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.large)
        Layout.rightMargin: -(Appearance.angelEverywhere ? Appearance.angel.roundingNormal : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.large)
    }
    StyledListView {
        id: deviceList
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -(Appearance.angelEverywhere ? Appearance.angel.roundingNormal : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.large)
        Layout.rightMargin: -(Appearance.angelEverywhere ? Appearance.angel.roundingNormal : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.large)
        leftMargin: 8
        rightMargin: 8
        topMargin: 8
        bottomMargin: 8

        clip: true
        spacing: 4
        animateAppearance: false

        header: Item {
            width: deviceList.width
            height: deviceList.count === 0 ? deviceList.height : 0
            visible: height > 0

            StyledText {
                anchors {
                    centerIn: parent
                    leftMargin: 24
                    rightMargin: 24
                }
                width: Math.max(0, parent.width - 48)
                text: !BluetoothStatus.available
                    ? Translation.tr("Bluetooth is unavailable")
                    : (Bluetooth.defaultAdapter?.discovering ?? false)
                        ? Translation.tr("Searching for Bluetooth devices…")
                        : Translation.tr("No Bluetooth devices found")
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        model: ScriptModel {
            values: [...Bluetooth.devices.values].sort((a, b) => {
                // Connected -> paired -> others
                let conn = (b.connected - a.connected) || (b.paired - a.paired);
                if (conn !== 0) return conn;

                // Ones with meaningful names before MAC addresses
                const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
                const aIsMac = macRegex.test(a.name);
                const bIsMac = macRegex.test(b.name);
                if (aIsMac !== bIsMac) return aIsMac ? 1 : -1;

                // Alphabetical by name
                return a.name.localeCompare(b.name);
            })
        }
        delegate: BluetoothDeviceItem {
            required property BluetoothDevice modelData
            device: modelData
            anchors {
                left: parent?.left
                right: parent?.right
                leftMargin: 8
                rightMargin: 8
            }
        }
    }
    WindowDialogSeparator {
        visible: !root.effectiveEmbedded || root.showEmbeddedFooter
    }
    WindowDialogButtonRow {
        visible: !root.effectiveEmbedded || root.showEmbeddedFooter
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                AppLauncher.launch("bluetooth")
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
