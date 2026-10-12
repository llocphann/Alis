#!/usr/bin/env node
// Multi-date Planner contract: pure civil-day policy + public integration guards.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");
const policy=read("modules/sidebarRight/events/EventDateSelection.js");
const {key,localDate,choose,range,ranges}=vm.runInNewContext(
  policy+";({key,localDate,choose,range,ranges})",{});
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
assert.match(dialog,/root\.plannerRepeatConflict && root\.recurrence!=="none"/);
assert.match(dialog,/chosen\.keys\.length>1 && root\.recurrence!=="none"/);
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
assert.match(service,/supplied\.length>1[\s\S]*\(recurrence \|\| "none"\)!=="none"/);
assert.match(service,/const groupIndex = bulk \? -1/);
assert.match(service,/if \(bulk\) event=Occurrences\.store\(event,explicitSlots\)/);
assert.match(service,/root\.eventAdded\(event\)[\s\S]*root\.saveToFile\(\)/);
assert.match(occurrences,/occurrences:ordered/);
assert.match(occurrences,/startDate:first\.startDate,dateTime:first\.startDate/);
assert.equal((dialog.match(/onDayActivated:/g)||[]).length,1,
  "Do not attach duplicate day-click handlers or extra buttons");
console.log("WEEKLY_PLANNER_MULTIDATE_PASS: ctrl toggle, shift ranges, cross-month, DST, one-ID storage and repeat isolation");
