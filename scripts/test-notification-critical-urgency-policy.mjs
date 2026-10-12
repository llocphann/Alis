#!/usr/bin/env node
// Actual source expression tests; no D-Bus, sound, desktop or notification use.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const service=readFileSync(new URL('services/Notifications.qml',root),'utf8');
const popup=readFileSync(new URL('modules/waffle/notificationPopup/WNotificationGroup.qml',root),'utf8');
const groupBegin='    function _groupsForListOptimized(list) {';
const groupEnd='\n    }\n\n    function _appNameListForGroups';
assert.equal(service.split(groupBegin).length,2,'expected one grouping implementation');
const groupBody=service.split(groupBegin)[1].split(groupEnd)[0];
assert(groupBody.length>0,'group implementation missing');
const groupsForList=new Function('list','root','NotificationUrgency',groupBody);
const popupStart='    readonly property bool hasCritical: ';
const popupEnd='\n    property bool expanded:';
assert.equal(popup.split(popupStart).length,2,'one Waffle critical predicate');
const expression=popup.split(popupStart)[1].split(popupEnd)[0];
const popupCritical=new Function('notifications','NotificationUrgency','return '+expression);
let checks=0;
const enumValues={Critical:2};
const groupRoot={latestTimeForApp:{Recorder:10,Chat:11}};
function item(urgency,app='Recorder',id=1) {
 return {notificationId:id,appName:app,appIcon:'',time:10,urgency};
}
for(const value of ['critical','Critical','CRITICAL',enumValues.Critical]){
 const items=[item('normal'),item(value,'Recorder',2),item('normal','Chat',3)];
 const groups=groupsForList(items,groupRoot,enumValues);
 assert.equal(groups.Recorder.hasCritical,true,'group must flag '+value);checks++;
 assert.equal(groups.Chat.hasCritical,false,'other group must not inherit critical');checks++;
 assert.equal(popupCritical(items.slice(0,2),enumValues),true,'Waffle popup must flag '+value);checks++;
}
for(const value of ['normal','low','',null,undefined]){
 const items=[item(value),item('normal','Chat')];
 const groups=groupsForList(items,groupRoot,enumValues);
 assert.equal(groups.Recorder.hasCritical,false,'noncritical must not flag '+value);checks++;
 assert.equal(popupCritical(items,enumValues),false,'Waffle must keep noncritical neutral');checks++;
}
assert.equal(popupCritical([null,item('critical')],enumValues),true);checks++;
assert.equal(popupCritical([],enumValues),false);checks++;
console.log('NOTIFICATION_CRITICAL_URGENCY_PASS',checks,'source-executed checks');
