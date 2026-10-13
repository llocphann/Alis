import fs from 'node:fs';import vm from 'node:vm';
const source=fs.readFileSync('modules/abyss/looks/AbyssGeometry.js','utf8');const ctx=vm.createContext({Math,Number,Object});vm.runInContext(source,ctx);
let seed=19730291;const rng=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296};
let skipped=0,checks=0,maxBoundOvershoot=-Infinity;
for(let i=0;i<250000;i++){
 const width=240+rng()*15800,height=240+rng()*15800;const edge=i%5;
 const x=(rng()-.1)*width*1.2,y=(rng()-.1)*height*1.2;
 const span=1+rng()*Math.min(1800,edge===0||edge===2?width:height),depth=1+rng()*1000;
 let rect=edge===0?{x:rng()*width,y:-50,width:span,height:depth+50}:edge===2?{x:rng()*width,y:height-depth,width:span,height:depth+50}:edge===3?{x:-50,y:rng()*height,width:depth+50,height:span}:edge===1?{x:width-depth,y:rng()*height,width:depth+50,height:span}:{x:rng()*width,y:rng()*height,width:span,height:depth};
 const radius=i%5===0?0:rng()*600,curvature=i%9===0?0:rng()*400;
 const enabled=[rng()>.5,rng()>.5,rng()>.5,rng()>.5];
 const b=ctx.surfaceDistance(x,y,width,height,rect,radius,enabled,curvature);
 const lower=Math.max(rect.x-x,x-rect.x-rect.width,rect.y-y,y-rect.y-rect.height)-curvature;
 maxBoundOvershoot=Math.max(maxBoundOvershoot,lower-b);
 const k=Math.max(.1,rng()*128),a=i%1024===0?-0:(rng()-.5)*32000;
 const h=Math.max(k-Math.abs(a-b),0)/k,original=Math.min(a,b)-h*h*k*.25;
 const bypass=lower>a+k+1;
 const candidate=bypass?a:original;
 if(bypass){skipped++;if(!Object.is(candidate,original))throw new Error('Union value changed at '+i+': '+JSON.stringify({x,y,rect,radius,curvature,a,b,lower,k,original,candidate,enabled}));}
 checks++;
}
const result={checks,skipped,maxBoundOvershoot,sourceSha:'55b1fd183876543d51e8d36394c155b5c9c50a35',scope:'seeded JS numeric support model, exact union-result check; not native GLSL Float32 or GPU/owner acceptance'};
fs.writeFileSync('.git/maintainer-validation/20261014-field-support-research/support-model.json',JSON.stringify(result,null,2)+'\n');console.log('SUPPORT_MODEL_PASS',JSON.stringify(result));
