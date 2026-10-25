// Versioned, copy-on-write "this and following" rules for one recurrence branch.
// Saved history and the original template remain the rollback/source anchors.
var dayMs = 86400000;
function date(value) {
    var result = new Date(value);
    return Number.isFinite(result.getTime()) ? result : null;
}
function civil(value) {
    return Date.UTC(value.getFullYear(), value.getMonth(), value.getDate());
}
function clock(value) {
    return [value.getHours(), value.getMinutes(), value.getSeconds(), value.getMilliseconds()];
}
function supported(mode) {
    return ["daily", "weekly", "monthly", "yearly"].includes(mode);
}
function slots(event) {
    return Array.isArray(event.occurrences) && event.occurrences.length
        ? event.occurrences : [event];
}
function anchor(slot) {
    var start = date(slot.plannerSeriesStartDate || slot.startDate || slot.dateTime);
    var end = date(slot.plannerSeriesEndDate || slot.endDate);
    if (!start) return null;
    if (!end || end <= start) end = new Date(start.getTime() + 3600000);
    return {start:start, end:end};
}
function signature(mode, start, end) {
    return JSON.stringify([mode, mode === "daily" ? 0
        : mode === "weekly" ? start.getDay()
        : mode === "monthly" ? start.getDate() : [start.getMonth(), start.getDate()],
        clock(start), (civil(end) - civil(start)) / dayMs, clock(end)]);
}
function validRule(rule) {
    return rule && rule.version === 1 && supported(rule.mode)
        && typeof rule.key === "string" && rule.key.length > 0
        && Number.isSafeInteger(rule.fromCycle)
        && Number.isSafeInteger(rule.anchorCycle)
        && !!date(rule.rootStartDate) && !!date(rule.rootEndDate)
        && !!date(rule.startDate) && !!date(rule.endDate)
        && date(rule.endDate) - date(rule.startDate) >= 15 * 60000;
}
function rules(event) {
    return Array.isArray(event.plannerFutureSchedule)
        ? event.plannerFutureSchedule.filter(function(rule) {
            return validRule(rule) && rule.mode === event.recurrence;
        }) : [];
}
function has(event) {
    return supported(event.recurrence) && rules(event).length > 0;
}
function cycleOf(start, value, mode) {
    if (mode === "daily" || mode === "weekly")
        return Math.floor((civil(value) - civil(start)) / dayMs / (mode === "daily" ? 1 : 7));
    if (mode === "monthly")
        return 12 * (value.getFullYear() - start.getFullYear()) + value.getMonth() - start.getMonth();
    return value.getFullYear() - start.getFullYear();
}
function cycleIndex(value, mode) {
    if (mode==="daily") return civil(value)/dayMs;
    if (mode==="weekly") return Math.floor((civil(value)/dayMs-4)/7);
    if (mode==="monthly") return value.getFullYear()*12+value.getMonth();
    return value.getFullYear();
}
function rootRange(info, mode, cycle) {
    return at(info.rootStartDate,info.rootEndDate,mode,
        cycle-cycleIndex(date(info.rootStartDate),mode));
}
// Use calendar arithmetic; do not turn a DST transition into a clock shift.
// Missing month days / leap dates are skipped, never overflowed into March.
function at(startValue, endValue, mode, step) {
    var start = date(startValue), end = date(endValue);
    if (!start || !end || end <= start || !Number.isInteger(step)) return null;
    var year = start.getFullYear(), month = start.getMonth(), day = start.getDate();
    if (mode === "daily" || mode === "weekly") {
        var moved = new Date(year, month, day + step * (mode === "daily" ? 1 : 7), 12);
        year = moved.getFullYear(); month = moved.getMonth(); day = moved.getDate();
    } else if (mode === "monthly") {
        var target = new Date(year, month + step, 1, 12);
        year = target.getFullYear(); month = target.getMonth();
    } else if (mode === "yearly") year += step;
    else return null;
    var begin = new Date(year, month, day, start.getHours(), start.getMinutes(),
        start.getSeconds(), start.getMilliseconds());
    if (begin.getFullYear() !== year || begin.getMonth() !== month || begin.getDate() !== day)
        return null;
    var finish = new Date(year, month, day + (civil(end) - civil(start)) / dayMs,
        end.getHours(), end.getMinutes(), end.getSeconds(), end.getMilliseconds());
    return finish > begin ? {startDate:begin.toISOString(), endDate:finish.toISOString()} : null;
}
function branch(event, index) {
    var entries = slots(event), slot = entries[index], range = slot && anchor(slot);
    if (!range || !supported(event.recurrence)) return null;
    var key = slot.plannerBranchKey || signature(event.recurrence, range.start, range.end);
    var known = rules(event).find(function(rule) { return rule.key === key; });
    if (known) return {key:key, rootStartDate:known.rootStartDate, rootEndDate:known.rootEndDate};
    var candidates = entries.concat(Array.isArray(event.repeatTemplate) ? event.repeatTemplate : [],
        Array.isArray(event.selectedTemplate) ? event.selectedTemplate : []);
    candidates.forEach(function(candidate) {
        var other = anchor(candidate);
        if (other && signature(event.recurrence, other.start, other.end) === key
                && other.start < range.start) range = other;
    });
    return {key:key, rootStartDate:range.start.toISOString(), rootEndDate:range.end.toISOString()};
}
function resolved(event, info, cycle) {
    var selected = null;
    rules(event).forEach(function(rule) {
        if (rule.key === info.key && rule.fromCycle <= cycle) selected = rule;
    });
    return selected ? at(selected.startDate, selected.endDate, event.recurrence,
        cycle - selected.anchorCycle)
        : rootRange(info,event.recurrence,cycle);
}
function cycleForSlot(event, index, info) {
    var slot = slots(event)[index];
    return Number.isInteger(slot.plannerScheduleCycle) ? slot.plannerScheduleCycle
        : cycleIndex(anchor(slot).start,event.recurrence);
}
function branches(event) {
    var found = new Map(), entries=slots(event);
    var first=Array.isArray(event.repeatTemplate) && event.repeatTemplate.length
        ? Math.max(0,Number(event.repeatCycleStart) || 0)
        : Array.isArray(event.selectedTemplate) && event.selectedTemplate.length
            ? Math.max(0,entries.length-event.selectedTemplate.length) : 0;
    slots(event).forEach(function(slot, index) {
        if (index<first) return;
        var info = branch(event, index);
        if (!info) return;
        var cycle = cycleForSlot(event, index, info), previous = found.get(info.key);
        if (!previous || cycle >= previous.cycle)
            found.set(info.key, Object.assign({}, info, {index:index, cycle:cycle}));
    });
    return Array.from(found.values());
}
function futureCycle(event, info, now) {
    var sources=[{startDate:info.rootStartDate,
        anchorCycle:cycleIndex(date(info.rootStartDate),event.recurrence)}]
        .concat(rules(event).filter(function(rule) { return rule.key===info.key; }));
    var guess=Math.min.apply(null,sources.map(function(rule) {
        return rule.anchorCycle+cycleOf(date(rule.startDate),now,event.recurrence)-3;
    }));
    for (var i = 0; i < 64; i++, guess++) {
        var range = resolved(event, info, guess);
        if (range && date(range.startDate) >= now) return guess;
    }
    return null;
}
function sameRange(a, b) {
    return !!a && !!b && date(a.startDate).getTime() === date(b.startDate).getTime()
        && date(a.endDate).getTime() === date(b.endDate).getTime();
}
function pendingOverride(event, info, cycle) {
    var original=rootRange(info,event.recurrence,cycle);
    if (!original || !Array.isArray(event.plannerOverrides)) return null;
    return event.plannerOverrides.find(function(item) {
        var source=Number.isInteger(item.occurrenceIndex) && branch(event,item.occurrenceIndex);
        var start=date(item.startDate),end=date(item.endDate);
        return source && source.key===info.key && item.originalStartDate===original.startDate
            && item.materializedOccurrenceIndex===undefined && item.forwardedEventId===undefined
            && start && end && end-start>=15*60000;
    }) || null;
}
function wall(value) {
    var d=date(value);
    return d ? civil(d)+d.getHours()*3600000+d.getMinutes()*60000
        +d.getSeconds()*1000+d.getMilliseconds() : NaN;
}
function shifted(value, delta) {
    var utc=new Date(wall(value)+delta);
    return new Date(utc.getUTCFullYear(),utc.getUTCMonth(),utc.getUTCDate(),
        utc.getUTCHours(),utc.getUTCMinutes(),utc.getUTCSeconds(),utc.getUTCMilliseconds()).toISOString();
}
// All operations address the pre-edit snapshot. Multiple selected dates of one
// daily/weekly branch must not compound the same shift or append duplicate rules.
function apply(event, operations, nowValue) {
    var now = date(nowValue), existing = event.plannerFutureSchedule;
    if (!now || !supported(event.recurrence) || !Array.isArray(operations)
            || !operations.length || existing !== undefined && (!Array.isArray(existing)
                || existing.some(function(rule) { return !validRule(rule); }))) return null;
    var grouped = new Map(), seen = new Set(), explicit = new Map();
    for (var op of operations) {
        if (!op || op.remove === true || op.future !== true || op.recurring !== true
                || !Number.isInteger(op.occurrenceIndex) || op.occurrenceIndex < 0
                || op.occurrenceIndex >= slots(event).length) return null;
        var info = branch(event, op.occurrenceIndex);
        if (!info || op.branchKey !== undefined && op.branchKey !== info.key) return null;
        var cycle = Number.isInteger(op.cycle) ? op.cycle
            : op.originalStartIso && date(op.originalStartIso)
                ? cycleIndex(date(op.originalStartIso),event.recurrence)
            : cycleForSlot(event, op.occurrenceIndex, info);
        if (!Number.isSafeInteger(cycle)) return null;
        var identity = JSON.stringify([info.key, cycle]);
        if (seen.has(identity)) return null;
        seen.add(identity);
        var before = op.originalStartIso ? pendingOverride(event,info,cycle)
            || resolved(event, info, cycle) : {
            startDate:slots(event)[op.occurrenceIndex].startDate || slots(event)[op.occurrenceIndex].dateTime,
            endDate:slots(event)[op.occurrenceIndex].endDate || anchor(slots(event)[op.occurrenceIndex]).end.toISOString()
        };
        var start = date(op.startIso), end = date(op.endIso);
        if (!before || !start || !end || end - start < 15 * 60000
                || Math.abs(start - date(before.startDate)) > 15 * dayMs) return null;
        if (op.previousStartIso && date(op.previousStartIso)?.getTime() !== date(before.startDate).getTime()) return null;
        var change = Object.assign({}, info, {cycle:cycle, index:op.occurrenceIndex,
            startDate:start.toISOString(), endDate:end.toISOString(), before:before});
        var prior = grouped.get(info.key);
        if (prior) {
            var early = prior.cycle <= cycle ? prior : change;
            var later = early === prior ? change : prior;
            if (!sameRange(at(early.startDate, early.endDate, event.recurrence,
                    later.cycle - early.cycle), later)) return null;
            grouped.set(info.key, early);
        } else grouped.set(info.key, change);
        if (!op.originalStartIso) explicit.set(op.occurrenceIndex, change);
    }
    var nextRules = (existing || []).slice();
    for (var change of grouped.values()) {
        var firstFuture = futureCycle(event, change, now);
        if (firstFuture === null || nextRules.length >= 512) return null;
        var record = {version:1, mode:event.recurrence, key:change.key,
            rootStartDate:change.rootStartDate, rootEndDate:change.rootEndDate,
            fromCycle:Math.max(change.cycle, firstFuture), anchorCycle:change.cycle,
            startDate:change.startDate, endDate:change.endDate};
        // Retrying the same gesture is safe; do not multiply schedule segments.
        var last = nextRules[nextRules.length - 1];
        if (JSON.stringify(last) !== JSON.stringify(record)) nextRules.push(record);
    }
    var updated = Object.assign({}, event, {plannerFutureSchedule:nextRules});
    if (Array.isArray(event.plannerOverrides)) {
        var invalid=false;
        updated.plannerOverrides=event.plannerOverrides.map(function(item) {
            var info=Number.isInteger(item.occurrenceIndex) && branch(event,item.occurrenceIndex);
            var change=info && grouped.get(info.key),original=date(item.originalStartDate);
            if (!change || !original || item.materializedOccurrenceIndex!==undefined
                    || item.forwardedEventId!==undefined) return item;
            var cycle=cycleIndex(original,event.recurrence);
            var rule=nextRules.slice().reverse().find(function(record) { return record.key===info.key; });
            if (cycle<rule.fromCycle || date(item.startDate)<now) return item;
            if (!date(item.startDate) || !date(item.endDate)) return item;
            var start=shifted(item.startDate,wall(change.startDate)-wall(change.before.startDate));
            var end=shifted(item.endDate,wall(change.endDate)-wall(change.before.endDate));
            if (date(end)-date(start)<15*60000) {invalid=true;return item;}
            return Object.assign({},item,{startDate:start,endDate:end});
        });
        if (invalid) return null;
    }
    var replacements = slots(event).map(function(slot, index) {
        var info = branch(event, index), chosen = explicit.get(index);
        if (!info || !grouped.has(info.key)) return slot;
        var cycle = cycleForSlot(event, index, info);
        var first = nextRules.slice().reverse().find(function(rule) { return rule.key === info.key; });
        var start = date(slot.startDate || slot.dateTime);
        // Directly edited history is explicit; no other past/notified slot is backfilled.
        if (!chosen && (slot.notified === true || start < now || cycle < first.fromCycle)) return slot;
        var range = chosen || resolved(updated, info, cycle);
        if (!range) return slot;
        var original = rootRange(info,event.recurrence,cycle)
            || {startDate:start.toISOString(), endDate:anchor(slot).end.toISOString()};
        var replacement = Object.assign({}, slot, {startDate:range.startDate, endDate:range.endDate,
            plannerSeriesStartDate:slot.plannerSeriesStartDate || original.startDate,
            plannerSeriesEndDate:slot.plannerSeriesEndDate || original.endDate,
            plannerBranchKey:info.key, plannerScheduleCycle:cycle});
        if (Object.prototype.hasOwnProperty.call(slot, "dateTime")) replacement.dateTime = replacement.startDate;
        return replacement;
    });
    if (Array.isArray(event.occurrences) && event.occurrences.length)
        updated.occurrences = replacements;
    else {
        var overrides=updated.plannerOverrides;
        updated=Object.assign({},replacements[0],{plannerFutureSchedule:nextRules,
            dateTime:replacements[0].startDate});
        if (Array.isArray(event.plannerOverrides)) updated.plannerOverrides=overrides;
    }
    return updated;
}
// Include saved ranges exactly once, then project only the latest branch cycle.
// A branch uses its own clock, allowing Tue 17:00 and Thu 18:30 under one Event ID.
function project(event, beginValue, endValue) {
    var begin = date(beginValue), end = date(endValue), result = [], saved = new Set();
    if (!begin || !end) return result;
    slots(event).forEach(function(slot, index) {
        var info = branch(event, index), start = date(slot.startDate || slot.dateTime), finish = date(slot.endDate);
        if (!info || !start) return;
        if (!finish || finish <= start) finish = new Date(start.getTime() + 3600000);
        var cycle = cycleForSlot(event, index, info);
        saved.add(JSON.stringify([info.key, cycle]));
        if (start < end && finish > begin) result.push({startDate:start.toISOString(), endDate:finish.toISOString(),
            occurrenceIndex:index, virtual:false, branchKey:info.key, cycle:cycle, originalStartIso:""});
    });
    // Legacy separate-ID recurrence has already handed responsibility to its
    // child after firing. Its saved history must not project a second series.
    if (!Array.isArray(event.occurrences) && event.notified===true) return result;
    branches(event).forEach(function(info) {
        var candidates = new Set(), sources = [{startDate:info.rootStartDate,
            anchorCycle:cycleIndex(date(info.rootStartDate),event.recurrence)}]
            .concat(rules(event).filter(function(rule) { return rule.key === info.key; }));
        sources.forEach(function(rule) {
            var first = rule.anchorCycle + cycleOf(date(rule.startDate), begin, event.recurrence) - 3;
            var last = rule.anchorCycle + cycleOf(date(rule.startDate), end, event.recurrence) + 3;
            for (var cycle = first; cycle <= last && candidates.size < 1024; cycle++) candidates.add(cycle);
        });
        Array.from(candidates).sort(function(a,b) { return a-b; }).forEach(function(cycle) {
            if (cycle <= info.cycle || saved.has(JSON.stringify([info.key, cycle]))) return;
            var range = pendingOverride(event,info,cycle) || resolved(event, info, cycle);
            if (!range || date(range.startDate) >= end || date(range.endDate) <= begin) return;
            var original = rootRange(info,event.recurrence,cycle);
            result.push(Object.assign({}, range, {occurrenceIndex:info.index, virtual:true,
                branchKey:info.key, cycle:cycle, originalStartIso:original?.startDate || range.startDate}));
        });
    });
    return result;
}
function nextCycle(event, nowValue) {
    var now = date(nowValue), streams = branches(event);
    if (!now || !streams.length) return null;
    var cycle = Math.max.apply(null, streams.map(function(info) {
        var future = futureCycle(event, info, now);
        return future === null ? Infinity : Math.max(info.cycle + 1, future);
    }));
    if (!Number.isFinite(cycle)) return null;
    for (var attempt = 0; attempt < 36; attempt++, cycle++) {
        var result = [];
        streams.forEach(function(info) {
            var range = resolved(event, info, cycle);
            if (!range) return;
            var original = rootRange(info,event.recurrence,cycle) || range;
            result.push(Object.assign({}, range, {notified:false, reminderNotified:false,
                plannerSeriesStartDate:original.startDate, plannerSeriesEndDate:original.endDate,
                plannerBranchKey:info.key, plannerScheduleCycle:cycle}));
        });
        if (result.length && result.every(function(slot) { return date(slot.startDate) > now; }))
            return result.sort(function(a,b) { return date(a.startDate)-date(b.startDate); });
    }
    return null;
}
