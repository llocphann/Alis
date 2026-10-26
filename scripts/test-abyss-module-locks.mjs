import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const layout=vm.createContext({Math,JSON,Number,Array});
vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssLayout.js',import.meta.url),'utf8'),layout);
const baseline=vm.createContext({Math,JSON,Number,Array});
const baselineSource=execFileSync('git',['show','0465ffc5ad7d7a6b9b1347f45a2b9c6ca1e798a5:modules/abyss/looks/AbyssLayout.js'],{encoding:'utf8'});
vm.runInContext(baselineSource,baseline);
let checks=0;
function check(ok,label){checks++;assert.ok(ok,label);}
function same(actual,wanted,label){checks++;assert.deepEqual(JSON.parse(JSON.stringify(actual)),JSON.parse(JSON.stringify(wanted)),label);}
function geometry(items,w,h,options){return layout.geometry(items,w,h,options,1);}
// R05 intentionally replaces vertical compact extents and rejects overfull
// layouts. Keep the original captured reference immutable; its fitting packing
// still checks unchanged bounds after supplying the requested full extents.
baseline.extent=layout.extent;
for(const edge of ['top','right','bottom','left'])for(const [w,h] of [[1920,1080],[853.5,479.25],[320,180]])for(const font of [.7,1,1.5,2])for(const alignment of ['free','start','center','end']){
 const entries=Array.from({length:10},(_,i)=>({id:'legacy'+i,kind:i%2?'weather':'clock',edge,position:i/9,alignment,enabled:i!==3,customSize:i===4,size:1.2}));
 const options={gap:16,edgeThickness:16,extents:{legacy5:0},editing:false};
 const actual=layout.geometry(layout.normalize(entries,edge),w,h,options,font).map(p=>{
  const copy={...p};delete copy.locked;delete copy.lockPosition;delete copy.lockScale;return copy;
 });
 if(layout.conflicts(actual).length) {
  check(actual.every(p=>p.capacityConflict),'overfull unlocked Edge is explicitly rejected');
  check(actual.every(p=>p.span===layout.extent(p.kind,false)*font*layout.moduleSize(p,options)),'rejection never compresses a full design');
  check(layout.capacityNotices(actual,w,h,font).length===1,'one repair target replaces rejected input');
 } else {
  const expected=baseline.geometry(baseline.normalize(entries,edge),w,h,options,font).map(p=>({...p,compact:!!entries.find(e=>e.id===p.id).compact}));
  same(actual.map(p=>({id:p.id,span:p.span,compact:p.compact,depth:p.depth})),expected.map(p=>({id:p.id,span:p.span,compact:p.compact,depth:p.depth})),'corner clearance preserves full content sizes and identities');
  valid(actual,w,h);
  check(actual.every(p=>p.along>=p.edgeStart-1e-7&&p.along+p.span<=p.edgeEnd+1e-7&&p.edgeStart>0),'R01 replaces flush endpoints with bounded clearance');
 }
}
function valid(records,w,h){
 for(const edge of ['top','right','bottom','left']){
  const length=['top','bottom'].includes(edge)?w:h;
  const entries=records.filter(p=>p.edge===edge&&!p.capacityConflict).sort((a,b)=>a.along-b.along);
  for(let i=0;i<entries.length;i++){
   const p=entries[i];check(Number.isFinite(p.along)&&p.along>=-1e-7&&p.along+p.span<=length+1e-7,'module remains on output');
   if(i)check(entries[i-1].along+entries[i-1].span<=p.along+1e-7,'neighbors never overlap');
  }
 }
}
for(const edge of ['top','right','bottom','left'])for(const [w,h] of [[1920,1080],[853.5,479.25],[480,320]])for(const alignment of ['free','start','center','end']){
 const horizontal=['top','bottom'].includes(edge),length=horizontal?w:h;
 const options={gap:8,extents:{a:84,b:60,c:72,new:64},edgeThickness:16,editing:true};
 const initial=layout.normalize([{id:'a',kind:'clock',edge,position:.3,alignment},{id:'b',kind:'battery',edge,position:.7},{id:'c',kind:'weather',edge,position:.9}],edge);
 check(initial.every(p=>p.locked===false),'existing layouts default unlocked');
 const before=geometry(initial,w,h,options).find(p=>p.id==='a');
 const locked=layout.setLocked(initial,'a',true,w,h,options,1);
 const a=locked.find(p=>p.id==='a');
 check(a.locked&&a.alignment===alignment&&a.position===.3,'lock preserves alignment/placement intent');
 same(layout.setLocked(locked,'a',true,w,h,options,1),locked,'repeated Lock does not recapture an anchor');
 for(const operation of ['insert','delete','resize','drag-into-lock','cross-edge']){
  let entries=locked;
  if(operation==='insert')entries=layout.normalize(locked.concat([{id:'new',kind:'timer',edge,position:.3}]),edge);
  if(operation==='delete')entries=locked.filter(p=>p.id!=='b');
  if(operation==='resize')entries=locked.map(p=>p.id==='b'?{...p,customSize:true,size:1.8}:p);
  if(operation==='drag-into-lock'||operation==='cross-edge'){
   const point=before.along+before.span/2;
   const x=operation==='cross-edge'?8:horizontal?point:edge==='left'?8:w-8;
   const y=operation==='cross-edge'?h/2:horizontal?edge==='top'?8:h-8:point;
   entries=layout.checkedMove(locked,'b',x,y,w,h,options,1,true).placements;
  }
  const records=geometry(entries,w,h,options),own=records.find(p=>p.id==='a');
  if(layout.conflicts(records).length) {
   check(records.filter(p=>p.edge===edge).every(p=>p.capacityConflict),'uncompressed locked interval rejects the affected Edge explicitly');
   check(layout.localSurfaces(records,w,h,{...options,edgeWidthAffectsModules:{[edge]:false}},1,48).every(p=>p.edge!==edge),'rejected interval never paints a phantom module');
   same(entries.find(p=>p.id==='a'),a,'rejected candidate preserves the saved pin');
   const unchanged=geometry(locked,w,h,options).find(p=>p.id==='a');
   check(Math.abs(unchanged.along-before.along)<1e-7&&Math.abs(unchanged.span-before.span)<1e-7,'original accepted pin remains unchanged');
   continue;
  }
  check(!layout.conflicts(records).length,'fitting uncompressed edits stay feasible');
  check(Math.abs(own.along-before.along)<1e-7&&Math.abs(own.span-before.span)<1e-7,'locked reservation never moves on '+operation);
  same(entries.find(p=>p.id==='a'),a,'neighbor operations preserve stored lock/edge/alignment');valid(records,w,h);
 }
 same(layout.move(locked,'a',w-8,h/2,w,h),locked,'direct move cannot bypass lock');
 const denied=layout.snapMove(locked,'a',w-8,h/2,w,h,options,1);
 check(denied.rejected&&denied.guides.length===0,'locked snap is rejected with feedback');same(denied.placements,locked,'locked snap preserves source');
 const released=layout.setLocked(locked,'a',false,w,h,options,1);
 check(!released.find(p=>p.id==='a').locked,'explicit Unlock clears the flag');
 const point=horizontal?length*.6:w-8;
 check(JSON.stringify(layout.move(released,'a',point,h-8,w,h))!==JSON.stringify(released),'unlocked module can move again');
 const profiles={outputLayouts:[{outputName:'B',placements:locked}]};
 const writes=layout.saveProfile(profiles,'A',locked,8,true);
 same(writes['abyss.modules.outputLayouts'].find(p=>p.outputName==='B'),profiles.outputLayouts[0],'unrelated output unchanged');
 same(layout.resolve({outputLayouts:writes['abyss.modules.outputLayouts']},'A',[]),locked,'output-only restart retains locks');
 same(layout.resolve(layoutOptions(layout.saveProfile(profiles,'A',locked,8,false)),'C',[]),locked,'global restart retains locks');
}
function layoutOptions(writes){return Object.fromEntries(Object.entries(writes).map(([key,value])=>[key.replace('abyss.modules.',''),value]));}
const options={extents:{full:466,mover:80},gap:8,edgeThickness:16,editing:true};
let full=layout.normalize([{id:'full',kind:'clock',edge:'top',position:.5},{id:'mover',kind:'timer',edge:'bottom',position:.5}],'top');
full=layout.setLocked(full,'full',true,480,320,options,1);
const impossible=layout.checkedMove(full,'mover',240,8,480,320,options,1,false);
check(impossible.rejected,'full edge rejects insertion rather than moving its lock');same(impossible.placements,full,'rejected move is a transaction no-op');
const tooSmall=geometry(full,300,320,options);check(layout.conflicts(tooSmall).length>0,'output shrink exposes conflict');valid(tooSmall,300,320);
check(full[0].locked&&full[0].lockPosition===.5,'fallback never unlocks or rewrites the source anchor');
same(geometry(full,480,320,options).find(p=>p.id==='full').along,7,'returning output restores reserved position with corner clearance');
const hidden=layout.normalize([{...full[0],enabled:false}], 'top');check(geometry(hidden,480,320,options).length===0&&hidden[0].locked,'disabled lock survives without reserving invisible space');
check(geometry([full[0]],480,320,{...options,editing:false,extents:{full:0}}).length===0,'measured-empty locked module does not reserve phantom gaps');
check(geometry([full[0]],480,320,{...options,edgeThicknesses:{top:0}}).length===0,'coupled zero-width releases a hidden lock');
check(geometry([full[0]],480,320,{...options,edgeThicknesses:{top:0},edgeWidthAffectsModules:{top:false}}).length===1,'edge-only zero width retains its module reservation');
// Deterministic generated placements exercise mixed reservations and allocation.
let random=11939;const next=()=>{random=(random*1664525+1013904223)>>>0;return random/4294967296;};
for(let trial=0;trial<180;trial++){
 const w=320+next()*1200,h=320+next()*800,edge=['top','right','bottom','left'][trial%4];
 const opts={gap:Math.floor(next()*20),edgeThickness:16,editing:true,extents:{}};
 let entries=layout.normalize(Array.from({length:2+trial%9},(_,i)=>({id:'p'+i,kind:'clock',edge,position:next(),alignment:'free'})),edge);
 for(const p of entries)opts.extents[p.id]=24+next()*90;
 const initialRecords=geometry(entries,w,h,opts);
 if(layout.conflicts(initialRecords).length){
  const before=JSON.stringify(entries);
  const rejected=layout.checkedBatch(entries,entries.filter((_,i)=>i%3===0).map(p=>p.id),'locked',true,w,h,opts,1);
  check(!!rejected.rejected,'overfull generated layout cannot capture new pins');
  same(rejected.placements,entries,'rejected lock leaves every source entry intact');
  check(JSON.stringify(entries)===before&&layout.capacityNotices(initialRecords,w,h,1).length===1,'generated capacity failure is explicit and non-destructive');
  continue;
 }
 for(const p of entries.filter((_,i)=>i%3===0))entries=layout.setLocked(entries,p.id,true,w,h,opts,1);
 const baseline=geometry(entries,w,h,opts);check(!layout.conflicts(baseline).length,'captured feasible locks stay feasible');valid(baseline,w,h);
 const unlocked=entries.find(p=>!p.locked);
 const moved=layout.checkedMove(entries,unlocked.id,next()*w,next()*h,w,h,opts,1,trial%2===0);
 const records=geometry(moved.placements,w,h,opts);valid(records,w,h);
 for(const p of baseline.filter(p=>p.locked)){
  const actual=records.find(rec=>rec.id===p.id);check(Math.abs(actual.along-p.along)<1e-7&&Math.abs(actual.span-p.span)<1e-7,'generated moves preserve each reservation');
 }
}
// Flexible adaptation across Screen Edge width, Edge size, overall scale, and Abyss curvature:
for(const edge of ['top','right','bottom','left']){
 const legacy=layout.normalize([
  {id:'distroIcon',kind:'distroIcon',edge,position:.00834,alignment:'start',joinCorner:true,locked:true,lockPosition:.0078,lockScale:1},
  {id:'resources',kind:'resources',edge,position:.06},
  {id:'activeWindow',kind:'activeWindow',edge,position:.15},
  {id:'workspaces',kind:'workspaces',edge,position:.5},
  {id:'clock',kind:'clock',edge,position:.62,locked:true,lockPosition:.62,lockScale:1},
  {id:'tray',kind:'tray',edge,position:.95,joinCorner:true},
  {id:'battery',kind:'battery',edge,position:.9915,alignment:'end',joinCorner:true,locked:true,lockPosition:.9921,lockScale:1}
 ],edge);
 for(const radius of [0,12,20,28,48,64,80])for(const thick of [6,10,16,24,32,40])for(const edgeScale of [.6,1,1.35,1.8])for(const editing of [false,true]){
  const opts={editing,cornerRadius:radius,edgeThickness:thick,edgeThicknesses:{[edge]:thick},edgeSizes:{[edge]:edgeScale},size:edgeScale>1.5?1.2:1};
  const recs=geometry(legacy,1920,1080,opts,1);
  check(!layout.conflicts(recs).length,'locked modules flexibly adapt to edge thickness/size/curvature without conflict');
  valid(recs,1920,1080);
  const startRec=recs.find(r=>r.id==='distroIcon'),endRec=recs.find(r=>r.id==='battery');
  check(Math.abs(startRec.along-startRec.edgeStart)<1e-6,'corner-welded start lock tracks updated corner clearance');
  check(Math.abs(endRec.along+endRec.span-endRec.edgeEnd)<1e-6,'corner-welded end lock tracks updated corner clearance');
 }
}
console.log('ABYSS_MODULE_LOCKS_PASS',checks);
