// View-only color identity for Dashboard Weekly Planner events.
// No stored Event fields, recurrence timestamps or calendar sources are edited.
// Numeric Alis IDs get a contrasting, evenly distributed 8-step gradient
// sequence; imported UID/string IDs use a stable FNV-1a hash.
function paletteSlot(event, source, count) {
    const size=Math.max(1,Math.floor(Number(count) || 1));
    const id=event?.id ?? event?.uid ?? event?.iCalUID ?? event?.externalId;
    const origin=String(source || "local");
    let basis;
    if (origin==="local" && typeof id==="number"
            && Number.isSafeInteger(id) && id>=0) {
        basis=id%size;
    } else {
        const identity=id===undefined || id===null || id===""
            ? String(event?.title || "") : String(id);
        const stable=origin+":"+identity;
        let hash=2166136261;
        for (let i=0;i<stable.length;i++) {
            hash^=stable.charCodeAt(i);
            hash=Math.imul(hash,16777619)>>>0;
        }
        basis=hash%size;
    }
    // Spread consecutive IDs across separated gradient stops, not adjacent
    // colors that become hard to distinguish in compact event cards.
    if (size===8) return [0,4,2,6,1,5,3,7][basis];
    return basis;
}

function identity(event,source) {
    const id=event?.id ?? event?.uid ?? event?.iCalUID ?? event?.externalId;
    return JSON.stringify([String(source || "local"),id===undefined || id===null || id===""
        ? "title:"+String(event?.title || "") : "id:"+String(id)]);
}
function mix32(value) {
    let bits=value>>>0;
    bits=Math.imul(bits^(bits>>>16),0x7feb352d)>>>0;
    bits=Math.imul(bits^(bits>>>15),0x846ca68b)>>>0;
    return (bits^(bits>>>16))>>>0;
}
// A stable position across the existing theme gradient, independent of any
// neighboring Event, visible week, ordering or cache lifetime. The old eight
// swatches remain available via paletteSlot(), but no longer collapse every
// eighth local ID to the same rendered color. No authored Event data changes.
function position(event,source) {
    const id=event?.id;
    if ((source || "local")==="local" && Number.isSafeInteger(id) && id>=0) {
        const low=id>>>0,high=Math.floor(id/4294967296);
        // Reversible triangular mixing of all 53 safe integer bits. Given
        // the output high bits, mix32's odd multipliers recover the low
        // bits, then the original high bits. Do not truncate IDs to 32 bits.
        const upper=(high+(mix32(low)&0x1fffff))&0x1fffff;
        const lower=mix32(low^mix32(upper));
        return (upper*4294967296+lower)/9007199254740992;
    }
    const stable=identity(event,source);
    let first=2166136261,second=3339675911;
    for (let i=0;i<stable.length;i++) {
        const code=stable.charCodeAt(i);
        first=Math.imul(first^code,16777619)>>>0;
        second=Math.imul(second^code,2246822519)>>>0;
    }
    return ((mix32(first)&0x1fffff)*4294967296+mix32(second))/9007199254740992;
}
// Compatibility helper for read-only inventories; membership never affects
// any returned identity's position. Rendering can call position() directly.
function assignPositions(localEvents,externalEvents) {
    const positions={};
    function collect(events,source) {
        for (let i=0;i<(events?.length || 0);i++) {
            const event=events[i];
            if (!event) continue;
            positions[identity(event,source)]=position(event,source);
        }
    }
    collect(localEvents,"local");collect(externalEvents,"external");
    return positions;
}
