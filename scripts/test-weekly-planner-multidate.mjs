#!/usr/bin/env node
// Multi-date Planner contract: pure civil-day policy + public integration guards.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");
const policy=read("modules/sidebarRight/events/EventDateSelection.js");
const {key,localDate,choose,range,ranges}=vm.runInNewContext(
  policy+";({key,localDate,choose,range,ranges})",{});
const R=vm.runInNewContext(
  read("services/EventRepeatPolicy.js")+";({allowed,templateAllowed,nextCycle})",{});
const date=(y,m,d)=>new Date(y,m-1,d,12);
const keys=result=>JSON.stringify(result.keys);
const old="2026-10-13";
let state=choose([], "",old,date(2026,10,13),false,false);
assert.equal(keys(state),JSON.stringify([old]));
state=choose(state.keys,state.anchor,state.primary,date(2026,10,17),true,false);
assert.equal(keys(state),JSON.stringify(["2026-10-13","2026-10-17"]),
  "Ctrl+Click must add a noncontiguous day");
state=choose(state.keys,state.anchor,state.primary,date(2026,10,19),true,false);
assert.equal(keys(state),JSON.stringify(["2026-10-13","2026-10-17","2026-10-19"]));
state=choose(state.keys,state.anchor,state.primary,date(2026,10,17),true,false);
assert.equal(keys(state),JSON.stringify(["2026-10-13","2026-10-19"]),
  "Ctrl+Click selected day must remove it");
state=choose(state.keys,state.anchor,state.primary,date(2026,10,22),false,true);
assert.equal(keys(state),JSON.stringify(["2026-10-19","2026-10-20","2026-10-21","2026-10-22"]),
  "Shift+Click must select inclusive contiguous range from anchor");
state=choose(state.keys,state.anchor,state.primary,date(2026,10,24),true,true);
assert.equal(keys(state),JSON.stringify(["2026-10-19","2026-10-20","2026-10-21","2026-10-22","2026-10-23","2026-10-24"]),
  "Ctrl+Shift must add range without losing prior dates");
state=choose(state.keys,state.anchor,state.primary,date(2026,11,3),false,false);
assert.equal(keys(state),JSON.stringify(["2026-11-03"]),
  "Plain click must replace selection");
state=choose(state.keys,state.anchor,state.primary,date(2026,11,3),true,false);
assert.equal(keys(state),JSON.stringify(["2026-11-03"]),
  "Ctrl click cannot leave the event with zero days");
state=choose(state.keys,state.anchor,state.primary,date(2026,10,30),false,false);
state=choose(state.keys,state.anchor,state.primary,date(2026,11,2),false,true);
assert.equal(keys(state),JSON.stringify(["2026-10-30","2026-10-31","2026-11-01","2026-11-02"]),
  "Shift range must survive navigating between months");
assert.equal(range("2026-01-01","2028-12-01"),null,
  "Huge range must be rejected instead of silently truncated");
assert.equal(localDate("2026-02-30"),null,"Invalid civil date must be rejected");
assert.equal(key(date(2028,2,29)),"2028-02-29","Leap day must survive");
assert.equal(ranges(["2026-10-10","2026-10-10"],"09:00","10:00",false),null,
  "Duplicate calendar days must not generate multiple slots");
const overnight=ranges(["2026-10-10","2026-10-12"],"23:30","01:15",false);
assert.equal(overnight.length,2);
assert.equal(new Date(overnight[0].endDate).getTime()
  - new Date(overnight[0].startDate).getTime(),105*60000,
  "Overnight times must end the next civil day");
process.env.TZ="America/New_York";
const dst=ranges(["2026-03-07","2026-03-08"],"00:00","00:00",true);
assert.equal(dst.length,2);
assert.equal((new Date(dst[1].endDate)-new Date(dst[1].startDate))/3600000,23,
  "Spring-forward all-day duration must follow local DST, not fixed 24h");
const fall=ranges(["2026-10-31","2026-11-01"],"00:00","00:00",true);
assert.equal((new Date(fall[1].endDate)-new Date(fall[1].startDate))/3600000,25,
  "Fall-back duration must be 25 hours");
const dialog=read("modules/sidebarRight/events/EventsDialog.qml");
const calendar=read("modules/common/widgets/ObsidianMonthCalendar.qml");
const service=read("services/Events.qml");
const occurrences=read("services/EventOccurrences.js");
assert.match(calendar,/signal dayActivated\(var date, int modifiers\)/);
assert.match(calendar,/root\.dayActivated\(dayCell\.modelData\.date,mouse\.modifiers\)/);
assert.match(dialog,/!root\.canSelectRepeat\(root\.recurrence\)/);
assert.match(dialog,/multi && !RepeatPolicy\.allowed\(chosen\.keys,root\.recurrence\)/);
assert.doesNotMatch(dialog.split("onRecurrenceChanged:",2)[1].split("Connections {",1)[0],
  /resetPlannerDateSelection/, "Repeat must never discard checked dates");
assert.equal((dialog.match(/enabled: root\.canSelectRepeat\(/g)||[]).length,4,
  "four recurring options must reactively disable");
assert.match(dialog,/onSelected: \(newValue\) => root\.setRepeatOption\(newValue\)/);
assert.match(dialog,/if \(!root\.canSelectRepeat\(value\)\) return/);
const selector=read("modules/common/widgets/ConfigSelectionArray.qml");
assert.match(selector,/enabled: modelData\?\.enabled !== false/);
assert.match(selector,/\|\| !paletteButton\.enabled/);
assert.match(selector,/if \(paletteButton\.enabled\) root\.selected\(modelData\.value\)/);
assert.match(dialog,/const multi= root\.plannerPresentation && !root\.isEditing/);
assert.match(dialog,/selectedDays\.length>1 && root\.recurrence!=="none"/);
assert.match(dialog,/DateSelection\.ranges\(selectedDays/);
assert.match(dialog,/root\.plannerSelectedDateKeys : \[\]\]/);
assert.match(service,/RepeatPolicy\.templateAllowed\(explicitSlots,recurrence \|\| "none"\)/);
assert.match(service,/event\.repeatTemplate=explicitSlots\.map/);
assert.match(service,/RepeatPolicy\.nextCycle\(event\.repeatTemplate/);
assert.match(service,/const groupIndex = bulk \? -1/);
assert.match(service,/if \(bulk\) event=Occurrences\.store\(event,explicitSlots\)/);
assert.match(service,/root\.eventAdded\(event\)[\s\S]*root\.saveToFile\(\)/);
assert.match(occurrences,/occurrences:ordered/);
assert.match(occurrences,/startDate:first\.startDate,dateTime:first\.startDate/);
assert.equal((dialog.match(/onDayActivated:/g)||[]).length,1,
  "Do not attach duplicate day-click handlers or extra buttons");
const cases=[
 {days:["2026-10-13"],expected:["none","daily","weekly","monthly","yearly"]},
 {days:["2026-10-13","2026-10-15"],expected:["none","weekly","monthly","yearly"]},
 {days:["2026-10-13","2026-10-20"],expected:["none","monthly","yearly"]},
 {days:["2026-10-30","2026-11-03"],expected:["none","yearly"]},
 {days:["2026-12-29","2027-01-03"],expected:["none","weekly"]},
 {days:["2026-12-15","2027-01-16"],expected:["none"]}
];
for(const example of cases) {
 const allowed=["none","daily","weekly","monthly","yearly"]
   .filter(mode=>R.allowed(example.days,mode));
 assert.deepEqual(allowed,example.expected,
   "incompatible repeat modes for "+JSON.stringify(example.days));
}
function slot(y,m,d,h=9) {
 const start=new Date(y,m-1,d,h,0,0),end=new Date(y,m-1,d,h+1,0,0);
 return {startDate:start.toISOString(),endDate:end.toISOString()};
}
function groupDates(group) {return group.map(s=>new Date(s.startDate).getDate());}
const weekly=R.nextCycle([slot(2026,10,13),slot(2026,10,15)],
 "weekly",new Date(2026,9,15,11));
assert.deepEqual(groupDates(weekly),[20,22],"weekly group did not repeat every selected weekday");
const monthly=R.nextCycle([slot(2026,1,30),slot(2026,1,31)],
 "monthly",new Date(2026,1,1));
assert.deepEqual(groupDates(monthly),[30,31],
 "30/31 January must skip February instead of overflowing");
assert.equal(new Date(monthly[0].startDate).getMonth(),2);
const leap=R.nextCycle([slot(2028,2,28),slot(2028,2,29)],
 "yearly",new Date(2028,2,1));
assert.deepEqual(groupDates(leap),[28],
 "yearly Feb 29 must skip non-leap years, not roll into March");
assert.equal(new Date(leap[0].startDate).getFullYear(),2029);
assert.equal(R.templateAllowed([slot(2026,10,13),slot(2026,10,20)],"weekly"),false);
assert.equal(R.templateAllowed([slot(2026,10,13),slot(2026,10,20)],"monthly"),true);
assert.match(read("modules/dashboard/WeeklyPlannerPolicy.js"),/date!==null/,
 "week projection must omit nonexistent calendar dates");
// Exercise the actual service's due-event implementation, not a copy.
const E=vm.runInNewContext(read("services/EventOccurrences.js")+";({entries,store})",{});
const checkDueSource=service.split("    function checkDueEvents() {",2)[1]
  ?.split("    function createNextRecurrence(event, afterTime) {",1)[0];
assert.ok(checkDueSource,"Events.checkDueEvents implementation missing");
const due=new Function("root","Occurrences","RepeatPolicy",
  "return function checkDueEvents() {"+checkDueSource);
const today=new Date(),monday=new Date(today.getFullYear(),today.getMonth(),today.getDate(),9);
monday.setDate(monday.getDate()-(monday.getDay()+6)%7-14);
const past=[0,2,3].map(offset=>{
 const start=new Date(monday);start.setDate(start.getDate()+offset);
 const end=new Date(start);end.setHours(end.getHours()+1);
 return {startDate:start.toISOString(),endDate:end.toISOString()};
});
const fixture={id:411,title:"Repeat cycle",recurrence:"weekly",allDay:false,
  reminderMinutes:0,todoLink:{key:"agenda-kept"},repeatTemplate:past,
  occurrences:past.map(slot=>({...slot,notified:false,reminderNotified:false}))};
let writes=0,triggers=0;
const owner={ready:true,list:[fixture],saveToFile(){writes++},
 eventTriggered(){triggers++},reminderTriggered(){},
 createNextRecurrence(){throw new Error("Legacy single-date path invoked");}};
const processDue=due(owner,E,R);
processDue();
assert.equal(owner.list.length,1,"recurrence must not create extra IDs");
assert.equal(owner.list[0].id,411);
assert.equal(owner.list[0].todoLink.key,"agenda-kept");
assert.equal(writes,1,"multi-day recurrence must be one durable write");
assert.equal(triggers,3,"all selected days must fire once");
assert.equal(owner.list[0].occurrences.length,6,
  "next complete weekly group not generated");
assert.ok(owner.list[0].occurrences.slice(3).every(slot=>new Date(slot.startDate)>today));
processDue();
assert.equal(owner.list[0].occurrences.length,6,"second poll generated duplicate cycle");
assert.equal(writes,1,"unchanged due state must not rewrite the store");
console.log("WEEKLY_PLANNER_MULTIDATE_PASS: modifier choice, cycle eligibility, recurring groups, DST and identity");
