
import QtQuick
import Quickshell
import "baseline.js" as Base
import "prototype.js" as Candidate
ShellRoot {
 id:root
 Component.onCompleted:{Quickshell.watchFiles=false;Qt.callLater(root.run)}
 function run(){try{
  let seed=12385931;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296}
  const cases=[];let pairs=0,fields=0,rows=0;
  for(const edge of["top","bottom","left","right"])for(const zero of[false,true])for(const k of[4,24,48,64])for(let i=0;i<35;i++){
   const w=480+rnd()*1800,h=320+rnd()*1000,ins={left:8,top:8,right:8,bottom:8};if(zero)ins[edge]=0;
   const n=Base.horizontal(edge)?w:h,along=i%3===0?0:i%3===1?n-150:40+rnd()*(n-200),p=[.01,.2,.7,1,1.025][i%5];
   const rec=Base.panel(w,h,ins,edge,along,90+rnd()*600,20+rnd()*400,p,14,[],true);rec.radius=[0,12,29,64][i%4];
   const args=[w,h,ins,edge,rec,[0,12,34,68][i%4],k,29,{[edge]:zero}];
   const a=Base.popupShoulders(...args),b=Candidate.popupShouldersSnapshot(...args);
   if(a.length!==b.length)throw new Error("row count "+pairs)
   for(let j=0;j<a.length;j++)for(const key of["x","y","width","height"]){fields++;if(!Object.is(a[j][key],b[j][key]))throw new Error("row value "+pairs+":"+j+":"+key)}
   cases.push(args);pairs++;rows+=a.length;
  }

  const results=[];
  for(let round=0;round<4;round++)for(const name of round%2?["prototype","baseline"]:["baseline","prototype"]){
   const module=name==="baseline"?Base:Candidate;let sum=0;const before=Date.now();
   for(let i=0;i<400;i++)sum+=(name==="baseline"?module.popupShoulders(...cases[(i*37)%cases.length]):module.popupShouldersSnapshot(...cases[(i*37)%cases.length])).length
   results.push({round,name,ms:Date.now()-before,sum})
  }
  if(Base.popupShoulders.length!==Candidate.popupShoulders.length)throw new Error("public arity changed")
  let observableCases=0,observableReads=0;
  function observe(module,mode){
   const trace=[];let count=0;const values={x:100.25,y:-50,width:240.5,height:210};
   const surface={};for(const key of["x","y","width","height"])Object.defineProperty(surface,key,{get(){trace.push(key);count++;if(mode>0 && count===mode)throw new TypeError("fixture getter "+key);return values[key]}})
   const record={get surface(){trace.push("surface");return surface},get radius(){trace.push("radius");return 29}}
   let result,error=null;try{result=module.popupShoulders(800,600,{left:8,top:8,right:8,bottom:8},"top",record,34,24,29)}catch(e){error={name:e.name,message:e.message}}
   return {trace,result,error}
  }
  for(const mode of[0,1,2,3,4,5,10,20,100]){const a=observe(Base,mode),b=observe(Candidate,mode);if(JSON.stringify(a)!==JSON.stringify(b))throw new Error("observable fallback "+mode);observableCases++;observableReads+=a.trace.length}


  console.info("SHOULDER_NUMERIC_RESEARCH_PASS",JSON.stringify({pairs,rows,fields,observableCases,observableReads,results}))
 }catch(e){console.error("SHOULDER_NUMERIC_RESEARCH_FAIL",e.message,e.stack)}Qt.quit()}
}