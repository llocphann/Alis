const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const h={};vm.createContext(h);vm.runInContext(fs.readFileSync('modules/settings/SettingsHierarchy.js','utf8'),h);
const keys=['quick','system','abyss','wallpaper','themes','panels','tools','services','advanced','shortcuts','modules','waffle-style','compositor','about','widgets','monitors','dashboard','autostart','dock','sidebars','ai','effects','abyss-waves','abyss-popups','abyss-modules','companion','integrations','default-apps'];
const pages=keys.map((key,i)=>({key,name:key,component:'page'+i}));
for(const keysOrder of [keys,keys.slice().reverse(),keys.filter(key=>key!=='widgets')]) {
 const order=keysOrder.map(key=>keys.indexOf(key)),before=JSON.stringify(order);
 const top=h.entries(pages,order,'',0,false),visited=[];
 assert.equal(top.length,order.length,'single-level sidebar exposes all ordered pages directly');
 assert.deepEqual(Array.from(top,e=>e.realIndex),order,'top-level order preserves custom relative order');
 for(const entry of top) {
  assert(!entry.groupKey && !entry.back,'single-level sidebar has no nested folder or back rows');
  assert(h.selected(entry,pages,entry.realIndex),'page keeps its numeric identity');
  assert(!h.selected(entry,pages,-1),'unmatched page is not selected');
  visited.push(entry.realIndex);
 }
 assert.deepEqual(visited.sort((a,b)=>a-b),order.slice().sort((a,b)=>a-b),'each visible destination appears once');
 assert.equal(new Set(visited).size,visited.length);
 assert.deepEqual(Array.from(h.entries(pages,order,'apps',0,true),e=>e.realIndex),order,'edit mode retains the complete saved arrangement');
 assert.equal(JSON.stringify(order),before,'navigation does not mutate saved arrangement');
}
assert.equal(h.parentKey({key:'future-page'}),'general','future pages remain reachable');
console.log('SETTINGS_HIERARCHY_PASS complete-once custom-order hidden-page parent-selection stable-index edit-mode');
