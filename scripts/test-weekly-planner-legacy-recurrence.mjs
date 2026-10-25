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
assert.equal(S.canSelect(saved),true,'identified recurring instances remain selectable');
assert.equal(S.canDelete(saved),false,'series must not enter batch delete');
assert.equal(S.canReschedule(saved),true,'legacy saved series not movable');
assert.equal(S.canReschedule({...saved,virtual:true}),false);
assert.equal(S.canReschedule({...saved,source:'external'}),false);
assert.equal(S.canReschedule({...saved,event:{...event,repeatTemplate:null}}),true,
  'pre-template multi-slot records must permit an identified single-slot edit');
assert.equal(S.canReschedule({...saved,event:{...event,occurrences:null}}),false);
const noSaved={...event,occurrences:undefined,repeatTemplate:undefined,
  startDate:'2026-10-20T09:00:00Z'};
assert.equal(S.canReschedule({...saved,event:noSaved,occurrenceIndex:0}),true,
  'a real legacy single-date Event should not need an occurrences migration');
assert.equal(S.canReschedule({...saved,event:noSaved}),false,
  'do not reinterpret occurrence #2 of a multi-slot series as a legacy single slot');
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
const crossed=O.rescheduleSavedRecurring(edited,2,
  '2026-10-14T09:00:00Z','2026-10-14T10:00:00Z');
assert.ok(crossed,'moving across another day must preserve slot identity');
const crossedStored=O.store(crossed,O.entries(crossed));
assert.equal(crossedStored.repeatCycleStart,event.repeatCycleStart);
assert.equal(crossedStored.occurrences[2].startDate,'2026-10-14T09:00:00.000Z');
assert.deepEqual(plainSlots(crossedStored.occurrences.slice(0,2)),plainSlots(O.entries(event).slice(0,2)),
  'cross-day move reordered or rewrote notified history');
function plainSlots(value) {return JSON.parse(JSON.stringify(value));}
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
// Pre-multi-date Agenda format: no occurrences, no repeatTemplate, but the
// saved top-level recurrence is a *real* instance and must be editable.
const oldSeries={
  id:303,title:'Old weekly study group',dateTime:'2026-10-20T09:00:00Z',
  startDate:'2026-10-20T09:00:00Z',endDate:'2026-10-20T10:00:00Z',
  recurrence:'weekly',notified:false,reminderNotified:false,
  todoLink:{key:'keep-old'},ownerField:{retained:true}
};
const unchangedOld=JSON.stringify(oldSeries);
const oldRows=P.project([oldSeries],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed);
const oldReal=oldRows.find(row=>row.event.id===303 && !row.virtual);
assert.ok(oldReal && S.canReschedule(oldReal),'old weekly Event cannot drag');
assert.equal(S.canSelect(oldReal),true,'old recurring instances remain selectable');
assert.equal(S.canDelete(oldReal),false,'recurring event must not enter batch deletion');
assert.equal(S.canReschedule({...oldReal,virtual:true}),false,'virtual series must stay read-only');
assert.equal(S.canReschedule({...oldReal,source:'external'}),false);
const oldDragged=G.rangeForGesture(oldReal,'move',0,13,102,52);
const oldTop=G.rangeForGesture(oldReal,'top',0,13,102,52);
const oldBottom=G.rangeForGesture(oldReal,'bottom',0,13,102,52);
assert.ok(oldDragged && oldTop && oldBottom,'missing old-event move/resize policy');
const oldUpdated=O.rescheduleSavedRecurring(oldSeries,0,
  oldDragged.startIso,oldDragged.endIso);
assert.ok(oldUpdated,'old single-date series backend rejected');
assert.equal(JSON.stringify(oldSeries),unchangedOld,'original owner record mutated');
assert.equal(oldUpdated.id,303);
assert.equal(oldUpdated.occurrences,undefined,'must not migrate old Events on gesture');
assert.equal(oldUpdated.startDate,'2026-10-20T09:15:00.000Z');
assert.equal(oldUpdated.dateTime,oldUpdated.startDate);
assert.equal(oldUpdated.plannerSeriesStartDate,'2026-10-20T09:00:00Z');
assert.equal(oldUpdated.plannerSeriesEndDate,'2026-10-20T10:00:00Z');
assert.equal(oldUpdated.notified,false);
assert.equal(JSON.stringify(oldUpdated.todoLink),JSON.stringify(oldSeries.todoLink));
assert.equal(JSON.stringify(oldUpdated.ownerField),JSON.stringify(oldSeries.ownerField));
const oldRendered=P.project([oldUpdated],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed);
assert.equal(oldRendered.filter(row=>!row.virtual && row.event.id===303
    && row.startDate.toISOString()==='2026-10-20T09:15:00.000Z').length,1,
  'edited old single-date event invisible');
const oldVirtual=P.project([oldUpdated],[],'2026-10-27T12:00:00Z',1)
  .flatMap(day=>day.timed);
assert.ok(oldVirtual.some(row=>row.virtual
    && row.startDate.toISOString()==='2026-10-27T09:00:00.000Z'),
  'future old weekly events must follow original 09:00 series');
assert.ok(!oldVirtual.some(row=>row.virtual
    && row.startDate.toISOString()==='2026-10-27T09:15:00.000Z'),
  'old recurring edit drifted the whole series');
// A moved occurrence must appear in the *destination week*, not only its
// original anchor week; avoid a duplicate virtual Event with the same start.
const weekMoved=O.rescheduleSavedRecurring(oldSeries,0,
  '2026-10-27T09:00:00Z','2026-10-27T10:00:00Z');
const movedRows=P.project([weekMoved],[],'2026-10-27T12:00:00Z',1)
  .flatMap(day=>day.timed);
assert.equal(movedRows.filter(row=>row.event.id===303
    && row.startDate.toISOString()==='2026-10-27T09:00:00.000Z').length,1,
  'moving old instance across weeks must not hide or duplicate it');
assert.equal(movedRows.filter(row=>!row.virtual).length,1,
  'destination week must contain the editable saved instance');
// A legacy single-slot occurrences array is also unambiguous, even when
// created before immutable templates existed.
const legacyOneSlot={...oldSeries,occurrences:[{startDate:oldSeries.startDate,
  endDate:oldSeries.endDate,notified:false}]};
const oneSlotRow=P.project([legacyOneSlot],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed).find(row=>!row.virtual);
assert.ok(oneSlotRow && S.canReschedule(oneSlotRow));
const promoted=O.rescheduleSavedRecurring(legacyOneSlot,0,oldTop.startIso,oldTop.endIso);
assert.ok(promoted && promoted.repeatTemplate.length===1);
assert.equal(promoted.repeatTemplate[0].startDate,oldSeries.startDate);
assert.equal(promoted.repeatCycleStart,0);
assert.equal(JSON.stringify(legacyOneSlot.occurrences[0]),
  JSON.stringify({startDate:oldSeries.startDate,endDate:oldSeries.endDate,notified:false}));
assert.equal(O.rescheduleSavedRecurring(oldSeries,1,oldDragged.startIso,oldDragged.endIso),null);
// Very old Agenda entries may only have dateTime and no endDate.
const oldest={id:404,title:'Archived daily legacy',dateTime:'2026-10-20T07:00:00Z',
  recurrence:'daily',notified:false,ownerNotes:{preserve:true}};
const oldestRow=P.project([oldest],[],'2026-10-20T12:00:00Z',1)
  .flatMap(day=>day.timed).find(row=>!row.virtual && row.event.id===404);
assert.ok(oldestRow && S.canReschedule(oldestRow),
  'dateTime-only repeating Event not draggable');
const oldestRange=G.rangeForGesture(oldestRow,'bottom',0,13,102,52);
assert.ok(oldestRange);
const oldestUpdate=O.rescheduleSavedRecurring(oldest,0,oldestRange.startIso,
  oldestRange.endIso);
assert.ok(oldestUpdate && oldestUpdate.occurrences===undefined);
assert.equal(oldestUpdate.plannerSeriesStartDate,oldest.dateTime);
assert.equal(oldestUpdate.plannerSeriesEndDate,'2026-10-20T08:00:00.000Z');
assert.equal(oldestUpdate.ownerNotes.preserve,true);
// Old weekly Events are often shown as *virtual* occurrences after the
// original stored date. These must be editable without materializing every
// recurrence, modifying the original Event ID or shifting later weeks.
const virtualRow=P.project([oldSeries],[],'2026-10-27T12:00:00Z',1)
  .flatMap(day=>day.timed).find(row=>row.event.id===303 && row.virtual);
assert.ok(virtualRow && virtualRow.plannerOriginalStartIso
  && S.canReschedule(virtualRow),'current-week projected old Event still locked');
assert.equal(S.canSelect(virtualRow),true,'identified virtual occurrences remain selectable');
assert.equal(S.canDelete(virtualRow),false,'virtual occurrence entered batch delete');
assert.equal(S.canReschedule({...virtualRow,source:'external'}),false);
assert.equal(S.canReschedule({...virtualRow,plannerOriginalStartIso:''}),false);
const virtualResize=G.rangeForGesture(virtualRow,'bottom',0,13,102,52);
assert.ok(virtualResize,'virtual resize gesture not computed');
const originalVirtual=virtualRow.plannerOriginalStartIso;
const exception=O.rescheduleProjectedRecurring(oldSeries,0,originalVirtual,
  virtualResize.startIso,virtualResize.endIso);
assert.ok(exception && exception.plannerOverrides?.length===1);
assert.equal(exception.id,oldSeries.id);
assert.equal(exception.occurrences,undefined);
assert.equal(exception.startDate,oldSeries.startDate);
assert.equal(exception.recurrence,oldSeries.recurrence);
assert.equal(JSON.stringify(exception.todoLink),JSON.stringify(oldSeries.todoLink));
assert.equal(JSON.stringify(oldSeries),unchangedOld,'virtual edit changed original');
const changedVirtual=P.project([exception],[],'2026-10-27T12:00:00Z',1)
  .flatMap(day=>day.timed).find(row=>row.plannerOriginalStartIso===originalVirtual);
assert.ok(changedVirtual && changedVirtual.virtual && S.canReschedule(changedVirtual));
assert.equal(changedVirtual.endDate.toISOString(),'2026-10-27T10:15:00.000Z');
const anotherResize=G.rangeForGesture(changedVirtual,'bottom',0,13,102,52);
const repeatedException=O.rescheduleProjectedRecurring(exception,0,originalVirtual,
  anotherResize.startIso,anotherResize.endIso);
assert.equal(repeatedException.plannerOverrides.length,1,
  'editing a virtual exception twice must not duplicate it');
assert.equal(O.rescheduleProjectedRecurring(oldSeries,0,
  '2026-10-28T09:00:00Z',virtualResize.startIso,virtualResize.endIso),null,
  'non-scheduled instance must be rejected by the backend');
const movedVirtual=O.rescheduleProjectedRecurring(oldSeries,0,originalVirtual,
  '2026-11-02T09:00:00Z','2026-11-02T10:00:00Z');
const projectedDestination=P.project([movedVirtual],[],'2026-11-02T12:00:00Z',1)
  .flatMap(day=>day.timed);
assert.equal(projectedDestination.filter(row=>row.plannerOriginalStartIso===
  originalVirtual && row.startDate.toISOString()==='2026-11-02T09:00:00.000Z').length,1,
  'moved virtual instance not shown in destination week');
assert.ok(projectedDestination.some(row=>row.plannerOriginalStartIso!==
  originalVirtual && row.startDate.toISOString()==='2026-11-03T09:00:00.000Z'),
  'independent weekly recurrence changed when virtual instance moved');
const groupedNext=P.project([event],[],'2026-10-27T12:00:00Z',1)
  .flatMap(day=>day.timed).find(row=>row.virtual);
assert.ok(groupedNext && S.canReschedule(groupedNext),
  'grouped legacy Weekly virtual future instance missing edit controls');
const groupedOverride=O.rescheduleProjectedRecurring(event,groupedNext.occurrenceIndex,
  groupedNext.plannerOriginalStartIso,groupedNext.startDate.toISOString(),
  new Date(groupedNext.endDate.getTime()+15*60000).toISOString());
assert.ok(groupedOverride && groupedOverride.plannerOverrides.length===1);
assert.equal(JSON.stringify(groupedOverride.repeatTemplate),JSON.stringify(event.repeatTemplate),
  'grouped virtual override changed repeatTemplate');
const source=fs.readFileSync(file('services/Events.qml'),'utf8');
const recurrenceFunction=source.slice(source.indexOf('function createNextRecurrence('),
  source.indexOf('function addEvent(',source.indexOf('function createNextRecurrence(')));
const created=[];
const scope=vm.createContext({root:{addEvent(...args){created.push(args);}},Date,Number,Math});
vm.runInContext(recurrenceFunction,scope);
scope.createNextRecurrence(oldUpdated,new Date('2026-10-21T12:00:00Z').getTime());
assert.equal(created.length,1);
assert.equal(created[0][2],'2026-10-27T09:00:00.000Z',
  'legacy next recurrence wrongly followed edited current instance');
assert.equal(created[0][7],'2026-10-27T10:00:00.000Z',
  'legacy future event duration must use original slot');
console.log('WEEKLY_PLANNER_LEGACY_RECURRENCE_PASS: pre-occurrences weekly editing, original repeat cadence, old slot and immutable history');
