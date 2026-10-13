#!/usr/bin/env node
// Selection keys must target individual canonical Agenda occurrences.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
const read=p=>fs.readFileSync(new URL("../"+p,import.meta.url),"utf8");
const selection=vm.runInNewContext(read("modules/dashboard/PlannerSelection.js")
    +";({canSelect,key,ordered,choose})");
const gesture=vm.runInNewContext(read("modules/dashboard/PlannerGesture.js")
    +";({rangeForSelection,rangeForGesture})");
const make=(id,day,hour,extra={})=>{
    const start=new Date(2026,9,day,hour);
    return {event:{id,recurrence:"none",allDay:false},
        source:"local",occurrenceIndex:0,virtual:false,
        startDate:start,endDate:new Date(start.getTime()+3600000),...extra};
};
const a=make(1,12,9),b=make(2,12,10),c=make(3,13,8);
const allDay=make(4,13,0,{event:{id:4,allDay:true}});
const external=make(5,13,11,{source:"external"});
const recurring=make(6,13,12,{event:{id:6,recurrence:"weekly"}});
const virtual=make(7,13,13,{virtual:true});
const rows=selection.ordered([{timed:[b,a],allDay:[]},
    {timed:[c,external,recurring,virtual],allDay:[allDay,allDay]}]);
assert.deepEqual(Array.from(rows.map(selection.key)),
    ["1:0","2:0","4:0","3:0"]);
const ctrl=selection.choose(rows,[],"",a,true,false);
assert.deepEqual(Array.from(ctrl.keys),["1:0"]);
const add=selection.choose(rows,ctrl.keys,ctrl.anchor,c,true,false);
assert.deepEqual(Array.from(add.keys),["1:0","3:0"]);
const toggle=selection.choose(rows,add.keys,add.anchor,c,true,false);
assert.deepEqual(Array.from(toggle.keys),["1:0"]);
const range=selection.choose(rows,add.keys,ctrl.anchor,c,false,true);
assert.deepEqual(Array.from(range.keys),["1:0","2:0","4:0","3:0"]);
const merged=selection.choose(rows,["1:0"],ctrl.anchor,c,true,true);
assert.deepEqual(Array.from(merged.keys),["1:0","2:0","4:0","3:0"]);
for(const disabled of [external,recurring,virtual]) {
 assert.equal(selection.canSelect(disabled),false);
 assert.equal(selection.choose(rows,[],ctrl.anchor,disabled,true,false),null);
}
const timed=gesture.rangeForSelection(a,"move",100,52,100,52);
assert.equal(new Date(timed.startIso).getDate(),13);
assert.equal(new Date(timed.startIso).getHours(),10);
const resized=gesture.rangeForSelection(b,"bottom",0,13,100,52);
assert.equal(new Date(resized.endIso).getMinutes(),15);
const dayMove=gesture.rangeForSelection(allDay,"move",200,0,100,52);
assert.equal(new Date(dayMove.startIso).getDate(),15);
assert.equal(gesture.rangeForSelection(allDay,"top",0,30,100,52),null);
assert.equal(gesture.rangeForSelection(recurring,"move",100,0,100,52),null);
console.log("WEEKLY_PLANNER_SELECTION_PASS: Ctrl toggle, Shift range, all-day, guards, move/resize");
