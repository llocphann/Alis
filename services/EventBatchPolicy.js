// Pure atomic planner batch edits. No list mutation, signals or writes here.
// Operations address the ORIGINAL stable Event ID + occurrence index.
function apply(events,operations,occurrences,futureSchedule,nowValue) {
    if (!Array.isArray(events) || !Array.isArray(operations)
            || operations.length<1 || operations.length>512
            || !occurrences || typeof occurrences.entries!=="function") return null;
    const changes=new Map();
    const byId=new Map();
    for (const event of events) {
        if (!event || event.id===undefined || byId.has(event.id)) return null;
        byId.set(event.id,event);
    }
    if (operations.some(op=>op?.future===true)) {
        if (!futureSchedule || typeof futureSchedule.apply!=="function") return null;
        const groups=new Map(),remaining=[];
        for (const op of operations) {
            if (!op || !byId.has(op.id)) return null;
            if (op.future!==true) {remaining.push(op);continue;}
            if (!groups.has(op.id)) groups.set(op.id,[]);
            groups.get(op.id).push(op);
        }
        // One Event cannot have two different edit scopes in one transaction.
        if (remaining.some(op=>groups.has(op.id))) return null;
        const replacements=new Map();
        for (const [id,changes] of groups) {
            const updated=futureSchedule.apply(byId.get(id),changes,
                nowValue===undefined ? Date.now() : nowValue);
            if (!updated) return null;
            replacements.set(id,Array.isArray(updated.occurrences)
                ? occurrences.store(updated,updated.occurrences) : updated);
        }
        const staged=events.map(event=>replacements.get(event.id) || event);
        const result=remaining.length ? apply(staged,remaining,occurrences)
            : {list:staged,updated:[],removed:[]};
        if (!result) return null;
        return {list:result.list,removed:result.removed,
            updated:result.updated.concat(Array.from(replacements.values()))};
    }
    if (operations.some(op=>op && byId.has(op.id)
            && (byId.get(op.id).recurrence || "none")!=="none"))
        return applyRecurring(events,operations,occurrences,byId);
    for (const op of operations) {
        if (!op || !Number.isInteger(op.occurrenceIndex)
                || op.occurrenceIndex<0 || !byId.has(op.id)) return null;
        const event=byId.get(op.id);
        // Imported and repeating events must never be batch-mutated.
        if ((event.recurrence || "none")!=="none") return null;
        const slots=occurrences.entries(event);
        if (op.occurrenceIndex>=slots.length) return null;
        const key=String(op.id)+":"+op.occurrenceIndex;
        if (changes.has(key)) return null;
        if (op.remove===true) {
            changes.set(key,{remove:true});
        } else {
            const start=new Date(op.startIso),end=new Date(op.endIso);
            if (!Number.isFinite(start.getTime())
                    || !Number.isFinite(end.getTime())
                    || end-start<15*60000) return null;
            changes.set(key,{startDate:start.toISOString(),
                endDate:end.toISOString()});
        }
    }
    const updated=[],removed=[];
    const result=events.map(function(event) {
        const prefix=String(event.id)+":";
        if (!operations.some(op=>op.id===event.id)) return event;
        const slots=occurrences.entries(event);
        const next=[];
        for (let i=0;i<slots.length;i++) {
            const op=changes.get(prefix+i);
            if (op?.remove===true) continue;
            next.push(op
                ? Object.assign({},slots[i],{startDate:op.startDate,endDate:op.endDate,
                    notified:false,reminderNotified:false})
                : slots[i]);
            if (op && Object.prototype.hasOwnProperty.call(slots[i],"dateTime"))
                next[next.length-1].dateTime=op.startDate;
        }
        if (!next.length) {
            removed.push(event.id);
            return null;
        }
        const distinct=new Set(next.map(slot=>slot.startDate+"|"+slot.endDate));
        if (distinct.size!==next.length) return null;
        const replacement=occurrences.store(event,next);
        updated.push(replacement);
        return replacement;
    });
    // A null is only valid for a fully deleted Event ID. This check is
    // separate from the pure map so a failed batch never emits any writes.
    if (result.some((event,i)=>event===null && !removed.includes(events[i].id)))
        return null;
    // Distinguish a valid removed ID from invalid duplicate ranges.
    if (updated.length+removed.length!==new Set(operations.map(op=>op.id)).size)
        return null;
    return {list:result.filter(event=>event!==null),updated:updated,removed:removed};
}

// Explicit instance edits only. Build every result in memory before the
// Events service emits signals or performs its single durable write.
function applyRecurring(events,operations,occurrences,byId) {
    const working=new Map(byId),seen=new Set(),changed=new Set(),ordinary=[];
    for (const op of operations) {
        if (!op || !byId.has(op.id) || !Number.isInteger(op.occurrenceIndex)
                || op.occurrenceIndex<0) return null;
        const event=working.get(op.id);
        if ((event.recurrence || "none")==="none") {ordinary.push(op);continue;}
        // Legacy callers cannot accidentally start batch-editing series.
        // Delete remains unavailable until an explicit series policy exists.
        if (op.recurring!==true || op.remove===true) return null;
        const identity=JSON.stringify([op.id,op.occurrenceIndex,op.originalStartIso || "saved"]);
        if (seen.has(identity)) return null;
        seen.add(identity);
        const updated=op.originalStartIso!==undefined
            ? occurrences.rescheduleProjectedRecurring(event,op.occurrenceIndex,
                op.originalStartIso,op.startIso,op.endIso)
            : occurrences.rescheduleSavedRecurring(event,op.occurrenceIndex,op.startIso,op.endIso);
        if (!updated) return null;
        working.set(op.id,updated);changed.add(op.id);
    }
    const staged=events.map(event=>working.get(event.id));
    const result=ordinary.length ? apply(staged,ordinary,occurrences)
        : {list:staged,updated:[],removed:[]};
    if (!result) return null;
    return {list:result.list,removed:result.removed,
        updated:result.updated.concat(result.list.filter(event=>changed.has(event.id)))};
}
