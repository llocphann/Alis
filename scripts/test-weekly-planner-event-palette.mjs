#!/usr/bin/env node
// Weekly Planner color contract: one real theme hue, stable schedule identity,
// eight lightness tiers. Pure presentation; NEVER rewrite stored Events.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const file=rel=>new URL('../'+rel,import.meta.url);
const source=rel=>fs.readFileSync(file(rel),'utf8');
const policy=source('modules/dashboard/PlannerEventPalette.js');
const scope=vm.createContext({Math,Number,String,JSON,Object,Map,Set,Array});
vm.runInContext(policy,scope);
const tone=(event,source='local')=>scope.toneIndex(event,source,8);
const legacy={id:42,title:'8-Grade Tutoring',category:'general',
    recurrence:'weekly',startDate:'2026-10-20T18:30:00Z',
    endDate:'2026-10-20T20:00:00Z',privateHistory:{keep:true}};
const snapshot=JSON.stringify(legacy);
assert.equal(tone(legacy),tone({...legacy,startDate:'2027-03-22T12:00:00Z',
    endDate:'2027-03-22T13:00:00Z'}),'time cannot determine color');
assert.equal(tone(legacy),tone({...legacy,occurrenceIndex:20,
    occurrences:[{startDate:'2028-01-01T19:00:00Z'}]}),
    'grouped and projected slots of the same ID must have one tone');
// Real legacy Agenda rollover creates a NEW ID through Events.addEvent.
// The *same recurring schedule* should still use its original color.
// Include mixed old/new and cross-week rows; do not alter historical JSON.
const next={...legacy,id:317,notified:false,
    startDate:'2026-10-27T18:30:00Z',endDate:'2026-10-27T20:00:00Z'};
const before={...legacy,id:6,notified:true,startDate:'2026-10-13T18:30:00Z'};
assert.equal(tone(legacy),tone(next),
    'legacy separate-ID weekly rollover recolored an existing class');
assert.equal(tone(legacy),tone(before),
    'already-notified historical weekly Event changed color');
assert.equal(tone(legacy),tone({...next,title:'  8-GRADE   TUTORING  '}),
    'case and whitespace should not separate one recurring class');
assert.equal(scope.toneIdentity(legacy,'local'),
    scope.toneIdentity(next,'local'),
    'series identity cannot contain the new Event ID or time');
assert.equal(tone({...legacy,seriesColorKey:'owner-series'}),
    tone({...next,seriesColorKey:'owner-series'}),
    'optional durable explicit series key should be supported');
// Classes visible in the owner's before/after screenshots; same schedule on
// different weekdays is one color, while these independent schedules receive
// different lightness levels of the SAME Material hue.
const names=['8-Grade Tutoring','B1-VSTEP Tutoring',
    '10-Grade Tutoring','10-Grade Class'];
const tones=names.map(title=>tone({...legacy,title}));
assert.equal(new Set(tones).size,names.length,
    'actual four classroom schedules collide after rebuilding tone mapping');
assert.ok(tones.every(index=>Number.isInteger(index)&&index>=0&&index<8));
const oneoffA={id:73,title:'Single meeting',recurrence:'none'};
const oneoffB={id:74,title:'Single meeting',recurrence:'none'};
assert.notEqual(scope.toneIdentity(oneoffA,'local'),
    scope.toneIdentity(oneoffB,'local'),
    'independent one-off Events must remain ID-based');
assert.equal(tone(oneoffA),tone({...oneoffA,startDate:'2030-05-25T10:00:00Z',
    title:'Edited name'}),'non-recurring ID must be immune to renames');
const ext={uid:'cal-uid-abc',title:'Imported',startDate:'2026-10-21T14:00:00Z'};
assert.equal(tone(ext,'external'),
    tone({...ext,id:994,startDate:'2026-11-21T14:00:00Z'},'external'),
    'external UID must remain stable even when a projection has an ID');
assert.equal(JSON.stringify(legacy),snapshot,'pure tone mapping touched owner Event');
assert.equal(JSON.stringify(next),JSON.stringify({...legacy,id:317,
    notified:false,startDate:'2026-10-27T18:30:00Z',
    endDate:'2026-10-27T20:00:00Z'}),'legacy user records altered');
for(let id=1;id<=20;id++)
    assert.equal(tone({id}),tone({id}),'tone mapping not deterministic');
// Keep the old *continuous* position identity API for unrelated consumers
// and the established 64-ID no-regression oracle.
assert.equal(scope.position({id:100},'local'),
    scope.assignPositions([{id:100}])[scope.identity({id:100},'local')]);
assert.doesNotMatch(policy,/Math\.random|Date\.now|saveToFile|writeFile/);
const qml=source('modules/dashboard/DashboardWeeklyPlanner.qml');
assert.match(qml,/import "PlannerEventPalette.js" as EventPalette/);
assert.match(qml,/readonly property color eventToneBase: Appearance\.colors\.colPrimary/,
    'the only generated hue must come from live Material Primary');
assert.match(qml,/function eventToneColor\(row\): color/);
assert.match(qml,/EventPalette\.toneIndex\(row\?\.event,row\?\.source,8\)/);
assert.match(qml,/const levels=\[-\.21,-\.15,-\.09,-\.03,\.03,\.09,\.15,\.21\]/);
assert.match(qml,/Qt\.hsla\(base\.hslHue>=0 \? base\.hslHue : 0,/);
assert.match(qml,/base\.hslSaturation,lightness,1\)/,
    'never inject saturation or another Event hue into the theme tone');
assert.doesNotMatch(qml,/CavaTheme\.vibrantColors|eventThemeColors|eventGradientColor\(/,
    'do not resurrect CAVA/rainbow mapping');
assert.match(qml,/row\?\.event\?\.color/);
assert.match(qml,/row\?\.event\?\.sourceColor/);
const allDay=qml.slice(qml.indexOf('objectName:"plannerAllDayEvent"'),
    qml.indexOf('objectName:"plannerTimedEvent"'));
const timed=qml.slice(qml.indexOf('objectName:"plannerTimedEvent"'),
    qml.indexOf('visible:dayColumn.today && root.presentationActive'));
assert.match(allDay,/root\.eventToneColor\(modelData\)/);
assert.match(allDay,/colBackground:Qt\.alpha\(allDayButton\.eventAccent/);
assert.match(timed,/root\.eventToneColor\(modelData\)/);
assert.match(timed,/gradient: Gradient \{/);
assert.match(timed,/orientation:Gradient\.Horizontal/);
assert.equal((timed.match(/color:Qt\.alpha\(timedButton\.eventAccent/g)||[]).length,2,
    'both gradient endpoints must use the SAME one-theme-hue swatch');
assert.doesNotMatch(timed,/x:1;y:3;width:3/,'Owner removed timed accent stripe');
assert.doesNotMatch(allDay,/x:2;y:4;width:3/,'Owner removed All-day accent stripe');
for(const action of ['plannerEventMoveArea','plannerResizeStart','plannerResizeEnd',
    'root.commitTimedGesture(modelData,mode,dx,dy)',
    'readonly property bool showResizeHandles: canReschedule']) {
    assert.ok(timed.includes(action),'new color presentation broke gestures: '+action);
}
console.log('WEEKLY_PLANNER_THEME_PALETTE_PASS: real single-theme hue, distinct tones, same-ID and legacy rollover, old data, drag/resize');
