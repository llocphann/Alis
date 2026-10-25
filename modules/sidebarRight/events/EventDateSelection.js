// Local-civil date selection for the Weekly Planner's Add Event calendar.
// This remains separate from Repeat, which generates future occurrences.
var limit = 512;

function key(value) {
    if (!value || typeof value.getTime !== "function"
            || !Number.isFinite(value.getTime())) return "";
    var y=value.getFullYear(),m=value.getMonth()+1,d=value.getDate();
    return String(y).padStart(4,"0")+"-"+String(m).padStart(2,"0")
        +"-"+String(d).padStart(2,"0");
}
function localDate(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
    var parts=value.split("-").map(Number);
    var date=new Date(parts[0],parts[1]-1,parts[2],12,0,0,0);
    return key(date)===value ? date : null;
}
function normalized(values) {
    return (Array.isArray(values) ? values : []).filter(function(value,index,all) {
        return localDate(value)!==null && all.indexOf(value)===index;
    }).sort();
}
function range(startKey,endKey) {
    var start=localDate(startKey),end=localDate(endKey);
    if (!start || !end) return null;
    if (start.getTime()>end.getTime()) {var temp=start;start=end;end=temp;}
    var values=[];
    for (var date=new Date(start);date.getTime()<=end.getTime();date.setDate(date.getDate()+1)) {
        values.push(key(date));
        if (values.length>limit) return null;
    }
    return values;
}
// Plain click replaces selection. Ctrl toggles a day. Shift replaces with
// an inclusive range from the last anchor. Ctrl+Shift adds that range.
function choose(values,anchor,primary,clicked,ctrl,shift) {
    var selected=normalized(values);
    var nextKey=key(clicked);
    if (!nextKey) return null;
    if (!selected.length && localDate(primary)) selected=[primary];
    var active=selected.indexOf(primary)>=0 ? primary : (selected[0]||nextKey);
    var lastAnchor=selected.indexOf(anchor)>=0 ? anchor : active;
    var result;
    if (shift) {
        var inclusive=range(lastAnchor,nextKey);
        if (!inclusive) return null;
        result=ctrl ? normalized(selected.concat(inclusive)) : inclusive;
    } else if (ctrl) {
        result=selected.indexOf(nextKey)>=0
            ? selected.filter(function(value) {return value!==nextKey;})
            : normalized(selected.concat([nextKey]));
        if (!result.length) result=[nextKey]; // Never save an empty event.
    } else {
        result=[nextKey];
    }
    if (result.length>limit) return null;
    var nextPrimary=result.indexOf(nextKey)>=0 ? nextKey
        : (result.indexOf(active)>=0 ? active : result[0]);
    // Removing a different selected day must not reset the existing range
    // anchor to the first day: subsequent Shift+Click still uses the last
    // active anchor instead of selecting an unexpectedly large date span.
    var nextAnchor=shift ? lastAnchor
        : (ctrl && selected.indexOf(nextKey)>=0
            ? (result.indexOf(lastAnchor)>=0 ? lastAnchor : nextPrimary)
            : nextKey);
    return {keys:result,primary:nextPrimary,anchor:nextAnchor};
}
// Construct each occurrence at LOCAL wall-clock time to preserve DST days,
// midnight-crossing durations and all-day end-exclusive semantics.
// Follow a successful Planner drag without overwriting manually edited
// dates/times or wiping the rest of the form. The baseline is rebased only
// for untouched fields, so unrelated unsaved title/note changes remain dirty.
// In multi-date groups, read the stored slots after the drag: the old day
// may still contain another occurrence and the slot index may have changed.
function editorSlots(event,index) {
    var saved=event?.occurrences;
    if (!saved || !Number.isInteger(saved.length) || saved.length<1) return [event];
    var slots=Array.from(saved);
    var repeating=(event.recurrence || "none")!=="none";
    var template=repeating ? event.repeatTemplate : event.selectedTemplate;
    var width=template && Number.isInteger(template.length) ? template.length : 0;
    if (width<1 || width>slots.length) return slots;
    var boundary=Number(event.repeatCycleStart || 0);
    if (!Number.isInteger(boundary) || boundary<0 || boundary>=slots.length) boundary=0;
    if (!repeating) return slots.slice(-width);
    var chosen=Number.isInteger(index) && index>=0 && index<slots.length ? index : boundary;
    // Indices retain cycle identity after a drag; chronological sorting or
    // highlighting the full saved history would select unrelated weeks.
    var start=chosen<boundary ? Math.floor(chosen/width)*width
        : boundary+Math.floor((chosen-boundary)/width)*width;
    return slots.slice(start,Math.min(start+width,slots.length));
}

function rebaseDraggedEvent(draft,baseline,oldStart,newStart,newEnd,canonical) {
    var before=new Date(oldStart),after=new Date(newStart),end=new Date(newEnd);
    if (!Array.isArray(baseline) || baseline.length<11
            || !Number.isFinite(before.getTime())
            || !Number.isFinite(after.getTime())
            || !Number.isFinite(end.getTime()) || end<=after
            || !canonical) return null;
    var slots=Array.isArray(canonical.occurrences)
            && canonical.occurrences.length>0
        ? canonical.occurrences : [canonical];
    var occurrenceIndex=slots.findIndex(function(slot) {
        return Number(new Date(slot.startDate || slot.dateTime))===after.getTime()
            && Number(new Date(slot.endDate))===end.getTime();
    });
    if (occurrenceIndex<0) return null;
    var updatedDays=normalized(editorSlots(canonical,occurrenceIndex).map(function(slot) {
        return key(new Date(slot.startDate || slot.dateTime));
    }));
    var nextKey=key(after);
    if (!nextKey || updatedDays.indexOf(nextKey)<0) return null;
    var wasDateClean=Number(new Date(draft.date))===Number(baseline[2]);
    var wasKeysClean=JSON.stringify(normalized(draft.keys))
        ===JSON.stringify(normalized(baseline[10]));
    var dateFollowed=wasDateClean && wasKeysClean;
    var timeClean=draft.time===baseline[3];
    var endClean=draft.endTime===baseline[4];
    function clock(date) {
        return String(date.getHours()).padStart(2,"0")+":"
            +String(date.getMinutes()).padStart(2,"0");
    }
    var nextDate=dateFollowed ? after : draft.date;
    var nextKeys=dateFollowed ? updatedDays : draft.keys;
    var nextAnchor=dateFollowed ? nextKey : draft.anchor;
    var nextTime=timeClean ? clock(after) : draft.time;
    var nextEnd=endClean ? clock(end) : draft.endTime;
    var newBaseline=baseline.slice();
    if (dateFollowed) {
        newBaseline[2]=after.getTime();
        newBaseline[10]=updatedDays.slice();
    }
    if (timeClean) newBaseline[3]=nextTime;
    if (endClean) newBaseline[4]=nextEnd;
    return {date:nextDate,keys:nextKeys,anchor:nextAnchor,
        time:nextTime,endTime:nextEnd,baseline:newBaseline,
        dateFollowed:dateFollowed,occurrenceIndex:occurrenceIndex};
}

function ranges(values,startTime,endTime,allDay) {
    var days=normalized(values);
    if (days.length<2 || days.length>limit) return null;
    function minutes(value) {
        var match=/^(\d{1,2}):(\d{2})$/.exec(String(value));
        if (!match) return null;
        var h=Number(match[1]),m=Number(match[2]);
        return h<24 && m<60 ? h*60+m : null;
    }
    var startMin=minutes(startTime),endMin=minutes(endTime);
    if (!allDay && (startMin===null || endMin===null)) return null;
    var output=[];
    for (var i=0;i<days.length;i++) {
        var date=localDate(days[i]);
        if (!date) return null;
        var from=new Date(date.getFullYear(),date.getMonth(),date.getDate());
        var to=new Date(from);
        if (allDay) {
            to.setDate(to.getDate()+1);
        } else {
            from.setHours(Math.floor(startMin/60),startMin%60,0,0);
            to.setHours(Math.floor(endMin/60),endMin%60,0,0);
            if (to<=from) to.setDate(to.getDate()+1);
        }
        if (!(to>from)) return null;
        output.push({startDate:from.toISOString(),endDate:to.toISOString()});
    }
    return output;
}
