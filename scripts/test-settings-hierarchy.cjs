const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const h={};vm.createContext(h);vm.runInContext(fs.readFileSync('modules/settings/SettingsHierarchy.js','utf8'),h);
const keys=['quick','system','abyss','wallpaper','themes','panels','tools','services','advanced','shortcuts','modules','waffle-style','compositor','about','widgets','monitors','dashboard','autostart','dock','sidebars','ai','effects','abyss-waves','abyss-popups','abyss-modules','companion','integrations','default-apps'];
const pages=keys.map((key,i)=>({key,name:key,component:'page'+i}));
for(const keysOrder of [keys,keys.slice().reverse(),keys.filter(key=>key!=='widgets')]) {
 const order=keysOrder.map(key=>keys.indexOf(key)),before=JSON.stringify(order);
 const top=h.entries(pages,order,'',0,false),visited=[];
 assert(top.length<=7,'root remains compact');
 for(const entry of top) {
  if(!entry.groupKey){visited.push(entry.realIndex);continue}
  const children=h.entries(pages,order,entry.groupKey,0,false);
  assert(children[0].back && !h.selected(children[0],pages,0));
  const expected=order.filter(index=>h.parentKey(pages[index])===entry.groupKey);
  assert.deepEqual(Array.from(children.slice(1),c=>c.realIndex),expected,'child order preserves custom relative order');
  for(const child of children.slice(1)) {
   assert(h.selected(entry,pages,child.realIndex),'search/deep link selects the parent');
   assert(h.selected(child,pages,child.realIndex),'page keeps its numeric identity');visited.push(child.realIndex);
  }
 }
 assert.deepEqual(visited.sort((a,b)=>a-b),order.slice().sort((a,b)=>a-b),'each visible destination appears once');
 assert.equal(new Set(visited).size,visited.length);
 assert.deepEqual(Array.from(h.entries(pages,order,'apps',0,true),e=>e.realIndex),order,'edit mode retains the complete saved arrangement');
 assert.equal(JSON.stringify(order),before,'drill-down does not mutate saved navigation');
}
assert.equal(h.parentKey({key:'future-page'}),'general','future pages remain reachable');
console.log('SETTINGS_HIERARCHY_PASS complete-once custom-order hidden-page parent-selection stable-index edit-mode');
