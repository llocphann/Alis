const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const base='/tmp/alis-abyss-resume-0620';
function load(path){const c=vm.createContext({});vm.runInContext(fs.readFileSync(path,'utf8').replace(/^\.pragma library\s*/,''),c);return c;}
const before=load(base+'/wave-before-travel.js'),after=load('/home/llocphann/Alis/modules/abyss/looks/AbyssWave.js');
const frames=2400,samples=256;
function work(api,travel=false){const s=api.create(samples,1920,1200,api.parameters({preset:'deep'})),hash=crypto.createHash('sha256');
 for(let i=0;i<frames;i++){
  if(i%48===0)api.impulse(s,['top','right','bottom','left'][Math.floor(i/48)%4],400+(i%5)*70,300,.8,1);
  if(travel && i%48===0)api.travel(s,['top','right','bottom','left'][Math.floor(i/48)%4],400+(i%5)*70,300,.8,1);
  api.advance(s,1/120);hash.update(Buffer.from(new Float64Array(s.displacement).buffer));
 }
 return {hash:hash.digest('hex'),steps:s.steps,packets:s.traveling?.length ?? 0};
}
const a=work(before),b=work(after);assert.equal(a.hash,b.hash);assert.equal(a.steps,b.steps);
const runs=[];for(let pair=0;pair<6;pair++)for(const name of pair%2 ? ['after','before'] : ['before','after']){
 const api=name==='before' ? before : after,start=process.hrtime.bigint(),cpu=process.cpuUsage();const result=work(api);assert.equal(result.hash,a.hash);
 runs.push({pair,name,wallMs:Number(process.hrtime.bigint()-start)/1e6,cpuMs:(process.cpuUsage(cpu).user+process.cpuUsage(cpu).system)/1000});
}
const start=process.hrtime.bigint(),cpu=process.cpuUsage(),storm=work(after,true);const withTravel={...storm,wallMs:Number(process.hrtime.bigint()-start)/1e6,cpuMs:(process.cpuUsage(cpu).user+process.cpuUsage(cpu).system)/1000};
const mean=name=>runs.filter(r=>r.name===name).reduce((v,r)=>v+r.cpuMs,0)/6;
const report={frames,samples,output:[1920,1200],beforeSha:'ed04f8500f9124cabea14a6134058f7349b3e91a',after:'working tree',equalOrdinaryDisplacementHash:a.hash,steps:a.steps,runs,beforeMeanCpuMs:mean('before'),afterMeanCpuMs:mean('after'),withTravel};
fs.writeFileSync(base+'/wave-profile.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
