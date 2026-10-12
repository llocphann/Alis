// Stateless 15-minute snap policy; no persistence during pointer movement.
// Moves preserve event duration, resize acts only on one chosen boundary.
function rangeForGesture(row, mode, dx, dy, dayWidth, hourHeight) {
    if (!row || row.source !== "local" || row.virtual
        || row.event?.allDay === true || (row.event?.recurrence || "none") !== "none")
        return null;
    const start=new Date(row.startDate),end=new Date(row.endDate);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())
        || end<=start || !(hourHeight>0) || !(dayWidth>0)) return null;
    const minutes=Math.round(Number(dy || 0)/hourHeight*4)*15;
    const days=mode==="move" ? Math.round(Number(dx || 0)/dayWidth) : 0;
    if (!Number.isFinite(minutes) || !Number.isFinite(days) || Math.abs(days)>14
        || Math.abs(minutes)>10080 || !["move","top","bottom"].includes(mode))
        return null;
    if (mode==="move") {
        // Shift both endpoints by *civil day* first (not 24h increments),
        // so horizontal dragging keeps the date correct over DST changes.
        if (days) {
            start.setDate(start.getDate()+days);
            end.setDate(end.getDate()+days);
        }
        if (minutes) {
            start.setMinutes(start.getMinutes()+minutes);
            end.setMinutes(end.getMinutes()+minutes);
        }
    } else if (mode==="top") {
        start.setMinutes(start.getMinutes()+minutes);
    } else {
        end.setMinutes(end.getMinutes()+minutes);
    }
    if (end-start<15*60000) return null;
    if (start.getTime()===new Date(row.startDate).getTime()
        && end.getTime()===new Date(row.endDate).getTime()) return null;
    return {startIso:start.toISOString(),endIso:end.toISOString()};
}
