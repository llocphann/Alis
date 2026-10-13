#!/usr/bin/env node
// Regression: grouped Agenda slots must produce individual Weekly Planner Calendar dots.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const read = path => fs.readFileSync(new URL("../" + path, import.meta.url), "utf8");
const policy = vm.runInNewContext(read("services/EventOccurrences.js") +
    ";({occurrencesForDay,intersectsDay})", {});
const service = read("services/Events.qml");
const accessor = service.match(/    function getAllEventOccurrencesForDate\(date\) \{[\s\S]*?\n    \}/)?.[0];
assert.ok(accessor, "Missing per-occurrence calendar accessor");
const store = {list: []};
const getForDate = new Function("root", "Occurrences",
    "return " + accessor)(store, policy);

function slot(day, hour, minute = 0, duration = 60) {
    const start = new Date(2026, 9, day, hour, minute);
    return {startDate:start.toISOString(),
        endDate:new Date(start.getTime() + duration * 60000).toISOString()};
}
const day14 = new Date(2026, 9, 14, 12);
const day15 = new Date(2026, 9, 15, 12);
const day16 = new Date(2026, 9, 16, 12);
const grouped = {id:1, title:"dsa", recurrence:"none",
    occurrences:[8,9,10,12,14].map(hour => slot(14,hour)).concat([slot(15,8)])};
const single = {id:2,title:"separate",...slot(14,16)};
const overnight = {id:3,title:"overnight",...slot(13,23,30,60)};
const notified = {id:4,title:"finished",
    occurrences:[{...slot(14,18),notified:true}]};
store.list = [grouped,single,overnight,notified];
assert.equal(store.list.filter(e => policy.intersectsDay(e,day14,true)).length,4,
    "fixture must expose the original canonical-ID undercount");
assert.equal(getForDate(day14).length,8,
    "five merged slots, one independent, overnight, notified history");
assert.equal(getForDate(day14).filter(e => e.id===1).length,5,
    "same-ID Agenda slots lost individual indicators");
assert.equal(getForDate(day15).length,1, "next-day slot counted incorrectly");
assert.equal(getForDate(day16).length,0, "calendar counted absent events");
assert.equal(policy.occurrencesForDay(notified,day14,false).length,0,
    "notified visibility of existing non-history calendars changed");
assert.equal(policy.occurrencesForDay(notified,day14,true).length,1,
    "completed Agenda must retain its Calendar dot");
grouped.occurrences[0]=slot(15,8,30);
assert.equal(getForDate(day14).length,7, "rescheduled slot remained on original day");
assert.equal(getForDate(day15).length,2, "rescheduled slot not added to new day");
grouped.occurrences.pop();
assert.equal(getForDate(day15).length,1, "removed slot remains counted");
const layout = vm.runInNewContext(read("modules/common/widgets/CalendarEventDotLayout.js") +
    ";({layoutDots})", {});
const colors = Array.from({length:15}, () => "#65b8c4");
const eight = layout.layoutDots(8,3,colors,"#65b8c4");
assert.deepEqual(JSON.parse(JSON.stringify(eight.edges.map(edge=>edge.length))),
    [3,3,2,0], "8 dots must wrap Bottom -> Right -> Top");
assert.equal(layout.layoutDots(12,3,colors,"#65b8c4").shown,12);
assert.equal(layout.layoutDots(13,3,colors,"#65b8c4").shown,12);
assert.equal(layout.layoutDots(30,3,colors,"#65b8c4").shown,12);
assert.equal("overflow" in layout.layoutDots(30,3,colors,"#65b8c4"),false);
console.log("CALENDAR_AGENDA_DOTS_PASS: grouped slots, midnight, notified, move/remove, 12-dot perimeter");
