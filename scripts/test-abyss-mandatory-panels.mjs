import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const P=vm.createContext({Math,JSON,Number,Array,Set,Object});vm.runInContext(fs.readFileSync(new URL('../modules/common/PanelFamilyPolicy.js',import.meta.url),'utf8'),P);
let checks=0;function check(v,label){checks++;assert.ok(v,label)}
for(const family of ['abyss','ii','waffle','unknown'])for(const initial of [[],['extra-package'],['abyssDock'],['abyssPerimeter','extra-package']]){
 const snapshot=JSON.stringify(initial),result=P.reconcileMandatory(family,initial);
 check(JSON.stringify(initial)===snapshot,'reconciliation preserves caller data');
 check(initial.every(id=>result.includes(id)),'existing and optional package IDs preserved');
 check(family==='waffle'?JSON.stringify(result)===snapshot:result.includes('abyssPerimeter'),'required host only on Abyss');
 check(JSON.stringify(P.reconcileMandatory(family,result))===JSON.stringify(result),'required reconciliation idempotent');
}
for(const optional of P.abyssPanels.filter(id=>id!=='abyssPerimeter')){
 const result=P.ensure('abyss',P.abyssPanels,['extra-package'],P.abyssPanels,['abyss','waffle']);
 check(result.enabled.includes('abyssPerimeter')&&!result.enabled.includes(optional),'seen optional OFF survives required host repair');
 check(result.enabled.includes('extra-package'),'package IDs survive family reconciliation');
}
check(P.mandatoryPanels('abyss').length===1&&P.mandatoryPanels('waffle').length===0,'explicit minimal structural set');
console.log('ABYSS_MANDATORY_PANELS_PASS',checks);
