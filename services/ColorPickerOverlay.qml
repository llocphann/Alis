pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    objectName: "alisColorPickerOverlay-" + (screen?.name ?? "")
    required property int requestId
    signal picked(int requestId, string value)
    signal cancelled(int requestId)
    signal failed(int requestId, string message)
    visible: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "alis:colorpicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property var capturedFrame: null
    property string sampledColor: ""
    property bool captureRequested: false
    property int currentPixelX: -1
    property int currentPixelY: -1
    property real cursorX: width * 0.5
    property real cursorY: height * 0.5
    property bool keyboardMoved: false
    readonly property bool ready: sampler.ready

    function capture(): void {
        if (!screenCopy.hasContent || captureRequested)
            return
        captureRequested = true
        if (!screenCopy.grabToImage(result => {
            root.capturedFrame = result
        }))
            failed(requestId, "Could not read the captured screen")
    }

    ScreencopyView {
        id: screenCopy
        anchors.fill: parent
        captureSource: root.screen
        live: false
        paintCursor: false
        // The window stays fully transparent until its first frozen frame exists.
        // Decorations are shown only after this frame has been sampled.
        onHasContentChanged: if (hasContent) Qt.callLater(root.capture)
        onStopped: if (!root.ready) root.failed(root.requestId, "Screen capture is unavailable")
    }

    ColorPickerSampler { id: sampler }
    Image {
        source: root.capturedFrame?.url ?? ""
        visible: false
        onStatusChanged: if (status === Image.Ready) {
            // grabToImage sizes are in logical pixels; the returned image has
            // the window's DPR. Read its real dimensions instead of multiplying
            // the screencopy frame a second time on scaled outputs.
            sampler.imageSize = sourceSize
            sampler.imageUrl = source
        }
    }

    Timer {
        interval: 5000
        running: !root.ready
        onTriggered: root.failed(root.requestId, "Screen capture timed out")
    }

    Item {
        anchors.fill: parent
        focus: true
        function stepPixel(dx: int, dy: int): void {
            if (!root.ready || sampler.imageSize.width <= 0 || sampler.imageSize.height <= 0
                    || root.width <= 0 || root.height <= 0)
                return
            if (root.currentPixelX < 0 || root.currentPixelY < 0) {
                const baseX = pointer.containsMouse ? pointer.mouseX : root.width * 0.5
                const baseY = pointer.containsMouse ? pointer.mouseY : root.height * 0.5
                const init = sampler.pixelAt(baseX, baseY, root.width, root.height)
                root.currentPixelX = init.x
                root.currentPixelY = init.y
            }
            const nx = Math.max(0, Math.min(sampler.imageSize.width - 1, root.currentPixelX + dx))
            const ny = Math.max(0, Math.min(sampler.imageSize.height - 1, root.currentPixelY + dy))
            root.currentPixelX = nx
            root.currentPixelY = ny
            root.cursorX = ((nx + 0.5) / sampler.imageSize.width) * root.width
            root.cursorY = ((ny + 0.5) / sampler.imageSize.height) * root.height
            root.keyboardMoved = true
            root.sampledColor = sampler.colorAt(nx, ny)
            magnifier.requestPaint()
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.cancelled(root.requestId)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (root.sampledColor)
                    root.picked(root.requestId, root.sampledColor)
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                    || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
                const dx = event.key === Qt.Key_Left ? -step : (event.key === Qt.Key_Right ? step : 0)
                const dy = event.key === Qt.Key_Up ? -step : (event.key === Qt.Key_Down ? step : 0)
                stepPixel(dx, dy)
                event.accepted = true
            }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property real lastMouseX: -1
            property real lastMouseY: -1
            function updateSample(): void {
                if (!root.ready || width <= 0 || height <= 0
                        || sampler.imageSize.width <= 0 || sampler.imageSize.height <= 0)
                    return
                const p = sampler.pixelAt(mouseX, mouseY, width, height)
                root.currentPixelX = p.x
                root.currentPixelY = p.y
                root.cursorX = mouseX
                root.cursorY = mouseY
                root.keyboardMoved = false
                lastMouseX = mouseX
                lastMouseY = mouseY
                root.sampledColor = sampler.colorAt(p.x, p.y)
                magnifier.requestPaint()
            }
            onPositionChanged: if (root.ready) updateSample()
            onClicked: event => {
                if (event.button === Qt.RightButton) root.cancelled(root.requestId)
                else if (root.ready) {
                    if (!root.keyboardMoved
                            || Math.abs(event.x - lastMouseX) >= 0.5
                            || Math.abs(event.y - lastMouseY) >= 0.5) {
                        updateSample()
                    }
                    if (root.sampledColor) root.picked(root.requestId, root.sampledColor)
                }
            }
            Connections {
                target: root
                function onReadyChanged() { if (root.ready) pointer.updateSample() }
            }
        }

        Rectangle {
            id: pixelReticle
            visible: root.ready && root.keyboardMoved
            width: 11
            height: 11
            radius: 5.5
            x: root.cursorX - width * 0.5
            y: root.cursorY - height * 0.5
            color: "transparent"
            border.width: 2
            border.color: "#FFFFFF"
            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 3.5
                color: "transparent"
                border.width: 1
                border.color: "#000000"
            }
        }

        Rectangle {
            visible: root.ready && (pointer.containsMouse || root.keyboardMoved)
            x: Math.max(0, Math.min(parent.width - width,
                root.cursorX + (root.cursorX + width + 24 < parent.width ? 24 : -width - 24)))
            y: Math.max(0, Math.min(parent.height - height, root.cursorY + 24))
            width: 166
            height: 196
            color: "#1D2028"
            border.color: "#D6DAE4"
            radius: 8
            Canvas {
                id: magnifier
                x: 11; y: 11; width: 143; height: 143
                onPaint: {
                    if (!sampler.ready) return
                    const ctx = getContext("2d")
                    const p = (root.currentPixelX >= 0 && root.currentPixelY >= 0)
                        ? Qt.point(root.currentPixelX, root.currentPixelY)
                        : sampler.pixelAt(root.cursorX, root.cursorY, root.width, root.height)
                    ctx.clearRect(0, 0, width, height)
                    // Draw discrete blocks so magnification cannot interpolate a color.
                    for (let yy = -5; yy <= 5; ++yy)
                        for (let xx = -5; xx <= 5; ++xx) {
                            const sx = Math.max(0, Math.min(sampler.imageSize.width - 1, p.x + xx))
                            const sy = Math.max(0, Math.min(sampler.imageSize.height - 1, p.y + yy))
                            // drawImage applies the source image's DPR again on
                            // some Qt versions. Fill a block with the original
                            // pixel color so fractional/2x outputs have no gaps.
                            ctx.fillStyle = sampler.colorAt(sx, sy) || "transparent"
                            ctx.fillRect((xx + 5) * 13, (yy + 5) * 13, 13, 13)
                        }
                    ctx.strokeStyle = "#000000"
                    ctx.lineWidth = 3
                    ctx.strokeRect(65, 65, 13, 13)
                    ctx.strokeStyle = "#FFFFFF"
                    ctx.lineWidth = 1
                    ctx.strokeRect(65, 65, 13, 13)
                }
            }
            Rectangle { x: 11; y: 165; width: 18; height: 18; color: root.sampledColor || "transparent"; border.color: "white" }
            Text { x: 38; y: 164; text: root.sampledColor; color: "white"; font.pixelSize: 16; font.family: "monospace" }
        }
    }
}
