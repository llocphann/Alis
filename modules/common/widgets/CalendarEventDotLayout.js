// Event indicator packing for counted calendars only.
// Counterclockwise perimeter order: Bottom -> Right -> Top -> Left.
function edgeLimit(value) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.max(0, Math.min(3, Math.floor(n))) : 0;
}
function layoutDots(count, maxPerEdge, colors, fallback) {
    const n = Number(count);
    const total = Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0;
    const limit = edgeLimit(maxPerEdge);
    const shown = Math.min(total, limit * 4);
    const edges = [[], [], [], []];
    for (let i = 0; i < shown; i++)
        edges[Math.floor(i / limit)].push(colors?.[i] ?? fallback);
    return {edges:edges, total:total, shown:shown};
}
