pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

// Scene-graph renderer for the full-width Bar audio spectrum.
//
// Keep the hot audio-frame path to one level-array rebuild plus primitive
// Rectangle updates. In particular, do not use Canvas/QQuickContext2D or a
// dynamically tessellated Shape/PathPolyline for the Bar.
Item {
    id: root

    property var points: []
    property bool active: false
    property string visualizerType: "bars"
    property real normalizationCeiling: 1000
    property real fillRatio: 0.6
    property real spectrumOpacity: 0.35
    property color spectrumColor: Appearance.colors.colPrimary
    property var spectrumColors: CavaTheme.visualizerColors
    property real pixelsPerBar: 12
    property real barSpacing: 2
    property real barRadius: 2
    property real barMinHeight: 1
    property string barsOrigin: "bottom"
    property int smoothing: 2
    property string waveMode: "fill"
    property real lineWidth: 2
    property real edgeInset: 0
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    property real edgeSoftness: 0.28
    property string frequencyProfile: "flat"
    property real accentStrength: 0.7
    property bool mirroredStereo: Config.options?.appearance?.cava?.stereo ?? true
    // A short Bar does not gain useful visual detail from hundreds of
    // horizontal wave primitives. Cap only the continuous wave path; discrete
    // bars continue to honor the configured density exactly.
    property int waveStripCap: 72

    property var _levels: []
    property var _selectedScratch: []
    property var _smoothScratch: []
    // Frequency shaping depends on geometry/config, never on amplitudes.
    // Keep just one vector per owner; frame buffers and publication stay intact.
    readonly property var _profileCache: ({
        count: -1, profile: "", stereo: false, strength: 0, factors: []
    })
    // Alternate two stable frame buffers so _levels still receives a new
    // object identity (and therefore notifies delegates) without allocating a
    // fresh JS array on every CAVA frame.
    property var _levelScratchA: []
    property var _levelScratchB: []
    property bool _levelScratchFlip: false

    readonly property real _innerWidth: Math.max(1, width - edgeInset * 2)
    readonly property int _barCount: root.active && root.visualizerType === "bars"
        ? Math.max(4, Math.floor(
            (root._innerWidth + Math.max(0, root.barSpacing))
            / Math.max(3, root.pixelsPerBar)))
        : 0
    readonly property int _levelCount: root._levels.length

    visible: root.opacity > 0.001 || root.active
    opacity: root.active ? Math.max(0, Math.min(1, root.spectrumOpacity)) : 0

    Behavior on opacity {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.calcEffectiveDuration(root.active ? 180 : 480)
            easing.type: root.active ? Easing.OutCubic : Easing.InOutCubic
        }
    }

    function _profileWeight(position): real {
        const x = Math.max(0, Math.min(1, position))
        if (root.frequencyProfile === "bass")
            return 0.44 + 1.86 * Math.exp(-4.2 * x)
        if (root.frequencyProfile === "warm")
            return 1.82 - 1.08 * x
        if (root.frequencyProfile === "vocal") {
            const distance = (x - 0.46) / 0.17
            return 0.48 + 1.72 * Math.exp(-distance * distance)
        }
        if (root.frequencyProfile === "treble")
            return 0.44 + 1.86 * Math.pow(x, 1.75)
        if (root.frequencyProfile === "smile")
            return 0.52 + 1.56 * Math.pow(Math.abs(x - 0.5) * 2, 1.45)
        return 1
    }

    function _profileFactors(count, strength): var {
        const cache = root._profileCache
        const profile = root.frequencyProfile
        const stereo = root.mirroredStereo
        if (cache.count !== count || cache.profile !== profile
                || cache.stereo !== stereo || cache.strength !== strength) {
            const factors = cache.factors
            factors.length = count
            for (let i = 0; i < count; ++i) {
                const domain = count > 1 ? i / (count - 1) : 0.5
                const frequency = stereo ? Math.abs(domain * 2 - 1) : domain
                const weight = root._profileWeight(frequency)
                factors[i] = 1 + (weight - 1) * strength
            }
            cache.count = count
            cache.profile = profile
            cache.stereo = stereo
            cache.strength = strength
        }
        return cache.factors
    }

    function _processedSource(): var {
        const source = root.points ?? []
        const count = source.length ?? 0
        if (!root.active || count === 0)
            return []

        const selected = root._selectedScratch
        selected.length = count
        const strength = Math.max(0, Math.min(1, root.accentStrength))
        const applyProfile = strength > 0 && root.frequencyProfile !== "flat"
        const factors = applyProfile ? root._profileFactors(count, strength) : null

        for (let i = 0; i < count; ++i) {
            let value = Number(source[i]) || 0
            if (applyProfile) {
                value *= factors[i]
            }
            selected[i] = value
        }

        const radius = Math.max(0, Math.round(root.smoothing))
        if (radius === 0 || count < 3)
            return selected

        const smoothed = root._smoothScratch
        smoothed.length = count
        let start = 0
        let end = Math.min(count - 1, radius)
        let sum = 0
        for (let i = start; i <= end; ++i)
            sum += selected[i]

        for (let i = 0; i < count; ++i) {
            const nextStart = Math.max(0, i - radius)
            const nextEnd = Math.min(count - 1, i + radius)
            while (start < nextStart)
                sum -= selected[start++]
            while (end < nextEnd)
                sum += selected[++end]
            smoothed[i] = sum / Math.max(1, end - start + 1)
        }
        return smoothed
    }

    function _sampleAt(source, ratio): real {
        const count = source.length ?? 0
        if (count === 0)
            return 0
        if (count === 1)
            return source[0] || 0

        const position = Math.max(0, Math.min(count - 1, ratio * (count - 1)))
        const low = Math.floor(position)
        const high = Math.min(count - 1, low + 1)
        const fraction = position - low
        return (source[low] || 0) * (1 - fraction)
            + (source[high] || 0) * fraction
    }

    function _nextLevelScratch(count): var {
        root._levelScratchFlip = !root._levelScratchFlip
        const levels = root._levelScratchFlip
            ? root._levelScratchA : root._levelScratchB
        levels.length = count
        return levels
    }

    function _rebuildLevels(): void {
        if (!root.active) {
            if (root._levels.length > 0)
                root._levels = []
            return
        }

        const source = root._processedSource()
        const sourceCount = source.length ?? 0
        if (sourceCount === 0) {
            if (root._levels.length > 0)
                root._levels = []
            return
        }

        const ceiling = Math.max(1, root.normalizationCeiling)
        if (root.visualizerType === "bars") {
            const count = root._barCount
            const levels = root._nextLevelScratch(count)
            for (let i = 0; i < count; ++i) {
                const from = Math.floor(i * sourceCount / count)
                const to = Math.min(sourceCount,
                    Math.max(from + 1, Math.ceil((i + 1) * sourceCount / count)))
                let sum = 0
                let peak = 0
                let samples = 0
                for (let j = from; j < to; ++j) {
                    const sample = source[j] || 0
                    sum += sample
                    peak = Math.max(peak, sample)
                    samples++
                }
                const average = samples > 0 ? sum / samples : 0
                levels[i] = Math.max(0, Math.min(1,
                    (average * 0.72 + peak * 0.28) / ceiling))
            }
            root._levels = levels
            return
        }

        const count = Math.max(2, Math.min(sourceCount, root.waveStripCap,
            Math.round(root._innerWidth / Math.max(4, root.pixelsPerBar))))
        const levels = root._nextLevelScratch(count)
        for (let i = 0; i < count; ++i) {
            const ratio = count > 1 ? i / (count - 1) : 0
            levels[i] = Math.max(0, Math.min(1,
                root._sampleAt(source, ratio) / ceiling))
        }
        root._levels = levels
    }

    // CavaService raises the adaptive ceiling before publishing louder points
    // and lowers it after weaker points. Rebuild on points only: this gives a
    // coherent loud frame and at most one-frame lag while the ceiling decays,
    // instead of doing a second geometry pass for the same CAVA frame.
    onPointsChanged: root._rebuildLevels()
    onActiveChanged: root._rebuildLevels()
    onVisualizerTypeChanged: root._rebuildLevels()
    onPixelsPerBarChanged: root._rebuildLevels()
    onBarSpacingChanged: root._rebuildLevels()
    onSmoothingChanged: root._rebuildLevels()
    onFrequencyProfileChanged: root._rebuildLevels()
    onAccentStrengthChanged: root._rebuildLevels()
    onMirroredStereoChanged: root._rebuildLevels()
    onWidthChanged: root._rebuildLevels()
    Component.onCompleted: root._rebuildLevels()

    function _cornerInset(x, radius, fromLeft): real {
        if (!(radius > 0))
            return 0
        let distance = 0
        if (fromLeft) {
            if (x >= radius)
                return 0
            distance = radius - Math.max(0, x)
        } else {
            if (x <= root.width - radius)
                return 0
            distance = Math.max(0, x - (root.width - radius))
        }
        return radius - Math.sqrt(Math.max(
            0, radius * radius - distance * distance))
    }

    function _edgeFactor(x): real {
        const scale = 0.75 + Math.max(0, Math.min(1, root.edgeSoftness)) * 1.25
        const startTaper = Math.max(
            root.topLeftRadius, root.bottomLeftRadius) * scale
        const endTaper = Math.max(
            root.topRightRadius, root.bottomRightRadius) * scale
        const x0 = Math.max(0, root.edgeInset)
        const x1 = Math.max(x0 + 1, root.width - root.edgeInset)
        let factor = 1
        if (startTaper > 0) {
            const t = Math.max(0, Math.min(1, (x - x0) / startTaper))
            factor *= t * t * (3 - 2 * t)
        }
        if (endTaper > 0) {
            const t = Math.max(0, Math.min(1, (x1 - x) / endTaper))
            factor *= t * t * (3 - 2 * t)
        }
        return Math.max(0, Math.min(1, factor))
    }

    function _topAt(x): real {
        return Math.max(
            root._cornerInset(x, root.topLeftRadius, true),
            root._cornerInset(x, root.topRightRadius, false))
    }

    function _bottomAt(x): real {
        const top = root._topAt(x)
        const bottomInset = Math.max(
            root._cornerInset(x, root.bottomLeftRadius, true),
            root._cornerInset(x, root.bottomRightRadius, false))
        return Math.max(top, root.height - bottomInset)
    }

    function _waveX(index): real {
        if (root._levelCount <= 1)
            return root.edgeInset
        return root.edgeInset
            + index * root._innerWidth / (root._levelCount - 1)
    }

    function _waveY(index, rawLevel): real {
        const x = root._waveX(index)
        const top = root._topAt(x)
        const bottom = root._bottomAt(x)
        const center = (top + bottom) / 2
        const level = Math.max(0, Math.min(1, rawLevel))
            * root._edgeFactor(x)
        const fill = Math.max(0.1, Math.min(1, root.fillRatio))
        if (root.barsOrigin === "top")
            return top + level * Math.max(0, bottom - top) * fill
        if (root.barsOrigin === "center" || root.barsOrigin === "mirror")
            return center - level * Math.max(0, center - top) * fill
        return bottom - level * Math.max(0, bottom - top) * fill
    }

    function _paletteColor(position): color {
        const palette = root.spectrumColors ?? []
        const count = palette.length ?? 0
        if (count === 0)
            return root.spectrumColor
        if (count === 1)
            return palette[0]

        const p = Math.max(0, Math.min(1, position)) * (count - 1)
        const low = Math.floor(p)
        const high = Math.min(count - 1, low + 1)
        const t = p - low
        const a = Qt.color(palette[low])
        const b = Qt.color(palette[high])
        if (!a.valid || !b.valid)
            return root.spectrumColor
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            a.a + (b.a - a.a) * t)
    }

    Repeater {
        id: barRepeater
        model: root.visualizerType === "bars" ? root._barCount : 0

        delegate: Item {
            required property int index

            readonly property int count: Math.max(1, root._barCount)
            readonly property real slot: root._innerWidth / count
            readonly property real barWidth: Math.max(
                1, slot - Math.max(0, root.barSpacing))
            readonly property real centerX: root.edgeInset
                + index * slot + slot / 2
            readonly property real rawLevel:
                Number(root._levels[index] ?? 0)
            readonly property real edge: root._edgeFactor(centerX)
            readonly property real level: rawLevel * edge
            readonly property real topY: root._topAt(centerX)
            readonly property real bottomY: root._bottomAt(centerX)
            readonly property real centerY: (topY + bottomY) / 2
            readonly property color barColor:
                root._paletteColor(count > 1 ? index / (count - 1) : 0.5)

            x: root.edgeInset + index * slot + (slot - barWidth) / 2
            y: 0
            width: barWidth
            height: root.height
            opacity: 0.5 + rawLevel * 0.5

            Rectangle {
                visible: root.barsOrigin !== "mirror"
                width: parent.width
                radius: Math.min(root.barRadius, width / 2, height / 2)
                color: parent.barColor
                readonly property real available: root.barsOrigin === "center"
                    ? Math.max(0, parent.centerY - parent.topY)
                    : Math.max(0, parent.bottomY - parent.topY)
                height: Math.min(available,
                    Math.max(root.barMinHeight * parent.edge,
                        parent.level * available
                            * Math.max(0.1, Math.min(1, root.fillRatio))))
                y: root.barsOrigin === "top"
                    ? parent.topY
                    : root.barsOrigin === "center"
                        ? parent.centerY - height
                        : parent.bottomY - height
            }

            Rectangle {
                visible: root.barsOrigin === "mirror"
                width: parent.width
                radius: Math.min(root.barRadius, width / 2, height / 2)
                color: parent.barColor
                readonly property real halfAvailable: Math.max(
                    0, (parent.bottomY - parent.topY) / 2 - 0.5)
                readonly property real halfHeight: Math.min(halfAvailable,
                    Math.max(root.barMinHeight * parent.edge,
                        parent.level * halfAvailable
                            * Math.max(0.1, Math.min(1, root.fillRatio))))
                height: halfHeight
                y: parent.centerY - height - 0.5
            }

            Rectangle {
                visible: root.barsOrigin === "mirror"
                width: parent.width
                radius: Math.min(root.barRadius, width / 2, height / 2)
                color: parent.barColor
                readonly property real halfAvailable: Math.max(
                    0, (parent.bottomY - parent.topY) / 2 - 0.5)
                readonly property real halfHeight: Math.min(halfAvailable,
                    Math.max(root.barMinHeight * parent.edge,
                        parent.level * halfAvailable
                            * Math.max(0.1, Math.min(1, root.fillRatio))))
                height: halfHeight
                y: parent.centerY + 0.5
            }
        }
    }

    // Filled and ribbon waves keep cheap vertical fill strips, but each sample
    // also bridges its visible edge to the next sample with a scene-graph quad.
    // This preserves the low-cost renderer while making the silhouette read as
    // one continuous waveform instead of a row of individually rounded spikes.
    Repeater {
        id: waveFillRepeater
        model: root.visualizerType === "wave" && root.waveMode !== "line"
            ? root._levelCount : 0

        delegate: Item {
            required property int index

            readonly property real slot: root._innerWidth
                / Math.max(1, root._levelCount - 1)
            readonly property real centerX: root._waveX(index)
            readonly property real topY: root._topAt(centerX)
            readonly property real bottomY: root._bottomAt(centerX)
            readonly property real centerY: (topY + bottomY) / 2
            readonly property bool ribbon:
                root.waveMode === "ribbon" || root.barsOrigin === "mirror"
            readonly property real rawLevel:
                Number(root._levels[index] ?? 0)
            readonly property real waveY: root._waveY(index, rawLevel)
            readonly property real lowerWaveY: ribbon
                ? centerY + Math.max(0, centerY - waveY)
                : waveY
            readonly property color waveColor: root._paletteColor(
                root._levelCount > 1 ? index / (root._levelCount - 1) : 0.5)

            readonly property bool hasNext: index + 1 < root._levelCount
            readonly property real nextX: hasNext
                ? root._waveX(index + 1) : centerX
            readonly property real nextWaveY: hasNext
                ? root._waveY(index + 1,
                    Number(root._levels[index + 1] ?? 0))
                : waveY
            readonly property real nextTopY: hasNext
                ? root._topAt(nextX) : topY
            readonly property real nextBottomY: hasNext
                ? root._bottomAt(nextX) : bottomY
            readonly property real nextCenterY:
                (nextTopY + nextBottomY) / 2
            readonly property real nextLowerWaveY: ribbon
                ? nextCenterY + Math.max(0, nextCenterY - nextWaveY)
                : nextWaveY
            readonly property real connectorDx: nextX - centerX
            readonly property real connectorDy: nextWaveY - waveY
            readonly property real connectorLength: Math.sqrt(
                connectorDx * connectorDx + connectorDy * connectorDy)
            readonly property real lowerConnectorDy:
                nextLowerWaveY - lowerWaveY
            readonly property real lowerConnectorLength: Math.sqrt(
                connectorDx * connectorDx
                    + lowerConnectorDy * lowerConnectorDy)
            readonly property real connectorThickness:
                Math.max(1.5, root.lineWidth * 0.8)

            // Clamp both strip edges, not only x. The first sample is centered
            // exactly on edgeInset; keeping a full slot width after clamping x
            // makes it overlap roughly half of sample 1 and renders the left
            // corner visibly brighter. Mirror the same half-cell treatment at
            // the right edge while preserving the small interior seam overlap.
            readonly property real stripLeft: Math.max(
                root.edgeInset, centerX - slot / 2)
            readonly property real stripRight: Math.max(stripLeft + 1,
                Math.min(root.width - root.edgeInset,
                    centerX + slot / 2 + (hasNext ? 0.75 : 0)))

            x: stripLeft
            y: 0
            width: Math.max(1, stripRight - stripLeft)
            height: root.height

            Rectangle {
                x: 0
                width: parent.width
                radius: 0
                color: parent.waveColor
                y: parent.ribbon
                    ? parent.waveY
                    : root.barsOrigin === "top"
                        ? parent.topY
                        : parent.waveY
                height: parent.ribbon
                    ? Math.max(0, parent.lowerWaveY - parent.waveY)
                    : root.barsOrigin === "top"
                        ? Math.max(0, parent.waveY - parent.topY)
                        : root.barsOrigin === "center"
                            ? Math.max(0, parent.centerY - parent.waveY)
                            : Math.max(0, parent.bottomY - parent.waveY)
            }

            Rectangle {
                visible: parent.hasNext
                x: parent.centerX - parent.x
                y: parent.waveY - height / 2
                width: parent.connectorLength
                height: parent.connectorThickness
                radius: height / 2
                color: root._paletteColor(
                    root._levelCount > 1
                        ? (parent.index + 0.5) / (root._levelCount - 1)
                        : 0.5)
                transformOrigin: Item.Left
                rotation: Math.atan2(
                    parent.connectorDy, parent.connectorDx) * 180 / Math.PI
            }

            Rectangle {
                visible: parent.ribbon && parent.hasNext
                x: parent.centerX - parent.x
                y: parent.lowerWaveY - height / 2
                width: parent.lowerConnectorLength
                height: parent.connectorThickness
                radius: height / 2
                color: root._paletteColor(
                    root._levelCount > 1
                        ? (parent.index + 0.5) / (root._levelCount - 1)
                        : 0.5)
                transformOrigin: Item.Left
                rotation: Math.atan2(
                    parent.lowerConnectorDy, parent.connectorDx)
                    * 180 / Math.PI
            }
        }
    }

    // Line mode uses GPU-friendly quads between adjacent samples instead of a
    // ShapePath. No JS point arrays or per-frame tessellation are involved.
    Repeater {
        id: waveLineRepeater
        model: root.visualizerType === "wave" && root.waveMode === "line"
            ? Math.max(0, root._levelCount - 1) : 0

        delegate: Item {
            required property int index

            readonly property real x0: root._waveX(index)
            readonly property real x1: root._waveX(index + 1)
            readonly property real y0: root._waveY(
                index, Number(root._levels[index] ?? 0))
            readonly property real y1: root._waveY(
                index + 1, Number(root._levels[index + 1] ?? 0))
            readonly property real dx: x1 - x0
            readonly property real dy: y1 - y0
            readonly property real segmentLength: Math.sqrt(dx * dx + dy * dy)

            x: x0
            y: y0 - Math.max(1, root.lineWidth) / 2
            width: segmentLength
            height: Math.max(1, root.lineWidth)
            transformOrigin: Item.Left
            rotation: Math.atan2(dy, dx) * 180 / Math.PI

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root._paletteColor(
                    root._levelCount > 1
                        ? index / (root._levelCount - 1) : 0.5)
            }
        }
    }
}
