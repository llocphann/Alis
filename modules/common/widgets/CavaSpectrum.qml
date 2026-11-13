pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

Canvas {
    id: root

    property var points: []
    property bool active: false
    property bool threadedRendering: false
    property string visualizerType: "bars"
    property real normalizationCeiling: 1000
    property real fillRatio: 0.6
    property real spectrumOpacity: 0.35
    property color spectrumColor: Appearance.colors.colPrimary
    property var spectrumColors: CavaTheme.visualizerColors
    property real sampleStartRatio: 0
    property real sampleEndRatio: 1
    property bool reverseFrequency: false
    property real pixelsPerBar: 12
    property real barSpacing: 2
    property real barRadius: 2
    property real barMinHeight: 1
    property string barsOrigin: "bottom"
    property int smoothing: 2
    property string waveMode: "fill"
    // Filled/ribbon waves already get their visual edge from the gradient fill.
    // Owners that cover large surfaces can disable the extra top-edge stroke,
    // avoiding a second rasterized path over the same samples every CAVA frame.
    property bool waveOutlineEnabled: true
    property real lineWidth: 2
    property real edgeInset: 0
    property real leftRadius: 0
    property real rightRadius: 0
    property real topLeftRadius: -1
    property real topRightRadius: -1
    property real bottomLeftRadius: -1
    property real bottomRightRadius: -1
    property real edgeSoftness: 0.28
    property string frequencyProfile: "flat"
    property real accentStrength: 0.7
    // Cava stereo raw output mirrors frequency space: highs at the outer
    // edges and lows toward the center. Profiles must follow frequency, not
    // raw x-position, or bass/treble weighting targets opposite bands on the
    // left channel.
    property bool mirroredStereo: Config.options?.appearance?.cava?.stereo ?? true
    property real startOpacity: 1
    property real endOpacity: 1
    property real startTaper: -1
    property real endTaper: -1
    property var clipSegments: []

    // Per-instance frame scratch. These arrays are internal and reused across
    // paint frames to avoid transient JS allocation at the CAVA refresh rate.
    property var _selectedScratch: []
    property var _smoothScratch: []
    property var _primaryScratch: []
    property var _secondaryScratch: []
    property var _baselineScratch: []

    readonly property var _resolvedPalette: root._makePalette()
    readonly property var _resolvedCornerRadii: root._makeCornerRadii()
    readonly property var _resolvedEdgeTapers: root._makeEdgeTapers()

    renderStrategy: root.threadedRendering ? Canvas.Threaded : Canvas.Immediate

    visible: (root.points?.length ?? 0) > 0 && (root.active || root.opacity > 0.001)
    opacity: root.active ? Math.max(0, Math.min(1, root.spectrumOpacity)) : 0

    Behavior on opacity {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.calcEffectiveDuration(root.active ? 180 : 480)
            easing.type: root.active ? Easing.OutCubic : Easing.InOutCubic
        }
    }

    function _rgbaColor(value, alpha): string {
        const color = Qt.color(value)
        const r = Math.round(color.r * 255)
        const g = Math.round(color.g * 255)
        const b = Math.round(color.b * 255)
        return `rgba(${r},${g},${b},${Math.max(0, Math.min(1, alpha))})`
    }

    function _rgba(alpha): string {
        return root._rgbaColor(root.spectrumColor, alpha)
    }

    function _makePalette(): var {
        const source = root.spectrumColors ?? []
        const palette = []
        for (let i = 0; i < source.length; ++i) {
            const color = Qt.color(source[i])
            if (color.valid)
                palette.push(color)
        }
        if (palette.length === 0)
            palette.push(Qt.color(root.spectrumColor))
        return palette
    }

    function _colorAt(position): color {
        const palette = root._resolvedPalette
        if (palette.length === 1)
            return palette[0]

        const x = Math.max(0, Math.min(1, position)) * (palette.length - 1)
        const lower = Math.floor(x)
        const upper = Math.min(palette.length - 1, lower + 1)
        const amount = x - lower
        const a = palette[lower]
        const b = palette[upper]
        return Qt.rgba(
            a.r + (b.r - a.r) * amount,
            a.g + (b.g - a.g) * amount,
            a.b + (b.b - a.b) * amount,
            1)
    }

    function _horizontalGradient(ctx, x0, x1, alphaScale): var {
        const gradient = ctx.createLinearGradient(x0, 0, x1, 0)
        const stopCount = 16
        for (let i = 0; i <= stopCount; ++i) {
            const ratio = i / stopCount
            const x = x0 + (x1 - x0) * ratio
            const opacity = root.startOpacity
                + (root.endOpacity - root.startOpacity) * ratio
            gradient.addColorStop(ratio,
                root._rgbaColor(root._colorAt(ratio), opacity * alphaScale
                    * Math.sqrt(root._edgeMorphFactor(x, x0, x1))))
        }
        return gradient
    }

    function _selectedPoints(): var {
        const source = root.points ?? []
        const count = source.length ?? 0
        if (count === 0)
            return []

        const startRatio = Math.max(0, Math.min(1, root.sampleStartRatio))
        const endRatio = Math.max(startRatio, Math.min(1, root.sampleEndRatio))
        const start = Math.min(count - 1, Math.floor(startRatio * count))
        const end = Math.max(start + 1, Math.min(count, Math.ceil(endRatio * count)))
        const selectedCount = end - start
        const strength = Math.max(0, Math.min(1, root.accentStrength))
        const applyProfile = strength > 0 && root.frequencyProfile !== "flat"
        const selected = root._selectedScratch
        selected.length = selectedCount

        for (let i = 0; i < selectedCount; ++i) {
            let value = Number(source[start + i]) || 0
            if (applyProfile) {
                const domainPosition = startRatio + (endRatio - startRatio)
                    * (selectedCount > 1 ? i / (selectedCount - 1) : 0.5)
                const frequencyPosition = root.mirroredStereo
                    ? Math.abs(domainPosition * 2 - 1)
                    : domainPosition
                const profileWeight = root._profileWeight(frequencyPosition)
                value *= 1 + (profileWeight - 1) * strength
            }
            selected[i] = value
        }
        return selected
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

    function _frequencySmooth(source): var {
        const radius = Math.max(0, Math.round(root.smoothing))
        if (radius === 0 || source.length < 3)
            return source
        const out = root._smoothScratch
        out.length = source.length
        let start = 0
        let end = Math.min(source.length - 1, radius)
        let sum = 0
        for (let i = start; i <= end; i++)
            sum += source[i]
        for (let i = 0; i < source.length; i++) {
            const nextStart = Math.max(0, i - radius)
            const nextEnd = Math.min(source.length - 1, i + radius)
            while (start < nextStart)
                sum -= source[start++]
            while (end < nextEnd)
                sum += source[++end]
            out[i] = sum / Math.max(1, end - start + 1)
        }
        return out
    }

    function _makeCornerRadii(): var {
        const maximum = Math.max(0, Math.min(root.width / 2, root.height / 2))
        const tl = Math.max(0, Math.min(maximum,
            root.topLeftRadius >= 0 ? root.topLeftRadius : root.leftRadius))
        const tr = Math.max(0, Math.min(maximum,
            root.topRightRadius >= 0 ? root.topRightRadius : root.rightRadius))
        const bl = Math.max(0, Math.min(maximum,
            root.bottomLeftRadius >= 0 ? root.bottomLeftRadius : root.leftRadius))
        const br = Math.max(0, Math.min(maximum,
            root.bottomRightRadius >= 0 ? root.bottomRightRadius : root.rightRadius))
        return [tl, tr, br, bl]
    }

    function _smoothstep(value): real {
        const x = Math.max(0, Math.min(1, value))
        return x * x * (3 - 2 * x)
    }

    function _makeEdgeTapers(): var {
        const radii = root._resolvedCornerRadii
        const scale = 0.75 + Math.max(0, Math.min(1, root.edgeSoftness)) * 1.25
        const autoStart = Math.max(radii[0], radii[3]) * scale
        const autoEnd = Math.max(radii[1], radii[2]) * scale
        return [
            root.startTaper >= 0 ? root.startTaper : autoStart,
            root.endTaper >= 0 ? root.endTaper : autoEnd,
        ]
    }

    function _edgeMorphFactor(x, x0, x1): real {
        const tapers = root._resolvedEdgeTapers
        let factor = 1
        if (tapers[0] > 0)
            factor *= root._smoothstep((x - x0) / tapers[0])
        if (tapers[1] > 0)
            factor *= root._smoothstep((x1 - x) / tapers[1])
        return Math.max(0, Math.min(1, factor))
    }

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
        return radius - Math.sqrt(Math.max(0, radius * radius - distance * distance))
    }

    function _curveHeadroom(top, bottom): real {
        const available = Math.max(0, bottom - top)
        const curveInset = Math.max(top, root.height - bottom)
        const pressure = Math.max(0, Math.min(1,
            curveInset / Math.max(1, root.height / 2)))
        return available * Math.max(0, Math.min(1, root.edgeSoftness))
            * pressure * 0.24
    }

    function _appendRoundedClip(ctx, x, y, width, height, radii): void {
        const maximum = Math.max(0, Math.min(width / 2, height / 2))
        const tl = Math.max(0, Math.min(maximum, radii[0] ?? 0))
        const tr = Math.max(0, Math.min(maximum, radii[1] ?? 0))
        const br = Math.max(0, Math.min(maximum, radii[2] ?? 0))
        const bl = Math.max(0, Math.min(maximum, radii[3] ?? 0))
        ctx.moveTo(x + tl, y)
        ctx.lineTo(x + width - tr, y)
        if (tr > 0)
            ctx.quadraticCurveTo(x + width, y, x + width, y + tr)
        else
            ctx.lineTo(x + width, y)
        ctx.lineTo(x + width, y + height - br)
        if (br > 0)
            ctx.quadraticCurveTo(x + width, y + height, x + width - br, y + height)
        else
            ctx.lineTo(x + width, y + height)
        ctx.lineTo(x + bl, y + height)
        if (bl > 0)
            ctx.quadraticCurveTo(x, y + height, x, y + height - bl)
        else
            ctx.lineTo(x, y + height)
        ctx.lineTo(x, y + tl)
        if (tl > 0)
            ctx.quadraticCurveTo(x, y, x + tl, y)
        else
            ctx.lineTo(x, y)
        ctx.closePath()
    }

    function _clipSurface(ctx): void {
        const segments = root.clipSegments ?? []
        ctx.beginPath()
        if (segments.length > 0) {
            for (let i = 0; i < segments.length; ++i) {
                const segment = segments[i]
                if (!(segment?.width > 0) || !(segment?.height > 0))
                    continue
                root._appendRoundedClip(ctx, segment.x, segment.y,
                    segment.width, segment.height, segment.radii ?? [0, 0, 0, 0])
            }
        } else {
            root._appendRoundedClip(ctx, 0, 0, root.width, root.height,
                root._resolvedCornerRadii)
        }
        ctx.clip()
    }

    function _alphaAt(x): real {
        const ratio = root.width > 0 ? Math.max(0, Math.min(1, x / root.width)) : 0
        return Math.max(0, Math.min(1,
            root.startOpacity + (root.endOpacity - root.startOpacity) * ratio))
    }

    function _roundedRect(ctx, x, y, width, height, radius): void {
        ctx.beginPath()
        if (!(width > 0) || !(height > 0))
            return
        const r = Math.max(0, Math.min(radius, width / 2, height / 2))
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + width - r, y)
        ctx.quadraticCurveTo(x + width, y, x + width, y + r)
        ctx.lineTo(x + width, y + height - r)
        ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height)
        ctx.lineTo(x + r, y + height)
        ctx.quadraticCurveTo(x, y + height, x, y + height - r)
        ctx.lineTo(x, y + r)
        ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.closePath()
    }

    function _paintBars(ctx, source, x0, x1): void {
        const span = Math.max(1, x1 - x0)
        const pitch = Math.max(3, root.pixelsPerBar)
        const count = Math.max(4, Math.floor((span + root.barSpacing) / pitch))
        const slot = span / count
        const width = Math.max(1, slot - Math.max(0, root.barSpacing))
        const gradient = root._horizontalGradient(ctx, x0, x1, 1)
        const radii = root._resolvedCornerRadii
        const ceiling = Math.max(1, root.normalizationCeiling)
        ctx.fillStyle = gradient

        for (let i = 0; i < count; i++) {
            const x = x0 + i * slot + (slot - width) / 2
            const centerX = x + width / 2
            const edgeFactor = root._edgeMorphFactor(centerX, x0, x1)
            if (edgeFactor < 0.01)
                continue
            const top = Math.max(
                root._cornerInset(centerX, radii[0], true),
                root._cornerInset(centerX, radii[1], false))
            const bottomInset = Math.max(
                root._cornerInset(centerX, radii[3], true),
                root._cornerInset(centerX, radii[2], false))
            const bottom = Math.max(top, root.height - bottomInset)
            const curveHeadroom = root._curveHeadroom(top, bottom)

            const from = Math.floor(i * source.length / count)
            const to = Math.min(source.length,
                Math.max(from + 1, Math.ceil((i + 1) * source.length / count)))
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
            const rawValue = Math.max(0, Math.min(1,
                (average * 0.72 + peak * 0.28) / ceiling))
            const value = rawValue * edgeFactor
            const center = (top + bottom) / 2
            const peakTop = Math.min(center, top + curveHeadroom)
            const peakBottom = Math.max(center, bottom - curveHeadroom)
            ctx.globalAlpha = 0.5 + rawValue * 0.5

            if (root.barsOrigin === "top") {
                const available = Math.max(0, peakBottom - top)
                if (!(available > 0))
                    continue
                const height = Math.min(available, Math.max(root.barMinHeight * edgeFactor,
                    value * available * Math.max(0.1, Math.min(1, root.fillRatio))))
                root._roundedRect(ctx, x, top, width, height, root.barRadius)
                ctx.fill()
            } else if (root.barsOrigin === "center") {
                const available = Math.max(0, center - peakTop)
                if (!(available > 0))
                    continue
                const height = Math.min(available, Math.max(root.barMinHeight * edgeFactor,
                    value * available * Math.max(0.1, Math.min(1, root.fillRatio))))
                root._roundedRect(ctx, x, center - height, width, height, root.barRadius)
                ctx.fill()
            } else if (root.barsOrigin === "mirror") {
                const available = Math.max(0,
                    Math.min(center - peakTop, peakBottom - center))
                if (!(available > 0))
                    continue
                const halfHeight = Math.min(available, Math.max(root.barMinHeight * edgeFactor,
                    value * available * Math.max(0.1, Math.min(1, root.fillRatio))))
                root._roundedRect(ctx, x, center - halfHeight - 0.5, width, halfHeight, root.barRadius)
                ctx.fill()
                root._roundedRect(ctx, x, center + 0.5, width, halfHeight, root.barRadius)
                ctx.fill()
            } else {
                const available = Math.max(0, bottom - peakTop)
                if (!(available > 0))
                    continue
                const height = Math.min(available, Math.max(root.barMinHeight * edgeFactor,
                    value * available * Math.max(0.1, Math.min(1, root.fillRatio))))
                root._roundedRect(ctx, x, bottom - height, width, height, root.barRadius)
                ctx.fill()
            }
        }
        ctx.globalAlpha = 1
    }

    function _traceSmooth(ctx, coordinates): void {
        const pointCount = Math.floor(coordinates.length / 2)
        if (pointCount === 0)
            return
        ctx.moveTo(coordinates[0], coordinates[1])
        for (let i = 1; i < pointCount - 1; ++i) {
            const offset = i * 2
            const nextOffset = offset + 2
            const currentX = coordinates[offset]
            const currentY = coordinates[offset + 1]
            const nextX = coordinates[nextOffset]
            const nextY = coordinates[nextOffset + 1]
            ctx.quadraticCurveTo(currentX, currentY,
                (currentX + nextX) / 2, (currentY + nextY) / 2)
        }
        if (pointCount > 1) {
            const lastOffset = (pointCount - 1) * 2
            const lastX = coordinates[lastOffset]
            const lastY = coordinates[lastOffset + 1]
            ctx.quadraticCurveTo(lastX, lastY, lastX, lastY)
        }
    }

    function _paintWave(ctx, source, x0, x1): void {
        const span = Math.max(1, x1 - x0)
        const count = Math.max(2, Math.min(source.length,
            Math.round(span / Math.max(4, root.pixelsPerBar))))
        const ceiling = Math.max(1, root.normalizationCeiling)
        const ribbonMode = root.waveMode === "ribbon" || root.barsOrigin === "mirror"
        const lineMode = root.waveMode === "line"
        const primary = root._primaryScratch
        primary.length = 0
        const secondary = ribbonMode ? root._secondaryScratch : null
        if (secondary)
            secondary.length = 0
        const baseline = !ribbonMode && !lineMode ? root._baselineScratch : null
        if (baseline)
            baseline.length = 0
        const radii = root._resolvedCornerRadii
        const strokeHeadroom = Math.max(0, root.lineWidth / 2 + 0.5)

        for (let i = 0; i < count; i++) {
            const x = x0 + i * span / Math.max(1, count - 1)
            const edgeFactor = root._edgeMorphFactor(x, x0, x1)
            const top = Math.max(
                root._cornerInset(x, radii[0], true),
                root._cornerInset(x, radii[1], false))
            const bottomInset = Math.max(
                root._cornerInset(x, radii[3], true),
                root._cornerInset(x, radii[2], false))
            const bottom = Math.max(top, root.height - bottomInset)
            const center = (top + bottom) / 2
            const curveHeadroom = root._curveHeadroom(top, bottom)
            const peakTop = Math.min(center, top + curveHeadroom + strokeHeadroom)
            const peakBottom = Math.max(center, bottom - curveHeadroom - strokeHeadroom)
            let level = 0
            if (source.length === 1) {
                level = Math.max(0, Math.min(1, source[0] / ceiling))
            } else {
                const position = i * (source.length - 1) / Math.max(1, count - 1)
                const low = Math.floor(position)
                const high = Math.min(source.length - 1, low + 1)
                const fraction = position - low
                const sample = source[low] * (1 - fraction) + source[high] * fraction
                level = Math.max(0, Math.min(1, sample / ceiling))
            }
            const value = level * edgeFactor
            const fill = Math.max(0.1, Math.min(1, root.fillRatio))

            if (ribbonMode) {
                const maximum = Math.max(0,
                    Math.min(center - peakTop, peakBottom - center))
                const half = value * maximum * fill
                primary.push(x, center - half)
                secondary.push(x, center + half)
            } else if (root.barsOrigin === "top") {
                const maximum = Math.max(0, peakBottom - top)
                primary.push(x, top + value * maximum * fill)
                if (baseline)
                    baseline.push(x, top)
            } else if (root.barsOrigin === "center") {
                const maximum = Math.max(0, center - peakTop)
                primary.push(x, center - value * maximum * fill)
                if (baseline)
                    baseline.push(x, center)
            } else {
                const maximum = Math.max(0, bottom - peakTop)
                primary.push(x, bottom - value * maximum * fill)
                if (baseline)
                    baseline.push(x, bottom)
            }
        }

        const gradient = root._horizontalGradient(ctx, x0, x1, 1)

        if (lineMode) {
            ctx.beginPath()
            root._traceSmooth(ctx, primary)
            ctx.strokeStyle = gradient
            ctx.lineWidth = Math.max(1, root.lineWidth)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.stroke()
            return
        }

        ctx.beginPath()
        root._traceSmooth(ctx, primary)
        if (secondary) {
            for (let i = secondary.length - 2; i >= 0; i -= 2)
                ctx.lineTo(secondary[i], secondary[i + 1])
        } else if (baseline) {
            for (let i = baseline.length - 2; i >= 0; i -= 2)
                ctx.lineTo(baseline[i], baseline[i + 1])
        }
        ctx.closePath()
        ctx.fillStyle = gradient
        ctx.fill()

        if (root.waveOutlineEnabled) {
            ctx.beginPath()
            root._traceSmooth(ctx, primary)
            ctx.globalAlpha = 0.9
            ctx.strokeStyle = gradient
            ctx.lineWidth = Math.max(1, root.lineWidth * 0.65)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.stroke()
            ctx.globalAlpha = 1
        }
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, root.width, root.height)
        let selected = root._selectedPoints()
        selected = root._frequencySmooth(selected)
        if (root.reverseFrequency)
            selected.reverse()
        if (selected.length === 0 || !(root.width > 0) || !(root.height > 0))
            return
        const inset = Math.max(0, Math.min(root.width / 2 - 1, root.edgeInset))
        const x0 = inset
        const x1 = Math.max(x0 + 1, root.width - inset)
        ctx.save()
        root._clipSurface(ctx)
        if (root.visualizerType === "wave")
            root._paintWave(ctx, selected, x0, x1)
        else
            root._paintBars(ctx, selected, x0, x1)
        ctx.restore()
    }

    function _queuePaint(): void {
        if (root.visible && root.available)
            root.requestPaint()
    }

    onAvailableChanged: root._queuePaint()
    onPointsChanged: if (root.visible) root._queuePaint()
    onVisibleChanged: if (root.visible) root._queuePaint()
    onWidthChanged: root._queuePaint()
    onHeightChanged: root._queuePaint()
    onVisualizerTypeChanged: root._queuePaint()
    onNormalizationCeilingChanged: root._queuePaint()
    onFillRatioChanged: root._queuePaint()
    onSpectrumColorChanged: root._queuePaint()
    onSpectrumColorsChanged: root._queuePaint()
    onSampleStartRatioChanged: root._queuePaint()
    onSampleEndRatioChanged: root._queuePaint()
    onReverseFrequencyChanged: root._queuePaint()
    onPixelsPerBarChanged: root._queuePaint()
    onBarSpacingChanged: root._queuePaint()
    onBarRadiusChanged: root._queuePaint()
    onBarMinHeightChanged: root._queuePaint()
    onBarsOriginChanged: root._queuePaint()
    onSmoothingChanged: root._queuePaint()
    onWaveModeChanged: root._queuePaint()
    onWaveOutlineEnabledChanged: root._queuePaint()
    onLineWidthChanged: root._queuePaint()
    onEdgeInsetChanged: root._queuePaint()
    onLeftRadiusChanged: root._queuePaint()
    onRightRadiusChanged: root._queuePaint()
    onTopLeftRadiusChanged: root._queuePaint()
    onTopRightRadiusChanged: root._queuePaint()
    onBottomLeftRadiusChanged: root._queuePaint()
    onBottomRightRadiusChanged: root._queuePaint()
    onEdgeSoftnessChanged: root._queuePaint()
    onFrequencyProfileChanged: root._queuePaint()
    onMirroredStereoChanged: root._queuePaint()
    onAccentStrengthChanged: root._queuePaint()
    onStartOpacityChanged: root._queuePaint()
    onEndOpacityChanged: root._queuePaint()
    onStartTaperChanged: root._queuePaint()
    onEndTaperChanged: root._queuePaint()
    onClipSegmentsChanged: root._queuePaint()
}
