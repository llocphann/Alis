#!/usr/bin/env node
// Synthetic pre-patch storage, public gesture policy and copy-on-write parity.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';
if (!process.env.PLANNER_MULTIDATE_ZONE_CASE) {
  for (const zone of ['UTC','Asia/Ho_Chi_Minh','America/New_York','Europe/Berlin']) {
    const result=spawnSync(process.execPath,[new URL(import.meta.url).pathname],{
      env:{...process.env,TZ:zone,PLANNER_MULTIDATE_ZONE_CASE:'1'},encoding:'utf8'});
    process.stdout.write(result.stdout);process.stderr.write(result.stderr);
    if(result.status!==0)process.exitCode=1;
  }
  process.exit(process.exitCode || 0);
}
const root=process.env.ALIS_PLANNER_SOURCE_ROOT || new URL('../',import.meta.url).pathname;
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
function load(p) { const s=vm.createContext({Date,Set,Map,Array,Object,Math,Number,String,JSON});
  vm.runInContext(read(p),s);return s; }
const S=load('modules/dashboard/PlannerSelection.js'),G=load('modules/dashboard/PlannerGesture.js');
const P=load('modules/dashboard/WeeklyPlannerPolicy.js'),O=load('services/EventOccurrences.js');
let passed=0,failed=0;
function test(name,fn) {try {fn();passed++;}catch(e){failed++;console.error('FAIL',name,e.message);}}
const plain=v=>JSON.parse(JSON.stringify(v));
const slot=(day,extra={})=>({startDate:`2032-10-${day}T09:00:00.000Z`,
  endDate:`2032-10-${day}T10:00:00.000Z`,notified:false,reminderNotified:true,...extra});
const legacy={id:41,title:'Synthetic pre-template weekly',recurrence:'weekly',
  occurrences:[slot('19',{retainedSlot:{value:3}}),slot('21')],
  createdAt:'2020-01-01T00:00:00Z',todoLink:{key:'retained'},ownerExtra:{value:7}};
const snapshot=JSON.stringify(legacy);
const rows=(e,date='2032-10-19T12:00:00Z')=>P.project([e],[],date,1).flatMap(d=>d.timed);
const saved=rows(legacy).find(r=>r.occurrenceIndex===0 && !r.virtual);
const virtual=rows(legacy,'2032-10-26T12:00:00Z').find(r=>r.occurrenceIndex===0 && r.virtual);
test('legacy multi-slot saved eligibility',()=>assert.ok(S.canReschedule(saved)));
test('legacy multi-slot projected eligibility',()=>assert.ok(S.canReschedule(virtual)));
test('Qt delegate sequence view is editable without converting canonical storage',()=>{
  const slots=Object.assign({length:legacy.occurrences.length},legacy.occurrences);
  assert.equal(Array.isArray(slots),false);
  const row={...saved,event:{...legacy,occurrences:slots}};
  assert.ok(S.canReschedule(row));
  assert.ok(G.rangeForGesture(row,'bottom',0,13,102,52));
  assert.equal(JSON.stringify(legacy),snapshot);
});
for(const mode of ['move','top','bottom']) {
  test('legacy '+mode,()=>{
    const range=G.rangeForGesture(saved,mode,0,13,102,52);assert.ok(range);
    const changed=O.rescheduleSavedRecurring(legacy,0,range.startIso,range.endIso);
    assert.ok(changed);assert.equal(JSON.stringify(legacy),snapshot);
    assert.deepEqual(plain(changed.occurrences[1]),plain(legacy.occurrences[1]));
    for(const key of ['id','title','createdAt','todoLink','ownerExtra','repeatTemplate'])
      assert.deepEqual(plain(changed[key] ?? null),plain(legacy[key] ?? null));
    assert.deepEqual(plain(changed.occurrences[0].retainedSlot),{value:3});
    assert.equal(changed.occurrences[0].reminderNotified,true);
    const reloaded=JSON.parse(JSON.stringify(O.store(changed,O.entries(changed))));
    assert.deepEqual(reloaded.occurrences[0].retainedSlot,{value:3});
    assert.equal(reloaded.occurrences[0].plannerSeriesStartDate,legacy.occurrences[0].startDate);
    assert.equal(rows(reloaded).filter(r=>!r.virtual && r.occurrenceIndex===0).length,1);
    assert.ok(rows(reloaded,'2032-10-26T12:00:00Z').some(r=>r.occurrenceIndex===0
      && r.startDate.toISOString()==='2032-10-26T09:00:00.000Z'));
    assert.equal(O.rescheduleSavedRecurring(reloaded,0,range.startIso,range.endIso),null);
  });
}
test('moving past another slot retains indices through persistence',()=>{
  const changed=O.rescheduleSavedRecurring(legacy,0,'2032-10-22T09:00:00Z','2032-10-22T10:00:00Z');
  assert.ok(changed);
  const saved=O.store(changed,O.entries(changed));
  assert.equal(saved.occurrences[0].startDate,'2032-10-22T09:00:00.000Z');
  assert.equal(saved.occurrences[1].startDate,legacy.occurrences[1].startDate);
  assert.deepEqual(plain(saved.occurrences[0].retainedSlot),{value:3});
  assert.equal(O.upcoming(saved,'2032-10-18T00:00:00Z','2032-10-24T00:00:00Z').startDate,
    legacy.occurrences[1].startDate,'upcoming must remain chronological after indices stop sorting');
});
test('multi-day span keeps full duration and shared identity for its own fragments',()=>{
  const span={id:90,title:'Synthetic overnight',startDate:'2032-10-19T23:00:00Z',
    endDate:'2032-10-21T01:00:00Z',recurrence:'weekly'};
  const fragments=rows(span);assert.ok(fragments.length>=2);
  assert.equal(new Set(fragments.map(gestureKey)).size,1);
  const range=G.rangeForGesture(fragments[0],'move',102,13,102,52);assert.ok(range);
  assert.equal(new Date(range.endIso)-new Date(range.startIso),26*3600000);
});
test('projected legacy exception can be edited repeatedly and reloaded',()=>{
  const range=G.rangeForGesture(virtual,'bottom',0,13,102,52);assert.ok(range);
  const edit=O.rescheduleProjectedRecurring(legacy,0,virtual.plannerOriginalStartIso,range.startIso,range.endIso);
  assert.ok(edit);assert.equal(edit.plannerOverrides.length,1);
  const saved=JSON.parse(JSON.stringify(edit));
  const again=O.rescheduleProjectedRecurring(saved,0,virtual.plannerOriginalStartIso,range.startIso,
    new Date(new Date(range.endIso).getTime()+15*60000).toISOString());
  assert.equal(again.plannerOverrides.length,1);
  assert.deepEqual(plain(again.occurrences),plain(legacy.occurrences));
  assert.equal(rows(again,'2032-10-26T12:00:00Z').filter(r=>r.occurrenceIndex===0).length,1);
});
function gestureKey(r) {return typeof S.gestureKey==='function' ? S.gestureKey(r) : S.key(r);}
test('recurring gesture has a nonempty key',()=>assert.ok(gestureKey(saved)));
test('another event never shares preview',()=>assert.notEqual(gestureKey(saved),gestureKey({...saved,event:{...legacy,id:42}})));
test('another slot never shares preview',()=>assert.notEqual(gestureKey(saved),gestureKey({...saved,occurrenceIndex:1})));
test('another cycle never shares preview',()=>assert.notEqual(gestureKey(saved),gestureKey(virtual)));
test('original virtual key survives edited time',()=>assert.equal(gestureKey(virtual),gestureKey({...virtual,
  startDate:new Date('2032-10-27T10:00:00Z')})));
test('invalid/imported rows have no gesture identity',()=>{
  assert.equal(gestureKey({...saved,source:'external'}),'');assert.equal(gestureKey(null),'');
});
test('recurring events still excluded from batch selection/delete',()=>assert.equal(S.canSelect(saved),false));
test('bad input cannot mutate legacy store',()=>{
  for(const index of [-1,2,1.5])assert.equal(O.rescheduleSavedRecurring(legacy,index,
    '2032-10-20T09:00:00Z','2032-10-20T10:00:00Z'),null);
  assert.equal(O.rescheduleSavedRecurring(legacy,0,'invalid','invalid'),null);
  assert.equal(JSON.stringify(legacy),snapshot);
});
test('fresh default and mixed old/new projection do not write',()=>{
  assert.equal(P.project([],[],'2032-10-19',1).flatMap(d=>d.timed).length,0);
  const modern={...legacy,id:43,repeatTemplate:plain(legacy.occurrences),repeatCycleStart:0};
  const mixed=[legacy,modern],before=JSON.stringify(mixed);
  const all=P.project(mixed,[],'2032-10-19',1).flatMap(d=>d.timed);
  assert.equal(all.length,4);assert.equal(JSON.stringify(mixed),before);
  assert.equal(new Set(all.map(gestureKey)).size,4);
});
test('all-day batch target eligibility remains available',()=>{
  const row={...saved,event:{id:5,allDay:true,recurrence:'none'}};
  assert.ok(S.canSelect(row));assert.ok(gestureKey(row));
  const ui=read('modules/dashboard/DashboardWeeklyPlanner.qml');
  const body=ui.split('function gestureTargets(row)')[1].split('function clickPlannerEvent')[0];
  assert.ok(body.includes('Selection.canSelect(row)'), 'all-day move must reach its existing batch backend');
});
test('UI previews use gesture identity, not empty batch-selection identity',()=>{
  const ui=read('modules/dashboard/DashboardWeeklyPlanner.qml');
  assert.ok(ui.includes('targets.map(row=>Selection.gestureKey(row))'));
  assert.ok(ui.includes('includes(Selection.gestureKey(modelData))'));
});
test('cycle rollover materializes exceptions once, preserving legacy IDs and pending edits',()=>{
  const source=read('services/Events.qml');
  const functions=source.slice(source.indexOf('function checkDueEvents()'),source.indexOf('function updateEventGroup('));
  const RepeatPolicy=load('services/EventRepeatPolicy.js');
  class Clock extends Date {constructor(...a){super(...(a.length?a:['2032-10-25T12:00:00Z']));}}
  const later=new Date('2032-10-26T09:00:00.000Z');later.setDate(later.getDate()+7);
  const laterEnd=new Date(later.getTime()+3600000);
  const laterStart=later.toISOString();later.setMinutes(later.getMinutes()+30);
  laterEnd.setMinutes(laterEnd.getMinutes()+30);
  for(const grouped of [true,false]) {
    const event=grouped ? plain(legacy) : {...slot('19'),id:41,title:'Synthetic old single',recurrence:'weekly'};
    let edited=O.rescheduleProjectedRecurring(event,0,'2032-10-26T09:00:00.000Z',
      '2032-10-26T09:15:00.000Z','2032-10-26T10:15:00.000Z');
    assert.ok(edited);
    edited=O.rescheduleProjectedRecurring(edited,0,laterStart,
      later.toISOString(),laterEnd.toISOString());
    assert.ok(edited);
    const root={ready:true,list:[edited],nextId:500,saves:0,saveToFile(){this.saves++;},
      eventTriggered(){},reminderTriggered(){},eventAdded(){}};
    const context=vm.createContext({root,Occurrences:O,RepeatPolicy,Date:Clock,Number,Math});
    vm.runInContext(functions,context);root.addEvent=context.addEvent;root.createNextRecurrence=context.createNextRecurrence;
    context.checkDueEvents();
    assert.equal(root.saves,1,'rollover must persist old receipt and new destination in one snapshot');
    assert.equal(root._checkingDue,false);
    assert.equal(root.list[0].id,41);
    assert.equal(root.list.length,grouped?1:2,'legacy separate-ID behavior changed');
    const week=P.project(root.list,[],'2032-10-26T12:00:00Z',1).flatMap(d=>d.timed);
    const corrected=week.filter(r=>r.startDate.toISOString()==='2032-10-26T09:15:00.000Z');
    assert.equal(corrected.length,1,'rollover lost or duplicated edited occurrence');
    assert.ok(!week.some(r=>r.startDate.toISOString()==='2032-10-26T09:00:00.000Z'));
    const future=P.project(root.list,[],'2032-11-02T12:00:00Z',1).flatMap(d=>d.timed);
    assert.equal(future.filter(r=>r.startDate.toISOString()===later.toISOString()).length,1,
      'pending exception lost or duplicated during legacy handoff');
    const before=JSON.stringify(root.list);context.checkDueEvents();
    assert.equal(JSON.stringify(root.list),before,'repeated tick duplicated materialized exceptions');
    assert.equal(root.saves,1);
  }
});
console.log(JSON.stringify({test:'multidate-gestures',zone:process.env.TZ,passed,failed,source_root:root}));
process.exitCode=failed ? 1 : 0;
