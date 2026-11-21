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
    // AbyssBarModule already rotates its Loader by contentRotation while passing
    // vertical: false and horizontal dimensions; only classic vertical BarContent
    // sets vertical: true and expects internal 90° rotation + swapped axes.
    readonly property bool isVertical: root.vertical
    readonly property bool contentAvailable: true

    readonly property int configuredWidth: Math.max(48, Math.min(480, Number(Config.options?.bar?.cava?.width ?? 120)))
    readonly property int configuredHeight: Math.max(10, Math.min(30, Number(Config.options?.bar?.cava?.height ?? 22)))
    readonly property int barSpacing: Math.max(1, Math.min(6, Number(Config.options?.bar?.cava?.barSpacing ?? 2)))
    readonly property int barRadius: Math.max(0, Math.min(6, Number(Config.options?.bar?.cava?.barRadius ?? 2)))
    readonly property bool mirrorBars: Boolean(Config.options?.bar?.cava?.mirror ?? false)
    readonly property bool stereoSource: Config.options?.appearance?.cava?.stereo ?? true
    readonly property int configuredBarCount: Math.max(0, Math.min(200, Number(Config.options?.appearance?.cava?.bars ?? 0)))

    readonly property real hostSpan: {
        const liveSpan = root.isVertical ? root.height : root.width
        return liveSpan > 1 ? liveSpan : root.configuredWidth
    }
    readonly property real hostCross: {
        const liveCross = root.isVertical ? root.width : root.height
        return liveCross > 1 ? liveCross : Number(Appearance.sizes.barHeight)
    }
    readonly property real innerSpan: Math.max(24, root.hostSpan - 10)
    readonly property real minBarWidth: 1.5
    readonly property real minBarGap: 1.0
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
        return Math.max(1.2, (root.innerSpan - (root.effectiveBarCount - 1) * root.effectiveGap) / root.effectiveBarCount)
    }

    readonly property real barPitch: root.effectiveBarCount > 1
        ? (root.innerSpan - root.barWidth) / (root.effectiveBarCount - 1)
        : 0

    clip: true
    implicitWidth: root.isVertical ? Number(Appearance.sizes.barHeight) : root.configuredWidth
    implicitHeight: root.isVertical ? root.configuredWidth : Number(Appearance.sizes.barHeight)

    CavaProcess {
        id: cavaProcess
        active: root.visible && (MprisController.anyAudioPlaying || Audio.hasActivePlayback)
        sampleCount: Math.max(32, root.effectiveBarCount * (root.stereoSource ? 2 : 1))
    }

    readonly property var _idleNormalized: {
        const count = Math.max(1, root.effectiveBarCount)
        const out = new Array(count)
        out.fill(0)
        return out
    }

    // Fold stereo CAVA frames ([L_high..L_low, R_low..R_high]) into a canonical
    // left-to-right bass -> mid -> treble bar equalizer, or bin mono frames
    // linearly, settling cleanly to 0 baseline whenever audio is inactive.
    function computeNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive): var {
        const count = Math.max(1, Number(barCount) || 1)
        const out = new Array(count)
        const len = pts ? pts.length : 0
        if (!signalActive || len <= 0) {
            out.fill(0)
            return out
        }
        const ceiling = Math.max(1, Number(ceilingValue) || 20)
        const foldStereo = Boolean(isStereo) && len >= 2
        const freqBins = foldStereo ? Math.floor(len / 2) : len
        const rightOffset = foldStereo ? (len - freqBins) : 0

        function readBin(k) {
            if (foldStereo) {
                const leftSample = Math.max(0, Number(pts[freqBins - 1 - k] || 0))
                const rightSample = Math.max(0, Number(pts[rightOffset + k] || 0))
                return (leftSample + rightSample) * 0.5
            }
            return Math.max(0, Number(pts[k] || 0))
        }

        const upsample = count > freqBins && freqBins > 1
        for (let idx = 0; idx < count; ++idx) {
            let level = 0
            if (upsample) {
                const pos = (idx * (freqBins - 1)) / Math.max(1, count - 1)
                const lo = Math.floor(pos)
                const hi = Math.min(freqBins - 1, lo + 1)
                const frac = pos - lo
                level = readBin(lo) * (1 - frac) + readBin(hi) * frac
            } else {
                const start = Math.floor(idx * freqBins / count)
                const end = Math.min(freqBins, Math.max(start + 1, Math.ceil((idx + 1) * freqBins / count)))
                let sum = 0
                let peak = 0
                let cnt = 0
                for (let k = start; k < end; ++k) {
                    const s = readBin(k)
                    sum += s
                    if (s > peak) peak = s
                    cnt++
                }
                const avg = cnt > 0 ? (sum / cnt) : 0
                level = avg * 0.62 + peak * 0.38
            }
            const clamped = Math.max(0, Math.min(1.0, level / ceiling))
            out[idx] = clamped > 0.002 ? Math.pow(clamped, 0.82) : 0
        }
        return out
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

    function _lerpColor(a: color, b: color, t: real): color {
        const f = Math.max(0, Math.min(1, t))
        return Qt.rgba(
            a.r + (b.r - a.r) * f,
            a.g + (b.g - a.g) * f,
            a.b + (b.b - a.b) * f,
            a.a + (b.a - a.a) * f
        )
    }

    function barColorForIndex(idx: int, count: int, normVal: real): color {
        const pal = root.paletteColors
        if (!pal || pal.length === 0) return Appearance.colors.colPrimary
        if (pal.length === 1) return pal[0]
        const pos = count > 1 ? (idx / (count - 1)) : 0
        const mix = Math.min(1, Math.max(0, pos * 0.55 + normVal * 0.45))
        const scaled = mix * (pal.length - 1)
        const lo = Math.max(0, Math.min(pal.length - 1, Math.floor(scaled)))
        const hi = Math.max(0, Math.min(pal.length - 1, lo + 1))
        return root._lerpColor(pal[lo], pal[hi], scaled - lo)
    }

    Item {
        id: barsContainer
        anchors.centerIn: parent
        width: root.innerSpan
        height: Math.min(root.configuredHeight, Math.max(12, root.hostCross - 6))
        rotation: root.vertical ? 90 : 0
        clip: true

        readonly property var targetNormalized: {
            if (!root.visible || !cavaProcess.audioSignalActive)
                return root._idleNormalized
            return root.computeNormalizedBars(
                cavaProcess.points,
                cavaProcess.normalizationCeiling,
                root.effectiveBarCount,
                root.stereoSource,
                true
            )
        }

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

                property real normalizedPoint: (index < barsContainer.targetNormalized.length)
                    ? barsContainer.targetNormalized[index] : 0
                Behavior on normalizedPoint {
                    enabled: Appearance.animationsEnabled && root.visible
                    NumberAnimation { duration: 42; easing.type: Easing.OutQuad }
                }
                readonly property real activeBarHeight: Math.max(2, Math.round(normalizedPoint * barSlot.height))
                readonly property color activeColor: root.barColorForIndex(index, root.effectiveBarCount, normalizedPoint)

                Rectangle {
                    width: barSlot.slotWidth
                    height: barSlot.activeBarHeight
                    topLeftRadius: Math.min(root.barRadius, width / 2)
                    topRightRadius: Math.min(root.barRadius, width / 2)
                    bottomLeftRadius: root.mirrorBars ? topLeftRadius : Math.min(1, width / 2)
                    bottomRightRadius: root.mirrorBars ? topRightRadius : Math.min(1, width / 2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.mirrorBars
                        ? (barSlot.height - height) / 2
                        : (barSlot.height - height)
                    color: barSlot.activeColor
                    opacity: cavaProcess.audioSignalActive ? 0.96 : 0.34
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled && root.visible
                        NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }
}
