#!/usr/bin/env node
// Regression for Qt QML's missing Array.prototype.flatMap on Events.list and
// Dashboard Agenda startup before the async Events store has loaded.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const read=(name)=>fs.readFileSync(new URL("../"+name,import.meta.url),"utf8");
const events=read("services/Events.qml");
const agenda=read("modules/dashboard/DashAgenda.qml");
const policy=vm.runInNewContext(read("services/EventOccurrences.js")+";({entries})",{});
function body(source,start,end,label) {
    const a=source.indexOf(start),b=source.indexOf(end,a+start.length);
    assert.ok(a>=0 && b>a,label+" body unavailable");
    return source.slice(a,b);
}
const method=body(events,"    function getUpcomingEvents(days) {",
    "    function markAsNotified(id) {","Events.getUpcomingEvents");
assert.doesNotMatch(method,/\.flatMap\s*\(/,"unsupported Array.flatMap reintroduced");
const offset=hours=>new Date(Date.now()+hours*3600000).toISOString();
const group={id:101,title:"Two days",allDay:false,occurrences:[
    {startDate:offset(4),endDate:offset(5),notified:false},
    {startDate:offset(2),endDate:offset(3),notified:false},
    {startDate:offset(6),endDate:offset(7),notified:true},
    {startDate:offset(250),endDate:offset(251),notified:false}
]};
const overlappingDay={id:102,title:"All day",allDay:true,
    startDate:offset(-2),endDate:offset(20),notified:true};
const pastTimed={id:103,title:"Past",allDay:false,
    startDate:offset(-4),endDate:offset(-3),notified:false};
const list=[group,overlappingDay,pastTimed];
// Simulate QML-provided array-like value without flatMap, but with iterator.
list.flatMap=undefined;
const root={list};
const upcoming=new Function("root","Occurrences","return "+method)(root,policy);
const result=upcoming(7);
assert.ok(Array.isArray(result));
assert.equal(result.length,3,"expected two future slots and one overlapping all-day");
assert.deepEqual(result.map(e=>e.id),[102,101,101],"chronological sort changed");
assert.deepEqual(result.filter(e=>e.id===101).map(e=>e._canonicalEvent._editOccurrenceIndex),[1,0],
    "individual occurrences no longer retain the selected index");
assert.ok(result.every(e=>e.startDate===e.dateTime && e._canonicalEvent.id===e.id));
assert.ok(!result.some(e=>e.id===103),"past timed events must be excluded");
assert.ok(!result.some(e=>e.id===101 && e._canonicalEvent._editOccurrenceIndex===2),
    "previously notified timed occurrence must be excluded");
assert.deepEqual(upcoming(0).map(e=>e.id),[102,101,101],
    "default lookahead changed");

const agBuild=body(agenda,"    function _buildEntries() {",
    "    Repeater {","DashAgenda._buildEntries");
const card={lookaheadDays:14,maxRows:8,overflowCount:0,
    _dayLabel(value){return new Date(value).toISOString().slice(0,10);}};
const sync={getEventsForDate(){return [];}};
const build=new Function("card","Events","CalendarSync",
    "return "+agBuild)(card,{getUpcomingEvents:upcoming},sync);
const rows=build();
assert.equal(rows.filter(e=>e.type==="event").length,3);
assert.equal(card.overflowCount,0);
const empty=new Function("card","Events","CalendarSync",
    "return "+agBuild)(card,{getUpcomingEvents(){return [];}},sync);
assert.deepEqual(empty(),[],"Dashboard empty state no longer reaches zero rows");
assert.match(agenda,/function onReadyChanged\(\) \{ card\._localTrigger\+\+ \}/,
    "DashAgenda does not rebuild when Events.ready changes");
assert.match(agenda,/if \(!Events\.ready\) return \[\]/,
    "DashAgenda does not guard async service initialization");
assert.match(agenda,/model: card\.entries \?\? \[\]/,
    "Agenda Repeater model must never become undefined");
assert.match(agenda,/card\.entries\?\.length \?\? 0/,
    "Agenda empty state must safely accept an uninitialized model");
console.log("AGENDA_UPCOMING_COMPAT_PASS: QML array compatibility, occurrence order, startup and empty state");
