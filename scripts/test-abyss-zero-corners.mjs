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
for(const r of [12,34,64])for(let step=1;step<90;step++){
 const angle=step*Math.PI/180,u=r-r*Math.cos(angle),v=r-r*Math.sin(angle);
 check(Math.abs(G.innerCornerDistance(u,v,r))<1e-9,'quarter arc has exact circular tangency');
 check(G.innerCornerDistance(u*.9,v*.9,r)<0,'monitor-corner side is painted');
 check(G.innerCornerDistance(u+r*.05,v+r*.05,r)>0,'workspace side remains clear');
}
for(const r of [12,34,64])for(const [u,v] of [[1.5*r,.5*r],[.5*r,1.5*r],[1.5*r,1.5*r]]){
 const a=Math.hypot(u-r,v),b=Math.hypot(u,v-r),expected=u>r&&v>r?Math.min(a,b):u>r?a:b;
 check(G.innerCornerDistance(u,v,r)===expected,'outside-quarter distances cannot paint a false ring');
}
for(const edge of ['top','right','bottom','left']){
 const base={edgeRoundZeroCorners:{top:false},outputLayouts:[{outputName:'B',placements:[],edgeRoundZeroCorners:{left:true},future:'keep'}]},flags={[edge]:true};
 const writes=L.saveProfile(base,'A',[],8,true,undefined,undefined,undefined,undefined,undefined,undefined,undefined,flags);
 check(writes['abyss.modules.outputLayouts'][0].future==='keep','other output preserved');
 check(L.optionsForOutput({outputLayouts:writes['abyss.modules.outputLayouts']},'A').edgeRoundZeroCorners[edge]===true,'output save/restart retains chosen flag');
 check(L.saveProfile(base,'A',[],8,false,undefined,undefined,undefined,undefined,undefined,undefined,undefined,flags)['abyss.modules.edgeRoundZeroCorners'][edge]===true,'global save retains flag');
}

// Reproduction of the owner's missing top corners: local module backing
// extends through the finite corner square and used to erase the curve.
for (const corner of ['top-left','top-right','bottom-right','bottom-left']) {
 const right=corner.includes('right'),bottom=corner.includes('bottom');
 const width=400,height=240,r=34;
 const x=right?width-28:28,y=bottom?height-28:28;
 const insideX=right?width-2:2,insideY=bottom?height-2:2;
 const module={surface:{x:right?width-175:-25,y:bottom?height-145:-25,width:200,height:170},radius:0};
 const physical={left:0,top:0,right:0,bottom:0};
 const chosen={[(bottom?'bottom':'top')]:true};
 const disabled=G.distance(x,y,width,height,physical,r,[module],24,0,{});
 const enabled=G.distance(x,y,width,height,physical,r,[module],24,0,chosen);
 check(disabled<0,corner+' fixture must be filled by the module before R02');
 check(enabled>0,corner+' 0px workspace cutout remains clear over module backing');
 check(G.distance(insideX,insideY,width,height,physical,r,[module],24,0,chosen)<0,
   corner+' physical outer pixel remains painted');
 check(G.distance(x,y,width,height,physical,r,[module],24,0,{[(bottom?'top':'bottom')]:true})===disabled,
   corner+' unrelated Edge checkbox does not clip local module');
}
// A module-expanded inset is not the configured 0px width. The option must
// still take effect while maintaining the same painted-inset geometry.
{
 const painted={left:0,top:56,right:0,bottom:0},widths={left:0,top:0,right:0,bottom:0};
 const rec={surface:{x:-25,y:-25,width:180,height:160},radius:0};
 const noChoice=G.distance(28,84,400,240,painted,34,[rec],24,0,{});
 const selected=G.distance(28,84,400,240,painted,34,[rec],24,0,{top:true},widths);
 check(noChoice<0 && selected>0,'0px top choice survives module-expanded render inset');
 check(G.zeroCornerMask(widths,{top:true})[0] && !G.zeroCornerMask(painted,{top:true})[0],
   'configured and effective widths are distinguished');
}
console.log('ABYSS_ZERO_CORNERS_PASS',checks);
