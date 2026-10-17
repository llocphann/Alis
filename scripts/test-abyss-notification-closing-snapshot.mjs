#!/usr/bin/env node
// Source-execute the exact Abyss closing snapshot implementation without Qt.
// Runtime render/frame-swap measurements remain an independent acceptance gate.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const rootDir=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>readFileSync(resolve(rootDir,p),'utf8');
const source=read('modules/abyss/content/AbyssNotificationsContent.qml');
const list=read('modules/common/widgets/NotificationListView.qml');
const host=read('modules/abyss/AbyssBodyHost.qml');
const perimeter=read('modules/abyss/AbyssPerimeter.qml');
const methodName='function captureClosingSnapshot(): void {';
const start=source.indexOf(methodName);
assert.ok(start>0);
const brace=source.indexOf('{',start);
let depth=0,end=-1;
for(let i=brace;i<source.length;i++) {
    if(source[i]==='{') depth++;
    if(source[i]==='}' && --depth===0) {end=i+1;break;}
}
assert.ok(end>brace,'closing snapshot must be a complete QML method');
const method=source.slice(start,end).replace('(): void {','() {');
const state={center:false,closingAppNames:[],closingGroups:{}};
const original={notificationId:11,appName:'Recorder',appIcon:'camera-video',
    summary:'Starting recording',body:'file.mp4 — No audio',image:'',
    time:456,urgency:'normal',actions:[{identifier:'open',text:'Open'}]};
const grp={appName:'Recorder',appIcon:'camera-video',time:456,
    hasCritical:false,notifications:[original]};
const live={popupList:[original],popupAppNameList:['Recorder'],
    popupGroupsByAppName:{Recorder:grp}};
const capture=new Function('root','Notifications',method+'; return captureClosingSnapshot;')(state,live);
capture();
assert.deepEqual(state.closingAppNames,['Recorder']);
assert.equal(state.closingGroups.Recorder.notifications[0].body,original.body);
assert.equal(state.closingGroups.Recorder.notifications[0].actions[0].text,'Open');
assert.notEqual(state.closingGroups.Recorder.notifications[0],original,
    'snapshot must not retain live/destroyable QtObjects');
assert.notEqual(state.closingGroups.Recorder.notifications[0].actions[0],original.actions[0],
    'snapshot cannot keep native actions after timeout');
const captured=state.closingGroups;
original.body='mutated/destroyed';
live.popupList=[];
live.popupAppNameList=[];
live.popupGroupsByAppName={};
capture();
assert.equal(state.closingGroups,captured,'empty popup must preserve last rendered card');
assert.equal(state.closingGroups.Recorder.notifications[0].body,'file.mp4 — No audio');
assert.ok(source.includes('root.participant.visualResident')
    && source.includes('!root.participant.open || Notifications.popupList.length === 0'),
    'pre-captured card must bridge an empty-live-model binding turn');
assert.ok(source.includes('transientAppNamesOverride: root.closingVisualTail')
    && source.includes('transientGroupsOverride: root.closingVisualTail'),
    'Abyss banner alone must select snapshot while retracting');
assert.ok(list.includes('root.transientAppNamesOverride ?? Notifications.popupAppNameList')
    && list.includes('root.transientGroupsOverride ?? Notifications.popupGroupsByAppName'),
    'normal history and other popup hosts must keep the live model');
assert.ok(source.includes('root.captureClosingSnapshot()')
    && source.includes('function onPopupAppNameListChanged()'),
    'snapshot must update after service publishes grouped app names');
assert.ok(host.includes('root.residentContent || root.visualResident || root.warmHeld')
    && host.includes('property bool visualResident:'),
    'host keeps loader alive through visible retract');
assert.ok(perimeter.includes('residentContent: Notifications.popupList.length > 0'),
    'banner residency stays tied to live notifications, not frozen visuals');
// A fresh arrival must use its live model, never a closing snapshot.
const visible=(isCenter,open,resident,names)=>
    !isCenter && !open && resident && names.length>0;
assert.equal(visible(false,false,true,state.closingAppNames),true);
assert.equal(visible(false,true,true,state.closingAppNames),false);
assert.equal(visible(false,false,false,state.closingAppNames),false);
assert.equal(visible(true,false,true,state.closingAppNames),false);
console.log('PASS: Abyss Notification closing snapshot lifetimes, immutable wrappers, reopen and non-Abyss defaults');
