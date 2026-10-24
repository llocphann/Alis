// Stable editable occurrence keys, deduped across multi-day projections.
function canSelect(row) {
    return !!row && row.source==="local" && !row.virtual
        && row.event?.id!==undefined && row.event?.id!==null
        && (row.event?.recurrence || "none")==="none";
}
// Local saved recurring slots are individually movable/resizable without
// rewriting the immutable series template. Identified virtual instances use
// per-occurrence exceptions; imported calendar rows stay read-only. Batch selection remains limited to
// non-recurring events because batch delete semantics differ for a series.
function canReschedule(row) {
    if (!row || row.source!=="local" || row.event?.allDay===true
            || row.event?.id===undefined || row.event?.id===null)
        return false;
    if (canSelect(row)) return true;
    var event=row.event;
    if (!["daily","weekly","monthly","yearly"].includes(event?.recurrence))
        return false;
    var index=row.occurrenceIndex;
    if (!Number.isInteger(index) || index<0) return false;
    // Virtual future occurrences can be edited individually, but only with
    // an explicit immutable series timestamp from the Planner projection.
    // Without it, a drag could accidentally edit the whole recurring series.
    if (row.virtual && (!row.plannerOriginalStartIso
            || !Number.isFinite(new Date(row.plannerOriginalStartIso).getTime())))
        return false;
    if (Array.isArray(event.occurrences) && event.occurrences.length) {
        // Old multi-date records have stable slots even without a template.
        // Editing one slot does not require inferring the whole series.
        return index<event.occurrences.length
            && !!(event.occurrences[index]?.startDate || event.occurrences[index]?.dateTime);
    }
    return index===0 && !!(event.startDate || event.dateTime);
}
function key(row) {
    return canSelect(row) ? String(row.event.id)+":"+String(row.occurrenceIndex) : "";
}
// Batch selection intentionally excludes recurring rows. Preview identity
// must not reuse its empty sentinel, or every recurring card moves together.
// A virtual exception retains its original key after moving across weeks.
function gestureKey(row) {
    if (!canSelect(row) && !canReschedule(row)) return "";
    return JSON.stringify([row.source,String(row.event.id),row.occurrenceIndex,
        row.virtual ? row.plannerOriginalStartIso : "saved"]);
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
