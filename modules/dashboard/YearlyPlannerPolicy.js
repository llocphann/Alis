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

function _validDate(value) {
    if (!value) return null;
    var date = value instanceof Date ? new Date(value.getTime()) : new Date(value);
    return isNaN(date.getTime()) ? null : date;
}

function _midnight(value) {
    var date = new Date(value.getTime ? value.getTime() : value);
    date.setHours(0, 0, 0, 0);
    return date;
}

function _addDaysDate(value, count) {
    var date = new Date(value.getTime ? value.getTime() : value);
    date.setDate(date.getDate() + count);
    return date;
}

function _civilIndex(value) {
    return Date.UTC(value.getFullYear(), value.getMonth(), value.getDate()) / 86400000;
}

function _formatTime(date) {
    return _pad2(date.getHours()) + ":" + _pad2(date.getMinutes());
}

function _rangeToIsoSpan(startDt, endDt, allDay) {
    if (!_isValidDate(startDt)) return null;
    var startIso = toIsoDate(startDt);
    var endIso = startIso;
    if (_isValidDate(endDt) && endDt.getTime() > startDt.getTime()) {
        var endCivil = toIsoDate(endDt);
        if (allDay || (endDt.getHours() === 0 && endDt.getMinutes() === 0 && endDt.getSeconds() === 0 && endDt.getMilliseconds() === 0)) {
            var prevDay = addDaysIso(endCivil, -1);
            endIso = prevDay >= startIso ? prevDay : startIso;
        } else {
            endIso = endCivil >= startIso ? endCivil : startIso;
        }
    }
    return { startIso: startIso, endIso: endIso };
}

function _expandStarts(event, winStartDt, winEndExclDt, source, durationMs) {
    var base = _validDate(event.startDate || event.dateTime);
    if (!base) return [];
    var recurrence = source === "local" && !event.notified ? String(event.recurrence || "none").toLowerCase() : "none";
    var dates = [base];
    var earliest = new Date(winStartDt.getTime() - durationMs - 2 * 86400000);
    var through = winEndExclDt;
    function range(first, last, create) {
        if (last < first) return;
        if (last - first + 1 > 1024) first = last - 1023;
        for (var idx = first; idx <= last; idx++) dates.push(create(idx));
    }
    if (recurrence === "daily" || recurrence === "weekly") {
        var step = recurrence === "daily" ? 1 : 7;
        var first = Math.max(1, Math.floor((_civilIndex(earliest) - _civilIndex(base)) / step) - 1);
        var last = Math.ceil((_civilIndex(through) - _civilIndex(base)) / step);
        range(first, last, function(n) { return _addDaysDate(base, n * step); });
    } else if (recurrence === "monthly") {
        var firstM = (earliest.getFullYear() - base.getFullYear()) * 12 + earliest.getMonth() - base.getMonth();
        var lastM = (through.getFullYear() - base.getFullYear()) * 12 + through.getMonth() - base.getMonth();
        range(Math.max(1, firstM - 1), lastM + 1, function(m) {
            var month = new Date(base.getFullYear(), base.getMonth() + m, 1, 12);
            var monthly = new Date(month.getFullYear(), month.getMonth(), base.getDate(),
                base.getHours(), base.getMinutes(), base.getSeconds(), base.getMilliseconds());
            return monthly.getMonth() === month.getMonth() ? monthly : null;
        });
    } else if (recurrence === "yearly") {
        range(Math.max(1, earliest.getFullYear() - base.getFullYear() - 1), through.getFullYear() - base.getFullYear() + 1, function(y) {
            var yearly = new Date(base.getFullYear() + y, base.getMonth(), base.getDate(),
                base.getHours(), base.getMinutes(), base.getSeconds(), base.getMilliseconds());
            return yearly.getMonth() === base.getMonth() ? yearly : null;
        });
    }
    return dates;
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

function _buildSpanRecord(event, startIso, endIso, today, opts) {
    opts = opts || {};
    var rawKind = String(event.plannerKind || "").toLowerCase();
    var kind = (rawKind === KIND_TRIP || rawKind === KIND_MILESTONE || rawKind === KIND_PLAN)
        ? rawKind
        : (String(event.category || "").toLowerCase() === "travel" ? KIND_TRIP : KIND_PLAN);

    var checklist = normalizeChecklist(event.checklist);
    var doneCount = 0;
    for (var i = 0; i < checklist.length; i++) {
        if (checklist[i].done) doneCount++;
    }

    var dayCount = Math.max(1, diffDaysIso(startIso, endIso) + 1);
    var source = String(opts.source || "local");
    var colorHex = String(event.color || (source === "external" ? event.sourceColor : "") || "").trim();
    var occIdx = Number.isInteger(opts.occurrenceIndex) ? opts.occurrenceIndex : 0;
    var spanKey = source + ":" + String(event.id ?? event.uid ?? event.title ?? "") + ":" + occIdx + ":" + startIso + ":" + endIso;

    var isHoliday = event.isHoliday === true || String(event.kind || "").toLowerCase() === "holiday";

    return {
        key: spanKey,
        id: event.id !== undefined && event.id !== null ? event.id : String(event.uid || event.iCalUID || event.title || ""),
        rawId: event.id,
        source: source,
        readOnly: source === "external",
        isHoliday: isHoliday,
        occurrenceIndex: occIdx,
        recurrence: String(event.recurrence || "none").toLowerCase(),
        virtual: !!opts.virtual,
        timeLabel: opts.timeLabel || "",
        title: String(event.title || "").trim() || "Untitled",
        startIso: startIso,
        endIso: endIso,
        dayCount: dayCount,
        kind: kind,
        place: String(event.place || event.location || "").trim(),
        notes: String(event.description || ""),
        color: colorHex,
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
    var endDt = endRaw ? new Date(endRaw) : null;
    if (endDt && isNaN(endDt.getTime())) endDt = null;
    var isoRange = _rangeToIsoSpan(startDt, endDt, event.allDay === true);
    if (!isoRange) return null;
    var today = parseIsoDate(todayIso) ? todayIso : toIsoDate(new Date());
    var timeLabel = event.allDay ? "All day" : _formatTime(startDt);

    return _buildSpanRecord(event, isoRange.startIso, isoRange.endIso, today, {
        source: "local",
        occurrenceIndex: 0,
        virtual: false,
        timeLabel: timeLabel
    });
}

function _expandEventToWindow(event, source, winStartDt, winEndExclDt, futureSchedule) {
    var out = [];
    if (!event || typeof event !== "object") return out;

    if (source === "local" && futureSchedule && typeof futureSchedule.has === "function" && futureSchedule.has(event)) {
        var projected = futureSchedule.project(event, winStartDt, winEndExclDt) || [];
        for (var i = 0; i < projected.length; i++) {
            var item = projected[i];
            var s = _validDate(item.startDate), f = _validDate(item.endDate);
            if (!s || !f) continue;
            var isoR = _rangeToIsoSpan(s, f, event.allDay === true);
            if (isoR) {
                out.push({
                    startDt: s,
                    endDt: f,
                    startIso: isoR.startIso,
                    endIso: isoR.endIso,
                    occurrenceIndex: item.occurrenceIndex || 0,
                    virtual: !!item.virtual,
                    isMovedOverride: false
                });
            }
        }
        return out;
    }

    var grouped = Array.isArray(event.occurrences) && event.occurrences.length > 0;
    var ranges = grouped ? event.occurrences : [event];
    var minute = 60000;

    for (var slotIndex = 0; slotIndex < ranges.length; slotIndex++) {
        var slot = ranges[slotIndex];
        if (!slot) continue;
        var base = _validDate(slot.startDate || slot.dateTime || event.startDate || event.dateTime);
        if (!base) continue;
        var baseEnd = _validDate(slot.endDate || event.endDate);
        var durationMs = baseEnd && baseEnd > base ? baseEnd.getTime() - base.getTime() : 3600000;
        var allDaySpan = event.allDay && baseEnd && baseEnd > base
            ? Math.max(1, _civilIndex(baseEnd) - _civilIndex(base)) : 1;
        var repeatingGroup = Array.isArray(event.repeatTemplate)
            && event.repeatTemplate.length > 0
            && (event.recurrence || "none") !== "none";
        var activeGroup = repeatingGroup && slotIndex >= Number(event.repeatCycleStart || 0);
        var recurring = source === "local" && (event.recurrence || "none") !== "none";
        var anchor = (recurring && _validDate(slot.plannerSeriesStartDate)) || base;
        var anchorEnd = (recurring && _validDate(slot.plannerSeriesEndDate)) || baseEnd;
        var seriesDuration = anchorEnd && anchorEnd > anchor ? anchorEnd.getTime() - anchor.getTime() : durationMs;
        var occSource = Object.assign({}, event, {
            startDate: anchor.toISOString(),
            dateTime: anchor.toISOString(),
            endDate: anchorEnd && anchorEnd > anchor ? anchorEnd.toISOString() : "",
            notified: (repeatingGroup && !activeGroup) || (slot.notified === true && !activeGroup)
        });

        var genDates = _expandStarts(occSource, winStartDt, winEndExclDt, source, event.allDay ? allDaySpan * 86400000 : seriesDuration);
        var overrides = recurring && Array.isArray(event.plannerOverrides)
            ? event.plannerOverrides.filter(function(ov) {
                return ov.occurrenceIndex === slotIndex
                    && ov.materializedOccurrenceIndex === undefined
                    && ov.forwardedEventId === undefined;
            }) : [];

        function findOverride(occDt) {
            var iso = occDt.toISOString();
            for (var oi = 0; oi < overrides.length; oi++) {
                if (overrides[oi].originalStartDate === iso) return overrides[oi];
            }
            return null;
        }

        function emitOccurrence(occDt, saved, correction) {
            var actS = correction && _validDate(correction.startDate);
            var actE = correction && _validDate(correction.endDate);
            if (!actS || !actE || actE <= actS) correction = null;
            var start = correction ? actS : (event.allDay ? _midnight(saved ? base : occDt) : (saved ? base : occDt));
            var finish = correction ? actE : (event.allDay ? _addDaysDate(start, allDaySpan) : new Date(start.getTime() + (saved ? durationMs : seriesDuration)));
            if (start >= winEndExclDt || finish <= winStartDt) return;
            var rIso = _rangeToIsoSpan(start, finish, event.allDay === true && !correction);
            if (!rIso) return;
            out.push({
                startDt: start,
                endDt: finish,
                startIso: rIso.startIso,
                endIso: rIso.endIso,
                occurrenceIndex: slotIndex,
                virtual: !saved,
                isMovedOverride: !!correction
            });
        }

        var sawAnchor = false;
        var seenVirtual = {};
        for (var di = 0; di < genDates.length; di++) {
            var occDt = genDates[di];
            if (!occDt) continue;
            var saved = occDt.getTime() === anchor.getTime();
            if (saved) sawAnchor = true;
            if (!saved) seenVirtual[occDt.toISOString()] = true;
            if (!saved && occDt.getTime() === base.getTime() && base.getTime() !== anchor.getTime()) continue;
            emitOccurrence(occDt, saved, saved ? null : findOverride(occDt));
        }
        for (var vi = 0; vi < overrides.length; vi++) {
            var ov = overrides[vi];
            if (seenVirtual[ov.originalStartDate]) continue;
            var origDt = _validDate(ov.originalStartDate);
            if (origDt) emitOccurrence(origDt, false, ov);
        }
        if (!sawAnchor && anchor.getTime() !== base.getTime()) {
            emitOccurrence(base, true, null);
        }
    }
    return out;
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

function projectYearBoard(events, anchorDate, mode, todayIso, searchQuery, options) {
    options = options || {};
    var showRecurring = options.showRecurring !== false;
    var showExternal = options.showExternal !== false;
    var externalEvents = showExternal && Array.isArray(options.externalEvents) ? options.externalEvents : [];
    var futureSchedule = options.futureSchedule || null;

    var today = parseIsoDate(todayIso) ? todayIso : toIsoDate(new Date());
    var months = buildMonthMatrix(anchorDate, mode, today);
    var windowStart = months[0].startIso;
    var windowEnd = months[11].endIso;
    var winStartDt = parseIsoDate(windowStart);
    var winEndExclDt = _addDaysDate(parseIsoDate(windowEnd), 1);

    var spans = [];
    var seenSpanKeys = {};
    var dayRecurringMap = {};
    var dayItemsMap = {};
    var dayHolidaysMap = {};
    var recurringSeriesIds = {};
    var externalEventCount = 0;
    var holidaySpanCount = 0;

    function addDayItem(iso, item) {
        if (!dayItemsMap[iso]) dayItemsMap[iso] = [];
        dayItemsMap[iso].push(item);
    }

    function addDayHoliday(iso, item) {
        if (!dayHolidaysMap[iso]) dayHolidaysMap[iso] = [];
        dayHolidaysMap[iso].push(item);
    }

    function addDayRecurring(iso, item) {
        if (!dayRecurringMap[iso]) dayRecurringMap[iso] = [];
        dayRecurringMap[iso].push(item);
    }

    var sources = [
        { list: Array.isArray(events) ? events : [], source: "local" },
        { list: externalEvents, source: "external" }
    ];

    for (var sIdxSrc = 0; sIdxSrc < sources.length; sIdxSrc++) {
        var list = sources[sIdxSrc].list;
        var source = sources[sIdxSrc].source;
        for (var i = 0; i < list.length; i++) {
            var ev = list[i];
            if (!ev || typeof ev !== "object") continue;
            var recMode = String(ev.recurrence || "none").toLowerCase();
            var isDenseRec = source === "local" && (recMode === "daily" || recMode === "weekly") && !ev.notified;
            var occs = _expandEventToWindow(ev, source, winStartDt, winEndExclDt, futureSchedule);
            if (!occs.length) continue;

            if (source === "external") externalEventCount++;

            var evSeen = {};
            var anySeriesMatch = false;
            for (var oi = 0; oi < occs.length; oi++) {
                var occ = occs[oi];
                var sIso = occ.startIso < windowStart ? windowStart : occ.startIso;
                var eIso = occ.endIso > windowEnd ? windowEnd : occ.endIso;
                if (eIso < windowStart || sIso > windowEnd) continue;

                var dedupKey = source + ":" + String(ev.id ?? ev.uid ?? ev.title ?? "") + ":" + occ.startIso + ":" + occ.endIso + ":" + _formatTime(occ.startDt);
                if (evSeen[dedupKey]) continue;
                evSeen[dedupKey] = true;

                var span = _buildSpanRecord(ev, occ.startIso, occ.endIso, today, {
                    source: source,
                    occurrenceIndex: occ.occurrenceIndex,
                    virtual: occ.virtual,
                    timeLabel: ev.allDay ? "All day" : _formatTime(occ.startDt)
                });
                if (!matchesSearch(span, searchQuery)) continue;

                // Daily/Weekly active series become compact per-day indicators to keep
                // 12-month swimlanes legible; single/multi-day plans, external events,
                // monthly/yearly cycles, and moved overrides render as horizontal bars.
                if (isDenseRec && !occ.isMovedOverride && !(Array.isArray(ev.repeatTemplate) && ev.repeatTemplate.length > 0 && occ.occurrenceIndex < Number(ev.repeatCycleStart || 0))) {
                    anySeriesMatch = true;
                    if (!showRecurring) continue;
                    var curIso = sIso;
                    var guard = 0;
                    while (curIso <= eIso && guard < 400) {
                        guard++;
                        var recEntry = {
                            key: span.key + ":" + curIso,
                            id: span.id,
                            rawId: span.rawId,
                            title: span.title,
                            startIso: span.startIso,
                            endIso: span.endIso,
                            timeLabel: span.timeLabel,
                            color: span.color,
                            recurrence: recMode,
                            source: source,
                            readOnly: span.readOnly,
                            occurrenceIndex: span.occurrenceIndex,
                            isRecurring: true,
                            span: span,
                            sourceEvent: ev
                        };
                        addDayRecurring(curIso, recEntry);
                        addDayItem(curIso, recEntry);
                        curIso = addDaysIso(curIso, 1);
                    }
                    continue;
                }

                // Deduplicate bars covering identical (source, id, startIso, endIso)
                var barKey = source + ":" + String(span.id) + ":" + span.startIso + ":" + span.endIso;
                if (seenSpanKeys[barKey]) continue;
                seenSpanKeys[barKey] = true;
                if (span.isHoliday) holidaySpanCount++;
                spans.push(span);

                var bCur = sIso;
                var bGuard = 0;
                while (bCur <= eIso && bGuard < 400) {
                    bGuard++;
                    var dayEntry = {
                        key: span.key + ":" + bCur,
                        id: span.id,
                        rawId: span.rawId,
                        title: span.title,
                        startIso: span.startIso,
                        endIso: span.endIso,
                        timeLabel: span.timeLabel,
                        color: span.color,
                        recurrence: recMode,
                        source: source,
                        readOnly: span.readOnly,
                        isHoliday: span.isHoliday === true,
                        occurrenceIndex: span.occurrenceIndex,
                        isRecurring: false,
                        span: span,
                        sourceEvent: ev
                    };
                    addDayItem(bCur, dayEntry);
                    if (span.isHoliday) addDayHoliday(bCur, dayEntry);
                    bCur = addDaysIso(bCur, 1);
                }
            }
            if (anySeriesMatch) {
                recurringSeriesIds[source + ":" + String(ev.id ?? ev.title ?? i)] = true;
            }
        }
    }

    spans.sort(function(a, b) {
        if (a.startIso !== b.startIso) return a.startIso < b.startIso ? -1 : 1;
        if (a.dayCount !== b.dayCount) return b.dayCount - a.dayCount;
        return Number(a.rawId || 0) - Number(b.rawId || 0) || String(a.id).localeCompare(String(b.id));
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
            return Number(a.span?.rawId || 0) - Number(b.span?.rawId || 0) || String(a.eventId).localeCompare(String(b.eventId));
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
        var daysWithRecurring = row.days.map(function(dayCell) {
            var recItems = dayRecurringMap[dayCell.iso] || [];
            var allItems = dayItemsMap[dayCell.iso] || [];
            var holItems = dayHolidaysMap[dayCell.iso] || [];
            return Object.assign({}, dayCell, {
                recurringItems: recItems,
                holidays: holItems,
                isHoliday: holItems.length > 0,
                dayItemCount: allItems.length
            });
        });
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
            days: daysWithRecurring,
            segments: segs,
            laneCount: Math.max(1, laneEnds.length)
        });
    }

    // Sort dayItemsMap chronologically per day
    var dayKeys = Object.keys(dayItemsMap);
    for (var dk = 0; dk < dayKeys.length; dk++) {
        dayItemsMap[dayKeys[dk]].sort(function(a, b) {
            if (a.timeLabel !== b.timeLabel) return a.timeLabel < b.timeLabel ? -1 : 1;
            return a.title.localeCompare(b.title);
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
        return Number(b.rawId || 0) - Number(a.rawId || 0);
    });

    return {
        windowStart: windowStart,
        windowEnd: windowEnd,
        months: monthsOut,
        spans: spans,
        dayRecurringMap: dayRecurringMap,
        dayItemsMap: dayItemsMap,
        dayHolidaysMap: dayHolidaysMap,
        summary: {
            planCount: spans.length,
            recurringCount: Object.keys(recurringSeriesIds).length,
            externalCount: externalEventCount,
            holidayCount: holidaySpanCount,
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
