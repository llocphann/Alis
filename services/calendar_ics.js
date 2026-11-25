// ICS/iCalendar parser — pure JavaScript, zero dependencies.
// Handles RFC 5545 VEVENT components with support for:
//   - CRLF and LF folded line unfolding
//   - Ignoring nested subcomponents (VALARM, etc.) so alarm fields never overwrite VEVENT fields
//   - DTSTART / DTEND / DURATION (date-only all-day, UTC, floating, and TZID incl. Outlook Windows names)
//   - SUMMARY, DESCRIPTION, LOCATION, STATUS (skips CANCELLED), CATEGORIES
//   - Full multi-year RRULE expansion (DAILY, WEEKLY, MONTHLY, YEARLY, INTERVAL, COUNT, UNTIL,
//     BYDAY with ordinals like 3MO/-1MO, BYMONTH, BYMONTHDAY, WKST) without month-rollover bugs
//   - EXDATE exclusions and RECURRENCE-ID instance overrides
//   - Holiday source tagging (isHoliday, kind: "holiday" | "event")

var WINDOWS_TZ_MAP = {
    "utc": "UTC",
    "coordinated universal time": "UTC",
    "gmt standard time": "Europe/London",
    "greenwich standard time": "Etc/GMT",
    "w. europe standard time": "Europe/Berlin",
    "romance standard time": "Europe/Paris",
    "central europe standard time": "Europe/Budapest",
    "central european standard time": "Europe/Warsaw",
    "eastern standard time": "America/New_York",
    "central standard time": "America/Chicago",
    "mountain standard time": "America/Denver",
    "pacific standard time": "America/Los_Angeles",
    "se asia standard time": "Asia/Bangkok",
    "indochina time": "Asia/Ho_Chi_Minh",
    "singapore standard time": "Asia/Singapore",
    "china standard time": "Asia/Shanghai",
    "taipei standard time": "Asia/Taipei",
    "tokyo standard time": "Asia/Tokyo",
    "korea standard time": "Asia/Seoul",
    "aus eastern standard time": "Australia/Sydney",
    "india standard time": "Asia/Kolkata"
};

var WEEKDAY_MAP = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

function _daysInMonth(year, monthIndex) {
    return new Date(year, monthIndex + 1, 0).getDate();
}

function _dayKey(date) {
    var y = date.getFullYear();
    var m = date.getMonth() + 1;
    var d = date.getDate();
    return y + "-" + (m < 10 ? "0" + m : m) + "-" + (d < 10 ? "0" + d : d);
}

function _resolveIanaTz(rawTzid) {
    if (!rawTzid) return "";
    var clean = String(rawTzid).replace(/^["']|["']$/g, "").trim();
    if (!clean) return "";
    // Strip leading slash (e.g. /freeassociation.sourceforge.net/Asia/Ho_Chi_Minh)
    var mapped = WINDOWS_TZ_MAP[clean.toLowerCase()];
    if (mapped) return mapped;
    var slashMatch = clean.match(/([A-Za-z_]+\/[A-Za-z0-9_+\-/]+)$/);
    return slashMatch ? slashMatch[1] : clean;
}

function _findUnquotedColon(line) {
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
        var ch = line.charAt(i);
        if (ch === "\"") {
            inQuotes = !inQuotes;
        } else if (ch === ":" && !inQuotes) {
            return i;
        }
    }
    return -1;
}

function _parseFixedUtcOffsetMinutes(clean) {
    var m = /^(?:UTC|GMT)?\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?$/i.exec(clean);
    if (!m) return null;
    var sign = m[1] === "-" ? -1 : 1;
    var hrs = parseInt(m[2], 10);
    var mins = parseInt(m[3] || "0", 10);
    if (hrs > 14 || mins >= 60) return null;
    return sign * (hrs * 60 + mins);
}

function _zonedWallToUtcDate(y, mo, d, h, mi, s, tzid) {
    var cleanTz = String(tzid || "").replace(/^["']|["']$/g, "").trim();
    var fixedOffset = _parseFixedUtcOffsetMinutes(cleanTz);
    if (fixedOffset !== null) {
        return new Date(Date.UTC(y, mo, d, h, mi, s) - fixedOffset * 60000);
    }
    var iana = _resolveIanaTz(cleanTz);
    if (!iana || typeof Intl === "undefined" || typeof Intl.DateTimeFormat !== "function")
        return new Date(y, mo, d, h, mi, s);
    try {
        var fmt = new Intl.DateTimeFormat("en-US", {
            timeZone: iana,
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
            hour12: false
        });
        var guessUtc = Date.UTC(y, mo, d, h, mi, s);
        for (var iter = 0; iter < 2; iter++) {
            var parts = fmt.formatToParts(new Date(guessUtc));
            var vals = {};
            for (var p = 0; p < parts.length; p++) {
                if (parts[p].type !== "literal") vals[parts[p].type] = parseInt(parts[p].value, 10);
            }
            var ph = vals.hour === 24 ? 0 : (vals.hour || 0);
            var obsAsUtc = Date.UTC(vals.year, (vals.month || 1) - 1, vals.day, ph, vals.minute || 0, vals.second || 0);
            var diff = Date.UTC(y, mo, d, h, mi, s) - obsAsUtc;
            guessUtc += diff;
            if (Math.abs(diff) < 1000) break;
        }
        return new Date(guessUtc);
    } catch (_e) {
        return new Date(y, mo, d, h, mi, s);
    }
}

function _parseDurationMs(raw) {
    if (!raw || typeof raw !== "string") return 0;
    var m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i.exec(raw.trim());
    if (!m) return 0;
    var sign = m[1] === "-" ? -1 : 1;
    var weeks = parseInt(m[2] || "0", 10);
    var days = parseInt(m[3] || "0", 10);
    var hours = parseInt(m[4] || "0", 10);
    var mins = parseInt(m[5] || "0", 10);
    var secs = parseInt(m[6] || "0", 10);
    return sign * (((((weeks * 7 + days) * 24 + hours) * 60 + mins) * 60 + secs) * 1000);
}

// Parse a raw ICS string into an array of event objects.
// Signature keeps 4-arg backward compatibility; optional 5th `options`:
//   { isHoliday: bool, kind: "holiday"|"event", windowStart: Date, windowEnd: Date }
function parseICS(icsText, sourceId, sourceName, sourceColor, options) {
    if (!icsText || typeof icsText !== "string") return [];
    options = options || {};

    // RFC 5545 unfolding supporting UTF-8 BOM and both CRLF and LF line endings.
    var normalized = icsText.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    var unfolded = normalized.replace(/\n[ \t]/g, "");
    var lines = unfolded.split("\n");

    var rawEvents = [];
    var inEvent = false;
    var subDepth = 0;
    var current = null;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line) continue;

        if (!inEvent) {
            if (line === "BEGIN:VEVENT") {
                inEvent = true;
                subDepth = 0;
                current = { EXDATES: [] };
            }
            continue;
        }

        if (line.indexOf("BEGIN:") === 0) {
            subDepth++;
            continue;
        }
        if (line.indexOf("END:") === 0) {
            if (subDepth > 0) {
                subDepth--;
                continue;
            }
            if (line === "END:VEVENT") {
                inEvent = false;
                if (current && current.DTSTART) {
                    rawEvents.push(current);
                }
                current = null;
            }
            continue;
        }

        // Ignore properties inside nested subcomponents (e.g., BEGIN:VALARM ... END:VALARM)
        if (subDepth > 0 || !current) continue;

        var colonIdx = _findUnquotedColon(line);
        if (colonIdx === -1) continue;

        var propPart = line.substring(0, colonIdx);
        var value = line.substring(colonIdx + 1);
        var semiIdx = propPart.indexOf(";");
        var propName = (semiIdx === -1 ? propPart : propPart.substring(0, semiIdx)).toUpperCase();
        var params = semiIdx === -1 ? "" : propPart.substring(semiIdx + 1);

        if (propName === "DTSTART" || propName === "DTEND" || propName === "RECURRENCE-ID") {
            current[propName] = value.trim();
            current[propName + "_PARAMS"] = params;
        } else if (propName === "EXDATE") {
            var parts = value.split(",");
            for (var p = 0; p < parts.length; p++) {
                var tok = parts[p].trim();
                if (tok) current.EXDATES.push({ value: tok, params: params });
            }
        } else if (propName === "RRULE" || propName === "DURATION" || propName === "UID" || propName === "STATUS") {
            current[propName] = value.trim();
        } else {
            current[propName] = _unescapeICS(value);
        }
    }

    // Collect RECURRENCE-ID override keys per UID so master series expansion skips overridden instances
    var overridesByUid = {};
    for (var r = 0; r < rawEvents.length; r++) {
        var re = rawEvents[r];
        if (!re.UID || !re["RECURRENCE-ID"]) continue;
        var ridParsed = _parseICSDate(re["RECURRENCE-ID"], re["RECURRENCE-ID_PARAMS"]);
        if (!ridParsed) continue;
        if (!overridesByUid[re.UID]) overridesByUid[re.UID] = { days: {}, times: {} };
        overridesByUid[re.UID].days[_dayKey(ridParsed.date)] = true;
        overridesByUid[re.UID].times[ridParsed.date.getTime()] = true;
    }

    var nowYear = new Date().getFullYear();
    var winStart = options.windowStart instanceof Date && !isNaN(options.windowStart.getTime())
        ? options.windowStart
        : new Date(nowYear - 1, 0, 1, 0, 0, 0, 0);
    var winEnd = options.windowEnd instanceof Date && !isNaN(options.windowEnd.getTime())
        ? options.windowEnd
        : new Date(nowYear + 2, 11, 31, 23, 59, 59, 999);

    var events = [];
    for (var e = 0; e < rawEvents.length; e++) {
        var raw = rawEvents[e];
        if (String(raw.STATUS || "").toUpperCase() === "CANCELLED")
            continue;

        var base = _buildEvent(raw, sourceId, sourceName, sourceColor, options);
        if (!base) continue;

        if (raw.RRULE && !raw["RECURRENCE-ID"]) {
            var exSet = _buildExdateSet(raw.EXDATES, overridesByUid[raw.UID]);
            var expanded = _expandRecurrence(base, raw.RRULE, exSet, winStart, winEnd);
            for (var k = 0; k < expanded.length; k++) {
                events.push(expanded[k]);
            }
        } else {
            events.push(base);
        }
    }

    return events;
}

function _buildExdateSet(exdates, uidOverrides) {
    var days = {};
    var times = {};
    if (Array.isArray(exdates)) {
        for (var i = 0; i < exdates.length; i++) {
            var parsed = _parseICSDate(exdates[i].value, exdates[i].params);
            if (!parsed) continue;
            days[_dayKey(parsed.date)] = true;
            times[parsed.date.getTime()] = true;
        }
    }
    if (uidOverrides) {
        var od = Object.keys(uidOverrides.days || {});
        for (var j = 0; j < od.length; j++) days[od[j]] = true;
        var ot = Object.keys(uidOverrides.times || {});
        for (var t = 0; t < ot.length; t++) times[ot[t]] = true;
    }
    return { days: days, times: times };
}

function _isExcluded(date, allDay, exSet) {
    if (!exSet) return false;
    if (allDay) return !!exSet.days[_dayKey(date)];
    return !!exSet.times[date.getTime()] || !!exSet.days[_dayKey(date)];
}

function _buildEvent(props, sourceId, sourceName, sourceColor, options) {
    var startResult = _parseICSDate(props.DTSTART, props.DTSTART_PARAMS);
    if (!startResult) return null;

    var endResult = props.DTEND ? _parseICSDate(props.DTEND, props.DTEND_PARAMS) : null;
    var endDate;
    if (endResult) {
        endDate = endResult.date;
    } else if (props.DURATION) {
        var durMs = _parseDurationMs(props.DURATION);
        endDate = durMs > 0
            ? new Date(startResult.date.getTime() + durMs)
            : new Date(startResult.date.getTime());
    } else if (startResult.allDay) {
        endDate = new Date(startResult.date.getFullYear(), startResult.date.getMonth(), startResult.date.getDate() + 1);
    } else {
        endDate = new Date(startResult.date.getTime());
    }

    var isHoliday = Boolean(options && (options.isHoliday === true || options.kind === "holiday"));

    return {
        title: props.SUMMARY || "(No title)",
        description: props.DESCRIPTION || "",
        location: props.LOCATION || "",
        startDate: startResult.date.toISOString(),
        endDate: endDate.toISOString(),
        allDay: startResult.allDay,
        sourceId: sourceId,
        sourceName: sourceName,
        sourceColor: sourceColor || "#4285F4",
        uid: props.UID || "",
        source: "external",
        kind: isHoliday ? "holiday" : "event",
        isHoliday: isHoliday,
        recurrence: props.RRULE ? _parseRRULEFreq(props.RRULE) : "none"
    };
}

// Parse ICS date string. Handles:
//   20260415T100000Z       (UTC)
//   20260415T100000        (local/floating)
//   20260415               (date-only = all-day)
//   TZID=America/New_York:20260415T100000
function _parseICSDate(value, params) {
    if (!value) return null;
    var dateStr = String(value).trim();

    var tzid = "";
    if (params) {
        var tzMatch = params.match(/TZID=("[^"]*"|[^;:]+)/i);
        if (tzMatch) tzid = tzMatch[1];
    }

    var isDateOnly = /^\d{8}$/.test(dateStr) || (params && /VALUE=DATE\b/i.test(params) && !/VALUE=DATE-TIME/i.test(params));

    if (isDateOnly) {
        if (dateStr.length < 8) return null;
        var y = parseInt(dateStr.substring(0, 4), 10);
        var m = parseInt(dateStr.substring(4, 6), 10) - 1;
        var d = parseInt(dateStr.substring(6, 8), 10);
        var dtOnly = new Date(y, m, d, 0, 0, 0, 0);
        if (isNaN(dtOnly.getTime())) return null;
        return { date: dtOnly, allDay: true };
    }

    var isUTC = dateStr.endsWith("Z") || dateStr.endsWith("z");
    dateStr = dateStr.replace(/[Zz]$/, "");
    if (dateStr.length < 15 || dateStr.charAt(8) !== "T") return null;

    var yr = parseInt(dateStr.substring(0, 4), 10);
    var mo = parseInt(dateStr.substring(4, 6), 10) - 1;
    var dy = parseInt(dateStr.substring(6, 8), 10);
    var h = parseInt(dateStr.substring(9, 11), 10) || 0;
    var mi = parseInt(dateStr.substring(11, 13), 10) || 0;
    var s = parseInt(dateStr.substring(13, 15), 10) || 0;

    var date;
    if (isUTC) {
        date = new Date(Date.UTC(yr, mo, dy, h, mi, s));
    } else if (tzid) {
        date = _zonedWallToUtcDate(yr, mo, dy, h, mi, s, tzid);
    } else {
        date = new Date(yr, mo, dy, h, mi, s);
    }

    if (isNaN(date.getTime())) return null;
    return { date: date, allDay: false };
}

function _parseRRULEFreq(rrule) {
    if (!rrule) return "none";
    var match = String(rrule).match(/FREQ=(\w+)/i);
    if (!match) return "none";
    switch (match[1].toUpperCase()) {
        case "DAILY": return "daily";
        case "WEEKLY": return "weekly";
        case "MONTHLY": return "monthly";
        case "YEARLY": return "yearly";
        default: return "none";
    }
}

function _parseRRule(rrule) {
    var parts = {};
    var tokens = String(rrule || "").split(";");
    for (var i = 0; i < tokens.length; i++) {
        var eq = tokens[i].indexOf("=");
        if (eq <= 0) continue;
        parts[tokens[i].substring(0, eq).trim().toUpperCase()] = tokens[i].substring(eq + 1).trim();
    }
    var freq = _parseRRULEFreq(rrule);
    var interval = Math.max(1, parseInt(parts.INTERVAL || "1", 10) || 1);
    var count = parts.COUNT ? Math.max(1, parseInt(parts.COUNT, 10) || 0) : 0;
    var until = null;
    var untilAllDayEnd = null;
    if (parts.UNTIL) {
        var uRaw = parts.UNTIL.trim();
        var u = _parseICSDate(uRaw, uRaw.length === 8 ? "VALUE=DATE" : "");
        if (u) {
            until = u.allDay
                ? new Date(u.date.getFullYear(), u.date.getMonth(), u.date.getDate(), 23, 59, 59, 999)
                : u.date;
            if (u.allDay) {
                untilAllDayEnd = until;
            } else if (/^\d{8}T\d{6}Z$/i.test(uRaw)) {
                var uy = parseInt(uRaw.substring(0, 4), 10);
                var um = parseInt(uRaw.substring(4, 6), 10) - 1;
                var ud = parseInt(uRaw.substring(6, 8), 10);
                untilAllDayEnd = new Date(uy, um, ud, 23, 59, 59, 999);
            } else {
                untilAllDayEnd = new Date(u.date.getFullYear(), u.date.getMonth(), u.date.getDate(), 23, 59, 59, 999);
            }
        }
    }
    var byDay = null;
    if (parts.BYDAY) {
        byDay = [];
        var rawDays = parts.BYDAY.split(",");
        for (var d = 0; d < rawDays.length; d++) {
            var bm = /^([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$/i.exec(rawDays[d].trim());
            if (bm) {
                byDay.push({
                    ord: bm[1] ? parseInt(bm[1], 10) : 0,
                    dow: WEEKDAY_MAP[bm[2].toUpperCase()]
                });
            }
        }
        if (!byDay.length) byDay = null;
    }
    var byMonth = null;
    if (parts.BYMONTH) {
        byMonth = parts.BYMONTH.split(",").map(function(v) { return parseInt(v, 10); })
            .filter(function(n) { return n >= 1 && n <= 12; });
        if (!byMonth.length) byMonth = null;
    }
    var byMonthDay = null;
    if (parts.BYMONTHDAY) {
        byMonthDay = parts.BYMONTHDAY.split(",").map(function(v) { return parseInt(v, 10); })
            .filter(function(n) { return n !== 0 && n >= -31 && n <= 31; });
        if (!byMonthDay.length) byMonthDay = null;
    }
    var bySetPos = null;
    if (parts.BYSETPOS) {
        bySetPos = parts.BYSETPOS.split(",").map(function(v) { return parseInt(v, 10); })
            .filter(function(n) { return n !== 0 && n >= -366 && n <= 366; });
        if (!bySetPos.length) bySetPos = null;
    }
    var wkst = parts.WKST && WEEKDAY_MAP[parts.WKST.toUpperCase()] !== undefined
        ? WEEKDAY_MAP[parts.WKST.toUpperCase()] : 1; // RFC 5545 default MO
    return {
        freq: freq,
        interval: interval,
        count: count,
        until: until,
        untilAllDayEnd: untilAllDayEnd,
        byDay: byDay,
        byMonth: byMonth,
        byMonthDay: byMonthDay,
        bySetPos: bySetPos,
        wkst: wkst
    };
}

function _applyBySetPos(dates, bySetPos) {
    if (!bySetPos || !bySetPos.length || !dates.length) return dates;
    var picked = {};
    var out = [];
    for (var i = 0; i < bySetPos.length; i++) {
        var pos = bySetPos[i];
        var idx = pos > 0 ? (pos - 1) : (dates.length + pos);
        if (idx >= 0 && idx < dates.length && !picked[idx]) {
            picked[idx] = true;
            out.push(dates[idx]);
        }
    }
    out.sort(function(a, b) { return a.getTime() - b.getTime(); });
    return out;
}

function _datesForMonthCandidates(year, monthIndex, rule, defaultDay, h, mi, s, ms) {
    var cands;
    if (rule.byDay && rule.byMonthDay) {
        var bd = _datesForMonthByDay(year, monthIndex, rule.byDay, h, mi, s, ms);
        var bmd = _datesForMonthByMonthDay(year, monthIndex, rule.byMonthDay, h, mi, s, ms);
        var mdSet = {};
        for (var i = 0; i < bmd.length; i++) mdSet[bmd[i].getDate()] = true;
        cands = bd.filter(function(dt) { return !!mdSet[dt.getDate()]; });
    } else if (rule.byDay) {
        cands = _datesForMonthByDay(year, monthIndex, rule.byDay, h, mi, s, ms);
    } else if (rule.byMonthDay) {
        cands = _datesForMonthByMonthDay(year, monthIndex, rule.byMonthDay, h, mi, s, ms);
    } else {
        var dim = _daysInMonth(year, monthIndex);
        cands = defaultDay <= dim
            ? [new Date(year, monthIndex, defaultDay, h, mi, s, ms)]
            : [];
    }
    return cands;
}

function _datesForMonthByDay(year, monthIndex, byDaySpecs, h, mi, s, ms) {
    var dim = _daysInMonth(year, monthIndex);
    var days = {};
    for (var i = 0; i < byDaySpecs.length; i++) {
        var spec = byDaySpecs[i];
        var matching = [];
        for (var day = 1; day <= dim; day++) {
            if (new Date(year, monthIndex, day).getDay() === spec.dow)
                matching.push(day);
        }
        if (spec.ord === 0) {
            for (var m = 0; m < matching.length; m++) days[matching[m]] = true;
        } else if (spec.ord > 0 && spec.ord <= matching.length) {
            days[matching[spec.ord - 1]] = true;
        } else if (spec.ord < 0 && matching.length + spec.ord >= 0) {
            days[matching[matching.length + spec.ord]] = true;
        }
    }
    return Object.keys(days).map(function(k) { return parseInt(k, 10); })
        .sort(function(a, b) { return a - b; })
        .map(function(day) { return new Date(year, monthIndex, day, h, mi, s, ms); });
}

function _datesForMonthByMonthDay(year, monthIndex, byMonthDay, h, mi, s, ms) {
    var dim = _daysInMonth(year, monthIndex);
    var days = {};
    for (var i = 0; i < byMonthDay.length; i++) {
        var md = byMonthDay[i];
        var target = md > 0 ? md : (dim + 1 + md);
        if (target >= 1 && target <= dim) days[target] = true;
    }
    return Object.keys(days).map(function(k) { return parseInt(k, 10); })
        .sort(function(a, b) { return a - b; })
        .map(function(day) { return new Date(year, monthIndex, day, h, mi, s, ms); });
}

// Expand a recurring event across [winStart, winEnd] (including the base occurrence itself
// if not excluded and inside the window). Returns array of occurrence event objects.
function _expandRecurrence(baseEvent, rruleStr, exSet, winStart, winEnd) {
    var rule = _parseRRule(rruleStr);
    if (rule.freq === "none") return [baseEvent];

    var startDate = new Date(baseEvent.startDate);
    var endDate = new Date(baseEvent.endDate);
    var durationMs = Math.max(0, endDate.getTime() - startDate.getTime());
    var allDay = baseEvent.allDay === true;
    var allDaySpanDays = allDay && durationMs >= 86400000
        ? Math.max(1, Math.round(durationMs / 86400000)) : 1;

    var baseH = startDate.getHours();
    var baseMi = startDate.getMinutes();
    var baseS = startDate.getSeconds();
    var baseMs = startDate.getMilliseconds();
    var startTime = startDate.getTime();
    var winStartTime = winStart.getTime();
    var winEndTime = winEnd.getTime();
    var effectiveUntil = allDay && rule.untilAllDayEnd ? rule.untilAllDayEnd : rule.until;
    var untilTime = effectiveUntil ? effectiveUntil.getTime() : Infinity;
    var hardEndTime = Math.min(winEndTime, untilTime);

    var results = [];
    var generatedCount = 0;
    var maxEmit = 2000;
    var maxSteps = 5000;

    function emitCandidate(cand) {
        var t = cand.getTime();
        if (t < startTime) return true;
        if (t > untilTime) return false;
        if (rule.count > 0 && generatedCount >= rule.count) return false;
        generatedCount++;
        if (t > winEndTime) return false;

        var occEnd = allDay
            ? new Date(cand.getFullYear(), cand.getMonth(), cand.getDate() + allDaySpanDays, 0, 0, 0, 0)
            : new Date(t + durationMs);
        if (occEnd.getTime() < winStartTime) return true;
        if (_isExcluded(cand, allDay, exSet)) return true;

        var isBase = t === startTime;
        results.push(Object.assign({}, baseEvent, {
            startDate: cand.toISOString(),
            endDate: occEnd.toISOString(),
            uid: isBase ? baseEvent.uid : (baseEvent.uid + "_recur_" + _dayKey(cand) + "_" + generatedCount)
        }));
        return results.length < maxEmit;
    }

    if (rule.freq === "daily") {
        var stepIdx = 0;
        // Fast-forward old DTSTARTs safely when COUNT is not specified
        if (!rule.count && startTime < winStartTime) {
            var daysDiff = Math.floor((winStartTime - startTime) / 86400000);
            stepIdx = Math.max(0, Math.floor(daysDiff / rule.interval) - 2);
        }
        var steps = 0;
        while (steps++ < maxSteps) {
            var cand = new Date(startDate.getFullYear(), startDate.getMonth(),
                startDate.getDate() + stepIdx * rule.interval, baseH, baseMi, baseS, baseMs);
            if (cand.getTime() > hardEndTime) break;
            var ok = true;
            if (rule.byDay) {
                var dow = cand.getDay();
                ok = rule.byDay.some(function(b) { return b.dow === dow; });
            }
            if (ok && rule.byMonth && rule.byMonth.indexOf(cand.getMonth() + 1) < 0)
                ok = false;
            if (ok && !emitCandidate(cand)) break;
            stepIdx++;
        }
    } else if (rule.freq === "weekly") {
        var weekDays = rule.byDay
            ? rule.byDay.map(function(b) { return b.dow; }).filter(function(v, idx, arr) { return arr.indexOf(v) === idx; })
            : [startDate.getDay()];
        // Anchor to the start of DTSTART's week (based on WKST)
        var offsetFromWkst = (startDate.getDay() - rule.wkst + 7) % 7;
        var week0Start = new Date(startDate.getFullYear(), startDate.getMonth(),
            startDate.getDate() - offsetFromWkst, baseH, baseMi, baseS, baseMs);
        var weekOffsets = weekDays.map(function(d) { return (d - rule.wkst + 7) % 7; })
            .sort(function(a, b) { return a - b; });
        var wIdx = 0;
        if (!rule.count && week0Start.getTime() < winStartTime) {
            var weeksDiff = Math.floor((winStartTime - week0Start.getTime()) / (7 * 86400000));
            wIdx = Math.max(0, Math.floor(weeksDiff / rule.interval) - 2);
        }
        var wSteps = 0;
        var stopWeekly = false;
        while (wSteps++ < maxSteps && !stopWeekly) {
            var wBaseDay = week0Start.getDate() + wIdx * rule.interval * 7;
            var weekLead = new Date(week0Start.getFullYear(), week0Start.getMonth(), wBaseDay, baseH, baseMi, baseS, baseMs);
            if (weekLead.getTime() > hardEndTime) break;
            var weekCands = [];
            for (var wi = 0; wi < weekOffsets.length; wi++) {
                var wc = new Date(week0Start.getFullYear(), week0Start.getMonth(),
                    wBaseDay + weekOffsets[wi], baseH, baseMi, baseS, baseMs);
                if (rule.byMonth && rule.byMonth.indexOf(wc.getMonth() + 1) < 0) continue;
                weekCands.push(wc);
            }
            weekCands = _applyBySetPos(weekCands, rule.bySetPos);
            for (var wci = 0; wci < weekCands.length; wci++) {
                if (!emitCandidate(weekCands[wci])) { stopWeekly = true; break; }
            }
            wIdx++;
        }
    } else if (rule.freq === "monthly") {
        var mIdx = 0;
        if (!rule.count && startTime < winStartTime) {
            var monthsDiff = (winStart.getFullYear() - startDate.getFullYear()) * 12
                + (winStart.getMonth() - startDate.getMonth());
            mIdx = Math.max(0, Math.floor(monthsDiff / rule.interval) - 2);
        }
        var mSteps = 0;
        var stopMonthly = false;
        while (mSteps++ < maxSteps && !stopMonthly) {
            var totalMonth = startDate.getFullYear() * 12 + startDate.getMonth() + mIdx * rule.interval;
            var yrM = Math.floor(totalMonth / 12);
            var moM = ((totalMonth % 12) + 12) % 12;
            var firstOfMonth = new Date(yrM, moM, 1, 0, 0, 0, 0);
            if (firstOfMonth.getTime() > hardEndTime) break;
            if (rule.byMonth && rule.byMonth.indexOf(moM + 1) < 0) { mIdx++; continue; }

            var monthCands = _applyBySetPos(
                _datesForMonthCandidates(yrM, moM, rule, startDate.getDate(), baseH, baseMi, baseS, baseMs),
                rule.bySetPos
            );
            for (var mc = 0; mc < monthCands.length; mc++) {
                if (!emitCandidate(monthCands[mc])) { stopMonthly = true; break; }
            }
            mIdx++;
        }
    } else if (rule.freq === "yearly") {
        var yIdx = 0;
        if (!rule.count && startTime < winStartTime) {
            var yearsDiff = winStart.getFullYear() - startDate.getFullYear();
            yIdx = Math.max(0, Math.floor(yearsDiff / rule.interval) - 1);
        }
        var ySteps = 0;
        var stopYearly = false;
        var targetMonths = rule.byMonth
            ? rule.byMonth.map(function(m) { return m - 1; }).sort(function(a, b) { return a - b; })
            : [startDate.getMonth()];
        while (ySteps++ < maxSteps && !stopYearly) {
            var yrY = startDate.getFullYear() + yIdx * rule.interval;
            if (new Date(yrY, 0, 1).getTime() > hardEndTime) break;
            var yearCands = [];
            for (var tm = 0; tm < targetMonths.length; tm++) {
                var moY = targetMonths[tm];
                var mcY = _datesForMonthCandidates(yrY, moY, rule, startDate.getDate(), baseH, baseMi, baseS, baseMs);
                for (var miY = 0; miY < mcY.length; miY++) yearCands.push(mcY[miY]);
            }
            yearCands = _applyBySetPos(yearCands, rule.bySetPos);
            for (var yc = 0; yc < yearCands.length; yc++) {
                if (!emitCandidate(yearCands[yc])) { stopYearly = true; break; }
            }
            yIdx++;
        }
    }

    return results;
}

// Unescape ICS special characters
function _unescapeICS(text) {
    if (!text) return "";
    return text
        .replace(/\\[nN]/g, "\n")
        .replace(/\\,/g, ",")
        .replace(/\\;/g, ";")
        .replace(/\\\\/g, "\\");
}
