// DASH-F01: stable custom-tab identities, customizable tab indicator icons, and inactivity policy.
// Pure functions: the callers persist only validated, JSON-safe definitions.
var builtIns = ["dashboard", "music", "weeklyPlanner"];
var reservedNames = ["dashboard", "music", "weekly planner", "spaced repetition"];
var defaultTabIcons = {
    dashboard: "dashboard",
    music: "library_music",
    weeklyPlanner: "calendar_month",
    spacedRepetition: "school",
    exercisesTracker: "fitness_center"
};
var presetTabIcons = [
    "dashboard", "space_dashboard", "home", "widgets", "apps", "grid_view",
    "library_music", "music_note", "headphones", "album",
    "calendar_month", "calendar_view_week", "event", "schedule",
    "school", "psychology", "auto_awesome", "analytics",
    "fitness_center", "monitor_heart",
    "tab", "folder", "terminal", "code", "hub", "layers",
    "checklist", "task_alt", "edit_note", "sticky_note_2",
    "bookmark", "star", "favorite", "bolt", "explore", "rocket_launch"
];
function defaultIconFor(id) {
    var key = String(id ?? "");
    return defaultTabIcons[key] || "tab";
}
function sanitizeIconName(raw) {
    var cleaned = String(raw ?? "").trim().toLowerCase()
        .replace(/[\s-]+/g, "_")
        .replace(/[^a-z0-9_]/g, "")
        .slice(0, 48);
    return cleaned;
}
function tabIcons(raw) {
    if (!raw || typeof raw === "string") return [];
    var byId = {}, order = [];
    if (typeof raw.length === "number") {
        var list = Array.from(raw);
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            var id = String(item?.id ?? "").trim().slice(0, 64);
            var icon = sanitizeIconName(item?.icon);
            if (!id || !icon) continue;
            if (!byId[id]) order.push(id);
            byId[id] = icon;
        }
    } else if (typeof raw === "object") {
        var keys = Object.keys(raw);
        for (var j = 0; j < keys.length; j++) {
            var k = String(keys[j] ?? "").trim().slice(0, 64);
            var v = sanitizeIconName(raw[k]);
            if (!k || !v) continue;
            if (!byId[k]) order.push(k);
            byId[k] = v;
        }
    }
    var result = [];
    for (var n = 0; n < order.length; n++) {
        var tabId = order[n];
        result.push({ id: tabId, icon: byId[tabId] });
    }
    return result;
}
function iconFor(rawTabIcons, pageId) {
    var key = String(pageId ?? "");
    var overrides = tabIcons(rawTabIcons);
    for (var i = 0; i < overrides.length; i++) {
        if (overrides[i].id === key)
            return overrides[i].icon;
    }
    return defaultIconFor(key);
}
function hasCustomIcon(rawTabIcons, pageId) {
    var key = String(pageId ?? "");
    if (!key) return false;
    var overrides = tabIcons(rawTabIcons);
    for (var i = 0; i < overrides.length; i++) {
        if (overrides[i].id === key)
            return overrides[i].icon !== defaultIconFor(key);
    }
    return false;
}
function setTabIcon(rawTabIcons, pageId, iconName) {
    var key = String(pageId ?? "").trim().slice(0, 64);
    var existing = tabIcons(rawTabIcons);
    if (!key) return existing;
    var nextIcon = sanitizeIconName(iconName);
    var defaultIcon = defaultIconFor(key);
    var filtered = existing.filter(function(item) { return item.id !== key; });
    if (!nextIcon || nextIcon === defaultIcon)
        return filtered;
    return filtered.concat([{ id: key, icon: nextIcon }]);
}
function removeTabIcon(rawTabIcons, pageId) {
    var key = String(pageId ?? "");
    return tabIcons(rawTabIcons).filter(function(item) { return item.id !== key; });
}
function tabs(raw) {
    // QML JsonAdapter list<var> may be exposed as an array-like object.
    if (!raw || typeof raw === "string" || typeof raw.length !== "number") return [];
    var source = Array.from(raw);
    var seenIds = {}, seenNames = {}, result = [];
    for (var item of source) {
        var id = String(item?.id ?? "");
        var name = String(item?.name ?? "").trim().slice(0, 40);
        var key = name.toLocaleLowerCase();
        if (!/^custom-[a-z0-9_-]{1,40}$/.test(id)
                || !name || reservedNames.indexOf(key) !== -1
                || seenIds[id] || seenNames[key]) continue;
        seenIds[id] = true; seenNames[key] = true;
        result.push({id:id, name:name});
        if (result.length >= 20) break;
    }
    return result;
}
function errorForName(raw, proposed, exceptId) {
    var name = String(proposed ?? "").trim();
    if (!name.length) return "Tab name cannot be empty";
    if (name.length > 40) return "Tab name must be 40 characters or fewer";
    var key = name.toLocaleLowerCase();
    if (reservedNames.indexOf(key) !== -1) return "This tab name is reserved";
    if (tabs(raw).some(function(item) {
        return item.id !== exceptId && item.name.toLocaleLowerCase() === key;
    })) return "A tab with this name already exists";
    return "";
}
function nextId(raw) {
    var used = tabs(raw).map(function(tab) { return tab.id; });
    for (var i = 1; i <= 999999; i++) {
        var id = "custom-" + i;
        if (used.indexOf(id) === -1) return id;
    }
    return "";
}
function available(raw, musicEnabled, spacedRepetitionEnabled) {
    var base = (musicEnabled ? builtIns : ["dashboard", "weeklyPlanner"])
        .concat(spacedRepetitionEnabled ? ["spacedRepetition"] : []);
    return base.concat(tabs(raw).map(function(tab) { return tab.id; }));
}
function selectAfterInactivity(now, hiddenAt, minutes, preferredId, ids, currentId) {
    var validIds = Array.from(ids || []);
    var fallback = validIds.indexOf("dashboard") !== -1 ? "dashboard" : (validIds[0] || "dashboard");
    var selected = validIds.indexOf(currentId) !== -1 ? currentId : fallback;
    var duration = Number(minutes), closed = Number(hiddenAt), time = Number(now);
    if (!Number.isFinite(duration) || duration <= 0
            || !Number.isFinite(time) || !Number.isFinite(closed)
            || closed <= 0 || time < closed
            || time - closed < duration * 60000)
        return selected;
    return validIds.indexOf(preferredId) !== -1 ? preferredId : fallback;
}
