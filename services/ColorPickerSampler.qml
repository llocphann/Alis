import QtQuick

// Sample the original screen pixels, never the magnified preview or overlay.
// Uses a single batched offscreen Canvas readback per region for 60fps smooth loupe updates.
Canvas {
    id: root
    width: 25
    height: 25
    opacity: 0
    property url imageUrl
    property size imageSize
    property bool imageLoaded: false
    readonly property bool ready: available && imageLoaded

    onImageUrlChanged: {
        imageLoaded = false
        if (imageUrl.toString() !== "") {
            loadImage(imageUrl)
            imageLoaded = isImageLoaded(imageUrl)
        }
    }
    onImageLoaded: imageLoaded = isImageLoaded(imageUrl)

    function pixelAt(x: real, y: real, logicalWidth: real, logicalHeight: real): point {
        return Qt.point(Math.max(0, Math.min(imageSize.width - 1,
            Math.floor(x * imageSize.width / logicalWidth))),
            Math.max(0, Math.min(imageSize.height - 1,
            Math.floor(y * imageSize.height / logicalHeight))))
    }

    function _toHex(r: int, g: int, b: int): string {
        return "#"
            + Number(r).toString(16).padStart(2, "0")
            + Number(g).toString(16).padStart(2, "0")
            + Number(b).toString(16).padStart(2, "0")
    }

    function sample(x: real, y: real, logicalWidth: real, logicalHeight: real): string {
        if (!ready || logicalWidth <= 0 || logicalHeight <= 0
                || imageSize.width <= 0 || imageSize.height <= 0)
            return ""
        const point = pixelAt(x, y, logicalWidth, logicalHeight)
        return colorAt(point.x, point.y)
    }

    function colorAt(x: int, y: int): string {
        if (!ready || imageSize.width <= 0 || imageSize.height <= 0) return ""
        const cx = Math.max(0, Math.min(imageSize.width - 1, x))
        const cy = Math.max(0, Math.min(imageSize.height - 1, y))
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, 1, 1)
        ctx.drawImage(imageUrl, cx, cy, 1, 1, 0, 0, 1, 1)
        const rgba = ctx.getImageData(0, 0, 1, 1).data
        if (rgba[3] !== 255)
            return ""
        return _toHex(rgba[0], rgba[1], rgba[2]).toUpperCase()
    }

    // Batched region readback: ONE drawImage + ONE getImageData for the entire
    // (2*radius+1) x (2*radius+1) loupe grid (up to 25x25). Edge pixels clamp cleanly.
    function readRegion(cx: int, cy: int, radius: int): var {
        if (!ready || imageSize.width <= 0 || imageSize.height <= 0)
            return null
        const r = Math.max(0, Math.min(12, radius))
        const dim = r * 2 + 1
        const minX = Math.max(0, cx - r)
        const minY = Math.max(0, cy - r)
        const maxX = Math.min(imageSize.width - 1, cx + r)
        const maxY = Math.min(imageSize.height - 1, cy + r)
        const srcW = Math.max(1, maxX - minX + 1)
        const srcH = Math.max(1, maxY - minY + 1)
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, srcW, srcH)
        ctx.drawImage(imageUrl, minX, minY, srcW, srcH, 0, 0, srcW, srcH)
        const raw = ctx.getImageData(0, 0, srcW, srcH).data
        return {
            cx: cx,
            cy: cy,
            radius: r,
            dim: dim,
            minX: minX,
            minY: minY,
            srcW: srcW,
            srcH: srcH,
            data: raw
        }
    }

    function regionPixelRgb(region, sx: int, sy: int): var {
        if (!region || !region.data) return null
        const lx = Math.max(0, Math.min(region.srcW - 1, sx - region.minX))
        const ly = Math.max(0, Math.min(region.srcH - 1, sy - region.minY))
        const off = (ly * region.srcW + lx) * 4
        const a = region.data[off + 3]
        if (a !== 255) return null
        return [region.data[off], region.data[off + 1], region.data[off + 2]]
    }

    function averageColorAt(cx: int, cy: int, boxSize: int): string {
        if (boxSize <= 1)
            return colorAt(cx, cy)
        const r = Math.floor(boxSize / 2)
        const region = readRegion(cx, cy, r)
        if (!region) return ""
        let sr = 0, sg = 0, sb = 0, count = 0
        for (let dy = -r; dy <= r; ++dy) {
            for (let dx = -r; dx <= r; ++dx) {
                const rgb = regionPixelRgb(region, cx + dx, cy + dy)
                if (rgb) {
                    sr += rgb[0]; sg += rgb[1]; sb += rgb[2]; count++
                }
            }
        }
        if (count === 0) return ""
        return _toHex(Math.round(sr / count), Math.round(sg / count), Math.round(sb / count)).toUpperCase()
    }
}
