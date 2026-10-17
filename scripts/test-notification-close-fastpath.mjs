#!/usr/bin/env node
// Execute actual production functions on a synthetic expired popup. No D-Bus,
// timers, disk writes, settings, compositor or user notifications are touched.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const source=read('services/Notifications.qml');
const group=read('modules/common/widgets/NotificationGroup.qml');
const host=read('modules/abyss/AbyssBodyHost.qml');
const perimeter=read('modules/abyss/AbyssPerimeter.qml');
const method=name=>{
 const prefix='    function '+name+'(';
 const start=source.indexOf(prefix);
 assert.ok(start>=0 && source.indexOf(prefix,start+1)<0,'exactly one '+name);
 const open=source.indexOf('{',start);
 let depth=0;
 for(let i=open;i<source.length;i++){
  if(source[i]==='{')depth++;
  else if(source[i]==='}' && --depth===0) return source.slice(start,i+1).replace(/\)\s*:\s*(?:void|var)\s*\{/g,') {');
 }
 throw Error('unclosed '+name);
};
const names=['_updatePopupGroups','triggerPopupListChange','timeoutNotification'];
const make=new Function('root','_groupsForListOptimized','_appNameListForGroups',
 names.map(method).join('\n')+'\nreturn {'+names.join(',')+'};');
let checks=0;
const check=(label,fn)=>{fn();checks++;};
const history=Array.from({length:2000},(_,i)=>({notificationId:i+100,
 appName:'History',time:i+1,popup:false}));
const first={notificationId:1,appName:'Recorder',time:3000,popup:true};
const second={notificationId:2,appName:'Recorder',time:3001,popup:true};
const historyGroups={History:{notifications:history}};
const historyKeys=['History'];
let fullRebuilds=0,popupGroupCalls=0;
const root={list:[...history,first,second],popupList:[first,second],
 _groupsDirty:false,_cachedGroupsByAppName:historyGroups,
 _cachedAppNameList:historyKeys,_cachedPopupGroupsByAppName:{},
 _cachedPopupAppNameList:['Recorder'],latestTimeForApp:{Recorder:3001},
 cancelled:[],timedOut:[],
 cancelTimeout(id){this.cancelled.push(id)},
 timeout(id){this.timedOut.push(id)},
 _updateGroups(){fullRebuilds++}};
const grouped=list=>{popupGroupCalls++;
 assert.ok(list.length<=2,'closing must never rebuild the large history cache');
 const out=Object.create(null);
 for(const n of list)(out[n.appName]??={notifications:[]}).notifications.push(n);
 return out;
};
const sorted=groups=>Object.keys(groups);
const real=make(root,grouped,sorted);
root._updatePopupGroups=real._updatePopupGroups;
real.timeoutNotification(1);
check('first timeout changes only the live popup',()=>{
 assert.equal(first.popup,false);assert.equal(second.popup,true);
 assert.deepEqual(root.popupList,[second]);
 assert.deepEqual(root.cancelled,[1]);assert.deepEqual(root.timedOut,[1]);
});
check('history cache keeps identity and is never regrouped',()=>{
 assert.equal(fullRebuilds,0);assert.equal(popupGroupCalls,1);
 assert.equal(root._cachedGroupsByAppName,historyGroups);
 assert.equal(root._cachedAppNameList,historyKeys);
});
real.timeoutNotification(2);
check('last popup disappears without recomputing history',()=>{
 assert.deepEqual(root.popupList,[]);
 assert.deepEqual(root._cachedPopupAppNameList,[]);
 assert.equal(fullRebuilds,0);assert.equal(popupGroupCalls,2);
 assert.deepEqual(root.timedOut,[1,2]);
});
root._groupsDirty=true;
const fresh={notificationId:3,appName:'Recorder',time:3100,popup:true};
root.list.push(fresh);
real.timeoutNotification(3);
check('initial grouping race falls back to authoritative full rebuild',()=>{
 assert.equal(fullRebuilds,1);assert.equal(popupGroupCalls,2);
 assert.equal(fresh.popup,false);assert.deepEqual(root.timedOut,[1,2,3]);
});
check('other list-change paths keep their full rebuild contract',()=>{
 assert.ok(method('triggerListChange').includes('root._groupsDirty = true'));
 assert.ok(method('triggerListChange').includes('root._updateGroups()'));
 assert.ok(method('timeoutAll').includes('root.list.filter('));
 assert.ok(method('discardNotification').includes('triggerListChange()'));
});
check('ScriptModel uses stable unique notification ID on live/snapshot swap',()=>{
 assert.ok(group.includes('objectProp: "notificationId"'));
 assert.ok(group.includes('values: root.expanded ? root.notifications.slice().reverse()'));
 const live={notificationId:50,summary:'Recorder'};
 const snapshot={notificationId:50,summary:'Recorder'};
 assert.equal(live.notificationId,snapshot.notificationId);
 assert.notEqual(live,snapshot);
});
check('zero-end-speed retract is notification-only and never double-fades',()=>{
 assert.ok(perimeter.includes('monotonicNotificationReveal: true'));
 assert.ok(host.includes('root.monotonicNotificationReveal && !root.presented'));
 assert.ok(host.includes('? Easing.InOutSine'));
 assert.ok(host.includes('root.presented ? Easing.OutCubic : Easing.InCubic'));
 assert.ok(host.includes('root.pyramidPresentationActive || root.monotonicNotificationReveal'));
 const oldSpeedEnd=3; // normalized slope of InCubic at t=1
 const sineSpeedEnd=Math.PI/2*Math.sin(Math.PI); // InOutSine derivative
 assert.ok(Math.abs(sineSpeedEnd)<1e-10 && oldSpeedEnd>2.9);
 assert.ok(!host.includes('interval: 228'),'animation durations stay in AbyssStyle');
});
console.log('PASS: '+checks+' production Notification close fast-path/identity/motion cases');
