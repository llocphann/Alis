// Three local civil dates for the compact Calendar-adjacent Events pane.
// Reuse WeeklyPlannerPolicy.project so recurrence, timed overlap, all-day
// exclusive ends and DST are computed by the existing canonical projection.
// This is view-only: each row retains its original event for Edit/Remove.
function threeDayEvents(local, external, currentDate, projectWeek) {
    const now = new Date(currentDate);
    if (!Number.isFinite(now.getTime())) return [];
    const days = projectWeek(local || [], external || [], now, now.getDay()).slice(0,3);
    const output = [];
    days.forEach((day,index) => {
        const rows = day.allDay.concat(day.timed).sort((a,b) =>
            (a.start - b.start) || (a.event?.allDay === b.event?.allDay
                ? 0 : a.event?.allDay ? -1 : 1)
                || String(a.key).localeCompare(String(b.key)));
        rows.forEach((row,position) => {
            const original = row.event;
            // Legacy single-instance/recurring records must retain their exact
            // canonical object identity. Only grouped Events need a per-date
            // edit index wrapper; the original store stays unchanged.
            const canonical = Array.isArray(original.occurrences)
                && original.occurrences.length
                ? Object.assign({},original,{_editOccurrenceIndex:row.occurrenceIndex})
                : original;
            output.push(Object.assign({}, original, {
                _source:row.source,
                _canonicalEvent:canonical,
                _dayOffset:index,
                _groupDate:day.date,
                _showDayHeader:position===0,
                _virtualOccurrence:row.virtual,
                dateTime:row.startDate.toISOString(),
                startDate:row.startDate.toISOString(),
                endDate:row.endDate.toISOString()
            }));
        });
    });
    return output;
}

function eventIsPast(start, end, nowValue) {
    const now = new Date(nowValue);
    if (end !== null && end !== undefined && end !== "") {
        const finish = new Date(end);
        if (Number.isFinite(finish.getTime())) return finish <= now;
    }
    const begin = new Date(start);
    return Number.isFinite(begin.getTime()) && begin < now;
}
