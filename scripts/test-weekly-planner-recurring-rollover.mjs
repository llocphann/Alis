import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const policy=p=>{const c=vm.createContext({});vm.runInContext(read(p),c);return c;};
const Occurrences=policy('services/EventOccurrences.js');
const RepeatPolicy=policy('services/EventRepeatPolicy.js');
const planner=policy('modules/dashboard/WeeklyPlannerPolicy.js');
const source=read('services/Events.qml');
const fn=source.slice(source.indexOf('function checkDueEvents()'),source.indexOf('function createNextRecurrence('));
class Clock extends Date {constructor(...args){super(...(args.length?args:['2026-10-19T12:00:00']));}}
const slot=(day,notified=true)=>({startDate:`2026-10-${day}T09:00:00`,endDate:`2026-10-${day}T10:00:00`,notified,reminderNotified:true});
for(const [mode,days,count] of [['weekly',['13'],1],['weekly',['13','15'],2],['daily',['13'],1],['none',['13'],0]]){
 const event={id:42,title:'Private fixture',recurrence:mode,occurrences:days.map(d=>slot(d)),custom:{keep:true}};
 const root={ready:true,list:[event],saves:0,saveToFile(){this.saves++;},eventTriggered(){},reminderTriggered(){},createNextRecurrence(){throw Error('must retain the original ID');}};
 const context=vm.createContext({root,Occurrences,RepeatPolicy,Date:Clock});vm.runInContext(fn+';checkDueEvents();',context);
 assert.equal(root.list.length,1);assert.equal(root.list[0].id,42);assert.equal(root.list[0].custom.keep,true);
 assert.equal(root.list[0].occurrences.length,days.length+count);
 assert.ok(root.list[0].occurrences.slice(0,days.length).every(s=>s.notified));
 const before=JSON.stringify(root.list);vm.runInContext('checkDueEvents()',context);assert.equal(JSON.stringify(root.list),before,'no duplicate cycle on repeated ticks');
 const rows=planner.project(root.list,[],'2026-10-19T12:00:00',1).flatMap(d=>d.timed);
 if(mode==='weekly'){assert.equal(rows.length,count);assert.equal(JSON.stringify(rows.map(r=>r.startDate.getDay())),JSON.stringify(days.length===1?[2]:[2,4]));}
 if(mode==='none')assert.equal(rows.length,0);
 if(mode!=='none')assert.ok(root.list[0].occurrences.slice(days.length).every(s=>new Date(s.startDate)>new Clock()));
}
console.log('PASS actual Events due-handler recovery, stable IDs/history, idempotent rollover and next-week projection');
