// DASH-F01: stable custom-tab identities and inactivity policy.
// Pure functions: the callers persist only validated, JSON-safe definitions.
var builtIns = ["dashboard", "music", "weeklyPlanner"];
var reservedNames = ["dashboard", "music", "weekly planner"];
function tabs(raw) {
    if (!Array.isArray(raw)) return [];
    var seenIds = {}, seenNames = {}, result = [];
    for (var item of raw) {
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
function available(raw, musicEnabled) {
    return (musicEnabled ? builtIns : ["dashboard", "weeklyPlanner"])
        .concat(tabs(raw).map(function(tab) { return tab.id; }));
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
