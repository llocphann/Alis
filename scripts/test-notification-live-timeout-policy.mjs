#!/usr/bin/env node
// Execute the production timeoutAll body against a deliberate stale
// notification grouping cache; no desktop notifications are sent.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const src=fs.readFileSync(new URL('../services/Notifications.qml',import.meta.url),'utf8');
const anchor='    function timeoutAll() {';
const end='\n    }\n\n    function _isViewLikeAction';
assert.equal(src.split(anchor).length,2,'find one production timeoutAll');
const body=src.split(anchor)[1].split(end)[0];
assert(body.includes('root.list.filter('),'production retraction must read the live source');
const run=new Function('root','triggerListChange',body);
let cases=0;
for(const setup of [
 {names:['fresh'],cached:[],expected:['fresh']},
 {names:['a','b','c'],cached:['a'],expected:['a','b','c']},
 {names:['older'],cached:['unrelated'],expected:['older']},
 {names:[],cached:['already-removed'],expected:[]}
]){
 const live=setup.names.map((id,i)=>({notificationId:id,popup:true,pinned:i===0,summary:'keep-'+id}));
 const history={notificationId:'saved-history',popup:false,pinned:true,summary:'stay'};
 const state={list:[...live,history],popupList:setup.cached.map(id=>({notificationId:id,popup:true})),cancels:[],signals:[],updates:0,
  cancelTimeout(id){this.cancels.push(id)},timeout(id){this.signals.push(id)}};
 const update=()=>{state.updates++};
 run(state,update);
 assert.deepEqual(state.cancels,setup.expected);cases++;
 assert.deepEqual(state.signals,setup.expected);cases++;
 assert(live.every(n=>n.popup===false&&n.summary==='keep-'+n.notificationId));cases++;
 assert.equal(history.popup,false);assert.equal(history.pinned,true);cases++;
 assert.equal(state.list.length,live.length+1);cases++;
 assert.equal(state.updates,live.length?1:0);cases++;
 run(state,update);
 assert.deepEqual(state.cancels,setup.expected);cases++;
 assert.deepEqual(state.signals,setup.expected);cases++;
 assert.equal(state.updates,live.length?1:0);cases++;
}
console.log('NOTIFICATION_LIVE_TIMEOUT_PASS',cases,'source-executed checks');
