import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const p=vm.createContext({Math,JSON,Number,Array,Set});
vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssLayout.js',import.meta.url),'utf8'),p);
let checks=0;
const check=(ok,label)=>{checks++;assert.ok(ok,label);};
const same=(a,b,label)=>{checks++;assert.deepEqual(JSON.parse(JSON.stringify(a)),JSON.parse(JSON.stringify(b)),label);};
const edges=['top','right','bottom','left'];
const point=(edge,along,w,h)=>({x:['top','bottom'].includes(edge)?along:edge==='left'?1:w-1,y:['top','bottom'].includes(edge)?edge==='top'?1:h-1:along});
const options={gap:8,edgeThickness:16,editing:true,extents:{a:40,b:52,c:36,d:30},edgeSizes:{top:1,right:1.2,bottom:.8,left:1}};
for(const [w,h] of [[1600,1000],[840,600],[480,340]])for(const edge of edges){
 const length=['top','bottom'].includes(edge)?w:h;
 const source=p.normalize([{id:'a',kind:'clock',edge,position:.25},{id:'b',kind:'clock',edge,position:.45},{id:'c',kind:'clock',edge,position:.88},{id:'d',kind:'clock',edge:edges[(edges.indexOf(edge)+1)%4],position:.2}],'top');
 const geometry=entries=>p.geometry(entries,w,h,options,1),original=geometry(source),before=JSON.stringify(source);
 const batch=(items,ids,action,value)=>p.checkedBatch(items,ids,action,value,w,h,options,1);
 const locked=batch(source,['a','b','a'],'locked',true);check(!locked.rejected,'batch Lock feasible');
 for(const id of ['a','b']){
  check(locked.placements.find(e=>e.id===id).locked,'each target locked');
  const a=geometry(locked.placements).find(r=>r.id===id),b=original.find(r=>r.id===id);
  check(Math.abs(a.along-b.along)<1e-6&&Math.abs(a.span-b.span)<1e-6,'simultaneous lock captures approved slots');
 }
 same(locked.placements.find(e=>e.id==='c'),source.find(e=>e.id==='c'),'unselected record untouched');
 const unlocked=batch(locked.placements,['a','b'],'locked',false);check(!unlocked.rejected&&unlocked.placements.every(e=>!e.locked),'explicit batch Unlock');
 const mixed=p.setLocked(source,'a',true,w,h,options,1);
 for(const action of ['size','customSize','alignment','edge','position','depth']){
  const result=batch(mixed,['a','b'],action,{size:1.2,customSize:true,alignment:'start',edge:'bottom',position:.7,depth:1.2}[action]);
  check(!!result.rejected,'mixed locked placement edit rejected '+action);same(result.placements,mixed,'rejected batch is atomic');
 }
 for(const action of ['locked','size','remove','enabled']){
  const stale=batch(source,['a','missing'],action,true);check(!!stale.rejected,'stale target rejected');same(stale.placements,source,'stale batch no partial edit');
 }
 const off=batch(mixed,['a','b'],'enabled',false);check(!off.rejected&&off.placements.filter(e=>['a','b'].includes(e.id)).every(e=>!e.enabled),'explicit Disable including locked targets');
 check(off.placements.find(e=>e.id==='a').locked,'Disable retains lock');
 const on=batch(off.placements,['a','b'],'enabled',true);check(!on.rejected&&on.placements.every(e=>e.enabled),'Enable preserves anchor');
 const removed=batch(mixed,['a','b'],'remove',true);same(removed.placements.map(e=>e.id),['c','d'],'Remove exact targets, including locks');
 const across=batch(source,['a','d'],'customSize',true);check(!across.rejected,'mixed-Edge size edit supported');
 check(across.placements.find(e=>e.id==='d').size===p.edgeSize(options,source.find(e=>e.id==='d').edge),'custom size inherits each own Edge');
 const mixedEdge=p.checkedGroupMove(source,['a','d'],'a',w/2,1,w,h,options,1,true);
 check(!!mixedEdge.rejected,'mixed-Edge drag explicitly denied');same(mixedEdge.placements,source,'mixed-Edge drag no partial transformation');
 const denied=p.checkedGroupMove(mixed,['a','b'],'a',w/2,1,w,h,options,1,true);
 check(!!denied.rejected,'mixed lock drag rejected');same(denied.placements,mixed,'drag no partial transformation');
 const to=point(edge,length*.36,w,h),move=p.checkedGroupMove(source,['a','b'],'a',to.x,to.y,w,h,options,1,false);
 check(!move.rejected,'free same-Edge group move succeeds '+edge);
 const moved=geometry(move.placements);const offset=records=>records.find(r=>r.id==='b').along-records.find(r=>r.id==='a').along;
 check(Math.abs(offset(moved)-offset(original))<1e-6,'group rendered spacing preserved');
 same(move.placements.find(e=>e.id==='d'),source.find(e=>e.id==='d'),'unselected other Edge untouched');
 for(const target of edges.filter(e=>e!==edge)){
  const n=['top','bottom'].includes(target)?w:h,dest=point(target,n*.5,w,h);
  const group=p.checkedGroupMove(source,['a','b'],'b',dest.x,dest.y,w,h,options,1,true);
  if(group.rejected){same(group.placements,source,'destination too small/blocked preserves source');continue;}
  check(group.placements.filter(e=>['a','b'].includes(e.id)).every(e=>e.edge===target),'group crosses Edge coherently');
  const records=geometry(group.placements),a=records.find(r=>r.id==='a'),b=records.find(r=>r.id==='b');
  check(a.along+a.span<=b.along+1e-6,'orientation retains order');
  check(Math.abs(b.along-a.along-a.span-(original.find(r=>r.id==='b').along-original.find(r=>r.id==='a').along-original.find(r=>r.id==='a').span))<1e-6,'destination gaps preserved');
 }
 const single=p.checkedGroupMove(source,['a'],'a',to.x,to.y,w,h,options,1,true);
 same(single,p.checkedMove(source,'a',to.x,to.y,w,h,options,1,true),'one selected uses original single-move geometry/guides');
 const saved=p.saveProfile({outputLayouts:[{outputName:'B',placements:source}]},'A',move.placements,8,true);
 same(saved['abyss.modules.outputLayouts'].find(e=>e.outputName==='B').placements,source,'other output profile unchanged');
 same(p.resolve({outputLayouts:JSON.parse(JSON.stringify(saved['abyss.modules.outputLayouts']))},'A',[]),move.placements,'actual persisted shape roundtrip');
 check(!JSON.stringify(saved).includes('selectedIds')&&!JSON.stringify(saved).includes('multiSelect'),'selection never persisted');
 check(JSON.stringify(source)===before,'transactions never mutate source');
}
// A locked full Edge cannot be overwritten by a multi-group insertion.
let full=p.normalize([{id:'full',kind:'clock',edge:'top',position:.5},{id:'a',kind:'clock',edge:'bottom',position:.2},{id:'b',kind:'clock',edge:'bottom',position:.4}],'top');
const opts={...options,extents:{...options.extents,full:800}};
full=p.setLocked(full,'full',true,800,600,opts,1);
const collision=p.checkedGroupMove(full,['a','b'],'a',400,1,800,600,opts,1,true);
check(!!collision.rejected,'full locked Edge rejects group');same(collision.placements,full,'full Edge immutable');
let seed=72503;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
let accepted=0,rejected=0;
for(let trial=0;trial<120;trial++){
 const w=400+random()*1100,h=300+random()*800,edge=edges[trial%4];
 const opts={gap:Math.floor(random()*24),editing:true,edgeThickness:16,extents:{}};
 let entries=p.normalize(Array.from({length:6},(_,i)=>({id:'r'+i,kind:i%2?'clock':'weather',edge,position:random(),size:i===3?1.2:1})),edge);
 for(const item of entries)opts.extents[item.id]=20+random()*60;
 entries=p.setLocked(entries,'r5',true,w,h,opts,1);
 const original=p.geometry(entries,w,h,opts,1),anchor=original.find(r=>r.id==='r5'),target=edges[(trial+1)%4],length=['top','bottom'].includes(target)?w:h;
 const dest=point(trial%3?edge:target,length*random(),w,h);
 const group=p.checkedGroupMove(entries,['r0','r1'],'r0',dest.x,dest.y,w,h,opts,1,trial%2===0);
 if(group.rejected){rejected++;same(group.placements,entries,'generated blocked groups are transactional');continue;}
 accepted++;
 const records=p.geometry(group.placements,w,h,opts,1),own=records.find(r=>r.id==='r5');
 check(Math.abs(anchor.along-own.along)<1e-6&&Math.abs(anchor.span-own.span)<1e-6,'generated group keeps unselected locked reservation');
 for(const side of edges){
  const n=['top','bottom'].includes(side)?w:h,list=records.filter(r=>r.edge===side).sort((a,b)=>a.along-b.along);
  for(let i=0;i<list.length;i++){
   check(list[i].along>=-1e-6&&list[i].along+list[i].span<=n+1e-6,'generated groups remain on screen');
   if(i)check(list[i-1].along+list[i-1].span<=list[i].along+1e-6,'generated groups never overlap');
  }
 }
}
check(accepted>10&&rejected>10,'generated cases exercise both real moves and guarded rejection');
console.log('ABYSS_MULTI_SELECTION_PASS',checks);
