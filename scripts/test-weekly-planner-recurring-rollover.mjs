import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
if(!process.env.PLANNER_ROLLOVER_ZONE_CASE){
 for(const zone of ['UTC','Asia/Ho_Chi_Minh','America/New_York','Europe/Berlin']){
  const result=spawnSync(process.execPath,[fileURLToPath(import.meta.url)],{
   env:{...process.env,TZ:zone,PLANNER_ROLLOVER_ZONE_CASE:'1'},encoding:'utf8'});
  process.stdout.write(result.stdout);process.stderr.write(result.stderr);
  assert.equal(result.status,0,zone);
 }
 process.exit(0);
}
const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const policy=p=>{const c=vm.createContext({});vm.runInContext(read(p),c);return c;};
const Occurrences=policy('services/EventOccurrences.js');
const RepeatPolicy=policy('services/EventRepeatPolicy.js');
const FutureSchedule=policy('services/EventFutureSchedule.js');
const planner=policy('modules/dashboard/WeeklyPlannerPolicy.js');
const source=read('services/Events.qml');
const fn=source.slice(source.indexOf('function checkDueEvents()'),source.indexOf('function createNextRecurrence('));
class Clock extends Date {constructor(...args){super(...(args.length?args:['2026-10-19T12:00:00']));}}
const slot=(day,notified=true)=>({startDate:`2026-10-${day}T09:00:00`,endDate:`2026-10-${day}T10:00:00`,notified,reminderNotified:true});
for(const [mode,days,count] of [['weekly',['13'],1],['weekly',['13','15'],2],['daily',['13'],1],['none',['13'],0]]){
 const event={id:42,title:'Private fixture',recurrence:mode,occurrences:days.map(d=>slot(d)),custom:{keep:true}};
 const root={ready:true,list:[event],saves:0,saveToFile(){this.saves++;},eventTriggered(){},reminderTriggered(){},createNextRecurrence(){throw Error('must retain the original ID');}};
 const context=vm.createContext({root,Occurrences,RepeatPolicy,FutureSchedule,Date:Clock});vm.runInContext(fn+';checkDueEvents();',context);
 assert.equal(root.list.length,1);assert.equal(root.list[0].id,42);assert.equal(root.list[0].custom.keep,true);
 assert.equal(root.list[0].occurrences.length,days.length+count);
 assert.ok(root.list[0].occurrences.slice(0,days.length).every(s=>s.notified));
 const before=JSON.stringify(root.list);vm.runInContext('checkDueEvents()',context);assert.equal(JSON.stringify(root.list),before,'no duplicate cycle on repeated ticks');
 const rows=planner.project(root.list,[],'2026-10-19T12:00:00',1).flatMap(d=>d.timed);
 if(mode==='weekly'){assert.equal(rows.length,count);assert.equal(JSON.stringify(rows.map(r=>r.startDate.getDay())),JSON.stringify(days.length===1?[2]:[2,4]));}
 if(mode==='none')assert.equal(rows.length,0);
 if(mode!=='none')assert.ok(root.list[0].occurrences.slice(days.length).every(s=>new Date(s.startDate)>new Clock()));
}
// A converted series may retain old fired cycles beside an explicitly chosen
// single active date. Do not infer the repeat pattern from archived dates.
{
 const active=slot('13');
 const event={id:71,title:'Selected date fixture',recurrence:'weekly',
  occurrences:[slot('06'),active],selectedTemplate:[active]};
 const root={ready:true,list:[event],saveToFile(){},eventTriggered(){},reminderTriggered(){}};
 const context=vm.createContext({root,Occurrences,RepeatPolicy,FutureSchedule,Date:Clock});
 vm.runInContext(fn+';checkDueEvents();',context);
 assert.equal(root.list[0].occurrences.length,3,'selected single date must roll over without losing history');
 assert.equal(root.list[0].repeatTemplate.length,1,'history must not become part of the pattern');
 assert.equal(root.list[0].repeatCycleStart,2);
 assert.equal(planner.project(root.list,[],'2026-10-19T12:00:00',1).flatMap(d=>d.timed).length,1);
 const edit=source.slice(source.indexOf('function updateEventGroup('),source.indexOf('// Reschedule one stored occurrence.'));
 root.eventUpdated=()=>{};
 vm.runInContext(edit,context);
 const selected=[root.list[0].occurrences.at(-1)];
 const fields={title:'Selected fixture',recurrence:'none'};
 assert.equal(context.updateEventGroup(71,fields,selected),true);
 assert.equal(root.list[0].occurrences.length,3);
 fields.recurrence='weekly';
 assert.equal(context.updateEventGroup(71,fields,selected),true);
 assert.equal(root.list[0].occurrences.length,3,'switching Weekly back on must preserve fired history');
 assert.equal(root.list[0].repeatCycleStart,2);
}
const dstStart=new Date(2026,9,25,9),dstEnd=new Date(2026,9,25,10);
const next=RepeatPolicy.nextCycle([{startDate:dstStart,endDate:dstEnd}],
 'weekly',new Date(2026,9,26,12));
assert.equal(new Date(next[0].startDate).getHours(),9,'civil start time across DST');
assert.equal(new Date(next[0].startDate).getDate(),1);
assert.equal(new Date(next[0].endDate).getHours(),10);
console.log('PASS actual Events due-handler recovery, stable IDs/history, idempotent rollover and next-week projection: '+process.env.TZ);
