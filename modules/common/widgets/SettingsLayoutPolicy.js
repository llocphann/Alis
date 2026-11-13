.pragma library

var SCHEMA_VERSION = 2;

function slugify(text) {
    var s = String(text || "").trim().toLowerCase();
    s = s.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return s || "item";
}

var MODULE_ACRONYM_MAP = Object.freeze({
    "ai": "AI",
    "api": "API",
    "cpu": "CPU",
    "dns": "DNS",
    "fps": "FPS",
    "gpu": "GPU",
    "hdr": "HDR",
    "html": "HTML",
    "id": "ID",
    "ii": "II",
    "ipc": "IPC",
    "json": "JSON",
    "kdl": "KDL",
    "llm": "LLM",
    "ocr": "OCR",
    "osd": "OSD",
    "pdf": "PDF",
    "qml": "QML",
    "ram": "RAM",
    "rgb": "RGB",
    "sddm": "SDDM",
    "ssh": "SSH",
    "stt": "STT",
    "tlp": "TLP",
    "tts": "TTS",
    "ui": "UI",
    "url": "URL",
    "usb": "USB",
    "vpn": "VPN",
    "vrr": "VRR",
    "xdg": "XDG"
});

function humanizeModuleTitle(rawTitle, moduleId) {
    var raw = String(rawTitle || "").trim();
    var id = String(moduleId || "").trim();
    var prefixPattern = /^(?:p-?\d+|custom):/i;
    if (raw.length > 0 && raw !== id && !prefixPattern.test(raw))
        return raw;

    var source = raw.length > 0 ? raw : id;
    var stripped = source.replace(prefixPattern, "").trim();
    if (!stripped.length)
        return raw || id || "Module";

    var tokens = stripped.split(/[-_:\s]+/);
    var words = [];
    for (var i = 0; i < tokens.length; i++) {
        var tok = tokens[i];
        if (!tok)
            continue;
        var lower = tok.toLowerCase();
        if (MODULE_ACRONYM_MAP[lower]) {
            words.push(MODULE_ACRONYM_MAP[lower]);
        } else {
            words.push(lower.charAt(0).toUpperCase() + lower.slice(1));
        }
    }
    return words.length > 0 ? words.join(" ") : (raw || id || "Module");
}

function makeModuleId(originPageIndex, title, fallbackIndex) {
    var pagePart = (typeof originPageIndex === "number" && originPageIndex >= 0)
        ? ("p" + originPageIndex)
        : "custom";
    var slug = slugify(title);
    if (slug === "item" && typeof fallbackIndex === "number" && fallbackIndex >= 0)
        slug = "card-" + fallbackIndex;
    return pagePart + ":" + slug;
}

function makePageKey(pageIndex, customTabId) {
    if (customTabId && String(customTabId).trim().length > 0)
        return "tab:" + String(customTabId).trim();
    return "page:" + String(typeof pageIndex === "number" ? pageIndex : -1);
}

function emptyState() {
    return {
        version: SCHEMA_VERSION,
        modules: {},
        pageLayouts: {},
        customTabs: [],
        innerOrders: {},
        innerItems: {},
        sliders: {}
    };
}

function clamp(val, minVal, maxVal) {
    if (typeof val !== "number" || isNaN(val))
        return minVal;
    return Math.max(minVal, Math.min(maxVal, val));
}

function snapValue(val, gridSize, enabled) {
    if (!enabled || !gridSize || gridSize <= 1)
        return Math.round(val);
    return Math.round(val / gridSize) * gridSize;
}

function normalizeModuleEntry(raw, moduleId) {
    var m = (raw && typeof raw === "object") ? raw : {};
    var originPage = Number.isInteger(m.originPageIndex) ? m.originPageIndex : -1;
    if (originPage < 0 && typeof moduleId === "string" && moduleId.indexOf("p") === 0) {
        var colon = moduleId.indexOf(":");
        if (colon > 1) {
            var parsed = parseInt(moduleId.substring(1, colon), 10);
            if (!isNaN(parsed) && parsed >= 0)
                originPage = parsed;
        }
    }
    var targetPage = Number.isInteger(m.targetPageIndex) ? m.targetPageIndex : originPage;
    var targetCustomTabId = typeof m.targetCustomTabId === "string" ? m.targetCustomTabId.trim() : "";
    if (targetCustomTabId.length > 0)
        targetPage = -1;

    var col = typeof m.column === "string" ? m.column : "auto";
    if (["auto", "full", "top", "left", "right"].indexOf(col) < 0)
        col = "auto";

    var fitMode = typeof m.contentFitMode === "string" ? m.contentFitMode : "scale";
    if (["scroll", "scale"].indexOf(fitMode) < 0)
        fitMode = "scale";

    var widthRatio = typeof m.widthRatio === "number" && !isNaN(m.widthRatio) && m.widthRatio > 0
        ? clamp(m.widthRatio, 0.25, 1.0)
        : 0;
    var customHeight = typeof m.customHeight === "number" && !isNaN(m.customHeight) && m.customHeight > 0
        ? Math.round(clamp(m.customHeight, 88, 2000))
        : 0;
    var innerColumns = Number.isInteger(m.innerColumns) ? clamp(m.innerColumns, 0, 3) : 0;

    return {
        originPageIndex: originPage,
        originSubTab: typeof m.originSubTab === "string" ? m.originSubTab : "",
        targetPageIndex: targetPage,
        targetCustomTabId: targetCustomTabId,
        targetSubTab: typeof m.targetSubTab === "string" ? m.targetSubTab : "",
        column: col,
        order: typeof m.order === "number" && !isNaN(m.order) ? m.order : 0,
        widthRatio: widthRatio,
        customHeight: customHeight,
        innerColumns: innerColumns,
        contentFitMode: fitMode,
        visible: m.visible !== false,
        expanded: typeof m.expanded === "boolean" ? m.expanded : null,
        canvasX: typeof m.canvasX === "number" && !isNaN(m.canvasX) && m.canvasX >= 0 ? Math.round(m.canvasX) : -1,
        canvasY: typeof m.canvasY === "number" && !isNaN(m.canvasY) && m.canvasY >= 0 ? Math.round(m.canvasY) : -1,
        canvasW: typeof m.canvasW === "number" && !isNaN(m.canvasW) && m.canvasW > 0 ? Math.round(clamp(m.canvasW, 180, 1800)) : 0,
        canvasH: typeof m.canvasH === "number" && !isNaN(m.canvasH) && m.canvasH > 0 ? Math.round(clamp(m.canvasH, 88, 2000)) : 0,
        title: typeof m.title === "string" ? m.title : "",
        icon: typeof m.icon === "string" ? m.icon : ""
    };
}

function normalizePageLayoutEntry(raw) {
    var p = (raw && typeof raw === "object") ? raw : {};
    var layoutMode = p.layoutMode === "canvas" ? "canvas" : "bento";
    var leftColumnRatio = typeof p.leftColumnRatio === "number" && !isNaN(p.leftColumnRatio)
        ? clamp(p.leftColumnRatio, 0.22, 0.78)
        : 0.5;
    var subTabs = [];
    if (Array.isArray(p.subTabs)) {
        for (var i = 0; i < p.subTabs.length; i++) {
            var st = p.subTabs[i];
            if (!st || typeof st !== "object")
                continue;
            var key = String(st.key || "").trim();
            var label = String(st.label || "").trim();
            if (!key || !label)
                continue;
            subTabs.push({
                key: key,
                label: label,
                icon: String(st.icon || "tab").trim() || "tab",
                custom: key !== "overview" && (st.custom !== undefined ? Boolean(st.custom) : true)
            });
        }
    }
    var renamedSubTabs = {};
    if (p.renamedSubTabs && typeof p.renamedSubTabs === "object" && !Array.isArray(p.renamedSubTabs)) {
        var rKeys = Object.keys(p.renamedSubTabs);
        for (var j = 0; j < rKeys.length; j++) {
            var rk = rKeys[j];
            var rv = String(p.renamedSubTabs[rk] || "").trim();
            if (rk && rv)
                renamedSubTabs[rk] = rv;
        }
    }
    var deletedSubTabs = [];
    if (Array.isArray(p.deletedSubTabs)) {
        for (var k = 0; k < p.deletedSubTabs.length; k++) {
            var dk = String(p.deletedSubTabs[k] || "").trim();
            if (dk && deletedSubTabs.indexOf(dk) < 0)
                deletedSubTabs.push(dk);
        }
    }
    var subTabOrder = [];
    if (Array.isArray(p.subTabOrder)) {
        for (var m = 0; m < p.subTabOrder.length; m++) {
            var ok = String(p.subTabOrder[m] || "").trim();
            if (ok && subTabOrder.indexOf(ok) < 0)
                subTabOrder.push(ok);
        }
    }
    return {
        layoutMode: layoutMode,
        leftColumnRatio: leftColumnRatio,
        subTabs: subTabs,
        renamedSubTabs: renamedSubTabs,
        deletedSubTabs: deletedSubTabs,
        subTabOrder: subTabOrder
    };
}

function normalizeCustomTab(raw, idx) {
    if (!raw || typeof raw !== "object")
        return null;
    var id = String(raw.id || "").trim();
    var label = String(raw.label || "").trim();
    if (!id || !label)
        return null;
    return {
        id: id,
        label: label,
        icon: String(raw.icon || "dashboard_customize").trim() || "dashboard_customize",
        categoryIndex: Number.isInteger(raw.categoryIndex) && raw.categoryIndex >= 0 ? raw.categoryIndex : 0,
        order: typeof raw.order === "number" && !isNaN(raw.order) ? raw.order : idx
    };
}

function normalizeInnerItemEntry(raw) {
    var item = (raw && typeof raw === "object") ? raw : {};
    var span = Number.isInteger(item.columnSpan) ? clamp(item.columnSpan, 1, 3) : 1;
    var widthRatio = typeof item.widthRatio === "number" && !isNaN(item.widthRatio) && item.widthRatio > 0
        ? clamp(item.widthRatio, 0.25, 1.0)
        : 0;
    var alignment = typeof item.alignment === "string" ? item.alignment : "fill";
    if (["fill", "left", "center", "right"].indexOf(alignment) < 0)
        alignment = "fill";
    return {
        columnSpan: span,
        widthRatio: widthRatio,
        alignment: alignment,
        compact: Boolean(item.compact)
    };
}

function normalizeSliderEntry(raw) {
    var s = (raw && typeof raw === "object") ? raw : {};
    var orientation = s.orientation === "vertical" ? "vertical" : "horizontal";
    var length = typeof s.length === "number" && !isNaN(s.length) && s.length > 0
        ? Math.round(clamp(s.length, 56, 640))
        : 0;
    var thickness = typeof s.thickness === "number" && !isNaN(s.thickness) && s.thickness > 0
        ? Math.round(clamp(s.thickness, 4, 48))
        : 0;
    var config = typeof s.configuration === "string" ? s.configuration : "";
    if (["", "xs", "s", "m", "l", "xl"].indexOf(config) < 0)
        config = "";
    return {
        orientation: orientation,
        length: length,
        thickness: thickness,
        configuration: config
    };
}

function parseState(raw) {
    var base = emptyState();
    if (!raw)
        return base;
    var parsed = null;
    if (typeof raw === "string") {
        var trimmed = raw.trim();
        if (!trimmed)
            return base;
        try {
            parsed = JSON.parse(trimmed);
        } catch (e) {
            return base;
        }
    } else if (typeof raw === "object") {
        parsed = raw;
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        return base;

    var isLegacyV1 = (!parsed.version || parsed.version < 2);
    if (parsed.modules && typeof parsed.modules === "object" && !Array.isArray(parsed.modules)) {
        var mKeys = Object.keys(parsed.modules);
        for (var i = 0; i < mKeys.length; i++) {
            var mk = mKeys[i];
            if (!mk)
                continue;
            var rawMod = parsed.modules[mk];
            var normMod = normalizeModuleEntry(rawMod, mk);
            if (isLegacyV1 && normMod.contentFitMode === "scroll" && (!rawMod || !rawMod.contentFitModeExplicit))
                normMod.contentFitMode = "scale";
            if (normMod.canvasX === 0 && normMod.canvasY === 0 && normMod.canvasW === 0 && normMod.canvasH === 0) {
                normMod.canvasX = -1;
                normMod.canvasY = -1;
            }
            base.modules[mk] = normMod;
        }
    }

    if (parsed.pageLayouts && typeof parsed.pageLayouts === "object" && !Array.isArray(parsed.pageLayouts)) {
        var pKeys = Object.keys(parsed.pageLayouts);
        for (var j = 0; j < pKeys.length; j++) {
            var pk = pKeys[j];
            if (!pk)
                continue;
            base.pageLayouts[pk] = normalizePageLayoutEntry(parsed.pageLayouts[pk]);
        }
    }

    if (Array.isArray(parsed.customTabs)) {
        var seenTabs = {};
        for (var k = 0; k < parsed.customTabs.length; k++) {
            var ct = normalizeCustomTab(parsed.customTabs[k], k);
            if (ct && !seenTabs[ct.id]) {
                seenTabs[ct.id] = true;
                base.customTabs.push(ct);
            }
        }
    }

    if (parsed.innerOrders && typeof parsed.innerOrders === "object" && !Array.isArray(parsed.innerOrders)) {
        var ioKeys = Object.keys(parsed.innerOrders);
        for (var m = 0; m < ioKeys.length; m++) {
            var iok = ioKeys[m];
            var arr = parsed.innerOrders[iok];
            if (Array.isArray(arr)) {
                var cleanArr = [];
                for (var n = 0; n < arr.length; n++) {
                    var itemKey = String(arr[n] || "").trim();
                    if (itemKey && cleanArr.indexOf(itemKey) < 0)
                        cleanArr.push(itemKey);
                }
                if (cleanArr.length > 0)
                    base.innerOrders[iok] = cleanArr;
            }
        }
    }

    if (parsed.innerItems && typeof parsed.innerItems === "object" && !Array.isArray(parsed.innerItems)) {
        var iiKeys = Object.keys(parsed.innerItems);
        for (var p = 0; p < iiKeys.length; p++) {
            var iik = iiKeys[p];
            if (iik)
                base.innerItems[iik] = normalizeInnerItemEntry(parsed.innerItems[iik]);
        }
    }

    if (parsed.sliders && typeof parsed.sliders === "object" && !Array.isArray(parsed.sliders)) {
        var sKeys = Object.keys(parsed.sliders);
        for (var q = 0; q < sKeys.length; q++) {
            var sk = sKeys[q];
            if (sk)
                base.sliders[sk] = normalizeSliderEntry(parsed.sliders[sk]);
        }
    }

    return base;
}

function serializeState(state) {
    var normalized = parseState(state);
    var hasModules = Object.keys(normalized.modules).length > 0;
    var hasPageLayouts = Object.keys(normalized.pageLayouts).length > 0;
    var hasCustomTabs = normalized.customTabs.length > 0;
    var hasInnerOrders = Object.keys(normalized.innerOrders).length > 0;
    var hasInnerItems = Object.keys(normalized.innerItems).length > 0;
    var hasSliders = Object.keys(normalized.sliders).length > 0;
    if (!hasModules && !hasPageLayouts && !hasCustomTabs && !hasInnerOrders && !hasInnerItems && !hasSliders)
        return "";
    return JSON.stringify(normalized);
}

function cloneState(state) {
    return parseState(JSON.parse(JSON.stringify(state || emptyState())));
}

function getModuleConfig(state, moduleId) {
    var s = state && state.modules ? state : parseState(state);
    if (!moduleId || !s.modules[moduleId])
        return normalizeModuleEntry({}, moduleId);
    return normalizeModuleEntry(s.modules[moduleId], moduleId);
}

function updateModuleConfig(state, moduleId, patch) {
    var next = cloneState(state);
    if (!moduleId)
        return next;
    var existing = next.modules[moduleId] ? next.modules[moduleId] : normalizeModuleEntry({}, moduleId);
    var merged = {};
    var eKeys = Object.keys(existing);
    for (var i = 0; i < eKeys.length; i++)
        merged[eKeys[i]] = existing[eKeys[i]];
    if (patch && typeof patch === "object") {
        var pKeys = Object.keys(patch);
        for (var j = 0; j < pKeys.length; j++) {
            var k = pKeys[j];
            if (patch[k] !== undefined)
                merged[k] = patch[k];
        }
    }
    next.modules[moduleId] = normalizeModuleEntry(merged, moduleId);
    return next;
}

function resizeModule(state, moduleId, sizeSpec, snapEnabled, gridSize) {
    if (!moduleId || !sizeSpec)
        return cloneState(state);
    var current = getModuleConfig(state, moduleId);
    var patch = {};
    if (sizeSpec.widthRatio !== undefined) {
        if (sizeSpec.widthRatio <= 0) {
            patch.widthRatio = 0;
        } else {
            var r = clamp(sizeSpec.widthRatio, 0.25, 1.0);
            if (snapEnabled)
                r = Math.round(r * 20) / 20; // 5% steps when snapping
            patch.widthRatio = r;
        }
    }
    if (sizeSpec.customHeight !== undefined) {
        if (sizeSpec.customHeight <= 0) {
            patch.customHeight = 0;
        } else {
            var h = clamp(sizeSpec.customHeight, 88, 2000);
            patch.customHeight = snapValue(h, gridSize || 16, snapEnabled);
        }
    }
    if (sizeSpec.column !== undefined)
        patch.column = sizeSpec.column;
    if (sizeSpec.innerColumns !== undefined)
        patch.innerColumns = clamp(sizeSpec.innerColumns, 0, 3);
    if (sizeSpec.contentFitMode !== undefined)
        patch.contentFitMode = sizeSpec.contentFitMode;
    if (sizeSpec.canvasX !== undefined)
        patch.canvasX = sizeSpec.canvasX < 0 ? -1 : Math.max(0, snapValue(sizeSpec.canvasX, gridSize || 16, snapEnabled));
    if (sizeSpec.canvasY !== undefined)
        patch.canvasY = sizeSpec.canvasY < 0 ? -1 : Math.max(0, snapValue(sizeSpec.canvasY, gridSize || 16, snapEnabled));
    if (sizeSpec.canvasW !== undefined)
        patch.canvasW = sizeSpec.canvasW <= 0 ? 0 : clamp(snapValue(sizeSpec.canvasW, gridSize || 16, snapEnabled), 180, 1800);
    if (sizeSpec.canvasH !== undefined)
        patch.canvasH = sizeSpec.canvasH <= 0 ? 0 : clamp(snapValue(sizeSpec.canvasH, gridSize || 16, snapEnabled), 88, 2000);
    return updateModuleConfig(state, moduleId, patch);
}

function moveModuleToTarget(state, moduleId, originInfo, targetSpec) {
    if (!moduleId || !targetSpec)
        return cloneState(state);
    var current = getModuleConfig(state, moduleId);
    var originPageIndex = (originInfo && Number.isInteger(originInfo.originPageIndex))
        ? originInfo.originPageIndex
        : current.originPageIndex;
    var originSubTab = (originInfo && typeof originInfo.originSubTab === "string")
        ? originInfo.originSubTab
        : current.originSubTab;

    var targetCustomTabId = typeof targetSpec.targetCustomTabId === "string"
        ? targetSpec.targetCustomTabId.trim()
        : "";
    var targetPageIndex = targetCustomTabId.length > 0
        ? -1
        : (Number.isInteger(targetSpec.targetPageIndex) ? targetSpec.targetPageIndex : originPageIndex);
    var targetSubTab = typeof targetSpec.targetSubTab === "string"
        ? targetSpec.targetSubTab
        : "";

    var patch = {
        originPageIndex: originPageIndex,
        originSubTab: originSubTab,
        targetPageIndex: targetPageIndex,
        targetCustomTabId: targetCustomTabId,
        targetSubTab: targetSubTab,
        visible: true
    };
    if (originInfo && originInfo.title)
        patch.title = originInfo.title;
    if (originInfo && originInfo.icon)
        patch.icon = originInfo.icon;
    if (targetSpec.column !== undefined)
        patch.column = targetSpec.column;
    if (targetSpec.order !== undefined)
        patch.order = targetSpec.order;
    if (targetSpec.canvasX !== undefined)
        patch.canvasX = targetSpec.canvasX;
    if (targetSpec.canvasY !== undefined)
        patch.canvasY = targetSpec.canvasY;

    return updateModuleConfig(state, moduleId, patch);
}

function reorderModulesInBucket(state, orderedModuleIds, columnOverride) {
    var next = cloneState(state);
    if (!Array.isArray(orderedModuleIds))
        return next;
    for (var i = 0; i < orderedModuleIds.length; i++) {
        var id = orderedModuleIds[i];
        if (!id)
            continue;
        var existing = next.modules[id] ? next.modules[id] : normalizeModuleEntry({}, id);
        existing.order = (i + 1) * 10;
        if (columnOverride && ["auto", "full", "top", "left", "right"].indexOf(columnOverride) >= 0)
            existing.column = columnOverride;
        next.modules[id] = normalizeModuleEntry(existing, id);
    }
    return next;
}

function resetModule(state, moduleId) {
    var next = cloneState(state);
    if (!moduleId)
        return next;
    if (next.modules[moduleId])
        delete next.modules[moduleId];
    var prefix = moduleId + ":";
    var ioKeys = Object.keys(next.innerOrders || {});
    for (var i = 0; i < ioKeys.length; i++) {
        if (ioKeys[i].indexOf(prefix) === 0)
            delete next.innerOrders[ioKeys[i]];
    }
    var iiKeys = Object.keys(next.innerItems || {});
    for (var j = 0; j < iiKeys.length; j++) {
        if (iiKeys[j].indexOf(prefix) === 0)
            delete next.innerItems[iiKeys[j]];
    }
    var m = /^p(-?\d+):(.+)$/.exec(moduleId);
    var sliderPrefix = m ? ("p" + m[1] + ":slider:" + m[2]) : "";
    var sKeys = Object.keys(next.sliders || {});
    for (var k = 0; k < sKeys.length; k++) {
        if (sKeys[k].indexOf(prefix) === 0 || (sliderPrefix && sKeys[k].indexOf(sliderPrefix) === 0))
            delete next.sliders[sKeys[k]];
    }
    return next;
}

function isModuleMovedAway(state, moduleId, currentPageIndex, currentCustomTabId, currentSubTab, hasSubTabs) {
    var s = state && state.modules ? state : parseState(state);
    var entry = s.modules[moduleId];
    if (!entry)
        return false;
    if (entry.visible === false)
        return true;

    var curTabId = String(currentCustomTabId || "").trim();
    var entryTabId = String(entry.targetCustomTabId || "").trim();

    if (curTabId.length > 0 || entryTabId.length > 0) {
        if (curTabId !== entryTabId)
            return true;
    } else {
        if (entry.targetPageIndex >= 0 && currentPageIndex >= 0 && entry.targetPageIndex !== currentPageIndex)
            return true;
    }

    if (hasSubTabs && entry.targetSubTab && currentSubTab && entry.targetSubTab !== currentSubTab)
        return true;

    return false;
}

function isModuleHostedOnTarget(state, moduleId, targetPageIndex, targetCustomTabId, targetSubTab, hasSubTabs) {
    var s = state && state.modules ? state : parseState(state);
    var entry = s.modules[moduleId];
    if (!entry || entry.visible === false)
        return false;

    var curTabId = String(targetCustomTabId || "").trim();
    var entryTabId = String(entry.targetCustomTabId || "").trim();

    if (curTabId.length > 0) {
        if (entryTabId !== curTabId)
            return false;
    } else {
        if (entryTabId.length > 0)
            return false;
        if (entry.targetPageIndex !== targetPageIndex)
            return false;
    }

    if (hasSubTabs && targetSubTab) {
        if (entry.targetSubTab) {
            if (entry.targetSubTab !== targetSubTab)
                return false;
        } else if (String(targetSubTab).indexOf("subtab-") === 0) {
            return false;
        }
    }
    return true;
}

function getForeignModuleIdsForTarget(state, targetPageIndex, targetCustomTabId, targetSubTab, hasSubTabs) {
    var s = state && state.modules ? state : parseState(state);
    var mKeys = Object.keys(s.modules);
    var result = [];
    var curTabId = String(targetCustomTabId || "").trim();

    for (var i = 0; i < mKeys.length; i++) {
        var id = mKeys[i];
        var entry = s.modules[id];
        if (!entry || entry.visible === false)
            continue;
        if (!isModuleHostedOnTarget(s, id, targetPageIndex, targetCustomTabId, targetSubTab, hasSubTabs))
            continue;

        var isCrossPage = (curTabId.length > 0) || (entry.originPageIndex >= 0 && entry.originPageIndex !== targetPageIndex);
        var isCrossSubTab = (!isCrossPage && hasSubTabs && entry.targetSubTab && entry.originSubTab && entry.targetSubTab !== entry.originSubTab);
        if (isCrossPage || isCrossSubTab)
            result.push(id);
    }

    result.sort(function(a, b) {
        var oa = s.modules[a] ? s.modules[a].order : 0;
        var ob = s.modules[b] ? s.modules[b].order : 0;
        if (oa !== ob)
            return oa - ob;
        return a < b ? -1 : (a > b ? 1 : 0);
    });
    return result;
}

function getDonorPageIndexesForTarget(state, targetPageIndex, targetCustomTabId) {
    var s = state && state.modules ? state : parseState(state);
    var mKeys = Object.keys(s.modules);
    var donors = [];
    var curTabId = String(targetCustomTabId || "").trim();

    for (var i = 0; i < mKeys.length; i++) {
        var id = mKeys[i];
        var entry = s.modules[id];
        if (!entry || entry.visible === false)
            continue;
        var matchesTarget = false;
        if (curTabId.length > 0) {
            matchesTarget = (entry.targetCustomTabId === curTabId);
        } else {
            matchesTarget = (!entry.targetCustomTabId && entry.targetPageIndex === targetPageIndex);
        }
        if (!matchesTarget)
            continue;
        if (entry.originPageIndex >= 0 && (curTabId.length > 0 || entry.originPageIndex !== targetPageIndex)) {
            if (donors.indexOf(entry.originPageIndex) < 0)
                donors.push(entry.originPageIndex);
        }
    }
    return donors;
}

function getPageLayoutConfig(state, pageIndex, customTabId) {
    var s = state && state.pageLayouts ? state : parseState(state);
    var key = makePageKey(pageIndex, customTabId);
    return normalizePageLayoutEntry(s.pageLayouts[key]);
}

function updatePageLayoutConfig(state, pageIndex, customTabId, patch) {
    var next = cloneState(state);
    var key = makePageKey(pageIndex, customTabId);
    var existing = next.pageLayouts[key] ? next.pageLayouts[key] : normalizePageLayoutEntry({});
    var merged = {};
    var eKeys = Object.keys(existing);
    for (var i = 0; i < eKeys.length; i++)
        merged[eKeys[i]] = existing[eKeys[i]];
    if (patch && typeof patch === "object") {
        var pKeys = Object.keys(patch);
        for (var j = 0; j < pKeys.length; j++) {
            if (patch[pKeys[j]] !== undefined)
                merged[pKeys[j]] = patch[pKeys[j]];
        }
    }
    next.pageLayouts[key] = normalizePageLayoutEntry(merged);
    return next;
}

function createCustomTab(state, label, icon, categoryIndex) {
    var next = cloneState(state);
    var cleanLabel = String(label || "").trim();
    if (!cleanLabel)
        cleanLabel = "Custom Tab " + (next.customTabs.length + 1);
    var baseSlug = "custom-" + slugify(cleanLabel);
    var id = baseSlug;
    var suffix = 2;
    while (next.customTabs.some(function(t) { return t.id === id; })) {
        id = baseSlug + "-" + suffix;
        suffix++;
    }
    var newTab = normalizeCustomTab({
        id: id,
        label: cleanLabel,
        icon: icon || "dashboard_customize",
        categoryIndex: Number.isInteger(categoryIndex) && categoryIndex >= 0 ? categoryIndex : 0,
        order: next.customTabs.length
    }, next.customTabs.length);
    next.customTabs.push(newTab);
    return { state: next, tabId: id, tab: newTab };
}

function renameCustomTab(state, tabId, newLabel, newIcon) {
    var next = cloneState(state);
    var cleanId = String(tabId || "").trim();
    var cleanLabel = String(newLabel || "").trim();
    if (!cleanId || !cleanLabel)
        return next;
    for (var i = 0; i < next.customTabs.length; i++) {
        if (next.customTabs[i].id === cleanId) {
            next.customTabs[i].label = cleanLabel;
            if (newIcon && String(newIcon).trim())
                next.customTabs[i].icon = String(newIcon).trim();
            break;
        }
    }
    return next;
}

function deleteCustomTab(state, tabId) {
    var next = cloneState(state);
    var cleanId = String(tabId || "").trim();
    if (!cleanId)
        return next;
    next.customTabs = next.customTabs.filter(function(t) { return t.id !== cleanId; });
    var pageKey = makePageKey(-1, cleanId);
    if (next.pageLayouts[pageKey])
        delete next.pageLayouts[pageKey];

    // Return any modules hosted on this custom tab back to their origin page
    var mKeys = Object.keys(next.modules);
    for (var i = 0; i < mKeys.length; i++) {
        var mk = mKeys[i];
        var entry = next.modules[mk];
        if (entry && entry.targetCustomTabId === cleanId) {
            entry.targetCustomTabId = "";
            entry.targetPageIndex = entry.originPageIndex;
            entry.targetSubTab = entry.originSubTab || "";
            next.modules[mk] = normalizeModuleEntry(entry, mk);
        }
    }
    return next;
}

function moveCustomTab(state, tabId, direction, targetCategoryIndex) {
    var next = cloneState(state);
    var idx = -1;
    for (var i = 0; i < next.customTabs.length; i++) {
        if (next.customTabs[i].id === tabId) {
            idx = i;
            break;
        }
    }
    if (idx < 0)
        return next;
    if (Number.isInteger(targetCategoryIndex) && targetCategoryIndex >= 0)
        next.customTabs[idx].categoryIndex = targetCategoryIndex;
    if (typeof direction === "number" && direction !== 0) {
        var targetIdx = clamp(idx + direction, 0, next.customTabs.length - 1);
        if (targetIdx !== idx) {
            var moved = next.customTabs.splice(idx, 1)[0];
            next.customTabs.splice(targetIdx, 0, moved);
        }
    }
    for (var j = 0; j < next.customTabs.length; j++)
        next.customTabs[j].order = j;
    return next;
}

function getEffectiveSubTabs(state, pageIndex, customTabId, baseSubTabs) {
    var pl = getPageLayoutConfig(state, pageIndex, customTabId);
    var baseList = Array.isArray(baseSubTabs) ? baseSubTabs : [];
    var byKey = {};
    var combined = [];

    for (var i = 0; i < baseList.length; i++) {
        var b = baseList[i];
        if (!b || !b.key)
            continue;
        var k = String(b.key).trim();
        if (pl.deletedSubTabs.indexOf(k) >= 0)
            continue;
        var item = {
            key: k,
            label: pl.renamedSubTabs[k] || String(b.label || k),
            icon: String(b.icon || "tab"),
            custom: false
        };
        byKey[k] = item;
        combined.push(item);
    }

    for (var j = 0; j < pl.subTabs.length; j++) {
        var ct = pl.subTabs[j];
        if (!ct || !ct.key || pl.deletedSubTabs.indexOf(ct.key) >= 0)
            continue;
        if (byKey[ct.key]) {
            byKey[ct.key].label = pl.renamedSubTabs[ct.key] || ct.label;
            if (ct.icon)
                byKey[ct.key].icon = ct.icon;
        } else {
            var cItem = {
                key: ct.key,
                label: pl.renamedSubTabs[ct.key] || ct.label,
                icon: ct.icon || "tab",
                custom: ct.key !== "overview" && (ct.custom !== undefined ? Boolean(ct.custom) : true)
            };
            byKey[ct.key] = cItem;
            combined.push(cItem);
        }
    }

    if (pl.subTabOrder.length > 0 && combined.length > 1) {
        combined.sort(function(a, b) {
            var ia = pl.subTabOrder.indexOf(a.key);
            var ib = pl.subTabOrder.indexOf(b.key);
            if (ia < 0 && ib < 0)
                return 0;
            if (ia < 0)
                return 1;
            if (ib < 0)
                return -1;
            return ia - ib;
        });
    }

    // Never allow deleting every single built-in sub-tab if baseList was non-empty
    if (combined.length === 0 && baseList.length > 0) {
        var first = baseList[0];
        combined.push({
            key: String(first.key),
            label: pl.renamedSubTabs[first.key] || String(first.label || first.key),
            icon: String(first.icon || "tab"),
            custom: false
        });
    }

    return combined;
}

function createSubTab(state, pageIndex, customTabId, label, icon, baseSubTabs) {
    var next = cloneState(state);
    var pl = getPageLayoutConfig(next, pageIndex, customTabId);
    var existing = getEffectiveSubTabs(next, pageIndex, customTabId, baseSubTabs);
    var cleanLabel = String(label || "").trim() || ("Tab " + (existing.length + 1));

    var subTabs = pl.subTabs.slice();
    var subTabOrder = existing.map(function(t) { return t.key; });

    // If this page previously had 0 sub-tabs, create a default "overview" sub-tab first
    // so existing cards on the page have a home tab alongside the newly added sub-tab.
    if (existing.length === 0) {
        var mainTab = {
            key: "overview",
            label: "General",
            icon: "tune",
            custom: false
        };
        subTabs.push(mainTab);
        subTabOrder.push(mainTab.key);
    }

    var baseKey = "subtab-" + slugify(cleanLabel);
    var key = baseKey;
    var suffix = 2;
    while (subTabOrder.indexOf(key) >= 0 || pl.deletedSubTabs.indexOf(key) >= 0) {
        key = baseKey + "-" + suffix;
        suffix++;
    }

    var newSubTab = {
        key: key,
        label: cleanLabel,
        icon: String(icon || "tab").trim() || "tab",
        custom: true
    };
    subTabs.push(newSubTab);
    subTabOrder.push(key);

    next = updatePageLayoutConfig(next, pageIndex, customTabId, {
        subTabs: subTabs,
        subTabOrder: subTabOrder
    });
    return { state: next, subTabKey: key, subTab: newSubTab };
}

function renameSubTab(state, pageIndex, customTabId, subTabKey, newLabel) {
    var next = cloneState(state);
    var cleanKey = String(subTabKey || "").trim();
    var cleanLabel = String(newLabel || "").trim();
    if (!cleanKey || !cleanLabel)
        return next;
    var pl = getPageLayoutConfig(next, pageIndex, customTabId);
    var renamed = {};
    var rKeys = Object.keys(pl.renamedSubTabs);
    for (var i = 0; i < rKeys.length; i++)
        renamed[rKeys[i]] = pl.renamedSubTabs[rKeys[i]];
    renamed[cleanKey] = cleanLabel;

    var subTabs = pl.subTabs.map(function(st) {
        if (st.key === cleanKey)
            return { key: st.key, label: cleanLabel, icon: st.icon, custom: st.custom };
        return st;
    });

    return updatePageLayoutConfig(next, pageIndex, customTabId, {
        renamedSubTabs: renamed,
        subTabs: subTabs
    });
}

function deleteSubTab(state, pageIndex, customTabId, subTabKey, baseSubTabs) {
    var next = cloneState(state);
    var cleanKey = String(subTabKey || "").trim();
    if (!cleanKey)
        return next;
    var effective = getEffectiveSubTabs(next, pageIndex, customTabId, baseSubTabs);
    if (effective.length <= 1)
        return next; // Keep at least one sub-tab

    var pl = getPageLayoutConfig(next, pageIndex, customTabId);
    var subTabs = pl.subTabs.filter(function(st) { return st.key !== cleanKey; });
    var deletedSubTabs = pl.deletedSubTabs.slice();
    var isBase = Array.isArray(baseSubTabs) && baseSubTabs.some(function(b) { return b && b.key === cleanKey; });
    if (isBase && deletedSubTabs.indexOf(cleanKey) < 0)
        deletedSubTabs.push(cleanKey);
    var subTabOrder = pl.subTabOrder.filter(function(k) { return k !== cleanKey; });

    next = updatePageLayoutConfig(next, pageIndex, customTabId, {
        subTabs: subTabs,
        deletedSubTabs: deletedSubTabs,
        subTabOrder: subTabOrder
    });

    var remaining = getEffectiveSubTabs(next, pageIndex, customTabId, baseSubTabs);
    var fallbackSubTab = remaining.length > 0 ? remaining[0].key : "";
    var curTabId = String(customTabId || "").trim();

    var mKeys = Object.keys(next.modules);
    for (var i = 0; i < mKeys.length; i++) {
        var mk = mKeys[i];
        var entry = next.modules[mk];
        if (!entry)
            continue;
        var sameHost = curTabId.length > 0
            ? (entry.targetCustomTabId === curTabId)
            : (!entry.targetCustomTabId && entry.targetPageIndex === pageIndex);
        if (sameHost && entry.targetSubTab === cleanKey) {
            var nextSub = fallbackSubTab;
            if (!curTabId && entry.originPageIndex === pageIndex && entry.originSubTab && remaining.some(function(r) { return r.key === entry.originSubTab; })) {
                nextSub = entry.originSubTab;
            } else if (nextSub === "overview") {
                nextSub = "";
            }
            entry.targetSubTab = nextSub;
            next.modules[mk] = normalizeModuleEntry(entry, mk);
        }
    }
    return next;
}

function reorderSubTab(state, pageIndex, customTabId, subTabKey, direction, baseSubTabs) {
    var next = cloneState(state);
    var effective = getEffectiveSubTabs(next, pageIndex, customTabId, baseSubTabs);
    var order = effective.map(function(t) { return t.key; });
    var idx = order.indexOf(subTabKey);
    if (idx < 0)
        return next;
    var targetIdx = clamp(idx + direction, 0, order.length - 1);
    if (targetIdx === idx)
        return next;
    var moved = order.splice(idx, 1)[0];
    order.splice(targetIdx, 0, moved);
    return updatePageLayoutConfig(next, pageIndex, customTabId, {
        subTabOrder: order
    });
}

function getInnerOrder(state, containerId, defaultKeys) {
    var s = state && state.innerOrders ? state : parseState(state);
    var saved = s.innerOrders[containerId];
    var defaults = Array.isArray(defaultKeys) ? defaultKeys : [];
    if (!Array.isArray(saved) || saved.length === 0)
        return defaults.slice();
    var result = [];
    for (var i = 0; i < saved.length; i++) {
        if (defaults.length === 0 || defaults.indexOf(saved[i]) >= 0)
            result.push(saved[i]);
    }
    for (var j = 0; j < defaults.length; j++) {
        if (result.indexOf(defaults[j]) < 0)
            result.push(defaults[j]);
    }
    return result;
}

function moveInnerItem(state, containerId, itemKey, directionOrTargetKey, defaultKeys) {
    var next = cloneState(state);
    if (!containerId || !itemKey)
        return next;
    var currentOrder = getInnerOrder(next, containerId, defaultKeys);
    var fromIdx = currentOrder.indexOf(itemKey);
    if (fromIdx < 0)
        return next;
    var toIdx = -1;
    if (typeof directionOrTargetKey === "number") {
        toIdx = clamp(fromIdx + directionOrTargetKey, 0, currentOrder.length - 1);
    } else if (typeof directionOrTargetKey === "string") {
        toIdx = currentOrder.indexOf(directionOrTargetKey);
    }
    if (toIdx < 0 || toIdx === fromIdx)
        return next;
    var moved = currentOrder.splice(fromIdx, 1)[0];
    currentOrder.splice(toIdx, 0, moved);
    next.innerOrders[containerId] = currentOrder;
    return next;
}

var DEFAULT_INNER_ITEM_CONFIG = Object.freeze({
    columnSpan: 1,
    widthRatio: 0,
    alignment: "fill",
    compact: false
});

var DEFAULT_SLIDER_CONFIG = Object.freeze({
    orientation: "horizontal",
    length: 0,
    thickness: 0,
    configuration: ""
});

function hasInnerCustomizations(state, containerId) {
    if (!containerId)
        return false;
    var s = state && state.innerOrders ? state : parseState(state);
    var savedOrder = s.innerOrders && s.innerOrders[containerId];
    if (Array.isArray(savedOrder) && savedOrder.length > 0)
        return true;
    var items = s.innerItems;
    if (items && typeof items === "object") {
        var prefix = containerId + "::";
        var keys = Object.keys(items);
        for (var i = 0; i < keys.length; i++) {
            if (keys[i].indexOf(prefix) === 0)
                return true;
        }
    }
    return false;
}

function getInnerItemConfig(state, itemId) {
    var s = state && state.innerItems ? state : parseState(state);
    if (!itemId || !s.innerItems[itemId])
        return DEFAULT_INNER_ITEM_CONFIG;
    return normalizeInnerItemEntry(s.innerItems[itemId]);
}

function updateInnerItemConfig(state, itemId, patch) {
    var next = cloneState(state);
    if (!itemId)
        return next;
    var existing = next.innerItems[itemId] ? next.innerItems[itemId] : normalizeInnerItemEntry({});
    var merged = {};
    var eKeys = Object.keys(existing);
    for (var i = 0; i < eKeys.length; i++)
        merged[eKeys[i]] = existing[eKeys[i]];
    if (patch && typeof patch === "object") {
        var pKeys = Object.keys(patch);
        for (var j = 0; j < pKeys.length; j++) {
            if (patch[pKeys[j]] !== undefined)
                merged[pKeys[j]] = patch[pKeys[j]];
        }
    }
    next.innerItems[itemId] = normalizeInnerItemEntry(merged);
    return next;
}

function getSliderConfig(state, sliderId) {
    var s = state && state.sliders ? state : parseState(state);
    if (!sliderId || !s.sliders[sliderId])
        return DEFAULT_SLIDER_CONFIG;
    return normalizeSliderEntry(s.sliders[sliderId]);
}

function updateSliderConfig(state, sliderId, patch) {
    var next = cloneState(state);
    if (!sliderId)
        return next;
    var existing = next.sliders[sliderId] ? next.sliders[sliderId] : normalizeSliderEntry({});
    var merged = {};
    var eKeys = Object.keys(existing);
    for (var i = 0; i < eKeys.length; i++)
        merged[eKeys[i]] = existing[eKeys[i]];
    if (patch && typeof patch === "object") {
        var pKeys = Object.keys(patch);
        for (var j = 0; j < pKeys.length; j++) {
            if (patch[pKeys[j]] !== undefined)
                merged[pKeys[j]] = patch[pKeys[j]];
        }
    }
    next.sliders[sliderId] = normalizeSliderEntry(merged);
    return next;
}

function toggleSliderOrientation(state, sliderId) {
    var cur = getSliderConfig(state, sliderId);
    var nextOrientation = cur.orientation === "vertical" ? "horizontal" : "vertical";
    return updateSliderConfig(state, sliderId, {
        orientation: nextOrientation
    });
}

function resizeSlider(state, sliderId, length, thickness, configuration) {
    var patch = {};
    if (length !== undefined)
        patch.length = length <= 0 ? 0 : Math.round(clamp(length, 56, 640));
    if (thickness !== undefined)
        patch.thickness = thickness <= 0 ? 0 : Math.round(clamp(thickness, 4, 48));
    if (configuration !== undefined)
        patch.configuration = configuration;
    return updateSliderConfig(state, sliderId, patch);
}

function resetSlider(state, sliderId) {
    var next = cloneState(state);
    if (sliderId && next.sliders[sliderId])
        delete next.sliders[sliderId];
    return next;
}
