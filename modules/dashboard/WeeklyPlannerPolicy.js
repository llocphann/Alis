// View-only projection of the canonical calendar. Never creates stored events.
var minute = 60000;
var hour = 60 * minute;
function validDate(value) {
    var date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
}
function midnight(value) {
    var date = new Date(value);
    date.setHours(0, 0, 0, 0);
    return date;
}
function addDays(value, count) {
    var date = new Date(value);
    date.setDate(date.getDate() + count);
    return date;
}
function week(value, firstDay) {
    var start = midnight(value);
    start.setDate(start.getDate() - (start.getDay() - Number(firstDay || 0) + 7) % 7);
    return Array.from({length:7}, function(_, index) {
        var date = addDays(start, index), end = addDays(date, 1);
        return {date:date, end:end, minutes:(end-date)/minute, timed:[], allDay:[], overflow:0};
    });
}
function civilIndex(value) {
    return Date.UTC(value.getFullYear(), value.getMonth(), value.getDate()) / 86400000;
}
function starts(event, days, source, duration) {
    var base = validDate(event.startDate || event.dateTime);
    if (!base) return {dates:[],limited:false};
    var recurrence = source === "local" && !event.notified ? event.recurrence : "none";
    var dates = [base];
    var earliest=new Date(days[0].date.getTime()-duration-2*86400000);
    var through=days[6].end;
    var limited=false;
    function range(first,last,create) {
        if (last-first+1>1024) {first=last-1023;limited=true;}
        for (var index=first;index<=last;index++) dates.push(create(index));
    }
    // Only the active canonical occurrence projects future repetitions. Saved
    // notified history is rendered once, not expanded into a duplicate series.
    if (recurrence === "daily" || recurrence === "weekly") {
        var step = recurrence === "daily" ? 1 : 7;
        var first = Math.max(1, Math.floor((civilIndex(earliest)-civilIndex(base))/step)-1);
        var last = Math.ceil((civilIndex(through)-civilIndex(base))/step);
        range(first,last,function(n) {return addDays(base,n*step);});
    } else if (recurrence === "monthly") {
        var firstMonth = (earliest.getFullYear()-base.getFullYear())*12+earliest.getMonth()-base.getMonth();
        var lastMonth = (through.getFullYear()-base.getFullYear())*12+through.getMonth()-base.getMonth();
        range(Math.max(1,firstMonth-1),lastMonth+1,function(m) {
            var month=new Date(base.getFullYear(),base.getMonth()+m,1,12);
            var monthly=new Date(month.getFullYear(),month.getMonth(),base.getDate(),
                base.getHours(),base.getMinutes(),base.getSeconds(),base.getMilliseconds());
            // Missing 29/30/31 in a shorter month skips this cycle.
            return monthly.getMonth()===month.getMonth() ? monthly : null;
        });
    } else if (recurrence === "yearly") {
        range(Math.max(1,earliest.getFullYear()-base.getFullYear()-1),through.getFullYear()-base.getFullYear()+1,function(y) {
            var yearly=new Date(base.getFullYear()+y,base.getMonth(),base.getDate(),
                base.getHours(),base.getMinutes(),base.getSeconds(),base.getMilliseconds());
            // Feb 29 repeats only in leap years.
            return yearly.getMonth()===base.getMonth() ? yearly : null;
        });
    }
    return {dates:dates,limited:limited};
}
function pack(rows) {
    rows.sort(function(a,b) {return a.start-b.start || a.end-b.end || a.key.localeCompare(b.key);});
    var active=[], cluster=[], clusterEnd=-Infinity, lanes=0;
    function finish() {
        cluster.forEach(function(row) {row.lanes=lanes;});
        cluster=[]; active=[]; lanes=0;
    }
    rows.forEach(function(row) {
        if (row.start>=clusterEnd) finish();
        active=active.filter(function(other) {return other.end>row.start;});
        var lane=0;
        while (active.some(function(other) {return other.lane===lane;})) lane++;
        row.lane=lane; lanes=Math.max(lanes,lane+1); cluster.push(row); active.push(row);
        clusterEnd=Math.max(clusterEnd,row.end);
    });
    finish();
    return rows;
}
function project(local, external, value, firstDay) {
    var days=week(value,firstDay);
    [[local,"local"],[external,"external"]].forEach(function(pair) {
        (pair[0] || []).forEach(function(event) {
            var grouped = Array.isArray(event.occurrences) && event.occurrences.length;
            var ranges = grouped ? event.occurrences : [event];
            ranges.forEach(function(slot,slotIndex) {
                var base=validDate(slot.startDate || slot.dateTime);
                if (!base) return;
                var baseEnd=validDate(slot.endDate);
                var duration=baseEnd && baseEnd>base ? baseEnd-base : hour;
                var allDaySpan=event.allDay && baseEnd && baseEnd>base
                    ? Math.max(1,civilIndex(baseEnd)-civilIndex(base)) : 1;
                // A repeating multi-day group is one pattern. Project every
                // day of its currently active cycle even when an earlier day
                // has already fired. Archive cycles render as history only.
                var repeatingGroup=Array.isArray(event.repeatTemplate)
                    && event.repeatTemplate.length>0
                    && (event.recurrence || "none")!=="none";
                var activeGroup=repeatingGroup && slotIndex>=Number(event.repeatCycleStart || 0);
                // When a saved recurring occurrence is independently moved,
                // project the current instance at its edited date, but generate
                // future virtual weeks from the immutable original schedule.
                // Never rewrite original Agenda slots while rendering.
                // Legacy single-date Events do not have an occurrences array or
                // repeatTemplate. The original top-level schedule anchor must
                // still govern virtual future instances after a manual edit.
                var recurring=pair[1]==="local" && (event.recurrence || "none")!=="none";
                var anchor=recurring && validDate(slot.plannerSeriesStartDate) || base;
                var anchorEnd=recurring && validDate(slot.plannerSeriesEndDate) || baseEnd;
                var seriesDuration=anchorEnd && anchorEnd>anchor ? anchorEnd-anchor : duration;
                var occurrenceSource=Object.assign({},event,{
                    startDate:anchor.toISOString(),dateTime:anchor.toISOString(),
                    endDate:anchorEnd && anchorEnd>anchor ? anchorEnd.toISOString() : "",
                    notified:(repeatingGroup && !activeGroup)
                        || (slot.notified===true && !activeGroup)
                });
                var generated=starts(occurrenceSource,days,pair[1],event.allDay
                    ? allDaySpan*86400000 : seriesDuration);
                if (generated.limited) days.forEach(function(day) {day.projectionLimited=true;});
                var overrides=recurring && Array.isArray(event.plannerOverrides)
                    ? event.plannerOverrides.filter(function(item) {
                        return item.occurrenceIndex===slotIndex
                            && item.materializedOccurrenceIndex===undefined
                            && item.forwardedEventId===undefined;
                    }) : [];
                function overrideFor(occurrence) {
                    return overrides.find(function(item) {
                        return item.originalStartDate===occurrence.toISOString();
                    }) || null;
                }
                function drawOccurrence(occurrence,saved,correction) {
                    var actualStart=correction && validDate(correction.startDate);
                    var actualEnd=correction && validDate(correction.endDate);
                    if (!actualStart || !actualEnd || actualEnd<=actualStart)
                        correction=null;
                    var start=correction ? actualStart
                        : event.allDay ? midnight(saved ? base : occurrence)
                        : (saved ? base : occurrence);
                    var finish=correction ? actualEnd
                        : event.allDay ? addDays(start,allDaySpan)
                        : new Date(start.getTime()+(saved ? duration : seriesDuration));
                    days.forEach(function(day,index) {
                        if (start>=day.end || finish<=day.date) return;
                        var bucket=event.allDay ? day.allDay : day.timed;
                        if (bucket.length>=512) {day.overflow++;return;}
                        var from=Math.max(start,day.date),to=Math.min(finish,day.end);
                        bucket.push({key:pair[1]+":"+String(event.id || event.uid || "")
                                +":"+slotIndex+":"+start.getTime()+":"+index,
                            event:event,source:pair[1],occurrenceIndex:slotIndex,
                            virtual:!saved,
                            // The original projected date is an immutable
                            // exception key even after this instance moves.
                            plannerOriginalStartIso:saved ? "" : occurrence.toISOString(),
                            start:(from-day.date)/minute,end:(to-day.date)/minute,
                            startDate:new Date(start),endDate:finish,lane:0,lanes:1});
                    });
                }
                var sawAnchor=false,seenVirtual=new Set();
                generated.dates.filter(function(date){return date!==null;}).forEach(function(occurrence) {
                    var saved=occurrence.getTime()===anchor.getTime();
                    if (saved) sawAnchor=true;
                    if (!saved) seenVirtual.add(occurrence.toISOString());
                    // If a stored instance moves onto a later projected
                    // occurrence, do not draw that same instance twice.
                    if (!saved && occurrence.getTime()===base.getTime()
                            && base.getTime()!==anchor.getTime()) return;
                    drawOccurrence(occurrence,saved,saved ? null : overrideFor(occurrence));
                });
                // A projected exception moved across weeks must be rendered
                // in its destination, even if its original generated date
                // lies outside this seven-day projection window.
                overrides.forEach(function(item) {
                    if (seenVirtual.has(item.originalStartDate)) return;
                    var original=validDate(item.originalStartDate);
                    if (original) drawOccurrence(original,false,item);
                });
                // The stored instance may have moved into another week while
                // its immutable series anchor remains in the original week.
                if (!sawAnchor && anchor.getTime()!==base.getTime())
                    drawOccurrence(base,true,null);
            });
        });
    });
    days.forEach(function(day) {pack(day.timed);});
    return days;
}
