import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';
const G=vm.createContext({Math,JSON,Number,Array});vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssGeometry.js',import.meta.url),'utf8'),G);
const old=vm.createContext({Math,JSON,Number,Array});vm.runInContext(execFileSync('git',['show','05c440e0b:modules/abyss/looks/AbyssGeometry.js'],{encoding:'utf8'}),old);
const L=vm.createContext({Math,JSON,Number,Array,Set});vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssLayout.js',import.meta.url),'utf8'),L);
let checks=0;function check(value,label){checks++;assert.ok(value,label)}
for(let bits=0;bits<16;bits++)for(let on=0;on<16;on++)for(const r of [12,34,64]){
 const edges=['left','top','right','bottom'],ins=Object.fromEntries(edges.map((edge,i)=>[edge,bits&(1<<i)?0:16])),choices=Object.fromEntries(edges.map((edge,i)=>[edge,!!(on&(1<<i))]));
 const mask=G.zeroCornerMask(ins,choices),pairs=[['left','top'],['top','right'],['right','bottom'],['bottom','left']];
 mask.forEach((v,i)=>check(v===pairs[i].some(edge=>ins[edge]===0&&choices[edge]),'shared corner has one deterministic OR owner'));
 for(const [x,y] of [[.5,.5],[399.5,.5],[399.5,239.5],[.5,239.5],[200,120],[200,.5],[.5,120]]){
  const off=G.distance(x,y,400,240,ins,r,[],24,24,{}),baseline=old.distance(x,y,400,240,ins,r,[],24,24);
  check(Object.is(off,baseline),'OFF preserves original distance exactly');
  if(bits===0)check(Object.is(G.distance(x,y,400,240,ins,r,[],24,24,choices),baseline),'nonzero edges ignore zero-corner option');
 }
}
for(const edge of ['top','right','bottom','left']){
 const base={edgeRoundZeroCorners:{top:false},outputLayouts:[{outputName:'B',placements:[],edgeRoundZeroCorners:{left:true},future:'keep'}]},flags={[edge]:true};
 const writes=L.saveProfile(base,'A',[],8,true,undefined,undefined,undefined,undefined,undefined,undefined,undefined,flags);
 check(writes['abyss.modules.outputLayouts'][0].future==='keep','other output preserved');
 check(L.optionsForOutput({outputLayouts:writes['abyss.modules.outputLayouts']},'A').edgeRoundZeroCorners[edge]===true,'output save/restart retains chosen flag');
 check(L.saveProfile(base,'A',[],8,false,undefined,undefined,undefined,undefined,undefined,undefined,undefined,flags)['abyss.modules.edgeRoundZeroCorners'][edge]===true,'global save retains flag');
}

// The owner retired detached corner patches. With no actual body there is
// no extra surface or shadow, regardless of a saved zero-width flag.
for(const radius of [12,34,64])for(let y=0;y<240;y+=3)for(let x=0;x<400;x+=5){
 const ins={left:0,top:0,right:0,bottom:0};
 check(Object.is(G.distance(x+.5,y+.5,400,240,ins,radius,[],24,29,{top:true,right:true,bottom:true,left:true}),
  old.distance(x+.5,y+.5,400,240,ins,radius,[],24,29)), 'empty contacts drew surplus corner geometry');
}
for(const edge of ['top','right','bottom','left']){
 const options={edgeThicknesses:{[edge]:0},edgeWidthAffectsModules:{[edge]:true}};
 const modules=L.normalize([{id:'one',kind:'clock',edge,position:.3,customSize:true,size:1},{id:'two',kind:'clock',edge,position:.7,customSize:true,size:1}],edge);
 check(L.edgeInsetsForModules(modules,options,1,16,48,false)[edge]===0,'0px paint expanded into a full module strip');
 check(L.edgeInsetsForModules(modules,options,1,16,48,true)[edge]>=48,'0px paint fix removed compositor reservations');
 check(L.localSurfaces(L.geometry(modules,400,240,options,1),400,240,options,1,48).length===2,'0px paint lost local module backings');
}
// Curvature uses the global Surface radius, not the body-specific radius.
const ins={left:0,top:0,right:0,bottom:0},record={surface:{x:150,y:-50,width:120,height:140},radius:29};
const small=G.distance(140.5,.5,400,240,ins,12,[record],24,29,{top:true});
const large=G.distance(140.5,.5,400,240,ins,64,[record],24,29,{top:true});
check(small!==large,'Surface Curvature did not change the actual contact');
// Nonzero adjacent Screen Edges round their inner corners against an enabled
// 0px Edge on all four sides (both bare edges and Scale-modules expanded strips).
for(const edge of ['top','right','bottom','left'])for(const strip of [10,44]){
 const mixed={left:strip,top:strip,right:strip,bottom:strip,[edge]:0};
 const pts=edge==='top'?[[strip+4,4],[400-strip-4,4]]
  :edge==='bottom'?[[strip+4,236],[400-strip-4,236]]
  :edge==='left'?[[4,strip+4],[4,240-strip-4]]
  :[[396,strip+4],[396,240-strip-4]];
 for(const [px,py] of pts){
  const dOff=G.distance(px,py,400,240,mixed,20,[],24,29,{});
  const dOn=G.distance(px,py,400,240,mixed,20,[],24,29,{[edge]:true});
  check(dOff>0 && dOn<0,`adjacent ${strip}px corner on 0px ${edge} did not round at (${px},${py})`);
 }
}
console.log('ABYSS_ZERO_CORNERS_PASS',checks);
