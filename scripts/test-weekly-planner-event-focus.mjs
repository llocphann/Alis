#!/usr/bin/env node
// Weekly Planner drag -> Edit Event calendar focus regression.
// Pure policy; native Quickshell/Niri pointer testing remains separate.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';

const helperFile=fileURLToPath(new URL('../modules/sidebarRight/events/EventDateSelection.js',import.meta.url));
const source=fs.readFileSync(helperFile,'utf8');
const sandbox=vm.createContext({Date,Array,Number,String,JSON,Object,Math});
vm.runInContext(source,sandbox,{filename:helperFile});
const {key,rebaseDraggedEvent}=sandbox;
const old=new Date(2026,9,14,5,15);
const next=new Date(2026,9,15,4,45);
const finish=new Date(2026,9,15,7,30);
const slot=(start,end)=>({startDate:start.toISOString(),endDate:end.toISOString()});
const current={
 date:old,keys:[key(old)],anchor:key(old),time:'05:15',endTime:'08:00'
};
const baseline=['Original title','Note',old.getTime(),'05:15','08:00',
 false,'general','normal',15,'none',[key(old)]];
const changed={id:91,...slot(next,finish),occurrences:[slot(next,finish)]};
const rebased=rebaseDraggedEvent(current,baseline,old,
 next.toISOString(),finish.toISOString(),changed);
assert.ok(rebased);
assert.equal(key(rebased.date),key(next),'date focus must follow moved day');
assert.equal(JSON.stringify(rebased.keys),JSON.stringify([key(next)]),
 'selected background must move, not stay on original day');
assert.equal(rebased.anchor,key(next));
assert.equal(rebased.time,'04:45');
assert.equal(rebased.endTime,'07:30');
assert.equal(rebased.occurrenceIndex,0);
assert.equal(rebased.dateFollowed,true);
assert.equal(rebased.baseline[2],next.getTime());
assert.equal(rebased.baseline[10][0],key(next));
assert.equal(rebased.baseline[0],'Original title');

// A note/title draft remains dirty even after the stored date/time baseline
// follows the external pointer gesture.
const dirtySnapshot=['Unsaved title','Note',rebased.date.getTime(),
 rebased.time,rebased.endTime,false,'general','normal',15,'none',rebased.keys];
assert.notEqual(JSON.stringify(dirtySnapshot),JSON.stringify(rebased.baseline));

// Moving one occurrence of an Event group preserves other selected dates.
// Sorting after a cross-day move can change the occurrence index.
const otherStart=new Date(2026,9,16,11);
const otherEnd=new Date(2026,9,16,12);
const lastStart=new Date(2026,9,13,12);
const lastEnd=new Date(2026,9,13,13);
const grouped={id:91,occurrences:[slot(lastStart,lastEnd),
 slot(next,finish),slot(otherStart,otherEnd)]};
const groupBaseline=baseline.slice();
groupBaseline[10]=[key(old),key(otherStart),key(lastStart)].sort();
const groupResult=rebaseDraggedEvent({
 ...current,keys:groupBaseline[10]
},groupBaseline,old,next,finish,grouped);
assert.deepEqual(Array.from(groupResult.keys),[key(lastStart),key(next),key(otherStart)]);
assert.equal(key(groupResult.date),key(next));
assert.equal(groupResult.occurrenceIndex,1);

// Manual date-selection changes take precedence over the drag, preventing
// unexpected overwrites of an unsaved Ctrl/Shift calendar selection.
const manual=new Date(2026,9,17);
const preserved=rebaseDraggedEvent({
 ...current,date:manual,keys:[key(manual)],anchor:key(manual)
},baseline,old,next,finish,changed);
assert.equal(key(preserved.date),key(manual));
assert.equal(preserved.keys[0],key(manual));
assert.equal(preserved.dateFollowed,false);
assert.equal(preserved.baseline[2],old.getTime());

// A hand-edited start time stays untouched; only clean fields are rebased.
const manualTime=rebaseDraggedEvent({...current,time:'06:00'},
 baseline,old,next,finish,changed);
assert.equal(manualTime.time,'06:00');
assert.equal(manualTime.baseline[3],'05:15');
assert.equal(manualTime.endTime,'07:30');
assert.equal(rebaseDraggedEvent(current,baseline,old,next,finish,
 {id:91,occurrences:[slot(lastStart,lastEnd)]}),null);

// Source integration guard: only the actual successful write may update
// the matching open editor, never a canceled/failed drag or a different ID.
const planner=fs.readFileSync(fileURLToPath(
 new URL('../modules/dashboard/DashboardWeeklyPlanner.qml',import.meta.url)),'utf8');
const editor=fs.readFileSync(fileURLToPath(
 new URL('../modules/sidebarRight/events/EventsDialog.qml',import.meta.url)),'utf8');
const body=planner.split('function commitTimedGesture(row, mode, dx, dy): void {',2)[1]
 .split('function editOccurrence(row): void {',1)[0];
assert.ok(body.indexOf('rescheduleOccurrence(')<body.indexOf('form.syncMovedOccurrence('));
assert.ok(body.includes('form.editingEvent?.id===target.event.id'));
assert.ok(body.includes('form.editingOccurrenceIndex===target.occurrenceIndex'));
assert.ok(body.includes('applyPlannerOccurrenceBatch(changes)'),
    'multi-selection must use one atomic write');
assert.ok(body.includes('if (!range) {'),
    'invalid group ranges must abort before any persistence');
assert.ok(body.indexOf('rescheduleOccurrence(')<body.indexOf('form.syncMovedOccurrence('),
    'single-event writes must complete before form reconciliation');
assert.ok(body.includes('return\n            }'),
    'failed group writes must return before updating the editor');
assert.ok(editor.includes('function syncMovedOccurrence(id, oldStart, newStart, newEnd): void'));
assert.ok(editor.includes('root._cleanFormSnapshot=JSON.stringify(change.baseline)'));
assert.ok(editor.includes('root._plannerPickingDate=true'));
assert.ok(editor.includes('root.plannerSelectedDateKeys=change.keys'));
assert.ok(editor.includes('root.eventDate=change.date'));
assert.ok(editor.includes('multiSelectedDates: root.plannerSelectedDateKeys'));
console.log('WEEKLY_PLANNER_EVENT_FOCUS_PASS: saved moves rebase date/time without wiping unsaved form');
