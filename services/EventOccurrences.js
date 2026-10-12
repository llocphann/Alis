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
function intersectsDay(event,date,includeNotified) {
    var begin=new Date(date);begin.setHours(0,0,0,0);
    var finish=new Date(begin);finish.setDate(finish.getDate()+1);
    return entries(event).some(function(slot) {
        return (includeNotified || !slot.notified || event.allDay===true)
            && valid(slot.startDate)<finish && valid(slot.endDate)>begin;
    });
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


/**
 * Automatic, idempotent migration of legacy single-date local events.
 *
 * Keep the original rows in Events.qml's persisted migration backup before
 * replacing this list; never import or modify an external calendar.
 * Preserve ID, Todo owner, notification flags and historical timestamps.
 * When an additional record already owns a linked/detached Todo, keep that
 * record separate rather than orphaning or stealing the user's task.
 */
function migrateLegacy(raw) {
    if (!Array.isArray(raw)) return {events:[],changed:false,normalized:0,merged:0,skippedLinked:0};
    var events=[],changed=false,normalized=0,merged=0,skippedLinked=0;
    raw.forEach(function(original) {
        if (!original || typeof original!=="object" || Array.isArray(original)) return;
        var value=original;
        var isSingle=(!Array.isArray(original.occurrences) || !original.occurrences.length)
            && (original.recurrence || "none")==="none";
        if (isSingle) {
            var slot=entry(original.startDate || original.dateTime,original.endDate,
                original.notified,original.reminderNotified);
            if (slot) {
                value=store(original,[slot]);
                normalized++;
                changed=true;
            }
        }
        var destination=-1;
        for (var i=0;i<events.length;i++) {
            if (compatible(events[i],value) && entries(events[i]).length<512) {
                var slotList=entries(value);
                var existing=entries(events[i]);
                if (slotList.length && slotList.every(function(slot) {
                    return !existing.some(function(prev) {
                        return prev.startDate===slot.startDate && prev.endDate===slot.endDate;
                    });
                })) {
                    destination=i; break;
                }
            }
        }
        if (destination>=0) {
            var link=value.todoLink;
            // Only unlinked or never-provisioned tasks can be consolidated.
            // "linked", "detached", or provider-bearing tasks keep their
            // original event ID, no automatic cross-provider mutation.
            if (link && (link.state!=="pending" || Boolean(link.provider))) {
                skippedLinked++;
                events.push(value);
                return;
            }
            var target=events[destination];
            var combined=store(target,entries(target).concat(entries(value)));
            var legacy=Array.isArray(target.mergedLegacyIds)
                ? target.mergedLegacyIds.slice():[];
            if (!legacy.includes(value.id)) legacy.push(value.id);
            events[destination]=Object.assign({},combined,{mergedLegacyIds:legacy});
            changed=true;
            merged++;
        } else events.push(value);
    });
    return {events:events,changed:changed,normalized:normalized,
        merged:merged,skippedLinked:skippedLinked};
}
