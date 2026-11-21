pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

StyledPopup {
    id: root

    property bool _subscribedTelemetry: false

    function _syncTelemetryLease(): void {
        const want = root.presentationActive
        if (want && !root._subscribedTelemetry) {
            root._subscribedTelemetry = true
            Battery.liveTelemetryConsumers = Battery.liveTelemetryConsumers + 1
            Battery.refreshTelemetry()
        } else if (!want && root._subscribedTelemetry) {
            root._subscribedTelemetry = false
            Battery.liveTelemetryConsumers = Math.max(0, Battery.liveTelemetryConsumers - 1)
        }
    }

    Component.onCompleted: root._syncTelemetryLease()
    onPresentationActiveChanged: root._syncTelemetryLease()
    Component.onDestruction: {
        if (root._subscribedTelemetry) {
            root._subscribedTelemetry = false
            Battery.liveTelemetryConsumers = Math.max(0, Battery.liveTelemetryConsumers - 1)
        }
    }

    readonly property color colBase: Appearance.colors.colLayer0Base
    readonly property real tonalDir: root.colBase.hslLightness > 0.86 ? -1.0 : 1.0
    readonly property color colTier1: ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.022, 1.04)
    readonly property color colTier2: ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.044, 1.07)
    readonly property color colTier2Hover: ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.066, 1.09)
    readonly property color colTrack: ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.088, 1.06)
    readonly property color colOutline: ColorUtils.applyAlpha(ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.16, 1.08), 0.32)

    readonly property int pctInt: Math.max(0, Math.min(100, Math.round(Battery.percentage * 100)))
    readonly property color accentColor: {
        if (Battery.isCritical && !Battery.isCharging)
            return Appearance.colors.colError
        if (Battery.isLow && !Battery.isCharging)
            return Appearance.colors.colTertiary
        return Appearance.colors.colPrimary
    }
    readonly property color activePillBg: Appearance.colors.colPrimary
    readonly property color activePillFg: ColorUtils.ensureReadable(
        Appearance.colors.colOnPrimary, root.activePillBg, 5.0
    )

    readonly property string batteryGlyph: {
        if (Battery.isCharging) return "battery_charging_full"
        if (Battery.isChargeLimited) return "battery_saver"
        if (root.pctInt >= 95) return "battery_full"
        if (root.pctInt >= 80) return "battery_6_bar"
        if (root.pctInt >= 65) return "battery_5_bar"
        if (root.pctInt >= 50) return "battery_4_bar"
        if (root.pctInt >= 35) return "battery_3_bar"
        if (root.pctInt >= 20) return "battery_2_bar"
        if (root.pctInt >= 10) return "battery_1_bar"
        return "battery_alert"
    }

    function formatDuration(seconds: real): string {
        const s = Math.max(0, Math.round(Number(seconds) || 0))
        if (s < 60) return ""
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h > 0) return `${h}h ${m}m`
        return `${m}m`
    }

    readonly property string etaText: {
        if (!root.presentationActive)
            return "—"
        if (Battery.isCharging) {
            const d = root.formatDuration(Battery.timeToFull)
            return d.length > 0 ? Translation.tr("%1 to full").arg(d) : Translation.tr("Charging")
        }
        if (Battery.onBattery) {
            const d = root.formatDuration(Battery.timeToEmpty)
            return d.length > 0 ? Translation.tr("%1 left").arg(d) : Translation.tr("Estimating")
        }
        if (Battery.isChargeLimited && Battery.effectiveEndThreshold > 0)
            return Translation.tr("Capped at %1%").arg(Battery.effectiveEndThreshold)
        if (Battery.isFullyCharged)
            return Translation.tr("AC connected")
        return Translation.tr("On AC")
    }

    readonly property string powerText: {
        const w = Battery.energyRate
        if (!Number.isFinite(w) || w < 0.05)
            return "0.0 W"
        const sign = Battery.isCharging ? "+" : (Battery.onBattery ? "-" : "")
        return `${sign}${w.toFixed(1)} W`
    }

    readonly property string capacityText: {
        if (Battery.energyNowWh >= 0 && Battery.energyFullWh > 0)
            return `${Battery.energyNowWh.toFixed(1)}/${Battery.energyFullWh.toFixed(1)} Wh`
        return "—"
    }

    readonly property string healthValueText: Battery.healthPercentage >= 0
        ? `${Math.round(Battery.healthPercentage)}%` : "—"

    readonly property string wearSubtext: {
        if (Battery.wearPercentage >= 0 && Battery.energyDesignWh > 0)
            return Translation.tr("%1% wear · %2 Wh").arg(Math.round(Battery.wearPercentage)).arg(Battery.energyDesignWh.toFixed(1))
        if (Battery.wearPercentage >= 0)
            return Translation.tr("%1% wear").arg(Math.round(Battery.wearPercentage))
        return Translation.tr("No wear data")
    }

    readonly property string hardwareSubtext: {
        const parts = []
        if (Battery.batteryTechnology.length > 0) parts.push(Battery.batteryTechnology)
        if (Battery.batteryManufacturer.length > 0) parts.push(Battery.batteryManufacturer)
        return parts.length > 0 ? parts.join(" · ") : Translation.tr("Hardware cell")
    }

    Item {
        id: popupBody
        objectName: "batteryPopupContent"
        implicitWidth: 292
        implicitHeight: columnLayout.implicitHeight

        ColumnLayout {
            id: columnLayout
            anchors.fill: parent
            spacing: 8

        // ─── Hero Charge Card (Layer 1) ───
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: heroCol.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: root.colTier1

            ColumnLayout {
                id: heroCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Icon Badge
                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 11
                        color: ColorUtils.applyAlpha(root.accentColor, 0.16)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: root.batteryGlyph
                            iconSize: 22
                            color: root.accentColor
                        }
                    }

                    // Percentage + Status
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                text: `${root.pctInt}%`
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                                font.features: ({ "tnum": 1 })
                                color: Appearance.colors.colOnLayer0
                            }

                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: statusChipText.implicitWidth + 12
                                radius: 10
                                color: ColorUtils.applyAlpha(root.accentColor, 0.16)

                                StyledText {
                                    id: statusChipText
                                    anchors.centerIn: parent
                                    text: Battery.statusText
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: root.accentColor
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.etaText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }

                // Charge Bar with optional Charge Limit marker
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 10

                    Rectangle {
                        id: chargeTrack
                        anchors.fill: parent
                        radius: 5
                        color: root.colTrack
                        clip: true

                        Rectangle {
                            height: parent.height
                            width: Math.max(height, Math.round(parent.width * Math.max(0, Math.min(1, Battery.percentage))))
                            radius: 5
                            color: root.accentColor

                            Behavior on width {
                                enabled: root.presentationActive && Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    // Charge Limit threshold marker tick (when < 100%)
                    Rectangle {
                        visible: Battery.effectiveEndThreshold > 0 && Battery.effectiveEndThreshold < 100
                        width: 2
                        height: parent.height + 2
                        y: -1
                        x: Math.max(2, Math.min(parent.width - 4, Math.round(parent.width * (Battery.effectiveEndThreshold / 100)) - 1))
                        radius: 1
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.72
                    }
                }
            }
        }

        // ─── 2x2 Hardware Telemetry Grid (Layer 2) ───
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 6

            // Tile 1: Live Power & Voltage
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                implicitHeight: powerTileCol.implicitHeight + 16
                radius: Appearance.rounding.small
                color: root.colTier2

                ColumnLayout {
                    id: powerTileCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        MaterialSymbol {
                            text: "bolt"
                            iconSize: 15
                            color: root.accentColor
                        }
                        StyledText {
                            text: Translation.tr("Power")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.powerText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Battery.voltageNowV > 0
                            ? `${Battery.voltageNowV.toFixed(2)} V`
                            : Translation.tr("Voltage n/a")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: ({ "tnum": 1 })
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            // Tile 2: Energy Capacity (Wh)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                implicitHeight: capTileCol.implicitHeight + 16
                radius: Appearance.rounding.small
                color: root.colTier2

                ColumnLayout {
                    id: capTileCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        MaterialSymbol {
                            text: "battery_horiz_075"
                            iconSize: 15
                            color: Appearance.colors.colSecondary
                        }
                        StyledText {
                            text: Translation.tr("Energy")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.capacityText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Battery.effectiveEndThreshold > 0 && Battery.effectiveEndThreshold < 100
                            ? Translation.tr("Limit %1%").arg(Battery.effectiveEndThreshold)
                            : Translation.tr("Full range")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            // Tile 3: Health & Wear
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                implicitHeight: healthTileCol.implicitHeight + 16
                radius: Appearance.rounding.small
                color: root.colTier2

                ColumnLayout {
                    id: healthTileCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        MaterialSymbol {
                            text: "health_and_safety"
                            iconSize: 15
                            color: (Battery.healthPercentage >= 0 && Battery.healthPercentage < 70)
                                ? Appearance.colors.colError
                                : Appearance.colors.colTertiary
                        }
                        StyledText {
                            text: Translation.tr("Health")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.healthValueText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.wearSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: ({ "tnum": 1 })
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            // Tile 4: Charge Cycles & Cell Info
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                implicitHeight: cycleTileCol.implicitHeight + 16
                radius: Appearance.rounding.small
                color: root.colTier2

                ColumnLayout {
                    id: cycleTileCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        MaterialSymbol {
                            text: "sync"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Cycles")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Battery.chargeCycles >= 0 ? String(Battery.chargeCycles) : "—"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.hardwareSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ─── Power Profile Switcher (Layer 1) ───
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: Appearance.rounding.small
            color: root.colTier1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Repeater {
                    model: PowerProfiles.hasPerformanceProfile
                        ? [
                            { profile: PowerProfile.PowerSaver, icon: "energy_savings_leaf", label: Translation.tr("Saver") },
                            { profile: PowerProfile.Balanced, icon: "balance", label: Translation.tr("Balanced") },
                            { profile: PowerProfile.Performance, icon: "speed", label: Translation.tr("Perf") }
                        ]
                        : [
                            { profile: PowerProfile.PowerSaver, icon: "energy_savings_leaf", label: Translation.tr("Saver") },
                            { profile: PowerProfile.Balanced, icon: "balance", label: Translation.tr("Balanced") }
                        ]

                    delegate: Rectangle {
                        id: profilePill
                        required property var modelData
                        readonly property bool active: PowerProfiles.profile === modelData.profile
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Math.max(4, Appearance.rounding.small - 3)
                        color: active
                            ? root.activePillBg
                            : (pillMouse.containsMouse ? root.colTier2Hover : "transparent")

                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: 120 }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: profilePill.modelData.icon
                                iconSize: 14
                                color: profilePill.active ? root.activePillFg : Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: profilePill.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: profilePill.active ? Font.DemiBold : Font.Medium
                                color: profilePill.active ? root.activePillFg : Appearance.colors.colOnLayer1
                            }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PowerProfiles.profile = profilePill.modelData.profile
                        }
                    }
                }
            }
        }
        }
    }
}
