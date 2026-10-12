#!/usr/bin/env node
// Pure-policy regression; the separate native Niri/Quickshell gate remains open.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
const load = (relative, names) => {
  const file = fileURLToPath(new URL(relative, import.meta.url));
  const context = vm.createContext({Date,Number,String,Object,Array,Math,Map,Set});
  vm.runInContext(fs.readFileSync(file,'utf8'), context,{filename:file});
  return Object.fromEntries(names.map(name=>[name,context[name]]));
};
const E=load('../services/EventOccurrences.js',
  ['nameKey','compatible','entries','append','reschedule','intersectsDay','upcoming']);
const G=load('../modules/dashboard/PlannerGesture.js',['rangeForGesture']);
const P=load('../modules/dashboard/WeeklyPlannerPolicy.js',['project']);
const original={id:9,title:'  Team   Review ',description:'Review',
  startDate:'2026-10-12T09:00:00Z',endDate:'2026-10-12T10:00:00Z',
  category:'meeting',priority:'normal',reminderMinutes:15,recurrence:'none',
  allDay:false,todoLink:{key:'preserve-owner-link'}};
const second={...original,title:'team review',startDate:'2026-10-14T11:00:00Z',
  endDate:'2026-10-14T12:30:00Z'};
assert.equal(E.nameKey(original.title),'team review');
const combined=E.append(original,second);
assert.ok(combined && !combined.duplicate);
assert.equal(combined.event.id,original.id);
assert.equal(combined.event.todoLink.key,original.todoLink.key);
assert.equal(combined.event.occurrences.length,2);
assert.equal(E.append(combined.event,second).duplicate,true);
assert.equal(E.compatible(original,{...second,description:'different'}),false);
assert.equal(E.compatible(original,{...second,recurrence:'daily'}),false);
assert.equal(E.intersectsDay(combined.event,'2026-10-14T12:00:00Z',true),true);
assert.equal(E.intersectsDay(combined.event,'2026-10-13T12:00:00Z',true),false);
assert.equal(E.upcoming(combined.event,'2026-10-13T00:00:00Z','2026-10-17T00:00:00Z').startDate,
 '2026-10-14T11:00:00.000Z');
const shifted=E.reschedule(combined.event,1,'2026-10-15T11:00:00Z','2026-10-15T13:30:00Z');
assert.equal(shifted.occurrences[1].endDate,'2026-10-15T13:30:00.000Z');
assert.equal(E.reschedule(shifted,1,'2026-10-12T11:00:00Z','2026-10-12T08:00:00Z'),null);
assert.equal(JSON.stringify(original.todoLink),JSON.stringify(shifted.todoLink));
const projected=P.project([shifted],[],'2026-10-14T12:00:00Z',1);
const row=projected.flatMap(day=>day.timed).find(row=>row.occurrenceIndex===1);
assert.ok(row && row.event.id===original.id);
assert.equal(projected.flatMap(day=>day.timed).length,1);
const move=G.rangeForGesture(row,'move',102,52,102,52);
assert.equal(new Date(move.startIso)-new Date(row.startDate),25*3600000);
const top=G.rangeForGesture(row,'top',0,13,102,52);
assert.equal(new Date(top.startIso)-new Date(row.startDate),15*60000);
const bottom=G.rangeForGesture(row,'bottom',0,26,102,52);
assert.equal(new Date(bottom.endIso)-new Date(row.endDate),30*60000);
assert.equal(G.rangeForGesture({...row,source:'external'},'move',10,10,102,52),null);
assert.equal(G.rangeForGesture({...row,virtual:true},'move',10,10,102,52),null);
assert.equal(G.rangeForGesture(row,'move',0,0,102,52),null);
assert.equal(G.rangeForGesture(row,'top',0,10000,102,52),null);
const acrossMidnight={...row,startDate:new Date('2026-10-12T23:30:00'),
 endDate:new Date('2026-10-13T00:30:00')};
const moved=G.rangeForGesture(acrossMidnight,'move',102,0,102,52);
assert.equal(new Date(moved.startIso).getDate(),13);
assert.equal(new Date(moved.endIso).getDate(),14);
console.log('PASS canonical multi-date Events, dedup identity, read-only and drag/resize policy');
