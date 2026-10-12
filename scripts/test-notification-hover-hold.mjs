#!/usr/bin/env node
// Execute the real QML hover-hold sync with destroyed/stale delegates.
// No session notifications, D-Bus or real timers are involved.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const src=readFileSync(new URL('../modules/common/widgets/NotificationTimeoutHold.qml',import.meta.url),'utf8');
const start='    function sync(): void {',end='\n    }\n    onActiveChanged:';
assert.equal(src.split(start).length,2,'one hover sync implementation');
const body=src.split(start)[1].split(end)[0];
const sync=new Function('active','notifications','heldIds','Notifications','root',body+'\nreturn heldIds;');
const owner={tag:'hover'},paused=new Set(),events=[];
const service={
 pauseTimeout(id,w){assert.equal(w,owner);paused.add(id);events.push('hold:'+id)},
 resumeTimeout(id,w){assert.equal(w,owner);paused.delete(id);events.push('release:'+id)}
};
let checks=0;
const test=(active,items,held)=>sync(active,items,held,service,owner);
let current=test(true,[{notificationId:1},null,undefined,{notificationId:1},
 {notificationId:2},{notificationId:'broken'}, {notificationId:NaN},
 {notificationId:Infinity}],[]);
assert.deepEqual(current,[1,2]);checks++;
assert.deepEqual([...paused],[1,2]);checks++;
assert.deepEqual(events,['hold:1','hold:2']);checks++;
current=test(true,[null,{notificationId:2},null],current);
assert.deepEqual(current,[2]);checks++;
assert.deepEqual([...paused],[2]);checks++;
assert(events.includes('release:1'));checks++;
current=test(false,[{notificationId:2}],current);
assert.deepEqual(current,[]);checks++;
assert.equal(paused.size,0);checks++;
current=test(true,null,[]);
assert.deepEqual(current,[]);checks++;
current=test(true,[{notificationId:0},{notificationId:3}],[]);
assert.deepEqual(current,[0,3]);checks++;
current=test(true,[null],current);
assert.deepEqual(current,[]);checks++;
assert.equal(paused.size,0);checks++;
console.log('NOTIFICATION_HOVER_HOLD_PASS',checks,'source-executed checks');
