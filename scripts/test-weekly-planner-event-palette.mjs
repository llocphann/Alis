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
// Three owner screenshots: cyan-blue, violet, and achromatic wallpapers.
// Theme fidelity beats forcing arbitrary 8-way hue distances. Eight cards
// remain distinguishable by tonal steps while retaining real Material hues.
const tones=context.materialTones;
const cases=[
  {name:'cyan',anchors:[{hue:.51,saturation:.75},
      {hue:.54,saturation:.42},{hue:.49,saturation:.34}]},
  {name:'purple',anchors:[{hue:.80,saturation:.67},
      {hue:.79,saturation:.38},{hue:.84,saturation:.27}]},
  {name:'neutral',anchors:[{hue:-1,saturation:0},
      {hue:-1,saturation:0},{hue:-1,saturation:0}]}
];
for (const {name,anchors} of cases) {
  for (const dark of [true,false]) {
    const swatches=Array.from(tones(anchors,dark));
    assert.equal(swatches.length,8,name+' palette size');
    const levels=swatches.map(v=>v.lightness);
    assert.equal(new Set(levels).size,8,name+' loses tonal differentiation');
    assert.ok(levels.every(level=>level>=0&&level<=1));
    for (let i=0;i<swatches.length;i++) {
      const source=anchors[[0,1,2,0,1,2,0,1][i]];
      assert.equal(swatches[i].saturation,source.saturation,
        name+' generated a non-theme saturation');
      assert.equal(swatches[i].hue,source.hue<0 ? 0 : source.hue,
        name+' introduced an unrelated rainbow hue');
    }
    if(name==='neutral')
      assert.ok(swatches.every(v=>v.saturation===0),
        'neutral wallpaper must never create arbitrary saturated Event colors');
  }
}
assert.deepEqual(Array.from(tones(cases[0].anchors,true)).map(v=>v.hue),
  Array.from(tones(cases[0].anchors,false)).map(v=>v.hue),
  'light/dark changes should not rotate the wallpaper hue');
assert.notDeepEqual(Array.from(tones(cases[0].anchors,true)).map(v=>v.hue),
  Array.from(tones(cases[1].anchors,true)).map(v=>v.hue),
  'switching wallpaper accent must change the Event palette');
assert.equal(JSON.stringify(event),original,'theme tones mutated owner data');
const qml=file('modules/dashboard/DashboardWeeklyPlanner.qml');
assert.match(qml,/import "PlannerEventPalette.js" as EventPalette/);
assert.match(qml,/readonly property var eventThemeColors: \\{/);
for (const accent of ['colPrimary','colSecondary','colTertiary'])
  assert.match(qml,new RegExp('Appearance\\\\.colors\\\\.'+accent));
assert.match(qml,/EventPalette\\.materialTones\\(/);
assert.match(qml,/saturation:color\\.hslSaturation/);
assert.match(qml,/hue:color\\.hslHue/);
assert.match(qml,/Qt\\.hsla\\(/);
assert.doesNotMatch(qml,/CavaTheme\\.vibrantColors|EventPalette\\.themeHues/,
  'Event colors must not be taken from music spectrum or synthetic rainbow hues');
assert.match(qml,/function eventGradientColor\\(row, palette\\): color/);
assert.match(qml,/function eventGradientTail\\(row, palette\\): color/);
assert.match(qml,/EventPalette\\.paletteSlot\\(row\\?\\.event,row\\?\\.source,palette\\.length\\)/);
assert.match(qml,/Appearance\\.colors\\.colLayer0/,
  'gradient tail should stay in the active theme, not another Event hue');
assert.match(qml,/row\\?\\.event\\?\\.color/,
  'an intentionally set Event color must remain respected');
assert.match(qml,/row\\?\\.event\\?\\.sourceColor/,
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
assert.match(timed,/color:Qt\.alpha\(timedButton\.eventAccentTail/);
assert.match(timed,/color:timedButton\.eventAccent/);
for (const token of ['plannerEventMoveArea','plannerResizeStart','plannerResizeEnd',
  'root.commitTimedGesture(modelData,mode,dx,dy)',
  'readonly property bool showResizeHandles: canReschedule']) {
  assert.ok(timed.includes(token),'palette change damaged Event gesture contract: '+token);
}
assert.doesNotMatch(policy,/Math\.random|Date\.now|saveToFile|writeFile/);
console.log('WEEKLY_PLANNER_THEME_PALETTE_PASS: real Material hues, neutral wallpaper, theme-reactive tonal gradients, stable IDs, old data, gestures');
