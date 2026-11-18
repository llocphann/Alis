pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    objectName: "bluetoothSettings"
    settingsPageName: Translation.tr("Bluetooth")

    readonly property var pairedDevices: [...(Bluetooth.devices?.values ?? [])].filter(d => Boolean(d?.paired || d?.connected)).sort((a, b) => {
        const conn = Number(Boolean(b?.connected)) - Number(Boolean(a?.connected))
        if (conn !== 0) return conn
        return String(a?.name ?? "").localeCompare(String(b?.name ?? ""))
    })

    readonly property var nearbyDevices: [...(Bluetooth.devices?.values ?? [])].filter(d => !d?.paired && !d?.connected).sort((a, b) => {
        return String(a?.name ?? "").localeCompare(String(b?.name ?? ""))
    })

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "bluetooth"
        title: Translation.tr("Bluetooth Adapter")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: !BluetoothStatus.available
                        ? Translation.tr("Bluetooth adapter unavailable")
                        : BluetoothStatus.connectionTooltip()
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                RippleButtonWithIcon {
                    visible: BluetoothStatus.available && BluetoothStatus.enabled
                    implicitHeight: 32
                    materialIcon: (Bluetooth.defaultAdapter?.discovering ?? false) ? "radar" : "bluetooth_searching"
                    mainText: (Bluetooth.defaultAdapter?.discovering ?? false)
                        ? Translation.tr("Stop scan")
                        : Translation.tr("Scan")
                    onClicked: {
                        if (Bluetooth.defaultAdapter)
                            Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                    }
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                enabled: BluetoothStatus.available
                buttonIcon: "bluetooth"
                text: Translation.tr("Enable Bluetooth")
                checked: BluetoothStatus.enabled
                onCheckedChanged: {
                    if (BluetoothStatus.enabled !== checked)
                        BluetoothStatus.setEnabled(checked)
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                enabled: BluetoothStatus.available && BluetoothStatus.enabled
                buttonIcon: "visibility"
                text: Translation.tr("Discoverable to nearby devices")
                checked: Bluetooth.defaultAdapter?.discoverable ?? false
                onCheckedChanged: {
                    if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discoverable !== checked)
                        Bluetooth.defaultAdapter.discoverable = checked
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "devices"
        title: Translation.tr("Paired Devices")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                visible: root.pairedDevices.length === 0
                text: Translation.tr("No paired Bluetooth devices")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: root.pairedDevices

                delegate: ColumnLayout {
                    id: pairedRow
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 8

                    SettingsDivider {
                        visible: pairedRow.index > 0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialSymbol {
                            text: Icons.getBluetoothDeviceMaterialSymbol(pairedRow.modelData?.icon ?? "")
                            iconSize: Appearance.font.pixelSize.larger
                            color: (pairedRow.modelData?.connected ?? false)
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: pairedRow.modelData?.name || Translation.tr("Unknown device")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: (pairedRow.modelData?.connected ?? false) ? Font.DemiBold : Font.Normal
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    let label = (pairedRow.modelData?.connected ?? false)
                                        ? Translation.tr("Connected")
                                        : Translation.tr("Paired")
                                    if (pairedRow.modelData?.batteryAvailable)
                                        label += " · " + Math.round((pairedRow.modelData?.battery ?? 0) * 100) + "%"
                                    return label
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: (pairedRow.modelData?.connected ?? false)
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        RippleButtonWithIcon {
                            implicitHeight: 30
                            materialIcon: (pairedRow.modelData?.connected ?? false) ? "link_off" : "link"
                            mainText: (pairedRow.modelData?.connected ?? false)
                                ? Translation.tr("Disconnect")
                                : Translation.tr("Connect")
                            onClicked: {
                                if (!pairedRow.modelData) return
                                if (pairedRow.modelData.connected) {
                                    pairedRow.modelData.disconnect()
                                } else {
                                    pairedRow.modelData.trusted = true
                                    pairedRow.modelData.connect()
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colErrorHover
                            onClicked: pairedRow.modelData?.forget()

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            StyledToolTip {
                                text: Translation.tr("Forget device")
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: BluetoothStatus.enabled
        expanded: true
        icon: "bluetooth_searching"
        title: Translation.tr("Available Devices")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                visible: root.nearbyDevices.length === 0
                text: (Bluetooth.defaultAdapter?.discovering ?? false)
                    ? Translation.tr("Scanning for nearby Bluetooth devices…")
                    : Translation.tr("Click Scan above to discover nearby devices")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: root.nearbyDevices

                delegate: ColumnLayout {
                    id: nearbyRow
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 8

                    SettingsDivider {
                        visible: nearbyRow.index > 0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialSymbol {
                            text: Icons.getBluetoothDeviceMaterialSymbol(nearbyRow.modelData?.icon ?? "")
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: nearbyRow.modelData?.name || Translation.tr("Unknown device")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        RippleButtonWithIcon {
                            implicitHeight: 30
                            materialIcon: "add_link"
                            mainText: Translation.tr("Pair")
                            onClicked: {
                                if (!nearbyRow.modelData) return
                                nearbyRow.modelData.trusted = true
                                nearbyRow.modelData.connect()
                            }
                        }
                    }
                }
            }
        }
    }
}
