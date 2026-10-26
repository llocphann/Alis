// One persisted arrangement; no renderer injects a second forced heading.
function arrange(raw, defaults, pageCount, retired) {
    var saved;
    try { saved=typeof raw === "string" && raw ? JSON.parse(raw) : null; } catch(e) {}
    var groups=Array.isArray(saved) ? saved : saved?.groups;
    if (!Array.isArray(groups) || !groups.length) groups=defaults;
    var hidden=Array.from(new Set(Array.from(saved?.hidden || []).filter(
        i=>Number.isInteger(i) && i>=0 && i<pageCount && retired.indexOf(i)<0)));
    var seen=new Set(retired.concat(hidden)),out=[];
    groups.forEach(function(group) {
        if (!group || typeof group.label !== "string") return;
        var label=group.label.trim();
        if (!label) return;
        var target=out.find(g=>g.label.toLowerCase() === label.toLowerCase());
        if (!target) { target={label:label,pages:[]};out.push(target); }
        Array.from(group.pages || []).forEach(function(index) {
            if (!Number.isInteger(index) || index<0 || index>=pageCount || seen.has(index)) return;
            target.pages.push(index);seen.add(index);
        });
    });
    for(var index=0;index<pageCount;index++) {
        if (seen.has(index)) continue;
        var home=defaults.find(g=>g.pages.indexOf(index)>=0);
        var label=home?.label || "More",target=out.find(g=>g.label.toLowerCase()===label.toLowerCase());
        if (!target) { target={label:label,pages:[]};out.push(target); }
        target.pages.push(index);seen.add(index);
    }
    var names={};
    if (saved && saved.names && typeof saved.names === "object" && !Array.isArray(saved.names)) {
        Object.keys(saved.names).forEach(function(k) {
            var idx=Number(k),val=typeof saved.names[k] === "string" ? saved.names[k].trim() : "";
            if (Number.isInteger(idx) && idx>=0 && idx<pageCount && val) names[String(idx)]=val;
        });
    }
    return {groups:out,hidden:hidden,names:names};
}
