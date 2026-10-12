// Pure policy shared by family routing, migration and behavioral tests.
function normalize(family) {
    return family === "waffle" ? "waffle" : "abyss";
}
function next(family) {
    var order = ["abyss", "waffle"];
    return order[(order.indexOf(normalize(family)) + 1) % order.length];
}
var abyssPanels = [
    "abyssPerimeter", "abyssBackground", "abyssBar", "abyssDock",
    "abyssSidebarLeft", "abyssSidebarRight", "abyssPopup",
    "abyssNotificationPopup", "abyssNotificationCenter", "abyssOnScreenDisplay",
    "abyssClipboard", "abyssOverview", "abyssLock", "abyssPolkit",
    "abyssSessionScreen", "iiCheatsheet", "iiOnScreenKeyboard", "iiOverlay",
    "iiControlPanel", "iiDashboard", "iiRegionSelector", "iiTilingOverlay", "iiWallpaperSelector",
    "iiWallpaperLauncher", "iiCoverflowSelector", "iiShellUpdate", "iiRecordingOsd"
];
function mandatoryPanels(family) { return normalize(family)==="abyss" ? ["abyssPerimeter"] : []; }
function reconcileMandatory(family,enabled) {
    var result=Array.from(enabled || []);
    mandatoryPanels(family).forEach(function(id) {if(result.indexOf(id)<0)result.push(id);});
    return result;
}
// Seen-but-disabled optional panels remain disabled on subsequent visits. A family's
// first explicit visit enables its own defaults, without reviving shared panels
// the user disabled in another family.
function ensure(family, base, enabled, known, visited) {
    family = normalize(family);
    var result = { enabled: enabled.slice(), known: known.slice(), visited: visited.slice() };
    var firstVisit = result.visited.indexOf(family) < 0;
    if (firstVisit) result.visited.push(family);
    for (var i = 0; i < base.length; ++i) {
        var id = base[i];
        var unseen = result.known.indexOf(id) < 0;
        var own = family === "abyss" ? id.indexOf("abyss") === 0
            : family === "waffle" ? id.indexOf("w") === 0 : id.indexOf("ii") === 0;
        if ((unseen || (firstVisit && own)) && result.enabled.indexOf(id) < 0)
            result.enabled.push(id);
        if (unseen) result.known.push(id);
    }
    result.enabled=reconcileMandatory(family,result.enabled);
    mandatoryPanels(family).forEach(function(id) {if(result.known.indexOf(id)<0)result.known.push(id);});
    return result;
}

// Historical style pages still accept IPC/search routes; their controls live once
// in the dedicated Abyss page. Common pages keep their stable numeric slots.
function settingsRoute(family, index, section) {
    var value = String(section || "");
    if (family !== "abyss") return {pageIndex:index,section:value};
    if (index === 26) return {pageIndex:2,section:"surface"};
    var tabs={waves:32,spectrum:32,interaction:32,modules:34,bar:34,dock:22,sidebars:23,popups:33};
    if (index === 2 && tabs[value.toLowerCase()])
        return {pageIndex:tabs[value.toLowerCase()],section:value};
    if (index === 10 && ["modules", "bar modules"].includes(value.toLowerCase().trim()))
        return {pageIndex:34,section:"modules"};
    if (index === 10 && value.toLowerCase() === "abyss")
        return {pageIndex:2,section:"surface"};
    return {pageIndex:index,section:value};
}

// Public Material -> Abyss cutover. Shared specialist panels and Waffle remain
// available, while old presentation IDs project onto their Abyss successors.
var materialPanelMap = {
    iiBar:"abyssBar",iiVerticalBar:"abyssBar",iiBackground:"abyssBackground",
    iiBackdrop:"abyssBackground",iiDock:"abyssDock",iiSidebarLeft:"abyssSidebarLeft",
    iiSidebarRight:"abyssSidebarRight",iiNotificationPopup:"abyssNotificationPopup",
    iiOnScreenDisplay:"abyssOnScreenDisplay",iiClipboard:"abyssClipboard",
    iiOverview:"abyssOverview",iiLock:"abyssLock",iiPolkit:"abyssPolkit",
    iiSessionScreen:"abyssSessionScreen",iiScreenCorners:"abyssNotificationCenter",
    iiMediaControls:"abyssPopup"
};
var materialSharedPanels = ["iiBootGreeting","iiCheatsheet","iiControlPanel",
    "iiOnScreenKeyboard","iiOverlay","iiRegionSelector","iiTilingOverlay",
    "iiWallpaperSelector","iiWallpaperLauncher","iiCoverflowSelector","iiShellUpdate",
    "iiRecordingOsd","iiDashboard","iiClipboard","iiOverview"];
function migrateMaterial(options) {
    options = options || {};
    var result = {};
    var family = normalize(options.panelFamily);
    if (family !== options.panelFamily) result.panelFamily = family;
    if (Number(options.panelStyleVersion || 0) >= 1) return result;
    result.panelStyleVersion = 1;
    if (!Array.isArray(options.enabledPanels)) return result;
    var enabled = options.enabledPanels.slice();
    var known = Array.from(options.knownPanels || []);
    var visited = Array.from(options.visitedPanelFamilies || []);
    var oldIds = Object.keys(materialPanelMap);
    var legacy = options.panelFamily === "ii" || options.panelFamily === undefined
        || oldIds.some(function(id) { return enabled.indexOf(id) >= 0 || known.indexOf(id) >= 0; });
    if (!legacy) return result;
    if (!known.length) known = oldIds.concat(materialSharedPanels);
    var successors = Array.from(new Set(Object.values(materialPanelMap)));
    successors.forEach(function(id) {
        // Previously visited Abyss preferences win over dormant Material IDs.
        if (known.indexOf(id) >= 0) return;
        var sources = oldIds.filter(function(old) { return materialPanelMap[old] === id; });
        if (sources.some(function(old) { return enabled.indexOf(old) >= 0; }) && enabled.indexOf(id) < 0)
            enabled.push(id);
        known.push(id);
    });
    if (known.indexOf("abyssPerimeter") < 0) {
        known.push("abyssPerimeter");enabled.push("abyssPerimeter");
    }
    // Keep old shared IDs because Waffle still consumes its supported modules.
    enabled = enabled.filter(function(id) { return !materialPanelMap[id] || materialSharedPanels.indexOf(id) >= 0; });
    visited = visited.map(function(id) { return normalize(id); });
    if (visited.indexOf("abyss") < 0) visited.push("abyss");
    result.enabledPanels = Array.from(new Set(enabled));
    result.knownPanels = Array.from(new Set(known));
    result.visitedPanelFamilies = Array.from(new Set(visited));
    return result;
}

// Read the raw saved object, not adapter defaults. Explicit Panel opacity
// (including 0 and inheritance) wins; a card-only legacy choice is adopted once.
// Keep retired/unknown keys so optional packages and newer schemas survive.
function migrateContentOpacity(options) {
    var content = options?.abyss?.content || {};
    if (Number(content.opacityVersion || 0) >= 1) return {};
    var result = {"abyss.content.opacityVersion":1};
    if (!Object.prototype.hasOwnProperty.call(content, "opacity")) {
        var legacy = content.cardOpacity;
        result["abyss.content.opacity"] = typeof legacy === "number" && Number.isFinite(legacy)
            ? Math.max(0, Math.min(1, legacy)) : -1;
    }
    return result;
}
