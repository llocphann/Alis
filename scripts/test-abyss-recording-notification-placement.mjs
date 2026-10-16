#!/usr/bin/env node
// Source-executed regression: the existing Abyss allocator must not translate
// the Recording pill when a transient notification arrives or retracts.
// This runs without Qt; native frame-time/multi-output acceptance is separate.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname,resolve} from 'node:path';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const source=readFileSync(resolve(root,'modules/abyss/looks/AbyssBodyPlacement.js'),'utf8');
const recordingBody=readFileSync(resolve(root,'modules/abyss/AbyssRecordingBody.qml'),'utf8');
const host=readFileSync(resolve(root,'modules/abyss/AbyssBodyHost.qml'),'utf8');
const perimeter=readFileSync(resolve(root,'modules/abyss/AbyssPerimeter.qml'),'utf8');
const arrange=new Function(source+'; return arrange;')();
assert.match(recordingBody,/identity:\s*"recording"[\s\S]*?placementPriority:\s*1/);
assert.match(host,/identity === "dialog" \? 2/);
const notificationStart=perimeter.indexOf('id: notification\n');
const notificationEnd=perimeter.indexOf('id: toastBody\n',notificationStart);
assert.ok(notificationStart>0 && notificationEnd>notificationStart);
const notification=perimeter.slice(notificationStart,notificationEnd);
assert.ok(!/placementPriority\s*:/.test(notification),
    'transient banner must keep its default priority');

let checks=0;
const geometry={width:1920,height:1200,insets:{left:16,top:16,right:16,bottom:16}};
function request(id,priority,edge,along,span,depth,order=0,open=true) {
    const padding=id==='recording' ? 10 : 20;
    const horizontal=edge==='top'||edge==='bottom';
    const content={x:horizontal ? along+padding : edge==='left' ? 16+padding : geometry.width-16-depth+padding,
        y:horizontal ? edge==='top' ? 16+padding : geometry.height-16-depth+padding : along+padding,
        width:horizontal ? span-2*padding : depth-2*padding,
        height:horizontal ? depth-2*padding : span-2*padding};
    return {id,priority,order,open,padding,minSpan:span,minDepth:depth,
        record:{edge,along,span,depth,targetDepth:depth,progress:1,content,
            surface:{x:along,y:-50,width:span,height:depth+66}}};
}
function check(scene,label){
    checks++;
    const baseline=arrange([scene.rec],geometry.width,geometry.height,geometry.insets);
    const together=arrange([scene.rec,scene.popup],geometry.width,geometry.height,geometry.insets);
    const closed=arrange([scene.rec,{...scene.popup,open:false}],
        geometry.width,geometry.height,geometry.insets);
    assert.equal(baseline.recording.visible,true,label+' initial recording');
    assert.equal(together.recording.visible,true,label+' recording not evicted');
    assert.deepEqual(together.recording,baseline.recording,
        label+' entering notification must NOT relocate/reflow Recording');
    assert.deepEqual(closed.recording,baseline.recording,
        label+' retracting notification must NOT relocate/reflow Recording');
    assert.equal(together.notification.visible,true,label+' notification not evicted');
    const n=together.notification.content,r=together.recording.content;
    assert.ok(n.y>=r.y+r.height+23.9 || n.x>=r.x+r.width+23.9
        || r.y>=n.y+n.height+23.9 || r.x>=n.x+n.width+23.9,
        label+' both remain readable with safe spacing');
    assert.ok(together.notification.inward>=0,label+' notification stays on same Edge');
    return {baseline,together};
}
const center=check({rec:request('recording',1,'top',850,200,50,1),
    popup:request('notification',0,'top',790,360,170,2)},'centered collision');
assert.equal(center.baseline.recording.inward,0);
assert.equal(center.together.recording.inward,0);
assert.equal(center.together.notification.inward,44);
const original=arrange([
    request('recording',0,'top',850,200,50,1),
    request('notification',0,'top',790,360,170,2)],1920,1200,geometry.insets);
assert.equal(original.recording.inward,164,
    'negative control must reproduce the pre-fix 164px pill displacement');
const remote=check({rec:request('recording',1,'top',850,200,50,1),
    popup:request('notification',0,'top',1250,360,170,2)},'non-overlap');
assert.equal(remote.together.notification.inward,0,
    'notification remains at its normal position when no collision exists');
for(const y of [0,1]) {
    const order=y?999:-999;
    check({rec:request('recording',1,'top',850,200,50,1),
        popup:request('notification',0,'top',790,360,170,order)},'alternate notification order '+order);
}
assert.match(recordingBody,/placementCanResize:\s*false/,
    'recording controls remain full size');
assert.match(recordingBody,/animatePlacementChanges:\s*!root.dragging/,
    'existing drag motion remains intact');
assert.match(recordingBody,/includeEdgeConnection:\s*true/,
    'native Recording hover bridge must be preserved');
console.log('PASS: '+checks+' live allocator Recording/Notification placement cases and negative control');
