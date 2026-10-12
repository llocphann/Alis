#!/usr/bin/env node
// Execute the production markAllRead body with modern/legacy counters.
// Never access a real session's notifications, clipboard or configuration.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';

const source=readFileSync(new URL('../services/Notifications.qml',import.meta.url),'utf8');
const anchor='    function markAllRead() {';
const ending='\n    }\n\n    function discardNotification';
assert.equal(source.split(anchor).length,2,'one markAllRead implementation');
const body=source.split(anchor)[1].split(ending)[0];
const run=new Function('root','Config','triggerListChange',body);
let checks=0;

for(const legacy of [false,true]){
 for(const count of [0,1,3]){
  const live=Array.from({length:count},(_,i)=>({
   notificationId:'live-'+i,popup:true,timer:{running:true},
   summary:'retain '+i,pinned:i===0
  }));
  const old={notificationId:'history',popup:false,summary:'existing history',pinned:true};
  const root={list:[...live,old],popupList:[],
   _manualUnreadCounter:7,cancels:[],
   cancelTimeout(id){
    this.cancels.push(id);
    const n=this.list.find(v=>v.notificationId===id);
    if(n)n.timer=null;
   }};
  const config={options:{notifications:{useLegacyCounter:legacy}}};
  let refreshes=0;
  const refresh=()=>refreshes++;
  run(root,config,refresh);
  assert.deepEqual(root.cancels,live.map(n=>n.notificationId),'cancel live timers');checks++;
  assert(live.every(n=>n.popup===false&&n.timer===null),'mark all live read');checks++;
  assert.equal(root._manualUnreadCounter,legacy?0:7,'legacy counter only');checks++;
  assert.equal(refreshes,count>0?1:0,'refresh only on change');checks++;
  assert.equal(root.list.length,count+1,'history preserved');checks++;
  assert.deepEqual([old.popup,old.summary,old.pinned],[false,'existing history',true],'stored item unchanged');checks++;
  run(root,config,refresh);
  assert.equal(root.cancels.length,count,'repeat cannot cancel twice');checks++;
  assert.equal(refreshes,count>0?1:0,'repeat cannot repaint');checks++;
 }
}
console.log('NOTIFICATION_READ_POLICY_PASS',checks,'source-executed checks');
