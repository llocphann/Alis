pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    objectName: "alisColorPickerOverlay-" + (screen?.name ?? "")
    required property int requestId
    property var themePalette: ({})
    signal picked(int requestId, string value, string formatted)
    signal cancelled(int requestId)
    signal failed(int requestId, string message)
    signal overlayActivated(string screenName)
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
    property bool isActiveOverlay: true
    property bool loupeLocked: false
    onIsActiveOverlayChanged: {
        if (!isActiveOverlay) {
            loupeLocked = false
            keyboardMoved = false
        }
    }
    readonly property bool ready: sampler.ready

    // Interactive studio controls (transcends hyprpicker)
    readonly property var formatOrder: ["HEX", "RGB", "HSL", "OKLCH", "HSV"]
    property int formatIndex: 0
    readonly property string activeFormat: root.formatOrder[root.formatIndex] ?? "HEX"
    readonly property var zoomRadii: [2, 3, 4, 5, 7, 9]
    property int zoomStepIndex: 3 // default radius 5 => 11x11 grid
    readonly property int gridRadius: root.zoomRadii[root.zoomStepIndex] ?? 5
    readonly property int gridCount: root.gridRadius * 2 + 1
    property int sampleBoxSize: 1 // 1, 3, or 5
    property bool showPixelGrid: true

    // Auto-themed Alis tokens passed from ColorPickerService (zero hardcoded dark box)
    readonly property bool isDark: root.themePalette?.darkmode !== undefined
        ? Boolean(root.themePalette.darkmode) : true
    readonly property color colLayer0: root.themePalette?.colLayer0 ?? (root.isDark ? "#14161b" : "#f4f6fa")
    readonly property color colLayer1: root.themePalette?.colLayer1 ?? (root.isDark ? "#1c1f26" : "#eaeef5")
    readonly property color colLayer2: root.themePalette?.colLayer2 ?? (root.isDark ? "#242832" : "#dfe5f0")
    readonly property color colPrimary: root.themePalette?.colPrimary ?? "#89b4fa"
    readonly property color colOnPrimary: root.themePalette?.colOnPrimary ?? (root.isDark ? "#0d1117" : "#ffffff")
    readonly property color colSecondary: root.themePalette?.colSecondary ?? "#94e2d5"
    readonly property color colOnLayer0: root.themePalette?.colOnLayer0 ?? (root.isDark ? "#e6eaf2" : "#181b22")
    readonly property color colSubtext: root.themePalette?.colSubtext ?? (root.isDark ? "#9ea6b8" : "#556070")
    readonly property color colOutline: root.themePalette?.colOutline ?? (root.isDark ? "#333947" : "#c6cfde")
    readonly property var recentColors: Array.isArray(root.themePalette?.recentColors) ? root.themePalette.recentColors : []

    // ─── Color Space Math (RGB / HSL / HSV / OKLCH / WCAG / Harmonies) ───
    function _parseHex(hex: string): var {
        if (!/^#[0-9A-Fa-f]{6}$/.test(hex)) return null
        return {
            r: parseInt(hex.slice(1, 3), 16),
            g: parseInt(hex.slice(3, 5), 16),
            b: parseInt(hex.slice(5, 7), 16)
        }
    }

    function _rgbToHex(r: real, g: real, b: real): string {
        const cr = Math.max(0, Math.min(255, Math.round(r)))
        const cg = Math.max(0, Math.min(255, Math.round(g)))
        const cb = Math.max(0, Math.min(255, Math.round(b)))
        return "#" + [cr, cg, cb].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase()
    }

    function _rgbToHsl(r: int, g: int, b: int): var {
        const rn = r / 255, gn = g / 255, bn = b / 255
        const max = Math.max(rn, gn, bn), min = Math.min(rn, gn, bn)
        const d = max - min
        let h = 0
        const l = (max + min) * 0.5
        const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1))
        if (d !== 0) {
            if (max === rn) h = ((gn - bn) / d) % 6
            else if (max === gn) h = (bn - rn) / d + 2
            else h = (rn - gn) / d + 4
            h *= 60
            if (h < 0) h += 360
        }
        return { h: h, s: s * 100, l: l * 100 }
    }

    function _hslToHex(h: real, s: real, l: real): string {
        const hn = ((h % 360) + 360) % 360
        const sn = Math.max(0, Math.min(100, s)) / 100
        const ln = Math.max(0, Math.min(100, l)) / 100
        const c = (1 - Math.abs(2 * ln - 1)) * sn
        const x = c * (1 - Math.abs((hn / 60) % 2 - 1))
        const m = ln - c * 0.5
        let r = 0, g = 0, b = 0
        if (hn < 60) { r = c; g = x; b = 0 }
        else if (hn < 120) { r = x; g = c; b = 0 }
        else if (hn < 180) { r = 0; g = c; b = x }
        else if (hn < 240) { r = 0; g = x; b = c }
        else if (hn < 300) { r = x; g = 0; b = c }
        else { r = c; g = 0; b = x }
        return root._rgbToHex((r + m) * 255, (g + m) * 255, (b + m) * 255)
    }

    function _rgbToHsv(r: int, g: int, b: int): var {
        const rn = r / 255, gn = g / 255, bn = b / 255
        const max = Math.max(rn, gn, bn), min = Math.min(rn, gn, bn)
        const d = max - min
        let h = 0
        if (d !== 0) {
            if (max === rn) h = ((gn - bn) / d) % 6
            else if (max === gn) h = (bn - rn) / d + 2
            else h = (rn - gn) / d + 4
            h *= 60
            if (h < 0) h += 360
        }
        const s = max === 0 ? 0 : (d / max) * 100
        return { h: h, s: s, v: max * 100 }
    }

    function _srgbToLinear(c: real): real {
        const v = c / 255
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    }

    function _rgbToOklch(r: int, g: int, b: int): var {
        const lr = root._srgbToLinear(r)
        const lg = root._srgbToLinear(g)
        const lb = root._srgbToLinear(b)
        const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        const a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        const bk = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        const C = Math.sqrt(a * a + bk * bk)
        let H = Math.atan2(bk, a) * (180 / Math.PI)
        if (H < 0) H += 360
        return { l: Math.max(0, Math.min(1, L)), c: C, h: H }
    }

    function formatColor(hex: string, fmt: string): string {
        const rgb = root._parseHex(hex)
        if (!rgb) return ""
        if (fmt === "RGB")
            return `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`
        if (fmt === "HSL") {
            const hsl = root._rgbToHsl(rgb.r, rgb.g, rgb.b)
            return `hsl(${Math.round(hsl.h)}, ${Math.round(hsl.s)}%, ${Math.round(hsl.l)}%)`
        }
        if (fmt === "OKLCH") {
            const ok = root._rgbToOklch(rgb.r, rgb.g, rgb.b)
            return `oklch(${(ok.l * 100).toFixed(1)}% ${ok.c.toFixed(3)} ${Math.round(ok.h)})`
        }
        if (fmt === "HSV") {
            const hsv = root._rgbToHsv(rgb.r, rgb.g, rgb.b)
            return `hsv(${Math.round(hsv.h)}, ${Math.round(hsv.s)}%, ${Math.round(hsv.v)}%)`
        }
        return hex.toUpperCase()
    }

    readonly property string formattedColor: root.formatColor(root.sampledColor, root.activeFormat)

    readonly property real relativeLuminance: {
        const rgb = root._parseHex(root.sampledColor)
        if (!rgb) return 0
        return 0.2126 * root._srgbToLinear(rgb.r)
            + 0.7152 * root._srgbToLinear(rgb.g)
            + 0.0722 * root._srgbToLinear(rgb.b)
    }
    readonly property real contrastOnWhite: (1.0 + 0.05) / (root.relativeLuminance + 0.05)
    readonly property real contrastOnBlack: (root.relativeLuminance + 0.05) / 0.05

    readonly property var harmonySwatches: {
        const rgb = root._parseHex(root.sampledColor)
        if (!rgb) return []
        const hsl = root._rgbToHsl(rgb.r, rgb.g, rgb.b)
        return [
            { key: "1", label: "Comp", hex: root._hslToHex(hsl.h + 180, hsl.s, hsl.l) },
            { key: "2", label: "Ana-", hex: root._hslToHex(hsl.h - 30, hsl.s, hsl.l) },
            { key: "3", label: "Ana+", hex: root._hslToHex(hsl.h + 30, hsl.s, hsl.l) },
            { key: "4", label: "Tint", hex: root._hslToHex(hsl.h, Math.min(100, hsl.s * 0.92), Math.min(94, hsl.l + 20)) },
            { key: "5", label: "Shade", hex: root._hslToHex(hsl.h, Math.min(100, hsl.s * 1.05), Math.max(8, hsl.l - 20)) }
        ]
    }

    readonly property var recallableRecents: {
        const keys = ["6", "7", "8", "9", "0"]
        const out = []
        const src = Array.isArray(root.recentColors) ? root.recentColors : []
        for (let i = 0; i < src.length && out.length < keys.length; ++i) {
            const hex = String(src[i] ?? "").trim().toUpperCase()
            if (/^#[0-9A-F]{6}$/.test(hex))
                out.push({ key: keys[out.length], hex: hex })
        }
        return out
    }

    function _swatchInkColor(hex: string): color {
        const rgb = root._parseHex(hex)
        if (!rgb) return "#FFFFFF"
        const lum = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        return lum > 145 ? "#101318" : "#FFFFFF"
    }

    function _commitPick(hex: string): void {
        if (!/^#[0-9A-Fa-f]{6}$/.test(hex)) return
        const upper = hex.toUpperCase()
        const fmt = root.activeFormat === "HEX" ? "" : root.formatColor(upper, root.activeFormat)
        root.picked(root.requestId, upper, fmt)
    }

    function _sampleAtPixel(px: int, py: int): string {
        return root.sampleBoxSize > 1
            ? sampler.averageColorAt(px, py, root.sampleBoxSize)
            : sampler.colorAt(px, py)
    }

    function _adjustZoom(delta: int): void {
        // delta > 0 = zoom IN (smaller radius / bigger pixels)
        const next = Math.max(0, Math.min(root.zoomRadii.length - 1, root.zoomStepIndex - delta))
        if (next !== root.zoomStepIndex) {
            root.zoomStepIndex = next
            magnifier.requestPaint()
        }
    }

    function _cycleFormat(): void {
        root.formatIndex = (root.formatIndex + 1) % root.formatOrder.length
    }

    function _cycleSampleBox(): void {
        root.sampleBoxSize = root.sampleBoxSize === 1 ? 3 : (root.sampleBoxSize === 3 ? 5 : 1)
        if (root.ready && root.currentPixelX >= 0 && root.currentPixelY >= 0) {
            root.sampledColor = root._sampleAtPixel(root.currentPixelX, root.currentPixelY)
            magnifier.requestPaint()
        }
    }

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
        id: overlayRoot
        x: 0
        y: 0
        width: root.width
        height: root.height
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
            root.overlayActivated(root.screen?.name ?? "")
            root.sampledColor = root._sampleAtPixel(nx, ny)
            magnifier.requestPaint()
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (root.loupeLocked) {
                    root.loupeLocked = false
                } else {
                    root.cancelled(root.requestId)
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (root.sampledColor)
                    root._commitPick(root.sampledColor)
                event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_F) {
                root._cycleFormat()
                event.accepted = true
            } else if (event.key === Qt.Key_A) {
                root._cycleSampleBox()
                event.accepted = true
            } else if (event.key === Qt.Key_G) {
                root.showPixelGrid = !root.showPixelGrid
                magnifier.requestPaint()
                event.accepted = true
            } else if (event.key === Qt.Key_L) {
                root.loupeLocked = !root.loupeLocked
                root.overlayActivated(root.screen?.name ?? "")
                event.accepted = true
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                root._adjustZoom(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Minus) {
                root._adjustZoom(-1)
                event.accepted = true
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                const idx = event.key - Qt.Key_1
                if (idx >= 0 && idx < root.harmonySwatches.length)
                    root._commitPick(root.harmonySwatches[idx].hex)
                event.accepted = true
            } else if ((event.key >= Qt.Key_6 && event.key <= Qt.Key_9) || event.key === Qt.Key_0) {
                const rIdx = event.key === Qt.Key_0 ? 4 : (event.key - Qt.Key_6)
                if (rIdx >= 0 && rIdx < root.recallableRecents.length)
                    root._commitPick(root.recallableRecents[rIdx].hex)
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
            cursorShape: root.loupeLocked ? Qt.ArrowCursor : Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property real lastMouseX: -1
            property real lastMouseY: -1
            function sampleAtCoords(sx: real, sy: real, fromMouse: bool): void {
                if (!root.ready || width <= 0 || height <= 0
                        || sampler.imageSize.width <= 0 || sampler.imageSize.height <= 0)
                    return
                const cx = Math.max(0, Math.min(width - 1, sx))
                const cy = Math.max(0, Math.min(height - 1, sy))
                const p = sampler.pixelAt(cx, cy, width, height)
                root.currentPixelX = p.x
                root.currentPixelY = p.y
                root.cursorX = cx
                root.cursorY = cy
                if (fromMouse) {
                    root.keyboardMoved = false
                    lastMouseX = cx
                    lastMouseY = cy
                    root.overlayActivated(root.screen?.name ?? "")
                }
                root.sampledColor = root._sampleAtPixel(p.x, p.y)
                magnifier.requestPaint()
            }
            function updateSample(): void {
                sampleAtCoords(mouseX, mouseY, true)
            }
            function initializeSample(): void {
                if (!root.ready) return
                if (containsMouse) {
                    updateSample()
                } else {
                    sampleAtCoords(width * 0.5, height * 0.5, false)
                }
            }
            onContainsMouseChanged: {
                if (containsMouse && root.ready && !root.loupeLocked)
                    updateSample()
            }
            onPositionChanged: {
                if (!root.ready || root.loupeLocked) return
                updateSample()
            }
            onWheel: wheel => {
                if (wheel.angleDelta.y > 0) root._adjustZoom(1)
                else if (wheel.angleDelta.y < 0) root._adjustZoom(-1)
                wheel.accepted = true
            }
            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    if (!root.ready) return
                    if (root.loupeLocked) {
                        root.loupeLocked = false
                    } else {
                        if (!root.keyboardMoved
                                || Math.abs(event.x - lastMouseX) >= 0.5
                                || Math.abs(event.y - lastMouseY) >= 0.5) {
                            sampleAtCoords(event.x, event.y, true)
                        }
                        root.loupeLocked = true
                        root.overlayActivated(root.screen?.name ?? "")
                    }
                } else if (root.ready) {
                    if (root.loupeLocked) {
                        root.loupeLocked = false
                        sampleAtCoords(event.x, event.y, true)
                        return
                    }
                    if (!root.keyboardMoved
                            || Math.abs(event.x - lastMouseX) >= 0.5
                            || Math.abs(event.y - lastMouseY) >= 0.5) {
                        updateSample()
                    }
                    if (root.sampledColor) root._commitPick(root.sampledColor)
                }
            }
            onWidthChanged: if (root.ready && root.currentPixelX < 0 && width > 0 && height > 0) initializeSample()
            onHeightChanged: if (root.ready && root.currentPixelX < 0 && width > 0 && height > 0) initializeSample()
            Connections {
                target: root
                function onReadyChanged() {
                    if (root.ready) {
                        pointer.initializeSample()
                        Qt.callLater(() => {
                            if (root.ready && root.currentPixelX < 0)
                                pointer.initializeSample()
                        })
                    }
                }
            }
        }

        // Precision cursor reticle when stepping via keyboard, locked, or awaiting initial mouse motion
        Rectangle {
            id: pixelReticle
            visible: root.ready && root.isActiveOverlay && (root.keyboardMoved || root.loupeLocked || !pointer.containsMouse)
            width: 13
            height: 13
            radius: 6.5
            x: root.cursorX - width * 0.5
            y: root.cursorY - height * 0.5
            color: "transparent"
            border.width: 2
            border.color: root.colPrimary
            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 3.5
                color: "transparent"
                border.width: 1
                border.color: "#FFFFFF"
            }
        }

        // ─── Compact Circular Auto-Themed Color Loupe + Right-Click Locked Studio Deck ───
        Item {
            id: loupeCluster
            objectName: "colorPickerCircularPopup"
            visible: root.ready && root.isActiveOverlay

            readonly property real circleDiameter: 176
            readonly property real deckWidth: 196
            readonly property real deckHeight: root.recallableRecents.length > 0 ? 74 : 54
            readonly property real gapBetween: 6
            readonly property real activeDeckExtent: root.loupeLocked ? (deckHeight + gapBetween) : 0
            readonly property real clusterWidth: root.loupeLocked ? Math.max(circleDiameter, deckWidth) : circleDiameter
            readonly property bool flipLeft: root.cursorX + clusterWidth + 20 > overlayRoot.width
            readonly property bool flipAbove: root.cursorY + circleDiameter + activeDeckExtent + 20 > overlayRoot.height

            width: clusterWidth
            height: circleDiameter + activeDeckExtent
            x: Math.max(10, Math.min(overlayRoot.width - width - 10,
                flipLeft ? (root.cursorX - width - 16) : (root.cursorX + 16)))
            y: Math.max(10, Math.min(overlayRoot.height - height - 10,
                flipAbove ? (root.cursorY - height - 12) : (root.cursorY + 12)))

            // Main Circular Loupe Body
            Rectangle {
                id: circularLoupe
                objectName: "colorPickerCircularLoupe"
                width: loupeCluster.circleDiameter
                height: loupeCluster.circleDiameter
                x: Math.round((loupeCluster.width - width) * 0.5)
                y: (root.loupeLocked && loupeCluster.flipAbove) ? (loupeCluster.deckHeight + loupeCluster.gapBetween) : 0
                radius: width * 0.5
                color: root.colLayer0
                border.width: 3
                border.color: root.sampledColor || root.colPrimary

                // Absorb left-clicks while locked; right-click anywhere on the loupe exits Lock & closes popup
                MouseArea {
                    anchors.fill: parent
                    enabled: root.loupeLocked
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton)
                            root.loupeLocked = false
                    }
                }

                // Inner Alis theme hairline ring separating the live color halo from the shell
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width * 0.5
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(root.colOutline, 0.72)
                }

                // Top bezel status strip: Zoom · Aperture · Lock (strictly within inner top chord)
                Row {
                    id: topBezelRow
                    anchors.top: parent.top
                    anchors.topMargin: 13
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Rectangle {
                        height: 14
                        width: zoomBadgeText.implicitWidth + 7
                        radius: 7
                        color: root.colLayer1
                        Text {
                            id: zoomBadgeText
                            anchors.centerIn: parent
                            text: `${root.gridCount}×`
                            color: root.colPrimary
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            font.family: "monospace"
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.loupeLocked
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: event => {
                                if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                                root._adjustZoom(1)
                            }
                        }
                    }

                    Rectangle {
                        height: 14
                        width: avgBadgeText.implicitWidth + 7
                        radius: 7
                        color: root.sampleBoxSize > 1 ? root.colPrimary : root.colLayer1
                        Text {
                            id: avgBadgeText
                            anchors.centerIn: parent
                            text: root.sampleBoxSize === 1 ? "1px" : `${root.sampleBoxSize}×${root.sampleBoxSize}`
                            color: root.sampleBoxSize > 1 ? root.colOnPrimary : root.colSubtext
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                            font.family: "monospace"
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.loupeLocked
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: event => {
                                if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                                root._cycleSampleBox()
                            }
                        }
                    }

                    Rectangle {
                        visible: root.loupeLocked
                        height: 14
                        width: lockBadgeText.implicitWidth + 6
                        radius: 7
                        color: root.colSecondary
                        Text {
                            id: lockBadgeText
                            anchors.centerIn: parent
                            text: "LOCK"
                            color: root.colOnPrimary
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            font.family: "monospace"
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.loupeLocked
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.loupeLocked = false
                        }
                    }
                }

                // Circularly Masked Magnifier Lens (100x100 Canvas with native 2D circular clip — crisp on both GPU & software)
                Item {
                    id: lensMaskContainer
                    width: 100
                    height: 100
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -2

                    Canvas {
                        id: magnifier
                        objectName: "colorPickerMagnifierCanvas"
                        width: 100
                        height: 100
                        antialiasing: true
                        onPaint: {
                            if (!sampler.ready) return
                            const ctx = getContext("2d")
                            const p = (root.currentPixelX >= 0 && root.currentPixelY >= 0)
                                ? Qt.point(root.currentPixelX, root.currentPixelY)
                                : sampler.pixelAt(root.cursorX, root.cursorY, root.width, root.height)
                            const r = root.gridRadius
                            const count = r * 2 + 1
                            const cell = width / count
                            const region = sampler.readRegion(p.x, p.y, r)
                            ctx.clearRect(0, 0, width, height)
                            ctx.save()
                            ctx.beginPath()
                            ctx.arc(width * 0.5, height * 0.5, width * 0.5 - 1, 0, Math.PI * 2)
                            ctx.clip()
                            if (region) {
                                for (let yy = -r; yy <= r; ++yy) {
                                    const py0 = Math.floor((yy + r) * cell)
                                    const py1 = Math.floor((yy + r + 1) * cell)
                                    const ch = Math.max(1, py1 - py0)
                                    for (let xx = -r; xx <= r; ++xx) {
                                        const px0 = Math.floor((xx + r) * cell)
                                        const px1 = Math.floor((xx + r + 1) * cell)
                                        const cw = Math.max(1, px1 - px0)
                                        const rgb = sampler.regionPixelRgb(region, p.x + xx, p.y + yy)
                                        ctx.fillStyle = rgb
                                            ? `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`
                                            : "transparent"
                                        ctx.fillRect(px0, py0, cw, ch)
                                    }
                                }
                            }
                            if (root.showPixelGrid && cell >= 8) {
                                ctx.strokeStyle = root.isDark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.10)"
                                ctx.lineWidth = 1
                                ctx.beginPath()
                                for (let i = 1; i < count; ++i) {
                                    const pos = Math.floor(i * cell) + 0.5
                                    ctx.moveTo(pos, 0); ctx.lineTo(pos, height)
                                    ctx.moveTo(0, pos); ctx.lineTo(width, pos)
                                }
                                ctx.stroke()
                            }
                            // Center sample box outline (1x1, 3x3, or 5x5)
                            const halfBox = Math.floor(root.sampleBoxSize / 2)
                            const boxStart = Math.floor((r - halfBox) * cell)
                            const boxEnd = Math.floor((r + halfBox + 1) * cell)
                            const boxW = Math.max(4, boxEnd - boxStart)
                            ctx.strokeStyle = "#000000"
                            ctx.lineWidth = 3
                            ctx.strokeRect(boxStart, boxStart, boxW, boxW)
                            ctx.strokeStyle = "#FFFFFF"
                            ctx.lineWidth = 1.25
                            ctx.strokeRect(boxStart, boxStart, boxW, boxW)
                            ctx.restore()
                        }
                    }

                    // Crisp circular lens rim
                    Rectangle {
                        anchors.fill: parent
                        radius: width * 0.5
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(root.colPrimary, 0.85)
                    }
                }

                // Bottom bezel readout pill: swatch + compact HEX (stays 100% inside inner circle chord with zero clipping)
                Rectangle {
                    id: loupeReadoutPill
                    objectName: "colorPickerLoupeReadoutPill"
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 15
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 18
                    width: Math.min(76, readoutRow.implicitWidth + 10)
                    radius: 9
                    color: root.colLayer1
                    border.width: 1
                    border.color: Qt.alpha(root.colOutline, 0.7)

                    Row {
                        id: readoutRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: root.sampledColor || "transparent"
                            border.width: 1
                            border.color: Qt.alpha(root.colOnLayer0, 0.6)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sampledColor || "#000000"
                            color: root.colOnLayer0
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.family: "monospace"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.loupeLocked
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: event => {
                            if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                            if (root.sampledColor) root._commitPick(root.sampledColor)
                        }
                    }
                }
            }

            // ─── Compact Right-Click Locked Studio Deck (Full Readout · WCAG · Harmonies · Recent Recall) ───
            Rectangle {
                id: studioDeck
                objectName: "colorPickerStudioDeck"
                visible: root.loupeLocked
                width: loupeCluster.deckWidth
                height: loupeCluster.deckHeight
                x: Math.round((loupeCluster.width - width) * 0.5)
                y: loupeCluster.flipAbove ? 0 : (loupeCluster.circleDiameter + loupeCluster.gapBetween)
                radius: 14
                color: root.colLayer0
                border.width: 1
                border.color: root.colPrimary

                // Absorb left-clicks while locked; right-click exits Lock & closes popup
                MouseArea {
                    anchors.fill: parent
                    enabled: root.loupeLocked
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton)
                            root.loupeLocked = false
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 4

                    // Row 1: Format badge + full formatted value (click to cycle format) + pixel coordinates
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            height: 18
                            implicitWidth: deckFmtText.implicitWidth + 8
                            radius: 9
                            color: root.colPrimary
                            Text {
                                id: deckFmtText
                                anchors.centerIn: parent
                                text: root.activeFormat
                                color: root.colOnPrimary
                                font.pixelSize: 8
                                font.weight: Font.Bold
                                font.family: "monospace"
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: root.loupeLocked
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: event => {
                                    if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                                    root._cycleFormat()
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            height: 18
                            radius: 9
                            color: root.colLayer1

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 5
                                anchors.rightMargin: 5
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: root.formattedColor || root.sampledColor
                                color: root.colOnLayer0
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.loupeLocked
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: event => {
                                    if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                                    root._cycleFormat()
                                }
                            }
                        }

                        Text {
                            id: coordText
                            Layout.alignment: Qt.AlignVCenter
                            text: root.currentPixelX >= 0 ? `${root.currentPixelX},${root.currentPixelY}` : ""
                            color: root.colSubtext
                            font.pixelSize: 8
                            font.family: "monospace"
                        }
                    }

                    // Row 2: WCAG contrast badges + 5 live harmony swatches (click or keys 1-5)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Rectangle {
                            height: 17
                            implicitWidth: wcagWText.implicitWidth + 6
                            radius: 8.5
                            color: root.colLayer2
                            Text {
                                id: wcagWText
                                anchors.centerIn: parent
                                text: `W${root.contrastOnWhite.toFixed(1)}`
                                color: root.contrastOnWhite >= 4.5 ? root.colPrimary : root.colSubtext
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.family: "monospace"
                            }
                        }

                        Rectangle {
                            height: 17
                            implicitWidth: wcagBText.implicitWidth + 6
                            radius: 8.5
                            color: root.colLayer2
                            Text {
                                id: wcagBText
                                anchors.centerIn: parent
                                text: `B${root.contrastOnBlack.toFixed(1)}`
                                color: root.contrastOnBlack >= 4.5 ? root.colSecondary : root.colSubtext
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.family: "monospace"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 3
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: root.harmonySwatches
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 18
                                    height: 17
                                    radius: 5
                                    color: modelData.hex
                                    border.width: harmonyMouse.containsMouse && root.loupeLocked ? 2 : 1
                                    border.color: harmonyMouse.containsMouse && root.loupeLocked
                                        ? root.colPrimary : Qt.alpha(root.colOnLayer0, 0.35)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.key
                                        color: root._swatchInkColor(modelData.hex)
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.family: "monospace"
                                    }

                                    MouseArea {
                                        id: harmonyMouse
                                        anchors.fill: parent
                                        enabled: root.loupeLocked
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: event => {
                                            if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                                            root._commitPick(modelData.hex)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Row 3 (when history exists): Interactive Recent Colors recall strip
                    RowLayout {
                        objectName: "colorPickerRecentRow"
                        visible: root.recallableRecents.length > 0
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "Recent"
                            color: root.colSubtext
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            font.family: "monospace"
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 3
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: root.recallableRecents
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 22
                                    height: 17
                                    radius: 5
                                    color: modelData.hex
                                    border.width: recentMouse.containsMouse && root.loupeLocked ? 2 : 1
                                    border.color: recentMouse.containsMouse && root.loupeLocked
                                        ? root.colPrimary : Qt.alpha(root.colOnLayer0, 0.4)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.key
                                        color: root._swatchInkColor(modelData.hex)
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.family: "monospace"
                                    }

                                    MouseArea {
                                        id: recentMouse
                                        anchors.fill: parent
                                        enabled: root.loupeLocked
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: event => {
                                            if (event.button === Qt.RightButton) { root.loupeLocked = false; return }
                                            root._commitPick(modelData.hex)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
