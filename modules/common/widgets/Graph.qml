import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property real lineWidth: 2
    property bool smooth: true
    property var alignment: Graph.Alignment.Left

    onValuesChanged: if (root.visible && root.available) root.requestPaint()
    onVisibleChanged: if (root.visible && root.available) root.requestPaint()
    onAvailableChanged: if (root.visible && root.available) root.requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return

        var n = root.points
        if (n < 2)
            return
        var dx = width / (n - 1)
        var firstIndex = root.alignment === Graph.Alignment.Right
            ? Math.max(0, n - root.values.length) : 0
        var endIndex = Math.min(n, firstIndex + root.values.length)
        var validCount = endIndex - firstIndex
        if (validCount < 2)
            return

        var rightAligned = root.alignment === Graph.Alignment.Right
        var firstValueIndex = rightAligned ? root.values.length - n + firstIndex : firstIndex
        var firstX = firstIndex * dx
        var firstY = height - root.values[firstValueIndex] * height
        var previousX = firstX
        var previousY = firstY
        var lastX = firstX

        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = root.lineWidth
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(firstX, height)
        ctx.lineTo(firstX, firstY)

        for (var i = firstIndex + 1; i < endIndex; ++i) {
            var currentX = i * dx
            var vi = rightAligned ? root.values.length - n + i : i
            var currentY = height - root.values[vi] * height
            if (root.smooth && validCount > 2) {
                var cpx = (previousX + currentX) / 2
                ctx.bezierCurveTo(cpx, previousY, cpx, currentY, currentX, currentY)
            } else {
                ctx.lineTo(currentX, currentY)
            }
            previousX = currentX
            previousY = currentY
            lastX = currentX
        }
        ctx.stroke()
        ctx.lineTo(lastX, height)
        ctx.fill()
    }
}
