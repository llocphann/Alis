#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const file=fileURLToPath(new URL('../modules/dashboard/WeeklyPlannerPolicy.js',import.meta.url));
if(!process.env.PLANNER_ZONE_CASE){
 for(const zone of ['UTC','Asia/Ho_Chi_Minh','America/New_York','Europe/Berlin']){
  const result=spawnSync(process.execPath,[fileURLToPath(import.meta.url)],{env:{...process.env,TZ:zone,PLANNER_ZONE_CASE:'1'},encoding:'utf8'});
  process.stdout.write(result.stdout);process.stderr.write(result.stderr);assert.equal(result.status,0,zone);
 }
 process.exit(0);
}
const p=vm.createContext({});vm.runInContext(fs.readFileSync(file,'utf8'),p);
const local=(id,start,end,extra={})=>({id,title:'task '+id,startDate:start,endDate:end,...extra});
const plain=value=>JSON.parse(JSON.stringify(value));
const week=p.week('2024-12-31T12:00:00',1);assert.equal(week.length,7);assert.equal(week[0].date.getDate(),30);assert.equal(week[6].date.getFullYear(),2025);
assert.equal(p.week('2024-12-31T12:00:00',0)[0].date.getDay(),0);
const items=[local(1,'2024-12-30T09:00:00','2024-12-30T10:00:00'),local(2,'2024-12-30T09:30:00','2024-12-30T11:00:00'),local(3,'2024-12-30T11:00:00','2024-12-30T12:00:00')];
const original=JSON.stringify(items);const projected=p.project(items,[],'2024-12-31T12:00:00',1);
assert.equal(projected[0].timed.length,3);assert.equal(projected[0].timed[0].lanes,2);assert.equal(projected[0].timed[1].lane,1);assert.equal(projected[0].timed[2].lanes,1);assert.equal(JSON.stringify(items),original);
const days=p.project([local(4,'2024-12-30T00:00:00','2025-01-02T00:00:00',{allDay:true})],[local(5,'2024-12-31T23:30:00','2025-01-01T00:30:00')],'2024-12-31T12:00:00',1);
assert.deepEqual(plain(days.map(day=>day.allDay.length)),[1,1,1,0,0,0,0]);assert.equal(days[1].timed[0].source,'external');assert.equal(days[2].timed[0].start,0);assert.equal(days[2].timed[0].end,30);
const daily=p.project([local(6,'2024-12-30T09:00:00','2024-12-30T10:00:00',{recurrence:'daily'})],[],'2024-12-31T12:00:00',1);
assert.equal(daily.reduce((sum,day)=>sum+day.timed.length,0),7);assert.equal(daily[1].timed[0].virtual,true);
const notified=p.project([local(6,'2024-12-30T09:00:00','2024-12-30T10:00:00',{recurrence:'daily',notified:true})],[],'2024-12-31T12:00:00',1);assert.equal(notified.reduce((sum,day)=>sum+day.timed.length,0),1);
const invalid=p.project([local(7,'invalid','invalid')],[],'2024-12-31T12:00:00',1);assert.equal(invalid[0].timed.length,0);
const longDaily=p.project([local(10,'2024-01-01T09:00:00','2024-01-05T09:00:00',{recurrence:'daily'})],[],'2024-12-31T12:00:00',1);
assert.equal(longDaily[0].timed.length,5,'prior multi-day occurrences must reach the visible week');
const monthly=p.project([local(11,'2024-01-15T09:00:00','2024-01-15T10:00:00',{recurrence:'monthly'})],[],'2024-12-15T12:00:00',1);
assert.equal(monthly.reduce((sum,day)=>sum+day.timed.length,0),1);assert.equal(monthly[6].timed[0].startDate.getMonth(),11);
const yearly=p.project([local(12,'2020-12-31T09:00:00','2020-12-31T10:00:00',{recurrence:'yearly'})],[],'2024-12-31T12:00:00',1);
assert.equal(yearly[1].timed.length,1);assert.equal(yearly[1].timed[0].startDate.getFullYear(),2024);
const allDayNoon=p.project([local(13,'2024-12-30T12:00:00','2025-01-01T12:00:00',{allDay:true})],[],'2024-12-31T12:00:00',1);
assert.equal(allDayNoon[0].allDay[0].start,0);assert.equal(allDayNoon[0].allDay[0].virtual,false);assert.equal(allDayNoon[2].allDay.length,0);
const huge=p.project([local(14,'2000-01-01T09:00:00','2040-01-01T09:00:00',{recurrence:'daily'})],[],'2024-12-31T12:00:00',1);
assert.equal(huge[0].projectionLimited,true);assert.equal(huge[0].timed.length,512);assert.ok(huge[0].overflow>0);
for(const [date,zone,minutes] of [['2024-03-10T12:00:00','America/New_York',1380],['2024-11-03T12:00:00','America/New_York',1500],['2024-03-31T12:00:00','Europe/Berlin',1380],['2024-10-27T12:00:00','Europe/Berlin',1500]]){
 const days=p.week(date,0);assert.equal(days.length,7);assert.equal(days[0].minutes,process.env.TZ===zone?minutes:1440);
 for(let i=1;i<7;i++)assert.equal(p.civilIndex(days[i].date)-p.civilIndex(days[i-1].date),1);
}
if(process.env.TZ==='America/New_York'){
 const spring=p.project([local(8,'2024-03-10T01:30:00-05:00','2024-03-10T03:30:00-04:00')],[],'2024-03-10T12:00:00',0)[0].timed[0];assert.equal(spring.end-spring.start,60);
 const fall=p.project([local(9,'2024-11-03T01:30:00-04:00','2024-11-03T01:30:00-05:00')],[],'2024-11-03T12:00:00',0)[0].timed[0];assert.equal(fall.end-fall.start,60);
}
const bounded=p.project(Array.from({length:530},(_,index)=>local(index+1,'2024-12-30T09:00:00','2024-12-30T10:00:00')),[],'2024-12-31T12:00:00',1)[0];assert.equal(bounded.timed.length,512);assert.equal(bounded.overflow,18);
console.log('PASS Weekly Planner civil dates, lanes, multi-day, recurrence, import/immutability, bounds and DST: '+process.env.TZ);
