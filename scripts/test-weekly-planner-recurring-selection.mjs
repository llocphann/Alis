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
// Plain click selects all visible occurrences belonging to the same stable
// Event ID, but Ctrl-click on one selected date must remove ONLY that date.
const second={...saved,occurrenceIndex:1,...slot(21)};
const duplicatedProjection={...saved,...slot(19)};
const visible=[saved,second,ordinary,virtual,duplicatedProjection,
  {...second,source:'external'}];
const grouped=Array.from(S.groupKeys(visible,saved));
assert.equal(grouped.length,3,'ID group missed saved/virtual occurrences or double-counted day copies');
assert.ok(grouped.includes(S.key(saved)) && grouped.includes(S.key(second))
  && grouped.includes(S.key(virtual)));
assert.equal(S.groupKeys(visible,ordinary).length,1);
assert.equal(S.groupKeys(visible,{...saved,source:'external'}).length,0);
const toggled=S.choose(visible,grouped,S.key(saved),second,true,false);
assert.equal(toggled.keys.length,2,'Ctrl-click failed to deselect one ID-group occurrence');
assert.ok(!toggled.keys.includes(S.key(second))
  && toggled.keys.includes(S.key(saved))
  && toggled.keys.includes(S.key(virtual)),
  'Ctrl-click deselected siblings rather than the exact instance');
assert.equal(S.choose(visible,toggled.keys,toggled.anchor,second,true,false).keys.length,3,
  'Ctrl-click must reselect just that exact occurrence');
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
// One drag of a *selected ID group* must commit every saved + virtual
// occurrence atomically; virtual exception must not move the whole cadence.
const groupEdits=B.apply(events,[
 {id:41,occurrenceIndex:0,recurring:true,
  startIso:slot(20).startDate,endIso:slot(20).endDate},
 {id:41,occurrenceIndex:1,recurring:true,
  startIso:slot(22).startDate,endIso:slot(22).endDate},
 {id:41,occurrenceIndex:0,recurring:true,
  originalStartIso:slot(26).startDate,
  startIso:slot(27).startDate,endIso:slot(27).endDate}
],O);
assert.ok(groupEdits,'group move rejected saved + projected IDs');
assert.equal(groupEdits.updated.length,1,'one Event ID should emit one atomic update');
assert.equal(groupEdits.list[0].occurrences[0].startDate,slot(20).startDate);
assert.equal(groupEdits.list[0].occurrences[1].startDate,slot(22).startDate);
assert.equal(groupEdits.list[0].plannerOverrides.length,1);
assert.equal(groupEdits.list[0].plannerOverrides[0].originalStartDate,slot(26).startDate);
assert.equal(groupEdits.list[0].plannerOverrides[0].startDate,slot(27).startDate);
assert.equal(groupEdits.list[0].todoLink.key,'keep');
assert.equal(JSON.stringify(events),raw,'atomic group edit mutated original history');
assert.equal(B.apply(events,[
 {id:41,occurrenceIndex:0,recurring:true,
  startIso:slot(20).startDate,endIso:slot(20).endDate},
 {id:41,occurrenceIndex:1,recurring:true,
  startIso:'invalid',endIso:slot(22).endDate}
],O),null,'invalid sibling must roll back every group operation');
for(const operations of [[savedOp,{...normalOp,id:999}],[savedOp,savedOp],
 [{...savedOp,remove:true}], [{...savedOp,recurring:false}],
 [savedOp,{...normalOp,endIso:'invalid'}]])assert.equal(B.apply(events,operations,O),null);
assert.equal(JSON.stringify(events),raw,'failed/mixed group edits must never mutate original data');
console.log('PLANNER_RECURRING_SELECTION_PASS: ID-group selection, Ctrl exact deselection, atomic saved/virtual drag, rollback and series-delete guards');
