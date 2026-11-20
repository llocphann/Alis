import QtQuick
import qs.modules.common
import qs.modules.abyss.looks

Canvas {
    id: root

    property bool editorVisible: false
    property bool rulerEnabled: true
    property string activeEdge: "top"
    property var guides: []
    property var records: []
    property var targetIds: []
    property real edgeThickness: 16
    property real fontScale: Appearance.fontSizeScale
    property color accentColor: AbyssStyle.accent
    property color inkColor: Appearance.colors.colOnLayer1
    property color surfaceColor: Appearance.colors.colSurfaceContainerHighest

    anchors.fill: parent
    enabled: false
    z: 5
    visible: root.editorVisible && root.rulerEnabled && width >= 520 && height >= 420

    function _repaintIfVisible(): void {
        if (root.visible)
            root.requestPaint()
    }

    onVisibleChanged: _repaintIfVisible()
    onActiveEdgeChanged: _repaintIfVisible()
    onGuidesChanged: _repaintIfVisible()
    onRecordsChanged: _repaintIfVisible()
    onTargetIdsChanged: _repaintIfVisible()
    onEdgeThicknessChanged: _repaintIfVisible()
    onWidthChanged: _repaintIfVisible()
    onHeightChanged: _repaintIfVisible()

    function rgba(c, alphaScale) {
        const a = Math.max(0, Math.min(1, c.a * alphaScale))
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a.toFixed(3) + ")"
    }

    function drawPillBadge(ctx, cx, cy, label, fillCol, textCol) {
        const clean = String(label || "").trim()
        if (!clean.length) return
        ctx.save()
        ctx.font = "600 " + Math.max(9, Math.round(10 * root.fontScale)) + "px sans-serif"
        const padX = 6
        const boxW = Math.ceil(ctx.measureText(clean).width) + padX * 2
        const boxH = Math.round(16 * root.fontScale)
        const bx = Math.max(4, Math.min(root.width - boxW - 4, cx - boxW / 2))
        const by = Math.max(4, Math.min(root.height - boxH - 4, cy - boxH / 2))
        const r = boxH / 2
        ctx.fillStyle = fillCol
        ctx.beginPath()
        ctx.moveTo(bx + r, by)
        ctx.arcTo(bx + boxW, by, bx + boxW, by + boxH, r)
        ctx.arcTo(bx + boxW, by + boxH, bx, by + boxH, r)
        ctx.arcTo(bx, by + boxH, bx, by, r)
        ctx.arcTo(bx, by, bx + boxW, by, r)
        ctx.closePath()
        ctx.fill()

        ctx.fillStyle = textCol
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(clean, bx + boxW / 2, by + boxH / 2 + 0.5)
        ctx.restore()
    }

    function drawArrowHead(ctx, x, y, dx, dy) {
        const s = 4
        ctx.beginPath()
        ctx.moveTo(x, y)
        ctx.lineTo(x - dx * s - dy * s * 0.65, y - dy * s + dx * s * 0.65)
        ctx.lineTo(x - dx * s + dy * s * 0.65, y - dy * s - dx * s * 0.65)
        ctx.closePath()
        ctx.fill()
    }

    onPaint: {
        if (!root.visible || width <= 0 || height <= 0)
            return
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        const offset = Math.max(22, Math.round(root.edgeThickness + 10))
        const accentSolid = root.rgba(root.accentColor, 0.94)
        const accentSoft = root.rgba(root.accentColor, 0.55)
        const pillBg = root.rgba(root.surfaceColor, 0.92)

        // 1. 4-edge perimeter rulers
        const edges = ["top", "bottom", "left", "right"]
        for (let ei = 0; ei < edges.length; ei++) {
            const edge = edges[ei]
            const horiz = edge === "top" || edge === "bottom"
            const len = horiz ? width : height
            const active = edge === root.activeEdge
            const lineAlpha = active ? 0.55 : 0.22
            const linePos = edge === "top" ? offset
                : edge === "bottom" ? height - offset
                : edge === "left" ? offset
                : width - offset
            const sign = (edge === "top" || edge === "left") ? 1 : -1

            ctx.strokeStyle = active ? root.rgba(root.accentColor, lineAlpha) : root.rgba(root.inkColor, lineAlpha)
            ctx.lineWidth = 1
            ctx.beginPath()
            if (horiz) {
                ctx.moveTo(0, linePos)
                ctx.lineTo(len, linePos)
            } else {
                ctx.moveTo(linePos, 0)
                ctx.lineTo(linePos, len)
            }
            ctx.stroke()

            // Fine 20px / major 100px ticks
            for (let p = 20; p < len; p += 20) {
                const isMajor = (p % 100 === 0)
                const tickLen = isMajor ? 6 : 3
                ctx.strokeStyle = root.rgba(root.inkColor, active ? (isMajor ? 0.52 : 0.28) : (isMajor ? 0.22 : 0.12))
                ctx.beginPath()
                if (horiz) {
                    ctx.moveTo(p, linePos)
                    ctx.lineTo(p, linePos + sign * tickLen)
                } else {
                    ctx.moveTo(linePos, p)
                    ctx.lineTo(linePos + sign * tickLen, p)
                }
                ctx.stroke()
            }

            // 25% / 50% / 75% landmark ticks
            const landmarks = [
                { frac: 0.25, text: "25%" },
                { frac: 0.50, text: "50%" },
                { frac: 0.75, text: "75%" }
            ]
            for (let li = 0; li < landmarks.length; li++) {
                const lm = landmarks[li]
                const pos = Math.round(len * lm.frac)
                ctx.strokeStyle = active ? accentSolid : root.rgba(root.accentColor, 0.35)
                ctx.lineWidth = lm.frac === 0.5 ? 1.5 : 1
                ctx.beginPath()
                if (horiz) {
                    ctx.moveTo(pos, linePos - sign * 3)
                    ctx.lineTo(pos, linePos + sign * 8)
                } else {
                    ctx.moveTo(linePos - sign * 3, pos)
                    ctx.lineTo(linePos + sign * 8, pos)
                }
                ctx.stroke()
                if (active) {
                    ctx.save()
                    ctx.font = "600 " + Math.max(8, Math.round(9 * root.fontScale)) + "px sans-serif"
                    ctx.fillStyle = accentSoft
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    if (horiz)
                        ctx.fillText(lm.text, pos, linePos + sign * 15)
                    else
                        ctx.fillText(lm.text, linePos + sign * 18, pos)
                    ctx.restore()
                }
            }
        }

        // 2. Highlight active/selected module bands on their edge ruler + live neighbor pixel gaps
        const recs = Array.isArray(root.records) ? root.records : []
        const targets = Array.isArray(root.targetIds) ? root.targetIds : []
        for (let ti = 0; ti < targets.length; ti++) {
            const rec = recs.find(r => r && r.id === targets[ti])
            if (!rec || rec.span <= 0) continue
            const horiz = rec.edge === "top" || rec.edge === "bottom"
            const edgeLen = horiz ? width : height
            const linePos = rec.edge === "top" ? offset
                : rec.edge === "bottom" ? height - offset
                : rec.edge === "left" ? offset
                : width - offset
            const sign = (rec.edge === "top" || rec.edge === "left") ? 1 : -1

            ctx.fillStyle = accentSolid
            if (horiz)
                ctx.fillRect(rec.along, linePos - 1.5, rec.span, 3)
            else
                ctx.fillRect(linePos - 1.5, rec.along, 3, rec.span)

            if (ti === 0) {
                const centerPct = Math.round(((rec.along + rec.span / 2) / Math.max(1, edgeLen)) * 100)
                const readout = Math.round(rec.along) + " px · " + Math.round(rec.span) + " px (" + centerPct + "%)"
                const badgeInk = root.accentColor.hslLightness > 0.62 ? "#11161d" : "#ffffff"
                if (horiz)
                    root.drawPillBadge(ctx, rec.along + rec.span / 2, linePos + sign * 28, readout, accentSolid, badgeInk)
                else
                    root.drawPillBadge(ctx, linePos + sign * 48, rec.along + rec.span / 2, readout, accentSolid, badgeInk)
            }
        }

        // 3. Smart alignment lines & spacing measurements from guides
        const gList = Array.isArray(root.guides) ? root.guides : []
        for (let gi = 0; gi < gList.length; gi++) {
            const g = gList[gi]
            if (!g) continue
            if (g.kind === "spacing") {
                const from = Number(g.from ?? 0)
                const to = Number(g.to ?? 0)
                if (!(to > from)) continue
                const spanOffset = offset + 12
                const lineCoord = g.edge === "top" ? spanOffset
                    : g.edge === "bottom" ? height - spanOffset
                    : g.edge === "left" ? spanOffset
                    : width - spanOffset

                ctx.save()
                ctx.strokeStyle = accentSolid
                ctx.fillStyle = accentSolid
                ctx.lineWidth = 1.25
                if (g.horizontal) {
                    ctx.beginPath()
                    ctx.moveTo(from, lineCoord)
                    ctx.lineTo(to, lineCoord)
                    ctx.stroke()
                    root.drawArrowHead(ctx, from, lineCoord, -1, 0)
                    root.drawArrowHead(ctx, to, lineCoord, 1, 0)
                    root.drawPillBadge(ctx, (from + to) / 2, lineCoord - 12, g.label, pillBg, accentSolid)
                } else {
                    ctx.beginPath()
                    ctx.moveTo(lineCoord, from)
                    ctx.lineTo(lineCoord, to)
                    ctx.stroke()
                    root.drawArrowHead(ctx, lineCoord, from, 0, -1)
                    root.drawArrowHead(ctx, lineCoord, to, 0, 1)
                    root.drawPillBadge(ctx, lineCoord + 24, (from + to) / 2, g.label, pillBg, accentSolid)
                }
                ctx.restore()
            } else if (g.along !== undefined) {
                const along = Number(g.along)
                ctx.save()
                ctx.strokeStyle = accentSolid
                ctx.lineWidth = 1.25
                ctx.setLineDash([4, 4])
                ctx.beginPath()
                if (g.horizontal) {
                    ctx.moveTo(along, 0)
                    ctx.lineTo(along, height)
                } else {
                    ctx.moveTo(0, along)
                    ctx.lineTo(width, along)
                }
                ctx.stroke()
                ctx.restore()

                if (g.horizontal)
                    root.drawPillBadge(ctx, along, offset + 44, g.label, pillBg, accentSolid)
                else
                    root.drawPillBadge(ctx, offset + 54, along, g.label, pillBg, accentSolid)
            }
        }
    }
}
