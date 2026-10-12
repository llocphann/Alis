import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const planner = vm.createContext({Date, Math, Number, Array, String});
vm.runInContext(fs.readFileSync(new URL("../modules/dashboard/WeeklyPlannerPolicy.js",import.meta.url),"utf8"),planner);
const calendar = vm.createContext({Date, Math, Number, Array, String, Object});
vm.runInContext(fs.readFileSync(new URL("../modules/sidebarRight/events/EventsWindow.js",import.meta.url),"utf8"),calendar);
const projection=calendar.threeDayEvents;
const at=(n,h=0,m=0)=>new Date(2026,9,12+n,h,m,0,0);
const iso=d=>d.toISOString();
let checks=0;
const eq=(a,b,msg)=>{
    checks++;
    assert.deepEqual(JSON.parse(JSON.stringify(a)),b,msg);
};
const ok=(condition,msg)=>{
    checks++;
    assert.ok(condition,msg);
};
const local=[
    {id:1,title:"In progress",dateTime:iso(at(-1,23)),endDate:iso(at(0,17))},
    {id:2,title:"Late tonight",dateTime:iso(at(0,22,50))},
    {id:3,title:"Tomorrow",dateTime:iso(at(1,11))},
    {id:4,title:"Day two late",dateTime:iso(at(2,23,59))},
    {id:5,title:"Outside",dateTime:iso(at(3,0))},
    {id:6,title:"Daily recurring",dateTime:iso(at(-1,9)),recurrence:"daily",notified:false}
];
const external=[
    {id:"all",startDate:iso(at(0)),endDate:iso(at(3)),allDay:true},
    {id:"outside-external",startDate:iso(at(3)),endDate:iso(at(3,12))}
];
const original=JSON.stringify({local,external});
const rows=projection(local,external,at(0,22,30),planner.project);
eq(rows.length,10,"three-day window includes all overlapping occurrences");
eq(rows.map(e=>e._dayOffset),[0,0,0,0,1,1,1,2,2,2],"exactly three local calendar days and sorted groups");
eq(rows.filter(e=>e._showDayHeader).map(e=>e._dayOffset),[0,1,2],"one group header per populated date");
eq(rows.filter(e=>e.id===6).map(e=>e._dayOffset),[0,1,2],"local daily recurrence displayed without modifying saved events");
eq(rows.filter(e=>e.id==="all").map(e=>e._dayOffset),[0,1,2],"external all-day exclusive end spans three dates");
eq(rows.filter(e=>e.id===1).map(e=>e._dayOffset),[0],"timed event begun yesterday remains visible while in progress");
ok(rows.some(e=>e.id===4),"23:59 on day two remains visible after a late-night current time");
ok(!rows.some(e=>e.id===5||e.id==="outside-external"),"day three is excluded, not a rolling 72h window");
ok(rows.filter(e=>e.id==="all").every(e=>e._source==="external"),"external rows remain read-only");
ok(rows.filter(e=>e.id===6).every(e=>e._canonicalEvent===local[5]),"virtual occurrences edit the original canonical event");
ok(rows.some(e=>e.id===6&&e._virtualOccurrence),"recurring instances are projected and labelled as virtual");
ok(rows.some(e=>e.id===2&&e._canonicalEvent===local[1]),"ordinary local events retain stable identity for edit/remove");
eq(JSON.stringify({local,external}),original,"projection does not mutate canonical data");
eq(projection([],[],at(0),planner.project),[],"empty three-day window");
eq(projection(local,external,"not a date",planner.project),[],"invalid current date is harmless");
ok(!calendar.eventIsPast(at(-1,22),at(0,23),at(0,14)),"ongoing timed event must not be marked past");
ok(calendar.eventIsPast(at(-1,22),at(0,13),at(0,14)),"event becomes past after its end time");
ok(calendar.eventIsPast(at(-1,22),null,at(0,14)),"legacy event with no end falls back to start");
ok(!calendar.eventIsPast(at(2,15),null,at(0,14)),"future event without end remains upcoming");

// This projection is intentionally caller opt-in: other EventsWidget owners
// keep their existing horizon, while Dashboard Agenda remains 14 days.
const eventsWidget=fs.readFileSync(new URL("../modules/sidebarRight/events/EventsWidget.qml",import.meta.url),"utf8");
const calendarContent=fs.readFileSync(new URL("../modules/bar/ClockCalendarContent.qml",import.meta.url),"utf8");
const agenda=fs.readFileSync(new URL("../modules/dashboard/DashAgenda.qml",import.meta.url),"utf8");
ok(eventsWidget.includes("property bool compactCalendarWindow: false"),"shared EventsWidget must opt in");
ok(calendarContent.includes("compactCalendarWindow: true"),"only Calendar popup requests three dates");
ok(eventsWidget.includes("Events.getUpcomingEvents(30)"),"legacy consumers retain original horizon");
ok(agenda.includes("lookaheadDays: 14"),"Dashboard Agenda lookahead unchanged");
ok(eventsWidget.includes("ScrollBar.AlwaysOff : ScrollBar.AsNeeded"),
    "Calendar list hides only scroll chrome while retaining Flickable");
ok(eventsWidget.includes("hideEmbeddedScrollBar: root.compactCalendarWindow"),
    "Calendar inline editor hides only embedded scrollbar chrome");
console.log("CALENDAR_THREE_DAY_PASS",checks);
