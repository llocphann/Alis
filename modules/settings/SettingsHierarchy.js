// Presentation only: saved page indices, ordering and visibility remain owned
// by SettingsArrangement. Every applicable destination has exactly one parent.
var definitions = [
 {key:"abyss",name:"Abyss",icon:"water",pages:["abyss","abyss-waves","abyss-modules","abyss-popups","companion","dock","sidebars","dashboard","overview"]},
 {key:"appearance",name:"Appearance",icon:"palette",pages:["themes","wallpaper","effects","advanced"]},
 {key:"desktop",name:"Desktop",icon:"desktop_windows",pages:["bar","panels","widgets","modules","shell-layout","waffle-style"]},
 {key:"general",name:"General",icon:"settings",pages:["system","monitors","compositor","autostart","shortcuts","about"]},
 {key:"apps",name:"Apps & data",icon:"apps",pages:["ai","integrations","services"]},
 {key:"tools",name:"Tools",icon:"build",pages:["tools"]}
];
function parentKey(page) {
 if (!page || page.key === "quick") return "";
 return (definitions.find(group=>group.pages.indexOf(page.key)>=0) || definitions[3]).key;
}
function flat(pages,order) {
 const seen=new Set(),result=[];
 for(const index of order) {
  if(!pages[index] || seen.has(index))continue;
  seen.add(index);result.push(Object.assign({},pages[index],{realIndex:index}));
 }
 return result;
}
function entries(pages,order,groupKey,currentPage,editMode) {
 const all=flat(pages,order);
 if(editMode)return all;
 if(groupKey) return [{name:"Settings",icon:"arrow_back",back:true,realIndex:currentPage}].concat(all.filter(page=>parentKey(page)===groupKey));
 const seen=new Set(),result=[];
 for(const page of all) {
  const key=parentKey(page);
  if(!key){result.push(page);continue;}
  if(seen.has(key))continue;
  seen.add(key);
  const group=definitions.find(value=>value.key===key);
  result.push({name:group.name,icon:group.icon,groupKey:key,realIndex:page.realIndex});
 }
 return result;
}
function selected(entry,pages,currentPage) {
 return !entry.back && (entry.groupKey ? parentKey(pages[currentPage])===entry.groupKey : entry.realIndex===currentPage);
}
