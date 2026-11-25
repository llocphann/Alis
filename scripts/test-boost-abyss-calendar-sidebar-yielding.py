#!/usr/bin/env python3
"""Comprehensive 100% silent verification for the 5-domain Alis upgrade:
1. Edit Abyss Layout: Built-in + user presets (Modules, Screen Edge, Popups/IPC, Companion),
   Undo/Cancel/Done position persistence, and borderless constant-surface detached pills.
2. Calendar: RFC 5545 ICS parser (VALARM nesting, LF/CRLF unfolding, STATUS:CANCELLED,
   DURATION, TZID + Windows names, multi-year RRULE with INTERVAL/BYDAY ordinals/BYMONTH/
   BYMONTHDAY/EXDATE/RECURRENCE-ID, zero setMonth rollover), webcal:// normalization on write
   and read-time, offline cache preservation, 1-click holiday presets, and Weekly/Yearly Planner
   holiday badges & day tints.
3. Left Sidebar: Borderless tab container (keeping bright activeIndicator), hover-revealed
   0px-collapsed Arrange button, and restored Abyss cloud gradient background in Translator.
4. Notifications/Activity Edgebar Lockout: Reproduces Hover Edgebar -> Right Sidebar ->
   Dashboard Open -> Dashboard Close -> Hover Edgebar again across multiple cycles.
5. Alis Smart Popup Yielding (A1 + A2 #1-#5): Cooperative shrinking, bounded tangential
   lateral shift before shrinking/Pyramid, heavy overlay mutual exclusion, intent priority
   (explicit/pinned/typing > hover without hover-swapping), differentiated eviction lifecycle
   (close hover leases, temp-hide & auto-restore explicit/focused), and unified Generic Popup
   + Companion externalBlockers participation.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import native_test_session  # noqa: E402


def run_node(js_code: str, label: str) -> None:
    res = subprocess.run(
        ["node", "-e", js_code],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=20,
    )
    if res.returncode != 0:
        raise AssertionError(f"[{label}] Node check failed:\n{res.stdout}\n{res.stderr}")
    print(f"PASS [{label}]: {res.stdout.strip()}")


def test_presets_and_calendar_and_yielding_js() -> None:
    layout_js = (ROOT / "modules/abyss/looks/AbyssLayout.js").read_text(encoding="utf-8")
    presets_js = (ROOT / "modules/abyss/looks/AbyssLayoutPresets.js").read_text(encoding="utf-8")
    geom_js = (ROOT / "modules/abyss/looks/AbyssGeometry.js").read_text(encoding="utf-8")
    place_js = (ROOT / "modules/abyss/looks/AbyssBodyPlacement.js").read_text(encoding="utf-8")
    ics_js = (ROOT / "services/calendar_ics.js").read_text(encoding="utf-8")
    weekly_js = (ROOT / "modules/dashboard/WeeklyPlannerPolicy.js").read_text(encoding="utf-8")
    yearly_js = (ROOT / "modules/dashboard/YearlyPlannerPolicy.js").read_text(encoding="utf-8")
    tab_policy_js = (ROOT / "modules/dashboard/DashboardCustomTabPolicy.js").read_text(encoding="utf-8")

    # 1. Presets unit tests (built-in, capture, upsert, remove, corrupt legacy fixtures)
    run_node(
        f"const Placement=(function(){{{layout_js}\nreturn {{normalize,catalog}};}})();\n"
        f"const Presets=(function(){{{presets_js}\nreturn {{builtInPresets,normalizePreset,normalizeUserPresets,allPresets,nextDefaultName,capturePreset,upsertUserPreset,removeUserPreset}};}})();\n"
        r"""
const assert = require("node:assert/strict");

const samples = Presets.builtInPresets();
assert.equal(samples.length, 0, "must expose zero built-in sample presets");
const all0 = Presets.allPresets([], Placement);
assert.equal(all0.length, 0, "fresh preset list starts empty");

// Legacy built-in entries persisted in old configs are normalized as deletable non-locked presets
const legacyPreset = Presets.normalizePreset({
    id: "builtin-classic-top",
    name: "Old Classic",
    builtIn: true,
    modules: { placements: [{ id: "clock", kind: "clock", edge: "top", position: 0.5 }] }
}, Placement);
assert.equal(legacyPreset.builtIn, false, "all presets normalized unlocked/deletable");
assert.equal(legacyPreset.icon, "bookmark");

// Capture full state (modules + screen edge + positions + companion)
const captured = Presets.capturePreset("Work Setup", {
    draft: [
        { id: "clock", kind: "clock", edge: "top", position: 0.5, detached: true },
        { id: "invalidKind", kind: "doesNotExist", edge: "top", position: 0.2 }
    ],
    gap: 12,
    moduleScale: 1.15,
    edgeSizes: { top: 1.1, right: 1, bottom: 1, left: 1 },
    edgeThicknesses: { top: 20, right: -1, bottom: -1, left: -1 },
    edgeWidthAffectsModules: { top: false, right: true, bottom: true, left: true },
    edgeJoinModules: { top: true, right: false, bottom: false, left: false },
    edgeModuleRadii: { top: 14, right: -1, bottom: -1, left: -1 },
    edgeRoundZeroCorners: { top: true, right: false, bottom: false, left: false },
    singleModuleExpansion: { top: "local", right: "edge", bottom: "edge", left: "edge" },
    draftPositions: [{ kind: "osd", outputName: "DP-1", edge: "bottom", alignment: "end", position: 0.9 }],
    companionDraftEdge: "right",
    companionDraftAlong: 0.42
}, Placement);
assert.equal(captured.name, "Work Setup");
assert.equal(captured.builtIn, false);
assert.equal(captured.modules.placements.length, 1, "invalid kinds pruned safely");
assert.equal(captured.modules.placements[0].detached, true);
assert.equal(captured.modules.gap, 12);
assert.equal(captured.modules.edgeThicknesses.top, 20);
assert.equal(captured.modules.edgeJoinModules.top, true);
assert.equal(captured.modules.singleModuleExpansion.top, "local");
assert.equal(captured.positions.length, 1);
assert.equal(captured.positions[0].edge, "bottom");
assert.equal(captured.companion.edge, "right");
assert.equal(captured.companion.along, 0.42);

// Upsert + case-insensitive overwrite + corrupt legacy resilience + universal deletion (zero locked presets)
const dirtyLegacy = [null, 42, { id: "", name: "" }, { id: "builtin-classic-top", name: "Old Sample", builtIn: true }, captured];
const normUsers = Presets.normalizeUserPresets(dirtyLegacy, Placement);
assert.equal(normUsers.length, 2);
assert.ok(normUsers.every(p => p.builtIn === false));

const updated = Presets.capturePreset("work setup", {
    draft: [{ id: "media", kind: "media", edge: "bottom", position: 0.5 }],
    gap: 6, moduleScale: 1, draftPositions: [], companionDraftEdge: "left", companionDraftAlong: 0.5
}, Placement);
const afterUpsert = Presets.upsertUserPreset(normUsers, updated, Placement);
assert.equal(afterUpsert.length, 2, "case-insensitive name updates existing preset");
assert.equal(afterUpsert.find(p => p.name === "work setup").id, captured.id, "id preserved across update");
assert.equal(afterUpsert.find(p => p.name === "work setup").modules.gap, 6);

const afterDeleteLegacyBuiltIn = Presets.removeUserPreset(afterUpsert, "builtin-classic-top", Placement);
assert.equal(afterDeleteLegacyBuiltIn.length, 1, "even builtin-* preset id must be deletable");
const afterDeleteUser = Presets.removeUserPreset(afterDeleteLegacyBuiltIn, captured.id, Placement);
assert.equal(afterDeleteUser.length, 0);

// Unnamed fallback name collision test: deleting Preset 1 while Preset 2 exists must produce Preset 3, never overwrite Preset 2!
let seqUsers = [];
const seq1 = Presets.capturePreset(Presets.nextDefaultName(seqUsers, "Preset", Placement), { gap: 8 }, Placement);
seqUsers = Presets.upsertUserPreset(seqUsers, seq1, Placement);
const seq2 = Presets.capturePreset(Presets.nextDefaultName(seqUsers, "Preset", Placement), { gap: 16 }, Placement);
seqUsers = Presets.upsertUserPreset(seqUsers, seq2, Placement);
seqUsers = Presets.removeUserPreset(seqUsers, seq1.id, Placement);
const seq3Name = Presets.nextDefaultName(seqUsers, "Preset", Placement);
assert.equal(seq3Name, "Preset 1", "reuses free Preset 1 slot without colliding with Preset 2");
const seq3 = Presets.capturePreset(seq3Name, { gap: 4 }, Placement);
seqUsers = Presets.upsertUserPreset(seqUsers, seq3, Placement);
assert.equal(seqUsers.length, 2, "Preset 2 preserved untouched");
assert.equal(seqUsers.find(p => p.name === "Preset 2").modules.gap, 16);
const seq4Name = Presets.nextDefaultName(seqUsers, "Preset", Placement);
assert.equal(seq4Name, "Preset 3");

console.log("presets unit assertions ok");
""",
        "LayoutPresets",
    )

    # 2. Calendar ICS parser + Weekly/Yearly Planner holiday projection unit tests
    run_node(
        f"const ICS=(function(){{{ics_js}\nreturn {{parseICS}};}})();\n"
        f"const Weekly=(function(){{{weekly_js}\nreturn {{project}};}})();\n"
        f"const Yearly=(function(){{{yearly_js}\nreturn {{projectYearBoard}};}})();\n"
        r"""
const assert = require("node:assert/strict");

// Comprehensive ICS fixture exercising:
// - LF-only folded lines
// - Nested VALARM with its own SUMMARY/DESCRIPTION/DURATION (must NOT overwrite VEVENT!)
// - STATUS:CANCELLED (must be skipped)
// - Multi-year yearly RRULE starting in 2015 (must NOT exhaust at 365 or 90 days)
// - BYMONTH + ordinal BYDAY (Thanksgiving 4TH Nov + Memorial Day -1MO May)
// - Monthly day-31 without setMonth rollover into March
// - Weekly INTERVAL=2 BYDAY=MO,WE,FR COUNT=6
// - EXDATE exclusion & RECURRENCE-ID override
// - DURATION without DTEND & Outlook Windows TZID
const sampleIcs = [
"BEGIN:VCALENDAR",
"VERSION:2.0",
// 1. Holiday with nested VALARM & LF folding & DURATION
"BEGIN:VEVENT",
"UID:vn-tet-2026",
"DTSTART;VALUE=DATE:20260217",
"DURATION:P3D",
"SUMMARY:Tết Nguyên",
" Đán (Lunar New Year)",
"DESCRIPTION:Vietnamese Lunar New Year",
"BEGIN:VALARM",
"ACTION:DISPLAY",
"TRIGGER:-PT15M",
"DURATION:PT5M",
"SUMMARY:ALARM SHOULD BE IGNORED",
"DESCRIPTION:ALARM DESC SHOULD BE IGNORED",
"END:VALARM",
"END:VEVENT",
// 2. Cancelled event (must be ignored)
"BEGIN:VEVENT",
"UID:cancelled-1",
"DTSTART;VALUE=DATE:20260220",
"SUMMARY:Cancelled Meeting",
"STATUS:CANCELLED",
"END:VEVENT",
// 3. Old DTSTART yearly holiday (2015) expanding across 2025..2028
"BEGIN:VEVENT",
"UID:vn-national-day",
"DTSTART;VALUE=DATE:20150902",
"RRULE:FREQ=YEARLY",
"SUMMARY:National Day (2/9)",
"END:VEVENT",
// 4. US Thanksgiving (4th Thursday of November) + Memorial Day (last Monday of May)
"BEGIN:VEVENT",
"UID:us-thanksgiving",
"DTSTART;VALUE=DATE:20201126",
"RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH",
"SUMMARY:Thanksgiving",
"END:VEVENT",
"BEGIN:VEVENT",
"UID:us-memorial",
"DTSTART;VALUE=DATE:20200525",
"RRULE:FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO",
"SUMMARY:Memorial Day",
"END:VEVENT",
// 5. Monthly 31st (must skip Feb/Apr, NEVER roll over to Mar 3 or May 1)
"BEGIN:VEVENT",
"UID:monthly-31",
"DTSTART;VALUE=DATE:20260131",
"RRULE:FREQ=MONTHLY;COUNT=4",
"SUMMARY:Month End Review",
"END:VEVENT",
// 6. Weekly INTERVAL=2 BYDAY=MO,WE,FR COUNT=6 + EXDATE + RECURRENCE-ID override
"BEGIN:VEVENT",
"UID:standup-1",
"DTSTART;TZID=\"SE Asia Standard Time\":20260302T090000",
"DURATION:PT1H30M",
"RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=6",
"EXDATE;TZID=\"SE Asia Standard Time\":20260304T090000",
"SUMMARY:Team Standup",
"END:VEVENT",
"BEGIN:VEVENT",
"UID:standup-1",
"RECURRENCE-ID;TZID=\"SE Asia Standard Time\":20260306T090000",
"DTSTART;TZID=\"SE Asia Standard Time\":20260306T110000",
"DURATION:PT1H",
"SUMMARY:Team Standup (Moved)",
"END:VEVENT",
"END:VCALENDAR"
].join("\n");

const winStart = new Date(2025, 0, 1);
const winEnd = new Date(2028, 11, 31, 23, 59, 59);
const parsed = ICS.parseICS(sampleIcs, "src_hol", "Holidays", "#EA4335", {
    isHoliday: true,
    windowStart: winStart,
    windowEnd: winEnd
});

const isoDay = ev => {
    const d = new Date(ev.startDate);
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
};

// VALARM + folding + DURATION
const tet = parsed.find(e => e.uid === "vn-tet-2026");
assert.ok(tet, "Tet event parsed");
assert.equal(tet.title, "Tết NguyênĐán (Lunar New Year)");
assert.equal(tet.description, "Vietnamese Lunar New Year");
assert.equal(tet.isHoliday, true);
assert.equal(tet.kind, "holiday");
assert.equal(Math.round((new Date(tet.endDate) - new Date(tet.startDate)) / 86400000), 3, "DURATION:P3D => 3 days");

// STATUS:CANCELLED skipped
assert.equal(parsed.some(e => e.uid === "cancelled-1"), false, "cancelled event omitted");

// Multi-year expansion for 2015 DTSTART covers 2025, 2026, 2027, 2028
const natDays = parsed.filter(e => e.uid.startsWith("vn-national-day")).map(isoDay);
assert.deepEqual(natDays, ["2025-09-02", "2026-09-02", "2027-09-02", "2028-09-02"]);

// Ordinal BYDAY: Thanksgiving & Memorial Day
const tg2026 = parsed.filter(e => e.uid.startsWith("us-thanksgiving")).map(isoDay);
assert.ok(tg2026.includes("2026-11-26") && tg2026.includes("2027-11-25"), "Thanksgiving 4TH Nov: " + tg2026);
const mem2026 = parsed.filter(e => e.uid.startsWith("us-memorial")).map(isoDay);
assert.ok(mem2026.includes("2026-05-25") && mem2026.includes("2027-05-31"), "Memorial Day -1MO May: " + mem2026);

// Monthly 31st — zero setMonth rollover (must be Jan 31, Mar 31, May 31, Jul 31)
const m31 = parsed.filter(e => e.uid.startsWith("monthly-31")).map(isoDay);
assert.deepEqual(m31, ["2026-01-31", "2026-03-31", "2026-05-31", "2026-07-31"]);

// Weekly INTERVAL=2 BYDAY=MO,WE,FR COUNT=6 + EXDATE (Mar 4 excluded) + RECURRENCE-ID (Mar 6 moved)
const standups = parsed.filter(e => e.uid.startsWith("standup-1"));
const standupDates = standups.map(isoDay).sort();
// Raw 6 occurrences: Mar 2, Mar 4 (EXDATE), Mar 6 (overridden), Mar 16, Mar 18, Mar 20 -> 5 remaining (incl. 1 override)
assert.equal(standups.length, 5, "EXDATE + RECURRENCE-ID dedup: " + JSON.stringify(standupDates));
assert.ok(!standupDates.includes("2026-03-04"), "EXDATE removed Mar 4");
const moved = standups.find(e => e.title === "Team Standup (Moved)");
assert.ok(moved, "RECURRENCE-ID override present");
assert.equal(new Date(moved.startDate).getUTCHours(), 4, "SE Asia Standard Time (UTC+7) 11:00 => 04:00 UTC");

// 7. Quoted colons in parameters (UTF-8 BOM + TZID="UTC+07:00" + ALTREP="http://...")
const quotedIcs = "\uFEFF" + [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "UID:quoted-1",
    "DTSTART;TZID=\"UTC+07:00\":20260510T090000",
    "DTEND;TZID=\"UTC+07:00\":20260510T100000",
    "SUMMARY;ALTREP=\"http://example.com/cal\":Quoted Colon Event",
    "END:VEVENT",
    "END:VCALENDAR"
].join("\r\n");
const parsedQuoted = ICS.parseICS(quotedIcs, "q1", "Q", "#4285F4");
assert.equal(parsedQuoted.length, 1, "quoted colon + BOM event parsed");
assert.equal(parsedQuoted[0].title, "Quoted Colon Event");
assert.equal(new Date(parsedQuoted[0].startDate).getUTCHours(), 2, "UTC+07:00 09:00 => 02:00 UTC");

// 8. BYSETPOS=-1 (last weekday of month)
const bySetPosIcs = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "UID:payday",
    "DTSTART;VALUE=DATE:20260130",
    "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
    "SUMMARY:Payday",
    "END:VEVENT",
    "END:VCALENDAR"
].join("\r\n");
const paydays = ICS.parseICS(bySetPosIcs, "q1", "Q", "#4285F4", {
    windowStart: new Date(2026, 0, 1),
    windowEnd: new Date(2026, 2, 31, 23, 59, 59)
}).map(isoDay);
assert.deepEqual(paydays, ["2026-01-30", "2026-02-27", "2026-03-31"], "BYSETPOS=-1 exact last weekday per month");

// 9. Combined BYDAY + BYMONTHDAY intersection (Friday the 13th in 2026)
const fri13Ics = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "UID:fri13",
    "DTSTART;VALUE=DATE:20260213",
    "RRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13",
    "SUMMARY:Friday 13th",
    "END:VEVENT",
    "END:VCALENDAR"
].join("\r\n");
const fri13 = ICS.parseICS(fri13Ics, "q1", "Q", "#4285F4", {
    windowStart: new Date(2026, 0, 1),
    windowEnd: new Date(2026, 11, 31, 23, 59, 59)
}).map(isoDay);
assert.deepEqual(fri13, ["2026-02-13", "2026-03-13", "2026-11-13"], "BYDAY+BYMONTHDAY intersection");

// 10. All-day UNTIL in UTC must NEVER emit a +1 ghost day in UTC+ timezones
const untilAllDayIcs = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "UID:until-allday",
    "DTSTART;VALUE=DATE:20261229",
    "RRULE:FREQ=DAILY;UNTIL=20261231T235959Z",
    "SUMMARY:Year End",
    "END:VEVENT",
    "END:VCALENDAR"
].join("\r\n");
const untilDays = ICS.parseICS(untilAllDayIcs, "q1", "Q", "#4285F4", {
    windowStart: new Date(2026, 11, 1),
    windowEnd: new Date(2027, 0, 5)
}).map(isoDay);
assert.deepEqual(untilDays, ["2026-12-29", "2026-12-30", "2026-12-31"], "all-day UTC UNTIL stops cleanly on Dec 31");

// Weekly Planner holiday projection & sorting
const weekDays = Weekly.project(
    [{ id: 1, title: "Regular All Day", allDay: true, startDate: new Date(2026, 1, 17).toISOString(), endDate: new Date(2026, 1, 18).toISOString() }],
    [tet],
    new Date(2026, 1, 17),
    1
);
const tue = weekDays.find(d => d.date.getDate() === 17);
assert.ok(tue && tue.holidayCount === 1 && tue.holidays.length === 1);
assert.equal(tue.allDay[0].isHoliday, true, "holidays sort before regular all-day events");

// Yearly Planner holiday projection (day cell flag, dayHolidaysMap, summary.holidayCount)
const yearBoard = Yearly.projectYearBoard([], new Date(2026, 0, 1), "calendar", "2026-02-01", "", {
    showExternal: true,
    externalEvents: parsed
});
assert.ok(yearBoard.summary.holidayCount >= 3, "yearly summary counts holiday spans");
const feb = yearBoard.months[1];
const feb17 = feb.days[16];
const feb19 = feb.days[18];
assert.equal(feb17.isHoliday, true, "Feb 17 marked holiday");
assert.equal(feb19.isHoliday, true, "Feb 19 (3rd day of Tet) marked holiday");
assert.ok(feb17.holidays.some(h => h.title.includes("Tết")));
console.log("calendar ICS + Weekly/Yearly holiday assertions ok");
""",
        "CalendarICSAndPlanners",
    )

    # 3. Smart Popup Yielding allocator unit tests (A1 + A2 #1, #3, #5)
    run_node(
        f"{geom_js}\n{place_js}\n"
        r"""
const assert = require("node:assert/strict");
const hdInsets = { left: 14, right: 14, top: 40, bottom: 14 };

function overlap(a, b, gap = 0) {
    return a.x < b.x + b.width + gap && a.x + a.width + gap > b.x
        && a.y < b.y + b.height + gap && a.y + a.height + gap > b.y;
}
function mkReq(id, edge, order, depth, along, span, W, H, opts = {}) {
    const padding = opts.padding ?? 14;
    const record = panel(W, H, hdInsets, edge, along, span, depth, 1, padding, [], opts.largeSurface ?? false);
    return {
        id, open: true, order,
        priority: opts.priority ?? 0,
        intentWeight: opts.intentWeight ?? 0,
        padding,
        allowInward: opts.allowInward ?? true,
        allowLateralShift: opts.allowLateralShift ?? ((opts.maxLateralShift ?? 0) > 0),
        maxLateralShift: opts.maxLateralShift,
        cooperativeShrink: opts.cooperativeShrink ?? false,
        cooperativePeer: opts.cooperativePeer ?? false,
        stackPolicy: opts.stackPolicy ?? "",
        stackProximity: opts.stackProximity ?? 24,
        minSpan: Math.min(record.span, opts.minSpan ?? (opts.largeSurface ? 680 : 220)),
        minDepth: Math.min(record.targetDepth, opts.minDepth ?? (opts.largeSurface ? 460 : 120)),
        record
    };
}

// (A1) 1920x1080: Dashboard + Left Sidebar + Right Sidebar cooperate without crushing sidebars!
const left1920 = mkReq("leftPanel", "left", 1, 460, 140, 760, 1920, 1080, {
    priority: 2, intentWeight: 1, minDepth: 320, minSpan: 320, cooperativePeer: true
});
const right1920 = mkReq("rightPanel", "right", 2, 460, 140, 760, 1920, 1080, {
    priority: 2, intentWeight: 0, minDepth: 360, minSpan: 420, cooperativePeer: true
});
const dash1920 = mkReq("dashboard", "bottom", 3, 818, 249, 1422, 1920, 1080, {
    priority: 3, intentWeight: 2, largeSurface: true, minSpan: 920, minDepth: 460, cooperativeShrink: true
});
const res1920 = arrange([left1920, right1920, dash1920], 1920, 1080, hdInsets, 24);
assert.equal(res1920.dashboard.visible, true);
assert.equal(res1920.leftPanel.visible, true);
assert.equal(res1920.rightPanel.visible, true);
assert.ok(res1920.leftPanel.depth >= 320, "Left sidebar never crushed below 320px: " + res1920.leftPanel.depth);
assert.ok(res1920.rightPanel.depth >= 360, "Right sidebar never crushed below 360px: " + res1920.rightPanel.depth);
assert.ok(res1920.dashboard.span >= 920 && res1920.dashboard.shrunk, "Dashboard cooperatively shrunk: " + res1920.dashboard.span);
assert.ok(!overlap(res1920.leftPanel.content, res1920.dashboard.content, 23.9));
assert.ok(!overlap(res1920.rightPanel.content, res1920.dashboard.content, 23.9));

// (A1 + A2 #3) Tight 1280x720: Dashboard (min 680) + Explicit Left (min 320) + Hover Right (min 360)
// All 3 need 320+24+680+24+360 = 1408 > 1252 -> Explicit Left + Dashboard cooperate, Hover Right yields cleanly!
const left1280 = mkReq("leftPanel", "left", 1, 420, 100, 560, 1280, 720, {
    priority: 2, intentWeight: 1, minDepth: 320, minSpan: 320, cooperativePeer: true
});
const right1280 = mkReq("rightPanel", "right", 2, 420, 100, 560, 1280, 720, {
    priority: 2, intentWeight: 0, minDepth: 360, minSpan: 420, cooperativePeer: true
});
const dash1280 = mkReq("dashboard", "bottom", 3, 540, 160, 960, 1280, 720, {
    priority: 3, intentWeight: 2, largeSurface: true, minSpan: 680, minDepth: 400, cooperativeShrink: true
});
const res1280 = arrange([left1280, right1280, dash1280], 1280, 720, hdInsets, 24);
assert.equal(res1280.dashboard.visible, true);
assert.equal(res1280.leftPanel.visible, true, "Explicit Left Sidebar survives cooperatively on 1280px");
assert.ok(res1280.leftPanel.depth >= 320);
assert.equal(res1280.rightPanel.evicted, true, "Lower-intent Hover Right Sidebar yields cleanly instead of clipping");
assert.ok(!overlap(res1280.leftPanel.content, res1280.dashboard.content, 23.9));

// (A2 #1) Bounded tangential lateral shift along the same Screen Edge BEFORE shrinking/Pyramid!
const topA = mkReq("topA", "top", 1, 200, 400, 360, 1920, 1080, {
    priority: 1, stackPolicy: "pyramid", maxLateralShift: 220
});
const topB = mkReq("topB", "top", 2, 180, 660, 260, 1920, 1080, {
    priority: 0, stackPolicy: "pyramid", maxLateralShift: 220
});
const resShift = arrange([topA, topB], 1920, 1080, hdInsets, 24);
assert.equal(resShift.topA.inward, 0);
assert.equal(resShift.topB.inward, 0, "Partially overlapping peer shifts laterally along SAME edge before stacking inward");
assert.equal(resShift.topB.shrunk, false, "Laterally shifted peer keeps full size");
assert.ok(Math.abs(resShift.topB.lateralShift) > 50 && Math.abs(resShift.topB.lateralShift) <= 220.01);
assert.ok(!overlap(resShift.topA.content, resShift.topB.content, 23.9));

// Same-anchor popups exceed maxLateralShift -> fall back cleanly to Pyramid inward stacking!
const sameA = mkReq("sameA", "top", 1, 200, 700, 420, 1920, 1080, {
    priority: 1, stackPolicy: "pyramid", maxLateralShift: 200
});
const sameB = mkReq("sameB", "top", 2, 180, 700, 420, 1920, 1080, {
    priority: 0, stackPolicy: "pyramid", maxLateralShift: 200
});
const resPyr = arrange([sameA, sameB], 1920, 1080, hdInsets, 24);
assert.equal(resPyr.sameA.inward, 0);
assert.ok(resPyr.sameB.inward > 0, "Heavily overlapping same-anchor popup stacks inward as Pyramid");
assert.equal(resPyr.sameB.lateralShift, 0);

// (A2 #3) Priority/Intent beats resting area inside Pyramid neighborhood!
const smallPinned = mkReq("smallPinned", "top", 1, 140, 700, 240, 1920, 1080, {
    priority: 1, intentWeight: 1, stackPolicy: "pyramid", maxLateralShift: 0
});
const hugeHover = mkReq("hugeHover", "top", 2, 260, 620, 420, 1920, 1080, {
    priority: 0, intentWeight: 0, stackPolicy: "pyramid", maxLateralShift: 0
});
const resIntent = arrange([hugeHover, smallPinned], 1920, 1080, hdInsets, 24);
assert.equal(resIntent.smallPinned.inward, 0, "Smaller pinned/explicit popup owns direct Edge tier over larger hover popup");
assert.ok(resIntent.hugeHover.inward > 0, "Larger hover popup pyramids behind explicit popup");

// (A2 #5) Unified Companion externalBlockers participation
const hoverBarPopup = mkReq("hoverPopup", "bottom", 1, 240, 1200, 320, 1920, 1080, {
    priority: 0, intentWeight: 0, maxLateralShift: 240
});
const companionChat = [{ x: 1240, y: 760, width: 320, height: 280, priority: 2, intentWeight: 1, kind: "companionChat" }];
const resComp = arrange([hoverBarPopup], 1920, 1080, hdInsets, 24, companionChat);
assert.equal(resComp.hoverPopup.visible, true);
assert.ok(!overlap(resComp.hoverPopup.content, companionChat[0], 23.9),
    "Hover popup yields/shifts cleanly around active Companion chat");

// Heavy overlay (prio 3) does NOT yield to lower-priority hover Companion cloud (prio 1)
const dashOnly = mkReq("dashboard", "bottom", 1, 600, 250, 1400, 1920, 1080, {
    priority: 3, intentWeight: 2, largeSurface: true, minSpan: 920, minDepth: 460
});
const hoverCloud = [{ x: 900, y: 700, width: 280, height: 200, priority: 1, intentWeight: 0, kind: "companionCloud" }];
const resDashCloud = arrange([dashOnly], 1920, 1080, hdInsets, 24, hoverCloud);
assert.equal(resDashCloud.dashboard.shrunk, false);
assert.equal(resDashCloud.dashboard.inward, 0);

// (A1 + Polkit modal guard) If a higher-priority modal (polkit prio 5) evicts dashboard's cooperative slot,
// unblocked leftPanel must NOT shrink unnecessarily to its unused cooperative override!
const polkitCenter = mkReq("polkit", "bottom", 4, 620, 610, 700, 1920, 1080, {
    priority: 5, intentWeight: 2, largeSurface: true, minSpan: 500, minDepth: 560
});
const dashBlocked = mkReq("dashboard", "bottom", 3, 760, 249, 1422, 1920, 1080, {
    priority: 3, intentWeight: 2, largeSurface: true, minSpan: 920, minDepth: 460, cooperativeShrink: true
});
const leftUnblocked = mkReq("leftPanel", "left", 1, 460, 190, 700, 1920, 1080, {
    priority: 2, intentWeight: 1, minDepth: 320, minSpan: 320, cooperativePeer: true
});
const resPolkit = arrange([polkitCenter, dashBlocked, leftUnblocked], 1920, 1080, hdInsets, 24);
assert.equal(resPolkit.dashboard.evicted, true, "Polkit evicts dashboard cleanly");
assert.equal(resPolkit.leftPanel.visible, true);
assert.equal(resPolkit.leftPanel.depth, 460, "Unblocked sidebar keeps full 460px when Polkit evicts dashboard");
assert.notEqual(resPolkit.leftPanel.cooperativeShrunk, true);

// (A1 + Companion Pocket externalBlocker) When Pocket blocks hover leftPanel, cooperative negotiation excludes
// leftPanel so dashboard + rightPanel keep full cooperative space instead of shrinking for an evicted sidebar!
const leftBlockedByPocket = mkReq("leftPanel", "left", 1, 460, 190, 700, 1920, 1080, {
    priority: 2, intentWeight: 0, minDepth: 320, minSpan: 320, cooperativePeer: true
});
const rightFree = mkReq("rightPanel", "right", 2, 460, 190, 700, 1920, 1080, {
    priority: 2, intentWeight: 0, minDepth: 360, minSpan: 420, cooperativePeer: true
});
const dashWithPocket = mkReq("dashboard", "bottom", 3, 760, 249, 1422, 1920, 1080, {
    priority: 3, intentWeight: 2, largeSurface: true, minSpan: 920, minDepth: 460, cooperativeShrink: true
});
const pocketExt = [{ x: 30, y: 200, width: 320, height: 680, priority: 2, intentWeight: 1, kind: "companionPocket" }];
const resPocket = arrange([dashWithPocket, leftBlockedByPocket, rightFree], 1920, 1080, hdInsets, 24, pocketExt);
assert.ok(resPocket.dashboard.span >= 1400, "Dashboard keeps full width when Pocket already blocks hover leftPanel (got " + resPocket.dashboard.span + ")");
assert.equal(resPocket.rightPanel.depth, 460, "Right sidebar stays full 460px");

// (A1 + minimumInward) Cooperative negotiation accounts for peer minimumInward without colliding!
const leftInward = Object.assign(mkReq("leftPanel", "left", 1, 460, 190, 700, 1920, 1080, {
    priority: 2, intentWeight: 1, minDepth: 320, minSpan: 320, cooperativePeer: true
}), { minimumInward: 60 });
const dashInward = mkReq("dashboard", "bottom", 3, 760, 249, 1422, 1920, 1080, {
    priority: 3, intentWeight: 2, largeSurface: true, minSpan: 920, minDepth: 460, cooperativeShrink: true
});
const resInward = arrange([dashInward, leftInward], 1920, 1080, hdInsets, 24);
assert.equal(resInward.dashboard.visible, true);
assert.equal(resInward.leftPanel.visible, true);
assert.equal(resInward.leftPanel.inward, 60);
assert.ok(!overlap(resInward.leftPanel.content, resInward.dashboard.content, 23.9));

console.log("smart popup yielding allocator assertions ok");
""",
        "SmartPopupYieldingJS",
    )

    # 4. DashboardCustomTabPolicy icon policy + legacy compatibility tests
    run_node(
        f"const TabPolicy=(function(){{{tab_policy_js}\nreturn {{defaultIconFor,sanitizeIconName,tabIcons,iconFor,hasCustomIcon,setTabIcon,removeTabIcon,presetTabIcons}};}})();\n"
        r"""
const assert = require("node:assert/strict");

assert.equal(TabPolicy.defaultIconFor("dashboard"), "dashboard");
assert.equal(TabPolicy.defaultIconFor("music"), "library_music");
assert.equal(TabPolicy.defaultIconFor("weeklyPlanner"), "calendar_month");
assert.equal(TabPolicy.defaultIconFor("spacedRepetition"), "school");
assert.equal(TabPolicy.defaultIconFor("exercisesTracker"), "fitness_center");
assert.equal(TabPolicy.defaultIconFor("custom-7"), "tab");

assert.equal(TabPolicy.sanitizeIconName("  Rocket-Launch! "), "rocket_launch");
assert.equal(TabPolicy.sanitizeIconName(""), "");

// Legacy empty / undefined / malformed / plain object tolerance
assert.deepEqual(TabPolicy.tabIcons(undefined), []);
assert.equal(TabPolicy.iconFor(undefined, "dashboard"), "dashboard");
assert.equal(TabPolicy.iconFor([null, {id:"", icon:"star"}, {id:"music", icon:"album"}], "music"), "album");
assert.equal(TabPolicy.iconFor({dashboard:"home", weeklyPlanner:"event"}, "weeklyPlanner"), "event");

// Set / reset / remove lifecycle
let icons = TabPolicy.setTabIcon([], "dashboard", "Home");
assert.deepEqual(icons, [{id:"dashboard", icon:"home"}]);
assert.equal(TabPolicy.hasCustomIcon(icons, "dashboard"), true);
assert.equal(TabPolicy.iconFor(icons, "dashboard"), "home");

// Setting back to default removes redundant override cleanly
icons = TabPolicy.setTabIcon(icons, "dashboard", "dashboard");
assert.deepEqual(icons, []);
assert.equal(TabPolicy.hasCustomIcon(icons, "dashboard"), false);

icons = TabPolicy.setTabIcon([{id:"custom-1", icon:"bolt"}, {id:"music", icon:"headphones"}], "custom-1", "rocket_launch");
assert.deepEqual(TabPolicy.removeTabIcon(icons, "custom-1"), [{id:"music", icon:"headphones"}]);
assert.ok(TabPolicy.presetTabIcons.length >= 24);
console.log("dashboard tab icon policy assertions ok");
""",
        "DashboardTabIconsPolicyJS",
    )


def test_quickshell_silent_runtime() -> None:
    if not shutil.which("qs"):
        print("SKIP_SILENT_RUNTIME: qs unavailable")
        return

    # Verify AbyssPerimeter heavy overlay mutual exclusion & anti-hover-swap contracts
    perim_src = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    cal_sync_src = (ROOT / "services/CalendarSync.qml").read_text(encoding="utf-8")
    assert "BEGIN:VCALENDAR" in cal_sync_src, "CalendarSync must reject non-ICS error pages to preserve offline cache"
    for required in (
        "function closeOtherHeavyOverlays(exceptKind: string): void",
        "closeOtherHeavyOverlays(\"dashboard\")",
        "closeOtherHeavyOverlays(\"settings\")",
        "closeOtherHeavyOverlays(\"nexus\")",
        "closeOtherHeavyOverlays(\"overview\")",
        "closeOtherHeavyOverlays(\"controls\")",
        "edgebarBlocked: corners.blocked",
        "companionExtension.popupOpen && !companionExtension.editing",
        "pairsWithLeftSidebar && !pairsWithRightSidebar\n                                ? leftPanel.placementPriority\n                                : pairsWithRightSidebar && !pairsWithLeftSidebar\n                                    ? rightPanel.placementPriority",
        "placementCanShiftLaterally: false",
        "placementIntent: _latchedExplicitIntent ? \"explicit\" : \"hover\"",
        "onSemanticOpenChanged: _latchedExplicitIntent = semanticOpen ? explicitOrFocusedPopup : false",
    ):
        if required not in perim_src:
            raise AssertionError(f"AbyssPerimeter missing required smart yielding wiring: {required}")
    for forbidden in (
        "placementIntent: explicitOrFocusedPopup ? \"explicit\" : \"hover\"",
        "placementIntent: explicitOrFocused ? \"explicit\" : \"hover\"",
        "promoteInteractionOrder(",
    ):
        if forbidden in perim_src:
            raise AssertionError(f"AbyssPerimeter MUST NOT mutate open placement intent or hover-swap: {forbidden}")
    for src_rel in (
        "modules/sidebarLeft/Translator.qml",
        "modules/sidebarLeft/news/NewsView.qml",
        "modules/sidebarLeft/ToolsView.qml",
    ):
        src_txt = (ROOT / src_rel).read_text(encoding="utf-8")
        if "height: 1.5" in src_txt:
            raise AssertionError(f"{src_rel} must not render the 1.5px top accent line")
        if "anchors.margins: 0" not in src_txt:
            raise AssertionError(f"{src_rel} background must use anchors.margins: 0 for 1px content border")
    ai_src = (ROOT / "modules/sidebarLeft/AiChat.qml").read_text(encoding="utf-8")
    if "anchors.margins: 0" not in ai_src:
        raise AssertionError("AiChat.qml companionChatLoader must use anchors.margins: 0 for 1px content border")
    for token in (
        "readonly property bool _companionChatWanted:",
        "id: legacyChatLoader",
        "active: !root._companionChatWanted",
        "id: legacyChatComp",
    ):
        if token not in ai_src:
            raise AssertionError(f"AiChat.qml missing lazy fallback chat token: {token}")

    # Fast zero-loading-screen Sidebars + background warmup + lazy tab/mask contracts
    lp_block_match = re.search(r"id:\s*leftPanel\b(.*?)id:\s*rightPanel\b", perim_src, re.DOTALL)
    rp_block_match = re.search(r"id:\s*rightPanel\b(.*?)id:\s*popup\b", perim_src, re.DOTALL)
    assert lp_block_match and rp_block_match, "Could not locate leftPanel / rightPanel blocks in AbyssPerimeter.qml"
    for panel_name, block in (("leftPanel", lp_block_match.group(1)), ("rightPanel", rp_block_match.group(1))):
        for req in ("showLoadingSurface: false", "warmContent: true", "retainAfterFirstOpen: true"):
            if req not in block:
                raise AssertionError(f"AbyssPerimeter {panel_name} missing instant-open contract: {req}")
        if "showLoadingSurface: true" in block:
            raise AssertionError(f"AbyssPerimeter {panel_name} must not enable showLoadingSurface: true")
    for reveal_token in (
        "onEdgeHoveredChanged: if (edgeHovered && !leftPanel.backgroundPreload) leftPanel.backgroundPreload = true",
        "onEdgeHoveredChanged: if (edgeHovered && !rightPanel.backgroundPreload) rightPanel.backgroundPreload = true",
        "readonly property bool sidebarWarmupIdle:",
        "window._warmupCursor === 0 ? 350",
        ": (window._warmupCursor === 1 ? 450 : 1200)",
    ):
        if reveal_token not in perim_src:
            raise AssertionError(f"AbyssPerimeter missing sidebar warmup speedup token: {reveal_token}")

    slc_src = (ROOT / "modules/sidebarLeft/SidebarLeftContent.qml").read_text(encoding="utf-8")
    if "asynchronous: !SwipeView.isCurrentItem && swipeView.currentIndex !== index" not in slc_src:
        raise AssertionError("SidebarLeftContent.qml tabLoader must load non-current tabs asynchronously")

    compact_right_src = (ROOT / "modules/sidebarRight/CompactSidebarRightContent.qml").read_text(encoding="utf-8")
    for tok in (
        "layer.enabled: root.panelVisible && !root.externalConnectedSurface && !gameModeMinimal",
        "layer.enabled: root.panelVisible && !root.externalConnectedSurface && !bg.gameModeMinimal",
        "asynchronous: !sectionItem.isCurrent && status !== Loader.Ready",
    ):
        if tok not in compact_right_src:
            raise AssertionError(f"CompactSidebarRightContent.qml missing speedup token: {tok}")

    # Edit Abyss Layout dynamic dock auto-expansion contracts
    imperative_stage_assign = re.search(r"window\.animatedStage\w+\s*=", perim_src)
    if imperative_stage_assign:
        raise AssertionError(
            f"AbyssPerimeter.qml must NEVER imperatively assign window.animatedStage* (breaks declarative bindings): {imperative_stage_assign.group(0)}"
        )
    for perim_tok in (
        "property real animatedStageDockWidth: window.latchedStageDockWidth",
        "property real animatedStageDockHeight: window.latchedStageDockHeight",
        "property real animatedStageLeftDockWidth: window.latchedStageLeftDockWidth",
        "property real animatedStageLeftDockHeight: window.latchedStageLeftDockHeight",
        "property real animatedStageRightDockWidth: window.latchedStageRightDockWidth",
        "property real animatedStageRightDockHeight: window.latchedStageRightDockHeight",
    ):
        if perim_tok not in perim_src:
            raise AssertionError(f"AbyssPerimeter.qml missing declarative binding: {perim_tok}")

    dock_src = (ROOT / "modules/common/widgets/AbyssCustomizationDock.qml").read_text(encoding="utf-8")
    for dock_tok in (
        "enabled: Appearance.animationsEnabled && !root.embeddedSurface",
        "readonly property real _displayTrayHeight:",
    ):
        if dock_tok not in dock_src:
            raise AssertionError(f"AbyssCustomizationDock.qml missing embedded lag fix token: {dock_tok}")

    pos_src = (ROOT / "modules/abyss/settings/AbyssPositionSettings.qml").read_text(encoding="utf-8")
    if "visible:(root.compactSideToolbar && root.compactCornerHost ? root.visible : true)" not in pos_src:
        raise AssertionError("AbyssPositionSettings.qml must keep abyssIpcJoinCornerToggle measurable before ancestor dock becomes visible")

    edge_ed_src = (ROOT / "modules/abyss/AbyssEdgeEditor.qml").read_text(encoding="utf-8")
    for ed_tok in (
        "dockFeedbackLabel.text.length > 0",
        "height: root.splitSideDocks ? implicitHeight : undefined",
        "readonly property real desiredLeftDockHeight: Math.max(168, Math.ceil(popupsDockCard.implicitHeight + 14))",
        "height:root.useHorizontalDock ? implicitHeight : undefined",
    ):
        if ed_tok not in edge_ed_src:
            raise AssertionError(f"AbyssEdgeEditor.qml missing dynamic dock sizing token: {ed_tok}")

    # Dashboard tab icon indicators + Settings customization contracts
    dh_src = (ROOT / "modules/dashboard/DashboardHeader.qml").read_text(encoding="utf-8")
    for dh_tok in (
        'import "DashboardCustomTabPolicy.js" as TabPolicy',
        'objectName: "dashboardPageIcon" + index',
        "return TabPolicy.iconFor(root.tabIcons, id)",
        "property var tabIcons: Config.options?.dashboard?.tabIcons ?? []",
    ):
        if dh_tok not in dh_src:
            raise AssertionError(f"DashboardHeader.qml missing tab icon indicator token: {dh_tok}")
    if '"dashboardPageDot"' in dh_src:
        raise AssertionError("DashboardHeader.qml must use icons instead of circular dashboardPageDot dots")

    det_src = (ROOT / "modules/dashboard/DashboardEditToolbar.qml").read_text(encoding="utf-8")
    if "return TabPolicy.iconFor(Config.options?.dashboard?.tabIcons, pageId)" not in det_src:
        raise AssertionError("DashboardEditToolbar.qml must resolve pageIcon via TabPolicy")

    dc_cfg_src = (ROOT / "modules/settings/DashboardConfig.qml").read_text(encoding="utf-8")
    for sc_tok in (
        'title: Translation.tr("Tab indicator icons")',
        'objectName: "dashboardTabIconTargetSelector"',
        'objectName: "dashboardTabIconPreview"',
        'objectName: "dashboardTabIconInput"',
        'objectName: "dashboardTabIconResetButton"',
        'objectName: "dashboardTabIconPreset_" + modelData',
        'Config.setNestedValue("dashboard.tabIcons", nextIcons)',
    ):
        if sc_tok not in dc_cfg_src:
            raise AssertionError(f"DashboardConfig.qml missing tab icon settings token: {sc_tok}")

    dc_content_src = (ROOT / "modules/dashboard/DashboardContent.qml").read_text(encoding="utf-8")
    for c_tok in (
        "tabIcons: Config.options?.dashboard?.tabIcons ?? []",
        '"dashboard.tabIcons":TabPolicy.removeTabIcon(Config.options?.dashboard?.tabIcons, id)',
    ):
        if c_tok not in dc_content_src:
            raise AssertionError(f"DashboardContent.qml missing tabIcons token: {c_tok}")

    cfg_qml_src = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
    defaults_dash = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))["dashboard"]
    if "property list<var> tabIcons: []" not in cfg_qml_src:
        raise AssertionError("Config.qml missing dashboard.tabIcons list<var> schema")
    if "tabIcons" not in defaults_dash or defaults_dash["tabIcons"] != []:
        raise AssertionError("defaults/config.json missing dashboard.tabIcons: []")

    print("PASS [AbyssPerimeterContracts]: heavy overlay mutual exclusion + v1.0.1 vacancy parity + Left Sidebar 1px border + instant Sidebars + Edit Stage dynamic docks + Dashboard icon indicators ok")

    with tempfile.TemporaryDirectory(prefix="alis-boost-runtime-") as tmp:
        folder = Path(tmp)
        for entry in [
            "modules", "services", "GlobalStates.qml", "qmldir",
            "assets", "scripts", "defaults", "translations",
        ]:
            (folder / entry).symlink_to(ROOT / entry)
        cfg_dir = folder / "config/alis"
        cfg_dir.mkdir(parents=True)
        data = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        data["calendar"]["externalSync"]["enable"] = False
        data["calendar"]["externalSync"]["sources"] = [
            {
                "id": "legacy_icloud",
                "name": "Legacy Apple Calendar",
                "url": "webcal://p12-caldav.icloud.com/published/2/legacy",
                "color": "#4285F4",
                "enabled": True
            },
            {
                "id": "legacy_vn_hol",
                "name": "Legacy VN Holidays",
                "url": "https://calendar.google.com/calendar/ical/en.vietnamese%23holiday%40group.v.calendar.google.com/public/basic.ics",
                "color": "#EA4335",
                "enabled": True
            }
        ]
        (cfg_dir / "config.json").write_text(json.dumps(data), encoding="utf-8")

        (folder / "WarmSidebarProbe.qml").write_text(
            r"""
import QtQuick
Item {
    id: probe
    property var participant: null
    property string outputName: ""
    readonly property bool contentReady: true
    Rectangle { anchors.fill: parent; color: "#123456" }
}
""",
            encoding="utf-8",
        )

        (folder / "shell.qml").write_text(
            r"""
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.dashboard
import qs.modules.sidebarLeft
import qs.modules.notificationCenter
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.content
import qs.modules.abyss.looks
import qs.modules.settings

ShellRoot {
    id: root
    property int stage: 0
    property int checks: 0
    Component.onCompleted: Quickshell.watchFiles = false
    function check(cond, msg) {
        checks++
        if (!cond) throw new Error(msg)
    }
    function find(item, pred) {
        if (!item) return null
        if (pred(item)) return item
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) {
            const f = find(kids[i], pred)
            if (f) return f
        }
        const res = item.resources ?? []
        for (let i = 0; i < res.length; ++i) {
            const f = find(res[i], pred)
            if (f) return f
        }
        return null
    }
    function findByObjectName(item, target) {
        if (!item) return null
        if (item.objectName === target) return item
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) {
            const f = findByObjectName(kids[i], target)
            if (f) return f
        }
        return null
    }
    function findAllByObjectName(item, target, out) {
        if (!item) return
        if (item.objectName === target) out.push(item)
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) findAllByObjectName(kids[i], target, out)
    }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1600
        implicitHeight: 900
        color: "#0b1112"

        // 1. Left Sidebar + Translator tests + AbyssLeftContent / AbyssRightContent min width forwarding
        SidebarLeftContent {
            id: sidebarLeft
            x: 10; y: 10; width: 420; height: 640
            panelVisible: true
            externalConnectedSurface: true
            aiChatEnabled: true
            translatorEnabled: true
            newsEnabled: true
            toolsEnabled: true
        }
        Translator {
            id: translatorProbe
            x: 440; y: 10; width: 380; height: 480
        }
        AbyssLeftContent {
            id: leftWrapProbe
            x: 10; y: 660; width: 420; height: 200
        }
        AbyssRightContent {
            id: rightWrapProbe
            x: 440; y: 660; width: 420; height: 200
        }

        // 2. Detached borderless AbyssBarModule test
        AbyssBarModule {
            id: detachedMod
            x: 840; y: 10; width: 120; height: 40
            kind: "clock"
            outputName: "TEST-1"
            detached: true
        }

        // 3. Priority audit hosts (A2 #2/#3)
        AbyssBodyHost { id: prioControls; identity: "controls"; width: 1200; height: 800; edgeInsets: ({left: 14, right: 14, top: 40, bottom: 14}) }
        AbyssBodyHost { id: prioClipboard; identity: "clipboard"; width: 1200; height: 800; edgeInsets: ({left: 14, right: 14, top: 40, bottom: 14}) }
        AbyssBodyHost { id: prioWallpaper; identity: "wallpaper"; width: 1200; height: 800; edgeInsets: ({left: 14, right: 14, top: 40, bottom: 14}) }
        AbyssBodyHost { id: prioDialog; identity: "dialog"; width: 1200; height: 800; edgeInsets: ({left: 14, right: 14, top: 40, bottom: 14}) }

        // 4. NotificationCenterPopup Edgebar Lockout regression harness
        AbyssSurfaceController {
            id: notifCtrl
            outputName: "TEST-1"
            outputWidth: 1600
            outputHeight: 900
            presented: true
            presentationItem: notifCanvas
        }
        Item {
            id: notifCanvas
            anchors.fill: parent
            property var liquidController: notifCtrl
            Item {
                id: cornerAnchor
                x: 1580; y: 880; width: 14; height: 14
                property bool containsMouse: false
                property var liquidController: notifCtrl
            }
            NotificationCenterPopup {
                id: notifPopup
                anchorItem: cornerAnchor
                outputName: "TEST-1"
                hoverAllowed: true
            }
        }

        // 5. AbyssEdgeEditor Presets + Undo + Done persistence harness
        Item {
            id: mockBarLayer
            width: 1600; height: 900
            property string edge: "top"
            property var zones: [["distroIcon"], ["workspaces"], ["clock"], ["media"], ["tray"]]
            property var placements: []
            property var layoutRecords: []
            property var renderedRecords: []
            property var localRecords: []
            property var deformations: []
            property var measuredExtents: ({})
            property var layoutOptions: ({})
        }
        AbyssEdgeEditor {
            id: edgeEditor
            width: 1600; height: 900
            visible: false
            outputName: "TEST-1"
            moduleLayer: mockBarLayer
            controller: notifCtrl
        }

        // 6. Generic Popup & StyledPopup differentiated eviction harness
        AbyssSurfaceController {
            id: yieldCtrl
            outputName: "TEST-YIELD"
            outputWidth: 1200
            outputHeight: 800
            presented: true
        }
        Item { id: hoverGenClosedTracker; property int closeCount: 0 }
        AbyssGenericPopupPresenter {
            id: genPopup
            width: 1200; height: 800
            controller: yieldCtrl
            outputName: "TEST-YIELD"
            outputWidth: 1200
            outputHeight: 800
            requestedKind: "wifi"
            requestedOpen: false
            transientOpen: true
            requestedFallbackEdge: "bottom"
            requestedAlongCenter: 600
            onCloseRequested: kind => {
                hoverGenClosedTracker.closeCount++
                genPopup.requestedOpen = false
            }
        }
        Item { id: bigOverlayContent; implicitWidth: 1120; implicitHeight: 720 }
        AbyssBodyHost {
            id: bigOverlay
            width: 1200; height: 800
            identity: "dashboard"
            controller: yieldCtrl
            outputName: "TEST-YIELD"
            edge: "bottom"
            edgeInsets: ({left: 14, right: 14, top: 40, bottom: 14})
            largeSurface: true
            along: 20; span: 1160; depth: 680
            minimumSpan: 1160; minimumDepth: 680
            placementPriority: 3
            placementIntent: "overlay"
            embeddedItem: bigOverlayContent
            animatePresentation: false; animatePlacementChanges: false
            open: false
        }
        Item { id: explicitSideContent; implicitWidth: 400; implicitHeight: 680 }
        AbyssBodyHost {
            id: explicitSide
            width: 1200; height: 800
            identity: "leftPanel"
            controller: yieldCtrl
            outputName: "TEST-YIELD"
            edge: "left"
            edgeInsets: ({left: 14, right: 14, top: 40, bottom: 14})
            along: 60; span: 680; depth: 420
            minimumSpan: 320; minimumDepth: 320
            placementPriority: 2
            placementIntent: "explicit"
            embeddedItem: explicitSideContent
            animatePresentation: false; animatePlacementChanges: false
            open: false
        }

        // 7. WeeklyPlanner all-day holiday & regular label width probe (no zero-width collapse!)
        DashboardWeeklyPlanner {
            id: weeklyProbe
            x: 840; y: 100; width: 720; height: 520
        }

        // 8. QuickNotes active-editing vs hover-only restoration across corners.blocked (A2 #4)
        property string qnEditorLeaseOutput: ""
        AbyssSurfaceController {
            id: qnCtrl
            outputName: "TEST-QN"
            outputWidth: 1200
            outputHeight: 800
            presented: true
            presentationItem: qnScene
            edgeInsets: ({left: 16, right: 16, top: 40, bottom: 16})
        }
        Item {
            id: qnScene
            width: 1200; height: 800
            property var liquidController: qnCtrl
            AbyssCorners {
                id: qnCorners
                anchors.fill: parent
                controller: qnCtrl
                outputName: "TEST-QN"
                presentationEnabled: true
                blocked: false
                quickNotesEditorOutput: win.qnEditorLeaseOutput
                onQuickNotesEditorLeaseChanged: (outName, focused) => {
                    if (focused) win.qnEditorLeaseOutput = outName
                    else if (win.qnEditorLeaseOutput === outName) win.qnEditorLeaseOutput = ""
                }
            }
            AbyssBodyHost {
                id: qnHost
                anchors.fill: parent
                identity: "styledPopup0"
                controller: qnCtrl
                outputName: "TEST-QN"
                edge: "bottom"
                edgeInsets: qnCtrl.edgeInsets
                stackPolicy: "pyramid"
                stableContentSize: true
                includeEdgeConnection: true
                singleExternalReveal: true
                readonly property var hostedPopup: qnCtrl.popupSlots[0]?.popup ?? null
                semanticOpenOverride: hostedPopup?.liquidSemanticVisible ?? false
                readonly property bool explicitOrFocusedPopup:
                    Boolean(hostedPopup?.popupPinned)
                    || Boolean(hostedPopup?.editorFocused)
                    || Boolean(hostedPopup?.todoDialogOpen)
                    || qnHost.contentFocused
                placementIntent: explicitOrFocusedPopup ? "explicit" : "hover"
                placementPriority: explicitOrFocusedPopup ? 2 : 1
                along: 16; span: 420; depth: 300; padding: 14
                open: (hostedPopup?.presentationActive ?? false)
                    && ((hostedPopup?.requestedVisible ?? false)
                        || ((hostedPopup?.hoverActivates ?? false)
                            && (hostedPopup?._lingerVisible ?? false)))
                externalProgress: hostedPopup?.revealProgress ?? 0
                embeddedItem: hostedPopup?.contentItem ?? null
                readonly property bool hostPlacementEvicted:
                    qnHost.semanticOpen && !qnHost.placementVisible
                property var _evictionTrackedPopup: null
                function _syncPopupEvictionState(): void {
                    const current = qnHost.hostedPopup
                    if (qnHost._evictionTrackedPopup && qnHost._evictionTrackedPopup !== current) {
                        if (qnHost._evictionTrackedPopup._placementEvicted !== undefined)
                            qnHost._evictionTrackedPopup._placementEvicted = false
                    }
                    qnHost._evictionTrackedPopup = current
                    if (current && current._placementEvicted !== undefined)
                        current._placementEvicted = qnHost.hostPlacementEvicted
                }
                onHostPlacementEvictedChanged: qnHost._syncPopupEvictionState()
                onHostedPopupChanged: qnHost._syncPopupEvictionState()
                onPlacementVisibleChanged: {
                    qnHost._syncPopupEvictionState()
                    if (qnHost.semanticOpen && !qnHost.placementVisible
                            && !qnHost.explicitOrFocusedPopup && hostedPopup) {
                        const evictedPopup = hostedPopup
                        Qt.callLater(() => {
                            if (qnHost.semanticOpen && !qnHost.placementVisible
                                    && !qnHost.explicitOrFocusedPopup && qnHost.hostedPopup === evictedPopup)
                                evictedPopup.dismissPresentation()
                        })
                    }
                }
                Component.onCompleted: qnCtrl.registerPopupHost(0, qnHost)
            }
            // High-priority modal body (e.g., dialogBody/wallpaperBody) NOT in corners.blocked
            Item { id: qnModalContent; implicitWidth: 1120; implicitHeight: 720 }
            AbyssBodyHost {
                id: qnModalHost
                anchors.fill: parent
                identity: "dialog"
                controller: qnCtrl
                outputName: "TEST-QN"
                edge: "bottom"
                edgeInsets: qnCtrl.edgeInsets
                along: 20; span: 1160; depth: 700; padding: 14
                minimumSpan: 1160; minimumDepth: 700
                largeSurface: true
                placementPriority: 4
                placementIntent: "modal"
                embeddedItem: qnModalContent
                animatePresentation: false; animatePlacementChanges: false
                open: false
            }
        }
        function simulateEnsureEscapeFocus(host): void {
            if (!host || !host.presented || !host.acceptsInput || !host.ready) return
            const item = host.embeddedItem
            if (item && typeof item.focusPrimarySurface === "function")
                item.focusPrimarySurface()
            else if (item && item.visible && item.enabled)
                item.forceActiveFocus()
        }

        // 9. Module Icon mode QuickNotesPopup restoration across edgebarBlocked (A2 #4)
        AbyssSurfaceController {
            id: qnModCtrl
            outputName: "TEST-QN-MOD"
            outputWidth: 1200
            outputHeight: 800
            presented: true
            presentationItem: qnModScene
            edgeInsets: ({left: 16, right: 16, top: 40, bottom: 16})
        }
        Item {
            id: qnModScene
            width: 1200; height: 800
            property var liquidController: qnModCtrl
            AbyssBarModule {
                id: qnBarMod
                x: 20; y: 0; width: 40; height: 40
                kind: "notesTimers"
                outputName: "TEST-QN-MOD"
                attachedEdge: "top"
                edgebarBlocked: false
            }
            AbyssBodyHost {
                id: qnModHost
                anchors.fill: parent
                identity: "styledPopup0"
                controller: qnModCtrl
                outputName: "TEST-QN-MOD"
                edge: "top"
                edgeInsets: qnModCtrl.edgeInsets
                along: 16; span: 420; depth: 300; padding: 14
                open: qnModCtrl.activePopup?.presentationActive ?? false
                externalProgress: qnModCtrl.activePopup?.revealProgress ?? 0
                embeddedItem: qnModCtrl.activePopup?.contentItem ?? null
                animatePresentation: false; animatePlacementChanges: false
                Component.onCompleted: qnModCtrl.registerPopupHost(0, qnModHost)
            }
        }

        // 10. Hover Exit Freeze + v1.0.1 Paired Edgebar/Sidebar Vacancy Parity Harness
        AbyssSurfaceController {
            id: freezeCtrl
            outputName: "TEST-FREEZE"
            outputWidth: 1920
            outputHeight: 1080
            presented: true
            edgeInsets: ({left: 16, right: 16, top: 48, bottom: 16})
        }
        Item { id: freezeSideContent; implicitWidth: 420; implicitHeight: 660 }
        Item { id: freezeEbContent; implicitWidth: 422; implicitHeight: 402 }
        AbyssBodyHost {
            id: freezeSidebar
            width: 1920; height: 1080
            controller: freezeCtrl
            identity: "leftPanel"
            edge: "left"
            outputName: "TEST-FREEZE"
            vacancyRole: "featureSidebar"
            cooperativePeer: true
            placementCanShiftLaterally: false
            placementPriority: 2
            edgeInsets: freezeCtrl.edgeInsets
            along: 190; span: 700; depth: 460; padding: 20
            minimumSpan: 320; minimumDepth: 320
            embeddedItem: freezeSideContent
            animatePresentation: true
            animatePlacementChanges: true
            stableContentSize: true
            open: false
        }
        AbyssBodyHost {
            id: freezeEdgebar
            width: 1920; height: 1080
            controller: freezeCtrl
            identity: "styledPopup0"
            edge: "left"
            outputName: "TEST-FREEZE"
            vacancyRole: "quickNotes"
            stackPolicy: "pyramid"
            placementCanShiftLaterally: false
            property bool simulatedEditorFocused: false
            property bool _latchedExplicitIntent: false
            onSemanticOpenChanged: _latchedExplicitIntent = semanticOpen ? simulatedEditorFocused : false
            placementIntent: _latchedExplicitIntent ? "explicit" : "hover"
            placementPriority: freezeSidebar.placementPriority
            edgeInsets: freezeCtrl.edgeInsets
            along: 634; span: 430; depth: 450; padding: 14
            minimumSpan: 240; minimumDepth: 180
            property real fifoTestProgress: -1
            property bool fifoTestSemanticOpen: true
            singleExternalReveal: fifoTestProgress >= 0
            semanticOpenOverride: fifoTestProgress >= 0 ? fifoTestSemanticOpen : undefined
            externalProgress: fifoTestProgress >= 0 ? fifoTestProgress : (freezeEdgebar.open ? 1 : 0.4)
            embeddedItem: freezeEbContent
            animatePresentation: true
            animatePlacementChanges: true
            stableContentSize: true
            open: false
        }

        // 11. Zero-Loading-Screen Sidebar Warmup + RetainAfterFirstOpen Probe
        Item {
            id: warmContainer
            width: 1920; height: 1080
            AbyssSurfaceController {
                id: warmCtrl
                outputName: "TEST-WARM"
                outputWidth: 1920
                outputHeight: 1080
                presented: true
                edgeInsets: ({left: 16, right: 16, top: 48, bottom: 16})
            }
            AbyssBodyHost {
                id: warmSidebarHost
                anchors.fill: parent
                identity: "leftPanel"
                edge: "left"
                outputName: "TEST-WARM"
                controller: warmCtrl
                animatePresentation: false
                stableContentSize: true
                showLoadingSurface: false
                warmContent: true
                retainAfterFirstOpen: true
                edgeInsets: warmCtrl.edgeInsets
                along: 24; span: 700; depth: 460; padding: 14
                open: false
                source: Qt.resolvedUrl("WarmSidebarProbe.qml")
            }
        }

        // 12. Embedded AbyssCustomizationDock zero-lag check + Edit Abyss Layout dynamic dock sizing harness
        AbyssCustomizationDock {
            id: embeddedDockProbe
            width: 820
            height: implicitHeight
            embeddedSurface: true
            trayExpanded: true
            trayHeight: 152
            showUndo: false
            showCancel: false
        }
        Item {
            id: editStageProbe
            width: 1920
            height: 1080
            property string editStageMode: ""
            property string retainedEditStageMode: ""
            readonly property string displayEditStageMode: editStageMode.length > 0 ? editStageMode : retainedEditStageMode
            property real latchedStageDockWidth: 960
            property real latchedStageDockHeight: 218
            property real latchedStageLeftDockWidth: 248
            property real latchedStageLeftDockHeight: 300
            property real latchedStageRightDockWidth: 262
            property real latchedStageRightDockHeight: 420
            readonly property real rawStageDockWidth: displayEditStageMode === "abyss" ? dockedEditor.desiredDockWidth : 960
            readonly property real rawStageDockHeight: displayEditStageMode === "abyss" ? dockedEditor.desiredDockHeight : 218
            readonly property real rawStageLeftDockWidth: displayEditStageMode === "abyss" ? dockedEditor.desiredLeftDockWidth : 0
            readonly property real rawStageLeftDockHeight: displayEditStageMode === "abyss" ? dockedEditor.desiredLeftDockHeight : 0
            readonly property real rawStageRightDockWidth: displayEditStageMode === "abyss" ? dockedEditor.desiredRightDockWidth : 0
            readonly property real rawStageRightDockHeight: displayEditStageMode === "abyss" ? dockedEditor.desiredRightDockHeight : 0
            onRawStageDockWidthChanged: if (editStageMode.length > 0 && rawStageDockWidth > 200) latchedStageDockWidth = Math.round(rawStageDockWidth)
            onRawStageDockHeightChanged: if (editStageMode.length > 0 && rawStageDockHeight > 40) latchedStageDockHeight = Math.round(rawStageDockHeight)
            onRawStageLeftDockWidthChanged: {
                if (editStageMode === "abyss" && rawStageLeftDockWidth > 160) {
                    latchedStageLeftDockWidth = Math.round(rawStageLeftDockWidth)
                    if (editStageProgress > 0.0001 && !_coalescing) syncStage()
                }
            }
            onRawStageLeftDockHeightChanged: if (editStageMode === "abyss" && rawStageLeftDockHeight > 120) latchedStageLeftDockHeight = Math.round(rawStageLeftDockHeight)
            onRawStageRightDockWidthChanged: {
                if (editStageMode === "abyss" && rawStageRightDockWidth > 160) {
                    latchedStageRightDockWidth = Math.round(rawStageRightDockWidth)
                    if (editStageProgress > 0.0001 && !_coalescing) syncStage()
                }
            }
            onRawStageRightDockHeightChanged: if (editStageMode === "abyss" && rawStageRightDockHeight > 120) latchedStageRightDockHeight = Math.round(rawStageRightDockHeight)
            property real animatedStageDockWidth: latchedStageDockWidth
            Behavior on animatedStageDockWidth {
                enabled: AbyssStyle.motionEnabled && editStageProbe.editStageProgress >= 0.98 && editStageProbe.editStageMode.length > 0
                NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
            }
            property real animatedStageDockHeight: latchedStageDockHeight
            Behavior on animatedStageDockHeight {
                enabled: AbyssStyle.motionEnabled && editStageProbe.editStageProgress >= 0.98 && editStageProbe.editStageMode.length > 0
                NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
            }
            property real animatedStageLeftDockWidth: latchedStageLeftDockWidth
            Behavior on animatedStageLeftDockWidth {
                enabled: AbyssStyle.motionEnabled && editStageProbe.editStageProgress >= 0.98 && editStageProbe.editStageMode.length > 0
                NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
            }
            property real animatedStageLeftDockHeight: latchedStageLeftDockHeight
            Behavior on animatedStageLeftDockHeight {
                enabled: AbyssStyle.motionEnabled && editStageProbe.editStageProgress >= 0.98 && editStageProbe.editStageMode.length > 0
                NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
            }
            property real animatedStageRightDockWidth: latchedStageRightDockWidth
            Behavior on animatedStageRightDockWidth {
                enabled: AbyssStyle.motionEnabled && editStageProbe.editStageProgress >= 0.98 && editStageProbe.editStageMode.length > 0
                NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
            }
            property real animatedStageRightDockHeight: latchedStageRightDockHeight
            Behavior on animatedStageRightDockHeight {
                enabled: AbyssStyle.motionEnabled && editStageProbe.editStageProgress >= 0.98 && editStageProbe.editStageMode.length > 0
                NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
            }
            property bool _stageAnimArmed: false
            property real editStageProgress: (editStageMode.length > 0 && _stageAnimArmed) ? 1 : 0
            Behavior on editStageProgress {
                enabled: AbyssStyle.motionEnabled
                NumberAnimation { duration: AbyssStyle.motionNormal; easing.type: Easing.OutCubic }
            }
            property bool _coalescing: false
            function syncStage(): void {
                if (_coalescing) return
                if (editStageProgress <= 0.0001 && editStageMode.length === 0) {
                    DesktopEditStage.clearStage("TEST-EDIT-DOCK")
                    retainedEditStageMode = ""
                    return
                }
                if (editStageMode.length > 0) {
                    if (rawStageDockWidth > 200) latchedStageDockWidth = Math.round(rawStageDockWidth)
                    if (rawStageDockHeight > 40) latchedStageDockHeight = Math.round(rawStageDockHeight)
                    if (rawStageLeftDockWidth > 160) latchedStageLeftDockWidth = Math.round(rawStageLeftDockWidth)
                    if (rawStageLeftDockHeight > 120) latchedStageLeftDockHeight = Math.round(rawStageLeftDockHeight)
                    if (rawStageRightDockWidth > 160) latchedStageRightDockWidth = Math.round(rawStageRightDockWidth)
                    if (rawStageRightDockHeight > 120) latchedStageRightDockHeight = Math.round(rawStageRightDockHeight)
                }
                DesktopEditStage.setStage(
                    "TEST-EDIT-DOCK",
                    displayEditStageMode,
                    editStageProgress,
                    animatedStageDockWidth,
                    animatedStageDockHeight,
                    animatedStageLeftDockWidth,
                    animatedStageLeftDockHeight,
                    animatedStageRightDockWidth,
                    animatedStageRightDockHeight,
                    editStageProgress,
                    editStageProgress
                )
            }
            onEditStageModeChanged: {
                _coalescing = true
                if (editStageMode.length > 0) {
                    retainedEditStageMode = editStageMode
                    if (rawStageDockWidth > 200) latchedStageDockWidth = Math.round(rawStageDockWidth)
                    if (rawStageDockHeight > 40) latchedStageDockHeight = Math.round(rawStageDockHeight)
                    if (rawStageLeftDockWidth > 160) latchedStageLeftDockWidth = Math.round(rawStageLeftDockWidth)
                    if (rawStageLeftDockHeight > 120) latchedStageLeftDockHeight = Math.round(rawStageLeftDockHeight)
                    if (rawStageRightDockWidth > 160) latchedStageRightDockWidth = Math.round(rawStageRightDockWidth)
                    if (rawStageRightDockHeight > 120) latchedStageRightDockHeight = Math.round(rawStageRightDockHeight)
                    _stageAnimArmed = true
                } else {
                    _stageAnimArmed = false
                }
                _coalescing = false
                syncStage()
            }
            onEditStageProgressChanged: syncStage()
            onAnimatedStageDockWidthChanged: if (editStageProgress > 0.0001) syncStage()
            onAnimatedStageDockHeightChanged: if (editStageProgress > 0.0001) syncStage()
            onAnimatedStageLeftDockWidthChanged: if (editStageProgress > 0.0001) syncStage()
            onAnimatedStageLeftDockHeightChanged: if (editStageProgress > 0.0001) syncStage()
            onAnimatedStageRightDockWidthChanged: if (editStageProgress > 0.0001) syncStage()
            onAnimatedStageRightDockHeightChanged: if (editStageProgress > 0.0001) syncStage()
            readonly property var editCard: DesktopEditStage.cardFor("TEST-EDIT-DOCK", width, height)
            readonly property bool editStageVisible: editCard.p > 0.001

            Item {
                id: editStageLeftDock
                visible: editStageProbe.editStageVisible && editStageProbe.editCard.leftDockWidth > 0 && editStageProbe.editCard.leftDockHeight > 0 && editStageProbe.editCard.leftProgress > 0.001
                x: editStageProbe.editCard.leftDockX
                y: editStageProbe.editCard.leftDockY
                width: editStageProbe.editCard.leftDockWidth
                height: editStageProbe.editCard.leftDockHeight
                clip: true
            }
            Item {
                id: editStageRightDock
                visible: editStageProbe.editStageVisible && editStageProbe.editCard.rightDockWidth > 0 && editStageProbe.editCard.rightDockHeight > 0 && editStageProbe.editCard.rightProgress > 0.001
                x: editStageProbe.editCard.rightDockX
                y: editStageProbe.editCard.rightDockY
                width: editStageProbe.editCard.rightDockWidth
                height: editStageProbe.editCard.rightDockHeight
                clip: true
            }
            Item {
                id: editStageBottomDock
                visible: editStageProbe.editStageVisible
                x: editStageProbe.editCard.dockX
                y: editStageProbe.editCard.dockY
                width: editStageProbe.editCard.dockWidth
                height: editStageProbe.editCard.dockHeight
                clip: true
            }
            AbyssEdgeEditor {
                id: dockedEditor
                anchors.fill: parent
                visible: editStageProbe.editStageMode === "abyss"
                outputName: "TEST-EDIT-DOCK"
                moduleLayer: mockBarLayer
                controller: warmCtrl
                externalDockParent: editStageBottomDock
                externalLeftDockParent: editStageLeftDock
                externalRightDockParent: editStageRightDock
            }
        }

        // 13. Dashboard icon indicators + DashboardConfig + Split Left Tabs dock probe
        Item {
            id: dashIconStage
            width: 820
            height: 760
            DashboardHeader {
                id: iconHeaderProbe
                width: 820
                showActions: false
                editMode: false
                pageCount: 3
                pageIds: ["dashboard", "music", "weeklyPlanner"]
                currentPage: 0
                indicatorProgress: 0
            }
            DashboardConfig {
                id: dashConfigProbe
                y: 60
                width: 760
                height: 680
            }
            QtObject {
                id: splitDashCanvasStub
                property bool editMode: true
                property var visibleIds: ["clock"]
                property var hiddenIds: []
                property var _allIds: ["clock"]
                property int gridSize: 24
                property string gridStyle: "dots"
                property bool snapEnabled: true
                property bool autoAdjustSizeEnabled: true
                property bool responsiveWorkspace: false
                property bool canUndo: false
                property string layoutMessage: ""
                function _label(id) { return String(id) }
            }
            QtObject {
                id: splitDashTabStub
                property var pageIds: ["dashboard", "music", "weeklyPlanner"]
                property string currentPageId: "dashboard"
                property var customTabs: []
                property bool tabNamingActive: false
                property string _customDialogName: ""
                property string _customDialogError: ""
                property string _customDialogMode: ""
                property string _pendingNewEditId: ""
                function selectPage(id) { currentPageId = String(id) }
            }
            Item {
                id: splitLeftDockHost
                x: 520
                y: 60
                width: 268
                height: Math.max(200, splitDashToolbarProbe.desiredLeftDockHeight)
            }
            DashboardEditToolbar {
                id: splitDashToolbarProbe
                visible: true
                width: 500
                splitSideDocks: true
                leftDockParent: splitLeftDockHost
                canvasController: splitDashCanvasStub
                tabController: splitDashTabStub
            }
        }
    }

    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            if (!Config.ready) return
            try {
                GlobalStates.deferredPanelsReady = true

                if (stage === 0) {
                    // --- Left Sidebar + Min Width Forwarding checks ---
                    const arrangeBtn = findByObjectName(sidebarLeft, "sidebarLeftArrangeTabsButton")
                    check(Boolean(arrangeBtn), "sidebarLeftArrangeTabsButton found")
                    check(arrangeBtn.width <= 0.5 && arrangeBtn.opacity === 0,
                        "Arrange button collapses to 0px when unhovered (width=" + arrangeBtn.width + ", opacity=" + arrangeBtn.opacity + ")")
                    sidebarLeft.tabEditMode = true

                    const trBg = findByObjectName(translatorProbe, "translatorCloudBackground")
                    check(Boolean(trBg) && trBg.visible && trBg.gradient !== null,
                        "Translator restored Abyss vertical cloud gradient background")
                    check(trBg.border.width === 1 && trBg.children.length === 0,
                        "Translator has 1px border and zero top accent line")
                    check(trBg.radius === Appearance.rounding.normal,
                        "Translator background radius matches Appearance.rounding.normal")

                    check(leftWrapProbe.minimumUsefulWidth >= 320,
                        "AbyssLeftContent forwards minimumUsefulWidth >= 320 (got " + leftWrapProbe.minimumUsefulWidth + ")")
                    check(rightWrapProbe.minimumUsefulWidth >= 320,
                        "AbyssRightContent forwards minimumUsefulWidth >= 320 (got " + rightWrapProbe.minimumUsefulWidth + ")")

                    // --- Priority inversion fix check ---
                    check(prioControls.placementPriority === 3, "controls priority === 3")
                    check(prioClipboard.placementPriority === 3, "clipboard priority === 3")
                    check(prioWallpaper.placementPriority === 3, "wallpaper priority === 3")
                    check(prioDialog.placementPriority === 4, "dialog priority === 4")

                    // --- Detached Borderless Pill check ---
                    const pill = findByObjectName(detachedMod, "abyssDetachedPillSurface")
                    check(Boolean(pill) && pill.visible, "detached pill visible")
                    check(pill.border.width === 0, "detached pill has zero border")
                    check(Qt.colorEqual(pill.color, AbyssStyle.surface),
                        "detached pill matches AbyssStyle.surface")
                    check(pill.children.length === 0, "detached pill has no inner hairline border")

                    // --- CalendarSync legacy webcal:// + holiday detection + presets ---
                    check(CalendarSync.normalizeUrl("webcal://example.com/a.ics") === "https://example.com/a.ics",
                        "webcal:// normalized to https://")
                    check(CalendarSync.normalizeUrl("WEBCALS://example.com/b.ics") === "https://example.com/b.ics",
                        "webcals:// normalized to https://")
                    const srcs = CalendarSync.sources
                    const legApple = srcs.find(s => s.id === "legacy_icloud")
                    check(Boolean(legApple) && legApple.url === "https://p12-caldav.icloud.com/published/2/legacy",
                        "pre-existing saved webcal:// source normalized at read-time")
                    const legVn = srcs.find(s => s.id === "legacy_vn_hol")
                    check(Boolean(legVn) && legVn.isHoliday === true && legVn.kind === "holiday",
                        "pre-existing Google holiday ICS URL inferred as holiday at read-time")
                    check(CalendarSync.holidayPresets.length >= 8, "holiday presets populated")

                    // Toggle 1-click holiday preset on and off cleanly
                    const jpPreset = CalendarSync.holidayPresets.find(p => p.id === "preset_jp")
                    check(Boolean(jpPreset) && !CalendarSync.hasHolidayPreset("preset_jp"), "JP holiday preset available")
                    CalendarSync.toggleHolidayPreset("preset_jp")
                    Config.setNestedValue("calendar.externalSync.enable", false)
                    check(CalendarSync.hasHolidayPreset("preset_jp"), "toggleHolidayPreset enabled JP holidays")
                    const jpSrc = CalendarSync.sources.find(s => s.url === jpPreset.url)
                    check(Boolean(jpSrc) && jpSrc.isHoliday === true, "toggled preset marked isHoliday=true")
                    // Disabling the preset source must clear hasHolidayPreset()
                    CalendarSync.toggleSource(jpSrc.id, false)
                    check(!CalendarSync.hasHolidayPreset("preset_jp"), "disabled holiday preset reports hasHolidayPreset=false")
                    // Re-toggling re-enables cleanly, then toggling removes
                    CalendarSync.toggleHolidayPreset("preset_jp")
                    Config.setNestedValue("calendar.externalSync.enable", false)
                    check(CalendarSync.hasHolidayPreset("preset_jp"), "re-toggled disabled holiday preset re-enabled")
                    CalendarSync.toggleHolidayPreset("preset_jp")
                    check(!CalendarSync.hasHolidayPreset("preset_jp"), "toggleHolidayPreset removed JP holidays")

                    // Seed today with a holiday + regular all-day event for WeeklyPlanner visibility check
                    const todayD = new Date()
                    const td0 = new Date(todayD.getFullYear(), todayD.getMonth(), todayD.getDate(), 0, 0, 0)
                    const td1 = new Date(todayD.getFullYear(), todayD.getMonth(), todayD.getDate() + 1, 0, 0, 0)
                    CalendarSync.events = [
                        { sourceId: "legacy_vn_hol", title: "Tết Nguyên Đán", allDay: true, isHoliday: true, kind: "holiday", source: "external", sourceColor: "#EA4335", uid: "tet-today", startDate: td0.toISOString(), endDate: td1.toISOString() },
                        { sourceId: "work_1", title: "Team Offsite", allDay: true, isHoliday: false, kind: "event", source: "external", sourceColor: "#4285F4", uid: "work-today", startDate: td0.toISOString(), endDate: td1.toISOString() }
                    ]
                    CalendarSync.eventsUpdated()

                    // Offline cache preservation test
                    CalendarSync._previousEventsBySource = CalendarSync._snapshotEventsBySource()
                    CalendarSync._fetchedEvents = []
                    CalendarSync._preserveCachedForSource(legVn, "curl exited with code 6")
                    check(CalendarSync._fetchedEvents.length === 1 && CalendarSync._fetchedEvents[0].title === "Tết Nguyên Đán",
                        "offline fetch failure preserves cached events per source")
                    check(CalendarSync.sourceStatuses["legacy_vn_hol"].stale === true,
                        "offline failed source marked stale")

                    // --- Edgebar Lockout Regression: Step 1 (Hover Edgebar opens) ---
                    cornerAnchor.containsMouse = true
                } else if (stage === 1) {
                    // Verify WeeklyPlanner all-day holiday + regular titles render with non-zero width!
                    const allDayBtns = []
                    findAllByObjectName(weeklyProbe, "plannerAllDayEvent", allDayBtns)
                    check(allDayBtns.length >= 2, "WeeklyPlanner rendered holiday + regular all-day buttons (" + allDayBtns.length + ")")
                    for (let bi = 0; bi < allDayBtns.length; ++bi) {
                        const row = allDayBtns[bi].contentItem?.children?.[0] ?? null
                        let titleW = 0
                        if (row) {
                            for (let ci = 0; ci < row.children.length; ++ci) {
                                if (row.children[ci]?.text === allDayBtns[bi].modelData?.event?.title)
                                    titleW = row.children[ci].width
                            }
                        }
                        check(titleW > 20, "WeeklyPlanner all-day title visible (width=" + titleW + " for " + allDayBtns[bi].modelData?.event?.title + ")")
                    }

                    check(notifPopup.presentationActive === true, "Cycle 1: Edgebar opened on hover")
                    // Step 2: Pointer leaves Edgebar (moves to Right Sidebar -> _contentHovered=true), then Dashboard blocks & dismisses
                    notifPopup._contentHovered = true
                    cornerAnchor.containsMouse = false
                    notifPopup.hoverAllowed = false
                    check(notifPopup.exitGraceHeld === false,
                        "blocking hoverAllowed must NOT re-arm exitGraceHeld via onHoverLeaseRequestedChanged")
                    notifPopup.dismissPresentation()
                    check(notifPopup._liquidDismissed === false,
                        "dismissPresentation must NOT strand _liquidDismissed=true")
                    check(notifPopup.hoverSessionArmed === true,
                        "dismissAndDisarm while unhovered must keep hoverSessionArmed=true")
                    // Re-allow hover -> hover again!
                    notifPopup.hoverAllowed = true
                    cornerAnchor.containsMouse = true
                } else if (stage === 2) {
                    const arrangeBtn2 = findByObjectName(sidebarLeft, "sidebarLeftArrangeTabsButton")
                    check(Boolean(arrangeBtn2) && arrangeBtn2.width >= 30 && arrangeBtn2.opacity > 0.8,
                        "Arrange button expanded smoothly when tabEditMode active (w=" + arrangeBtn2?.width + ", op=" + arrangeBtn2?.opacity + ")")
                    sidebarLeft.tabEditMode = false

                    check(notifPopup.presentationActive === true,
                        "Cycle 2: Edgebar RE-ACTIVATED cleanly after Dashboard lockout!")
                    // Dismiss while pointer IS still on anchor -> disarms, then leave -> auto-rearms
                    notifPopup.dismissPresentation()
                    check(notifPopup.hoverSessionArmed === false, "disarmed while pointer still on anchor")
                    cornerAnchor.containsMouse = false
                    check(notifPopup.hoverSessionArmed === true,
                        "leaving anchor immediately rearms hoverSessionArmed=true")
                    check(notifPopup._liquidDismissed === false,
                        "leaving anchor clears _liquidDismissed=false")
                } else if (stage === 3) {
                    // Cycle 3: hover again opens cleanly
                    cornerAnchor.containsMouse = true
                } else if (stage === 4) {
                    check(notifPopup.presentationActive === true,
                        "Cycle 3: Edgebar re-activated cleanly after in-place disarm+leave!")
                    cornerAnchor.containsMouse = false

                    // --- AbyssEdgeEditor Presets (0 built-in, all deletable) + Undo + Cancel + Done persistence ---
                    edgeEditor.visible = true
                    edgeEditor.begin()
                    edgeEditor.editorSection = "presets"
                    const origDraftLen = edgeEditor.draft.length
                    check(edgeEditor.availablePresets.length === 0,
                        "Editor starts with 0 built-in presets")
                    const emptyLbl = findByObjectName(edgeEditor, "abyssPresetsEmptyLabel")
                    check(Boolean(emptyLbl) && emptyLbl.visible === true,
                        "Empty presets state label visible when 0 presets exist")

                    // Seed edits & save a custom preset ("Owner Dual")
                    edgeEditor.edgeJoinModules = Object.assign({}, edgeEditor.edgeJoinModules, { bottom: true })
                    edgeEditor.draftPositions = [{ kind: "osd", outputName: "", edge: "top", alignment: "center", position: 0.5 }]
                    edgeEditor._positionsReplaced = true
                    edgeEditor.companionDraftAlong = 0.86
                    edgeEditor.saveCurrentPreset("Owner Dual")
                    const customPreset = edgeEditor.availablePresets.find(p => p.name === "Owner Dual")
                    check(Boolean(customPreset) && customPreset.builtIn === false, "Saved custom preset is unlocked")
                    check(emptyLbl.visible === false, "Empty state hidden once preset saved")

                    // Revert via cancel then re-open and apply the saved preset
                    edgeEditor.finish(false)
                    edgeEditor.visible = true
                    edgeEditor.begin()
                    edgeEditor.applyPreset(customPreset)
                    check(edgeEditor.edgeJoinModules.bottom === true, "preset applied edgeJoinModules")
                    check(edgeEditor._positionsReplaced === true && edgeEditor.draftPositions.length === 1,
                        "preset replaced draftPositions")
                    check(Math.abs(edgeEditor.companionDraftAlong - 0.86) < 0.001,
                        "preset applied companion anchor")

                    // Undo restores prior state AND clears activePresetId
                    edgeEditor.undo()
                    check(edgeEditor.draft.length === origDraftLen, "Undo restored draft")
                    check(edgeEditor._positionsReplaced === false, "Undo restored _positionsReplaced")
                    check(edgeEditor.activePresetId === "", "Undo restored activePresetId")
                    // Reset clones Qt6 list<var> positions safely
                    edgeEditor.reset()
                    check(Array.isArray(edgeEditor.draftPositions), "reset() keeps draftPositions as Array")

                    // Cancel leaves Config.options.abyss.positions unchanged
                    edgeEditor.applyPreset(customPreset)
                    edgeEditor.finish(false)
                    check((Config.options?.abyss?.positions ?? []).length === 0,
                        "Cancel did NOT persist preset draftPositions")

                    // Pre-seed another output's position override to test outputOnly preservation
                    Config.setNestedValue("abyss.positions", [
                        { kind: "osd", outputName: "HDMI-OTHER", edge: "bottom", alignment: "end", position: 0.9 }
                    ])
                    // Re-open in outputOnly mode, apply preset, overwrite preset, save second preset, and finish(true)
                    edgeEditor.visible = true
                    edgeEditor.begin()
                    edgeEditor.outputOnly = true
                    edgeEditor.applyPreset(customPreset)
                    edgeEditor.overwriteUserPreset(customPreset.id)
                    edgeEditor.saveCurrentPreset("Owner Custom Test")
                    const savedUsers = Config.options?.abyss?.layoutPresets ?? []
                    check(savedUsers.some(p => p.name === "Owner Custom Test"),
                        "saveCurrentPreset persisted user preset to Config")
                    const createdId = savedUsers.find(p => p.name === "Owner Custom Test").id
                    edgeEditor.finish(true)
                    const persistedPositions = Array.from(Config.options?.abyss?.positions ?? [])
                    check(persistedPositions.some(p => p.outputName === "HDMI-OTHER"),
                        "outputOnly finish(true) preserved other outputs' abyss.positions")
                    check(persistedPositions.some(p => p.kind === "osd" && p.outputName === ""),
                        "finish(true) persisted preset draftPositions to Config.options.abyss.positions")
                    edgeEditor.deleteUserPreset(createdId)
                    edgeEditor.deleteUserPreset(customPreset.id)
                    check(edgeEditor.availablePresets.length === 0,
                        "deleteUserPreset removed ALL presets without locks")

                    // --- Smart Yielding Eviction Lifecycle (A2 #4) ---
                    genPopup.requestedOpen = true
                    explicitSide.open = true
                } else if (stage === 5) {
                    check(genPopup.open === true && genPopup.presented === true, "Hover generic popup opened")
                    check(explicitSide.open === true && explicitSide.presented === true, "Explicit sidebar opened")
                    // Open huge non-cooperative overlay -> evicts BOTH hover generic popup AND explicit sidebar
                    bigOverlay.open = true
                } else if (stage === 6) {
                    check(bigOverlay.presented === true, "Heavy overlay presented")
                    check(hoverGenClosedTracker.closeCount >= 1 && genPopup.requestedOpen === false,
                        "Hover-only generic popup cleanly closed its lease on eviction")
                    check(explicitSide.open === true && explicitSide.presented === false,
                        "Explicit sidebar temp-hidden while evicted (open preserved)")
                    // Close heavy overlay -> explicit sidebar auto-restores, hover generic popup stays closed!
                    bigOverlay.open = false
                } else if (stage === 7) {
                    check(explicitSide.open === true && explicitSide.presented === true,
                        "Explicit sidebar auto-restored when heavy overlay closed!")
                    check(genPopup.requestedOpen === false && genPopup.presented === false,
                        "Evicted hover generic popup NEVER resurrected after heavy overlay closed!")

                    // --- QuickNotes Edgebar active-editing vs hover-only across corners.blocked (A2 #4) ---
                    Config.setNestedValue("abyss.modules.notesTimersMode", "edgebar")
                    check(qnCorners.notesAvailable === true, "QuickNotes corner available in edgebar mode")
                    qnCorners.notesAnchor.containsMouse = true
                } else if (stage === 8) {
                    if (!Notepad.ready) return
                    check(qnCorners.notesPopup.presentationActive === true,
                        "QuickNotes Edgebar opened on hover")
                    check(qnCorners.notesPopup.popupPinned === false,
                        "QuickNotes starts unpinned")
                    const qnViewBefore = find(qnCorners.notesPopup.contentItem,
                        item => typeof item.focusEditor === "function" && item.markdownReading !== undefined)
                    const qnTextBefore = find(qnCorners.notesPopup.contentItem,
                        item => item.objectName === "quickNotesSourceEditor")
                    check(Boolean(qnViewBefore) && Boolean(qnTextBefore), "QuickNotesView + Source editor loaded inside Edgebar popup")
                    qnViewBefore.focusEditor()
                    qnCorners.notesPopup.enterEditorMode()
                    qnTextBefore.text = "UNSAVED_DRAFT_BLOCK_CHECK"
                    qnCorners.notesAnchor.containsMouse = false
                    check(qnCorners.notesPopup.editorFocused === true,
                        "QuickNotes entered active editing mode while unpinned")
                    check(qnViewBefore.markdownReading === false,
                        "QuickNotesView entered Source editing mode before block")
                    check(win.qnEditorLeaseOutput === "TEST-QN",
                        "Active editing QuickNotes acquired output editor lease")
                    // Heavy overlay (Dashboard) activates corners.blocked -> must flush unsaved draft & suspend cleanly
                    qnCorners.blocked = true
                    check(Notepad.text === "UNSAVED_DRAFT_BLOCK_CHECK",
                        "Suspending active-editing QuickNotes flushed unsaved TextArea draft to Notepad")
                    check(qnCorners.notesAvailable === false && qnCorners.notesAnchor.visible === false,
                        "Dashboard block hides notesAnchor")
                    check(qnCorners.notesPopup.presentationActive === false,
                        "Active-editing QuickNotes temp-hidden while Dashboard blocks corner")
                    check(qnCorners.notesPopup.editorFocused === false,
                        "Active-editing QuickNotes releases keyboard focus while blocked")
                    check(win.qnEditorLeaseOutput === "",
                        "Suspended QuickNotes releases cross-output editor lease while blocked")
                    check(qnCtrl.activePopup === null,
                        "Suspended QuickNotes releases surface controller slot while blocked")
                    // Dashboard -> Settings same-turn unblock/reblock flicker must NOT lose restore intent
                    qnCorners.blocked = false
                    qnCorners.blocked = true
                } else if (stage === 9) {
                    check(qnCorners.notesPopup.presentationActive === false && qnCtrl.activePopup === null,
                        "Same-turn block flicker keeps QuickNotes suspended while still blocked")
                    // Close blocking heavy overlay -> active-editing QuickNotes MUST auto-restore!
                    qnCorners.blocked = false
                } else if (stage === 10) {
                    // Simulate AbyssPerimeter.ensureEscapeFocus() firing during restore (must NOT steal focus from TextArea!)
                    win.simulateEnsureEscapeFocus(qnHost)
                    check(qnCorners.notesAvailable === true,
                        "QuickNotes corner available again after Dashboard closes")
                    check(qnCorners.notesPopup.presentationActive === true,
                        "Unpinned active-editing QuickNotes AUTO-RESTORED after Dashboard closed!")
                    check(qnCorners.notesPopup.editorFocused === true,
                        "Restored QuickNotes preserved active editing session")
                    check(qnCorners.notesPopup.popupPinned === false,
                        "Restored unpinned QuickNotes did NOT silently mutate popupPinned")
                    check(qnCtrl.activePopup === qnCorners.notesPopup,
                        "Restored QuickNotes re-joined surface controller")
                    check(win.qnEditorLeaseOutput === "TEST-QN",
                        "Restored QuickNotes re-acquired editor lease")
                } else if (stage === 11) {
                    const qnViewAfter = find(qnCorners.notesPopup.contentItem,
                        item => typeof item.focusEditor === "function" && item.markdownReading !== undefined)
                    const qnTextAfter = find(qnCorners.notesPopup.contentItem,
                        item => item.objectName === "quickNotesSourceEditor")
                    check(Boolean(qnViewAfter) && qnViewAfter.markdownReading === false,
                        "Restored QuickNotesView stayed in Source editing mode after ensureEscapeFocus")
                    check(Boolean(qnTextAfter) && qnTextAfter.activeFocus === true,
                        "Restored QuickNotes TextArea regained real activeFocus without clicking again")
                    check(Boolean(qnTextAfter) && qnTextAfter.text === "UNSAVED_DRAFT_BLOCK_CHECK",
                        "Restored QuickNotes preserved flushed unsaved draft text")
                    // Non-blocked modal allocator eviction (dialogBody/wallpaperBody) must temp-hide, flush draft,
                    // hide clickOutsideBackdrop, and auto-restore active editing without losing focus!
                    qnTextAfter.text = "UNSAVED_EVICT_DRAFT_CHECK"
                    qnModalHost.open = true
                } else if (stage === 12) {
                    check(qnHost.placementVisible === false && qnCorners.notesPopup._placementEvicted === true,
                        "Modal overlay evicted active-editing QuickNotes host via allocator")
                    check(qnCorners.notesPopup.editorFocused === true && qnCorners.notesPopup.presentationActive === true,
                        "Allocator eviction preserved unpinned active-editing QuickNotes session")
                    check(qnCorners.notesPopup._clickOutsideBackdropObject.visible === false,
                        "Evicted QuickNotes hid clickOutsideBackdrop while covered by modal")
                    check(Notepad.text === "UNSAVED_EVICT_DRAFT_CHECK",
                        "Allocator eviction flushed unsaved draft to Notepad")
                    qnModalHost.open = false
                } else if (stage === 13) {
                    win.simulateEnsureEscapeFocus(qnHost)
                    check(qnHost.placementVisible === true && qnCorners.notesPopup._placementEvicted === false,
                        "QuickNotes host restored placementVisible after modal closed")
                } else if (stage === 14) {
                    const qnViewUnEvict = find(qnCorners.notesPopup.contentItem,
                        item => typeof item.focusEditor === "function" && item.markdownReading !== undefined)
                    const qnTextUnEvict = find(qnCorners.notesPopup.contentItem,
                        item => item.objectName === "quickNotesSourceEditor")
                    check(qnCorners.notesPopup.presentationActive === true && qnCorners.notesPopup.editorFocused === true,
                        "Unpinned active-editing QuickNotes survived allocator eviction & restored!")
                    check(Boolean(qnViewUnEvict) && qnViewUnEvict.markdownReading === false
                            && Boolean(qnTextUnEvict) && qnTextUnEvict.activeFocus === true,
                        "QuickNotes re-acquired Source editing + activeFocus after modal eviction")
                    // Second corners.blocked cycle must remain idempotent
                    qnCorners.blocked = true
                    check(qnCorners.notesPopup.presentationActive === false && qnCorners.notesPopup.editorFocused === false,
                        "Cycle 2: active-editing QuickNotes suspended cleanly again")
                    qnCorners.blocked = false
                } else if (stage === 15) {
                    check(qnCorners.notesPopup.presentationActive === true && qnCorners.notesPopup.editorFocused === true,
                        "Cycle 2: active-editing QuickNotes auto-restored again!")
                    // Genuine user close (leaveEditorMode) ends session cleanly
                    qnCorners.notesPopup.leaveEditorMode()
                    qnCorners.notesPopup.dismissPresentation()
                    check(qnCorners.notesPopup.presentationActive === false && qnCorners.notesPopup.editorFocused === false,
                        "User dismissal closed active-editing QuickNotes cleanly")
                    // Case 2: Hover-only QuickNotes (unpinned, NOT editing) across corners.blocked AND modal eviction
                    qnCorners.notesAnchor.containsMouse = true
                } else if (stage === 16) {
                    check(qnCorners.notesPopup.presentationActive === true
                            && qnCorners.notesPopup.editorFocused === false
                            && qnCorners.notesPopup.popupPinned === false,
                        "Hover-only QuickNotes opened without editor focus or pin")
                    // Dashboard opens while pointer leaves -> must dismiss without resurrecting
                    qnCorners.notesAnchor.containsMouse = false
                    qnCorners.blocked = true
                    check(qnCorners.notesPopup.presentationActive === false && qnCtrl.activePopup === null,
                        "Hover-only QuickNotes dismissed cleanly when Dashboard blocked corner")
                    // Close Dashboard -> hover-only QuickNotes MUST STAY CLOSED!
                    qnCorners.blocked = false
                } else if (stage === 17) {
                    check(qnCorners.notesPopup.presentationActive === false
                            && qnCorners.notesPopup.requestedVisible === false
                            && qnCorners.notesPopup.editorFocused === false
                            && qnCtrl.activePopup === null,
                        "Hover-only QuickNotes STAYED CLOSED after Dashboard closed (zero ghost resurrection)!")
                    // Re-hover after block must still work cleanly (no _liquidDismissed lockout)
                    qnCorners.notesAnchor.containsMouse = true
                } else if (stage === 18) {
                    check(qnCorners.notesPopup.presentationActive === true,
                        "Hover-only QuickNotes re-opened cleanly on fresh hover after Dashboard")
                    // Hover-only QuickNotes evicted by non-blocked modal must dismiss and NEVER resurrect
                    qnCorners.notesAnchor.containsMouse = false
                    qnModalHost.open = true
                } else if (stage === 19) {
                    check(qnCorners.notesPopup.presentationActive === false && qnCtrl.activePopup === null,
                        "Hover-only QuickNotes dismissed cleanly on modal allocator eviction")
                    qnModalHost.open = false
                } else if (stage === 20) {
                    check(qnCorners.notesPopup.presentationActive === false && qnCtrl.activePopup === null,
                        "Hover-only QuickNotes NEVER resurrected after modal closed")
                    // Case 3: Unpinned To-do inline Add dialog (todoDialogOpen === true) preserves draft across corners.blocked
                    qnCorners.notesAnchor.containsMouse = true
                } else if (stage === 21) {
                    qnCorners.notesPopup.selectedMainTab = 0
                    qnCorners.notesPopup.selectedNotesTab = 1
                } else if (stage === 22) {
                    const todoView = find(qnCorners.notesPopup.contentItem, item => item.showAddDialog !== undefined)
                    check(Boolean(todoView), "DashTodo loaded inside QuickNotes popup")
                    todoView.showAddDialog = true
                    const todoInput = find(todoView, item => typeof item.addTask === "function" && item.text !== undefined)
                    check(Boolean(todoInput), "DashTodo add dialog TextField located")
                    todoInput.text = "Review popup yielding"
                    qnCorners.notesAnchor.containsMouse = false
                    check(qnCorners.notesPopup.todoDialogOpen === true, "Unpinned To-do add dialog active before block")
                    qnCorners.blocked = true
                    check(qnCorners.notesPopup.presentationActive === false && qnCorners.notesPopup.todoDialogOpen === false,
                        "Active To-do add dialog suspended cleanly while Dashboard blocked corner")
                    qnCorners.blocked = false
                } else if (stage === 23) {
                    win.simulateEnsureEscapeFocus(qnHost)
                    const todoView2 = find(qnCorners.notesPopup.contentItem, item => item.showAddDialog !== undefined)
                    const todoInput2 = todoView2 ? find(todoView2, item => typeof item.addTask === "function" && item.text !== undefined) : null
                    check(qnCorners.notesPopup.presentationActive === true && qnCorners.notesPopup.todoDialogOpen === true,
                        "Unpinned To-do inline Add dialog AUTO-RESTORED after Dashboard closed!")
                    check(Boolean(todoInput2) && todoInput2.text === "Review popup yielding",
                        "Restored To-do Add dialog preserved in-progress draft text")
                    // Close To-do dialog and return to Quick Notes tab for Case 4
                    if (todoView2) todoView2.showAddDialog = false
                    qnCorners.notesPopup.selectedNotesTab = 0
                    qnCorners.notesPopup.dismissPresentation()
                    // Case 4: Pinned QuickNotes restores across block, and owner revocation clears pending restore
                    qnCorners.notesAnchor.containsMouse = true
                } else if (stage === 24) {
                    qnCorners.notesPopup.popupPinned = true
                    qnCorners.notesAnchor.containsMouse = false
                    qnCorners.blocked = true
                    check(qnCorners.notesPopup.presentationActive === false && qnCtrl.activePopup === null,
                        "Pinned QuickNotes suspended cleanly while blocked")
                    qnCorners.blocked = false
                } else if (stage === 25) {
                    check(qnCorners.notesPopup.presentationActive === true
                            && qnCorners.notesPopup.popupPinned === true
                            && qnCorners.notesPopup.editorFocused === false,
                        "Pinned QuickNotes auto-restored pinned after Dashboard closed")
                    // Revoking corner ownership while blocked must cancel restore intent
                    qnCorners.blocked = true
                    qnCorners.presentationEnabled = false
                    qnCorners.blocked = false
                    qnCorners.presentationEnabled = true
                } else if (stage === 26) {
                    check(qnCorners.notesPopup.presentationActive === false
                            && qnCorners.notesPopup.popupPinned === false
                            && qnCtrl.activePopup === null,
                        "Owner revocation while blocked canceled pending restore cleanly")
                    // Case 5: Module Icon mode (AbyssBarModule) active-editing vs hover-only across edgebarBlocked
                    const modFace = qnBarMod.feature
                    const modPopup = modFace ? find(modFace, item => item.liquidPresentationKind === "notesTimers") : null
                    check(Boolean(modFace) && Boolean(modPopup), "Module Icon notesTimers QuickNotesPopup mounted")
                    modPopup.editorFocused = true
                    check(modPopup.presentationActive === true && modPopup.popupPinned === false,
                        "Module Icon unpinned active-editing QuickNotes opened")
                    qnBarMod.edgebarBlocked = true
                    check(modPopup.presentationActive === false && modPopup.editorFocused === false && qnModCtrl.activePopup === null,
                        "Module Icon active-editing QuickNotes suspended cleanly while edgebarBlocked")
                    qnBarMod.edgebarBlocked = false
                } else if (stage === 27) {
                    const modPopup2 = find(qnBarMod.feature, item => item.liquidPresentationKind === "notesTimers")
                    check(Boolean(modPopup2) && modPopup2.presentationActive === true
                            && modPopup2.editorFocused === true && modPopup2.popupPinned === false,
                        "Module Icon unpinned active-editing QuickNotes AUTO-RESTORED after unblock!")
                    modPopup2.leaveEditorMode()
                    modPopup2.dismissPresentation()
                    // Module Icon hover-only must stay closed after unblock
                    modPopup2.entryBridgeHeld = true
                    check(modPopup2.presentationActive === true && modPopup2.editorFocused === false,
                        "Module Icon hover-bridge QuickNotes opened")
                    qnBarMod.edgebarBlocked = true
                    check(modPopup2.presentationActive === false && qnModCtrl.activePopup === null,
                        "Module Icon hover-only QuickNotes dismissed cleanly when blocked")
                    qnBarMod.edgebarBlocked = false
                } else if (stage === 28) {
                    const modPopup3 = find(qnBarMod.feature, item => item.liquidPresentationKind === "notesTimers")
                    check(Boolean(modPopup3) && modPopup3.presentationActive === false
                            && modPopup3.editorFocused === false && qnModCtrl.activePopup === null,
                        "Module Icon hover-only QuickNotes STAYED CLOSED after unblock!")
                    // Case A (hover Edgebar 1st -> hover Sidebar 2nd) close-freeze test
                    freezeCtrl.noteHoverSurfaceActive("styledPopup0", true)
                    freezeEdgebar.open = true
                } else if (stage === 29) {
                    freezeCtrl.noteHoverSurfaceActive("leftPanel", true)
                    freezeSidebar.open = true
                } else if (stage === 30) {
                    check(freezeSidebar.placement.vacancyBorrowed === true && freezeSidebar.placement.span > 700,
                        "Case A: Sidebar stretched when hovered after Edgebar (span=" + freezeSidebar.placement?.span + ")")
                    // Focusing/editing an already-open QuickNotes Edgebar must NEVER swap or move it!
                    const ebBeforeInward = freezeEdgebar.placement.inward
                    const ebBeforeX = freezeEdgebar.placement.content.x
                    const ebBeforeY = freezeEdgebar.placement.content.y
                    check(ebBeforeInward > 0 && freezeSidebar.placement.inward === 0,
                        "Case A: Initially Edgebar is inward behind Sidebar")
                    freezeEdgebar.simulatedEditorFocused = true
                    check(freezeEdgebar._latchedExplicitIntent === false && freezeEdgebar.placementIntent === "hover",
                        "Focusing already-open hover QuickNotes keeps latched placementIntent='hover'")
                    check(freezeEdgebar.placement.inward === ebBeforeInward
                            && Math.abs(freezeEdgebar.placement.content.x - ebBeforeX) < 0.1
                            && Math.abs(freezeEdgebar.placement.content.y - ebBeforeY) < 0.1
                            && freezeSidebar.placement.inward === 0,
                        "Focusing already-open QuickNotes never moves QuickNotes or swaps Sidebar")
                    freezeEdgebar.simulatedEditorFocused = false
                    const stretchedSideSpan = freezeSidebar.placement.span
                    // Pointer leaves both; Edgebar closes first
                    freezeCtrl.noteHoverSurfaceLeave("styledPopup0", true)
                    freezeCtrl.noteHoverSurfaceLeave("leftPanel", true)
                    freezeEdgebar.open = false
                    check(freezeSidebar.placementFrozenForExit === true,
                        "Case A: Sidebar froze borrowed geometry while waiting to close")
                    check(Math.abs(freezeSidebar.effectivePlacement.span - stretchedSideSpan) < 0.5,
                        "Case A: Sidebar must NOT shrink back up before closing")
                    // Re-hovering Sidebar unfreezes cleanly
                    freezeCtrl.noteHoverSurfaceActive("leftPanel", true)
                    check(freezeSidebar.placementFrozenForExit === false,
                        "Re-hovering Sidebar unfreezes placement cleanly")
                    freezeCtrl.noteHoverSurfaceLeave("leftPanel", true)
                    freezeSidebar.open = false
                } else if (stage === 31) {
                    check(Math.abs(freezeSidebar.effectivePlacement.span - 700) < 0.5
                            || freezeSidebar.progress <= 0.001,
                        "Case A: Closing Sidebar retracted at non-shrunk snapshot or finished closing")
                    // Case B (hover Sidebar 1st -> hover Edgebar 2nd): Edgebar owns outer edge + stretches upward!
                    freezeCtrl.noteHoverSurfaceActive("leftPanel", true)
                    freezeSidebar.open = true
                } else if (stage === 32) {
                    freezeCtrl.noteHoverSurfaceActive("styledPopup0", true)
                    freezeEdgebar.open = true
                } else if (stage === 33) {
                    check(freezeEdgebar.placement.inward === 0 && freezeEdgebar.placement.vacancyBorrowed === true
                            && freezeEdgebar.placement.vacancyDirection === "top" && freezeEdgebar.placement.span > 430,
                        "Case B: Later Edgebar stays at inward=0 and stretches upward (span="
                            + freezeEdgebar.placement?.span + ", inward=" + freezeEdgebar.placement?.inward + ")")
                    check(freezeSidebar.placement.inward > 0,
                        "Case B: Earlier Sidebar slides inward behind Edgebar (inward=" + freezeSidebar.placement?.inward + ")")
                    check(freezeSidebar.pyramidMotionEnabled === true,
                        "Case B: Stacked inward Sidebar must enable pyramidMotionEnabled")
                    const stretchedEbSpan = freezeEdgebar.placement.span
                    const ebBoundaryX = freezeEdgebar.record.surface.x + freezeEdgebar.record.surface.width
                    // Pointer leaves both; Sidebar closes first
                    freezeCtrl.noteHoverSurfaceLeave("leftPanel", true)
                    freezeCtrl.noteHoverSurfaceLeave("styledPopup0", true)
                    freezeSidebar.open = false
                    check(freezeSidebar.pyramidClosing === true,
                        "Case B: Stacked inward Sidebar must enter pyramidClosing on close")
                    check(freezeSidebar.pyramidOriginRecord !== null
                            && Math.abs(freezeSidebar.pyramidOriginRecord.content.x - ebBoundaryX) < 1.0,
                        "Case B: Stacked Sidebar must collapse directly into Edgebar boundary (got x="
                            + freezeSidebar.pyramidOriginRecord?.content?.x + ", expected=" + ebBoundaryX + ")")
                    check(freezeEdgebar.placementFrozenForExit === true,
                        "Case B: Edgebar froze stretched geometry when Sidebar closed before it")
                    check(Math.abs(freezeEdgebar.effectivePlacement.span - stretchedEbSpan) < 0.5,
                        "Case B: Edgebar must NOT shrink back down while closing")
                    freezeEdgebar.open = false
                } else if (stage === 34) {
                    check(warmSidebarHost.backgroundPreload === false && warmSidebarHost.contentItem.item === null
                            && warmSidebarHost.loadingPresentationActive === false,
                        "WarmSidebar: stays unloaded and loading-screen-free before warmup")
                    warmSidebarHost.backgroundPreload = true
                    const ebCanvas = findCanvas(freezeEdgebar)
                    check(ebCanvas !== null && ebCanvas.parent !== null
                            && ebCanvas.parent.width < ebCanvas.width - 1
                            && Math.abs(ebCanvas.x - (ebCanvas.parent.width - ebCanvas.width)) < 0.5,
                        "Case B: Left-edge closing Edgebar must slide contentCanvas rigidly left (x="
                            + (ebCanvas ? ebCanvas.x : "null") + ", expected="
                            + (ebCanvas && ebCanvas.parent ? (ebCanvas.parent.width - ebCanvas.width) : "null") + ")")
                    freezeEdgebar.fifoTestSemanticOpen = true
                    freezeEdgebar.fifoTestProgress = 1
                    freezeEdgebar.open = true
                    freezeSidebar.open = true
                } else if (stage === 35) {
                    if (fifoGateStarted)
                        return
                    fifoGateStarted = true
                    check(freezeCtrl.participants["styledPopup0"]?.geometry?.edge === "left"
                            && freezeCtrl.participants["leftPanel"]?.geometry?.edge === "left",
                        "Case C: Both same-edge participants must have live left geometry before FIFO close gate")
                    freezeCtrl.fifoCloseStepMs = 30
                    freezeCtrl._fifoStaggerTimer.stop()
                    freezeCtrl._fifoWaitTimer.stop()
                    freezeCtrl._fifoHoverSeq = 0
                    freezeCtrl._fifoHoverState = ({})
                    freezeCtrl._fifoLastClosedId = ""
                    freezeCtrl._fifoLastCloseStartedMs = 0
                    freezeCtrl.noteHoverSurfaceActive("styledPopup0", true)
                    freezeCtrl.noteHoverSurfaceActive("leftPanel", true)
                    freezeCtrl.noteHoverSurfaceLeave("styledPopup0", true)
                    freezeCtrl.noteHoverSurfaceLeave("leftPanel", true)
                    freezeCtrl.requestHoverSurfaceClose("styledPopup0", () => {
                        freezeEdgebar.fifoTestSemanticOpen = false
                        freezeEdgebar.fifoTestProgress = 0.35
                    })
                    freezeCtrl.requestHoverSurfaceClose("leftPanel", () => {
                        fifoSbClosedCount++
                        freezeSidebar.open = false
                    })
                    fifoGatePhase1Timer.start()
                    return
                }
                stage++
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    property bool fifoGateStarted: false
    property int fifoSbClosedCount: 0
    function findCanvas(item) {
        if (!item) return null
        if (item.fullRect !== undefined) return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) {
            const hit = findCanvas(kids[i])
            if (hit) return hit
        }
        return null
    }
    Timer {
        id: fifoGatePhase1Timer
        interval: 110
        repeat: false
        onTriggered: {
            try {
                check(fifoSbClosedCount === 0,
                    "Case C: same-edge FIFO close must wait while previous surface progress > 0.015 (count="
                        + fifoSbClosedCount + ", ebGeomProg="
                        + (freezeCtrl.participants["styledPopup0"]?.geometry?.progress) + ")")
                check(Math.abs((freezeCtrl.participants["styledPopup0"]?.geometry?.progress ?? -1) - 0.35) < 0.01,
                    "Case C: closing popup geometry.progress must hold at 0.35 (got="
                        + (freezeCtrl.participants["styledPopup0"]?.geometry?.progress) + ")")
                freezeEdgebar.fifoTestProgress = 0.01
                fifoGatePhase2Timer.start()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }
    Timer {
        id: fifoGatePhase2Timer
        interval: 60
        repeat: false
        onTriggered: {
            try {
                check(fifoSbClosedCount === 1,
                    "Case C: same-edge FIFO close must fire once previous surface progress <= 0.015 (count=" + fifoSbClosedCount + ")")
                freezeEdgebar.open = false

                // Verify warmed zero-loading-screen sidebar retains its item across open -> close -> reopen
                check(warmSidebarHost.contentItem.status === Loader.Ready && warmSidebarHost.contentItem.item !== null,
                    "WarmSidebar: backgroundPreload warmed sidebar content while closed (status=" + warmSidebarHost.contentItem.status + ")")
                const warmedItem = warmSidebarHost.contentItem.item
                const warmLoadScreen = findByObjectName(warmSidebarHost, "abyssBodyLoadingScreen")
                check(warmSidebarHost.loadingPresentationActive === false && (!warmLoadScreen || !warmLoadScreen.visible),
                    "WarmSidebar: never activates abyssBodyLoadingScreen before open")
                warmSidebarHost.open = true
                check(warmSidebarHost.progress === 1 && warmSidebarHost.loadingPresentationActive === false
                        && warmSidebarHost.openedOnce === true && warmSidebarHost.contentItem.item === warmedItem
                        && (!warmLoadScreen || !warmLoadScreen.visible),
                    "WarmSidebar: first open uses prewarmed instance immediately with zero loading screen")
                warmSidebarHost.backgroundPreload = false
                warmSidebarHost.open = false
                check(warmSidebarHost.progress === 0 && warmSidebarHost.contentItem.active === true
                        && warmSidebarHost.contentItem.item === warmedItem,
                    "WarmSidebar: close preserves loaded item via retainAfterFirstOpen even after backgroundPreload=false")
                warmSidebarHost.open = true
                check(warmSidebarHost.progress === 1 && warmSidebarHost.loadingPresentationActive === false
                        && warmSidebarHost.contentItem.item === warmedItem,
                    "WarmSidebar: reopen reuses retained item without recreation")
                warmSidebarHost.open = false

                // Verify embedded AbyssCustomizationDock sizes immediately without _animatedTrayHeight lag
                const embH1 = embeddedDockProbe.implicitHeight
                embeddedDockProbe.trayHeight = 190
                check(embeddedDockProbe.implicitHeight === embH1 + 38,
                    "Embedded AbyssCustomizationDock updates implicitHeight synchronously without double-animation lag")
                embeddedDockProbe.trayHeight = 152
                check(embeddedDockProbe.implicitHeight === embH1,
                    "Embedded AbyssCustomizationDock contracts synchronously")

                // Enter Edit Abyss Layout stage and verify dynamic dock auto-expansion
                editStageProbe.editStageMode = "abyss"
                editStagePhase1Timer.start()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    property real editBaseDockH: 0
    property real editBaseCardDockH: 0
    property real editBaseLeftH: 0
    property real editBaseCardLeftH: 0
    property real editBaseRightH: 0
    property real editBaseCardRightH: 0

    Timer {
        id: editStagePhase1Timer
        interval: 420
        repeat: false
        onTriggered: {
            try {
                check(editStageProbe.editStageProgress >= 0.99 && editStageProbe.editCard.active,
                    "EditStageProbe entered active Edit Abyss Layout (p=" + editStageProbe.editStageProgress + ")")
                editBaseDockH = dockedEditor.desiredDockHeight
                editBaseCardDockH = editStageProbe.editCard.dockHeight
                editBaseLeftH = dockedEditor.desiredLeftDockHeight
                editBaseCardLeftH = editStageProbe.editCard.leftDockHeight
                editBaseRightH = dockedEditor.desiredRightDockHeight
                editBaseCardRightH = editStageProbe.editCard.rightDockHeight

                const bottomScroll = findByObjectName(editStageBottomDock, "abyssEdgeEditorScroll")
                const bottomDock = findByObjectName(editStageBottomDock, "abyssEdgeEditorDock")
                const inspector = findByObjectName(editStageBottomDock, "abyssDockModuleInspector")
                const leftDockItem = findByObjectName(editStageLeftDock, "abyssLeftPopupsDock")
                const rightDockItem = findByObjectName(editStageRightDock, "abyssRightEdgeDock")
                const joinBtn = findByObjectName(editStageLeftDock, "abyssIpcJoinCornerToggle")
                const leftFlick = find(leftDockItem, item => item && item.contentHeight !== undefined && item.flickableDirection !== undefined)
                const rightFlick = find(rightDockItem, item => item && item.contentHeight !== undefined && item.flickableDirection !== undefined)

                check(Boolean(bottomScroll) && Boolean(bottomDock) && Boolean(inspector), "Bottom Edit Stage dock items present")
                check(bottomScroll.interactive === false && bottomDock.implicitHeight <= editStageBottomDock.height + 0.5,
                    "Bottom dock fits without clipping at entry (dock=" + bottomDock.implicitHeight + ", stage=" + editStageBottomDock.height + ")")
                const inspBR = inspector.mapToItem(editStageBottomDock, 0, inspector.height)
                check(inspector.visible && inspBR.y <= editStageBottomDock.height + 0.5,
                    "Bottom dock inspector strip is completely unclipped at entry (bottom=" + inspBR.y + ", stage=" + editStageBottomDock.height + ")")

                check(Boolean(leftDockItem) && Boolean(leftFlick), "Left Popups dock & Flickable present")
                check(leftFlick.contentHeight <= leftFlick.height + 1 && leftFlick.interactive === false,
                    "Left dock fits at entry with zero scroll clipping (content=" + leftFlick.contentHeight + ", h=" + leftFlick.height + ")")
                check(Boolean(joinBtn) && joinBtn.visible === true,
                    "Left dock abyssIpcJoinCornerToggle is visible right at initial entry")
                const joinBR = joinBtn.mapToItem(editStageLeftDock, 0, joinBtn.height)
                check(joinBR.y <= editStageLeftDock.height + 0.5,
                    "Left dock abyssIpcJoinCornerToggle is not clipped at entry (bottom=" + joinBR.y + ", stage=" + editStageLeftDock.height + ")")

                check(Boolean(rightDockItem) && Boolean(rightFlick), "Right Screen Edge dock & Flickable present")
                check(rightFlick.contentHeight <= rightFlick.height + 1 && rightFlick.interactive === false,
                    "Right dock fits at entry with zero scroll clipping (content=" + rightFlick.contentHeight + ", h=" + rightFlick.height + ")")

                // Trigger dynamic expansion in both Bottom dock (feedback banner) and Left dock (Custom position slider)
                dockedEditor.feedback = "Unlock this module before moving it"
                const posSettings = findByObjectName(editStageLeftDock, "abyssEditorIpcPlacement")
                check(Boolean(posSettings), "Found abyssEditorIpcPlacement inside Left dock")
                posSettings.change("alignment", "custom")

                editStagePhase2Timer.start()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    Timer {
        id: editStagePhase2Timer
        interval: 340
        repeat: false
        onTriggered: {
            try {
                const bottomScroll = findByObjectName(editStageBottomDock, "abyssEdgeEditorScroll")
                const bottomDock = findByObjectName(editStageBottomDock, "abyssEdgeEditorDock")
                const inspector = findByObjectName(editStageBottomDock, "abyssDockModuleInspector")
                const leftDockItem = findByObjectName(editStageLeftDock, "abyssLeftPopupsDock")
                const leftFlick = find(leftDockItem, item => item && item.contentHeight !== undefined && item.flickableDirection !== undefined)

                check(dockedEditor.desiredDockHeight >= editBaseDockH + 22,
                    "Bottom dock desiredDockHeight expanded for feedback banner (before=" + editBaseDockH + ", after=" + dockedEditor.desiredDockHeight + ")")
                check(Math.abs(editStageProbe.animatedStageDockHeight - Math.round(dockedEditor.desiredDockHeight)) <= 1,
                    "AbyssPerimeter animatedStageDockHeight followed expansion live (anim=" + editStageProbe.animatedStageDockHeight + ", desired=" + dockedEditor.desiredDockHeight + ")")
                check(editStageProbe.editCard.dockHeight > editBaseCardDockH + 20,
                    "DesktopEditStage Bottom dock card expanded (before=" + editBaseCardDockH + ", after=" + editStageProbe.editCard.dockHeight + ")")
                check(bottomScroll.interactive === false && bottomDock.implicitHeight <= editStageBottomDock.height + 0.5,
                    "Expanded Bottom dock fits banner + gallery + inspector with zero clipping (dock=" + bottomDock.implicitHeight + ", stage=" + editStageBottomDock.height + ")")
                const inspBR = inspector.mapToItem(editStageBottomDock, 0, inspector.height)
                check(inspBR.y <= editStageBottomDock.height + 0.5,
                    "Inspector remains unclipped below feedback banner (inspBottom=" + inspBR.y + ", stage=" + editStageBottomDock.height + ")")

                check(dockedEditor.desiredLeftDockHeight > editBaseLeftH + 20,
                    "Left dock desiredLeftDockHeight expanded for Custom position slider (before=" + editBaseLeftH + ", after=" + dockedEditor.desiredLeftDockHeight + ")")
                check(Math.abs(editStageProbe.animatedStageLeftDockHeight - Math.round(dockedEditor.desiredLeftDockHeight)) <= 1,
                    "AbyssPerimeter animatedStageLeftDockHeight followed Left dock expansion (anim=" + editStageProbe.animatedStageLeftDockHeight + ", desired=" + dockedEditor.desiredLeftDockHeight + ")")
                check(editStageProbe.editCard.leftDockHeight > editBaseCardLeftH + 20,
                    "DesktopEditStage Left dock card expanded (before=" + editBaseCardLeftH + ", after=" + editStageProbe.editCard.leftDockHeight + ")")
                check(leftFlick.contentHeight <= leftFlick.height + 1 && leftFlick.interactive === false,
                    "Expanded Left dock fits Custom position slider with zero clipping (content=" + leftFlick.contentHeight + ", h=" + leftFlick.height + ")")

                dockedEditor.editorSection = "presets"
                const posSettings = findByObjectName(editStageLeftDock, "abyssEditorIpcPlacement")
                posSettings.change("alignment", "source")
                editStagePhase3Timer.start()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    Timer {
        id: editStagePhase3Timer
        interval: 340
        repeat: false
        onTriggered: {
            try {
                const bottomScroll = findByObjectName(editStageBottomDock, "abyssEdgeEditorScroll")
                check(bottomScroll.contentHeight <= bottomScroll.height + 1 && bottomScroll.interactive === false,
                    "Bottom Presets tab + feedback banner fits cleanly without clipping (content=" + bottomScroll.contentHeight + ", h=" + bottomScroll.height + ")")
                check(Math.abs(editStageProbe.editCard.leftDockHeight - editBaseCardLeftH) <= 2,
                    "Left dock contracted cleanly back to baseline after leaving Custom position (base=" + editBaseCardLeftH + ", now=" + editStageProbe.editCard.leftDockHeight + ")")

                dockedEditor.feedback = ""
                dockedEditor.editorSection = "modules"
                editStagePhase4Timer.start()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    Timer {
        id: editStagePhase4Timer
        interval: 340
        repeat: false
        onTriggered: {
            try {
                check(Math.abs(editStageProbe.editCard.dockHeight - editBaseCardDockH) <= 2,
                    "Bottom dock contracted smoothly back to baseline once feedback cleared (base=" + editBaseCardDockH + ", now=" + editStageProbe.editCard.dockHeight + ")")
                editStageProbe.editStageMode = ""

                // Verify DashboardHeader icon indicators + DashboardConfig customization live round-trip
                check(iconHeaderProbe.height === 32,
                    "DashboardHeader keeps 32px height when showActions=false (got=" + iconHeaderProbe.height + ")")
                const icon0 = findByObjectName(iconHeaderProbe, "dashboardPageIcon0")
                const icon1 = findByObjectName(iconHeaderProbe, "dashboardPageIcon1")
                const icon2 = findByObjectName(iconHeaderProbe, "dashboardPageIcon2")
                const indPill = findByObjectName(iconHeaderProbe, "dashboardActivePageIndicator")
                check(Boolean(icon0) && icon0.visible && icon0.text === "dashboard",
                    "Dashboard tab 0 shows default 'dashboard' icon")
                check(Boolean(icon1) && icon1.visible && icon1.text === "library_music",
                    "Dashboard tab 1 shows default 'library_music' icon")
                check(Boolean(icon2) && icon2.visible && icon2.text === "calendar_month",
                    "Dashboard tab 2 shows default 'calendar_month' icon")
                check(findByObjectName(iconHeaderProbe, "dashboardPageDot0") === null,
                    "Legacy circular dot removed")
                check(Boolean(indPill) && indPill.visible && indPill.width === 32 && indPill.height === 30,
                    "Active page indicator renders 32x30 icon pill")

                const presetRocket = findByObjectName(dashConfigProbe, "dashboardTabIconPreset_rocket_launch")
                const iconField = findByObjectName(dashConfigProbe, "dashboardTabIconInput")
                const resetBtn = findByObjectName(dashConfigProbe, "dashboardTabIconResetButton")
                const previewIcon = findByObjectName(dashConfigProbe, "dashboardTabIconPreview")
                check(Boolean(presetRocket) && Boolean(iconField) && Boolean(resetBtn) && Boolean(previewIcon),
                    "DashboardConfig renders Tab indicator icons customizer controls")
                check(resetBtn.enabled === false, "Reset button disabled before customization")

                presetRocket.clicked()
                check(icon0.text === "rocket_launch" && previewIcon.text === "rocket_launch",
                    "Selecting preset icon updates DashboardHeader and preview live (got=" + icon0.text + ")")
                check(resetBtn.enabled === true && iconField.text === "rocket_launch",
                    "Customizing icon enables Reset and syncs input text")

                dashConfigProbe.applySelectedTabIcon("Star")
                check(icon0.text === "star" && previewIcon.text === "star",
                    "Custom typed icon sanitizes and live-updates header (got=" + icon0.text + ")")

                resetBtn.clicked()
                check(icon0.text === "dashboard" && resetBtn.enabled === false
                        && (Config.options?.dashboard?.tabIcons?.length ?? 0) === 0,
                    "Reset restores default tab icon cleanly")
                check(findByObjectName(iconHeaderProbe, "dashboardSetDefaultTab") === null
                        && findByObjectName(iconHeaderProbe, "dashboardCreateCustomTab") === null
                        && findByObjectName(iconHeaderProbe, "dashboardDeleteCustomTab") === null
                        && findByObjectName(iconHeaderProbe, "dashboardRenameCustomTab") === null
                        && findByObjectName(iconHeaderProbe, "dashboardCustomTabActions") === null,
                    "Redundant inline SetDefault/Add/Rename/Delete buttons must be removed from DashboardHeader")
                iconHeaderProbe.showActions = true
                const hdrEditBtn = findByObjectName(iconHeaderProbe, "dashboardEditLayoutButton")
                check(Boolean(hdrEditBtn), "DashboardHeader exposes dashboardEditLayoutButton")
                for (let idx = 0; idx < iconHeaderProbe.pageIds.length; ++idx) {
                    iconHeaderProbe.currentPage = idx
                    check(hdrEditBtn.enabled === true,
                        "Edit Dashboard Layout button enabled on tab '" + iconHeaderProbe.pageIds[idx] + "'")
                }
                iconHeaderProbe.currentPage = 0
                iconHeaderProbe.showActions = false

                // Verify split Left Tabs dock Tab Icon Customizer end-to-end
                const baseLeftH = splitDashToolbarProbe.desiredLeftDockHeight
                check(baseLeftH > 0, "Split Left Tabs dock reports positive baseline height (got=" + baseLeftH + ")")
                const leftIconToggle = findByObjectName(splitLeftDockHost, "dashboardToolbarActionTabIcon")
                const leftPicker = findByObjectName(splitLeftDockHost, "dashboardLeftTabIconPicker")
                const musicBadgeBtn = findByObjectName(splitLeftDockHost, "dashboardLeftPageIconButton_music")
                const leftPresetHeadphones = findByObjectName(splitLeftDockHost, "dashboardToolbarTabIconPreset_headphones")
                const leftIconInput = findByObjectName(splitLeftDockHost, "dashboardToolbarTabIconInput")
                const leftIconReset = findByObjectName(splitLeftDockHost, "dashboardToolbarTabIconReset")
                check(Boolean(leftIconToggle) && Boolean(leftPicker) && Boolean(musicBadgeBtn)
                        && Boolean(leftPresetHeadphones) && Boolean(leftIconInput) && Boolean(leftIconReset),
                    "Split Left Tabs dock Tab Icon controls present")
                check(leftPicker.visible === false, "Split Tab Icon picker hidden by default")

                leftIconToggle.clicked()
                check(leftPicker.visible === true, "Clicking Tab Icon opens split Left dock picker")
                splitTabIconOpenTimer.baseLeftH = baseLeftH
                splitTabIconOpenTimer.restart()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    Timer {
        id: splitTabIconOpenTimer
        property real baseLeftH: 0
        interval: 90
        repeat: false
        onTriggered: {
            try {
                const leftIconToggle = findByObjectName(splitLeftDockHost, "dashboardToolbarActionTabIcon")
                const leftPicker = findByObjectName(splitLeftDockHost, "dashboardLeftTabIconPicker")
                const musicBadgeBtn = findByObjectName(splitLeftDockHost, "dashboardLeftPageIconButton_music")
                const leftPresetHeadphones = findByObjectName(splitLeftDockHost, "dashboardToolbarTabIconPreset_headphones")
                const leftIconInput = findByObjectName(splitLeftDockHost, "dashboardToolbarTabIconInput")
                const leftIconReset = findByObjectName(splitLeftDockHost, "dashboardToolbarTabIconReset")
                const icon1 = findByObjectName(iconHeaderProbe, "dashboardPageIcon1")
                const expandedLeftH = splitDashToolbarProbe.desiredLeftDockHeight
                check(expandedLeftH > baseLeftH + 40,
                    "Opening split Left Tab Icon picker expands dock height (base=" + baseLeftH + ", now=" + expandedLeftH + ")")

                musicBadgeBtn.clicked()
                leftPresetHeadphones.clicked()
                check(icon1.text === "headphones" && leftIconInput.text === "headphones",
                    "Split Left dock badge + preset updates Music tab icon and input live (got=" + icon1.text + ")")

                leftIconReset.clicked()
                check(icon1.text === "library_music" && leftIconInput.text === "",
                    "Split Left dock Reset restores default Music icon cleanly (got=" + icon1.text + ")")

                leftIconToggle.clicked()
                check(leftPicker.visible === false, "Clicking Tab Icon closes split Left dock picker")
                const leftMusicPill = findByObjectName(splitLeftDockHost, "dashboardLeftPagePill_music")
                const leftDashPill = findByObjectName(splitLeftDockHost, "dashboardLeftPagePill_dashboard")
                check(Boolean(leftMusicPill) && Boolean(leftDashPill),
                    "Split Left dock exposes named Pages pills")
                splitDashToolbarProbe.switchDashboardTab("music")
                check(splitDashTabStub.currentPageId === "music" && splitDashCanvasStub.editMode === true,
                    "Switching to Music from split Left Pages pill keeps Edit Mode active")
                splitDashToolbarProbe.switchDashboardTab("dashboard")
                check(splitDashTabStub.currentPageId === "dashboard" && splitDashCanvasStub.editMode === true,
                    "Switching back to Dashboard from split Left Pages pill keeps Edit Mode active")
                splitTabIconCloseTimer.baseLeftH = baseLeftH
                splitTabIconCloseTimer.restart()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }

    Timer {
        id: splitTabIconCloseTimer
        property real baseLeftH: 0
        interval: 90
        repeat: false
        onTriggered: {
            try {
                check(splitDashToolbarProbe.desiredLeftDockHeight === baseLeftH,
                    "Closing split Left Tab Icon picker restores baseline dock height (base=" + baseLeftH + ", now=" + splitDashToolbarProbe.desiredLeftDockHeight + ")")
                console.info("BOOST_SILENT_RUNTIME_PASS", checks)
                Qt.quit()
            } catch (e) {
                console.error("BOOST_SILENT_RUNTIME_FAIL:", e.message, e.stack ?? "")
                Qt.quit()
            }
        }
    }
}
""",
            encoding="utf-8",
        )

        with native_test_session.private_wayland(folder, isolate_xdg=True) as env:
            env = dict(env)
            env.pop("QS_CONFIG_NAME", None)
            env.pop("QS_CONFIG_PATH", None)
            env["XDG_CONFIG_HOME"] = str(folder / "config")
            env["XDG_STATE_HOME"] = str(folder / "state")
            env["XDG_CACHE_HOME"] = str(folder / "cache")
            res = native_test_session.run_qs(folder, env, timeout=30)

        out = res.stdout or ""
        if (
            res.returncode != 0
            or "BOOST_SILENT_RUNTIME_PASS" not in out
            or "BOOST_SILENT_RUNTIME_FAIL" in out
        ):
            raise AssertionError(f"Silent Quickshell runtime test failed:\n{out}")
        for bad in ("TypeError:", "ReferenceError:", "Binding loop", "Unable to assign"):
            if bad in out:
                raise AssertionError(f"QML runtime error ({bad}) detected:\n{out}")
        print("PASS [SilentQuickshellRuntime]:", [l for l in out.splitlines() if "BOOST_SILENT_RUNTIME_PASS" in l][-1])


def test_dashboard_edit_toolbar_and_header_contract():
    header_src = (ROOT / "modules/dashboard/DashboardHeader.qml").read_text(encoding="utf-8")
    for removed_id in (
        "dashboardSetDefaultTab",
        "dashboardCreateCustomTab",
        "dashboardDeleteCustomTab",
        "dashboardRenameCustomTab",
        "dashboardCustomTabActions",
    ):
        if removed_id in header_src:
            raise AssertionError(f"DashboardHeader.qml must remove redundant {removed_id}")
    if "dashboardTabReorderHandle" not in header_src:
        raise AssertionError("DashboardHeader.qml must keep dashboardTabReorderHandle")
    if "enabled: root.pageCount > 0" not in header_src:
        raise AssertionError("DashboardHeader.qml must allow Edit Dashboard Layout from any tab")
    if 'enabled: root.pageIds[root.currentPage] === "dashboard"' in header_src:
        raise AssertionError("DashboardHeader.qml still restricts Edit button to dashboard/custom tabs")
    if "border.width:pageButton.activeFocus" in header_src:
        raise AssertionError("DashboardHeader.qml must not draw focus border around tab icon buttons")
    if "focusPolicy:Qt.StrongFocus" in header_src or "focusPolicy: Qt.StrongFocus" in header_src:
        raise AssertionError("DashboardHeader.qml tab icons must use Qt.TabFocus to prevent click focus borders")
    if "Qt.MouseFocusReason" not in header_src:
        raise AssertionError("DashboardHeader.qml must pass Qt.MouseFocusReason when retaining key focus")

    toolbar_src = (ROOT / "modules/dashboard/DashboardEditToolbar.qml").read_text(encoding="utf-8")
    for required_token in (
        "dashboardToolbarActionDefaultTab",
        "dashboardToolbarActionTabIcon",
        "dashboardLeftTabIconPicker",
        "dashboardBottomTabIconPicker",
        "dashboardToolbarTabIconInput",
        "dashboardToolbarTabIconReset",
        "dashboardToolbarTabIconPreset_",
        "dashboardLeftPageIconButton_",
        "dashboardToolbarIconTab_",
        "dashboardLeftPagePill_",
        "dashboardBottomPageCard_",
        "tabIconController.openFor",
    ):
        if required_token not in toolbar_src:
            raise AssertionError(f"DashboardEditToolbar.qml missing {required_token}")
    print("PASS [DashboardEditToolbarHeaderContract]")


if __name__ == "__main__":
    test_dashboard_edit_toolbar_and_header_contract()
    test_presets_and_calendar_and_yielding_js()
    test_quickshell_silent_runtime()
    print("ALL_BOOST_TESTS_PASS")
