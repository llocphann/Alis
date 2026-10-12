import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const L=vm.createContext({Math,JSON,Number,Array,Set});
vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssLayout.js',import.meta.url),'utf8'),L);
let checks=0;
function check(ok,message){checks++;assert.ok(ok,message)}
function same(a,b,message){checks++;assert.equal(JSON.stringify(a),JSON.stringify(b),message)}
for(const kind of L.catalog)for(const edge of ['top','right','bottom','left'])for(const font of [.7,1,1.25,2])for(const size of [.6,1,1.8]){
 const p=L.normalize([{id:'one',kind,edge,position:.5,customSize:true,size}],edge),before=JSON.stringify(p);
 const records=L.geometry(p,1920,1080,{editing:true},font),r=records[0],horizontal=['top','bottom'].includes(edge);
 check(!r.capacityConflict,'single full design fits '+kind+edge);
 same(L.extent(kind,true),L.extent(kind,false),'orientation cannot substitute a compact extent');
 same(r.span,L.extent(kind,false)*font*size,'configured span preserved');
 same(horizontal?r.content.width:r.content.height,r.span,'physical axes swapped only');
 same(horizontal?r.content.height:r.content.width,32*font*size,'configured cross size preserved');
 same(JSON.stringify(p),before,'render never rewrites saved placements');
}
for(const edge of ['top','right','bottom','left']){
 const p=L.normalize(Array.from({length:24},(_,i)=>({id:'c'+i,kind:'clock',edge,position:i/23})),edge),before=JSON.stringify(p),opts={editing:true,edgeWidthAffectsModules:{[edge]:false}};
 const r=L.geometry(p,320,240,opts,1);
 check(r.length===24&&r.every(p=>p.capacityConflict&&p.span===104),'explicit all-member capacity rejection');
 check(L.localSurfaces(r,320,240,opts,1,48).length===0,'no rejected backing/input decoration');
 const notice=L.capacityNotices(r,320,240,1);check(notice.length===1,'exactly one repair action');
 const c=notice[0].content;check(c.x>=0&&c.y>=0&&c.x+c.width<=320&&c.y+c.height<=240,'bounded repair footprint');
 const remove=L.checkedBatch(p,p.slice(0,22).map(p=>p.id),'enabled',false,320,240,opts,1);
 check(!remove.rejected&&!L.conflicts(L.geometry(remove.placements,320,240,opts,1)).length,'explicit repair preserves two full modules');
 same(JSON.stringify(p),before,'invalid saved layout remains unchanged');
}
const p=L.normalize([{id:'a',kind:'clock',edge:'top',position:.3},...['b','c','d'].map((id,i)=>({id,kind:'clock',edge:'right',position:(i+1)/4}))],'top');
const denied=L.checkedMove(p,'a',790,100,800,330,{editing:true},1,false);
check(!!denied.rejected,'moving into overfull Edge is rejected');same(denied.placements,p,'rejected drag keeps every original placement');
const bad=L.normalize(Array.from({length:6},(_,i)=>({id:'c'+i,kind:'clock',edge:'left',position:i/5,locked:i===0,lockPosition:.1,lockScale:1})),'left');
check(!L.checkedBatch(bad,['c0'],'locked',false,320,240,{editing:true},1).rejected,'unlock remains available while repairing an overfull legacy layout');
check(!L.checkedBatch(bad,['c1'],'remove',true,320,240,{editing:true},1).rejected,'remove remains available before repair is fully complete');
console.log('ABYSS_FULL_SIZE_POLICY_PASS',checks);
