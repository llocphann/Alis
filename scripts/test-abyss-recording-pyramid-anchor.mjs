#!/usr/bin/env node
// Production source runtime: Recording participates in the shared output-level
// Pyramid Popup stack — larger coexisting popups own the Screen Edge base while
// smaller peers (including Recording above a Notification or a compact popup
// above Recording) stack in the inner tier and emerge from their lower contour.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const body=read('modules/abyss/AbyssBodyHost.qml');
const rec=read('modules/abyss/AbyssRecordingBody.qml');
const perimeter=read('modules/abyss/AbyssPerimeter.qml');
const coordinator=read('modules/abyss/AbyssPyramidCoordinator.qml');
const placementJs=read('modules/abyss/looks/AbyssBodyPlacement.js');
const motionJs=read('modules/abyss/looks/AbyssPyramidMotion.js');
const geometryJs=read('modules/abyss/looks/AbyssGeometry.js');
const start=perimeter.indexOf('id: notification\n');
const end=perimeter.indexOf('id: toastBody\n',start);
assert.ok(start>=0 && end>start);
const banner=perimeter.slice(start,end);
assert.ok(banner.includes('stackPolicy: "pyramid"') && banner.includes('externalProgress: 1'));
assert.ok(rec.includes('pyramidAnchor: true') && rec.includes('placementPriority: 1'));
assert.ok(rec.includes('stackPolicy: "pyramid"') && rec.includes('externalProgress: 1'));
assert.ok(body.includes('property bool pyramidAnchor:'));
assert.ok(body.includes('pyramidAnchor:root.pyramidAnchor,'));
assert.ok(coordinator.includes('request?.pyramidAnchor !== true'));
let checks=7;
const arrange=new Function(placementJs+';return arrange;')();
const Motion=new Function(motionJs+';return {cloneRecord,clonePlacement,collapsedRecord};')();
const Geo=new Function(geometryJs+';return {panel,placedPanel};')();
const names=['_number','_descriptor','_descriptorGap','_pyramidDescriptorsRelated',
 '_candidate','_candidatePool','_pyramidGroupCandidates','_lowerPeer','entryOrigin'];
function sourceFn(name){
 const start=coordinator.indexOf('function '+name+'(');
 assert.ok(start>=0,'missing '+name);
 const brace=coordinator.indexOf('{',start);let level=0;
 for(let i=brace;i<coordinator.length;i++){
   if(coordinator[i]==='{')level++;
   else if(coordinator[i]==='}' && --level===0)
    return coordinator.slice(start,i+1).replace(/\)\s*:\s*(?:bool|void|var|int)\s*\{/,') {');
 }
 throw Error('unclosed '+name);
}
const root={controller:{participants:{},bodyPlacements:{}},closings:{}};
Object.assign(root,new Function('root','Motion',names.map(sourceFn).join('\n')
  +'\nreturn {'+names.join(',')+'};')(root,Motion));
const width=1920,height=1200,insets={left:16,top:16,right:16,bottom:16};
function request(id,priority,edge,along,span,depth,order){
 const padding=id==='recording'?10:20;
 return {id,priority,order,open:true,padding,minSpan:span,minDepth:depth,
  stackPolicy:'pyramid',
  pyramidAnchor:id==='recording',
  record:Geo.panel(width,height,insets,edge,along,span,depth,1,padding,[],false)};
}
function scene(recEdge='top',recAlong=850,recOpen=true,peerId='notification',peerSpan=360,peerDepth=170,peerAlong=790){
 const r=request('recording',1,recEdge,recAlong,200,50,1);
 const p=request(peerId,0,'top',peerAlong,peerSpan,peerDepth,2);
 r.open=recOpen;
 const together=arrange([r,p],width,height,insets);
 const rp=together.recording,pp=together[peerId];
 const recRecord=Geo.placedPanel(width,height,insets,r.record.edge,
  r.record.along,r.record.span,r.record.targetDepth,1,r.padding,[],false,rp);
 const peerRecord=Geo.placedPanel(width,height,insets,p.record.edge,
  p.record.along,p.record.span,p.record.targetDepth,1,p.padding,[],false,pp);
 root.controller.bodyPlacements=together;
 root.controller.participants={
  recording:{placementRequest:r,visualPlacement:rp,geometry:recRecord},
  [peerId]:{placementRequest:p,visualPlacement:pp,geometry:peerRecord},
 };
 return {r,p,together,rp,pp,recRecord,peerRecord};
}
{
 // Recording (200x50) + larger Notification (360x170): Notification owns the
 // Screen Edge base (inward=0) and Recording stacks neatly in the inner tier,
 // emerging along Notification's lower Pyramid contour.
 const s=scene();
 assert.equal(s.pp.inward,0,'larger notification owns Screen Edge base');checks++;
 assert.ok(s.rp.inward>0,'smaller recording moves to inner Pyramid tier');checks++;
 assert.equal(root._lowerPeer('recording',s.r,s.rp)?.identity,'notification');checks++;
 const origin=root.entryOrigin('recording',s.r,s.rp,s.recRecord);
 assert.ok(origin.surface.height>0 && origin.surface.height<s.recRecord.surface.height);checks++;
 assert.equal(origin.content.height,0);checks++;
 assert.equal(origin.content.y,s.peerRecord.surface.y+s.peerRecord.surface.height);checks++;
}
{
 // Recording (200x50 = 10,000) + smaller compact Pyramid popup (120x64 = 7,680):
 // Recording owns the Screen Edge base and the compact popup emerges from Recording's contour.
 const s=scene('top',850,true,'compactPopup',120,64,890);
 assert.equal(s.rp.inward,0,'larger recording owns Screen Edge base');checks++;
 assert.ok(s.pp.inward>0,'smaller compact popup moves to inner Pyramid tier');checks++;
 assert.equal(root._lowerPeer('compactPopup',s.p,s.pp)?.identity,'recording');checks++;
 const origin=root.entryOrigin('compactPopup',s.p,s.pp,s.peerRecord);
 assert.equal(origin.content.height,0);checks++;
 assert.equal(origin.content.y,s.recRecord.surface.y+s.recRecord.surface.height);checks++;
}
{
 const s=scene('right',850);
 assert.equal(root._lowerPeer('recording',s.r,s.rp),null);checks++;
 assert.equal(root._lowerPeer('notification',s.p,s.pp),null);checks++;
}
{
 const s=scene('top',1280);
 assert.equal(root._lowerPeer('recording',s.r,s.rp),null);checks++;
 assert.equal(root._lowerPeer('notification',s.p,s.pp),null);checks++;
}
{
 const s=scene('top',850,false);
 assert.equal(root._lowerPeer('notification',s.p,s.pp),null);checks++;
}
console.log('PASS: '+checks+' source-executed Recording Pyramid participation cases');
