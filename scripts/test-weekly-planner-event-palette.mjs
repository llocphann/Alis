#!/usr/bin/env node
// Curated, subdued Event colors are deterministic by ID/UID and do not use
// theme, title, occurrence time, or an automatically rotated rainbow hue.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const file=rel=>new URL('../'+rel,import.meta.url);
const source=rel=>fs.readFileSync(file(rel),'utf8');
const policy=source('modules/dashboard/PlannerEventPalette.js');
const scope=vm.createContext({Math,Number,String,JSON,Object,Map,Set,Array});
vm.runInContext(policy,scope);
const color=(event,origin='local')=>scope.eventSwatch(event,origin);
const identity=(event,origin='local')=>scope.eventColorIdentity(event,origin);
const swatches=Array.from(vm.runInContext('EVENT_SWATCHES',scope));
assert.equal(swatches.length,16,'keep a deliberately hand-curated sixteen-color palette');
assert.equal(new Set(swatches).size,swatches.length);
assert.ok(swatches.every(hex=>/^#[0-9A-F]{6}$/i.test(hex)));
for(const hex of swatches){
    const rgb=[1,3,5].map(n=>parseInt(hex.slice(n,n+2),16));
    const chroma=Math.max(...rgb)-Math.min(...rgb);
    assert.ok(chroma<=64,'neon/saturated Event color slipped into muted palette: '+hex);
    assert.ok(Math.max(...rgb)<=160,'curated colors must remain gentle on dark surfaces');
    assert.ok(Math.min(...rgb)>=80,'swatches should remain legible on dark surfaces');
}
const sample={id:42,title:'8-Grade Tutor',category:'general',recurrence:'weekly',
    startDate:'2026-10-19T18:30:00Z',endDate:'2026-10-19T20:00:00Z',
    ownerExtras:{retain:true}};
const original=JSON.stringify(sample);
const variations=[
    {...sample,title:'Renamed class',recurrence:'daily'},
    {...sample,startDate:'2031-11-02T09:45:00Z',endDate:'2031-11-02T10:45:00Z'},
    {...sample,occurrences:[{startDate:'2030-01-01T13:00:00Z'}]},
    {...sample,notified:true,priority:'high'},
    {...sample,virtual:true,plannerOriginalStartIso:'2031-02-10T09:00:00Z'}
];
for(const event of variations){
    assert.equal(color(event),color(sample),'same Event ID recolored after schedule edit');
    assert.equal(identity(event),identity(sample),'ID identity depends on event fields');
}
assert.equal(color({id:'42'}),color(sample),'old numeric-string ID mismatch');
assert.equal(identity({id:'00042'}),identity(sample));
assert.equal(JSON.stringify(sample),original,'color assignment changed saved Event');
assert.notEqual(color({...sample,id:43}),color(sample),'adjacent IDs share a swatch');
assert.notEqual(color({...sample,id:317}),color(sample),'old separate-ID rollover shares a swatch');
// Deterministic 16 authored tones + two mild value variations; first 48 IDs
// are visually distinct without rainbow hue synthesis.
const first48=Array.from({length:48},(_,id)=>color({id}));
assert.equal(new Set(first48).size,48,'curated swatch variants collide');
assert.ok(first48.slice(0,16).every((c,id)=>c===swatches[id]),
    'first sixteen numeric IDs must map directly to the authored palette');
assert.ok(first48.every(c=>/^#[0-9A-F]{6}$/i.test(c)));
for(const id of [0,1,48,123456,4294967296,Number.MAX_SAFE_INTEGER]){
    assert.equal(color({id}),color({id}), 'color is not stable on repeat read');
    assert.equal(color({id:String(id)}),color({id}),
        'legacy numeric-string Event ID must have the same color');
}
const imported={uid:'ical-stable',id:19,title:'Outside event'};
assert.equal(color(imported,'external'),color({...imported,id:927,
    title:'Edited',startDate:'2029-01-01T09:00:00Z'},'external'));
assert.equal(identity(imported,'external'),identity({...imported,id:22},'external'));
assert.equal(color({title:'ID-less old Event'}),color({title:'ID-less old Event'}));
// Preserve old position API for independent view-only users/contract tests.
assert.equal(scope.position({id:42},'local'),
    scope.assignPositions([{id:42}])[scope.identity({id:42},'local')]);
assert.doesNotMatch(policy,/Math\.random|Date\.now|saveToFile|writeFile/);
assert.doesNotMatch(policy,/function eventHue\(/,
    'continuous golden-angle color wheel must not return');
const qml=source('modules/dashboard/DashboardWeeklyPlanner.qml');
assert.match(qml,/import "PlannerEventPalette.js" as EventPalette/);
assert.match(qml,/function eventIdentityColor\(row\): color/);
assert.match(qml,/Qt\.color\(EventPalette\.eventSwatch\(row\?\.event,row\?\.source\)\)/);
assert.doesNotMatch(qml,/EventPalette\.eventHue|eventToneBase|EventPalette\.toneIndex|CavaTheme\.vibrantColors/,
    'Event colors must not derive from theme or rainbow hue rotation');
const colorBody=qml.slice(qml.indexOf('function eventIdentityColor(row): color'),
    qml.indexOf('    // Match the date and All-day headings'));
assert.doesNotMatch(colorBody,/Appearance\.|CavaTheme|m3colors|Date\.|random/,
    'color selection must not follow wallpaper, time, or random state');
assert.match(colorBody,/row\?\.event\?\.color/,
    'explicit saved custom color must remain honored');
assert.match(colorBody,/row\?\.event\?\.sourceColor/,
    'explicit external calendar color must remain honored');
const allDay=qml.slice(qml.indexOf('objectName:"plannerAllDayEvent"'),
    qml.indexOf('objectName:"plannerTimedEvent"'));
const timed=qml.slice(qml.indexOf('objectName:"plannerTimedEvent"'),
    qml.indexOf('visible:dayColumn.today && root.presentationActive'));
assert.match(allDay,/root\.eventIdentityColor\(modelData\)/);
assert.match(allDay,/root\.isEventSelected\(modelData\) \|\| root\.isEditorEvent\(modelData\) \? \.44 : \.35/);
assert.match(timed,/root\.eventIdentityColor\(modelData\)/);
assert.match(timed,/gradient: Gradient \{/);
assert.match(timed,/orientation:Gradient\.Horizontal/);
assert.equal((timed.match(/color:Qt\.alpha\(timedButton\.eventAccent/g)||[]).length,2,
    'gradient ends must share the SAME Event swatch');
assert.match(timed,/eventMouse\.containsMouse \? \.47 : \.36/);
assert.match(timed,/eventMouse\.containsMouse \? \.34 : \.24/);
const resizeSection=timed.slice(timed.indexOf('objectName:"plannerResizeStart"'),
    timed.indexOf('id:bottomResizeMouse'));
assert.equal((resizeSection.match(/color:Qt\.lighter\(timedButton\.eventAccent,1\.20\)/g)||[]).length,2,
    'both hover-resize lines must derive from the same Event swatch');
assert.doesNotMatch(resizeSection,/color:root\.headerAccent/,
    'shared Today accent must never recolor individual Event resize bars');
assert.equal((timed.match(/opacity:timedButton\.showResizeHandles/g)||[]).length,2,
    'event-local hover/drag visibility must stay intact');
assert.doesNotMatch(timed,/x:1;y:3;width:3/,'do not resurrect retired accent stripe');
assert.doesNotMatch(allDay,/x:2;y:4;width:3/,'do not resurrect retired accent stripe');
for(const action of ['plannerEventMoveArea','plannerResizeStart','plannerResizeEnd',
    'root.commitTimedGesture(modelData,mode,dx,dy)',
    'readonly property bool showResizeHandles: canReschedule']){
    assert.ok(timed.includes(action),'palette change broke Event gestures: '+action);
}
console.log('WEEKLY_PLANNER_CURATED_EVENT_COLORS_PASS: muted authored palette, 48 distinct ID variants, stable imported UID, preserved data and gestures');
