pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    objectName: "barCavaEqualizerModule"

    property bool vertical: false
    property real contentRotation: 0
    readonly property bool contentAvailable: true

    readonly property int configuredWidth: Math.max(48, Math.min(360, Number(Config.options?.bar?.cava?.width ?? 120)))
    readonly property int configuredHeight: Math.max(10, Math.min(30, Number(Config.options?.bar?.cava?.height ?? 22)))
    readonly property int barSpacing: Math.max(1, Math.min(6, Number(Config.options?.bar?.cava?.barSpacing ?? 2)))
    readonly property int barRadius: Math.max(0, Math.min(6, Number(Config.options?.bar?.cava?.barRadius ?? 2)))
    readonly property bool mirrorBars: Config.options?.bar?.cava?.mirror ?? true
    readonly property int configuredBarCount: Math.max(0, Math.min(200, Number(Config.options?.appearance?.cava?.bars ?? 0)))

    readonly property real hostSpan: {
        const liveSpan = root.vertical ? root.height : root.width
        return liveSpan > 1 ? liveSpan : root.configuredWidth
    }
    readonly property real hostCross: {
        const liveCross = root.vertical ? root.width : root.height
        return liveCross > 1 ? liveCross : Number(Appearance.sizes.barHeight)
    }
    readonly property real innerSpan: Math.max(24, root.hostSpan - 12)
    readonly property real minBarWidth: 1.2
    readonly property real minBarGap: 0.8
    readonly property int maxFittingBars: Math.max(4, Math.floor((root.innerSpan + root.minBarGap) / (root.minBarWidth + root.minBarGap)))

    readonly property int effectiveBarCount: {
        if (root.configuredBarCount > 0) {
            return Math.max(4, Math.min(root.maxFittingBars, root.configuredBarCount))
        }
        const autoCount = Math.floor((root.innerSpan + root.barSpacing) / (3 + root.barSpacing))
        return Math.max(8, Math.min(root.maxFittingBars, Math.min(48, autoCount)))
    }

    readonly property real effectiveGap: {
        if (root.effectiveBarCount <= 1) return 0
        const maxAllowedGap = (root.innerSpan - root.effectiveBarCount * root.minBarWidth) / (root.effectiveBarCount - 1)
        return Math.max(root.minBarGap, Math.min(root.barSpacing, maxAllowedGap))
    }

    readonly property real barWidth: {
        if (root.effectiveBarCount <= 0) return root.minBarWidth
        return Math.max(1.0, (root.innerSpan - (root.effectiveBarCount - 1) * root.effectiveGap) / root.effectiveBarCount)
    }

    readonly property real barPitch: root.effectiveBarCount > 1
        ? (root.innerSpan - root.barWidth) / (root.effectiveBarCount - 1)
        : 0

    clip: true
    implicitWidth: root.vertical ? Number(Appearance.sizes.barHeight) : root.configuredWidth
    implicitHeight: root.vertical ? root.configuredWidth : Number(Appearance.sizes.barHeight)

    CavaProcess {
        id: cavaProcess
        active: root.visible
        sampleCount: Math.max(16, root.effectiveBarCount)
    }

    readonly property var paletteColors: {
        const pal = CavaTheme.visualizerColors
        if (pal && pal.length > 0) return pal
        return [
            Appearance.colors.colPrimary,
            Appearance.colors.colSecondary,
            Appearance.colors.colTertiary
        ]
    }

    function barColorForIndex(idx: int, count: int, normVal: real): color {
        const pal = root.paletteColors
        if (!pal || pal.length === 0) return Appearance.colors.colPrimary
        if (pal.length === 1) return pal[0]
        const pos = count > 1 ? (idx / (count - 1)) : 0
        const mix = Math.min(1, Math.max(0, pos * 0.65 + normVal * 0.35))
        const palIdx = Math.min(pal.length - 1, Math.max(0, Math.floor(mix * pal.length)))
        return pal[palIdx]
    }

    Item {
        id: barsContainer
        anchors.centerIn: parent
        width: root.innerSpan
        height: Math.min(root.configuredHeight, Math.max(10, root.hostCross - 6))
        rotation: root.vertical ? 90 : 0
        clip: true

        Repeater {
            model: root.visible ? root.effectiveBarCount : 0

            Item {
                id: barSlot
                required property int index
                readonly property real slotWidth: root.barWidth
                x: root.effectiveBarCount > 1
                    ? (index * root.barPitch)
                    : (barsContainer.width - slotWidth) / 2
                y: 0
                width: slotWidth
                height: barsContainer.height

                readonly property real rawPoint: {
                    const pts = cavaProcess.points
                    const len = pts ? pts.length : 0
                    if (!root.visible || len <= 0) return 0
                    const start = Math.floor(index * len / Math.max(1, root.effectiveBarCount))
                    const end = Math.min(len, Math.max(start + 1, Math.ceil((index + 1) * len / Math.max(1, root.effectiveBarCount))))
                    let sum = 0
                    let cnt = 0
                    for (let i = start; i < end; i++) {
                        sum += Number(pts[i] || 0)
                        cnt++
                    }
                    return cnt > 0 ? (sum / cnt) : 0
                }

                readonly property real ceiling: Math.max(100, Number(cavaProcess.normalizationCeiling || 1000))
                readonly property real normalized: {
                    if (!cavaProcess.audioSignalActive) {
                        // Subtle idle equalizer silhouette so module size/bars are always clear
                        const wave = 0.14 + 0.08 * Math.sin((index / Math.max(1, root.effectiveBarCount)) * Math.PI)
                        return wave
                    }
                    return Math.max(0.08, Math.min(1.0, rawPoint / ceiling))
                }

                readonly property real activeBarHeight: Math.max(2, Math.round(normalized * barSlot.height))
                readonly property color activeColor: root.barColorForIndex(index, root.effectiveBarCount, normalized)

                Rectangle {
                    width: barSlot.slotWidth
                    height: barSlot.activeBarHeight
                    radius: Math.min(root.barRadius, width / 2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.mirrorBars
                        ? (barSlot.height - height) / 2
                        : (barSlot.height - height)
                    color: barSlot.activeColor
                    opacity: cavaProcess.audioSignalActive ? 0.95 : 0.45

                    Behavior on height {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 65; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }
}
