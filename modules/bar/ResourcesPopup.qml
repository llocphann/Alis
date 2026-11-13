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

    property int userSelectedLevel: -1
    readonly property bool followPowerProfileActive:
        ThinkFanService.profileFanControlEnabled
        || (Config.options?.powerProfiles?.fanControl?.enabled === true)

    readonly property int hardwareManualLevel: {
        const lvl = String(ThinkFanService.fanLevel ?? "").trim().toLowerCase()
        if (lvl === "" || lvl === "auto") return 0
        if (lvl === "full-speed" || lvl === "disengaged") return 7
        const num = Number(lvl)
        return isFinite(num) ? Math.max(0, Math.min(7, Math.round(num))) : 0
    }

    readonly property int effectiveManualLevel:
        popup.userSelectedLevel >= 0 ? popup.userSelectedLevel : popup.hardwareManualLevel

    function selectManualFanLevel(level: int): void {
        const clamped = Math.max(0, Math.min(7, Math.round(level)))
        popup.userSelectedLevel = clamped
        const target = clamped === 0 ? "auto" : String(clamped)
        if (popup.thinkFanManaged && popup.thinkFanCanApply) {
            ThinkFanService.applyProfile("firmware")
        }
        if (ThinkFanService.directControlAvailable && !popup.thinkFanManaged) {
            ThinkFanService.applyFanLevel(target)
        }
    }

    property Timer fanRefreshTimer: Timer {
        interval: 2000
        repeat: true
        running: popup.presentationActive
        onTriggered: ThinkFanService.refresh()
    }

    property Connections fanLevelConn: Connections {
        target: ThinkFanService
        function onFanLevelChanged() {
            popup.userSelectedLevel = -1
        }
    }

    onPresentationActiveChanged: {
        if (popup.presentationActive) {
            ThinkFanService.refresh()
        }
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
            text: popup.presentationActive ? resourceItem.value : (resourceItem.minimumValueSample || resourceItem.value)
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

        ColumnLayout {
            id: fanCompactSection
            objectName: "fanCompactSection"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: resourcesRow.implicitWidth
            spacing: 8

            // Hidden geometry references preserving column-width layout contract
            Item {
                visible: false
                width: thermalColumn.width
                height: 0
                Item { width: cpuColumn.width; height: 0 }
            }

            // 1. Header: Fan icon + Fan | RPM readout
            Item {
                Layout.fillWidth: true
                implicitHeight: 22
                height: 22

                RowLayout {
                    anchors.fill: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "mode_fan"
                        fill: (ThinkFanService.fanRpm > 0 || popup.thinkFanManaged) ? 1 : 0
                        iconSize: Appearance.font.pixelSize.large
                        color: (ThinkFanService.fanRpm > 0 || popup.thinkFanManaged)
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurfaceVariant
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: Translation.tr("Fan")
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    MaterialSymbol {
                        text: "speed"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.75
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: Translation.tr("RPM:")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.75
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.preferredWidth: rpmSampleText.implicitWidth
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignVCenter

                        StyledText {
                            id: rpmSampleText
                            visible: false
                            text: "9999"
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }

                        StyledText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: (popup.presentationActive && ThinkFanService.fanRpm >= 0)
                                ? String(ThinkFanService.fanRpm)
                                : "—"
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            // 2. Manual Fan Controls (Hidden when Follow power profile is active)
            Item {
                id: manualFanControlsCol
                objectName: "manualFanControlsCol"
                visible: !popup.followPowerProfileActive
                Layout.fillWidth: true
                implicitHeight: !popup.followPowerProfileActive ? 50 : 0
                Layout.preferredHeight: !popup.followPowerProfileActive ? 50 : 0
                Layout.maximumHeight: !popup.followPowerProfileActive ? 50 : 0
                clip: true

                // Thinking-Effort-Style Fan Level Slider (Auto, 1..7)
                Item {
                    x: 0
                    y: 0
                    width: parent.width
                    height: 16

                    RowLayout {
                        anchors.fill: parent
                        spacing: 4

                        MaterialSymbol {
                            text: "tune"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: Translation.tr("Level:")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: popup.effectiveManualLevel === 0
                                ? Translation.tr("Auto")
                                : `L${popup.effectiveManualLevel}`
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                Item {
                    id: fanEffortSlider
                    objectName: "fanEffortSlider"
                    x: 0
                    y: 18
                    width: parent.width
                    height: 32

                    readonly property var levelModel: [
                        { value: 0, label: "Auto" },
                        { value: 1, label: "1" },
                        { value: 2, label: "2" },
                        { value: 3, label: "3" },
                        { value: 4, label: "4" },
                        { value: 5, label: "5" },
                        { value: 6, label: "6" },
                        { value: 7, label: "7" }
                    ]
                    readonly property int stepCount: 8
                    readonly property real stepSlotWidth: Math.max(16, width / stepCount)
                    readonly property int activeStepIndex: popup.effectiveManualLevel
                    property real animatedStepIndex: activeStepIndex

                    Behavior on animatedStepIndex {
                        enabled: popup.presentationActive
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    function applyLevelAtX(localX: real): void {
                        if (width <= 0) return
                        const pad = stepSlotWidth * 0.5
                        const trackW = Math.max(1, width - stepSlotWidth)
                        const ratio = Math.max(0, Math.min(1, (localX - pad) / trackW))
                        const idx = Math.max(0, Math.min(stepCount - 1, Math.round(ratio * (stepCount - 1))))
                        popup.selectManualFanLevel(idx)
                    }

                    Rectangle {
                        id: fanEffortTrackBg
                        x: Math.round(fanEffortSlider.stepSlotWidth * 0.5)
                        y: 9
                        width: Math.max(0, fanEffortSlider.width - fanEffortSlider.stepSlotWidth)
                        height: 4
                        radius: 2
                        color: Qt.alpha(Appearance.colors.colOnSurfaceVariant, 0.16)
                    }

                    Rectangle {
                        id: fanEffortTrackFill
                        x: fanEffortTrackBg.x
                        y: fanEffortTrackBg.y
                        width: Math.round(fanEffortTrackBg.width * (fanEffortSlider.animatedStepIndex / (fanEffortSlider.stepCount - 1)))
                        height: 4
                        radius: 2
                        color: Appearance.colors.colPrimary
                    }

                    Rectangle {
                        id: fanEffortThumb
                        objectName: "fanEffortThumb"
                        z: 5
                        width: 12
                        height: 12
                        radius: 6
                        x: Math.round((fanEffortSlider.animatedStepIndex + 0.5) * fanEffortSlider.stepSlotWidth - width / 2)
                        y: 5
                        color: Appearance.colors.colPrimary
                        border.width: 2
                        border.color: Appearance.colors.colOnPrimary
                    }

                    Repeater {
                        id: fanEffortRepeater
                        model: fanEffortSlider.levelModel

                        delegate: RippleButton {
                            id: fanEffortStep
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: index === fanEffortSlider.activeStepIndex
                            x: Math.round(index * fanEffortSlider.stepSlotWidth)
                            y: 0
                            width: Math.max(16, Math.round(fanEffortSlider.stepSlotWidth))
                            height: 32
                            implicitWidth: 24
                            implicitHeight: 32
                            buttonRadius: 7
                            colBackground: "transparent"
                            colBackgroundHover: Qt.alpha(Appearance.colors.colPrimary, 0.10)
                            moveAction: event => {
                                if (fanEffortStep.down) {
                                    fanEffortStep.suppressClickOnRelease = true
                                    fanEffortSlider.applyLevelAtX(fanEffortStep.x + event.x)
                                }
                            }
                            onClicked: popup.selectManualFanLevel(modelData.value)

                            contentItem: Item {
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 7
                                    width: 8
                                    height: 8
                                    radius: 4
                                    visible: !fanEffortStep.isSelected
                                    color: fanEffortStep.index <= fanEffortSlider.activeStepIndex
                                        ? Qt.alpha(Appearance.colors.colPrimary, 0.68)
                                        : Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Qt.alpha(Appearance.colors.colOnSurfaceVariant, 0.28)
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 18
                                    height: 12
                                    text: fanEffortStep.modelData.label
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.smallest - 2
                                    font.weight: fanEffortStep.isSelected ? Font.DemiBold : Font.Normal
                                    color: fanEffortStep.isSelected
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }

            // 4. Follow power profile row (aligned left-to-right, no Auto toggle)
            Item {
                Layout.fillWidth: true
                implicitHeight: 24
                height: 24

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Follow power profile")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    StyledSwitch {
                        id: followProfileSwitch
                        checked: popup.followPowerProfileActive
                        enabled: Config.ready
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        onToggled: {
                            const nextEnabled = checked
                            Config.setNestedValue("powerProfiles.fanControl.enabled", nextEnabled)
                            ThinkFanService.setProfileFanControlEnabled(nextEnabled)
                            if (!nextEnabled && popup.thinkFanManaged && popup.thinkFanCanApply) {
                                ThinkFanService.applyProfile("firmware")
                            }
                            checked = Qt.binding(() => popup.followPowerProfileActive)
                        }
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
