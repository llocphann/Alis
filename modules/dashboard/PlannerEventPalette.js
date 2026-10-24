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

// Theme-faithful Material tones, NOT artificially separated rainbow hues.
// Use only the real Primary/Secondary/Tertiary hue and saturation of the
// active theme. When that theme is grayscale, Event colors stay grayscale.
// Eight luminance stops distinguish individual Events within the same family;
// do not introduce an unrelated hue or force saturation on neutral themes.
function materialTones(anchors, darkMode) {
    if (!Array.isArray(anchors) || anchors.length<3) return [];
    const lightnessOffsets=[-.14,-.10,-.06,-.02,.02,.06,.10,.14];
    const anchorOrder=[0,1,2,0,1,2,0,1];
    const center=darkMode ? .59 : .46;
    const limit=value=>Math.min(1,Math.max(0,value));
    return lightnessOffsets.map((offset,index)=>{
        const source=anchors[anchorOrder[index]] || {};
        const hue=Number(source.hue);
        const sat=Number(source.saturation);
        return {
            // HSL's -1 for achromatic theme colors is not an invitation to
            // invent a hue: with saturation 0, hue 0 remains neutral.
            hue:Number.isFinite(hue)&&hue>=0 ? limit(hue) : 0,
            saturation:Number.isFinite(sat) ? limit(sat) : 0,
            lightness:limit(center+offset)
        };
    });
}
