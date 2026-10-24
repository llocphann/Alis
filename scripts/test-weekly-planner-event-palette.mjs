#!/usr/bin/env node
// Pure mapping + view source contracts: Event swatches never mutate storage.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const path=rel=>new URL('../'+rel,import.meta.url);
const file=rel=>fs.readFileSync(path(rel),'utf8');
const policy=file('modules/dashboard/PlannerEventPalette.js');
const context=vm.createContext({Math,Number,String});
vm.runInContext(policy,context);
const slot=context.paletteSlot;
const event={id:42,title:'Weekly class',recurrence:'weekly',
  startDate:'2026-10-20T09:00:00Z',privateData:{retain:true}};
const original=JSON.stringify(event);
const index=slot(event,'local',8);
assert.ok(index>=0 && index<8);
assert.equal(slot({...event,title:'Renamed',startDate:'2027-01-02T09:00:00Z'},'local',8),index,
  'editing Event title/date must not change identity color');
assert.equal(slot({...event,occurrenceIndex:11},'local',8),index,
  'every occurrence of one Event must keep the same color');
assert.equal(JSON.stringify(event),original,'color mapping mutated user Event');
const firstEight=Array.from({length:8},(_,i)=>slot({id:i+1},'local',8));
assert.equal(new Set(firstEight).size,8,'successive local Event IDs should spread over all swatches');
assert.ok(firstEight.every((value,i)=>i===0 || Math.abs(value-firstEight[i-1])>1),
  'neighboring Event IDs cannot get near-identical gradient stops');
const external={uid:'calendar-uid@example.com',title:'Outside meeting'};
assert.equal(slot(external,'external',8),slot({...external,title:'Updated meeting'},'external',8));
assert.equal(slot({title:'Legacy id-less Event'},'local',8),
  slot({title:'Legacy id-less Event'},'local',8));
assert.equal(slot({id:1},'local',1),0);
assert.equal(slot({id:999},'local',8),slot({id:999},'local',8));
const qml=file('modules/dashboard/DashboardWeeklyPlanner.qml');
assert.match(qml,/import "PlannerEventPalette.js" as EventPalette/);
assert.match(qml,/readonly property var eventThemeColors: CavaTheme\.vibrantColors/,
  'palette must follow theme and must not follow music cover/CAVA source changes');
assert.match(qml,/function eventGradientColor\(row, palette\): color/);
assert.match(qml,/EventPalette\.paletteSlot\(row\?\.event,row\?\.source,steps\)/);
assert.match(qml,/row\?\.event\?\.color/,
  'an intentionally set Event color must remain respected');
assert.match(qml,/row\?\.event\?\.sourceColor/,
  'external source colors must remain respected');
const allDay=qml.slice(qml.indexOf('objectName:"plannerAllDayEvent"'),
  qml.indexOf('objectName:"plannerTimedEvent"'));
const timed=qml.slice(qml.indexOf('objectName:"plannerTimedEvent"'),
  qml.indexOf('visible:dayColumn.today && root.presentationActive'));
assert.match(allDay,/root\.eventGradientColor\(modelData,root\.eventThemeColors\)/);
assert.match(allDay,/colBackground:Qt\.alpha\(allDayButton\.eventAccent/);
assert.match(timed,/root\.eventGradientColor\(modelData,root\.eventThemeColors\)/);
assert.match(timed,/gradient: Gradient \{/);
assert.match(timed,/orientation:Gradient\.Horizontal/);
assert.match(timed,/color:Qt\.alpha\(timedButton\.eventAccent/);
assert.match(timed,/color:timedButton\.eventAccent/);
for (const token of ['plannerEventMoveArea','plannerResizeStart','plannerResizeEnd',
  'root.commitTimedGesture(modelData,mode,dx,dy)',
  'readonly property bool showResizeHandles: canReschedule']) {
  assert.ok(timed.includes(token),'palette change damaged Event gesture contract: '+token);
}
assert.doesNotMatch(policy,/Math\.random|Date\.now|saveToFile|writeFile/);
console.log('WEEKLY_PLANNER_THEME_PALETTE_PASS: stable identity, theme palette, gradients, old data, gestures');
