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
            var monthly=new Date(base);monthly.setMonth(base.getMonth()+m);return monthly;
        });
    } else if (recurrence === "yearly") {
        range(Math.max(1,earliest.getFullYear()-base.getFullYear()-1),through.getFullYear()-base.getFullYear()+1,function(y) {
            var yearly=new Date(base);yearly.setFullYear(base.getFullYear()+y);return yearly;
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
                var occurrenceSource=Object.assign({},event,{
                    startDate:base.toISOString(),dateTime:base.toISOString(),
                    endDate:baseEnd && baseEnd>base ? baseEnd.toISOString() : "",
                    notified:slot.notified===true
                });
                var generated=starts(occurrenceSource,days,pair[1],event.allDay
                    ? allDaySpan*86400000 : duration);
                if (generated.limited) days.forEach(function(day) {day.projectionLimited=true;});
                generated.dates.forEach(function(occurrence) {
                    var start=event.allDay ? midnight(occurrence) : occurrence;
                    var finish=event.allDay ? addDays(start,allDaySpan)
                        : new Date(start.getTime()+duration);
                    days.forEach(function(day,index) {
                        if (start>=day.end || finish<=day.date) return;
                        var bucket=event.allDay ? day.allDay : day.timed;
                        if (bucket.length>=512) {day.overflow++;return;}
                        var from=Math.max(start,day.date),to=Math.min(finish,day.end);
                        bucket.push({key:pair[1]+":"+String(event.id || event.uid || "")
                                +":"+slotIndex+":"+start.getTime()+":"+index,
                            event:event,source:pair[1],occurrenceIndex:slotIndex,
                            virtual:occurrence.getTime()!==base.getTime(),
                            start:(from-day.date)/minute,end:(to-day.date)/minute,
                            startDate:new Date(start),endDate:finish,lane:0,lanes:1});
                    });
                });
            });
        });
    });
    days.forEach(function(day) {pack(day.timed);});
    return days;
}
