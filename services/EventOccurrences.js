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
    var grouped = Array.isArray(event?.occurrences) && event.occurrences.length;
    var source = grouped ? event.occurrences : [event];
    return source.map(function(slot) {
        var normalized=entry(slot.startDate || slot.dateTime,slot.endDate,
            slot.notified,slot.reminderNotified);
        if (!normalized) return null;
        // Preserve the immutable scheduled time of an edited recurring
        // instance through due processing and its subsequent store() pass.
        if (slot.plannerSeriesStartDate && slot.plannerSeriesEndDate) {
            normalized.plannerSeriesStartDate=slot.plannerSeriesStartDate;
            normalized.plannerSeriesEndDate=slot.plannerSeriesEndDate;
        }
        // Preserve extension fields and per-instance metadata through a
        // save/due/reload pass, including older schemas we do not own.
        return Object.assign({},grouped ? slot : {},normalized);
    }).filter(function(slot) {return slot !== null;});
}
function store(event, slots) {
    // Recurring indices are persistent identity and repeatCycleStart is an
    // index boundary. A moved instance may cross another slot chronologically;
    // sorting here would silently retarget later edits/exception keys.
    var ordered=slots.slice();
    if ((event.recurrence || "none")==="none") ordered.sort(function(a,b) {
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
    slots[index]=Object.assign({},slots[index],newSlot);
    return store(event,slots);
}
// Adjust exactly one already-persisted repeating occurrence. Do not touch
// the recurrence mode, immutable repeatTemplate, selectedTemplate, history,
// notified flags or stable slot indices. In particular, never call store():
// sorting a moved slot would silently corrupt repeatCycleStart boundaries.
function rescheduleSavedRecurring(event,index,start,end) {
    if (!event || !["daily","weekly","monthly","yearly"].includes(event.recurrence)
            || !Number.isInteger(index) || index<0)
        return null;
    var a=valid(start),b=valid(end);
    if (!a || !b || b-a<15*60000) return null;
    var grouped=Array.isArray(event.occurrences) && event.occurrences.length>0;
    // Legacy Events used just startDate/dateTime + recurrence. A single
    // persisted occurrence is a real editable instance, not a virtual date.
    // Slot identity is sufficient even before repeatTemplate existed. Keep
    // every original slot/index and do not infer a cycle from old history.
    if (grouped && index>=event.occurrences.length)
        return null;
    if (!grouped && index!==0) return null;
    var slots=grouped ? event.occurrences : [event];
    var previous=slots[index];
    var prior=valid(previous?.startDate || previous?.dateTime);
    var priorEnd=valid(previous?.endDate);
    if (!prior) return null;
    if (!priorEnd || priorEnd<=prior)
        priorEnd=new Date(prior.getTime()+3600000);
    // store() keeps recurring indices stable, so crossing a neighboring day
    // no longer requires blocking an otherwise valid single-instance move.
    if (a.getTime()===prior.getTime() && b.getTime()===priorEnd.getTime())
        return null;
    var originalStart=previous.plannerSeriesStartDate
        || previous.startDate || previous.dateTime;
    var originalEnd=previous.plannerSeriesEndDate
        || previous.endDate || priorEnd.toISOString();
    var replacement=Object.assign({},previous,{
        startDate:a.toISOString(),endDate:b.toISOString(),
        plannerSeriesStartDate:originalStart,
        plannerSeriesEndDate:originalEnd
    });
    if (!grouped) {
        // No automatic migration: keep the old top-level single-event shape,
        // original stable ID, notified history and unrelated custom fields.
        return Object.assign({},event,replacement,{dateTime:replacement.startDate});
    }
    var updated=slots.slice();
    updated[index]=replacement;
    var result=Object.assign({},event,{occurrences:updated});
    if (event.occurrences.length===1 && !event.repeatTemplate?.length) {
        // Safe, explicit promotion only when the owner edits this one slot.
        // The pre-edit time remains the repeat rule's immutable anchor.
        result.repeatTemplate=[{startDate:originalStart,endDate:originalEnd}];
        result.repeatCycleStart=0;
    }
    if (index===0) {
        result.startDate=replacement.startDate;
        result.dateTime=replacement.startDate;
        result.endDate=replacement.endDate;
    }
    return result;
}
// A projected recurring occurrence has no saved slot to reschedule. Store
// only an occurrence-keyed exception, never rewrite the template, history,
// stable Event ID or its generated future dates.
function recurringVirtualMatches(base,original,mode) {
    var from=valid(base),target=valid(original);
    if (!from || !target || target<=from
            || from.getHours()!==target.getHours()
            || from.getMinutes()!==target.getMinutes()
            || from.getSeconds()!==target.getSeconds()
            || from.getMilliseconds()!==target.getMilliseconds()) return false;
    var days=(Date.UTC(target.getFullYear(),target.getMonth(),target.getDate())
        -Date.UTC(from.getFullYear(),from.getMonth(),from.getDate()))/86400000;
    if (mode==="daily") return Number.isInteger(days) && days>=1;
    if (mode==="weekly") return Number.isInteger(days) && days>=7 && days%7===0;
    if (mode==="monthly") return target.getDate()===from.getDate()
        && 12*(target.getFullYear()-from.getFullYear())
            +target.getMonth()-from.getMonth()>=1;
    if (mode==="yearly") return target.getMonth()===from.getMonth()
        && target.getDate()===from.getDate()
        && target.getFullYear()>from.getFullYear();
    return false;
}
function rescheduleProjectedRecurring(event,index,originalIso,start,end) {
    if (!event || !["daily","weekly","monthly","yearly"].includes(event.recurrence)
            || !Number.isInteger(index) || index<0
            || event.plannerOverrides && !Array.isArray(event.plannerOverrides))
        return null;
    var grouped=Array.isArray(event.occurrences) && event.occurrences.length>0;
    if (grouped && index>=event.occurrences.length)
        return null;
    if (!grouped && index!==0) return null;
    var slot=grouped ? event.occurrences[index] : event;
    var base=valid(slot?.plannerSeriesStartDate || slot?.startDate || slot?.dateTime);
    var original=valid(originalIso),a=valid(start),b=valid(end);
    if (!base || !original || !a || !b || b-a<15*60000
            || !recurringVirtualMatches(base,original,event.recurrence))
        return null;
    // A single gesture is at most two civil weeks; do not allow arbitrary
    // time-warp, missing keys or unbounded custom metadata from the UI.
    if (Math.abs(a-original)>15*86400000) return null;
    var current=Array.isArray(event.plannerOverrides) ? event.plannerOverrides : [];
    var same=function(item) {
        return item.occurrenceIndex===index && item.originalStartDate===original.toISOString();
    };
    var existing=current.find(same);
    if (!existing && current.length>=512) return null;
    if (existing && existing.startDate===a.toISOString()
            && existing.endDate===b.toISOString()) return null;
    var record={occurrenceIndex:index,originalStartDate:original.toISOString(),
        startDate:a.toISOString(),endDate:b.toISOString()};
    var next=existing ? current.map(function(item){return same(item) ? record : item;})
        : current.concat([record]);
    return Object.assign({},event,{plannerOverrides:next});
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
    return entries(event).filter(function(slot) {
        var a=valid(slot.startDate),b=valid(slot.endDate);
        return event.allDay===true ? b>now && a<=through
            : a>=now && a<=through && !slot.notified;
    }).sort(function(a,b) {return valid(a.startDate)-valid(b.startDate);})[0] || null;
}


