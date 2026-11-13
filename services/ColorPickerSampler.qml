import QtQuick

// Sample the original screen pixels, never the magnified preview or overlay.
Canvas {
    id: root
    width: 1
    height: 1
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

    function sample(x: real, y: real, logicalWidth: real, logicalHeight: real): string {
        if (!ready || logicalWidth <= 0 || logicalHeight <= 0
                || imageSize.width <= 0 || imageSize.height <= 0)
            return ""
        const point = pixelAt(x, y, logicalWidth, logicalHeight)
        return colorAt(point.x, point.y)
    }
    function colorAt(x: int, y: int): string {
        if (!ready) return ""
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, 1, 1)
        ctx.drawImage(imageUrl, x, y, 1, 1, 0, 0, 1, 1)
        const rgba = ctx.getImageData(0, 0, 1, 1).data
        if (rgba[3] !== 255)
            return ""
        return "#" + [rgba[0], rgba[1], rgba[2]].map(value =>
            Number(value).toString(16).padStart(2, "0")).join("").toUpperCase()
    }
}
