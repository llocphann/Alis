pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Reusable direct-on-image annotation layer shared between the live
// screenshot selector and the standalone AnnotationEditor window.
Item {
    id: root

    property string imageSource: ""
    property string tool: "" // "" | "pen" | "arrow" | "rect" | "ellipse" | "highlight" | "text" | "pixelate" | "step"
    property color strokeColor: Appearance.colors.colPrimary
    property real strokeWidth: 4
    property bool interactive: true
    property bool handleInternalPointer: true
    property real minPointStep: 2.5

    property var items: []
    property var redoStack: []
    property var currentItem: null
    property var activeTextItem: null
    property int nextStepNumber: 1

    readonly property bool textEditing: activeTextItem !== null
    readonly property bool drawing: currentItem !== null
    readonly property bool hasAnnotations: items.length > 0
        || currentItem !== null
        || (activeTextItem !== null && inlineTextInput.text.trim().length > 0)
    readonly property bool canUndo: items.length > 0 || activeTextItem !== null
    readonly property bool canRedo: redoStack.length > 0

    readonly property var palette: [
        Appearance.m3colors.m3primary,
        Appearance.m3colors.m3error,
        "#f59e0b",
        "#10b981",
        Appearance.m3colors.m3tertiary,
        "#ffffff",
        "#111827"
    ]

    signal annotationChanged()
    signal editingTextFinished()
    signal toolSelected(string nextTool)

    property string _loadedImageSource: ""
    property point _lastPoint: Qt.point(NaN, NaN)

    function _syncImageToCanvas(): void {
        const src = String(root.imageSource || "");
        if (root._loadedImageSource.length > 0 && root._loadedImageSource !== src) {
            committedCanvas.unloadImage(root._loadedImageSource);
            root._loadedImageSource = "";
        }
        if (src.length > 0 && sourceProbe.status === Image.Ready) {
            if (committedCanvas.isImageLoaded(src))
                committedCanvas.unloadImage(src);
            committedCanvas.loadImage(src);
            root._loadedImageSource = src;
        }
    }

    onImageSourceChanged: {
        // Drop cached pixelate samples if the underlying screenshot changed.
        if (root.items.length > 0) {
            for (let i = 0; i < root.items.length; ++i) {
                if (root.items[i] && root.items[i]._blocks)
                    root.items[i]._blocks = null;
            }
        }
        Qt.callLater(root._syncImageToCanvas);
    }

    Component.onDestruction: {
        if (root._loadedImageSource.length > 0) {
            committedCanvas.unloadImage(root._loadedImageSource);
            root._loadedImageSource = "";
        }
    }

    Image {
        id: sourceProbe
        visible: false
        source: root.imageSource
        cache: false
        onStatusChanged: {
            if (status === Image.Ready)
                root._syncImageToCanvas();
        }
    }

    function _recomputeNextStep(): void {
        let maxStep = 0;
        for (let i = 0; i < root.items.length; ++i) {
            const it = root.items[i];
            if (it && it.kind === "step")
                maxStep = Math.max(maxStep, Number(it.stepNumber || 0));
        }
        root.nextStepNumber = maxStep + 1;
    }

    function commitActiveText(): bool {
        if (!root.activeTextItem)
            return false;
        const rawText = inlineTextInput.text.replace(/\s+$/, "");
        if (rawText.trim().length > 0) {
            const nextItems = root.items.slice();
            nextItems.push({
                kind: "text",
                x: root.activeTextItem.x,
                y: root.activeTextItem.y,
                color: root.activeTextItem.color,
                size: root.activeTextItem.size,
                text: rawText
            });
            root.items = nextItems;
            root.redoStack = [];
            committedCanvas.requestPaint();
            root.annotationChanged();
        }
        root.activeTextItem = null;
        root.editingTextFinished();
        return true;
    }

    function cancelActiveText(): bool {
        if (!root.activeTextItem)
            return false;
        root.activeTextItem = null;
        root.editingTextFinished();
        return true;
    }

    function undo(): bool {
        if (root.activeTextItem) {
            root.cancelActiveText();
            return true;
        }
        if (root.items.length === 0)
            return false;
        const nextItems = root.items.slice();
        const removed = nextItems.pop();
        const nextRedo = root.redoStack.slice();
        nextRedo.push(removed);
        root.items = nextItems;
        root.redoStack = nextRedo;
        root._recomputeNextStep();
        committedCanvas.requestPaint();
        root.annotationChanged();
        return true;
    }

    function redo(): bool {
        if (root.redoStack.length === 0)
            return false;
        const nextRedo = root.redoStack.slice();
        const restored = nextRedo.pop();
        const nextItems = root.items.slice();
        nextItems.push(restored);
        root.items = nextItems;
        root.redoStack = nextRedo;
        root._recomputeNextStep();
        committedCanvas.requestPaint();
        root.annotationChanged();
        return true;
    }

    function clearAll(): void {
        root.activeTextItem = null;
        root.currentItem = null;
        root.items = [];
        root.redoStack = [];
        root.nextStepNumber = 1;
        committedCanvas.requestPaint();
        liveCanvas.requestPaint();
        root.annotationChanged();
    }

    function handleKey(event): bool {
        if (!event || root.textEditing)
            return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        if (ctrl && ((shift && event.key === Qt.Key_Z) || event.key === Qt.Key_Y)) {
            root.redo();
            event.accepted = true;
            return true;
        }
        if (ctrl && event.key === Qt.Key_Z) {
            root.undo();
            event.accepted = true;
            return true;
        }
        if (!ctrl && (event.modifiers & Qt.AltModifier) === 0 && (event.modifiers & Qt.MetaModifier) === 0) {
            const keyTools = {};
            keyTools[Qt.Key_0] = "";
            keyTools[Qt.Key_1] = "pen";
            keyTools[Qt.Key_2] = "arrow";
            keyTools[Qt.Key_3] = "rect";
            keyTools[Qt.Key_4] = "ellipse";
            keyTools[Qt.Key_5] = "highlight";
            keyTools[Qt.Key_6] = "text";
            keyTools[Qt.Key_7] = "pixelate";
            keyTools[Qt.Key_8] = "step";
            const mapped = keyTools[event.key];
            if (mapped !== undefined) {
                root.tool = mapped;
                root.toolSelected(mapped);
                event.accepted = true;
                return true;
            }
        }
        return false;
    }

    function _colorLuminance(colStr): real {
        const c = Qt.color(colStr);
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    function _snapEndpoint(a, b, shiftHeld, mode): var {
        if (!shiftHeld)
            return b;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        if (mode === "rect" || mode === "ellipse") {
            const side = Math.max(Math.abs(dx), Math.abs(dy));
            return { x: a.x + (dx >= 0 ? side : -side), y: a.y + (dy >= 0 ? side : -side) };
        }
        if (mode === "pen" || mode === "arrow" || mode === "highlight") {
            const len = Math.hypot(dx, dy);
            if (len < 1)
                return b;
            const stepRad = Math.PI / 12.0; // 15 deg
            const ang = Math.round(Math.atan2(dy, dx) / stepRad) * stepRad;
            return { x: a.x + Math.cos(ang) * len, y: a.y + Math.sin(ang) * len };
        }
        return b;
    }

    function _ensurePixelateBlocks(ctx, item, cw, ch): var {
        if (item._blocks && !item._blocks.fallback)
            return item._blocks;
        const pts = item.pts;
        if (!pts || pts.length < 2)
            return null;
        const p0 = pts[0];
        const p1 = pts[pts.length - 1];
        const bx = Math.max(0, Math.floor(Math.min(p0.x, p1.x)));
        const by = Math.max(0, Math.floor(Math.min(p0.y, p1.y)));
        const bw = Math.min(Math.floor(cw) - bx, Math.ceil(Math.abs(p1.x - p0.x)));
        const bh = Math.min(Math.floor(ch) - by, Math.ceil(Math.abs(p1.y - p0.y)));
        if (bw < 3 || bh < 3)
            return null;

        const bs = Math.max(10, Math.round(Number(item.width || 4) * 3));
        const cols = Math.max(1, Math.min(180, Math.ceil(bw / bs)));
        const rows = Math.max(1, Math.min(180, Math.ceil(bh / bs)));

        const src = String(root.imageSource || "");
        const nw = sourceProbe.sourceSize.width;
        const nh = sourceProbe.sourceSize.height;
        if (src.length > 0 && nw > 0 && nh > 0 && committedCanvas.isImageLoaded(src) && cw > 0 && ch > 0) {
            try {
                const sx = Math.max(0, Math.min(nw - 1, bx * (nw / cw)));
                const sy = Math.max(0, Math.min(nh - 1, by * (nh / ch)));
                const sw = Math.max(1, Math.min(nw - sx, bw * (nw / cw)));
                const sh = Math.max(1, Math.min(nh - sy, bh * (nh / ch)));

                // Preserve existing top-left corner pixels of committedCanvas while sampling downscaled tiles.
                const backup = ctx.getImageData(0, 0, cols, rows);
                ctx.save();
                ctx.imageSmoothingEnabled = true;
                ctx.drawImage(src, sx, sy, sw, sh, 0, 0, cols, rows);
                const sampled = ctx.getImageData(0, 0, cols, rows);
                ctx.putImageData(backup, 0, 0);
                ctx.restore();

                const srcW = Math.max(1, Number(sampled.width || cols));
                const srcH = Math.max(1, Number(sampled.height || rows));
                const colors = new Array(rows * cols);
                const d = sampled.data;
                for (let r = 0; r < rows; ++r) {
                    const sr = Math.min(srcH - 1, Math.floor(r * srcH / rows));
                    for (let c = 0; c < cols; ++c) {
                        const sc = Math.min(srcW - 1, Math.floor(c * srcW / cols));
                        const o = (sr * srcW + sc) * 4;
                        colors[r * cols + c] = `rgb(${d[o]},${d[o + 1]},${d[o + 2]})`;
                    }
                }
                item._blocks = { bx: bx, by: by, bw: bw, bh: bh, bs: bs, cols: cols, rows: rows, colors: colors };
                return item._blocks;
            } catch (e) {
                // Fall back to deterministic neutral mosaic tiles if image pixels cannot be read.
            }
        }
        const fallback = new Array(rows * cols);
        for (let r = 0; r < rows; ++r) {
            for (let c = 0; c < cols; ++c) {
                const shade = ((r + c) % 2 === 0) ? 28 : 42;
                fallback[r * cols + c] = `rgb(${shade},${shade + 4},${shade + 8})`;
            }
        }
        item._blocks = { bx: bx, by: by, bw: bw, bh: bh, bs: bs, cols: cols, rows: rows, colors: fallback, fallback: true };
        return item._blocks;
    }

    function _drawItem(ctx, item, cw, ch, isLive): void {
        if (!item)
            return;
        const kind = item.kind;
        ctx.save();

        if (kind === "text") {
            const fontSize = Math.max(12, Number(item.size || 18));
            const lines = String(item.text || "").split("\n");
            ctx.font = `600 ${fontSize}px "${Appearance.font.family.main}", sans-serif`;
            ctx.textBaseline = "top";
            const darkStroke = root._colorLuminance(item.color) > 0.45;
            ctx.lineJoin = "round";
            ctx.lineWidth = Math.max(2.5, fontSize * 0.16);
            ctx.strokeStyle = darkStroke ? "rgba(8, 12, 16, 0.85)" : "rgba(255, 255, 255, 0.85)";
            ctx.fillStyle = String(item.color);
            const lh = fontSize * 1.24;
            for (let i = 0; i < lines.length; ++i) {
                const ly = Number(item.y) + i * lh;
                ctx.strokeText(lines[i], Number(item.x), ly);
                ctx.fillText(lines[i], Number(item.x), ly);
            }
            ctx.restore();
            return;
        }

        const pts = item.pts;
        if (!pts || pts.length === 0) {
            ctx.restore();
            return;
        }

        if (kind === "pixelate") {
            const p0 = pts[0];
            const p1 = pts[pts.length - 1];
            const bx = Math.max(0, Math.min(p0.x, p1.x));
            const by = Math.max(0, Math.min(p0.y, p1.y));
            const bw = Math.abs(p1.x - p0.x);
            const bh = Math.abs(p1.y - p0.y);
            if (isLive) {
                ctx.fillStyle = "rgba(18, 24, 32, 0.42)";
                ctx.fillRect(bx, by, bw, bh);
                ctx.strokeStyle = String(item.color || "#38bdf8");
                ctx.lineWidth = 1.5;
                ctx.strokeRect(bx, by, bw, bh);
                const bs = Math.max(10, Math.round(Number(item.width || 4) * 3));
                ctx.strokeStyle = "rgba(255, 255, 255, 0.22)";
                ctx.lineWidth = 1;
                for (let gx = bx + bs; gx < bx + bw; gx += bs) {
                    ctx.beginPath(); ctx.moveTo(gx, by); ctx.lineTo(gx, by + bh); ctx.stroke();
                }
                for (let gy = by + bs; gy < by + bh; gy += bs) {
                    ctx.beginPath(); ctx.moveTo(bx, gy); ctx.lineTo(bx + bw, gy); ctx.stroke();
                }
            } else {
                const blocks = root._ensurePixelateBlocks(ctx, item, cw, ch);
                if (blocks) {
                    const cellW = blocks.bw / blocks.cols;
                    const cellH = blocks.bh / blocks.rows;
                    for (let r = 0; r < blocks.rows; ++r) {
                        const ry = blocks.by + r * cellH;
                        const rh = (r === blocks.rows - 1) ? (blocks.by + blocks.bh - ry) : Math.ceil(cellH);
                        for (let c = 0; c < blocks.cols; ++c) {
                            const rx = blocks.bx + c * cellW;
                            const rw = (c === blocks.cols - 1) ? (blocks.bx + blocks.bw - rx) : Math.ceil(cellW);
                            ctx.fillStyle = blocks.colors[r * blocks.cols + c];
                            ctx.fillRect(rx, ry, rw, rh);
                        }
                    }
                }
            }
            ctx.restore();
            return;
        }

        if (kind === "step") {
            const c = pts[0];
            const t = pts[pts.length - 1];
            const w = Math.max(2, Number(item.width || 4));
            const r = Math.max(12, Math.round(w * 2.4 + 3));
            const col = String(item.color || "#38bdf8");
            const dx = t.x - c.x;
            const dy = t.y - c.y;
            const dist = Math.hypot(dx, dy);

            if (dist > r + 6) {
                const ux = dx / dist;
                const uy = dy / dist;
                const sx = c.x + ux * (r - 1);
                const sy = c.y + uy * (r - 1);
                const head = Math.min(18, Math.max(10, w * 3.2));
                const shaftEndX = t.x - ux * (head * 0.65);
                const shaftEndY = t.y - uy * (head * 0.65);

                ctx.strokeStyle = col;
                ctx.lineWidth = Math.max(2, w * 0.85);
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(sx, sy);
                ctx.lineTo(shaftEndX, shaftEndY);
                ctx.stroke();

                const ang = 0.45;
                const lx = t.x - head * (ux * Math.cos(ang) - uy * Math.sin(ang));
                const ly = t.y - head * (uy * Math.cos(ang) + ux * Math.sin(ang));
                const rx = t.x - head * (ux * Math.cos(ang) + uy * Math.sin(ang));
                const ry = t.y - head * (uy * Math.cos(ang) - ux * Math.sin(ang));
                ctx.fillStyle = col;
                ctx.beginPath();
                ctx.moveTo(t.x, t.y);
                ctx.lineTo(lx, ly);
                ctx.lineTo(rx, ry);
                ctx.closePath();
                ctx.fill();
            }

            const darkStroke = root._colorLuminance(col) > 0.55;
            ctx.fillStyle = col;
            ctx.beginPath();
            ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
            ctx.fill();
            ctx.lineWidth = 1.75;
            ctx.strokeStyle = darkStroke ? "rgba(15, 23, 42, 0.8)" : "rgba(255, 255, 255, 0.9)";
            ctx.stroke();

            const numSize = Math.max(11, Math.round(r * 1.08));
            ctx.font = `700 ${numSize}px "${Appearance.font.family.main}", sans-serif`;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillStyle = darkStroke ? "#0f172a" : "#ffffff";
            ctx.fillText(String(item.stepNumber || 1), c.x, c.y + 0.5);
            ctx.restore();
            return;
        }

        ctx.strokeStyle = String(item.color);
        ctx.fillStyle = String(item.color);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        if (kind === "highlight") {
            ctx.globalAlpha = 0.36;
            ctx.lineWidth = Math.max(8, Number(item.width || 4) * 3.8);
            if (pts.length >= 2) {
                ctx.beginPath();
                ctx.moveTo(pts[0].x, pts[0].y);
                for (let i = 1; i < pts.length; ++i)
                    ctx.lineTo(pts[i].x, pts[i].y);
                ctx.stroke();
            }
            ctx.restore();
            return;
        }

        ctx.lineWidth = Math.max(1, Number(item.width || 4));
        if (kind === "pen") {
            if (pts.length === 1) {
                ctx.beginPath();
                ctx.arc(pts[0].x, pts[0].y, ctx.lineWidth * 0.5, 0, Math.PI * 2);
                ctx.fill();
            } else if (pts.length >= 2) {
                ctx.beginPath();
                ctx.moveTo(pts[0].x, pts[0].y);
                for (let i = 1; i < pts.length - 1; ++i) {
                    const mx = (pts[i].x + pts[i + 1].x) * 0.5;
                    const my = (pts[i].y + pts[i + 1].y) * 0.5;
                    ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my);
                }
                const last = pts[pts.length - 1];
                ctx.lineTo(last.x, last.y);
                ctx.stroke();
            }
            ctx.restore();
            return;
        }

        const p0 = pts[0];
        const p1 = pts[pts.length - 1];
        if (kind === "rect") {
            const rx = Math.min(p0.x, p1.x);
            const ry = Math.min(p0.y, p1.y);
            const rw = Math.abs(p1.x - p0.x);
            const rh = Math.abs(p1.y - p0.y);
            ctx.strokeRect(rx, ry, rw, rh);
        } else if (kind === "ellipse") {
            const rx = Math.abs(p1.x - p0.x) * 0.5;
            const ry = Math.abs(p1.y - p0.y) * 0.5;
            if (rx >= 0.5 && ry >= 0.5) {
                const cx = (p0.x + p1.x) * 0.5;
                const cy = (p0.y + p1.y) * 0.5;
                ctx.translate(cx, cy);
                ctx.scale(rx, ry);
                ctx.beginPath();
                ctx.arc(0, 0, 1, 0, Math.PI * 2);
                ctx.restore();
                ctx.save();
                ctx.strokeStyle = String(item.color);
                ctx.lineWidth = Math.max(1, Number(item.width || 4));
                ctx.stroke();
            }
        } else if (kind === "arrow") {
            const dx = p1.x - p0.x;
            const dy = p1.y - p0.y;
            const len = Math.hypot(dx, dy);
            if (len >= 1) {
                const ux = dx / len;
                const uy = dy / len;
                const head = Math.max(10, Math.min(28, ctx.lineWidth * 3.4, len * 0.48));
                const shaftEndX = p1.x - ux * (head * 0.65);
                const shaftEndY = p1.y - uy * (head * 0.65);

                ctx.beginPath();
                ctx.moveTo(p0.x, p0.y);
                ctx.lineTo(shaftEndX, shaftEndY);
                ctx.stroke();

                const ang = 0.45;
                const lx = p1.x - head * (ux * Math.cos(ang) - uy * Math.sin(ang));
                const ly = p1.y - head * (uy * Math.cos(ang) + ux * Math.sin(ang));
                const rx = p1.x - head * (ux * Math.cos(ang) + uy * Math.sin(ang));
                const ry = p1.y - head * (uy * Math.cos(ang) - ux * Math.sin(ang));
                ctx.beginPath();
                ctx.moveTo(p1.x, p1.y);
                ctx.lineTo(lx, ly);
                ctx.lineTo(rx, ry);
                ctx.closePath();
                ctx.fill();
            }
        }
        ctx.restore();
    }

    Canvas {
        id: committedCanvas
        anchors.fill: parent
        z: 1
        renderStrategy: Canvas.Cooperative
        renderTarget: Canvas.Image
        onImageLoaded: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const list = root.items || [];
            for (let i = 0; i < list.length; ++i)
                root._drawItem(ctx, list[i], width, height, false);
        }
    }

    Canvas {
        id: liveCanvas
        anchors.fill: parent
        z: 2
        visible: root.currentItem !== null
        renderStrategy: Canvas.Threaded
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.currentItem)
                root._drawItem(ctx, root.currentItem, width, height, true);
        }
    }

    // Inline text composer shown only while actively typing a new label; once
    // Enter commits, the label is baked onto committedCanvas with zero cursor.
    Item {
        id: inlineTextBox
        z: 20
        visible: root.activeTextItem !== null
        x: Math.max(4, Math.min(root.width - Math.max(120, width) - 4, Number(root.activeTextItem?.x ?? 0)))
        y: Math.max(4, Math.min(root.height - Math.max(32, height) - 4, Number(root.activeTextItem?.y ?? 0)))
        width: Math.max(96, Math.min(root.width - 16, inlineTextInput.contentWidth + 18))
        height: Math.max(30, inlineTextInput.contentHeight + 10)

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Qt.rgba(0.06, 0.08, 0.1, 0.72)
            border.width: 1
            border.color: String(root.activeTextItem?.color ?? Appearance.colors.colPrimary)
        }

        TextEdit {
            id: inlineTextInput
            anchors.fill: parent
            anchors.margins: 5
            color: String(root.activeTextItem?.color ?? Appearance.colors.colPrimary)
            font.family: Appearance.font.family.main
            font.weight: Font.DemiBold
            font.pixelSize: Number(root.activeTextItem?.size ?? 18)
            selectByMouse: true
            Keys.onPressed: (event) => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && (event.modifiers & Qt.ShiftModifier) === 0) {
                    event.accepted = true;
                    root.commitActiveText();
                } else if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    root.cancelActiveText();
                }
            }
        }
    }

    function startStroke(x: real, y: real, modifiers: int): bool {
        if (!root.interactive || root.tool.length === 0)
            return false;
        if (root.textEditing) {
            root.commitActiveText();
            return true;
        }
        if (root.tool === "text") {
            const fontSize = Math.max(14, Math.round(root.strokeWidth * 4 + 4));
            inlineTextInput.text = "";
            root.activeTextItem = {
                x: x,
                y: y,
                color: String(root.strokeColor),
                size: fontSize,
                text: ""
            };
            Qt.callLater(() => {
                inlineTextInput.forceActiveFocus();
            });
            return true;
        }
        root._lastPoint = Qt.point(x, y);
        root.currentItem = {
            kind: root.tool,
            color: String(root.strokeColor),
            width: root.strokeWidth,
            stepNumber: root.tool === "step" ? root.nextStepNumber : 0,
            pts: [{ x: x, y: y }]
        };
        liveCanvas.requestPaint();
        return true;
    }

    function moveStroke(x: real, y: real, modifiers: int): void {
        if (!root.currentItem)
            return;
        const c = root.currentItem;
        const dx = x - root._lastPoint.x;
        const dy = y - root._lastPoint.y;
        if (dx * dx + dy * dy < root.minPointStep * root.minPointStep)
            return;
        root._lastPoint = Qt.point(x, y);
        const shift = (modifiers & Qt.ShiftModifier) !== 0;
        const p = root._snapEndpoint(c.pts[0], { x: x, y: y }, shift, c.kind);
        if ((c.kind === "pen" || c.kind === "highlight") && !shift)
            c.pts.push(p);
        else
            c.pts = [c.pts[0], p];
        root.currentItem = c;
        liveCanvas.requestPaint();
    }

    function endStroke(): void {
        if (!root.currentItem)
            return;
        const c = root.currentItem;
        root.currentItem = null;
        root._lastPoint = Qt.point(NaN, NaN);
        liveCanvas.requestPaint();

        let valid = false;
        if (c.kind === "step") {
            valid = true;
        } else if (c.kind === "pen" || c.kind === "highlight") {
            valid = c.pts.length >= 1;
        } else if (c.pts.length >= 2) {
            const a = c.pts[0];
            const b = c.pts[c.pts.length - 1];
            valid = Math.hypot(b.x - a.x, b.y - a.y) >= 3;
        }
        if (!valid)
            return;

        const nextItems = root.items.slice();
        nextItems.push(c);
        root.items = nextItems;
        root.redoStack = [];
        root._recomputeNextStep();
        committedCanvas.requestPaint();
        root.annotationChanged();
    }

    function cancelStroke(): void {
        if (!root.currentItem)
            return;
        root.currentItem = null;
        root._lastPoint = Qt.point(NaN, NaN);
        liveCanvas.requestPaint();
    }

    MouseArea {
        id: drawArea
        anchors.fill: parent
        z: 10
        visible: root.handleInternalPointer
        enabled: root.handleInternalPointer && root.interactive && root.tool.length > 0
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: (root.handleInternalPointer && root.interactive && root.tool.length > 0)
            ? (root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor)
            : Qt.ArrowCursor

        onPressed: (mouse) => root.startStroke(mouse.x, mouse.y, mouse.modifiers)
        onPositionChanged: (mouse) => root.moveStroke(mouse.x, mouse.y, mouse.modifiers)
        onReleased: () => root.endStroke()
        onCanceled: () => root.cancelStroke()
    }
}
