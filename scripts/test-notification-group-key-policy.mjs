#!/usr/bin/env node
// Source-execute the production appName-keyed notification grouping/cache.
// No native service, notifications, D-Bus, user data or backend writes.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../services/Notifications.qml',import.meta.url),'utf8');
const extract=(begin,end)=>{
 assert.equal(source.split(begin).length,2,'unique body '+begin);
 const code=source.split(begin)[1].split(end)[0];
 assert(code.length>0,'missing extracted function');
 return code;
};
const grouped=new Function('list','root','NotificationUrgency',
 extract('    function _groupsForListOptimized(list) {',
   '\n    }\n\n    function _appNameListForGroups'));
const sorted=new Function('groups',
 extract('    function _appNameListForGroups(groups) {',
   '\n    }\n\n    // Notification appName'));
const update=new Function('root','_groupsDirty','_groupsForListOptimized','_appNameListForGroups',
 extract('    function _updateGroups() {',
   '\n    }\n\n    function _groupsForListOptimized'));
const urgency={Critical:3};
const notifications=[
 {appName:'constructor',appIcon:'one',notificationId:1,time:10,urgency:'normal',popup:true},
 {appName:'toString',appIcon:'two',notificationId:2,time:20,urgency:'critical',popup:true},
 {appName:'__proto__',appIcon:'three',notificationId:3,time:30,urgency:'normal',popup:true},
 {appName:'Rec',appIcon:'four',notificationId:4,time:40,urgency:'normal',popup:true},
 {appName:'constructor',appIcon:'one',notificationId:5,time:50,urgency:'normal',popup:false}
];
const keys=['constructor','toString','__proto__','Rec'];
let checks=0;
const root={list:notifications,popupList:[],_cachedGroupsByAppName:{},
 _cachedPopupGroupsByAppName:{},_cachedAppNameList:[],_cachedPopupAppNameList:[],
 latestTimeForApp:{}};
function calcGroups(list){return grouped(list,root,urgency)}
function calcKeys(groups){return sorted(groups)}
update(root,true,calcGroups,calcKeys);
assert.equal(Object.getPrototypeOf(root.latestTimeForApp),null);checks++;
assert.equal(Object.getPrototypeOf(root._cachedGroupsByAppName),null);checks++;
assert.equal(Object.getPrototypeOf(root._cachedPopupGroupsByAppName),null);checks++;
for(const key of keys){
 assert(Object.hasOwn(root.latestTimeForApp,key),'time own key '+key);checks++;
 assert(Object.hasOwn(root._cachedGroupsByAppName,key),'group own key '+key);checks++;
 assert(Object.hasOwn(root._cachedPopupGroupsByAppName,key),'popup own key '+key);checks++;
}
assert.equal(root._cachedGroupsByAppName.constructor.notifications.length,2);checks++;
assert.equal(root._cachedPopupGroupsByAppName.constructor.notifications.length,1);checks++;
assert.equal(root._cachedGroupsByAppName.toString.hasCritical,true);checks++;
assert.equal(root.latestTimeForApp.constructor,50);checks++;
assert.deepEqual(root._cachedAppNameList,['constructor','Rec','__proto__','toString']);checks++;
// The group cache survives repeated rebuilds, marking read and disappearing
// popups, without changing object identity for the appName strings.
notifications[0].popup=false;
update(root,true,calcGroups,calcKeys);
assert.equal(root._cachedPopupGroupsByAppName.constructor,undefined);checks++;
assert(root._cachedGroupsByAppName.constructor.notifications.length===2);checks++;
assert(Object.hasOwn(root.latestTimeForApp,'__proto__'));checks++;
assert(!Object.hasOwn(root.latestTimeForApp,'hasOwnProperty'));checks++;
console.log('NOTIFICATION_GROUP_KEY_POLICY_PASS',checks,'source-executed checks');
