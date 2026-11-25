pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    property bool _subscribedTelemetry: false
    property bool _draggingLimit: false
    property int _dragLimit: 80
    property int _hoveredPreset: -1
    property int _pendingLimit: -1

    function _syncTelemetryLease(): void {
        const want = root.presentationActive
        if (want && !root._subscribedTelemetry) {
            root._subscribedTelemetry = true
            Battery.liveTelemetryConsumers = Battery.liveTelemetryConsumers + 1
            Battery.refreshTelemetry()
            if (Battery.chargeLimitAvailable && !Battery.chargeLimitBusy)
                TlpService.refresh()
        } else if (!want && root._subscribedTelemetry) {
            root._subscribedTelemetry = false
            Battery.liveTelemetryConsumers = Math.max(0, Battery.liveTelemetryConsumers - 1)
        }
    }

    Component.onCompleted: root._syncTelemetryLease()
    onPresentationActiveChanged: {
        root._syncTelemetryLease()
        if (!root.presentationActive) {
            root._draggingLimit = false
            root._interactionHold = false
            root._hoveredPreset = -1
        }
    }
    Component.onDestruction: {
        root._draggingLimit = false
        root._interactionHold = false
        if (root._subscribedTelemetry) {
            root._subscribedTelemetry = false
            Battery.liveTelemetryConsumers = Math.max(0, Battery.liveTelemetryConsumers - 1)
        }
    }

    readonly property bool chargeLimitEditable: Battery.chargeLimitInteractive
    readonly property var chargeLimitPresets: Battery.chargeLimitPresets()
    readonly property int settledChargeLimit: {
        if (Battery.effectiveEndThreshold > 0 && Battery.effectiveEndThreshold < 100)
            return Battery.effectiveEndThreshold
        if (Battery.chargeLimitActive && Battery.currentChargeLimit > 0 && Battery.currentChargeLimit < 100)
            return Battery.currentChargeLimit
        if (Battery.chargeLimitEnabled && Battery.effectiveChargeLimitThreshold > 0 && Battery.effectiveChargeLimitThreshold < 100)
            return Battery.effectiveChargeLimitThreshold
        return 100
    }
    readonly property int displayedChargeLimit: root._draggingLimit
        ? root._dragLimit
        : ((Battery.chargeLimitBusy && root._pendingLimit > 0) ? root._pendingLimit : root.settledChargeLimit)
    readonly property bool hasActiveChargeLimit: root.displayedChargeLimit > 0 && root.displayedChargeLimit < 100

    function percentToX(pct: real, trackWidth: real): real {
        const w = Math.max(0, Number(trackWidth) || 0)
        const inset = Math.min(7, w * 0.5)
        const ratio = Math.max(0, Math.min(100, Number(pct) || 0)) / 100
        return Math.max(inset, Math.min(Math.max(inset, w - inset), w * ratio))
    }

    function xToChargeLimit(xPos: real, trackWidth: real, snapThresholdPx: real): int {
        const w = Math.max(1, Number(trackWidth) || 1)
        const presets = root.chargeLimitPresets ?? []
        let bestPreset = -1
        let bestDist = Number(snapThresholdPx) || 0
        for (let i = 0; i < presets.length; ++i) {
            const p = Number(presets[i])
            const d = Math.abs(Number(xPos) - root.percentToX(p, w))
            if (d <= bestDist) {
                bestDist = d
                bestPreset = p
            }
        }
        if (bestPreset > 0)
            return bestPreset
        const rawPct = Math.max(0, Math.min(100, (Number(xPos) / w) * 100))
        return Battery.normalizeChargeLimit(rawPct)
    }

    readonly property string chargeLimitLabelText: {
        if (root._draggingLimit) {
            return root._dragLimit >= 100
                ? Translation.tr("Off (100%)")
                : `${root._dragLimit}%`
        }
        if (Battery.chargeLimitBusy) {
            return root._pendingLimit >= 100
                ? Translation.tr("Resetting…")
                : (root._pendingLimit > 0
                    ? Translation.tr("Applying %1%…").arg(root._pendingLimit)
                    : Translation.tr("Applying…"))
        }
        if (root._hoveredPreset > 0) {
            return root._hoveredPreset >= 100
                ? Translation.tr("Full (100%)")
                : Translation.tr("Set %1%").arg(root._hoveredPreset)
        }
        if (root.hasActiveChargeLimit)
            return `${root.displayedChargeLimit}%`
        return Translation.tr("Off · 100%")
    }

    readonly property color colBase: Appearance.colors.colLayer0Base
    readonly property real tonalDir: root.colBase.hslLightness > 0.86 ? -1.0 : 1.0
    readonly property color colTier1: ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.022, 1.04)
    readonly property color colTier2: ColorUtils.tonalStep(root.colBase, root.tonalDir * 0.044, 1.07)
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
        implicitWidth: 304
        implicitHeight: columnLayout.implicitHeight

        Connections {
            target: Battery
            function onChargeLimitBusyChanged(): void {
                if (!Battery.chargeLimitBusy)
                    root._pendingLimit = -1
            }
        }

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

                // Charge Bar with integrated Charge Limit preset dots + draggable vertical line
                Item {
                    id: chargeBarArea
                    objectName: "batteryChargeBar"
                    Layout.fillWidth: true
                    implicitHeight: root.chargeLimitEditable ? 22 : 12

                    Rectangle {
                        id: chargeTrack
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: root.chargeLimitEditable ? 14 : 10
                        radius: height / 2
                        color: root.colTrack
                        clip: true

                        Rectangle {
                            id: chargeFill
                            height: parent.height
                            width: Math.max(height, Math.round(parent.width * Math.max(0, Math.min(1, Battery.percentage))))
                            radius: height / 2
                            color: root.accentColor

                            Behavior on width {
                                enabled: root.presentationActive && Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Protected reserve zone above the active charge limit
                        Rectangle {
                            visible: root.hasActiveChargeLimit
                            x: Math.round(root.percentToX(root.displayedChargeLimit, chargeTrack.width))
                            width: Math.max(0, chargeTrack.width - x)
                            height: chargeTrack.height
                            color: ColorUtils.applyAlpha(root.colBase, 0.34)
                        }
                    }

                    // Preset dots inside the battery bar
                    Repeater {
                        id: presetDotsRepeater
                        model: root.chargeLimitEditable ? root.chargeLimitPresets : []

                        delegate: Rectangle {
                            required property int modelData
                            readonly property real dotX: root.percentToX(modelData, chargeTrack.width)
                            readonly property bool isHovered: root._hoveredPreset === modelData
                            readonly property bool isSelected: root.displayedChargeLimit === modelData
                            readonly property bool overFill: dotX <= chargeFill.width

                            width: (isHovered || isSelected) ? 7 : 5
                            height: width
                            radius: width / 2
                            x: Math.round(dotX - width / 2)
                            y: Math.round((chargeBarArea.height - height) / 2)
                            color: overFill
                                ? ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, (isHovered || isSelected) ? 0.96 : 0.56)
                                : ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, (isHovered || isSelected) ? 0.92 : 0.42)

                            Behavior on width {
                                enabled: root.presentationActive && Appearance.animationsEnabled
                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                            }
                            Behavior on height {
                                enabled: root.presentationActive && Appearance.animationsEnabled
                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    // Integrated vertical Charge Limit indicator / drag handle line
                    Item {
                        id: chargeLimitLine
                        objectName: "batteryChargeLimitLine"
                        visible: root.chargeLimitEditable || root.hasActiveChargeLimit
                        width: 6
                        height: chargeBarArea.height
                        x: Math.round(root.percentToX(root.displayedChargeLimit, chargeTrack.width) - width / 2)

                        Behavior on x {
                            enabled: !root._draggingLimit && root.presentationActive && Appearance.animationsEnabled
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 4
                            height: parent.height
                            radius: 2
                            color: ColorUtils.applyAlpha(root.colTier1, 0.78)
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: (root._draggingLimit || limitMouse.containsMouse) ? 3 : 2
                            height: Math.max(4, parent.height - 2)
                            radius: 1.5
                            color: Appearance.colors.colOnLayer0
                            opacity: Battery.chargeLimitBusy ? 0.55 : 0.95
                        }
                    }

                    MouseArea {
                        id: limitMouse
                        objectName: "batteryChargeLimitMouse"
                        anchors.fill: parent
                        anchors.topMargin: -4
                        anchors.bottomMargin: -4
                        enabled: root.chargeLimitEditable && !Battery.chargeLimitBusy
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                        onPressed: mouse => {
                            root._interactionHold = true
                            root._draggingLimit = true
                            root._dragLimit = root.xToChargeLimit(mouse.x, chargeTrack.width, 10)
                        }
                        onPositionChanged: mouse => {
                            if (pressed) {
                                root._dragLimit = root.xToChargeLimit(mouse.x, chargeTrack.width, 7)
                                return
                            }
                            const presets = root.chargeLimitPresets ?? []
                            let hovered = -1
                            let bestDist = 10
                            for (let i = 0; i < presets.length; ++i) {
                                const p = Number(presets[i])
                                const d = Math.abs(mouse.x - root.percentToX(p, chargeTrack.width))
                                if (d <= bestDist) {
                                    bestDist = d
                                    hovered = p
                                }
                            }
                            root._hoveredPreset = hovered
                        }
                        onReleased: mouse => {
                            const target = root.xToChargeLimit(mouse.x, chargeTrack.width, 10)
                            root._draggingLimit = false
                            root._interactionHold = false
                            root._pendingLimit = target
                            Battery.setChargeLimitFromPopup(target)
                        }
                        onCanceled: {
                            root._draggingLimit = false
                            root._interactionHold = false
                            root._hoveredPreset = -1
                        }
                        onExited: root._hoveredPreset = -1
                    }
                }

                // Slim Charge Limit summary row (presets live inside the bar above)
                RowLayout {
                    visible: root.chargeLimitEditable || root.hasActiveChargeLimit
                    Layout.fillWidth: true
                    spacing: 5

                    MaterialSymbol {
                        text: "battery_saver"
                        iconSize: 13
                        color: (root.hasActiveChargeLimit || root._draggingLimit || Battery.chargeLimitBusy)
                            ? root.accentColor
                            : Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: Translation.tr("Charge limit")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        objectName: "batteryChargeLimitLabel"
                        text: root.chargeLimitLabelText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: (root.hasActiveChargeLimit || root._draggingLimit || root._hoveredPreset > 0)
                            ? Font.DemiBold : Font.Normal
                        font.features: ({ "tnum": 1 })
                        color: (root.hasActiveChargeLimit || root._draggingLimit || root._hoveredPreset > 0)
                            ? root.accentColor
                            : Appearance.colors.colSubtext
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

        // ─── Battery Health History Card (Layer 1) ───
        Rectangle {
            id: historyCard
            objectName: "batteryHistoryCard"
            Layout.fillWidth: true
            visible: Battery.available && (Battery.healthHistory.length > 0 || Battery.healthPercentage >= 0)
            implicitHeight: historyCol.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: root.colTier1

            ColumnLayout {
                id: historyCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("History")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: ColorUtils.ensureReadable(root.accentColor, root.colTier1, 4.5)
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        visible: historySparkline.hoveredIndex >= 0 && historySparkline.hoveredIndex < historySparkline._plottedPoints.length
                        text: {
                            const idx = historySparkline.hoveredIndex
                            const pts = historySparkline._plottedPoints
                            if (idx < 0 || idx >= pts.length)
                                return ""
                            return Qt.formatDate(new Date(Number(pts[idx].t) * 1000), "MMM d")
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledText {
                    id: historySummaryText
                    objectName: "batteryHistorySummaryText"
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({ "tnum": 1 })
                    color: ColorUtils.ensureReadable(Appearance.colors.colTertiary, root.colTier1, 4.5)
                    elide: Text.ElideRight
                    text: {
                        const idx = historySparkline.hoveredIndex
                        const pts = historySparkline._plottedPoints
                        if (idx >= 0 && idx < pts.length) {
                            const pt = pts[idx]
                            const cyc = Number(pt.c ?? -1)
                            return cyc >= 0
                                ? Translation.tr("%1% health · %2 cycles").arg(Number(pt.h).toFixed(1)).arg(cyc)
                                : Translation.tr("%1% health").arg(Number(pt.h).toFixed(1))
                        }
                        return String(Battery.healthHistorySummary?.summaryText ?? "")
                    }
                }

                Canvas {
                    id: historySparkline
                    objectName: "batteryHistorySparkline"
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 42
                    antialiasing: true

                    property int hoveredIndex: -1
                    property var _plottedPoints: []

                    function _repaintIfVisible(): void {
                        if (root.presentationActive && width > 0 && height > 0)
                            requestPaint()
                    }

                    Component.onCompleted: _repaintIfVisible()
                    onWidthChanged: _repaintIfVisible()
                    onHeightChanged: _repaintIfVisible()
                    onHoveredIndexChanged: _repaintIfVisible()

                    Connections {
                        target: root
                        function onAccentColorChanged(): void { historySparkline._repaintIfVisible() }
                        function onPresentationActiveChanged(): void {
                            if (!root.presentationActive)
                                historySparkline.hoveredIndex = -1
                            else
                                historySparkline._repaintIfVisible()
                        }
                    }

                    Connections {
                        target: Battery
                        function onHealthHistoryChanged(): void {
                            if (historySparkline.hoveredIndex >= 0)
                                historySparkline.hoveredIndex = -1
                            historySparkline._repaintIfVisible()
                        }
                        function on_HistoryRevisionChanged(): void {
                            historySparkline._repaintIfVisible()
                        }
                        function onHealthPercentageChanged(): void {
                            if ((Battery.healthHistory?.length ?? 0) === 0)
                                historySparkline._repaintIfVisible()
                        }
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        if (!ctx || width <= 0 || height <= 0)
                            return
                        ctx.clearRect(0, 0, width, height)

                        let src = Array.isArray(Battery.healthHistory) ? Battery.healthHistory : []
                        if (src.length === 0 && Battery.healthPercentage >= 0) {
                            src = [{
                                t: Math.floor(Date.now() / 1000),
                                h: Math.round(Battery.healthPercentage * 100) / 100,
                                c: Battery.chargeCycles >= 0 ? Battery.chargeCycles : -1
                            }]
                        }
                        if (src.length === 0) {
                            historySparkline._plottedPoints = []
                            return
                        }

                        const maxPts = 160
                        const sampled = []
                        if (src.length <= maxPts) {
                            for (let i = 0; i < src.length; ++i)
                                sampled.push(src[i])
                        } else {
                            for (let i = 0; i < maxPts; ++i) {
                                const idx = i === maxPts - 1
                                    ? (src.length - 1)
                                    : Math.floor((i * (src.length - 1)) / Math.max(1, maxPts - 1))
                                sampled.push(src[idx])
                            }
                        }

                        const strokeColor = ColorUtils.ensureReadable(root.accentColor, root.colTier1, 3.5).toString()
                        const mutedColor = ColorUtils.applyAlpha(root.accentColor, 0.35).toString()
                        const ringColor = root.colTier1.toString()
                        const padX = 3
                        const padY = 5
                        const drawW = Math.max(1, width - padX * 2)
                        const drawH = Math.max(1, height - padY * 2)

                        if (sampled.length === 1) {
                            const midY = height * 0.5
                            const dotX = width - padX - 2
                            historySparkline._plottedPoints = [{
                                x: dotX,
                                y: midY,
                                t: sampled[0].t,
                                h: sampled[0].h,
                                c: sampled[0].c
                            }]
                            ctx.strokeStyle = mutedColor
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(padX, midY)
                            ctx.lineTo(dotX, midY)
                            ctx.stroke()

                            ctx.fillStyle = strokeColor
                            ctx.beginPath()
                            ctx.arc(dotX, midY, 3, 0, Math.PI * 2)
                            ctx.fill()
                            return
                        }

                        let minH = Number(sampled[0].h)
                        let maxH = minH
                        let tMin = Number(sampled[0].t)
                        let tMax = Number(sampled[sampled.length - 1].t)
                        for (let i = 1; i < sampled.length; ++i) {
                            const hVal = Number(sampled[i].h)
                            if (hVal < minH) minH = hVal
                            if (hVal > maxH) maxH = hVal
                        }

                        let loH
                        let hiH
                        const rawSpan = maxH - minH
                        if (rawSpan < 2.0) {
                            const midH = (minH + maxH) * 0.5
                            loH = Math.max(0, midH - 1.0)
                            hiH = Math.min(100, loH + 2.0)
                            if (hiH - loH < 2.0)
                                loH = Math.max(0, hiH - 2.0)
                        } else {
                            const padH = rawSpan * 0.14
                            loH = Math.max(0, minH - padH)
                            hiH = Math.min(100, maxH + padH)
                        }
                        const hSpan = Math.max(0.01, hiH - loH)
                        const tSpan = tMax - tMin

                        const plotted = []
                        for (let i = 0; i < sampled.length; ++i) {
                            const pt = sampled[i]
                            const tx = tSpan > 0
                                ? ((Number(pt.t) - tMin) / tSpan)
                                : (i / Math.max(1, sampled.length - 1))
                            const px = padX + drawW * Math.max(0, Math.min(1, tx))
                            const normY = (Number(pt.h) - loH) / hSpan
                            const py = padY + drawH * (1 - Math.max(0, Math.min(1, normY)))
                            plotted.push({
                                x: px,
                                y: py,
                                t: pt.t,
                                h: pt.h,
                                c: pt.c
                            })
                        }
                        historySparkline._plottedPoints = plotted

                        ctx.strokeStyle = strokeColor
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(plotted[0].x, plotted[0].y)
                        for (let i = 1; i < plotted.length; ++i)
                            ctx.lineTo(plotted[i].x, plotted[i].y)
                        ctx.stroke()

                        const hIdx = historySparkline.hoveredIndex
                        if (hIdx >= 0 && hIdx < plotted.length) {
                            const hp = plotted[hIdx]
                            ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.22).toString()
                            ctx.lineWidth = 1.0
                            ctx.beginPath()
                            ctx.moveTo(hp.x, padY * 0.5)
                            ctx.lineTo(hp.x, height - padY * 0.5)
                            ctx.stroke()

                            ctx.fillStyle = ringColor
                            ctx.beginPath()
                            ctx.arc(hp.x, hp.y, 4.5, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.fillStyle = strokeColor
                            ctx.beginPath()
                            ctx.arc(hp.x, hp.y, 2.8, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.presentationActive && historySparkline._plottedPoints.length > 0
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton

                        onPositionChanged: mouse => {
                            const pts = historySparkline._plottedPoints
                            if (!pts || pts.length === 0)
                                return
                            let bestIdx = 0
                            let bestDist = Math.abs(mouse.x - pts[0].x)
                            for (let i = 1; i < pts.length; ++i) {
                                const d = Math.abs(mouse.x - pts[i].x)
                                if (d < bestDist) {
                                    bestDist = d
                                    bestIdx = i
                                }
                            }
                            if (historySparkline.hoveredIndex !== bestIdx)
                                historySparkline.hoveredIndex = bestIdx
                        }
                        onExited: historySparkline.hoveredIndex = -1
                    }
                }
            }
        }
        }
    }
}
