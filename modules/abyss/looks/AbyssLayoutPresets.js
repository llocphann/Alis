// Built-in sample presets and user preset helpers for Edit Abyss Layout.
// Captures and restores Modules, Screen Edge styling, Popups/IPC positions, and Companion anchor.

var EDGES = ["top", "right", "bottom", "left"];

function _toArray(value) {
    if (!value) return [];
    if (Array.isArray(value)) return value;
    if (typeof value === "object" && typeof value.length === "number" && value.length >= 0) {
        var arr = [];
        for (var i = 0; i < value.length; ++i) arr.push(value[i]);
        return arr;
    }
    return [];
}

function _clone(value) {
    try {
        return JSON.parse(JSON.stringify(value));
    } catch (_e) {
        return value;
    }
}

function _bounded(value, fallback, low, high) {
    var n = Number(value);
    return Number.isFinite(n) ? Math.max(low, Math.min(high, n)) : fallback;
}

function _edgeMap(source, fallback, coerce) {
    var out = {};
    for (var i = 0; i < EDGES.length; ++i) {
        var edge = EDGES[i];
        var raw = source && typeof source === "object" ? source[edge] : undefined;
        out[edge] = coerce ? coerce(raw, fallback) : (raw !== undefined ? raw : fallback);
    }
    return out;
}

function _normalizeEdgeSizes(map) {
    return _edgeMap(map, 1, function(v, fb) { return _bounded(v, fb, 0.6, 1.8); });
}

function _normalizeEdgeThicknesses(map) {
    return _edgeMap(map, -1, function(v, fb) {
        var n = Number(v);
        if (!Number.isFinite(n) || n < 0) return fb;
        return Math.max(0, Math.min(64, Math.round(n)));
    });
}

function _normalizeEdgeBools(map, fallback) {
    return _edgeMap(map, fallback, function(v, fb) {
        return typeof v === "boolean" ? v : fb;
    });
}

function _normalizeEdgeRadii(map) {
    return _edgeMap(map, -1, function(v, fb) {
        var n = Number(v);
        if (!Number.isFinite(n) || n < 0) return fb;
        return Math.max(0, Math.min(32, Math.round(n)));
    });
}

function _normalizeExpansion(map) {
    return _edgeMap(map, "edge", function(v) {
        return v === "local" ? "local" : "edge";
    });
}

function _normalizePositions(list) {
    var items = _toArray(list);
    if (!items.length) return [];
    var out = [];
    for (var i = 0; i < items.length; ++i) {
        var item = items[i];
        if (!item || typeof item !== "object" || Array.isArray(item)) continue;
        var kind = String(item.kind || "").trim();
        if (!kind) continue;
        var entry = { kind: kind, outputName: String(item.outputName || "") };
        if (EDGES.indexOf(item.edge) >= 0) entry.edge = item.edge;
        if (["source", "start", "center", "end", "custom"].indexOf(item.alignment) >= 0)
            entry.alignment = item.alignment;
        if (Number.isFinite(Number(item.position)))
            entry.position = _bounded(item.position, 0.5, 0, 1);
        if (item.joinCorner === true) entry.joinCorner = true;
        out.push(entry);
    }
    return out;
}

function _normalizeCompanion(raw) {
    var edge = raw && EDGES.indexOf(raw.edge) >= 0 ? raw.edge : "bottom";
    var along = _bounded(raw && raw.along, 0.72, 0.08, 0.92);
    return { edge: edge, along: Math.round(along * 1000) / 1000 };
}

function _defaultModulesSnapshot() {
    return {
        placements: [],
        gap: 8,
        size: 1,
        edgeSizes: { top: 1, right: 1, bottom: 1, left: 1 },
        edgeThicknesses: { top: -1, right: -1, bottom: -1, left: -1 },
        edgeWidthAffectsModules: { top: true, right: true, bottom: true, left: true },
        edgeJoinModules: { top: false, right: false, bottom: false, left: false },
        edgeModuleRadii: { top: -1, right: -1, bottom: -1, left: -1 },
        edgeRoundZeroCorners: { top: false, right: false, bottom: false, left: false },
        singleModuleExpansion: { top: "edge", right: "edge", bottom: "edge", left: "edge" }
    };
}

function builtInPresets() {
    return [];
}

function normalizePreset(raw, placementHelper) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    var id = String(raw.id || "").trim();
    var name = String(raw.name || "").trim();
    if (!id || !name) return null;
    var rawModules = raw.modules && typeof raw.modules === "object" ? raw.modules : {};
    var rawPlacements = _toArray(rawModules.placements);
    var placements = (placementHelper && typeof placementHelper.normalize === "function")
        ? placementHelper.normalize(rawPlacements, "top")
        : _clone(rawPlacements);
    return {
        id: id,
        name: name.slice(0, 48),
        description: String(raw.description || "").trim().slice(0, 120),
        icon: String(raw.icon || "bookmark"),
        builtIn: false,
        createdAt: String(raw.createdAt || ""),
        modules: {
            placements: placements,
            gap: _bounded(rawModules.gap, 8, 0, 32),
            size: _bounded(rawModules.size, 1, 0.6, 1.8),
            edgeSizes: _normalizeEdgeSizes(rawModules.edgeSizes),
            edgeThicknesses: _normalizeEdgeThicknesses(rawModules.edgeThicknesses),
            edgeWidthAffectsModules: _normalizeEdgeBools(rawModules.edgeWidthAffectsModules, true),
            edgeJoinModules: _normalizeEdgeBools(rawModules.edgeJoinModules, false),
            edgeModuleRadii: _normalizeEdgeRadii(rawModules.edgeModuleRadii),
            edgeRoundZeroCorners: _normalizeEdgeBools(rawModules.edgeRoundZeroCorners, false),
            singleModuleExpansion: _normalizeExpansion(rawModules.singleModuleExpansion)
        },
        positions: _normalizePositions(raw.positions),
        companion: _normalizeCompanion(raw.companion)
    };
}

function normalizeUserPresets(rawList, placementHelper) {
    var items = _toArray(rawList);
    if (!items.length) return [];
    var seen = {};
    var out = [];
    for (var i = 0; i < items.length; ++i) {
        var norm = normalizePreset(items[i], placementHelper);
        if (!norm || seen[norm.id]) continue;
        seen[norm.id] = true;
        out.push(norm);
    }
    return out.slice(0, 32);
}

function allPresets(rawUserList, placementHelper) {
    return normalizeUserPresets(rawUserList, placementHelper);
}

function nextDefaultName(rawUserList, prefix, placementHelper) {
    var users = normalizeUserPresets(rawUserList, placementHelper);
    var base = String(prefix || "Preset").trim() || "Preset";
    var taken = {};
    for (var i = 0; i < users.length; ++i)
        taken[users[i].name.toLowerCase()] = true;
    var n = 1;
    while (taken[(base + " " + n).toLowerCase()]) n++;
    return base + " " + n;
}

function capturePreset(name, draftState, placementHelper, existingId) {
    var cleanName = String(name || "").trim().slice(0, 48);
    if (!cleanName) cleanName = "Custom Layout";
    var id = existingId
        ? String(existingId)
        : ("user-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6));
    var state = draftState || {};
    return normalizePreset({
        id: id,
        name: cleanName,
        description: "Saved layout preset",
        icon: "bookmark",
        builtIn: false,
        createdAt: new Date().toISOString(),
        modules: {
            placements: _clone(_toArray(state.draft)),
            gap: state.gap,
            size: state.moduleScale,
            edgeSizes: state.edgeSizes,
            edgeThicknesses: state.edgeThicknesses,
            edgeWidthAffectsModules: state.edgeWidthAffectsModules,
            edgeJoinModules: state.edgeJoinModules,
            edgeModuleRadii: state.edgeModuleRadii,
            edgeRoundZeroCorners: state.edgeRoundZeroCorners,
            singleModuleExpansion: state.singleModuleExpansion
        },
        positions: _clone(_toArray(state.draftPositions)),
        companion: {
            edge: state.companionDraftEdge,
            along: state.companionDraftAlong
        }
    }, placementHelper);
}

function upsertUserPreset(rawUserList, preset, placementHelper) {
    var users = normalizeUserPresets(rawUserList, placementHelper);
    var norm = normalizePreset(preset, placementHelper);
    if (!norm) return users;
    var lower = norm.name.toLowerCase();
    var idx = users.findIndex(function(p) {
        return p.id === norm.id || p.name.toLowerCase() === lower;
    });
    if (idx >= 0) {
        norm.id = users[idx].id;
        users[idx] = norm;
    } else {
        users.push(norm);
    }
    return users.slice(-32);
}

function removeUserPreset(rawUserList, id, placementHelper) {
    var targetId = String(id || "");
    if (!targetId)
        return normalizeUserPresets(rawUserList, placementHelper);
    return normalizeUserPresets(rawUserList, placementHelper).filter(function(p) {
        return p.id !== targetId;
    });
}
