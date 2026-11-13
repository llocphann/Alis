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
    "abyssSessionScreen", "iiCheatsheet", "iiOnScreenKeyboard",
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
    if (index === 26 || index === 32) return {pageIndex:2,section:value || "surface"};
    if (index === 37 && value.toLowerCase().trim() === "ai") return {pageIndex:24,section:"ai"};
    var tabs={waves:2,spectrum:2,interaction:2,performance:2,modules:34,bar:34,dock:22,sidebars:23,popups:33};
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
    "iiOnScreenKeyboard","iiRegionSelector","iiTilingOverlay",
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

// Strip retired toggle identifiers ("musicRecognition") from persisted user
// quick-toggle layouts while preserving every other toggle's order and size.
function migrateRetiredToggles(options) {
    options = options || {};
    var result = {};
    var androidToggles = options?.sidebar?.quickToggles?.android?.toggles;
    if (Array.isArray(androidToggles) && androidToggles.some(function(item) { return item && item.type === "musicRecognition"; })) {
        result["sidebar.quickToggles.android.toggles"] = androidToggles.filter(function(item) {
            return !item || item.type !== "musicRecognition";
        });
    }
    var waffleToggles = options?.waffles?.actionCenter?.toggles;
    if (Array.isArray(waffleToggles) && waffleToggles.indexOf("musicRecognition") >= 0) {
        result["waffles.actionCenter.toggles"] = waffleToggles.filter(function(id) {
            return id !== "musicRecognition";
        });
    }
    return result;
}

// Preserve legacy apps.fileExplorer values by backfilling apps.fileManager once
// when a pre-SET-F01 config had fileExplorer without fileManager.
function migrateDefaultApps(options) {
    options = options || {};
    var apps = options.apps;
    if (!apps || typeof apps !== "object") return {};
    var result = {};
    if (!Object.prototype.hasOwnProperty.call(apps, "fileManager")
            && typeof apps.fileExplorer === "string"
            && apps.fileExplorer.trim().length > 0) {
        result["apps.fileManager"] = apps.fileExplorer.trim();
    }
    return result;
}

function migrateNexusConfig(options) {
    var out = {};
    if (!options || typeof options !== "object")
        return out;
    var legacyKey = "ob" + "sidian";
    var legacyEnabledKey = legacyKey + "Enabled";

    if (options.abyss && typeof options.abyss === "object"
            && options.abyss.companionMind && typeof options.abyss.companionMind === "object"
            && Object.prototype.hasOwnProperty.call(options.abyss.companionMind, legacyEnabledKey)) {
        var curMindVal = options.abyss.companionMind.nexusEnabled;
        out["abyss.companionMind.nexusEnabled"] = (curMindVal !== undefined)
            ? (curMindVal === true)
            : (options.abyss.companionMind[legacyEnabledKey] === true);
        delete options.abyss.companionMind[legacyEnabledKey];
    }

    if (options.integrations && typeof options.integrations === "object") {
        if (options.integrations.alisIntergration && typeof options.integrations.alisIntergration === "object"
                && Object.prototype.hasOwnProperty.call(options.integrations.alisIntergration, legacyKey)) {
            var curPluginVal = options.integrations.alisIntergration.nexus;
            out["integrations.alisIntergration.nexus"] = (curPluginVal !== undefined)
                ? (curPluginVal === true)
                : (options.integrations.alisIntergration[legacyKey] === true);
            delete options.integrations.alisIntergration[legacyKey];
        }
        if (Object.prototype.hasOwnProperty.call(options.integrations, legacyKey)) {
            var legacyInt = options.integrations[legacyKey];
            var curInt = (options.integrations.nexus && typeof options.integrations.nexus === "object")
                ? options.integrations.nexus : {};
            if (legacyInt && typeof legacyInt === "object") {
                var intKeys = ["autoTheme", "configPath", "applicationConfigPath", "applicationPath"];
                for (var i = 0; i < intKeys.length; ++i) {
                    var k = intKeys[i];
                    var curVal = curInt[k];
                    if (legacyInt[k] !== undefined && (curVal === undefined || curVal === "" || (k === "configPath" && curVal === "." + legacyKey) || (k === "applicationPath" && curVal === legacyKey))) {
                        var val = legacyInt[k];
                        if (k === "applicationPath" && val === legacyKey)
                            val = "nexus";
                        if (k === "configPath" && val === "." + legacyKey)
                            val = ".nexus";
                        out["integrations.nexus." + k] = val;
                    }
                }
            }
            if (out["integrations.nexus.autoTheme"] === undefined && curInt.autoTheme !== undefined)
                out["integrations.nexus.autoTheme"] = curInt.autoTheme === true;
            delete options.integrations[legacyKey];
        } else if (options.integrations.nexus && typeof options.integrations.nexus === "object") {
            if (options.integrations.nexus.configPath === "." + legacyKey)
                out["integrations.nexus.configPath"] = ".nexus";
            if (options.integrations.nexus.applicationPath === legacyKey)
                out["integrations.nexus.applicationPath"] = "nexus";
        }
    }

    if (options.todo && typeof options.todo === "object") {
        if (options.todo.backend === legacyKey)
            out["todo.backend"] = "nexus";
        if (Object.prototype.hasOwnProperty.call(options.todo, legacyKey)) {
            var legacyTodo = options.todo[legacyKey];
            var curTodo = (options.todo.nexus && typeof options.todo.nexus === "object")
                ? options.todo.nexus : {};
            if (legacyTodo && typeof legacyTodo === "object") {
                var todoKeys = ["vaultPath", "sourceMode", "notePath", "scope", "preferTasksPlugin", "allowBasicOfflineMutation"];
                for (var j = 0; j < todoKeys.length; ++j) {
                    var tk = todoKeys[j];
                    if (legacyTodo[tk] !== undefined && (curTodo[tk] === undefined || curTodo[tk] === ""))
                        out["todo.nexus." + tk] = legacyTodo[tk];
                }
                if (legacyTodo.dailyNote && typeof legacyTodo.dailyNote === "object") {
                    var curDaily = (curTodo.dailyNote && typeof curTodo.dailyNote === "object")
                        ? curTodo.dailyNote : {};
                    var dailyKeys = ["folder", "format", "plannerHeading", "plannerHeadingLevel", "defaultDurationMinutes"];
                    for (var d = 0; d < dailyKeys.length; ++d) {
                        var dk = dailyKeys[d];
                        if (legacyTodo.dailyNote[dk] !== undefined && (curDaily[dk] === undefined || curDaily[dk] === ""))
                            out["todo.nexus.dailyNote." + dk] = legacyTodo.dailyNote[dk];
                    }
                }
            }
            if (out["todo.nexus.vaultPath"] === undefined && curTodo.vaultPath !== undefined)
                out["todo.nexus.vaultPath"] = curTodo.vaultPath;
            delete options.todo[legacyKey];
        }
    }

    return out;
}
