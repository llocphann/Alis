import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: popup
    readonly property bool thinkFanManaged:
        ThinkFanService.stateKnown && ThinkFanService.profile === "managed"
    readonly property bool thinkFanCanApply:
        ThinkFanService.stateKnown
        && ThinkFanService.serviceInstalled
        && !ThinkFanService.busy
        && (popup.thinkFanManaged || ThinkFanService.available)
    readonly property string thinkFanApplyErrorMessage:
        popup.describeThinkFanApplyError(ThinkFanService.lastApplyError)

    function describeThinkFanApplyError(error): string {
        switch (String(error ?? "")) {
        case "":
            return ""
        case "unsupported-profile":
            return Translation.tr("Unsupported ThinkFan profile")
        case "apply-busy":
            return Translation.tr("Another ThinkFan change is already in progress")
        case "service-unavailable":
            return Translation.tr("thinkfan.service is unavailable")
        case "thinkfan-unavailable":
            return Translation.tr("ThinkFan is unavailable")
        case "apply-start-failed":
            return Translation.tr("Could not start the privileged ThinkFan helper")
        case "apply-timeout":
            return Translation.tr("Changing the ThinkFan profile timed out")
        case "apply-failed":
            return Translation.tr("Changing the ThinkFan profile failed")
        default:
            return Translation.tr("ThinkFan profile change failed: %1").arg(error)
        }
    }

    property QtObject resourceMonitor: ResourceUsageMonitor {
        network: false
        histories: false
        active: popup.presentationActive
    }

    onPresentationActiveChanged: {
        if (popup.presentationActive)
            ThinkFanService.refresh()
    }

    component ResourceItem: RowLayout {
        id: resourceItem
        required property string icon
        required property string label
        required property string value
        property string minimumValueSample: ""
        // Keep the value cell width stable for changing percentages while
        // allowing compact rows to place the text directly after the label.
        property int valueHorizontalAlignment: Text.AlignRight
        spacing: 4

        MaterialSymbol {
            text: resourceItem.icon
            color: Appearance.colors.colOnSurfaceVariant
            iconSize: Appearance.font.pixelSize.large
        }
        StyledText {
            text: resourceItem.label
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            id: minimumValueText
            visible: false
            text: resourceItem.minimumValueSample
        }
        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: minimumValueText.implicitWidth
            horizontalAlignment: resourceItem.valueHorizontalAlignment
            visible: resourceItem.value !== ""
            color: Appearance.colors.colOnSurfaceVariant
            text: resourceItem.value
        }
    }

    component ResourceHeaderItem: Row {
        id: headerItem
        required property var icon
        required property var label
        spacing: 5

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 0
            font.weight: Font.Medium
            text: headerItem.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: headerItem.label
            font {
                weight: Font.Medium
                pixelSize: Appearance.font.pixelSize.normal
            }
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    ColumnLayout {
        spacing: 12

        Row {
            id: resourcesRow
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Column {
                id: ramColumn
                anchors.top: parent.top
                spacing: 8

                ResourceHeaderItem {
                    icon: "memory"
                    label: "RAM"
                }
                Column {
                    spacing: 4
                    ResourceItem {
                        icon: "clock_loader_60"
                        label: Translation.tr("Used:")
                        value: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB"
                        minimumValueSample: "99.9 GB"
                    }
                    ResourceItem {
                        icon: "empty_dashboard"
                        label: Translation.tr("Total:")
                        value: (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(1) + " GB"
                        minimumValueSample: "99.9 GB"
                    }
                }
            }

            Column {
                id: thermalColumn
                anchors.top: parent.top
                spacing: 8

                ResourceHeaderItem {
                    icon: "thermostat"
                    label: Translation.tr("Thermal")
                }
                Column {
                    spacing: 4
                    ResourceItem {
                        icon: "memory"
                        label: "CPU:"
                        value: ResourceUsage.cpuTemp + "°C"
                        minimumValueSample: "99°C"
                    }
                    ResourceItem {
                        icon: "memory_alt"
                        label: "GPU:"
                        value: ResourceUsage.gpuTemp + "°C"
                        minimumValueSample: "99°C"
                    }
                }
            }

            Column {
                id: cpuColumn
                anchors.top: parent.top
                spacing: 8

                ResourceHeaderItem {
                    icon: "planner_review"
                    label: Translation.tr("Load")
                }
                Column {
                    spacing: 4
                    ResourceItem {
                        icon: "bolt"
                        label: Translation.tr("CPU:")
                        value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                        // Keep the existing reserved "99%" cell so popup
                        // geometry never changes, but align the live value to
                        // the cell's leading edge to remove the visual gap.
                        minimumValueSample: "99%"
                        valueHorizontalAlignment: Text.AlignLeft
                    }
                    ResourceItem {
                        icon: "memory_alt"
                        label: Translation.tr("GPU:")
                        value: `${Math.round(ResourceUsage.gpuUsage * 100)}%`
                        minimumValueSample: "99%"
                        valueHorizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
            opacity: 0.65
        }

        Row {
            id: fanMetricsRow
            Layout.alignment: Qt.AlignHCenter
            spacing: resourcesRow.spacing

            Item {
                width: ramColumn.width
                height: fanControlRow.implicitHeight

                RowLayout {
                    id: fanControlRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    MaterialSymbol {
                        text: "mode_fan"
                        fill: popup.thinkFanManaged ? 1 : 0
                        iconSize: Appearance.font.pixelSize.large
                        color: popup.thinkFanManaged
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurfaceVariant
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: Translation.tr("Fan")
                        font.weight: Font.Medium
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        verticalAlignment: Text.AlignVCenter
                    }

                    StyledSwitch {
                        id: thinkFanProfileSwitch
                        checked: popup.thinkFanManaged
                        enabled: popup.thinkFanCanApply
                        activeFocusOnTab: true
                        Accessible.name: Translation.tr("Use ThinkFan managed fan control")

                        onToggled: {
                            const requestedManaged = checked
                            ThinkFanService.applyProfile(
                                requestedManaged ? "managed" : "firmware")
                            checked = Qt.binding(() => popup.thinkFanManaged)
                        }
                    }
                }
            }

            Item {
                width: thermalColumn.width
                height: speedRow.implicitHeight

                RowLayout {
                    id: speedRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    MaterialSymbol {
                        text: "speed"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: Translation.tr("RPM:")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        text: ThinkFanService.fanRpm >= 0
                            ? String(ThinkFanService.fanRpm)
                            : "—"
                        font.weight: Font.Medium
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            Item {
                width: cpuColumn.width
                height: levelRow.implicitHeight

                RowLayout {
                    id: levelRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    MaterialSymbol {
                        text: "tune"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: Translation.tr("Level:")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        text: ThinkFanService.fanLevel.length > 0
                            ? ThinkFanService.fanLevel : "—"
                        font.weight: Font.Medium
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }

        NoticeBox {
            visible: popup.thinkFanApplyErrorMessage.length > 0
            Layout.fillWidth: true
            materialIcon: "warning"
            text: popup.thinkFanApplyErrorMessage
        }
    }
}
