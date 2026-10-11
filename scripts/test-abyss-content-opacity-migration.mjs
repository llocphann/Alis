import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const policy=vm.createContext({});
vm.runInContext(readFileSync(new URL('../modules/common/PanelFamilyPolicy.js',import.meta.url),'utf8'),policy);
let checks=0;
function check(content,expected){
    const input={panelFamily:'waffle',panelStyleVersion:1,enabledPanels:['wBar'],
        abyss:{surface:{opacity:.62},content},appearance:{screenEdge:{outputs:{private:{left:0,right:12}}}},
        optionalPackage:{unknown:['preserve',0,null]}};
    const before=JSON.stringify(input);
    const changes=JSON.parse(JSON.stringify(policy.migrateContentOpacity(input)));
    assert.deepEqual(changes,expected); checks++;
    assert.equal(JSON.stringify(input),before,'migration mutated its input'); checks++;
    const migrated=structuredClone(input);
    for(const [path,value] of Object.entries(changes)){
        const keys=path.split('.');let target=migrated;
        for(const key of keys.slice(0,-1))target=target[key]??=( {} );
        target[keys.at(-1)]=value;
    }
    assert.deepEqual(JSON.parse(JSON.stringify(policy.migrateContentOpacity(migrated))),{},'migration is not idempotent');checks++;
    const effective=migrated.abyss.content.opacity;
    if(Object.hasOwn(changes,'abyss.content.opacity'))assert.equal(effective,changes['abyss.content.opacity']);
    else assert.equal(effective,content.opacity,'explicit opacity was overwritten');checks++;
    if(!Object.hasOwn(content,'opacityVersion'))delete migrated.abyss.content.opacityVersion;
    if(!Object.hasOwn(content,'opacity'))delete migrated.abyss.content.opacity;
    assert.deepEqual(migrated,input,'unrelated/retired preferences changed');checks++;
}
for(const opacity of [-1,0,.25,.5,.75,1,null,'0.4']){
    for(const cardOpacity of [0,.4,.9,1])check({opacity,cardOpacity,blurRadius:17,unknown:{a:1}}, {'abyss.content.opacityVersion':1});
}
for(const [legacy,value] of [[-1,0],[0,0],[.25,.25],[.9,.9],[1,1],[2,1],[null,-1],['bad',-1]])
    check({cardOpacity:legacy,blurRadius:-1}, {'abyss.content.opacityVersion':1,'abyss.content.opacity':value});
check({blurRadius:0},{'abyss.content.opacityVersion':1,'abyss.content.opacity':-1});
for(const opacityVersion of [1,2,99])check({opacityVersion,opacity:.4,cardOpacity:.8,unknown:true},{});
assert.deepEqual(JSON.parse(JSON.stringify(policy.migrateContentOpacity({}))),{'abyss.content.opacityVersion':1,'abyss.content.opacity':-1});checks++;
console.log(`ABYSS_CONTENT_OPACITY_MIGRATION_PASS ${checks} checks; explicit zero/inheritance wins, legacy-only fallback, unknown/per-output/Waffle preservation, idempotency/future schemas`);
