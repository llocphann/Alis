import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const G=vm.createContext({Math,Number,Array,JSON});
vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssGeometry.js',import.meta.url),'utf8'),G);
let checks=0;
function check(v,m){checks++;assert.ok(v,m)}
const w=853.5,h=479.25;
const allContacts=[true,true,true,true];
function scene(edge,t,n){return edge==='top'?[t,n]:edge==='bottom'?[t,h-n]:edge==='left'?[n,t]:[w-n,t]}
function rect(edge,start,span,depth){return edge==='top'?{x:start,y:-50,width:span,height:depth+50}:edge==='bottom'?{x:start,y:h-depth,width:span,height:depth+50}:edge==='left'?{x:-50,y:start,width:depth+50,height:span}:{x:w-depth,y:start,width:depth+50,height:span}}
for(const edge of ['top','bottom','left','right'])for(const start of [67.5,121.25,255])for(const span of [64,140])for(const depth of [8,24,120])for(const radius of [0,12,34,64]){
 const body=rect(edge,start,span,depth),bodyRadius=Math.min(radius,span/2,(depth+50)/2);
 const r=Math.max(0,Math.min(radius,span/2,depth-bodyRadius));
 for(let i=1;i<24;i++){
  if(r>0){
   // Independent circle geometry: a moving boundary, not fixed screen corners.
   const q=r*i/24,n=r-Math.sqrt(r*r-q*q);
   for(const t of [start-r+q,start+span+r-q]){
    const p=scene(edge,t,n),d=G.surfaceDistance(...p,w,h,body,radius,allContacts);
    check(Math.abs(d)<1e-8,`contact left the tangent circle ${edge} ${d}`);
   }
   const p=scene(edge,start-.125,r*.1);
   check(G.surfaceDistance(...p,w,h,body,radius,allContacts)<0,'false interior seam at body contact');
  }
  const p=scene(edge,start-100,i);
  check(G.physicalContactDistance(...p,w,h,body,radius,allContacts)>24,'contact escaped local footprint');
 }
 if(r>0){
  const small=.0001*r;
  const atBoundary=(r-Math.sqrt(r*r-small*small))/small;
  check(atBoundary<.0001,'contact tangent is not parallel to screen');
 }
 const points=[[400,250],[8,8],[800,440],[start,80]];
 for(const p of points)check(Number.isFinite(G.surfaceDistance(...p,w,h,body,radius)),'nonfinite field');
 const corners={top:true,right:true,bottom:true,left:true};
 for(const insets of [{left:0,top:0,right:0,bottom:0},{left:16,top:16,right:16,bottom:16}]){
  const record={surface:body,radius:radius,edge:edge};
  const rows=G.popupShoulders(w,h,insets,edge,record,34,24,radius,corners,insets);
  for(const row of rows){
   check(row.x>=0&&row.y>=0&&row.x+row.width<=Math.floor(w)+1&&row.y+row.height<=Math.floor(h)+1,'native contact escaped output');
   for(let dx=0;dx<row.width;dx++)for(let dy=0;dy<row.height;dy++){
    const d=G.distance(row.x+dx+.5,row.y+dy+.5,w,h,insets,34,[record],24,radius,corners,insets);
    check(d<0,'native shoulder captured unpainted pixel');
   }
  }
 }
}
// A shallow inherited/custom rounded module cannot grow a tip over its lower
// corner. Independent body distance owns that entire corner and its shadow.
for(const edge of ['top','bottom','left','right'])for(const bodyRadius of [0,12,29,38,64])for(const curvature of [12,34,64]){
 const body=rect(edge,140,220,48),effective=Math.min(bodyRadius,110,49),straight=Math.max(0,48-effective);
 for(let n=Math.ceil(straight)+.25;n<72;n+=.5)for(const t of [139.9,136,145,160,359.9,364]){
  const p=scene(edge,t,n),distance=G.surfaceDistance(...p,w,h,body,bodyRadius,allContacts,curvature);
  check(Object.is(distance,G.roundedDistance(...p,body,bodyRadius)),`contact changed inherited lower corner/shadow ${edge} ${bodyRadius} ${curvature} ${t} ${n}`);
 }
 const cap=G.physicalContactRadius(body,curvature,bodyRadius,220,48);
 check(cap<=straight,'contact crossed the inherited straight-side limit');
}
const detached={x:120,y:100,width:240,height:180};
for(let y=0;y<480;y+=7)for(let x=0;x<854;x+=9){
 check(G.physicalContactDistance(x,y,w,h,detached,34,allContacts)===Infinity,'detached body gained a screen contact');
 check(Object.is(G.surfaceDistance(x,y,w,h,detached,34,allContacts),G.roundedDistance(x,y,detached,34)),'detached body shape changed');
}
// Bidirectional pixel oracle: every newly painted shoulder must be reachable,
// including a 0px Edge with smoothing disabled. Never bridge an empty corner.
for(const edge of ['top','bottom','left','right'])for(const start of [4.5,120.25])for(const softness of [0,24])for(const cut of [false,true]){
 const body=rect(edge,start,140,90),insets={left:0,top:0,right:0,bottom:0};
 const corners={top:cut,right:cut,bottom:cut,left:cut};
 const rows=G.popupShoulders(w,h,insets,edge,{surface:body,radius:34},34,softness,34,corners,insets);
 check(cut?rows.length>0:rows.length===0,'0px contact mask ignores its per-Edge control');
 const extent=edge==='top'||edge==='bottom'?w:h;
 for(let cross=0;cross<Math.ceil(34+softness)+4;cross++)for(let t=Math.max(0,Math.floor(start-35));t<Math.min(Math.floor(extent),Math.ceil(start+175));t++){
  const x=edge==='top'||edge==='bottom'?t:edge==='left'?cross:Math.ceil(w)-cross-1;
  const y=edge==='left'||edge==='right'?t:edge==='top'?cross:Math.ceil(h)-cross-1;
  if(x>=Math.floor(w)||y>=Math.floor(h))continue;
  // The main body bounds own the central rectangle; the rows own its sides.
  const tangent=edge==='top'||edge==='bottom'?x:y;
  if(tangent>=Math.floor(start)&&tangent<Math.ceil(start+140))continue;
  const d=G.distance(x+.5,y+.5,w,h,insets,34,[{surface:body,radius:34}],softness,34,corners,insets);
  const base=G.distance(x+.5,y+.5,w,h,insets,34,[],softness,34,corners,insets);
  const covered=rows.some(row=>x>=row.x&&x<row.x+row.width&&y>=row.y&&y<row.y+row.height);
  check(!covered||d<0,'native contact captured an empty pixel');
  if(d<0&&base>=0)check(covered,'newly painted contact lost native coverage '+JSON.stringify({edge,start,softness,cut,x,y,d,covered}));
 }
}
// Nonzero physical widths must ignore even a saved enabled flag. Absence of
// an opt-in restores the original local body contour exactly on every Edge.
for(const edge of ['top','bottom','left','right'])for(const width of [0,1,10,16,40])for(const selected of [false,true]){
 const insets={left:16,top:16,right:16,bottom:16,[edge]:width},choices={[edge]:selected};
 const mask=G.physicalContactMask(insets,choices),index=['top','right','bottom','left'].indexOf(edge);
 check(mask[index]===(selected&&width===0),'configured 0px checkbox gating failed');
 check(mask.filter(Boolean).length===(selected&&width===0?1:0),'rounding leaked to another Edge');
 const body=rect(edge,120.25,140,90);
 if(!mask[index])for(let n=0;n<50;n++)for(let t=80;t<305;t+=7){
  const p=scene(edge,t+.5,n+.5);
  check(Object.is(G.surfaceDistance(...p,w,h,body,34,mask),G.roundedDistance(...p,body,34)),'disabled/nonzero rounding changed body pixels');
 }
}
console.log('ABYSS_PHYSICAL_CONTACTS_PASS',checks,'moving four-edge tangents, bounded native coverage and detached parity');
