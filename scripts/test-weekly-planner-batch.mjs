#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
const read = p => fs.readFileSync(new URL("../"+p, import.meta.url),"utf8");
const sandbox = source => vm.runInNewContext(source,{Date,Array,Math,Number,Map,Set});
const occurrence=sandbox(read("services/EventOccurrences.js")+";({entries,store})");
const batch=sandbox(read("services/EventBatchPolicy.js")+";({apply})");
const slot=(d,h)=>{const start=new Date(2026,9,d,h);return {
 startDate:start.toISOString(),endDate:new Date(start.getTime()+3600000).toISOString()
}};
const a={id:11,title:"same ID",recurrence:"none",occurrences:[slot(14,9),slot(14,11)]};
const b={id:12,title:"another",...slot(15,13)};
const repeating={id:13,title:"read-only repeat",recurrence:"weekly",...slot(14,15)};
const initial=[a,b,repeating],before=JSON.stringify(initial);
const change=(id,index,start,end)=>({id,occurrenceIndex:index,startIso:start,endIso:end});
const shift=(id,index,date,hour)=>change(id,index,slot(date,hour).startDate,slot(date,hour).endDate);
const result=batch.apply(initial,[shift(11,0,15,9),shift(12,0,16,13)],occurrence);
assert.ok(result);
assert.equal(result.updated.length,2);
assert.equal(result.removed.length,0);
assert.equal(result.list.length,3);
assert.equal(result.list[0].occurrences.length,2);
assert.equal(result.list[0].occurrences[0].startDate,slot(14,11).startDate);
assert.equal(result.list[0].occurrences[1].startDate,slot(15,9).startDate);
assert.equal(result.list[1].startDate,slot(16,13).startDate);
assert.equal(result.list[2],repeating);
assert.equal(JSON.stringify(initial),before,"batch mutated original events");
const failed=[
 [shift(11,0,14,11)], // collision with untouched slot
 [shift(11,0,15,9),shift(11,0,15,9)], // duplicated selection
 [shift(13,0,15,9)], // repeating
 [shift(99,0,15,9)], // missing
 [change(11,1,slot(14,10).startDate,slot(14,9).endDate)], // invalid duration
 [{id:11,occurrenceIndex:2,remove:true}], // out of range
 [shift(11,0,16,10),shift(11,1,16,10)] // collision within the batch
];
for(const ops of failed) {
 assert.equal(batch.apply(initial,ops,occurrence),null,"failed operation was partially applied");
 assert.equal(JSON.stringify(initial),before,"failed batch mutated events");
}
const removed=batch.apply(initial,[
 {id:11,occurrenceIndex:0,remove:true},
 {id:11,occurrenceIndex:1,remove:true},
 {id:12,occurrenceIndex:0,remove:true}
],occurrence);
assert.ok(removed);
assert.deepEqual(Array.from(removed.removed),[11,12]);
assert.equal(removed.list.length,1);
assert.equal(removed.list[0],repeating);
assert.equal(JSON.stringify(initial),before);
const retained=batch.apply(initial,[{id:11,occurrenceIndex:1,remove:true}],occurrence);
assert.equal(retained.list[0].occurrences.length,1);
assert.equal(retained.list[0].startDate,slot(14,9).startDate);
console.log("WEEKLY_PLANNER_BATCH_PASS: atomic move, resize, delete, grouped ID, no mutation");
