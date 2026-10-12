#!/usr/bin/env node
// Source-execute the production QML slide-dismiss functions. Never send or
// dismiss an actual desktop notification. Guard mutable delegates and
// asynchronous Qt.callLater callbacks with primitive IDs.
import {readFileSync} from "node:fs";
import assert from "node:assert/strict";

const dir = new URL("../", import.meta.url);
const files = {
  group: readFileSync(new URL("modules/common/widgets/NotificationGroup.qml", dir), "utf8"),
  item: readFileSync(new URL("modules/common/widgets/NotificationItem.qml", dir), "utf8")
};
function extract(text, start, end) {
  assert.equal(text.split(start).length, 2, "expected unique code: " + start);
  const code = text.split(start)[1].split(end)[0];
  assert(code.length > 0, "empty source body: " + start);
  return code;
}
const start = "    function destroyWithAnimation(left = false) {";
const animationStart = "        onFinished: () => {";
const groupBegin = extract(files.group, start, "\n    }\n\n    hoverEnabled:");
const itemBegin = extract(files.item, start, "\n    }\n\n    TextMetrics {");
const groupFinished = extract(files.group, animationStart,
   "\n        }\n    }\n\n    function toggleExpanded");
const itemFinished = extract(files.item, animationStart,
   "\n        }\n    }\n\n    DragManager");
const begin = new Function("left", "root", "background", "destroyAnimation", groupBegin);
const end = new Function("root", "destroyAnimation", "Qt", "Notifications", groupFinished);
const beginOne = new Function("left", "root", "background", "destroyAnimation", itemBegin);
const endOne = new Function("destroyAnimation", "Notifications", itemFinished);
let checks = 0;
function harness(ids) {
  const pending = [];
  const notifications = {list: ids.map(notificationId => ({notificationId})), removed:[],
    discardNotification(id) {
      assert(this.list.some(n => n?.notificationId === id), "unexpected discard");
      this.removed.push(id);
      this.list = this.list.filter(n => n?.notificationId !== id);
    }};
  return {notifications, Qt: {callLater(callback) {pending.push(callback)}},
    flush() {while(pending.length) pending.shift()()}, pending};
}
function surface(notifs) {
  return {
    root: {xOffset:3, implicitHeight:100,notifications:notifs,
      notificationObject:notifs[0] ?? null,qmlParent:{resetDrag(){}}},
    background:{anchors:{leftMargin:0},implicitHeight:120},
    animation:{running:false,left:true,dismissIds:[],dismissId:-1}
  };
}
{
  const h=harness([1,2,3]),s=surface([{notificationId:1},{notificationId:2}]);
  begin(false,s.root,s.background,s.animation);
  assert.deepEqual(s.animation.dismissIds,[1,2]);checks++;
  assert.equal(s.animation.left,false);checks++;
  s.animation.running=true;
  s.root.notifications=[{notificationId:3},{notificationId:2}];
  begin(true,s.root,s.background,s.animation);
  assert.deepEqual(s.animation.dismissIds,[1,2]);checks++;
  s.animation.running=false;
  end(s.root,s.animation,h.Qt,h.notifications);
  assert.deepEqual(s.animation.dismissIds,[]);checks++;
  // A separate owner has already removed ID 2 before queued Qt callbacks.
  h.notifications.list=h.notifications.list.filter(n=>n.notificationId!==2);
  h.flush();
  assert.deepEqual(h.notifications.removed,[1]);checks++;
  assert(h.notifications.list.some(n=>n.notificationId===3));checks++;
}
{
  const h=harness([0,4,5]),s=surface([{notificationId:0},{notificationId:4},
    {notificationId:4},null,{notificationId:"bad"},{notificationId:-5}]);
  begin(true,s.root,s.background,s.animation);
  assert.deepEqual(s.animation.dismissIds,[0,4]);checks++;
  end(s.root,s.animation,h.Qt,h.notifications);h.flush();
  assert.deepEqual(h.notifications.removed,[0,4]);checks++;
  assert(h.notifications.list.some(n=>n.notificationId===5));checks++;
  begin(true,s.root,s.background,s.animation);
  end(s.root,s.animation,h.Qt,h.notifications);h.flush();
  assert.deepEqual(h.notifications.removed,[0,4]);checks++;
}
{
  const h=harness([7,8]),s=surface([{notificationId:7}]);
  beginOne(false,s.root,s.background,s.animation);
  assert.equal(s.animation.dismissId,7);checks++;
  s.root.notificationObject={notificationId:8};
  s.animation.running=true;
  beginOne(true,s.root,s.background,s.animation);
  assert.equal(s.animation.dismissId,7);checks++;
  s.animation.running=false;
  endOne(s.animation,h.notifications);
  assert.deepEqual(h.notifications.removed,[7]);checks++;
  assert(h.notifications.list.some(n=>n.notificationId===8));checks++;
  assert.equal(s.animation.dismissId,-1);checks++;
}
{
  const h=harness([9]),s=surface([null]);
  beginOne(true,s.root,s.background,s.animation);
  assert.equal(s.animation.running,false);checks++;
  assert.equal(s.animation.dismissId,-1);checks++;
  endOne(s.animation,h.notifications);
  assert.deepEqual(h.notifications.removed,[]);checks++;
}
console.log("NOTIFICATION_SWIPE_DISMISS_PASS",checks, "source-executed assertions");
