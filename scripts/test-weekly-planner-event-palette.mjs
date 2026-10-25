#!/usr/bin/env node
// Fixed ID color contract. Event colors are independent of wallpaper/theme,
// title, date/time, recurrence and membership in the visible week.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const file=rel=>new URL('../'+rel,import.meta.url);
const source=rel=>fs.readFileSync(file(rel),'utf8');
const policy=source('modules/dashboard/PlannerEventPalette.js');
const scope=vm.createContext({Math,Number,String,JSON,Object,Map,Set,Array});
vm.runInContext(policy,scope);
const hue=(event,kind='local')=>scope.eventHue(event,kind);
const identity=(event,kind='local')=>scope.eventColorIdentity(event,kind);
const saved={id:42,title:'8-Grade Tutor',category:'general',recurrence:'weekly',
    startDate:'2026-10-19T18:30:00Z',endDate:'2026-10-19T20:00:00Z',
    ownerExtras:{doNotChange:true}};
const before=JSON.stringify(saved);
const variants=[
    {...saved,title:'Renamed Class',recurrence:'daily'},
    {...saved,startDate:'2027-11-02T08:15:00Z',endDate:'2027-11-02T09:15:00Z'},
    {...saved,occurrences:[{startDate:'2027-11-02T14:00:00Z'}]},
    {...saved,notified:true,priority:'high'},
    {...saved,virtual:true,plannerOriginalStartIso:'2028-01-01T09:00:00Z'}
];
for(const variation of variants) {
    assert.equal(hue(variation),hue(saved),
        'same Event ID changed color after timing/metadata/recurrence edit');
    assert.equal(identity(variation),identity(saved),'Event identity changed with fields');
}
assert.equal(hue({id:'42'},'local'),hue(saved),'numeric-string legacy ID differs');
assert.equal(identity({id:'00042'},'local'),identity(saved));
assert.equal(JSON.stringify(saved),before,'pure color mapping modified owner record');
// Different IDs, including two entries with the same title and recurrence,
// must get independent colors. The previous title-based sharing was incorrect.
assert.notEqual(hue({...saved,id:43}),hue(saved),
    'separate Event IDs are assigned the same color');
assert.notEqual(hue({...saved,id:317}),hue(saved),
    'separate legacy rollover ID must have its own identifying color');
assert.notEqual(identity({...saved,id:43}),identity(saved));
const consecutive=Array.from({length:16},(_,i)=>hue({id:i+1}));
assert.equal(new Set(consecutive).size,16,'first 16 Event IDs collided');
for(let i=1;i<consecutive.length;i++){
    const difference=Math.abs(consecutive[i]-consecutive[i-1]);
    assert.ok(Math.min(difference,1-difference)>.25,
        'nearby IDs should be readily distinguishable on the color wheel');
}
const specialIds=[0,1,65535,65536,4294967295,4294967296,Number.MAX_SAFE_INTEGER];
for(const id of specialIds) {
    const c=hue({id});
    assert.ok(Number.isFinite(c)&&c>=0&&c<1,'invalid hue for safe numeric Event ID');
    assert.equal(c,hue({id}), 'ID color changed across independent reads');
}
const imported={uid:'stable-ical-uid',id:19,title:'Outside meeting'};
assert.equal(hue(imported,'external'),hue({...imported,id:27,
    title:'New meeting title',startDate:'2029-01-01T10:00:00Z'},'external'),
    'imported UID changed due to temporary provider ID');
assert.notEqual(hue(imported,'external'),hue({...imported,uid:'new-uid'},'external'));
assert.equal(hue({title:'Legacy no ID'},'local'),
    hue({title:'Legacy no ID'},'local'),'old ID-less fallback unstable');
// Previous immutable position inventory API still belongs to other consumers.
assert.equal(scope.position({id:42},'local'),
    scope.assignPositions([{id:42}])[scope.identity({id:42},'local')]);
assert.doesNotMatch(policy,/Math\\.random|Date\\.now|saveToFile|writeFile/);
const qml=source('modules/dashboard/DashboardWeeklyPlanner.qml');
assert.match(qml,/import "PlannerEventPalette.js" as EventPalette/);
assert.match(qml,/function eventIdentityColor\\(row\\): color/);
assert.match(qml,/EventPalette\\.eventHue\\(row\\?\\.event,row\\?\\.source\\)/);
assert.match(qml,/Qt\\.hsla\\(EventPalette\\.eventHue/);
assert.match(qml,/0\\.74,0\\.56,1\\)/);
assert.doesNotMatch(qml,/eventToneBase|EventPalette\\.toneIndex|CavaTheme\\.vibrantColors/,
    'ID colors must not derive from theme or the old tone system');
const body=qml.slice(qml.indexOf('function eventIdentityColor(row): color'),
    qml.indexOf('    // Match the date and All-day headings'));
assert.doesNotMatch(body,/Appearance\\.|CavaTheme|m3colors|Date\\.|time|random/,
    'the color function cannot depend on wallpaper/theme/time');
assert.match(body,/row\\?\\.event\\?\\.color/,
    'do not silently discard user-set custom colors');
assert.match(body,/row\\?\\.event\\?\\.sourceColor/,
    'do not silently discard explicit external calendar colors');
const allDay=qml.slice(qml.indexOf('objectName:"plannerAllDayEvent"'),
    qml.indexOf('objectName:"plannerTimedEvent"'));
const timed=qml.slice(qml.indexOf('objectName:"plannerTimedEvent"'),
    qml.indexOf('visible:dayColumn.today && root.presentationActive'));
assert.match(allDay,/root\\.eventIdentityColor\\(modelData\\)/);
assert.match(timed,/root\\.eventIdentityColor\\(modelData\\)/);
assert.match(timed,/gradient: Gradient \\{/);
assert.equal((timed.match(/color:Qt\\.alpha\\(timedButton\\.eventAccent/g)||[]).length,2,
    'both gradient endpoints must use the same stable ID swatch');
assert.doesNotMatch(timed,/x:1;y:3;width:3/,'do not restore old timed accent stripe');
assert.doesNotMatch(allDay,/x:2;y:4;width:3/,'do not restore old all-day accent stripe');
for(const action of ['plannerEventMoveArea','plannerResizeStart','plannerResizeEnd',
    'root.commitTimedGesture(modelData,mode,dx,dy)',
    'readonly property bool showResizeHandles: canReschedule']) {
    assert.ok(timed.includes(action),'color changes broke Event gestures: '+action);
}
console.log('WEEKLY_PLANNER_EVENT_ID_COLORS_PASS: distinct fixed IDs, import UID, legacy, no-theme, gradients, unchanged gestures');
