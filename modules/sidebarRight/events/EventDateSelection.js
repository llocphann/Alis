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
    var nextPrimary=result.indexOf(nextKey)>=0 ? nextKey : result[0];
    var nextAnchor=shift ? lastAnchor
        : (ctrl && selected.indexOf(nextKey)>=0 ? nextPrimary : nextKey);
    return {keys:result,primary:nextPrimary,anchor:nextAnchor};
}
// Construct each occurrence at LOCAL wall-clock time to preserve DST days,
// midnight-crossing durations and all-day end-exclusive semantics.
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
