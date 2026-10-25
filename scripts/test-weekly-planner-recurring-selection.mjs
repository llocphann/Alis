#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=process.env.ALIS_PLANNER_SOURCE_ROOT || path.dirname(path.dirname(fileURLToPath(import.meta.url)));
function load(p){const ctx=vm.createContext({Date,Array,Number,String,JSON,Object,Math,Set,Map});vm.runInContext(fs.readFileSync(path.join(root,p),'utf8'),ctx);return ctx;}
const S=load('modules/dashboard/PlannerSelection.js'),B=load('services/EventBatchPolicy.js'),O=load('services/EventOccurrences.js');
const slot=day=>({startDate:`2032-10-${day}T09:00:00.000Z`,endDate:`2032-10-${day}T10:00:00.000Z`,owner:{keep:1}});
const a={id:41,recurrence:'weekly',occurrences:[slot(19),slot(21)],todoLink:{key:'keep'}};
const b={id:42,recurrence:'none',...slot(20)};
const saved={source:'local',event:a,occurrenceIndex:0,virtual:false,...slot(19)};
const ordinary={source:'local',event:b,occurrenceIndex:0,virtual:false,...slot(20)};
assert.equal(S.canSelect(saved),true,'Owner regression: recurring cards must support Ctrl/Shift selection');
assert.equal(S.canDelete(saved),false,'selecting an instance does not grant series deletion');
const selected=S.choose([saved,ordinary],[],"",saved,true,false);
const both=S.choose([saved,ordinary],selected.keys,selected.anchor,ordinary,true,false);
assert.equal(both.keys.length,2);
assert.equal(S.choose([saved,ordinary],selected.keys,selected.anchor,ordinary,false,true).keys.length,2);
const virtual={...saved,virtual:true,plannerOriginalStartIso:slot(26).startDate,...slot(26)};
assert.equal(S.canSelect(virtual),true);
assert.notEqual(S.key(saved),S.key(virtual));
assert.equal(S.canSelect({...saved,source:'external'}),false);
const events=[a,b],raw=JSON.stringify(events);
const savedOp={id:41,occurrenceIndex:0,recurring:true,startIso:slot(20).startDate,endIso:slot(20).endDate};
const normalOp={id:42,occurrenceIndex:0,startIso:slot(21).startDate,endIso:slot(21).endDate};
const updated=B.apply(events,[savedOp,normalOp],O);
assert.ok(updated);assert.equal(updated.updated.length,2);assert.equal(updated.removed.length,0);
assert.equal(updated.list[0].occurrences[0].startDate,slot(20).startDate);
assert.deepEqual(JSON.parse(JSON.stringify(updated.list[0].occurrences[1])),a.occurrences[1]);
assert.equal(updated.list[0].occurrences[0].plannerSeriesStartDate,slot(19).startDate);
assert.equal(updated.list[0].todoLink.key,'keep');
const future=B.apply(events,[{...savedOp,originalStartIso:slot(26).startDate,startIso:slot(27).startDate,endIso:slot(27).endDate},normalOp],O);
assert.equal(future.list[0].plannerOverrides.length,1);
assert.equal(future.list[0].occurrences[0].startDate,slot(19).startDate);
for(const operations of [[savedOp,{...normalOp,id:999}],[savedOp,savedOp],
 [{...savedOp,remove:true}], [{...savedOp,recurring:false}],
 [savedOp,{...normalOp,endIso:'invalid'}]])assert.equal(B.apply(events,operations,O),null);
assert.equal(JSON.stringify(events),raw,'failed/mixed group edits must never mutate original data');
console.log('PLANNER_RECURRING_SELECTION_PASS: Ctrl/Shift, saved/virtual/mixed atomic edits, rollback and series deletion guards');
