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

// Use the actual Material theme accents as hue anchors, not CAVA's
// deliberately hue-shifted audio spectrum. Material wallpaper palettes can
// have nearly identical Primary/Secondary/Tertiary hues; in that case choose
// the closest separated hue so compact Event cards remain distinguishable.
// This function is pure and computes only presentation colors.
function themeHues(primary,secondary,tertiary,count) {
    const length=Math.max(1,Math.min(8,Math.floor(Number(count) || 8)));
    const normalize=value=>{
        const hue=Number(value);
        return Number.isFinite(hue) && hue>=0 ? ((hue%1)+1)%1 : 0.58;
    };
    const anchors=[normalize(primary),normalize(secondary),normalize(tertiary)];
    const offsets=[0,0,0,.13,-.13,.26,-.26,.39];
    const shifts=[0,.10,-.10,.20,-.20,.30,-.30,.40,-.40,.50];
    const circularDistance=(a,b)=>{
        const difference=Math.abs(a-b);
        return Math.min(difference,1-difference);
    };
    const result=[];
    for (let i=0;i<length;i++) {
        const base=(anchors[i%3]+offsets[i])%1;
        let chosen=base,bestDistance=-1;
        for (const shift of shifts) {
            const hue=(base+shift+1)%1;
            const nearest=result.length
                ? Math.min(...result.map(previous=>circularDistance(previous,hue)))
                : 1;
            if (nearest>bestDistance) {
                bestDistance=nearest;chosen=hue;
            }
            if (nearest>=.09) {
                chosen=hue;break;
            }
        }
        result.push(chosen);
    }
    return result;
}
