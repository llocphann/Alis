#!/usr/bin/env node
// Production source runtime: Recording pill stays fixed; Notification Pyramid
// emerges from its lower contour only when same-edge and within proximity.
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
assert.ok(!rec.includes('stackPolicy: "pyramid"'));
assert.ok(body.includes('property bool pyramidAnchor: false'));
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
  stackPolicy:id==='notification'?'pyramid':'',
  pyramidAnchor:id==='recording',
  record:Geo.panel(width,height,insets,edge,along,span,depth,1,padding,[],false)};
}
function scene(recEdge='top',recAlong=850,recOpen=true){
 const r=request('recording',1,recEdge,recAlong,200,50,1);
 const n=request('notification',0,'top',790,360,170,2);
 r.open=recOpen;
 const initial=arrange([r],width,height,insets);
 const together=arrange([r,n],width,height,insets);
 const rp=together.recording,np=together.notification;
 const recRecord=Geo.placedPanel(width,height,insets,r.record.edge,
  r.record.along,r.record.span,r.record.targetDepth,1,r.padding,[],false,rp);
 root.controller.bodyPlacements=together;
 root.controller.participants.recording={placementRequest:r,
  visualPlacement:rp,geometry:recRecord};
 const full=Geo.placedPanel(width,height,insets,n.record.edge,
  n.record.along,n.record.span,n.record.targetDepth,1,n.padding,[],false,np);
 return {r,n,initial,together,rp,np,recRecord,full};
}
{
 const s=scene();
 assert.deepEqual(s.rp,s.initial.recording,'recording must not reflow');
 checks++;
 assert.ok(s.np.inward>0,'notification moves to inner tier');checks++;
 assert.equal(root._lowerPeer('notification',s.n,s.np)?.identity,'recording');checks++;
 const origin=root.entryOrigin('notification',s.n,s.np,s.full);
 assert.ok(origin.surface.height>0 && origin.surface.height<s.full.surface.height);checks++;
 assert.equal(origin.content.height,0);checks++;
 assert.equal(origin.content.y,s.recRecord.surface.y+s.recRecord.surface.height);checks++;
}
{
 const s=scene('right',850);
 assert.equal(root._lowerPeer('notification',s.n,s.np),null);checks++;
}
{
 const s=scene('top',1280);
 assert.equal(root._lowerPeer('notification',s.n,s.np),null);checks++;
}
{
 const s=scene('top',850,false);
 assert.equal(root._lowerPeer('notification',s.n,s.np),null);checks++;
}
console.log('PASS: '+checks+' source-executed Recording fixed / Notification Pyramid cases');
