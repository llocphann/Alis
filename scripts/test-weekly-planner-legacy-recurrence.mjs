#!/usr/bin/env node
// Legacy saved-Event compatibility: edit ONE persisted repeating occurrence,
// never the recurrence template, notified history, stable ID or user files.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const file = rel => new URL('../' + rel, import.meta.url);
function load(rel) {
  const scope=vm.createContext({Date,Array,Object,Math,Set,Map,Number,String});
  vm.runInContext(fs.readFileSync(file(rel),'utf8'),scope);
  return scope;
}
const S=load('modules/dashboard/PlannerSelection.js');
const G=load('modules/dashboard/PlannerGesture.js');
const P=load('modules/dashboard/WeeklyPlannerPolicy.js');
const O=load('services/EventOccurrences.js');
const baseSlot=(day,hour,notified)=>({
  startDate:`2026-10-${day}T${hour}:00:00Z`,
  endDate:`2026-10-${day}T${String(Number(hour)+1).padStart(2,'0')}:00:00Z`,
  notified,reminderNotified:notified
});
const archived=[baseSlot('13','09',true),baseSlot('15','09',true)];
const active=[baseSlot('20','09',false),baseSlot('22','09',false)];
const event={id:101,title:'Legacy recurring class',recurrence:'weekly',
  description:'Preserve owner metadata',todoLink:{id:55,state:'linked'},
  occurrences:archived.concat(active),repeatTemplate:archived.map(slot=>({
    startDate:slot.startDate,endDate:slot.endDate})),repeatCycleStart:2,
  selectedTemplate:archived.slice(),privateExtra:{preserve:true}
};
const original=JSON.stringify(event);
const rows=P.project([event],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed);
const saved=rows.find(row=>row.occurrenceIndex===2 && !row.virtual);
assert.ok(saved,'saved legacy series instance missing from this week');
assert.equal(S.canSelect(saved),false,'series must not enter batch delete');
assert.equal(S.canReschedule(saved),true,'legacy saved series not movable');
assert.equal(S.canReschedule({...saved,virtual:true}),false);
assert.equal(S.canReschedule({...saved,source:'external'}),false);
assert.equal(S.canReschedule({...saved,event:{...event,repeatTemplate:null}}),false,
  'unanchored old series is intentionally not mutated');
assert.equal(S.canReschedule({...saved,event:{...event,occurrences:null}}),false);
const noSaved={...event,occurrences:undefined,repeatTemplate:undefined,
  startDate:'2026-10-20T09:00:00Z'};
assert.equal(S.canReschedule({...saved,event:noSaved}),false,
  'legacy single-date recurrence without a stable slot is not writable');
const move=G.rangeForGesture(saved,'move',0,13,102,52);
const top=G.rangeForGesture(saved,'top',0,13,102,52);
const bottom=G.rangeForGesture(saved,'bottom',0,13,102,52);
assert.ok(move && top && bottom);
assert.equal(new Date(move.startIso)-new Date(saved.startDate),15*60000);
assert.equal(new Date(top.startIso)-new Date(saved.startDate),15*60000);
assert.equal(new Date(bottom.endIso)-new Date(saved.endDate),15*60000);
assert.equal(G.rangeForGesture({...saved,virtual:true},'move',0,13,102,52),null);
const edited=O.rescheduleSavedRecurring(event,2,top.startIso,top.endIso);
assert.ok(edited,'single saved historical series occurrence rejected');
assert.equal(JSON.stringify(event),original,'editing must be copy-on-write');
assert.equal(edited.id,101);
assert.equal(edited.occurrences[2].startDate,'2026-10-20T09:15:00.000Z');
assert.equal(edited.occurrences[2].endDate,'2026-10-20T10:00:00.000Z');
assert.equal(edited.occurrences[2].plannerSeriesStartDate,active[0].startDate);
assert.equal(edited.occurrences[2].plannerSeriesEndDate,active[0].endDate);
for(const key of ['repeatTemplate','selectedTemplate','repeatCycleStart',
    'todoLink','privateExtra']) {
  assert.equal(JSON.stringify(edited[key]),JSON.stringify(event[key]),
    'series identity/metadata modified: '+key);
}
assert.deepEqual(JSON.parse(JSON.stringify(edited.occurrences.slice(0,2))),
  JSON.parse(JSON.stringify(archived)),'fired history changed');
assert.equal(O.reschedule(event,2,top.startIso,top.endIso),null,
  'old whole-series reschedule path must reject repeats');
assert.equal(O.rescheduleSavedRecurring(edited,2,
  '2026-10-14T09:00:00Z','2026-10-14T10:00:00Z'),null,
  'cannot reorder saved history and break repeatCycleStart');
const persisted=O.store(edited,O.entries(edited));
assert.equal(persisted.occurrences[2].plannerSeriesStartDate,active[0].startDate,
  'saved override original date disappeared during due-handler persist');
const current=P.project([persisted],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed);
assert.equal(current.filter(row=>!row.virtual && row.occurrenceIndex===2).length,1);
assert.ok(current.some(row=>!row.virtual && row.startDate.toISOString()===
  '2026-10-20T09:15:00.000Z'),'edited legacy slot not shown');
const nextWeek=P.project([persisted],[],'2026-10-27T12:00:00Z',1)
  .flatMap(day=>day.timed);
assert.ok(nextWeek.some(row=>row.virtual && row.startDate.toISOString()===
  '2026-10-27T09:00:00.000Z'),'next cycle shifted with edited instance');
assert.ok(!nextWeek.some(row=>row.startDate.toISOString()===
  '2026-10-27T09:15:00.000Z'),'future schedule drifted from series template');
assert.equal(O.rescheduleSavedRecurring(event,2,'invalid','invalid'),null);
assert.equal(O.rescheduleSavedRecurring(event,2,
  '2026-10-20T09:00:00Z','2026-10-20T09:05:00Z'),null);
const legacyOneOff={id:202,title:'Old Agenda',dateTime:'2026-10-20T11:00:00Z'};
const oldOne=P.project([legacyOneOff],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed).find(row=>row.event.id===202);
assert.ok(oldOne && S.canReschedule(oldOne),'pre-occurrence one-off no longer editable');
console.log('WEEKLY_PLANNER_LEGACY_RECURRENCE_PASS: old stored slots, immutable template, history, projection, pure one-off');
