#!/usr/bin/env node
// Saved history must not become the Edit Event calendar selection after a drag.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=process.env.ALIS_PLANNER_SOURCE_ROOT || path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const policy=vm.runInNewContext(fs.readFileSync(path.join(root,
 'modules/sidebarRight/events/EventDateSelection.js'),'utf8')+';({key,rebaseDraggedEvent,editorSlots:typeof editorSlots==="function"?editorSlots:null})',
 {Date,Array,Number,String,JSON,Object,Math});
const slot=day=>({startDate:new Date(2032,9,day,9).toISOString(),
 endDate:new Date(2032,9,day,10).toISOString(),owner:{keep:day}});
const saved=[5,7,12,14,19,21].map(slot);
const before=slot(19),moved=slot(20);
const event={id:41,recurrence:'weekly',occurrences:saved.slice(),
 repeatTemplate:saved.slice(0,2),repeatCycleStart:4,owner:{keep:1}};
event.occurrences[4]={...saved[4],...moved,plannerSeriesStartDate:before.startDate};
const baseline=['title','draft',new Date(before.startDate).getTime(),'09:00','10:00',
 false,'general','normal',15,'weekly',[19,21].map(d=>policy.key(new Date(2032,9,d)))];
const draft={date:new Date(before.startDate),keys:baseline[10],anchor:baseline[10][0],time:'09:00',endTime:'10:00'};
const original=JSON.stringify(event);
const result=policy.rebaseDraggedEvent(draft,baseline,before.startDate,moved.startDate,moved.endDate,event);
assert.deepEqual(Array.from(result.keys),[20,21].map(d=>policy.key(new Date(2032,9,d))),
 'drag must highlight only its own two-day cycle, never saved historical weeks');
assert.equal(JSON.stringify(event),original,'calendar observation must not migrate or rewrite data');
assert.deepEqual(Array.from(policy.editorSlots(event,4).map(s=>s.startDate)),[moved.startDate,saved[5].startDate]);
assert.deepEqual(Array.from(policy.editorSlots(event,0).map(s=>s.startDate)),saved.slice(0,2).map(s=>s.startDate));
assert.deepEqual(Array.from(policy.editorSlots(event).map(s=>s.startDate)),[moved.startDate,saved[5].startDate]);
assert.equal(policy.editorSlots({...event,occurrences:Object.assign({length:6},event.occurrences)},4).length,2,
 'Qt sequence view must retain its indexed group');
assert.equal(policy.editorSlots({id:1,...slot(19)}).length,1);
assert.equal(policy.editorSlots({id:1,occurrences:saved}).length,6,'legacy explicit dates are not guessed away');
assert.equal(policy.editorSlots({...event,recurrence:'none',selectedTemplate:saved.slice(-2)}).length,2);
const manual=policy.rebaseDraggedEvent({...draft,keys:[baseline[10][0]]},baseline,before.startDate,moved.startDate,moved.endDate,event);
assert.equal(manual.dateFollowed,false,'manual draft date selection must remain untouched');
assert.equal(manual.keys.length,1);
assert.equal(JSON.stringify(event),original);
console.log('PLANNER_EDITOR_CYCLE_PASS: history/current/legacy/Qt sequence/manual draft, no writes');
