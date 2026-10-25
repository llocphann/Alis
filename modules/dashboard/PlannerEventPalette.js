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
// Keep every uncontested original swatch. Resolve modulo/hash collisions
// once per Event inventory, never per occurrence or visible-week ordering.
// This is a view cache: no saved colors/IDs/history or source data change.
function assignPositions(localEvents,externalEvents) {
    const records=new Map(),positions={},used=new Set(),pending=[];
    function collect(events,source) {
        for (let i=0;i<(events?.length || 0);i++) {
            const event=events[i];
            if (!event) continue;
            const key=identity(event,source);
            if (!records.has(key)) records.set(key,{key:key,
                preferred:paletteSlot(event,source,8)/7});
        }
    }
    collect(localEvents,"local");collect(externalEvents,"external");
    const ordered=Array.from(records.values()).sort((a,b)=>a.key<b.key ? -1 : a.key>b.key ? 1 : 0);
    for (const record of ordered) {
        if (used.has(record.preferred)) {pending.push(record);continue;}
        positions[record.key]=record.preferred;used.add(record.preferred);
    }
    let subdivision=1;
    for (const record of pending) {
        let chosen=-1,distance=-1;
        if (used.size<8) {
            for (let stop=0;stop<8;stop++) {
                const candidate=stop/7;
                if (used.has(candidate)) continue;
                const gap=Math.min.apply(null,Array.from(used).map(value=>Math.abs(value-candidate)));
                if (gap>distance) {distance=gap;chosen=candidate;}
            }
        } else {
            // Dyadic interior positions do not coincide with the original
            // seven-interval grid. Additional identities remain distinct
            // without repeated full-inventory scans or a hard record limit.
            do {
                let digits=subdivision++,fraction=0,weight=.5;
                while (digits>0) {fraction+=(digits%2)*weight;digits=Math.floor(digits/2);weight/=2;}
                chosen=fraction;
            } while (used.has(chosen));
        }
        positions[record.key]=chosen;used.add(chosen);
    }
    return positions;
}
