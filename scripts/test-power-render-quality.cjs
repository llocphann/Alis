const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const policy={};vm.createContext(policy);
vm.runInContext(fs.readFileSync('modules/abyss/looks/PowerRenderQuality.js','utf8').replace(/^\.pragma library\s*/,''),policy);
for(const profile of ['power-saver','balanced','performance','unavailable']) {
 for(const manual of ['performance','balanced','quality','unknown']) {
  assert.equal(policy.abyss(manual,false,profile),['performance','balanced','quality'].includes(manual)?manual:'balanced');
  assert.equal(policy.abyss(manual,true,profile),profile==='power-saver'?'performance':profile==='performance'?'quality':'balanced');
  for(const shell of ['performance','balanced','quality']) {
   assert.equal(policy.aqua(manual,false,profile,shell),shell==='performance'||manual==='performance'?'performance':'quality');
   assert.equal(policy.aqua(manual,true,profile,shell),shell==='performance'||profile==='power-saver'?'performance':'quality');
  }
 }
}
// The explicit higher tier never bypasses shell Performance or increases
// the pre-existing automatic profile cost.
for(const profile of ['power-saver','balanced','performance','unavailable']) {
 for(const shell of ['performance','balanced','quality']) {
  assert.equal(policy.aqua('detailed',false,profile,shell),shell==='performance'?'performance':'detailed');
  assert.equal(policy.aqua('detailed',true,profile,shell),shell==='performance'||profile==='power-saver'?'performance':'quality');
 }
}
assert.equal(policy.aquaLabel('performance'),'Performance');
assert.equal(policy.aquaLabel('quality'),'Balanced');
assert.equal(policy.aquaLabel('detailed'),'Quality');
assert.equal(policy.aquaLabel('unknown'),'Balanced');
console.log('PASS: live-profile policy matrix and manual mode');
