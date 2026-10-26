pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick

// Serpantinum-inspired renderer for PlayerControl's optional decorative
// CAVA wave. Owners with an integrated analyzer (notably BarMediaPopup's EQ DSP)
// can suppress this layer without creating a second CAVA/EQ subsystem.
Item {
    id: root

    property list<var> points
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property bool live: true
    property color color: CavaTheme.primaryColor
    // Preserve the existing user-facing wave opacity setting as the baseline
    // opacity for the bar field.
    property real fillOpacity: (Config.options?.appearance?.cava?.waveOpacity ?? 30) / 100

    property real barSpacing: 3
    property real minBarWidth: 4
    property real minBarHeight: 2

    readonly property int activeBars: Math.max(4, Math.min(64,
        Math.floor((root.width + root.barSpacing)
            / (root.minBarWidth + root.barSpacing))))
    readonly property real actualBarWidth: Math.max(1,
        (root.width - (root.activeBars - 1) * root.barSpacing)
            / Math.max(1, root.activeBars))

    // Serpantinum mirrors low frequencies toward the center and higher
    // frequencies toward the edges, then eases the outer bars to zero. Alis
    // receives raw CAVA amplitudes plus an adaptive ceiling, so normalize first
    // and keep that same visual mapping without replacing the shared service.
    readonly property var processedBars: {
        const count = root.activeBars
        let out = new Array(count).fill(0.0)
        if (!root.live || !root.points || root.points.length === 0)
            return out

        const source = root.points
        const srcLen = source.length
        const maxVal = Math.max(1, root.maxVisualizerValue)
        const half = (count - 1) / 2

        for (let i = 0; i < count; ++i) {
            const distFromCenter = Math.abs(i - half)
            const norm = half > 0 ? distFromCenter / half : 0
            const pos = Math.pow(norm, 1.25) * (srcLen - 1)
            const idx0 = Math.floor(pos)
            const idx1 = Math.min(srcLen - 1, idx0 + 1)
            const frac = pos - idx0
            const v0 = Math.max(0, Number(source[idx0]) || 0) / maxVal
            const v1 = Math.max(0, Number(source[idx1]) || 0) / maxVal
            const rawVal = Math.max(0, Math.min(1, v0 + (v1 - v0) * frac))

            const threshold = 0.02
            let value = rawVal < threshold
                ? 0.0
                : Math.pow((rawVal - threshold) / (1 - threshold), 1.10)
            value = Math.max(0.0, Math.min(1.0, value))

            const edgeNorm = Math.sin((i / Math.max(1, count - 1)) * Math.PI)
            let edgeFactor = Math.min(1.0, edgeNorm * 2.0)
            edgeFactor = edgeFactor * edgeFactor * (3.0 - 2.0 * edgeFactor)
            out[i] = value * edgeFactor
        }

        // Keep the old smoothing knob meaningful with a lightweight neighbour
        // pass. Capping the passes prevents pathological config values from
        // adding unnecessary per-frame work.
        const passes = Math.min(3, Math.max(0, Math.round(root.smoothing)))
        for (let pass = 0; pass < passes; ++pass) {
            // This fresh local array is unpublished. Carry old neighbours
            // across writes so every pass keeps the original stencil/order.
            let prev = out[0]
            let curr = out[0]
            for (let i = 0; i < count; ++i) {
                const following = i < count - 1 ? out[i + 1] : curr
                out[i] = prev * 0.25 + curr * 0.5 + following * 0.25
                prev = curr
                curr = following
            }
        }
        return out
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height
        spacing: root.barSpacing

        Repeater {
            model: root.activeBars

            delegate: Rectangle {
                required property int index
                property real level: root.processedBars && index < root.processedBars.length
                    ? root.processedBars[index] : 0.0
                property real edgeNorm: Math.sin(
                    (index / Math.max(1, root.activeBars - 1)) * Math.PI)
                property real rawEdgeFactor: Math.min(1.0, edgeNorm * 2.0)
                property real edgeFactor: rawEdgeFactor * rawEdgeFactor
                    * (3.0 - 2.0 * rawEdgeFactor)

                width: root.actualBarWidth
                // Animated delegates can lose their visual parent before the
                // owner finishes unloading. Preserve bottom alignment without
                // retaining an anchor or dereferencing a retired parent.
                height: Math.max(root?.minBarHeight ?? 0, level * (parent?.height ?? 0) * 0.96)
                y: (parent?.height ?? 0) - height
                topLeftRadius: width * 0.45
                topRightRadius: width * 0.45
                bottomLeftRadius: 0
                bottomRightRadius: 0
                // PlayerControl historically passes a transparentized accent.
                // Use its RGB as the bar color and let opacity own intensity so
                // the equalizer cannot become effectively double-transparent.
                color: Qt.rgba(root.color.r, root.color.g, root.color.b, 1.0)
                opacity: {
                    const base = Math.max(0.12, Math.min(0.70, root.fillOpacity))
                    const strength = root.live
                        ? base + level * (0.95 - base)
                        : base * 0.45
                    return strength * edgeFactor
                }

                Behavior on height {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: 75; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: 75; easing.type: Easing.OutQuad }
                }
            }
        }
    }
}
