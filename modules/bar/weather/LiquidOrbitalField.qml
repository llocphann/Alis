pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions

// Animated liquid ribbon for the Weather popup.
//
// RENDERER CONTRACT (2026-09-25):
// The accepted visual is the GPU membrane in LiquidOrbitalField.frag.qsb.
// When that path is unavailable, the Canvas fallback must still be this
// continuous deformed sheet; never fall back to discrete bridge/node capsules.
// Also never gate ShaderEffect.visible on ShaderEffect.Compiled: Qt can compile
// runtime shaders on their first rendered frame, so a status-gated visibility
// creates a self-blocking path on backends that use runtime compilation.
//
// Goal: visually closer to the concept image. The ribbon is thin, translucent
// and always moving, while the hourly nodes read as dark glass orbs sitting in
// the same fluid structure. Motion comes from travelling waves on the centre
// line + independently moving inner / outer boundaries + flowing specular
// streaks that clearly show liquid direction.
Item {
    id: root

    property var hourAngles: []
    property real orbitRadiusX: 1
    property real orbitRadiusY: 1
    property real nodeWidth: 48
    property real nodeHeight: 48
    property int activeIndex: 0
    property bool animate: false

    readonly property real regularNodeRadius:
        Math.max(14, Math.min(root.nodeWidth, root.nodeHeight) * 0.5)
    readonly property bool shaderBackendAvailable:
        GraphicsInfo.api !== GraphicsInfo.Software
        && GraphicsInfo.api !== GraphicsInfo.Null
    readonly property bool ready:
        (root.shaderBackendAvailable
            && liquidShader.status === ShaderEffect.Compiled)
        || liquidCanvas.available

    readonly property int sampleCount: 120
    readonly property real baseThickness: Math.max(5.5,
        Math.min(8.5, Math.min(root.nodeWidth, root.nodeHeight) * 0.125))
    readonly property color bodyColor: ColorUtils.applyAlpha(
        ColorUtils.mix(
            Appearance.colors.colSurfaceContainerHigh,
            Appearance.colors.colPrimaryContainer,
            0.55),
        0.22)
    readonly property color bodyBright: ColorUtils.applyAlpha(
        ColorUtils.mix(
            Appearance.colors.colPrimaryContainer,
            Appearance.colors.colPrimary,
            0.82),
        0.16)
    readonly property color rimColor: ColorUtils.applyAlpha(
        Appearance.colors.colPrimary, 0.30)
    readonly property color innerRimColor: ColorUtils.applyAlpha(
        Appearance.colors.colOnSurface, 0.08)
    readonly property color glowColor: ColorUtils.applyAlpha(
        Appearance.colors.colPrimary, Appearance.effectsEnabled ? 0.22 : 0.10)
    readonly property color glowTransparent: ColorUtils.applyAlpha(
        Appearance.colors.colPrimary, 0)
    readonly property color streakStrongColor: ColorUtils.applyAlpha(
        Appearance.colors.colOnPrimaryContainer, 0.22)
    readonly property color streakSoftColor: ColorUtils.applyAlpha(
        Appearance.colors.colOnPrimaryContainer, 0.14)
    readonly property color sheetColorA: ColorUtils.applyAlpha(
        Appearance.colors.colPrimaryContainer, 0.075)
    readonly property color sheetColorB: ColorUtils.applyAlpha(
        Appearance.colors.colPrimary, 0.055)
    readonly property color podFill: ColorUtils.applyAlpha(
        Appearance.colors.colSurfaceContainerHigh, 0.46)
    readonly property color podEdgeFill: ColorUtils.applyAlpha(
        Appearance.colors.colPrimaryContainer, 0.24)
    readonly property color podHighlight: ColorUtils.applyAlpha(
        Appearance.colors.colOnSurface, 0.10)
    readonly property color activePodFill: ColorUtils.applyAlpha(
        ColorUtils.mix(Appearance.colors.colPrimaryContainer,
            Appearance.colors.colPrimary, 0.30), 0.56)
    readonly property color activePodHighlight: ColorUtils.applyAlpha(
        Appearance.colors.colOnPrimaryContainer, 0.24)

    FrameAnimation {
        id: liquidClock
        running: root.animate
            && root.visible
            && root.hourAngles.length > 0
            && Appearance.animationsEnabled
        onTriggered: {
            if (liquidCanvas.visible)
                liquidCanvas.requestPaint()
        }
    }

    readonly property real timeSeconds: liquidClock.running
        ? liquidClock.elapsedTime
        : 0.73

    function nodeX(index: int): real {
        if (index < 0 || index >= root.hourAngles.length)
            return -10000
        return root.width / 2
            + Math.cos(Number(root.hourAngles[index])) * root.orbitRadiusX
    }

    function nodeY(index: int): real {
        if (index < 0 || index >= root.hourAngles.length)
            return -10000
        return root.height / 2
            + Math.sin(Number(root.hourAngles[index])) * root.orbitRadiusY
    }

    // Keep this item renderable while the backend decides/compiles the shader.
    // The Canvas beneath it is visible until status becomes Compiled.
    ShaderEffect {
        id: liquidShader
        anchors.fill: parent
        visible: root.shaderBackendAvailable
            && root.hourAngles.length > 0
        blending: true
        fragmentShader: Qt.resolvedUrl("LiquidOrbitalField.frag.qsb")

        readonly property vector2d fieldSize:
            Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
        readonly property vector2d orbitRadii:
            Qt.vector2d(root.orbitRadiusX, root.orbitRadiusY)
        readonly property vector4d nodesX0: Qt.vector4d(
            root.nodeX(0), root.nodeX(1), root.nodeX(2), root.nodeX(3))
        readonly property vector4d nodesX1: Qt.vector4d(
            root.nodeX(4), root.nodeX(5), root.nodeX(6), root.nodeX(7))
        readonly property vector4d nodesY0: Qt.vector4d(
            root.nodeY(0), root.nodeY(1), root.nodeY(2), root.nodeY(3))
        readonly property vector4d nodesY1: Qt.vector4d(
            root.nodeY(4), root.nodeY(5), root.nodeY(6), root.nodeY(7))
        readonly property color bodyInk: Appearance.colors.colPrimaryContainer
        readonly property color accentInk: Appearance.colors.colPrimary
        readonly property color deepInk: Appearance.colors.colSurfaceContainerHigh
        readonly property color glintInk: Appearance.colors.colOnPrimaryContainer
        readonly property real seconds: root.timeSeconds
        readonly property real regularRadius: root.regularNodeRadius
        readonly property int selectedIndex: root.activeIndex
        readonly property int nodeCount: root.hourAngles.length

        onStatusChanged: {
            if (status === ShaderEffect.Error)
                console.warn("[Weather] Liquid shader unavailable; using continuous Canvas fallback:", log)
        }
    }

    function wrapAngle(value: real): real {
        let wrapped = value % (Math.PI * 2)
        if (wrapped > Math.PI)
            wrapped -= Math.PI * 2
        else if (wrapped < -Math.PI)
            wrapped += Math.PI * 2
        return wrapped
    }

    function mix(a: real, b: real, t: real): real {
        return a + (b - a) * t
    }

    function ellipseFrame(angle: real): var {
        const c = Math.cos(angle)
        const s = Math.sin(angle)
        const cx = root.width / 2 + c * root.orbitRadiusX
        const cy = root.height / 2 + s * root.orbitRadiusY
        const txRaw = -root.orbitRadiusX * s
        const tyRaw = root.orbitRadiusY * c
        const tLen = Math.max(0.001, Math.sqrt(txRaw * txRaw + tyRaw * tyRaw))
        const tx = txRaw / tLen
        const ty = tyRaw / tLen
        const nx = ty
        const ny = -tx
        return { cx, cy, tx, ty, nx, ny, speed: tLen }
    }

    function smoothMax(a: real, b: real, k: real): real {
        if (k <= 0.001)
            return Math.max(a, b)
        const h = Math.max(0, Math.min(1, 0.5 + 0.5 * (a - b) / k))
        return root.mix(b, a, h) + k * h * (1 - h)
    }

    function nodeRadius(nodeIndex: int, time: real): real {
        const active = nodeIndex === root.activeIndex
        const base = Math.min(root.nodeWidth, root.nodeHeight) * 0.5
        const conceptScale = active ? 1.28 : 1.0
        const breathing = Math.sin(time * (active ? 1.08 : 0.72)
            + nodeIndex * 1.47) * (active ? 1.35 : 0.55)
        return Math.max(root.baseThickness + 2, base * conceptScale + breathing)
    }

    function nodeGeometry(angle: real, nodeIndex: int, time: real): var {
        if (nodeIndex < 0 || nodeIndex >= root.hourAngles.length)
            return { profile: 0, radialHalf: 0, signedArc: 0, radius: 0 }

        const nodeAngle = Number(root.hourAngles[nodeIndex] ?? 0)
        const nodeFrame = root.ellipseFrame(nodeAngle)
        const delta = root.wrapAngle(angle - nodeAngle)
        const signedArc = delta * nodeFrame.speed
        const radius = root.nodeRadius(nodeIndex, time)
        const inside = Math.abs(signedArc) < radius
        const radialHalf = inside
            ? Math.sqrt(Math.max(0, radius * radius - signedArc * signedArc))
            : 0
        const profile = radius > 0 ? radialHalf / radius : 0
        return { profile, radialHalf, signedArc, radius }
    }

    function liquidSample(angle: real, time: real): var {
        const frame = root.ellipseFrame(angle)

        // Overall centreline motion.
        let normalDrift = Math.sin(angle * 2.0 - time * 0.74) * 1.2
            + Math.sin(angle * 4.0 + time * 0.46 + 1.3) * 0.95
            + Math.sin(angle * 7.0 - time * 1.02 + 0.4) * 0.55
        let tangentDrift = Math.sin(angle * 3.0 - time * 0.43 + 0.2) * 1.2
            + Math.sin(angle * 6.0 + time * 0.29 + 0.6) * 0.7

        // Concept-like ribbon: thin between nodes, swelling smoothly at pods.
        let outerThickness = root.baseThickness
            + Math.sin(angle * 5.0 - time * 0.88) * 0.75
            + Math.sin(angle * 9.0 + time * 0.51 + 0.7) * 0.36
        let innerThickness = root.baseThickness * 0.96
            + Math.sin(angle * 4.0 + time * 0.71 + 0.5) * 0.55
            + Math.sin(angle * 8.0 - time * 0.37 + 1.9) * 0.28

        for (let i = 0; i < root.hourAngles.length; ++i) {
            const node = root.nodeGeometry(angle, i, time)
            if (node.radialHalf <= 0)
                continue
            const active = i === root.activeIndex

            // Circular support is the key visual match to the reference: the
            // hour pods remain true round glass bubbles while the ribbon
            // smoothly maximises into them. This makes the neck thin and
            // concave instead of a broad super-ellipse shoulder.
            outerThickness = root.smoothMax(
                outerThickness, node.radialHalf, active ? 5.5 : 4.2)
            innerThickness = root.smoothMax(
                innerThickness, node.radialHalf * 0.985, active ? 5.2 : 4.0)

            const shoulder = Math.tanh(node.signedArc / Math.max(5, node.radius * 0.30))
            tangentDrift += node.profile * shoulder
                * Math.sin(time * 0.84 + i * 0.91) * (active ? 3.8 : 2.0)
            normalDrift += node.profile
                * Math.sin(time * 0.58 + i * 1.57) * (active ? 1.25 : 0.55)
        }

        const cx = frame.cx + frame.nx * normalDrift + frame.tx * tangentDrift
        const cy = frame.cy + frame.ny * normalDrift + frame.ty * tangentDrift
        return {
            cx, cy,
            outerX: cx + frame.nx * outerThickness,
            outerY: cy + frame.ny * outerThickness,
            innerX: cx - frame.nx * innerThickness,
            innerY: cy - frame.ny * innerThickness,
            tx: frame.tx, ty: frame.ty,
            nx: frame.nx, ny: frame.ny,
            outerThickness,
            innerThickness,
            meanThickness: (outerThickness + innerThickness) / 2
        }
    }

    function traceClosed(ctx, points): void {
        if (!points || points.length < 3)
            return
        const count = points.length
        ctx.moveTo(points[0].x, points[0].y)
        for (let i = 0; i < count; ++i) {
            const p0 = points[(i + count - 1) % count]
            const p1 = points[i]
            const p2 = points[(i + 1) % count]
            const p3 = points[(i + 2) % count]
            ctx.bezierCurveTo(
                p1.x + (p2.x - p0.x) / 6,
                p1.y + (p2.y - p0.y) / 6,
                p2.x - (p3.x - p1.x) / 6,
                p2.y - (p3.y - p1.y) / 6,
                p2.x, p2.y)
        }
        ctx.closePath()
    }

    function traceOpen(ctx, points): void {
        if (!points || points.length < 2)
            return
        ctx.moveTo(points[0].x, points[0].y)
        for (let i = 0; i < points.length - 1; ++i) {
            const p0 = points[Math.max(0, i - 1)]
            const p1 = points[i]
            const p2 = points[i + 1]
            const p3 = points[Math.min(points.length - 1, i + 2)]
            ctx.bezierCurveTo(
                p1.x + (p2.x - p0.x) / 6,
                p1.y + (p2.y - p0.y) / 6,
                p2.x - (p3.x - p1.x) / 6,
                p2.y - (p3.y - p1.y) / 6,
                p2.x, p2.y)
        }
    }

    function requestPaint(): void {
        if (liquidCanvas.visible && liquidCanvas.available)
            liquidCanvas.requestPaint()
    }

    onHourAnglesChanged: root.requestPaint()
    onOrbitRadiusXChanged: root.requestPaint()
    onOrbitRadiusYChanged: root.requestPaint()
    onNodeWidthChanged: root.requestPaint()
    onNodeHeightChanged: root.requestPaint()
    onActiveIndexChanged: root.requestPaint()

    Canvas {
        id: liquidCanvas
        anchors.fill: parent
        visible: !root.shaderBackendAvailable
            || liquidShader.status !== ShaderEffect.Compiled
        antialiasing: true
        renderStrategy: Canvas.Threaded
        renderTarget: Canvas.Image

        onVisibleChanged: if (visible && available) requestPaint()
        onAvailableChanged: if (visible && available) requestPaint()
        onWidthChanged: if (visible && available) requestPaint()
        onHeightChanged: if (visible && available) requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0 || root.hourAngles.length === 0)
                return

            const time = root.timeSeconds
            const outer = []
            const inner = []
            const mid = []
            for (let i = 0; i < root.sampleCount; ++i) {
                const angle = -Math.PI / 2 + i / root.sampleCount * Math.PI * 2
                const sample = root.liquidSample(angle, time)
                outer.push({ x: sample.outerX, y: sample.outerY })
                inner.push({ x: sample.innerX, y: sample.innerY })
                mid.push({
                    x: root.mix(sample.outerX, sample.innerX, 0.5),
                    y: root.mix(sample.outerY, sample.innerY, 0.5)
                })
            }

            if (root.activeIndex >= 0 && root.activeIndex < root.hourAngles.length) {
                const activeAngle = Number(root.hourAngles[root.activeIndex] ?? 0)
                const activeSample = root.liquidSample(activeAngle, time)
                const glowRadius = Math.max(root.nodeWidth, root.nodeHeight)
                    * (0.82 + 0.04 * Math.sin(time * 1.11))
                const glow = ctx.createRadialGradient(
                    activeSample.cx, activeSample.cy, 2,
                    activeSample.cx, activeSample.cy, glowRadius)
                glow.addColorStop(0, root.glowColor)
                glow.addColorStop(1, root.glowTransparent)
                ctx.fillStyle = glow
                ctx.beginPath()
                ctx.arc(activeSample.cx, activeSample.cy, glowRadius, 0, Math.PI * 2)
                ctx.fill()
            }

            // Soft body fill.
            const fillGradient = ctx.createLinearGradient(0, 0, width, height)
            fillGradient.addColorStop(0, root.bodyBright)
            fillGradient.addColorStop(0.5, root.bodyColor)
            fillGradient.addColorStop(1, root.bodyBright)
            ctx.fillStyle = fillGradient
            ctx.beginPath()
            root.traceClosed(ctx, outer)
            root.traceClosed(ctx, inner.slice().reverse())
            ctx.fill()

            // Two translucent moving sheets overlap inside the same annulus.
            // The reference reads like folded smoke/liquid layers rather than a
            // flat filled path; these broad bands create that depth without a
            // blur FBO or a second scene-graph renderer.
            for (let sheet = 0; sheet < 2; ++sheet) {
                const sheetOuter = []
                const sheetInner = []
                for (let i = 0; i < root.sampleCount; ++i) {
                    const angle = -Math.PI / 2 + i / root.sampleCount * Math.PI * 2
                    const driftA = Math.sin(angle * (2.0 + sheet)
                        - time * (0.31 + sheet * 0.09) + sheet * 1.7) * 0.055
                    const driftB = Math.sin(angle * (4.0 + sheet)
                        + time * (0.27 + sheet * 0.05) + 0.8) * 0.045
                    const outerRatio = Math.max(0.02, Math.min(0.70,
                        (sheet === 0 ? 0.05 : 0.30) + driftA))
                    const innerRatio = Math.max(0.30, Math.min(0.98,
                        (sheet === 0 ? 0.58 : 0.92) + driftB))
                    sheetOuter.push({
                        x: root.mix(outer[i].x, inner[i].x, outerRatio),
                        y: root.mix(outer[i].y, inner[i].y, outerRatio)
                    })
                    sheetInner.push({
                        x: root.mix(outer[i].x, inner[i].x, innerRatio),
                        y: root.mix(outer[i].y, inner[i].y, innerRatio)
                    })
                }
                ctx.fillStyle = sheet === 0 ? root.sheetColorA : root.sheetColorB
                ctx.beginPath()
                root.traceClosed(ctx, sheetOuter)
                root.traceClosed(ctx, sheetInner.slice().reverse())
                ctx.fill()
            }

            // Paint the hour pods as glass volumes inside the same continuous
            // contour. There is deliberately no independent pod border here:
            // the shared liquid contour supplies the silhouette, avoiding the
            // "cards placed on a ring" look.
            for (let nodeIndex = 0; nodeIndex < root.hourAngles.length; ++nodeIndex) {
                const angle = Number(root.hourAngles[nodeIndex] ?? 0)
                const sample = root.liquidSample(angle, time)
                const radius = root.nodeRadius(nodeIndex, time)
                const active = nodeIndex === root.activeIndex
                const gx = sample.cx - radius * 0.18
                const gy = sample.cy - radius * 0.24
                const podGradient = ctx.createRadialGradient(
                    gx, gy, radius * 0.08,
                    sample.cx, sample.cy, radius)
                podGradient.addColorStop(0, active
                    ? root.activePodHighlight : root.podHighlight)
                podGradient.addColorStop(0.46, active
                    ? root.activePodFill : root.podFill)
                podGradient.addColorStop(1, root.podEdgeFill)
                ctx.fillStyle = podGradient
                ctx.beginPath()
                ctx.arc(sample.cx, sample.cy, radius * 0.975, 0, Math.PI * 2)
                ctx.fill()

                // Fixed glass crescent with a tiny phase drift. It gives each
                // pod the translucent spherical read visible in the concept.
                ctx.lineWidth = active ? 1.55 : 1.05
                ctx.strokeStyle = active
                    ? root.activePodHighlight : root.podHighlight
                ctx.beginPath()
                ctx.arc(sample.cx, sample.cy, radius * 0.82,
                    Math.PI * (1.08 + 0.025 * Math.sin(time * 0.31 + nodeIndex)),
                    Math.PI * 1.66)
                ctx.stroke()
            }

            // Broad soft outer aura for that foggy/translucent concept feel.
            ctx.lineWidth = 8.0
            ctx.strokeStyle = ColorUtils.applyAlpha(root.rimColor, 0.18)
            ctx.beginPath()
            root.traceClosed(ctx, outer)
            ctx.stroke()

            // Crisp readable liquid edges.
            ctx.lineWidth = 1.25
            ctx.strokeStyle = root.rimColor
            ctx.beginPath()
            root.traceClosed(ctx, outer)
            ctx.stroke()
            ctx.lineWidth = 0.85
            ctx.strokeStyle = root.innerRimColor
            ctx.beginPath()
            root.traceClosed(ctx, inner)
            ctx.stroke()

            // Layered translucent sheets running around the whole ring. The
            // supplied concept has several overlapping smoky ribbons rather
            // than one flat band, so each sheet has an independently travelling
            // cross-section.
            for (let band = 0; band < 3; ++band) {
                const bandPoints = []
                const baseRatio = 0.24 + band * 0.25
                for (let i = 0; i < root.sampleCount; ++i) {
                    const angle = -Math.PI / 2 + i / root.sampleCount * Math.PI * 2
                    const ratio = Math.max(0.12, Math.min(0.88,
                        baseRatio
                            + Math.sin(angle * (3 + band) - time * (0.40 + band * 0.07)
                                + band * 1.3) * 0.065))
                    bandPoints.push({
                        x: root.mix(outer[i].x, inner[i].x, ratio),
                        y: root.mix(outer[i].y, inner[i].y, ratio)
                    })
                }
                ctx.lineWidth = band === 1 ? 1.35 : 0.9
                ctx.strokeStyle = band === 1
                    ? root.streakStrongColor : root.streakSoftColor
                ctx.beginPath()
                root.traceClosed(ctx, bandPoints)
                ctx.stroke()
            }

            // Moving internal caustic-like lines following the deformed ribbon.
            for (let streak = 0; streak < 4; ++streak) {
                const centerAngle = -Math.PI / 2
                    + (time * (0.38 + streak * 0.04)
                        + streak * Math.PI * 2 / 4) % (Math.PI * 2)
                const streakPoints = []
                for (let j = -9; j <= 9; ++j) {
                    const angle = centerAngle + j * 0.032
                    const sample = root.liquidSample(angle, time)
                    const mixRatio = streak % 2 === 0 ? 0.34 : 0.58
                    streakPoints.push({
                        x: root.mix(sample.outerX, sample.innerX, mixRatio),
                        y: root.mix(sample.outerY, sample.innerY, mixRatio)
                    })
                }
                ctx.lineWidth = streak === 0 ? 1.8 : 1.15
                ctx.strokeStyle = streak === 0 || streak === 2
                    ? root.streakStrongColor : root.streakSoftColor
                ctx.beginPath()
                root.traceOpen(ctx, streakPoints)
                ctx.stroke()
            }

            // A subtle centreline flow helps the ribbon feel like it is moving
            // around the whole loop, not merely wobbling in place.
            ctx.lineWidth = 0.85
            ctx.strokeStyle = ColorUtils.applyAlpha(root.streakSoftColor, 0.8)
            ctx.beginPath()
            root.traceClosed(ctx, mid)
            ctx.stroke()
        }
    }
}
