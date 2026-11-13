// Output-local resting geometry for the bottom-connected Abyss customization dock.
// Always stays connected to the physical bottom Screen Edge ("bottom"), sliding
// horizontally (and clamping span into clear bottom gaps when needed) to avoid
// covering desktop widgets without ever detaching or rotating to side/top edges.
function choose(work, widgets, selectedKey, requestedDepth) {
    const left = Number(work?.left) || 0, top = Number(work?.top) || 0;
    const right = Math.max(left, Number(work?.right) || left);
    const bottom = Math.max(top, Number(work?.bottom) || top);
    const workWidth = right - left, workHeight = bottom - top;
    const gap = 12, padding = Math.min(6, workWidth / 2);
    const boundLeft = left + padding;
    const boundRight = Math.max(boundLeft, right - padding);
    const maxSpan = Math.max(0, boundRight - boundLeft);
    const preferredSpan = Math.min(maxSpan, Math.max(Math.min(maxSpan, 360), Math.min(1080, workWidth - 48)));
    const minReadableSpan = Math.min(preferredSpan, Math.max(Math.min(maxSpan, 420), Math.floor(preferredSpan * 0.55)));
    const rawDepth = Number(requestedDepth);
    const targetDepth = Number.isFinite(rawDepth) && rawDepth > 0 ? rawDepth : 168;
    const depth = Math.max(0, Math.min(targetDepth, workHeight));
    const y = bottom - depth;

    const rects = [];
    const bottomIntervals = [];
    for (const item of widgets ?? []) {
        const x = Number(item?.x), wy = Number(item?.y);
        const width = Number(item?.width), height = Number(item?.height);
        if (![x, wy, width, height].every(Number.isFinite) || width <= 0 || height <= 0)
            continue;
        const rx = x - gap, ry = wy - gap, rw = width + gap * 2, rh = height + gap * 2;
        const ovY = Math.min(bottom, ry + rh) - Math.max(y, ry);
        if (ovY <= 0)
            continue;
        rects.push({ x: rx, y: ry, width: rw, height: rh, ovY: ovY, weight: item.key === selectedKey ? 4 : 1 });
        const ix0 = Math.max(boundLeft, rx), ix1 = Math.min(boundRight, rx + rw);
        if (ix1 > ix0)
            bottomIntervals.push([ix0, ix1]);
    }

    bottomIntervals.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    const merged = [];
    for (const iv of bottomIntervals) {
        if (merged.length > 0 && iv[0] <= merged[merged.length - 1][1] + 1e-6)
            merged[merged.length - 1][1] = Math.max(merged[merged.length - 1][1], iv[1]);
        else
            merged.push([iv[0], iv[1]]);
    }

    const clearGaps = [];
    let cursor = boundLeft;
    for (const iv of merged) {
        if (iv[0] - cursor >= minReadableSpan - 1e-6)
            clearGaps.push([cursor, iv[0]]);
        cursor = Math.max(cursor, iv[1]);
    }
    if (boundRight - cursor >= minReadableSpan - 1e-6)
        clearGaps.push([cursor, boundRight]);

    const spans = [preferredSpan];
    for (const g of clearGaps) {
        const gapWidth = g[1] - g[0];
        if (gapWidth < preferredSpan - 1e-6 && gapWidth >= minReadableSpan - 1e-6) {
            const clamped = Math.max(minReadableSpan, Math.min(preferredSpan, gapWidth));
            if (!spans.some(s => Math.abs(s - clamped) < 1e-6))
                spans.push(clamped);
        }
    }

    let best = null, bestOverlap = Infinity, bestSpanLoss = Infinity, bestCenterDist = Infinity;
    for (const span of spans) {
        const first = boundLeft;
        const last = Math.max(first, boundRight - span);
        const center = (first + last) / 2;
        const positions = [center, first, last];
        for (const rect of rects) {
            positions.push(
                Math.max(first, Math.min(last, rect.x - span)),
                Math.max(first, Math.min(last, rect.x + rect.width))
            );
        }
        for (const g of clearGaps) {
            if (g[1] - g[0] >= span - 1e-6) {
                const gapFirst = Math.max(first, g[0]);
                const gapLast = Math.min(last, g[1] - span);
                positions.push(Math.max(gapFirst, Math.min(gapLast, center)));
            }
        }
        for (const along of positions) {
            let overlap = 0;
            for (const rect of rects) {
                const ovX = Math.max(0, Math.min(along + span, rect.x + rect.width) - Math.max(along, rect.x));
                overlap += ovX * rect.ovY * rect.weight;
            }
            const spanLoss = preferredSpan - span;
            const centerDist = Math.abs(along - center);
            const better = overlap < bestOverlap - 1e-6
                || (Math.abs(overlap - bestOverlap) <= 1e-6 && (
                    spanLoss < bestSpanLoss - 1e-6
                    || (Math.abs(spanLoss - bestSpanLoss) <= 1e-6 && centerDist < bestCenterDist - 1e-6)
                ));
            if (better) {
                bestOverlap = overlap;
                bestSpanLoss = spanLoss;
                bestCenterDist = centerDist;
                best = {
                    edge: "bottom",
                    along: along,
                    span: span,
                    depth: depth,
                    x: along,
                    y: y,
                    width: span,
                    height: depth
                };
            }
        }
    }
    return best;
}
