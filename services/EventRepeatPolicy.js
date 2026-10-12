// Civil-calendar compatibility and next-cycle generation for multi-date Agenda.
// A group recurs as one weekly/monthly/yearly pattern; not separate event IDs.
function date(value) {
    var v=new Date(value);
    return Number.isFinite(v.getTime()) ? v : null;
}
function key(value) {
    var d=date(value);
    return d ? String(d.getFullYear()).padStart(4,"0")+"-"
        +String(d.getMonth()+1).padStart(2,"0")+"-"
        +String(d.getDate()).padStart(2,"0") : "";
}
function allowed(keys,mode) {
    if (["none","daily","weekly","monthly","yearly"].indexOf(mode)<0) return false;
    if (!Array.isArray(keys) || !keys.length) return mode==="none";
    var dates=keys.map(function(value) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
        var fields=value.split("-").map(Number);
        var d=new Date(fields[0],fields[1]-1,fields[2],12);
        return key(d)===value ? d : null;
    });
    if (dates.some(function(d){return !d;})) return false;
    if (mode==="none" || dates.length===1) return true;
    if (mode==="daily") return false;
    var first=dates[0];
    if (mode==="yearly") return dates.every(function(d) {
        return d.getFullYear()===first.getFullYear();
    });
    if (mode==="monthly") return dates.every(function(d) {
        return d.getFullYear()===first.getFullYear()
            && d.getMonth()===first.getMonth();
    });
    function weekStart(d) {
        var monday=new Date(d.getFullYear(),d.getMonth(),d.getDate(),12);
        monday.setDate(monday.getDate()-(monday.getDay()+6)%7);
        return key(monday);
    }
    return dates.every(function(d){return weekStart(d)===weekStart(first);});
}
function templateAllowed(slots,mode) {
    if (!Array.isArray(slots) || slots.length<2 || slots.length>512) return false;
    var keys=slots.map(function(slot){return key(slot?.startDate);});
    return new Set(keys).size===keys.length && allowed(keys,mode);
}
// Rebuild from immutable original template, avoiding drift on short months
// and leap years. Skip invalid calendar dates rather than overflowing.
function nextCycle(template,mode,afterTime) {
    if (!templateAllowed(template,mode) || ["none","daily"].includes(mode)) return null;
    var starts=template.map(function(slot){return date(slot.startDate);});
    var ends=template.map(function(slot){return date(slot.endDate);});
    var now=date(afterTime);
    if (!now || starts.some(function(d){return !d;})
        || ends.some(function(d,i){return !d || d<=starts[i];})) return null;
    var first=starts[0],step;
    if (mode==="weekly") {
        var days=Math.floor((Date.UTC(now.getFullYear(),now.getMonth(),now.getDate())
            -Date.UTC(first.getFullYear(),first.getMonth(),first.getDate()))/86400000);
        step=Math.max(1,Math.floor(days/7));
    } else if (mode==="monthly") {
        step=Math.max(1,12*(now.getFullYear()-first.getFullYear())
            +now.getMonth()-first.getMonth());
    } else step=Math.max(1,now.getFullYear()-first.getFullYear());
    function startAt(base,k) {
        var y=base.getFullYear(),m=base.getMonth(),d=base.getDate();
        if (mode==="weekly") {
            var target=new Date(y,m,d,12);
            target.setDate(target.getDate()+7*k);
            y=target.getFullYear();m=target.getMonth();d=target.getDate();
        } else if (mode==="monthly") {
            var month=new Date(y,m+k,1,12);
            y=month.getFullYear();m=month.getMonth();
        } else y+=k;
        var result=new Date(y,m,d,base.getHours(),base.getMinutes(),
            base.getSeconds(),base.getMilliseconds());
        return result.getFullYear()===y && result.getMonth()===m
            && result.getDate()===d ? result : null;
    }
    function endAt(begin,end,moved) {
        var dayStart=Date.UTC(begin.getFullYear(),begin.getMonth(),begin.getDate())/86400000;
        var dayEnd=Date.UTC(end.getFullYear(),end.getMonth(),end.getDate())/86400000;
        return new Date(moved.getFullYear(),moved.getMonth(),moved.getDate()+dayEnd-dayStart,
            end.getHours(),end.getMinutes(),end.getSeconds(),end.getMilliseconds());
    }
    for (var attempt=0;attempt<36;attempt++,step++) {
        var result=[];
        for (var i=0;i<template.length;i++) {
            var begin=startAt(starts[i],step);
            if (!begin) continue;
            var finish=endAt(starts[i],ends[i],begin);
            if (finish<=begin) continue;
            result.push({startDate:begin.toISOString(),endDate:finish.toISOString(),
                notified:false,reminderNotified:false});
        }
        result.sort(function(a,b){return a.startDate.localeCompare(b.startDate);});
        if (result.length && new Date(result[0].startDate)>now) return result;
    }
    return null;
}
