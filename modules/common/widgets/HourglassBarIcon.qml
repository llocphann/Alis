import QtQuick
import qs.modules.common

Item {
    id: root

    property string visualStyle: "turned"
    property real progress: 1.0
    property bool paused: false
    property bool overtime: false
    property color color: Appearance.colors.colOnLayer1
    property color trackColor: Qt.alpha(color, 0.28)
    property int iconSize: Math.round(Appearance.font.pixelSize.normal * Appearance.sizes.barModuleScale)

    readonly property int stepQuarter: root.overtime
        ? 0
        : Math.max(0, Math.min(4, root.progress <= 0.001 ? 0 : Math.ceil(root.progress * 4)))
    readonly property string normalizedStyle: {
        const s = String(root.visualStyle || "turned").toLowerCase()
        return (s === "matrix" || s === "square" || s === "turned") ? s : "turned"
    }

    implicitWidth: Math.max(12, root.iconSize)
    implicitHeight: Math.max(12, root.iconSize)

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

    onNormalizedStyleChanged: canvas.requestPaint()
    onStepQuarterChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onPausedChanged: canvas.requestPaint()
    onOvertimeChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

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

            const s = Math.min(w, h)
            const ox = (w - s) / 2
            const oy = (h - s) / 2
            const frac = root.stepQuarter / 4.0

            ctx.save()
            ctx.translate(ox, oy)
            ctx.scale(s / 18.0, s / 18.0)

            const strokeCol = root.rgba(root.color, 1.0)
            const dimCol = root.rgba(root.trackColor, 1.0)

            if (root.normalizedStyle === "matrix") {
                const rowsTop = [5, 3, 1]
                const topTotal = 9
                const litTop = Math.round(frac * topTotal)
                const litBottom = topTotal - litTop
                const r = 0.85

                ctx.fillStyle = strokeCol
                ctx.fillRect(3.2, 1.4, 11.6, 1.1)
                ctx.fillRect(3.2, 15.5, 11.6, 1.1)

                let idxTop = 0
                for (let row = 0; row < rowsTop.length; row++) {
                    const cols = rowsTop[row]
                    const y = 4.1 + row * 2.0
                    const startX = 9.0 - (cols - 1) * 1.15
                    for (let c = 0; c < cols; c++) {
                        const x = startX + c * 2.3
                        const active = (topTotal - idxTop) <= litTop
                        ctx.fillStyle = active ? strokeCol : dimCol
                        ctx.beginPath()
                        ctx.arc(x, y, r, 0, Math.PI * 2)
                        ctx.fill()
                        idxTop++
                    }
                }

                const rowsBot = [1, 3, 5]
                let idxBot = 0
                for (let row = 0; row < rowsBot.length; row++) {
                    const cols = rowsBot[row]
                    const y = 9.9 + row * 2.0
                    const startX = 9.0 - (cols - 1) * 1.15
                    for (let c = 0; c < cols; c++) {
                        const x = startX + c * 2.3
                        const active = (topTotal - idxBot) <= litBottom
                        ctx.fillStyle = active ? strokeCol : dimCol
                        ctx.beginPath()
                        ctx.arc(x, y, r, 0, Math.PI * 2)
                        ctx.fill()
                        idxBot++
                    }
                }
            } else if (root.normalizedStyle === "square") {
                ctx.strokeStyle = strokeCol
                ctx.lineWidth = 1.35
                ctx.lineJoin = "round"
                root.roundedRectPath(ctx, 2.2, 2.2, 13.6, 13.6, 2.2)
                ctx.stroke()

                const total = 16
                const lit = Math.round(frac * total)
                const dotR = 0.95
                for (let r = 0; r < 4; r++) {
                    const y = 4.75 + r * 2.83
                    for (let c = 0; c < 4; c++) {
                        const idx = r * 4 + c
                        const x = 4.75 + c * 2.83
                        const active = (total - idx) <= lit
                        ctx.fillStyle = active ? strokeCol : dimCol
                        ctx.beginPath()
                        ctx.arc(x, y, dotR, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            } else {
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                ctx.fillStyle = strokeCol
                ctx.fillRect(3.2, 1.5, 11.6, 1.35)
                ctx.fillRect(3.2, 15.15, 11.6, 1.35)

                if (frac > 0.01) {
                    const topY = 8.4 - frac * 5.0
                    const halfW = 1.0 + frac * 3.1
                    ctx.fillStyle = strokeCol
                    ctx.beginPath()
                    ctx.moveTo(9.0 - halfW, topY)
                    ctx.lineTo(9.0 + halfW, topY)
                    ctx.lineTo(9.45, 8.5)
                    ctx.lineTo(8.55, 8.5)
                    ctx.closePath()
                    ctx.fill()
                }

                const botFrac = 1.0 - frac
                if (botFrac > 0.01) {
                    const apexY = 14.5 - botFrac * 4.5
                    const halfW = 1.6 + botFrac * 2.9
                    ctx.fillStyle = strokeCol
                    ctx.beginPath()
                    ctx.moveTo(9.0, apexY)
                    ctx.lineTo(9.0 + halfW, 14.65)
                    ctx.lineTo(9.0 - halfW, 14.65)
                    ctx.closePath()
                    ctx.fill()
                }

                if (frac > 0.01 && frac < 0.99 && !root.paused) {
                    ctx.fillStyle = strokeCol
                    ctx.beginPath()
                    ctx.arc(9.0, 9.75, 0.75, 0, Math.PI * 2)
                    ctx.fill()
                }

                ctx.strokeStyle = strokeCol
                ctx.lineWidth = 1.35
                ctx.beginPath()
                ctx.moveTo(4.4, 2.85)
                ctx.bezierCurveTo(4.4, 6.4, 8.2, 7.9, 8.2, 9.0)
                ctx.bezierCurveTo(8.2, 10.1, 4.4, 11.6, 4.4, 15.15)
                ctx.moveTo(13.6, 2.85)
                ctx.bezierCurveTo(13.6, 6.4, 9.8, 7.9, 9.8, 9.0)
                ctx.bezierCurveTo(9.8, 10.1, 13.6, 11.6, 13.6, 15.15)
                ctx.stroke()
            }

            ctx.restore()
        }
    }
}
