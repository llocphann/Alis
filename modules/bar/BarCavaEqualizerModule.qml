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
        sampleCount: Math.max(32, root.effectiveBarCount)
    }

    property var _scratchA: []
    property var _scratchB: []
    property bool _scratchFlip: false
    readonly property var _idleNormalized: {
        const count = Math.max(1, root.effectiveBarCount)
        const out = new Array(count)
        out.fill(0)
        return out
    }

    // Upstream symmetric stereo presentation: CAVA outputs mirrored stereo frames
    // ([L_high..L_low, R_low..R_high]) so mapping samples directly across bars
    // keeps stereo bass symmetric at the center and highs tapering toward both edges,
    // while mono mode maps linearly left-to-right and silence settles to 0.
    function _fillNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive, out): var {
        const count = Math.max(1, Number(barCount) || 1)
        out.length = count
        const len = pts ? pts.length : 0
        if (!signalActive || len <= 0) {
            for (let i = 0; i < count; ++i) out[i] = 0
            return out
        }
        const ceiling = Math.max(1, Number(ceilingValue) || 20)
        const upsample = count > len && len > 1
        for (let idx = 0; idx < count; ++idx) {
            let level = 0
            if (upsample) {
                const pos = (idx * (len - 1)) / Math.max(1, count - 1)
                const lo = Math.floor(pos)
                const hi = Math.min(len - 1, lo + 1)
                const frac = pos - lo
                const vLo = Math.max(0, Number(pts[lo] || 0))
                const vHi = Math.max(0, Number(pts[hi] || 0))
                level = vLo * (1 - frac) + vHi * frac
            } else {
                const start = Math.floor(idx * len / count)
                const end = Math.min(len, Math.max(start + 1, Math.ceil((idx + 1) * len / count)))
                let sum = 0
                let peak = 0
                let cnt = 0
                for (let k = start; k < end; ++k) {
                    const s = Math.max(0, Number(pts[k] || 0))
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

    function computeNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive): var {
        return root._fillNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive, new Array(Math.max(1, Number(barCount) || 1)))
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

    // Precomputed per-bar palette (mirrored symmetrically in stereo mode) — zero per-frame Qt.rgba() churn.
    readonly property var cachedBarColors: {
        const count = Math.max(1, root.effectiveBarCount)
        const pal = root.paletteColors
        const out = new Array(count)
        if (!pal || pal.length === 0) {
            out.fill(Appearance.colors.colPrimary)
            return out
        }
        if (pal.length === 1) {
            out.fill(pal[0])
            return out
        }
        const symmetric = root.stereoSource
        for (let idx = 0; idx < count; ++idx) {
            const linear = count > 1 ? (idx / (count - 1)) : 0
            const pos = symmetric ? (1.0 - Math.abs(linear * 2.0 - 1.0)) : linear
            const scaled = pos * (pal.length - 1)
            const lo = Math.max(0, Math.min(pal.length - 1, Math.floor(scaled)))
            const hi = Math.max(0, Math.min(pal.length - 1, lo + 1))
            out[idx] = root._lerpColor(pal[lo], pal[hi], scaled - lo)
        }
        return out
    }

    function barColorForIndex(idx: int, count: int, normVal: real): color {
        const cached = root.cachedBarColors
        if (cached && idx >= 0 && idx < cached.length)
            return cached[idx]
        return Appearance.colors.colPrimary
    }

    Item {
        id: barsContainer
        anchors.centerIn: parent
        width: root.innerSpan
        height: Math.min(root.configuredHeight, Math.max(12, root.hostCross - 6))
        rotation: root.vertical ? 90 : 0
        clip: true

        // Imperative double-buffered frame rebuild (matching BarCavaVisualizer) avoids
        // self-mutating QML binding loops and redundant ceiling-decay recomputation.
        property var targetNormalized: root._idleNormalized

        function rebuildTargetNormalized(): void {
            if (!root.visible || !cavaProcess.audioSignalActive) {
                if (targetNormalized !== root._idleNormalized)
                    targetNormalized = root._idleNormalized
                return
            }
            root._scratchFlip = !root._scratchFlip
            const buf = root._scratchFlip ? root._scratchA : root._scratchB
            targetNormalized = root._fillNormalizedBars(
                cavaProcess.points,
                cavaProcess.normalizationCeiling,
                root.effectiveBarCount,
                root.stereoSource,
                true,
                buf
            )
        }

        Connections {
            target: cavaProcess
            function onPointsChanged(): void { barsContainer.rebuildTargetNormalized() }
            function onAudioSignalActiveChanged(): void { barsContainer.rebuildTargetNormalized() }
        }
        Connections {
            target: root
            function onVisibleChanged(): void { barsContainer.rebuildTargetNormalized() }
            function onEffectiveBarCountChanged(): void { barsContainer.rebuildTargetNormalized() }
            function onStereoSourceChanged(): void { barsContainer.rebuildTargetNormalized() }
        }
        Component.onCompleted: barsContainer.rebuildTargetNormalized()

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
                readonly property color activeColor: root.barColorForIndex(index, root.effectiveBarCount, 0)

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
