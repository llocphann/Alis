const fs=require('fs'),vm=require('vm'),assert=require('assert');
const base=process.argv[2];function load(name){let c={};vm.createContext(c);vm.runInContext(fs.readFileSync(base+'/'+name+'.js','utf8'),c);return c}const a=load('baseline'),b=load('prototype');
let seed=12385931;const rnd=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296};const args=[];let pairs=0,rows=0;
for(const edge of['top','bottom','left','right'])for(const zero of[false,true])for(const k of[4,24,48,64])for(let i=0;i<35;i++){
 const w=480+rnd()*1800,h=320+rnd()*1000,ins={left:8,top:8,right:8,bottom:8};if(zero)ins[edge]=0;
 const n=a.horizontal(edge)?w:h,along=i%3===0?0:i%3===1?n-150:40+rnd()*(n-200),p=[.01,.2,.7,1,1.025][i%5];
 const rec=a.panel(w,h,ins,edge,along,90+rnd()*600,20+rnd()*400,p,14,[],true);rec.radius=[0,12,29,64][i%4];const x=[w,h,ins,edge,rec,[0,12,34,68][i%4],k,29,{[edge]:zero}];
 const ra=a.popupShoulders(...x),rb=b.popupShoulders(...x);assert.strictEqual(JSON.stringify(ra),JSON.stringify(rb),'case'+pairs);pairs++;rows+=ra.length;args.push(x);
}
const results=[];for(let round=0;round<4;round++)for(const name of round%2?['prototype','baseline']:['baseline','prototype']){
 const c=name==='baseline'?a:b;let sum=0,t=process.hrtime.bigint();for(let i=0;i<400;i++)sum+=c.popupShoulders(...args[(i*37)%args.length]).length;results.push({round,name,ms:Number(process.hrtime.bigint()-t)/1e6,sum});
}
console.log(JSON.stringify({scope:'offline V8 numeric-only research; not QV4/behavior/owner performance qualification',pairs,rows,results},null,2));
