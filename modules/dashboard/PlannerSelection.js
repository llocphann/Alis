// Stable editable occurrence keys, deduped across multi-day projections.
function canSelect(row) {
    return !!row && row.source==="local" && !row.virtual
        && row.event?.id!==undefined && row.event?.id!==null
        && (row.event?.recurrence || "none")==="none";
}
// Local saved recurring slots are individually movable/resizable without
// rewriting the immutable series template. Virtual future projections and
// imported calendar rows stay read-only. Batch selection remains limited to
// non-recurring events because batch delete semantics differ for a series.
function canReschedule(row) {
    if (!row || row.source!=="local" || row.virtual || row.event?.allDay===true)
        return false;
    if (canSelect(row)) return true;
    var event=row.event;
    if (!["daily","weekly","monthly","yearly"].includes(event?.recurrence)
            || !Array.isArray(event.occurrences)
            || !Array.isArray(event.repeatTemplate) || !event.repeatTemplate.length)
        return false;
    var index=row.occurrenceIndex;
    return Number.isInteger(index) && index>=0 && index<event.occurrences.length
        && !!event.occurrences[index];
}
function key(row) {
    return canSelect(row) ? String(row.event.id)+":"+String(row.occurrenceIndex) : "";
}
function ordered(days) {
    const unique=new Set(),rows=[];
    for (const day of days || []) {
        for (const row of (day.allDay || []).concat(day.timed || [])) {
            const id=key(row);
            if (!id || unique.has(id)) continue;
            unique.add(id);rows.push(row);
        }
    }
    rows.sort((a,b)=>new Date(a.startDate)-new Date(b.startDate)
        || key(a).localeCompare(key(b)));
    return rows;
}
function choose(rows,selected,anchor,target,ctrl,shift) {
    const id=key(target);
    if (!id) return null;
    const options=rows.map(key),end=options.indexOf(id);
    if (end<0) return null;
    if (shift) {
        const start=Math.max(0,options.indexOf(anchor));
        const range=options.slice(Math.min(start,end),Math.max(start,end)+1);
        const merged=ctrl ? (selected || []).concat(range) : range;
        return {keys:Array.from(new Set(merged)),anchor:options[start]};
    }
    if (ctrl) {
        const next=(selected || []).includes(id)
            ? selected.filter(value=>value!==id) : (selected || []).concat([id]);
        return {keys:next,anchor:id};
    }
    return {keys:[id],anchor:id};
}
