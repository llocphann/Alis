#!/usr/bin/env node
// Actual QML service functions executed with representative Dock identities.
// Zero host notification, clipboard, database or timer operations.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../services/Notifications.qml',import.meta.url),'utf8');
function body(start,end) {
 assert.equal(source.split(start).length,2,'expected unique '+start);
 const chunk=source.split(start)[1].split(end)[0];
 assert(chunk.length>0,'missing body for '+start);
 return chunk;
}
const normalize=new Function('name',body(
 '    function _normalizeAppKey(name): string {',
 '\n    }\n\n    // App names whose group'));
const count=new Function('identifiers','root',body(
 '    function countForApp(identifiers): int {',
 '\n    }\n\n    function markReadForApp'));
const markRead=new Function('identifiers','root','cancelTimeout','triggerListChange',body(
 '    function markReadForApp(identifiers) {',
 '\n    }\n\n    // Public API'));
const list=[
 {notificationId:1,appName:'Alpha App',popup:true},
 {notificationId:2,appName:'Alpha App',popup:true},
 {notificationId:3,appName:'alpha-app.desktop',popup:true},
 {notificationId:4,appName:'alpha-app.desktop',popup:true},
 {notificationId:5,appName:'alpha-app.desktop',popup:true},
 {notificationId:6,appName:'Unrelated',popup:true},
 {notificationId:7,appName:'Alpha App',popup:false}
];
const root={list,popupGroupsByAppName:{},_normalizeAppKey:normalize};
let checks=0,refreshes=0;
const update=()=>{
 refreshes++;
 const groups={};
 for(const notif of list){
  if(!notif.popup)continue;
  (groups[notif.appName]??={notifications:[]}).notifications.push(notif);
 }
 root.popupGroupsByAppName=groups;
};
const cancelled=[],cancelTimeout=id=>cancelled.push(id);
update();
assert.equal(count(['Alpha App','alpha-app.desktop'],root),5);checks++;
assert.equal(count(['Alpha App','Alpha App','alpha-app.desktop'],root),5);checks++;
assert.equal(count(['ALPHA_APP','alpha app.desktop'],root),5);checks++;
assert.equal(count(['alpha-app.desktop'],root),3);checks++;
assert.equal(count(['Unrelated'],root),1);checks++;
assert.equal(count([],root),0);checks++;
assert.equal(count(null,root),0);checks++;
assert.equal(count(['Unknown'],root),0);checks++;
assert.equal(count(['Alpha App','Unrelated'],root),3);checks++;
markRead(['Alpha App','alpha-app.desktop'],root,cancelTimeout,update);
assert.deepEqual(cancelled,[1,2,3,4,5]);checks++;
assert.equal(count(['Alpha App','alpha-app.desktop'],root),0);checks++;
assert.equal(count(['Unrelated'],root),1);checks++;
assert.equal(list[6].popup,false);checks++;
assert.equal(list.length,7);checks++;
const previousRefreshes=refreshes;
markRead(['Alpha App','alpha-app.desktop'],root,cancelTimeout,update);
assert.equal(refreshes,previousRefreshes);checks++;
assert.equal(cancelled.length,5);checks++;
console.log('NOTIFICATION_DOCK_BADGE_POLICY_PASS',checks,'source-executed checks');
