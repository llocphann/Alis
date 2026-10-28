#!/usr/bin/env python3
"""Exercise anchor-preserving body allocation, reflow and eviction."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
host_source = (root / "modules/abyss/AbyssBodyHost.qml").read_text()
if 'property bool placementCanStackInward: identity !== "dock"' not in host_source:
    raise SystemExit("FAIL: Dock must opt out of inward allocator stacking")
if "allowInward:root.placementCanStackInward" not in host_source:
    raise SystemExit("FAIL: AbyssBodyHost must publish inward-stacking policy to the allocator")

program = (root / "modules/abyss/looks/AbyssGeometry.js").read_text() + "\n" + (
    root / "modules/abyss/looks/AbyssBodyPlacement.js"
).read_text() + r"""
const assert=require('node:assert/strict');
const edgeInsets={left:16,right:16,top:48,bottom:16};

function overlap(a,b,gap=0) {
 return a.x<b.x+b.width+gap && a.x+a.width+gap>b.x
     && a.y<b.y+b.height+gap && a.y+a.height+gap>b.y;
}
function request(id,edge,order,depth=200,along=300,span=420,options={}) {
 const padding=options.padding ?? 14;
 const record=panel(1200,900,edgeInsets,edge,along,span,depth,1,padding,[],true);
 return {id,open:true,order,priority:options.priority ?? 0,padding,
   allowInward:options.allowInward ?? true,
   stackPolicy:options.stackPolicy ?? "",
   stackProximity:options.stackProximity ?? 24,
   minSpan:Math.min(record.span,options.minSpan ?? 220),
   minDepth:Math.min(record.targetDepth,options.minDepth ?? 120),record};
}
function center(record) { return record.along+record.span/2; }
function verify(requests,result) {
 const rects=[];
 for(const request of requests) {
  const placement=result[request.id];
  if(!placement?.visible) continue;
  assert(Math.abs((placement.along+placement.span/2)-center(request.record))<1e-6,
      'physical Edge anchor center is retained');
  assert(placement.span+1e-6>=request.minSpan && placement.depth+1e-6>=request.minDepth,
      'reflow never crosses readable minima');
  const record=placedPanel(1200,900,edgeInsets,request.record.edge,
      request.record.along,request.record.span,request.record.targetDepth,1,
      request.padding,[],true,placement);
  assert.deepEqual(record.content,placement.content,
      'field, content, allocator and input share exact coordinates');
  const content=record.content;
  assert(content.x>=edgeInsets.left-.01 && content.y>=edgeInsets.top-.01
      && content.x+content.width<=1184.01 && content.y+content.height<=884.01,
      'allocated content stays inside the viewport');
  for(const other of rects) assert(!overlap(content,other,23.99),
      'visible bodies retain the configured content gap');
  rects.push(content);
 }
}

for(const edge of ['top','bottom','left','right']) {
 const requests=[request('old',edge,1),request('middle',edge,2),request('new',edge,3)];
 const snapshot=JSON.stringify(requests);
 const result=arrange(requests,1200,900,edgeInsets);
 verify(requests,result);
 assert(result.old.visible && result.middle.visible && result.new.visible);
 assert.equal(result.new.inward,0,'newest body keeps the direct Edge slot');
 assert(result.old.inward>result.middle.inward && result.middle.inward>0,
     'older same-anchor bodies stack inward without lateral relocation');
 assert.equal(result.new.shrunk,false,'roomy layouts retain requested dimensions');
 assert.equal(JSON.stringify(requests),snapshot,'allocator never mutates caller requests');
 const fading=placedPanel(1200,900,edgeInsets,edge,
     requests[0].record.along,requests[0].record.span,requests[0].record.targetDepth,.4,
     requests[0].padding,[],true,result.old);
 assert(Math.abs((fading.along+fading.span/2)-center(requests[0].record))<1e-6,
     'reveal frames retain the same anchor');
}

// Pyramid grouping follows the common case: different anchors on one Edge
// whose requested content intervals overlap (or are within the 24 px clearance).
// Outsiders keep their legacy slots while connected neighborhood members
// deterministically reorder those slots by resting area.
const pyramidLarge=request('pyramidLarge','top',1,260,400,400,{stackPolicy:'pyramid'});
const pyramidSmall=request('pyramidSmall','top',3,140,650,260,{stackPolicy:'pyramid'});
const remote=request('remote','top',2,180,40,250,{stackPolicy:'pyramid'});
const expectedOrder=['pyramidLarge','remote','pyramidSmall'];
const permutations=[
 [pyramidLarge,pyramidSmall,remote],
 [pyramidLarge,remote,pyramidSmall],
 [pyramidSmall,pyramidLarge,remote],
 [pyramidSmall,remote,pyramidLarge],
 [remote,pyramidLarge,pyramidSmall],
 [remote,pyramidSmall,pyramidLarge]
];
for(const permutation of permutations)
 assert.deepEqual(_orderedRequests(permutation).map(request=>request.id),expectedOrder,
     'pyramid ordering is deterministic and preserves outsider legacy slots');

const pyramidPair=[pyramidLarge,pyramidSmall];
let pyramidPacked=arrange(pyramidPair,1200,900,edgeInsets);
assert.equal(pyramidPacked.pyramidLarge.inward,0,
    'larger same-neighborhood popup owns the physical Edge tier');
assert(pyramidPacked.pyramidSmall.inward>0,
    'overlapping different-anchor popup stacks inward');

const crowded=[
 request('settings','bottom',1,760,80,1040,{minSpan:520,minDepth:240}),
 request('osd','bottom',2,200,400,420,{minSpan:220,minDepth:120})
];
let packed=arrange(crowded,1200,900,edgeInsets);
verify(crowded,packed);
assert(packed.osd.visible && packed.settings.visible,
    'older content reflows before it is evicted');
assert(packed.settings.shrunk,'constrained older content reports reflow');
assert(Math.abs((packed.settings.along+packed.settings.span/2)-center(crowded[0].record))<1e-6,
    'reflow keeps the requested physical anchor');

const impossible=[
 request('settings','bottom',1,760,80,1040,{minSpan:1040,minDepth:700}),
 request('osd','bottom',2,200,400,420,{minSpan:420,minDepth:200})
];
packed=arrange(impossible,1200,900,edgeInsets);
assert(packed.osd.visible && packed.settings.evicted && !packed.settings.visible,
    'lower-priority body is evicted only after readable minima cannot fit');
impossible[1].open=false;
packed=arrange(impossible,1200,900,edgeInsets);
assert(packed.settings.visible && !packed.settings.evicted,
    'evicted body automatically becomes placeable when the newer body closes');

const mixed=[
 request('left','left',1,250,140,420,{minSpan:240,minDepth:140}),
 request('top','top',2,220,240,500,{minSpan:260,minDepth:140}),
 request('bottom','bottom',3,220,430,420,{minSpan:240,minDepth:140}),
 request('right','right',4,240,180,440,{minSpan:240,minDepth:140})
];
packed=arrange(mixed,1200,900,edgeInsets);
verify(mixed,packed);
assert(Object.values(packed).filter(p=>p.visible).length>=3,
    'perpendicular bodies partition/reflow rather than all collapsing');
mixed[0].priority=2;
packed=arrange(mixed,1200,900,edgeInsets);
assert(packed.left.visible && packed.left.inward===0 && !packed.left.shrunk,
    'modal/high-priority body retains its direct anchor and requested size');

// Dock is edge-locked: it may yield by retracting, but it must never become
// a floating inner-tier panel when a higher-priority surface owns its space.
const dock=request('dock','bottom',1,96,390,420,{
 priority:-1,minSpan:420,minDepth:96,allowInward:false
});
const blocker=request('dockBlocker','bottom',2,180,320,560,{
 minSpan:560,minDepth:180
});
packed=arrange([dock,blocker],1200,900,edgeInsets);
assert(blocker.open && packed.dock.evicted && !packed.dock.visible,
    'edge-locked Dock retracts when its physical Edge slot is unavailable');
assert.equal(packed.dock.inward,0,
    'edge-locked Dock is never reassigned to an inward tier');
blocker.open=false;
packed=arrange([dock,blocker],1200,900,edgeInsets);
assert(packed.dock.visible && !packed.dock.evicted,
    'edge-locked Dock restores automatically when the conflict clears');
assert.equal(packed.dock.inward,0,
    'restored Dock returns to the physical Edge');

assert.deepEqual(arrange([],1200,900,edgeInsets),{});

// Dashboard + 1 or 2 Sidebars: Dashboard keeps full width while both Sidebars
// shrink width at inward=0 instead of closing or being pushed inward.
const hdInsets={left:14,right:14,top:40,bottom:14};
function hdRequest(id,edge,order,depth,along,span,options={}) {
 const padding=options.padding ?? 14;
 const record=panel(1920,1080,hdInsets,edge,along,span,depth,1,padding,[],options.largeSurface ?? true);
 return {id,open:true,order,priority:options.priority ?? 0,padding,
   allowInward:options.allowInward ?? true,
   preserveAspect:options.preserveAspect ?? false,
   minSpan:Math.min(record.span,options.minSpan ?? (options.largeSurface ? 520 : 220)),
   minDepth:Math.min(record.targetDepth,options.minDepth ?? (options.largeSurface ? 360 : 120)),record};
}
const leftSb=hdRequest('leftPanel','left',1,460,190,700,{priority:2,largeSurface:false});
const rightSb=hdRequest('rightPanel','right',2,460,190,700,{priority:2,largeSurface:false});
const dash=hdRequest('dashboard','top',3,818,268,1384,{priority:3,largeSurface:true});
let hdPacked=arrange([leftSb,rightSb,dash],1920,1080,hdInsets);
assert(hdPacked.dashboard.visible && !hdPacked.dashboard.shrunk,'Dashboard keeps full dimensions');
assert(hdPacked.leftPanel.visible && hdPacked.leftPanel.inward===0 && hdPacked.leftPanel.shrunk && hdPacked.leftPanel.depth===258,
    'Left sidebar shrinks width to exact gap beside Dashboard');
assert(hdPacked.rightPanel.visible && hdPacked.rightPanel.inward===0 && hdPacked.rightPanel.shrunk && hdPacked.rightPanel.depth===258,
    'Right sidebar shrinks width to exact gap beside Dashboard');

// Overview hovered first (order=1, prio=2) then Sidebar opened second (order=2, prio=1):
// Overview stays full size and Sidebar scales down below Overview at inward=0.
const ovFirst=hdRequest('overview','top',1,232,100,1720,{priority:2,largeSurface:false,preserveAspect:true});
const sbSecond=hdRequest('leftPanel','left',2,460,190,700,{priority:1,largeSurface:false});
hdPacked=arrange([ovFirst,sbSecond],1920,1080,hdInsets);
assert(hdPacked.overview.visible && !hdPacked.overview.shrunk && hdPacked.overview.inward===0,
    'Overview hovered first retains full size at top edge');
assert(hdPacked.leftPanel.visible && hdPacked.leftPanel.inward===0 && hdPacked.leftPanel.shrunk && hdPacked.leftPanel.along===268,
    'Sidebar opened after Overview scales down below Overview at inward=0');

// Sidebar opened first (order=1, prio=2) then Overview hovered second (order=2, prio=1):
// Sidebar stays full size and Overview scales down above Sidebar at inward=0.
const sbFirst=hdRequest('leftPanel','left',1,460,190,700,{priority:2,largeSurface:false});
const ovSecond=hdRequest('overview','top',2,232,100,1720,{priority:1,largeSurface:false,preserveAspect:true});
hdPacked=arrange([sbFirst,ovSecond],1920,1080,hdInsets);
assert(hdPacked.leftPanel.visible && !hdPacked.leftPanel.shrunk && hdPacked.leftPanel.inward===0,
    'Sidebar opened first retains full size at left edge');
assert(hdPacked.overview.visible && hdPacked.overview.inward===0 && hdPacked.overview.shrunk && hdPacked.overview.depth===154,
    'Overview opened after Sidebar scales down at top edge instead of jumping to bottom');

// Edgebar + Sidebar same-priority order rules:
// 1. Edgebar first (order=1, prio=2), Sidebar second (order=2, prio=2) -> Sidebar at inward=0, Edgebar pushed outward at full size.
const ebFirst=hdRequest('quickNotes','left',1,346,696,370,{priority:2,largeSurface:false});
const sbAfterEb=hdRequest('leftPanel','left',2,460,190,700,{priority:2,largeSurface:false});
hdPacked=arrange([ebFirst,sbAfterEb],1920,1080,hdInsets);
assert(hdPacked.leftPanel.visible && hdPacked.leftPanel.inward===0 && !hdPacked.leftPanel.shrunk,
    'Sidebar opened after Edgebar claims inward=0 at full size');
assert(hdPacked.quickNotes.visible && hdPacked.quickNotes.inward===456 && !hdPacked.quickNotes.shrunk,
    'Edgebar opened first is pushed outward to inward=456 while keeping full original size');

// 2. Sidebar first (order=1, prio=2), Edgebar second (order=2, prio=2) -> Edgebar at inward=0, Sidebar pushed outward at full size.
const sbBeforeEb=hdRequest('leftPanel','left',1,460,190,700,{priority:2,largeSurface:false});
const ebSecond=hdRequest('quickNotes','left',2,346,696,370,{priority:2,largeSurface:false});
hdPacked=arrange([sbBeforeEb,ebSecond],1920,1080,hdInsets);
assert(hdPacked.quickNotes.visible && hdPacked.quickNotes.inward===0 && !hdPacked.quickNotes.shrunk,
    'Edgebar opened after Sidebar claims inward=0 at full size');
assert(hdPacked.leftPanel.visible && hdPacked.leftPanel.inward===342 && !hdPacked.leftPanel.shrunk,
    'Sidebar opened first is pushed outward to inward=342 while keeping full original size');

console.log('PASS: anchors retained, inward partitioning, readable reflow, edge-locked Dock eviction/restoration and exact geometry');
"""
raise SystemExit(subprocess.run(["node","-e",program],cwd=root).returncode)
