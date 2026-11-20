#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const policyPath = fileURLToPath(
    new URL("../modules/dashboard/YearlyPlannerPolicy.js", import.meta.url)
);

if (!process.env.YEARLY_PLANNER_ZONE_CASE) {
    for (const zone of ["UTC", "Asia/Ho_Chi_Minh", "America/New_York", "Europe/Berlin"]) {
        const res = spawnSync(process.execPath, [fileURLToPath(import.meta.url)], {
            env: { ...process.env, TZ: zone, YEARLY_PLANNER_ZONE_CASE: "1" },
            encoding: "utf8",
        });
        process.stdout.write(res.stdout);
        process.stderr.write(res.stderr);
        assert.equal(res.status, 0, `Timezone ${zone} failed`);
    }
    process.exit(0);
}

const p = vm.createContext({});
vm.runInContext(fs.readFileSync(policyPath, "utf8"), p);

// 1. Calendar matrix (leap & non-leap) + Rolling 12
const leapMonths = p.buildMonthMatrix(new Date(2024, 5, 15), "calendar", "2024-02-29");
assert.equal(leapMonths.length, 12);
assert.equal(leapMonths[1].daysInMonth, 29);
assert.equal(leapMonths[1].days[28].isToday, true);
assert.equal(leapMonths[0].days[0].isPast, true);
assert.equal(leapMonths[2].days[0].isPast, false);

const nonLeapMonths = p.buildMonthMatrix(new Date(2026, 0, 10), "calendar", "2026-06-15");
assert.equal(nonLeapMonths[1].daysInMonth, 28);

const rolling = p.buildMonthMatrix(new Date(2026, 7, 15), "rolling", "2026-08-20");
assert.equal(rolling[0].key, "2026-08");
assert.equal(rolling[4].key, "2026-12");
assert.equal(rolling[5].key, "2027-01");
assert.equal(rolling[11].key, "2027-07");
assert.ok(rolling[5].label.includes("Jan 27"), "Year transition label should show Jan 27");

// 2. Event normalization (exclusive midnight allDay vs legacy timed vs invalid)
const localMidnight = (y, m, d) => new Date(y, m - 1, d, 0, 0, 0, 0).toISOString();
const events = [
    {
        id: 1,
        title: "Winter Break Past",
        startDate: localMidnight(2026, 1, 10),
        endDate: localMidnight(2026, 1, 13),
        allDay: true,
        plannerKind: "trip",
        place: "Da Lat",
        checklist: [{ text: "Coat", done: true }],
    },
    {
        id: 2,
        title: "Cross-Month Expedition",
        startDate: localMidnight(2026, 1, 25),
        endDate: localMidnight(2026, 3, 4), // Jan 25 .. Mar 3 inclusive (7d + 28d + 3d = 38d)
        allDay: true,
        plannerKind: "trip",
        place: "Kyoto",
        checklist: [{ text: "JR Pass", done: true }, { text: "SIM", done: false }],
    },
    {
        id: 3,
        title: "Design Sync",
        startDate: new Date(2026, 5, 10, 9, 0, 0).toISOString(),
        endDate: new Date(2026, 5, 10, 11, 30, 0).toISOString(),
        allDay: false,
    },
    {
        id: 4,
        title: "Launch Day",
        startDate: localMidnight(2026, 8, 20),
        endDate: localMidnight(2026, 8, 21),
        allDay: true,
        plannerKind: "milestone",
        description: "v2 rollout",
    },
    {
        id: 5,
        title: "Invalid",
        startDate: "not-a-date",
        endDate: "invalid",
    },
];

const snapshotBefore = JSON.stringify(events);
const board = p.projectYearBoard(events, new Date(2026, 4, 1), "calendar", "2026-05-01", "");
assert.equal(JSON.stringify(events), snapshotBefore, "projectYearBoard must not mutate inputs");
assert.equal(board.spans.length, 4, "Invalid date entry should be skipped cleanly");

// Verify Cross-Month Expedition split & longest segment showLabel
const janSegs = board.months[0].segments.filter((s) => s.eventId === 2);
const febSegs = board.months[1].segments.filter((s) => s.eventId === 2);
const marSegs = board.months[2].segments.filter((s) => s.eventId === 2);
assert.equal(janSegs.length, 1);
assert.equal(febSegs.length, 1);
assert.equal(marSegs.length, 1);
assert.equal(janSegs[0].wrapLeft, false);
assert.equal(janSegs[0].wrapRight, true);
assert.equal(janSegs[0].showLabel, false);
assert.equal(febSegs[0].wrapLeft, true);
assert.equal(febSegs[0].wrapRight, true);
assert.equal(febSegs[0].dayLength, 28);
assert.equal(febSegs[0].showLabel, true, "Longest Feb segment must carry bar label");
assert.equal(marSegs[0].wrapLeft, true);
assert.equal(marSegs[0].wrapRight, false);
assert.equal(marSegs[0].endDay, 3);
assert.equal(marSegs[0].showLabel, false);

// Verify swimlane packing in overlapping month
const overlapping = p.projectYearBoard(
    [
        { id: 10, title: "A", startDate: localMidnight(2026, 6, 5), endDate: localMidnight(2026, 6, 12), allDay: true },
        { id: 11, title: "B", startDate: localMidnight(2026, 6, 10), endDate: localMidnight(2026, 6, 16), allDay: true },
        { id: 12, title: "C", startDate: localMidnight(2026, 6, 13), endDate: localMidnight(2026, 6, 18), allDay: true },
    ],
    new Date(2026, 5, 1),
    "calendar",
    "2026-05-01",
    ""
);
const juneSegs = overlapping.months[5].segments;
assert.equal(overlapping.months[5].laneCount, 2);
assert.equal(juneSegs.find((s) => s.eventId === 10).lane, 0);
assert.equal(juneSegs.find((s) => s.eventId === 11).lane, 1);
assert.equal(juneSegs.find((s) => s.eventId === 12).lane, 0, "C starts after A ends -> reuses lane 0");

// Verify summary strip metrics
assert.equal(board.summary.planCount, 4);
assert.equal(board.summary.tripCount, 2);
assert.equal(board.summary.daysAway, 3 + 38);
assert.equal(board.summary.nextPlan.id, 3);
assert.equal(board.summary.upNextPlan.id, 4);
assert.equal(board.summary.lastPlan.id, 2);

// Verify search matches title, place, notes, and checklist text
assert.equal(p.projectYearBoard(events, new Date(2026, 4, 1), "calendar", "2026-05-01", "kyoto").spans.length, 1);
assert.equal(p.projectYearBoard(events, new Date(2026, 4, 1), "calendar", "2026-05-01", "jr pass").spans.length, 1);
assert.equal(p.projectYearBoard(events, new Date(2026, 4, 1), "calendar", "2026-05-01", "rollout").spans.length, 1);

// Verify shift & resize clamping across leap day
const shifted = p.shiftSpanRange("2024-02-28", "2024-03-01", 1);
assert.deepEqual(JSON.parse(JSON.stringify(shifted)), { startIso: "2024-02-29", endIso: "2024-03-02" });
assert.deepEqual(
    JSON.parse(JSON.stringify(p.resizeSpanRange("2026-06-10", "2026-06-15", "start", "2026-06-20"))),
    { startIso: "2026-06-15", endIso: "2026-06-15" }
);
assert.deepEqual(
    JSON.parse(JSON.stringify(p.resizeSpanRange("2026-06-10", "2026-06-15", "end", "2026-06-05"))),
    { startIso: "2026-06-10", endIso: "2026-06-10" }
);

console.log(`PASS YearlyPlannerPolicy: ${process.env.TZ}`);
