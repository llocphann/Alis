#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const ownRoot=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const root=process.env.ALIS_PLANNER_SOURCE_ROOT || ownRoot;
function load(rel,base=root) {
 const ctx=vm.createContext({Date,Array,Object,Math,Set,Map,Number,String,JSON});
 vm.runInContext(fs.readFileSync(path.join(base,rel),'utf8'),ctx);return ctx;
}
const F=load('services/EventFutureSchedule.js',ownRoot);
const O=load('services/EventOccurrences.js'), B=load('services/EventBatchPolicy.js');
const P=load('modules/dashboard/WeeklyPlannerPolicy.js');
const stamp=(y,m,d,h=9,min=0)=>new Date(y,m-1,d,h,min).toISOString();
const slot=(y,m,d,h=9)=>({startDate:stamp(y,m,d,h),endDate:stamp(y,m,d,h+1),
 notified:false,reminderNotified:false,ownerSlot:{retained:d}});
const rows=(event,day)=>P.project([event],[],day,1,F).flatMap(d=>d.timed);
let checks=0;
function check(value,message){checks++;assert.ok(value,message);}
function edit(event,index,start,end,now,extra={}) {
 const op={id:event.id,occurrenceIndex:index,recurring:true,future:true,
  startIso:start,endIso:end,...extra};
 const result=B.apply([event],[op],O,F,now);
 check(result,'forward edit was rejected');return result.list[0];
}
const history=[{...slot(2032,10,5),notified:true},{...slot(2032,10,7),notified:true}];
const event={id:41,title:'Synthetic Tue/Thu',recurrence:'weekly',
 occurrences:history.concat([slot(2032,10,19),slot(2032,10,21),slot(2032,10,26),slot(2032,10,28)]),
 repeatTemplate:history.map(s=>({startDate:s.startDate,endDate:s.endDate})),repeatCycleStart:2,
 todoLink:{key:'retain'},owner:{keep:7}};
const raw=JSON.stringify(event), now=stamp(2032,10,18,12);
const moved=edit(event,2,stamp(2032,10,19,17),stamp(2032,10,19,18),now);
check(Array.isArray(moved.plannerFutureSchedule),'Planner must save a forward rule, not only one exception');
check(JSON.stringify(event)===raw,'input was mutated');
assert.deepEqual(JSON.parse(JSON.stringify(moved.occurrences.slice(0,2))),history);checks++;
check(moved.occurrences[4].startDate===stamp(2032,10,26,17),'already-saved next Tuesday did not follow');
check(moved.occurrences[3].startDate===event.occurrences[3].startDate
 && moved.occurrences[5].startDate===event.occurrences[5].startDate,'Thursday branch changed');
check(rows(moved,stamp(2032,11,2)).some(r=>r.startDate.toISOString()===stamp(2032,11,2,17)),
 'virtual next month did not follow Tuesday');
check(rows(moved,stamp(2032,11,2)).some(r=>r.startDate.toISOString()===stamp(2032,11,4,9)),
 'another weekday lost its own clock');
check(JSON.stringify(moved.repeatTemplate)===JSON.stringify(event.repeatTemplate),'original template changed');
check(moved.todoLink.key==='retain' && moved.owner.keep===7,'user fields lost');
const future=rows(moved,stamp(2032,11,2)).find(r=>r.startDate.toISOString()===stamp(2032,11,2,17));
const resized=edit(moved,future.occurrenceIndex,stamp(2032,11,2,17),stamp(2032,11,2,19),now,{
 originalStartIso:future.plannerOriginalStartIso,branchKey:future.plannerBranchKey,cycle:future.plannerScheduleCycle});
check(rows(resized,stamp(2032,11,9)).some(r=>r.startDate.toISOString()===stamp(2032,11,9,17)
 && r.endDate.toISOString()===stamp(2032,11,9,19)),'projected resize did not propagate');
check(rows(resized,stamp(2032,10,26)).some(r=>r.startDate.toISOString()===stamp(2032,10,26,17)
 && r.endDate.toISOString()===stamp(2032,10,26,18)),'later resize rewrote an earlier week');
const reloaded=JSON.parse(JSON.stringify(resized));
check(JSON.stringify(F.project(reloaded,stamp(2032,11,8),stamp(2032,11,15)))
 ===JSON.stringify(F.project(resized,stamp(2032,11,8),stamp(2032,11,15))),'restart changed projection');
const beforeFailure=JSON.stringify(resized);
check(B.apply([resized],[{id:41,occurrenceIndex:2,recurring:true,future:true,
 startIso:'invalid',endIso:stamp(2032,10,19,18)}],O,F,now)===null,'invalid operation accepted');
check(JSON.stringify(resized)===beforeFailure,'failed batch changed data');
for(const mode of ['daily','weekly','monthly','yearly']) {
 const original=slot(2032,1,15);
 const old={id:55,recurrence:mode,...original,owner:{keep:mode}};
 const adjusted=edit(old,0,stamp(2032,1,15,10),stamp(2032,1,15,11,30),stamp(2032,1,14));
 const next=F.nextCycle(adjusted,stamp(2032,1,15,12));
 check(next?.length===1 && new Date(next[0].startDate).getHours()===10
  && new Date(next[0].endDate).getHours()===11
  && new Date(next[0].endDate).getMinutes()===30,mode+' rollover clock/duration lost');
 check(adjusted.owner.keep===mode && !adjusted.occurrences,'legacy shape/metadata lost');
 check(adjusted.dateTime===adjusted.startDate,'legacy dateTime compatibility alias stale');
}
// A changed monthly day or leap date has its NEW calendar cadence, rather
// than inheriting a skipped February from the superseded 31st/29th rule.
const month={id:61,recurrence:'monthly',...slot(2032,1,31)};
const monthEdit=edit(month,0,stamp(2032,1,20),stamp(2032,1,20,10),stamp(2032,1,1));
check(F.nextCycle(monthEdit,stamp(2032,1,31,12))[0].startDate===stamp(2032,2,20),
 'new monthly day disappeared in a short month');
const leap={id:62,recurrence:'yearly',...slot(2032,2,29)};
const leapEdit=edit(leap,0,stamp(2032,2,28),stamp(2032,2,28,10),stamp(2032,2,1));
check(F.nextCycle(leapEdit,stamp(2032,3,1))[0].startDate===stamp(2033,2,28),
 'new yearly day retained the old leap-year skip');
const daily={id:63,recurrence:'daily',occurrences:[slot(2032,10,19),slot(2032,10,20)]};
const grouped=B.apply([daily],[0,1].map((index)=>({id:63,occurrenceIndex:index,
 recurring:true,future:true,startIso:stamp(2032,10,19+index,10),endIso:stamp(2032,10,19+index,11)})),O,F,now);
check(grouped?.list[0].plannerFutureSchedule.length===1,'one group gesture compounded a branch rule');
check(F.nextCycle(grouped.list[0],stamp(2032,10,21,12))[0].startDate===stamp(2032,10,22,10),
 'daily group applied a delta multiple times');
const exception={occurrenceIndex:2,originalStartDate:stamp(2032,11,2),
 startDate:stamp(2032,11,2,9,30),endDate:stamp(2032,11,2,10,30),ownerReceipt:{keep:1}};
const consumed={...exception,originalStartDate:stamp(2032,10,12),materializedOccurrenceIndex:0};
const withExceptions={...event,plannerOverrides:[exception,consumed]};
const followed=edit(withExceptions,2,stamp(2032,10,19,10),stamp(2032,10,19,11),now);
check(followed.plannerOverrides[0].startDate===stamp(2032,11,2,10,30)
 && followed.plannerOverrides[0].ownerReceipt.keep===1,'future exception offset/metadata lost');
check(JSON.stringify(followed.plannerOverrides[1])===JSON.stringify(consumed),'consumed receipt rewritten');
check(rows(followed,stamp(2032,11,2)).some(r=>r.startDate.toISOString()===stamp(2032,11,2,10,30)),
 'projection ignored the retained future exception');
const rolled=F.nextCycle(followed,stamp(2032,10,29));
const materialized=O.materializeProjectedRecurring(followed,rolled,6,41);
check(materialized.slots.some(s=>s.startDate===stamp(2032,11,2,10,30))
 && materialized.overrides[0].materializedOccurrenceIndex===6,'rollover lost or duplicated future exception');
const pastNow=stamp(2032,10,29);
const pastEdit=edit(event,2,stamp(2032,10,19,11),stamp(2032,10,19,12),pastNow);
check(JSON.stringify(pastEdit.occurrences[4])===JSON.stringify(event.occurrences[4]),
 'editing historical Tuesday rewrote another past Tuesday');
check(rows(pastEdit,stamp(2032,11,2)).some(r=>r.startDate.toISOString()===stamp(2032,11,2,11)),
 'historical direct edit did not update future Tuesday');
check(B.apply([event],[{id:41,occurrenceIndex:2,recurring:true,future:true,
 startIso:stamp(2032,10,19,10),endIso:stamp(2032,10,19,11)},
 {id:999,occurrenceIndex:0,startIso:stamp(2032,10,19),endIso:stamp(2032,10,19,10)}],O,F,now)===null,
 'unknown mixed batch must roll back every forward rule');
const differentClocks=JSON.parse(raw);
for(const index of [3,5]) {
 const d=new Date(differentClocks.occurrences[index].startDate);
 d.setHours(18,30,0,0);differentClocks.occurrences[index].startDate=d.toISOString();
 d.setHours(20,0,0,0);differentClocks.occurrences[index].endDate=d.toISOString();
}
const independent=edit(differentClocks,2,stamp(2032,10,19,17),stamp(2032,10,19,18),now);
const nextGroup=F.nextCycle(independent,stamp(2032,10,29));
check(nextGroup.length===2 && nextGroup[0].startDate===stamp(2032,11,2,17)
 && nextGroup[1].startDate===stamp(2032,11,4,18,30),
 'different per-day clocks misaligned the next grouped cycle');
check(F.project({...daily,occurrences:undefined,...slot(2032,10,19),
 plannerFutureSchedule:grouped.list[0].plannerFutureSchedule,notified:true},
 stamp(2032,10,18),stamp(2032,10,25)).length===1,
 'retired legacy parent projected duplicates beside its child');
console.log('PLANNER_FUTURE_SCHEDULE_PASS',checks,process.env.TZ || 'system');
