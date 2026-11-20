var MONTH_NAMES = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
];

var KIND_PLAN = "plan";
var KIND_TRIP = "trip";
var KIND_MILESTONE = "milestone";

function _pad2(value) {
    var s = String(Math.floor(value));
    return s.length < 2 ? "0" + s : s;
}

function _isValidDate(d) {
    return !!d && typeof d.getTime === "function" && typeof d.getFullYear === "function" && !isNaN(d.getTime());
}

function toIsoDate(date) {
    if (typeof date === "string") {
        var direct = /^(\d{4}-\d{2}-\d{2})$/.exec(date.trim());
        if (direct) return direct[1];
        var parsedStr = new Date(date);
        if (!isNaN(parsedStr.getTime()))
            date = parsedStr;
        else
            return "";
    }
    if (!_isValidDate(date))
        return "";
    return date.getFullYear() + "-" + _pad2(date.getMonth() + 1) + "-" + _pad2(date.getDate());
}

function parseIsoDate(iso) {
    if (typeof iso !== "string") return null;
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso.trim());
    if (!m) return null;
    var y = parseInt(m[1], 10);
    var mo = parseInt(m[2], 10);
    var d = parseInt(m[3], 10);
    var dt = new Date(y, mo - 1, d, 0, 0, 0, 0);
    if (dt.getFullYear() !== y || dt.getMonth() !== mo - 1 || dt.getDate() !== d)
        return null;
    return dt;
}

function daysInMonth(year, monthIndex) {
    return new Date(year, monthIndex + 1, 0).getDate();
}

function addDaysIso(iso, deltaDays) {
    var base = parseIsoDate(iso);
    if (!base) return "";
    var dt = new Date(base.getFullYear(), base.getMonth(), base.getDate() + Math.round(deltaDays || 0), 0, 0, 0, 0);
    return toIsoDate(dt);
}

function diffDaysIso(aIso, bIso) {
    var a = parseIsoDate(aIso);
    var b = parseIsoDate(bIso);
    if (!a || !b) return 0;
    var utcA = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
    var utcB = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
    return Math.round((utcB - utcA) / 86400000);
}

function buildMonthMatrix(anchorDate, mode, todayIso) {
    var anchor = _isValidDate(anchorDate)
        ? anchorDate
        : (typeof anchorDate === "string" && !isNaN(new Date(anchorDate).getTime()) ? new Date(anchorDate) : new Date());
    var normalizedMode = String(mode || "calendar").toLowerCase() === "rolling" ? "rolling" : "calendar";
    var today = parseIsoDate(todayIso) ? todayIso : toIsoDate(new Date());

    var baseYear = anchor.getFullYear();
    var baseMonth = normalizedMode === "rolling" ? anchor.getMonth() : 0;
    var months = [];

    for (var i = 0; i < 12; i++) {
        var totalMonth = baseYear * 12 + baseMonth + i;
        var y = Math.floor(totalMonth / 12);
        var mIdx = ((totalMonth % 12) + 12) % 12;
        var dim = daysInMonth(y, mIdx);
        var key = y + "-" + _pad2(mIdx + 1);
        var startIso = key + "-01";
        var endIso = key + "-" + _pad2(dim);
        var shortLabel = MONTH_NAMES[mIdx];
        var label = (normalizedMode === "rolling" && (i === 0 || mIdx === 0))
            ? shortLabel + " " + String(y).slice(-2)
            : shortLabel;

        var days = [];
        for (var d = 1; d <= dim; d++) {
            var dt = new Date(y, mIdx, d, 0, 0, 0, 0);
            var wd = dt.getDay();
            var iso = key + "-" + _pad2(d);
            days.push({
                day: d,
                iso: iso,
                weekday: wd,
                isWeekend: wd === 0 || wd === 6,
                isToday: iso === today,
                isPast: iso < today
            });
        }

        months.push({
            index: i,
            year: y,
            monthIndex: mIdx,
            key: key,
            label: label,
            shortLabel: shortLabel,
            daysInMonth: dim,
            startIso: startIso,
            endIso: endIso,
            days: days
        });
    }
    return months;
}

function normalizeChecklist(items) {
    if (!Array.isArray(items)) return [];
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (!item || typeof item !== "object") continue;
        var text = String(item.text || "").trim();
        if (!text.length) continue;
        out.push({ text: text, done: item.done === true });
    }
    return out;
}

function normalizeEventSpan(event, todayIso) {
    if (!event || typeof event !== "object") return null;
    var slots = Array.isArray(event.occurrences) && event.occurrences.length > 0
        ? event.occurrences
        : [event];
    var primary = slots[0] || event;
    var startRaw = primary.startDate || primary.dateTime || event.startDate || event.dateTime;
    var endRaw = primary.endDate || event.endDate;
    if (!startRaw) return null;

    var startDt = new Date(startRaw);
    if (isNaN(startDt.getTime())) return null;
    var startIso = toIsoDate(startDt);

    var endIso = startIso;
    if (endRaw) {
        var endDt = new Date(endRaw);
        if (!isNaN(endDt.getTime()) && endDt.getTime() > startDt.getTime()) {
            var endCivil = toIsoDate(endDt);
            // Exclusive midnight end (00:00:00.000 of next day) maps back to previous inclusive civil day.
            if (endDt.getHours() === 0 && endDt.getMinutes() === 0 && endDt.getSeconds() === 0 && endDt.getMilliseconds() === 0) {
                var prevDay = addDaysIso(endCivil, -1);
                endIso = prevDay >= startIso ? prevDay : startIso;
            } else {
                endIso = endCivil >= startIso ? endCivil : startIso;
            }
        }
    }

    var rawKind = String(event.plannerKind || "").toLowerCase();
    var kind = (rawKind === KIND_TRIP || rawKind === KIND_MILESTONE || rawKind === KIND_PLAN)
        ? rawKind
        : (String(event.category || "").toLowerCase() === "travel" ? KIND_TRIP : KIND_PLAN);

    var checklist = normalizeChecklist(event.checklist);
    var doneCount = 0;
    for (var i = 0; i < checklist.length; i++) {
        if (checklist[i].done) doneCount++;
    }

    var today = parseIsoDate(todayIso) ? todayIso : toIsoDate(new Date());
    var dayCount = Math.max(1, diffDaysIso(startIso, endIso) + 1);

    return {
        id: event.id,
        title: String(event.title || "").trim() || "Untitled",
        startIso: startIso,
        endIso: endIso,
        dayCount: dayCount,
        kind: kind,
        place: String(event.place || "").trim(),
        notes: String(event.description || ""),
        color: String(event.color || "").trim(),
        checklist: checklist,
        checklistDone: doneCount,
        checklistTotal: checklist.length,
        allDay: event.allDay === true,
        isPast: endIso < today,
        isOngoing: startIso <= today && endIso >= today,
        isUpcoming: startIso > today,
        sourceEvent: event
    };
}

function matchesSearch(span, searchQuery) {
    var q = String(searchQuery || "").trim().toLowerCase();
    if (!q.length) return true;
    if (span.title.toLowerCase().indexOf(q) >= 0) return true;
    if (span.place.toLowerCase().indexOf(q) >= 0) return true;
    if (span.notes.toLowerCase().indexOf(q) >= 0) return true;
    if (span.kind.toLowerCase().indexOf(q) >= 0) return true;
    for (var i = 0; i < span.checklist.length; i++) {
        if (span.checklist[i].text.toLowerCase().indexOf(q) >= 0)
            return true;
    }
    return false;
}

function projectYearBoard(events, anchorDate, mode, todayIso, searchQuery) {
    var today = parseIsoDate(todayIso) ? todayIso : toIsoDate(new Date());
    var months = buildMonthMatrix(anchorDate, mode, today);
    var windowStart = months[0].startIso;
    var windowEnd = months[11].endIso;

    var spans = [];
    var list = Array.isArray(events) ? events : [];
    for (var i = 0; i < list.length; i++) {
        var span = normalizeEventSpan(list[i], today);
        if (!span) continue;
        if (span.endIso < windowStart || span.startIso > windowEnd) continue;
        if (!matchesSearch(span, searchQuery)) continue;
        spans.push(span);
    }

    spans.sort(function(a, b) {
        if (a.startIso !== b.startIso) return a.startIso < b.startIso ? -1 : 1;
        if (a.dayCount !== b.dayCount) return b.dayCount - a.dayCount;
        return Number(a.id || 0) - Number(b.id || 0);
    });

    var monthSegments = {};
    for (var mIdx = 0; mIdx < months.length; mIdx++) {
        monthSegments[months[mIdx].key] = [];
    }

    for (var sIdx = 0; sIdx < spans.length; sIdx++) {
        var sp = spans[sIdx];
        var parts = [];
        for (var k = 0; k < months.length; k++) {
            var mo = months[k];
            if (sp.endIso < mo.startIso || sp.startIso > mo.endIso) continue;
            var segStartIso = sp.startIso > mo.startIso ? sp.startIso : mo.startIso;
            var segEndIso = sp.endIso < mo.endIso ? sp.endIso : mo.endIso;
            var startDay = parseInt(segStartIso.slice(8, 10), 10);
            var endDay = parseInt(segEndIso.slice(8, 10), 10);
            var dayLength = endDay - startDay + 1;
            parts.push({
                eventId: sp.id,
                span: sp,
                monthKey: mo.key,
                monthIndex: k,
                startIso: segStartIso,
                endIso: segEndIso,
                startDay: startDay,
                endDay: endDay,
                dayLength: dayLength,
                wrapLeft: sp.startIso < mo.startIso,
                wrapRight: sp.endIso > mo.endIso,
                showLabel: false,
                lane: 0
            });
        }

        if (parts.length > 0) {
            var bestIdx = 0;
            for (var p = 1; p < parts.length; p++) {
                if (parts[p].dayLength > parts[bestIdx].dayLength)
                    bestIdx = p;
            }
            parts[bestIdx].showLabel = true;
            for (var p2 = 0; p2 < parts.length; p2++) {
                monthSegments[parts[p2].monthKey].push(parts[p2]);
            }
        }
    }

    var monthsOut = [];
    for (var mOut = 0; mOut < months.length; mOut++) {
        var row = months[mOut];
        var segs = monthSegments[row.key];
        segs.sort(function(a, b) {
            if (a.startDay !== b.startDay) return a.startDay - b.startDay;
            if (a.dayLength !== b.dayLength) return b.dayLength - a.dayLength;
            return Number(a.eventId || 0) - Number(b.eventId || 0);
        });
        var laneEnds = [];
        for (var g = 0; g < segs.length; g++) {
            var seg = segs[g];
            var assignedLane = -1;
            for (var l = 0; l < laneEnds.length; l++) {
                if (laneEnds[l] < seg.startDay) {
                    assignedLane = l;
                    laneEnds[l] = seg.endDay;
                    break;
                }
            }
            if (assignedLane < 0) {
                assignedLane = laneEnds.length;
                laneEnds.push(seg.endDay);
            }
            seg.lane = assignedLane;
        }
        monthsOut.push({
            index: row.index,
            year: row.year,
            monthIndex: row.monthIndex,
            key: row.key,
            label: row.label,
            shortLabel: row.shortLabel,
            daysInMonth: row.daysInMonth,
            startIso: row.startIso,
            endIso: row.endIso,
            days: row.days,
            segments: segs,
            laneCount: Math.max(1, laneEnds.length)
        });
    }

    var tripCount = 0;
    var daysAway = 0;
    var upcomingPlans = [];
    var pastPlans = [];
    for (var n = 0; n < spans.length; n++) {
        var item = spans[n];
        if (item.kind === KIND_TRIP) {
            tripCount++;
            var clippedStart = item.startIso > windowStart ? item.startIso : windowStart;
            var clippedEnd = item.endIso < windowEnd ? item.endIso : windowEnd;
            daysAway += Math.max(1, diffDaysIso(clippedStart, clippedEnd) + 1);
        }
        if (item.endIso >= today) {
            upcomingPlans.push(item);
        } else {
            pastPlans.push(item);
        }
    }
    pastPlans.sort(function(a, b) {
        if (a.endIso !== b.endIso) return a.endIso > b.endIso ? -1 : 1;
        return Number(b.id || 0) - Number(a.id || 0);
    });

    return {
        windowStart: windowStart,
        windowEnd: windowEnd,
        months: monthsOut,
        spans: spans,
        summary: {
            planCount: spans.length,
            tripCount: tripCount,
            daysAway: daysAway,
            nextPlan: upcomingPlans.length > 0 ? upcomingPlans[0] : null,
            upNextPlan: upcomingPlans.length > 1 ? upcomingPlans[1] : null,
            upcomingPlans: upcomingPlans,
            lastPlan: pastPlans.length > 0 ? pastPlans[0] : null
        }
    };
}

function shiftSpanRange(startIso, endIso, deltaDays) {
    if (!parseIsoDate(startIso) || !parseIsoDate(endIso))
        return null;
    var s = addDaysIso(startIso, deltaDays);
    var e = addDaysIso(endIso, deltaDays);
    return (s && e) ? { startIso: s, endIso: e } : null;
}

function resizeSpanRange(startIso, endIso, edge, targetIso) {
    if (!parseIsoDate(startIso) || !parseIsoDate(endIso) || !parseIsoDate(targetIso))
        return null;
    if (edge === "start") {
        return {
            startIso: targetIso <= endIso ? targetIso : endIso,
            endIso: endIso
        };
    }
    if (edge === "end") {
        return {
            startIso: startIso,
            endIso: targetIso >= startIso ? targetIso : startIso
        };
    }
    return null;
}
