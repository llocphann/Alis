#!/usr/bin/env python3
"""Focused semantic vacancy regression for Abyss."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
def read(p): return (ROOT / p).read_text(encoding="utf-8")
perimeter=read("modules/abyss/AbyssPerimeter.qml")
controller=read("modules/abyss/AbyssSurfaceController.qml")
corners=read("modules/abyss/AbyssCorners.qml")
notification_popup=read("modules/notificationCenter/NotificationCenterPopup.qml")
window_dialog=read("modules/common/widgets/WindowDialog.qml")
wifi_dialog=read("modules/sidebarRight/wifiNetworks/WifiDialog.qml")
bluetooth_dialog=read("modules/sidebarRight/bluetoothDevices/BluetoothDialog.qml")
host=read("modules/abyss/AbyssBodyHost.qml")
participant=read("modules/abyss/AbyssParticipant.qml")
geometry=read("modules/abyss/looks/AbyssGeometry.js")
resolver=read("modules/abyss/looks/AbyssVacancyBorrowing.js")
for token in ('vacancyRole: "featureSidebar"','vacancyRole: "systemSidebar"',
              'presentationKind === "quickNotes"','presentationKind === "notificationCenter"'):
    assert token in perimeter, token
for token in ('property string vacancyRole: ""','id: vacancyBodyHover',
              'vacancyRole: root.vacancyRole'):
    assert token in host + participant, token
assert 'VacancyBorrowing.resolve(' in controller
assert 'hovered:participants[key]?.vacancyHovered' not in controller
assert '&& quickNotesEditorOutput.length === 0' not in corners
assert 'keyboardAllowed:root.quickNotesEditorOutput.length === 0' in corners
assert 'property bool keyboardAllowed: true' in notification_popup
assert '!root.presentationActive || !root.keyboardAllowed' in notification_popup
assert 'property string liquidVacancyRole: ""' in window_dialog
assert 'liquidVacancyRole: "connectivityDialog"' in wifi_dialog
assert 'liquidVacancyRole: "connectivityDialog"' in bluetooth_dialog
assert 'liquid.activeDialog?.liquidVacancyRole' in perimeter
assert 'peer:"connectivityDialog"' in resolver
assert 'parallelEnvelope:true' in resolver

program=geometry+"\n"+resolver+r"""
const assert=require("node:assert/strict");
const W=1800,H=1000,IN={left:16,right:16,top:16,bottom:16},G=24;
function m(id,role,edge,order,p){return{
 request:{id,open:true,order,padding:14,record:{edge,along:p.along,span:p.span,targetDepth:p.depth,depth:p.depth}},
 meta:{id,role,hovered:false,hoverOrder:0},placement:p};}
function run(ms){const ps=Object.fromEntries(ms.map(x=>[x.request.id,x.placement]));
 return{base:ps,out:resolve(ms.map(x=>x.request),ms.map(x=>x.meta),ps,W,H,IN,G)};}
function borrowers(o){return Object.entries(o).filter(([_,p])=>p.vacancyBorrowed).map(([id])=>id).sort();}
function collide(a,b,g=G){return a.x<b.x+b.width+g&&a.x+a.width+g>b.x&&a.y<b.y+b.height+g&&a.y+a.height+g>b.y;}

const feature=m("leftPanel","featureSidebar","left",31,{visible:true,along:70,inward:20,span:780,depth:394,content:{x:50,y:84,width:366,height:752}});
const notes=m("styledPopup0","quickNotes","bottom",32,{visible:true,along:456,inward:0,span:368,depth:344,content:{x:470,y:642,width:340,height:316}});
const system=m("rightPanel","systemSidebar","right",33,{visible:true,along:70,inward:20,span:780,depth:394,content:{x:1340,y:84,width:366,height:752}});
const center=m("styledPopup1","notificationCenter","top",34,{visible:true,along:916,inward:0,span:368,depth:344,content:{x:930,y:64,width:340,height:316}});

// Exact live failure: four surfaces on two sides keep both independent automatic owners.
let r=run([feature,notes,system,center]);
assert.deepEqual(borrowers(r.out),["styledPopup0","styledPopup1"]);
assert(!collide(r.out.styledPopup0.content,r.out.styledPopup1.content));
// Notification Center is inward of its right sidebar in this fixture, so the
// literal-gap path must not turn it into a full-height panel.
assert.equal(r.out.styledPopup1.vacancyDirection,"right");
assert.equal(r.out.styledPopup1.content.height,center.placement.content.height);
assert(r.out.styledPopup1.content.width>center.placement.content.width);

// Hover metadata cannot alter geometry or restart ownership.
const automaticLeft=JSON.stringify(r.out.styledPopup0);
notes.meta.hovered=true;notes.meta.hoverOrder=100;
feature.meta.hovered=true;feature.meta.hoverOrder=101;
r=run([feature,notes,system,center]);
assert.deepEqual(borrowers(r.out),["styledPopup0","styledPopup1"]);
assert.equal(JSON.stringify(r.out.styledPopup0),automaticLeft);
notes.meta.hovered=false;feature.meta.hovered=false;

// Closing one peer collapses only that pair.
center.request.open=false;
r=run([feature,notes,system,center]);
assert.deepEqual(borrowers(r.out),["styledPopup0"]);
center.request.open=true;

// Intended automatic owner per pair.
assert.deepEqual(borrowers(run([feature,notes]).out),["styledPopup0"]);
assert.deepEqual(borrowers(run([system,center]).out),["styledPopup1"]);

// Video regression: Quick Notes stays Edge-direct while the later sidebar
// is reflowed inward. It must fill the exposed outer strip immediately, with
// no hover event, and stop at the sidebar's tangent envelope.
const videoNotes=m("videoNotes","quickNotes","left",41,{visible:true,along:600,inward:0,span:360,depth:420,content:{x:30,y:614,width:392,height:332}});
const videoSidebar=m("videoSidebar","featureSidebar","left",42,{visible:true,along:210,inward:450,span:720,depth:450,content:{x:480,y:224,width:422,height:692}});
r=run([videoNotes,videoSidebar]);
assert.deepEqual(borrowers(r.out),["videoNotes"]);
assert.equal(r.out.videoNotes.vacancyDirection,"top");
assert(r.out.videoNotes.content.y < videoNotes.placement.content.y);
assert.equal(r.out.videoNotes.content.width,videoNotes.placement.content.width);
assert(r.out.videoNotes.content.y >= videoSidebar.placement.content.y-.01);

// Screenshot regression: Controls/systemSidebar is physically on the left,
// while its Wi-Fi/Bluetooth WindowDialog is on the right. The connectivity
// dialog fills the free lower strip to the sidebar envelope without consuming
// their already-resolved horizontal gap. Physical swap must not affect pairing.
const controlsLeft=m("controlsLeft","systemSidebar","left",51,{visible:true,along:249,inward:0,span:700,depth:451,content:{x:37,y:249,width:450,height:700}});
const connectivity=m("dialog","connectivityDialog","right",52,{visible:true,along:64,inward:0,span:495,depth:381,content:{x:500,y:64,width:380,height:495}});
r=run([controlsLeft,connectivity]);
assert.deepEqual(borrowers(r.out),["dialog"]);
assert.equal(r.out.dialog.vacancyDirection,"bottom");
assert.equal(r.out.dialog.content.x,connectivity.placement.content.x);
assert.equal(r.out.dialog.content.width,connectivity.placement.content.width);
assert.equal(r.out.dialog.content.y,connectivity.placement.content.y);
assert.equal(r.out.dialog.content.y+r.out.dialog.content.height,
    controlsLeft.placement.content.y+controlsLeft.placement.content.height);

// An unrelated body in the free strip still caps the borrow with the normal
// safety gap; semantic pairing never grants permission through blockers.
const stripBlocker=m("stripBlocker","", "right",60,{visible:true,along:800,inward:0,span:100,depth:381,content:{x:500,y:800,width:380,height:100}});
r=run([controlsLeft,connectivity,stripBlocker]);
assert.equal(r.out.dialog.content.y+r.out.dialog.content.height,800-G);

// Without the logical system sidebar there is no semantic vacancy transaction.
r=run([connectivity]);
assert.strictEqual(r.out,r.base);

// The special parallel-envelope policy is connectivity-only. Notification
// Center keeps the established literal-gap rule and must not become full-height.
const centerByLeftControls=m("centerByLeftControls","notificationCenter","right",53,{visible:true,along:64,inward:0,span:495,depth:381,content:{x:500,y:64,width:380,height:495}});
r=run([controlsLeft,centerByLeftControls]);
assert.equal(r.out.centerByLeftControls?.content.height,
    centerByLeftControls.placement.content.height);

// No vacancy is strict identity no-op.
const blocked=m("styledPopup0","quickNotes","left",99,{visible:true,along:70,inward:20,span:780,depth:394,content:{x:50,y:84,width:366,height:752}});
r=run([feature,blocked]);assert.strictEqual(r.out,r.base);

// Resolved content is the rendered geometry truth.
r=run([feature,notes]);
const rec=placedPanel(W,H,IN,"left",feature.request.record.along,feature.request.record.span,feature.request.record.targetDepth,1,14,[],true,r.out.leftPanel);
assert.deepEqual([rec.content.x,rec.content.y,rec.content.width,rec.content.height],
 [r.out.leftPanel.content.x,r.out.leftPanel.content.y,r.out.leftPanel.content.width,r.out.leftPanel.content.height]);

// Same-edge Sidebar + QuickNotes:
// 1. QuickNotes hovered first (order=1, inward=456), Sidebar opened second (order=2, inward=0) -> Sidebar expands bottom.
const edgeNotesFirst=m("styledPopup0","quickNotes","left",1,{visible:true,along:696,inward:456,span:370,depth:346,content:{x:484,y:710,width:318,height:342}});
const edgeSidebarSecond=m("leftPanel","featureSidebar","left",2,{visible:true,along:190,inward:0,span:700,depth:460,content:{x:28,y:204,width:432,height:672}});
r=run([edgeSidebarSecond,edgeNotesFirst]);
assert.deepEqual(borrowers(r.out),["leftPanel"]);
assert.equal(r.out.leftPanel.vacancyDirection,"bottom");
assert(r.out.leftPanel.span > edgeSidebarSecond.placement.span);

// 2. Sidebar opened first (order=1, inward=342), QuickNotes hovered second (order=2, inward=0) -> QuickNotes expands top.
const edgeSidebarFirst=m("leftPanel","featureSidebar","left",1,{visible:true,along:190,inward:342,span:700,depth:460,content:{x:370,y:204,width:432,height:672}});
const edgeNotesSecond=m("styledPopup0","quickNotes","left",2,{visible:true,along:696,inward:0,span:370,depth:346,content:{x:28,y:710,width:318,height:342}});
r=run([edgeSidebarFirst,edgeNotesSecond]);
assert.deepEqual(borrowers(r.out),["styledPopup0"]);
assert.equal(r.out.styledPopup0.vacancyDirection,"top");
assert.equal(r.out.styledPopup0.content.y,edgeSidebarFirst.placement.content.y);

// 3. One-sided perpendicular blocker (Overview at top) shrinks Sidebars symmetrically
// around anchorCenter -> VacancyBorrowing shifts unblocked bottom down slightly
// and adjusts vertical height while keeping Overview at full size.
const topOverview=m("styledPopup0","","top",3,{visible:true,along:100,inward:0,span:1720,depth:232,content:{x:114,y:54,width:1692,height:204}});
const shrunkLeftSidebar={
 request:{id:"leftPanel",open:true,order:1,padding:14,record:{edge:"left",along:190,span:700,targetDepth:460,depth:460}},
 meta:{id:"leftPanel",role:"featureSidebar",hovered:false,hoverOrder:0},
 placement:{visible:true,shrunk:true,along:268,inward:0,span:544,depth:460,content:{x:28,y:282,width:432,height:516}}
};
const shrunkRightSidebar={
 request:{id:"rightPanel",open:true,order:2,padding:14,record:{edge:"right",along:190,span:700,targetDepth:460,depth:460}},
 meta:{id:"rightPanel",role:"systemSidebar",hovered:false,hoverOrder:0},
 placement:{visible:true,shrunk:true,along:268,inward:0,span:544,depth:460,content:{x:1460,y:282,width:432,height:516}}
};
r=run([topOverview,shrunkLeftSidebar,shrunkRightSidebar]);
assert.equal(r.out.leftPanel.vacancyDirection,"bottom");
assert.equal(r.out.leftPanel.along,268);
assert.equal(r.out.leftPanel.span,661);
assert.equal(r.out.leftPanel.along+r.out.leftPanel.span,929);
assert.equal(r.out.rightPanel.vacancyDirection,"bottom");
assert.equal(r.out.rightPanel.along,268);
assert.equal(r.out.rightPanel.span,661);
assert.equal(r.out.rightPanel.along+r.out.rightPanel.span,929);

console.log("PASS: two semantic pairs borrow independently without collision");
"""
raise SystemExit(subprocess.run(["node","-e",program],cwd=ROOT).returncode)
