// Canonical multi-date Agenda policy. Pure, storage-compatible and non-destructive.
// An Event owns one stable id/todoLink and ordered occurrence ranges.
function valid(value) {
    var d = new Date(value);
    return Number.isFinite(d.getTime()) ? d : null;
}
function nameKey(value) {
    return String(value || "").trim().replace(/\s+/g, " ").toLocaleLowerCase();
}
function entry(start, end, notified, reminded) {
    var a = valid(start), b = valid(end);
    if (!a) return null;
    if (!b || b <= a) b = new Date(a.getTime() + 3600000);
    return {startDate:a.toISOString(),endDate:b.toISOString(),
        notified:notified===true,reminderNotified:reminded===true};
}
function entries(event) {
    var source = Array.isArray(event?.occurrences) && event.occurrences.length
        ? event.occurrences : [event];
    return source.map(function(slot) {
        return entry(slot.startDate || slot.dateTime, slot.endDate,
            slot.notified, slot.reminderNotified);
    }).filter(function(slot) {return slot !== null;});
}
function store(event, slots) {
    var ordered=slots.slice().sort(function(a,b) {
        return new Date(a.startDate)-new Date(b.startDate);
    });
    if (!ordered.length) return event;
    var first=ordered[0];
    return Object.assign({},event,{
        occurrences:ordered,
        startDate:first.startDate,dateTime:first.startDate,endDate:first.endDate,
        notified:first.notified,reminderNotified:first.reminderNotified
    });
}
function compatible(a,b) {
    return nameKey(a.title)!=="" && nameKey(a.title)===nameKey(b.title)
        && String(a.description || "").trim()===String(b.description || "").trim()
        && (a.category || "general")===(b.category || "general")
        && (a.priority || "normal")===(b.priority || "normal")
        && Number(a.reminderMinutes ?? 15)===Number(b.reminderMinutes ?? 15)
        && (a.allDay===true)===(b.allDay===true)
        && (a.recurrence || "none")==="none" && (b.recurrence || "none")==="none"
        && a.todoLink?.state !== "detached";
}
function append(existing, incoming) {
    if (!compatible(existing,incoming)) return null;
    var slot=entry(incoming.startDate || incoming.dateTime,incoming.endDate,false,false);
    if (!slot) return null;
    var slots=entries(existing);
    if (slots.length >= 512) return null;
    if (slots.some(function(s) {return s.startDate===slot.startDate && s.endDate===slot.endDate;}))
        return {event:existing,duplicate:true};
    return {event:store(existing,slots.concat([slot])),duplicate:false};
}
function reschedule(event,index,start,end) {
    if ((event.recurrence || "none")!=="none") return null;
    var slots=entries(event),newSlot=entry(start,end,false,false);
    if (!newSlot || !Number.isInteger(index) || index<0 || index>=slots.length) return null;
    var a=valid(start),b=valid(end);
    if (!a || !b || b <= a) return null;
    if (slots.some(function(s,i) {
        return i!==index && s.startDate===newSlot.startDate && s.endDate===newSlot.endDate;
    })) return null;
    slots[index]=newSlot;
    return store(event,slots);
}
// Each saved time slot counts separately in calendar indicators, even when
// several compatible Agenda slots share one canonical Event ID.
function occurrencesForDay(event,date,includeNotified) {
    var begin=valid(date);
    if (!begin) return [];
    begin.setHours(0,0,0,0);
    var finish=new Date(begin);finish.setDate(finish.getDate()+1);
    return entries(event).filter(function(slot) {
        return (includeNotified || !slot.notified || event.allDay===true)
            && valid(slot.startDate)<finish && valid(slot.endDate)>begin;
    });
}
function intersectsDay(event,date,includeNotified) {
    return occurrencesForDay(event,date,includeNotified).length > 0;
}
function upcoming(event,nowValue,throughValue) {
    var now=valid(nowValue),through=valid(throughValue);
    if (!now || !through) return null;
    return entries(event).find(function(slot) {
        var a=valid(slot.startDate),b=valid(slot.endDate);
        return event.allDay===true ? b>now && a<=through
            : a>=now && a<=through && !slot.notified;
    }) || null;
}


