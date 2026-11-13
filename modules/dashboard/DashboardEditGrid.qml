import QtQuick
import qs.modules.common
import qs.modules.common.functions

Canvas {
    id: root

    property int gridSize: 24
    property string gridStyle: "dots"
    property color accentColor: Appearance.colors.colPrimary
    property real gridOpacity: 0.16

    antialiasing: true

    onGridSizeChanged: requestPaint()
    onGridStyleChanged: requestPaint()
    onAccentColorChanged: requestPaint()
    onGridOpacityChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (width <= 0 || height <= 0 || gridSize <= 0)
            return

        const step = Math.max(8, gridSize)
        ctx.strokeStyle = accentColor
        ctx.fillStyle = accentColor
        ctx.globalAlpha = gridOpacity

        if (gridStyle === "lines") {
            ctx.lineWidth = 1
            ctx.beginPath()
            for (let x = 0.5; x <= width; x += step) {
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
            }
            for (let y = 0.5; y <= height; y += step) {
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
            }
            ctx.stroke()
        } else if (gridStyle === "cross") {
            ctx.lineWidth = 1
            const arm = Math.max(2, Math.min(4, step * 0.16))
            let ops = 0
            ctx.beginPath()
            for (let x = 0; x <= width; x += step) {
                for (let y = 0; y <= height; y += step) {
                    ctx.moveTo(x - arm, y)
                    ctx.lineTo(x + arm, y)
                    ctx.moveTo(x, y - arm)
                    ctx.lineTo(x, y + arm)
                    if (++ops >= 256) {
                        ctx.stroke()
                        ctx.beginPath()
                        ops = 0
                    }
                }
            }
            if (ops > 0)
                ctx.stroke()
        } else {
            const dotSize = Math.max(2, Math.min(4.2, step * 0.105))
            const halfDot = dotSize * 0.5
            let ops = 0
            ctx.beginPath()
            for (let x = 0; x <= width; x += step) {
                for (let y = 0; y <= height; y += step) {
                    ctx.rect(x - halfDot, y - halfDot, dotSize, dotSize)
                    if (++ops >= 512) {
                        ctx.fill()
                        ctx.beginPath()
                        ops = 0
                    }
                }
            }
            if (ops > 0)
                ctx.fill()
        }

        ctx.globalAlpha = 1
    }
}
