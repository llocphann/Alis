.pragma library

// Presentation only. These helpers never change output identities/positions or
// invoke the display backend; the existing monitor drag transaction owns that.
function fitScale(bounds, width, height, padding) {
    const usableWidth = Math.max(1, width - 2 * padding)
    const usableHeight = Math.max(1, height - 2 * padding)
    return Math.min(usableWidth / Math.max(1, bounds.width),
                    usableHeight / Math.max(1, bounds.height))
}

function centeredOffset(bounds, width, height, scale) {
    return {
        x: (width - bounds.width * scale) / 2 - bounds.minX * scale,
        y: (height - bounds.height * scale) / 2 - bounds.minY * scale
    }
}

function boundedPan(x, y, layoutBounds, width, height, scale) {
    // Keep a portion of the output group reachable, including when zoomed in.
    const limitX = Math.max(0, (layoutBounds.width * scale + width) / 2 - Math.min(24, width / 2))
    const limitY = Math.max(0, (layoutBounds.height * scale + height) / 2 - Math.min(24, height / 2))
    return {x: Math.max(-limitX, Math.min(limitX, x)),
            y: Math.max(-limitY, Math.min(limitY, y))}
}

function zoomPan(pointerX, pointerY, oldScale, newScale, oldOffset, newCenter) {
    // Hold the world point under the cursor still as the viewport zooms.
    return {x: pointerX - (pointerX - oldOffset.x) * newScale / oldScale - newCenter.x,
            y: pointerY - (pointerY - oldOffset.y) * newScale / oldScale - newCenter.y}
}

function dragCoordinate(origin, delta, viewportExtent, tileExtent, margin) {
    // A zoomed/panned tile can start partly outside the viewport. Including
    // that initial position avoids a jump (and an unintended desktop move)
    // on the first drag event, while retaining the normal fitted-view bounds.
    const minimum = Math.min(margin, origin)
    const maximum = Math.max(margin, viewportExtent - tileExtent - margin, origin)
    return Math.max(minimum, Math.min(maximum, origin + delta))
}
