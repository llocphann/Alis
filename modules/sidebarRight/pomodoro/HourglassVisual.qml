import QtQuick
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root

    property string visualStyle: "turned"
    property real progress: 1.0
    property bool running: false
    property bool paused: false
    property bool overtime: false
    property bool isBreak: false

    property color accentColor: Appearance.colors.colPrimary
    property color textColor: Appearance.colors.colOnLayer1
    property color sandColor: root.overtime
        ? Appearance.colors.colError
        : ColorUtils.mix(root.accentColor, root.textColor, 0.74)
    property color sandHighlightColor: root.overtime
        ? Appearance.colors.colError
        : ColorUtils.mix("#ffffff", root.sandColor, 0.35)
    property color frameColor: root.overtime
        ? Appearance.colors.colError
        : ColorUtils.mix(root.textColor, root.accentColor, 0.65)
    property color emptyDotColor: Qt.alpha(root.textColor, 0.14)
    property color glassTintColor: Qt.alpha(root.accentColor, 0.08)
    property color glassHighlightColor: Appearance.colors.colLayer1.hslLightness > 0.5
        ? Qt.rgba(1, 1, 1, 0.52)
        : Qt.rgba(1, 1, 1, 0.22)

    readonly property string normalizedStyle: {
        const s = String(root.visualStyle || "turned").toLowerCase()
        return (s === "matrix" || s === "square" || s === "turned") ? s : "turned"
    }
    readonly property real clampedProgress: root.overtime
        ? 0.0
        : Math.max(0.0, Math.min(1.0, Number(root.progress) || 0.0))

    property real grainPhase: 0.0
    property real flipRotation: 0.0
    property real _lastProgress: 1.0

    implicitWidth: 140
    implicitHeight: 168

    function triggerFlip(): void {
        if (!Appearance.animationsEnabled) {
            flipAnim.stop()
            root.flipRotation = 0
            return
        }
        flipAnim.restart()
    }

    function rgba(c, alphaScale) {
        const a = Math.max(0, Math.min(1, c.a * alphaScale))
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a.toFixed(3) + ")"
    }

    function roundedRectPath(ctx, x, y, w, h, r) {
        const radius = Math.min(r, w / 2, h / 2)
        ctx.beginPath()
        ctx.moveTo(x + radius, y)
        ctx.arcTo(x + w, y, x + w, y + h, radius)
        ctx.arcTo(x + w, y + h, x, y + h, radius)
        ctx.arcTo(x, y + h, x, y, radius)
        ctx.arcTo(x, y, x + w, y, radius)
        ctx.closePath()
    }

    onClampedProgressChanged: {
        if (!root.overtime && root.clampedProgress - root._lastProgress > 0.45 && root.visible)
            root.triggerFlip()
        root._lastProgress = root.clampedProgress
        canvas.requestPaint()
    }
    onNormalizedStyleChanged: canvas.requestPaint()
    onRunningChanged: canvas.requestPaint()
    onPausedChanged: canvas.requestPaint()
    onOvertimeChanged: canvas.requestPaint()
    onAccentColorChanged: canvas.requestPaint()
    onSandColorChanged: canvas.requestPaint()
    onFrameColorChanged: canvas.requestPaint()
    onEmptyDotColorChanged: canvas.requestPaint()

    NumberAnimation {
        id: flipAnim
        target: root
        property: "flipRotation"
        from: -180
        to: 0
        duration: 440
        easing.type: Easing.OutCubic
    }

    Timer {
        id: grainTimer
        interval: 42
        repeat: true
        running: root.visible && root.running && !root.paused && root.clampedProgress > 0.001 && !root.overtime && Appearance.animationsEnabled
        onTriggered: {
            root.grainPhase = (root.grainPhase + 0.085) % 1.0
            canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        transform: Rotation {
            origin.x: canvas.width / 2
            origin.y: canvas.height / 2
            angle: root.flipRotation
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const w = width
            const h = height
            if (w <= 0 || h <= 0)
                return

            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, w, h)

            // Virtual coordinate space: 120 x 144
            const scale = Math.min(w / 120.0, h / 144.0)
            const ox = (w - 120.0 * scale) / 2.0
            const oy = (h - 144.0 * scale) / 2.0

            ctx.save()
            ctx.translate(ox, oy)
            ctx.scale(scale, scale)

            if (root.normalizedStyle === "matrix") {
                root._paintMatrix(ctx)
            } else if (root.normalizedStyle === "square") {
                root._paintSquare(ctx)
            } else {
                root._paintTurned(ctx)
            }

            ctx.restore()
        }
    }

    function _paintTurned(ctx) {
        const p = root.clampedProgress
        const botFrac = 1.0 - p
        const activeFlow = root.running && !root.paused && p > 0.002 && !root.overtime

        // Soft interior glass tint
        ctx.fillStyle = root.rgba(root.glassTintColor, 1.0)
        ctx.beginPath()
        ctx.moveTo(33.5, 16.5)
        ctx.bezierCurveTo(33.5, 48.0, 56.5, 58.5, 56.5, 72.0)
        ctx.bezierCurveTo(56.5, 85.5, 33.5, 96.0, 33.5, 127.5)
        ctx.lineTo(86.5, 127.5)
        ctx.bezierCurveTo(86.5, 96.0, 63.5, 85.5, 63.5, 72.0)
        ctx.bezierCurveTo(63.5, 58.5, 86.5, 48.0, 86.5, 16.5)
        ctx.closePath()
        ctx.fill()

        // Upper chamber sand (clipped inside top bulb)
        if (p > 0.002) {
            ctx.save()
            ctx.beginPath()
            ctx.moveTo(35.2, 17.5)
            ctx.bezierCurveTo(35.2, 47.0, 57.6, 58.0, 57.6, 71.2)
            ctx.lineTo(62.4, 71.2)
            ctx.bezierCurveTo(62.4, 58.0, 84.8, 47.0, 84.8, 17.5)
            ctx.closePath()
            ctx.clip()

            const chamberHeight = 52.0
            const topY = 71.2 - Math.pow(p, 0.72) * chamberHeight
            const dipDepth = (1.0 - Math.pow(p, 1.35)) * 8.0 * Math.min(1.0, p * 5.0)
            ctx.fillStyle = root.rgba(root.sandColor, root.paused ? 0.8 : 0.96)
            ctx.beginPath()
            ctx.moveTo(30.0, topY)
            ctx.quadraticCurveTo(60.0, topY + dipDepth, 90.0, topY)
            ctx.lineTo(90.0, 74.0)
            ctx.lineTo(30.0, 74.0)
            ctx.closePath()
            ctx.fill()

            // Meniscus highlight
            ctx.strokeStyle = root.rgba(root.sandHighlightColor, 0.65)
            ctx.lineWidth = 1.6
            ctx.beginPath()
            ctx.moveTo(34.0, topY + 0.8)
            ctx.quadraticCurveTo(60.0, topY + dipDepth + 0.8, 86.0, topY + 0.8)
            ctx.stroke()

            ctx.restore()
        }

        // Lower chamber conical sand pile (clipped inside bottom bulb)
        const apexY = 127.0 - Math.pow(botFrac, 0.68) * 51.0
        if (botFrac > 0.002) {
            ctx.save()
            ctx.beginPath()
            ctx.moveTo(57.6, 72.8)
            ctx.bezierCurveTo(57.6, 86.0, 35.2, 97.0, 35.2, 127.0)
            ctx.lineTo(84.8, 127.0)
            ctx.bezierCurveTo(84.8, 97.0, 62.4, 86.0, 62.4, 72.8)
            ctx.closePath()
            ctx.clip()

            const skirtY = Math.min(127.2, apexY + 14.0 + botFrac * 9.0)
            ctx.fillStyle = root.rgba(root.sandColor, root.paused ? 0.8 : 0.96)
            ctx.beginPath()
            ctx.moveTo(31.0, skirtY)
            ctx.quadraticCurveTo(48.0, apexY + 1.0, 60.0, apexY)
            ctx.quadraticCurveTo(72.0, apexY + 1.0, 89.0, skirtY)
            ctx.lineTo(89.0, 129.0)
            ctx.lineTo(31.0, 129.0)
            ctx.closePath()
            ctx.fill()

            // Crisp sand slope highlight
            ctx.strokeStyle = root.rgba(root.sandHighlightColor, 0.52)
            ctx.lineWidth = 1.4
            ctx.beginPath()
            ctx.moveTo(36.0, Math.min(126.5, skirtY - 1.5))
            ctx.quadraticCurveTo(49.0, apexY + 1.2, 60.0, apexY + 0.6)
            ctx.quadraticCurveTo(71.0, apexY + 1.2, 84.0, Math.min(126.5, skirtY - 1.5))
            ctx.stroke()

            ctx.restore()
        }

        // Falling stream & shimmering sand droplets when running
        if (activeFlow) {
            const streamEndY = Math.max(76.0, Math.min(125.0, apexY + 1.0))
            const streamLen = Math.max(4.0, streamEndY - 72.0)

            ctx.strokeStyle = root.rgba(root.sandColor, 0.88)
            ctx.lineWidth = 1.9
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(60.0, 71.5)
            ctx.lineTo(60.0, streamEndY)
            ctx.stroke()

            ctx.fillStyle = root.rgba(root.sandHighlightColor, 0.95)
            for (let i = 0; i < 5; i++) {
                const t = (root.grainPhase + i * 0.2) % 1.0
                const gy = 72.5 + t * streamLen
                const jitter = ((i % 2 === 0 ? 1 : -1) * 0.55) * Math.sin(t * Math.PI)
                ctx.beginPath()
                ctx.arc(60.0 + jitter, gy, 1.05, 0, Math.PI * 2)
                ctx.fill()
            }
        }

        // Glass bulb outer rim
        ctx.strokeStyle = root.rgba(root.frameColor, 0.95)
        ctx.lineWidth = 2.4
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(33.5, 16.5)
        ctx.bezierCurveTo(33.5, 48.0, 56.5, 58.5, 56.5, 72.0)
        ctx.bezierCurveTo(56.5, 85.5, 33.5, 96.0, 33.5, 127.5)
        ctx.moveTo(86.5, 16.5)
        ctx.bezierCurveTo(86.5, 48.0, 63.5, 58.5, 63.5, 72.0)
        ctx.bezierCurveTo(63.5, 85.5, 86.5, 96.0, 86.5, 127.5)
        ctx.stroke()

        // Specular left-shoulder glass sheen
        ctx.strokeStyle = root.rgba(root.glassHighlightColor, 1.0)
        ctx.lineWidth = 1.8
        ctx.beginPath()
        ctx.moveTo(39.0, 22.0)
        ctx.bezierCurveTo(39.2, 43.0, 49.0, 53.0, 53.2, 62.5)
        ctx.moveTo(39.0, 122.0)
        ctx.bezierCurveTo(39.2, 102.0, 48.0, 92.5, 52.5, 82.0)
        ctx.stroke()

        // Turned side posts + rounded top & bottom caps
        ctx.strokeStyle = root.rgba(root.frameColor, 0.72)
        ctx.lineWidth = 2.4
        ctx.beginPath()
        ctx.moveTo(25.5, 16.5)
        ctx.lineTo(25.5, 127.5)
        ctx.moveTo(94.5, 16.5)
        ctx.lineTo(94.5, 127.5)
        ctx.stroke()

        ctx.fillStyle = root.rgba(root.frameColor, 1.0)
        root.roundedRectPath(ctx, 18.0, 9.5, 84.0, 7.0, 3.5)
        ctx.fill()
        root.roundedRectPath(ctx, 18.0, 127.5, 84.0, 7.0, 3.5)
        ctx.fill()
    }

    function _paintMatrix(ctx) {
        const p = root.clampedProgress
        const activeFlow = root.running && !root.paused && p > 0.002 && !root.overtime
        const topRows = [9, 7, 5, 3, 1]
        const botRows = [1, 3, 5, 7, 9]
        const totalHalf = 25
        const litTop = Math.round(p * totalHalf)
        const litBot = totalHalf - litTop

        const sandStr = root.rgba(root.sandColor, root.paused ? 0.78 : 1.0)
        const dimStr = root.rgba(root.emptyDotColor, 1.0)
        const frameStr = root.rgba(root.frameColor, 0.95)
        const dx = 8.4
        const dy = 9.8
        const r = 2.85

        // Minimal frame caps & tapered rail hints
        ctx.fillStyle = frameStr
        root.roundedRectPath(ctx, 21.0, 11.0, 78.0, 5.2, 2.6)
        ctx.fill()
        root.roundedRectPath(ctx, 21.0, 127.8, 78.0, 5.2, 2.6)
        ctx.fill()

        ctx.strokeStyle = root.rgba(root.frameColor, 0.28)
        ctx.lineWidth = 1.6
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(22.0, 21.0)
        ctx.lineTo(54.0, 68.5)
        ctx.lineTo(22.0, 123.0)
        ctx.moveTo(98.0, 21.0)
        ctx.lineTo(66.0, 68.5)
        ctx.lineTo(98.0, 123.0)
        ctx.stroke()

        // Upper inverted triangle drains from top row down toward waist
        let topIdx = 0
        for (let row = 0; row < topRows.length; row++) {
            const cols = topRows[row]
            const y = 25.0 + row * dy
            const startX = 60.0 - ((cols - 1) * dx) / 2.0
            for (let c = 0; c < cols; c++) {
                const x = startX + c * dx
                const active = (totalHalf - topIdx) <= litTop
                ctx.fillStyle = active ? sandStr : dimStr
                ctx.beginPath()
                ctx.arc(x, y, r, 0, Math.PI * 2)
                ctx.fill()
                topIdx++
            }
        }

        // Animated trickle grain across waist while active
        if (activeFlow) {
            const pulseAlpha = 0.45 + 0.55 * Math.abs(Math.sin(root.grainPhase * Math.PI))
            ctx.fillStyle = root.rgba(root.sandHighlightColor, pulseAlpha)
            ctx.beginPath()
            ctx.arc(60.0, 72.0 + (root.grainPhase - 0.5) * 4.5, 2.2, 0, Math.PI * 2)
            ctx.fill()
        }

        // Lower upright triangle builds from bottom row up to neck
        let botIdx = 0
        for (let row = 0; row < botRows.length; row++) {
            const cols = botRows[row]
            const y = 79.8 + row * dy
            const startX = 60.0 - ((cols - 1) * dx) / 2.0
            for (let c = 0; c < cols; c++) {
                const x = startX + c * dx
                const active = (totalHalf - botIdx) <= litBot
                ctx.fillStyle = active ? sandStr : dimStr
                ctx.beginPath()
                ctx.arc(x, y, r, 0, Math.PI * 2)
                ctx.fill()
                botIdx++
            }
        }
    }

    function _paintSquare(ctx) {
        const p = root.clampedProgress
        const activeFlow = root.running && !root.paused && p > 0.002 && !root.overtime
        const total = 100
        const lit = Math.round(p * total)

        const frameStr = root.rgba(root.frameColor, 0.95)
        const sandStr = root.rgba(root.sandColor, root.paused ? 0.78 : 1.0)
        const dimStr = root.rgba(root.emptyDotColor, 1.0)

        // Subtle glass backdrop + crisp rounded-square frame
        ctx.fillStyle = root.rgba(root.glassTintColor, 0.85)
        root.roundedRectPath(ctx, 13.0, 25.0, 94.0, 94.0, 14.0)
        ctx.fill()

        ctx.strokeStyle = frameStr
        ctx.lineWidth = 2.6
        root.roundedRectPath(ctx, 13.0, 25.0, 94.0, 94.0, 14.0)
        ctx.stroke()

        // 10 x 10 grid draining top-to-bottom
        const step = 7.7
        const startX = 60.0 - 4.5 * step
        const startY = 72.0 - 4.5 * step
        const r = 2.45

        for (let row = 0; row < 10; row++) {
            const y = startY + row * step
            for (let col = 0; col < 10; col++) {
                const x = startX + col * step
                const idx = row * 10 + col
                const orderFromBottom = total - idx
                const active = orderFromBottom <= lit
                const isFrontier = activeFlow && active && orderFromBottom === lit

                if (isFrontier) {
                    const pulse = 0.65 + 0.35 * Math.sin(root.grainPhase * Math.PI * 2.0)
                    ctx.fillStyle = root.rgba(root.sandHighlightColor, pulse)
                } else {
                    ctx.fillStyle = active ? sandStr : dimStr
                }

                ctx.beginPath()
                ctx.arc(x, y, isFrontier ? r * 1.16 : r, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }
}
