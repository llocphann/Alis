// One persisted arrangement; no renderer injects a second forced heading.
var SCHEMA_VERSION = 14;

function arrange(raw, defaults, pageCount, retired) {
    var saved = null;
    try { saved = typeof raw === "string" && raw ? JSON.parse(raw) : (raw && typeof raw === "object" ? raw : null); } catch (e) {}
    var hasSavedGroups = Array.isArray(saved) ? saved.length > 0 : (Array.isArray(saved?.groups) && saved.groups.length > 0);
    var savedVersion = Array.isArray(saved) ? 1 : Number(saved?.version || 0);
    var needsV14Migration = !saved || Array.isArray(saved) || savedVersion < SCHEMA_VERSION;

    var groups = Array.isArray(saved) ? saved : saved?.groups;
    if (!Array.isArray(groups) || !groups.length) groups = defaults;

    var baseRetired = Array.isArray(retired) ? retired.slice() : [];
    if (needsV14Migration) {
        [14, 15, 16].forEach(function(rIdx) {
            if (baseRetired.indexOf(rIdx) < 0) baseRetired.push(rIdx);
        });
    }

    var hidden = Array.from(new Set(Array.from(saved?.hidden || []).filter(
        i => Number.isInteger(i) && i >= 0 && i < pageCount && baseRetired.indexOf(i) < 0)));
    var seen = new Set(baseRetired.concat(hidden)), out = [];
    groups.forEach(function(group) {
        if (!group || typeof group.label !== "string") return;
        var label = group.label.trim();
        if (!label) return;
        var target = out.find(g => g.label.toLowerCase() === label.toLowerCase());
        if (!target) { target = { label: label, pages: [] }; out.push(target); }
        Array.from(group.pages || []).forEach(function(index) {
            if (!Number.isInteger(index) || index < 0 || index >= pageCount || seen.has(index)) return;
            target.pages.push(index); seen.add(index);
        });
    });
    for (var index = 0; index < pageCount; index++) {
        if (seen.has(index)) continue;
        var home = (defaults || []).find(g => Array.isArray(g.pages) && g.pages.indexOf(index) >= 0);
        var label = home?.label || "More", target = out.find(g => g.label.toLowerCase() === label.toLowerCase());
        if (!target) { target = { label: label, pages: [] }; out.push(target); }
        target.pages.push(index); seen.add(index);
    }

    if (needsV14Migration && hasSavedGroups) {
        var displayGroup = out.find(function(g) { return g.label.toLowerCase() === "display & windows"; });
        if (displayGroup) {
            if (displayGroup.pages.indexOf(33) >= 0) {
                displayGroup.pages = displayGroup.pages.filter(function(p) { return p !== 33; });
                if (hidden.indexOf(33) < 0 && baseRetired.indexOf(33) < 0) {
                    var abyssGroup = out.find(function(g) {
                        var low = g.label.toLowerCase();
                        return low === "abyss" || low === "abyss & bar" || low === "bar & shell";
                    }) || out.find(function(g) {
                        return g.pages.indexOf(2) >= 0 || g.pages.indexOf(37) >= 0;
                    });
                    if (!abyssGroup) {
                        var defAbyss = (defaults || []).find(function(g) { return Array.isArray(g.pages) && g.pages.indexOf(33) >= 0; });
                        abyssGroup = { label: defAbyss?.label || "Abyss & Bar", pages: [] };
                        out.unshift(abyssGroup);
                    }
                    if (abyssGroup.pages.indexOf(33) < 0) {
                        var idx34 = abyssGroup.pages.indexOf(34);
                        var idx37 = abyssGroup.pages.indexOf(37);
                        var idx2 = abyssGroup.pages.indexOf(2);
                        if (idx34 >= 0) abyssGroup.pages.splice(idx34 + 1, 0, 33);
                        else if (idx37 >= 0) abyssGroup.pages.splice(idx37, 0, 33);
                        else if (idx2 >= 0) abyssGroup.pages.splice(idx2 + 1, 0, 33);
                        else abyssGroup.pages.push(33);
                    }
                }
            }

            var moveToPanels = [10, 11].filter(function(p) { return displayGroup.pages.indexOf(p) >= 0; });
            if (moveToPanels.length > 0) {
                displayGroup.pages = displayGroup.pages.filter(function(p) { return p !== 10 && p !== 11; });
                var panelsGroup = out.find(function(g) {
                    return g.label.toLowerCase() === "panels & dock";
                }) || out.find(function(g) {
                    return g.pages.indexOf(22) >= 0 || g.pages.indexOf(23) >= 0;
                });
                if (!panelsGroup) {
                    var defPanels = (defaults || []).find(function(g) { return Array.isArray(g.pages) && g.pages.indexOf(10) >= 0; });
                    panelsGroup = { label: defPanels?.label || "Panels & Dock", pages: [] };
                    out.push(panelsGroup);
                }
                moveToPanels.forEach(function(p) {
                    if (hidden.indexOf(p) >= 0 || baseRetired.indexOf(p) >= 0 || panelsGroup.pages.indexOf(p) >= 0) return;
                    if (p === 10 && panelsGroup.pages.indexOf(11) >= 0) {
                        panelsGroup.pages.splice(panelsGroup.pages.indexOf(11), 0, 10);
                    } else {
                        panelsGroup.pages.push(p);
                    }
                });
            }
        }
    }

    var appsGroup = out.find(function(g) { return g.pages.indexOf(39) >= 0 && g.pages.indexOf(24) >= 0; });
    var compGroup = out.find(function(g) { return g.pages.indexOf(37) >= 0; });
    if (appsGroup && compGroup && appsGroup !== compGroup) {
        appsGroup.pages = appsGroup.pages.filter(function(p) { return p !== 24; });
        if (appsGroup.label === "Apps & AI") appsGroup.label = "Applications";
        if (compGroup.pages.indexOf(24) < 0) {
            var cIdx = compGroup.pages.indexOf(37);
            compGroup.pages.splice(cIdx + 1, 0, 24);
        }
    }
    var names = {};
    if (saved && saved.names && typeof saved.names === "object" && !Array.isArray(saved.names)) {
        Object.keys(saved.names).forEach(function(k) {
            var idx = Number(k), val = typeof saved.names[k] === "string" ? saved.names[k].trim() : "";
            if (Number.isInteger(idx) && idx >= 0 && idx < pageCount && val) names[String(idx)] = val;
        });
    }
    return { version: SCHEMA_VERSION, groups: out, hidden: hidden, names: names };
}
