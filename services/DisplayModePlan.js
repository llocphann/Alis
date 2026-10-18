// Pure display-mode planning. Runtime execution lives in DisplayMode.qml.
function normalizedNames(names) {
    const seen = {};
    return Array.from(names || []).map(name => String(name || "")).filter(name => {
        if (!name.length || seen[name]) return false;
        seen[name] = true;
        return true;
    });
}
function primary(names, preferred) {
    names = normalizedNames(names);
    preferred = String(preferred || "");
    return names.includes(preferred) ? preferred : (names[0] || "");
}
function activeNames(outputs) {
    return Object.keys(outputs || {}).filter(name => !!outputs[name]?.logical).sort();
}
function orderedActions(names, enabled) {
    names = normalizedNames(names);
    enabled = normalizedNames(enabled).filter(name => names.includes(name));
    const enabledSet = {};
    enabled.forEach(name => enabledSet[name] = true);
    return enabled.map(name => ({output:name,power:"on"}))
        .concat(names.filter(name => !enabledSet[name]).map(name => ({output:name,power:"off"})));
}
function plan(mode, names, preferredPrimary, secondary, mirrorSource, mirrorTarget) {
    names = normalizedNames(names);
    if (!names.length) return {ok:false,error:"No connected outputs are available.",actions:[],targets:[]};
    const primaryName = primary(names, preferredPrimary);
    let targets = [];
    let mirror = null;
    if (mode === "extend") {
        targets = names.slice();
    } else if (mode === "primary-only") {
        targets = [primaryName];
    } else if (mode === "second-only") {
        secondary = String(secondary || "");
        if (!names.includes(secondary) || secondary === primaryName)
            return {ok:false,error:"Choose a connected secondary output.",actions:[],targets:[]};
        targets = [secondary];
    } else if (mode === "mirror") {
        mirrorSource = String(mirrorSource || "");
        mirrorTarget = String(mirrorTarget || "");
        if (!names.includes(mirrorSource) || !names.includes(mirrorTarget) || mirrorSource === mirrorTarget)
            return {ok:false,error:"Choose two different connected outputs to mirror.",actions:[],targets:[]};
        targets = [mirrorSource, mirrorTarget];
        mirror = {source:mirrorSource,target:mirrorTarget};
    } else {
        return {ok:false,error:"Unknown display mode.",actions:[],targets:[]};
    }
    return {ok:true,error:"",actions:orderedActions(names,targets),targets:targets,mirror:mirror};
}
function restore(names, previouslyActive, preferredPrimary) {
    names = normalizedNames(names);
    if (!names.length) return {ok:false,error:"No connected outputs remain for rollback.",actions:[],targets:[]};
    let targets = normalizedNames(previouslyActive).filter(name => names.includes(name));
    if (!targets.length) targets = [primary(names,preferredPrimary)];
    return {ok:true,error:"",actions:orderedActions(names,targets),targets:targets};
}

// Stable runtime reporting: UI source/target dropdowns can change while
// wl-mirror is still running. Only the launched pair is authoritative.
function mirrorRunningMessage(pair) {
    return pair?.source && pair?.target
        ? "Mirroring " + pair.source + " to " + pair.target + "."
        : "";
}
function mirrorStoppedMessage(expectedStop, manualStop) {
    // Internal stop during Apply/hotplug must not replace its own status.
    return !expectedStop || manualStop ? "Display mirror stopped." : "";
}

// Validate the actual running wl-mirror pair, not a UI selection that may be
// rewritten when Niri reports a hotplug. Reject stale queued restarts too.
function mirrorPairConnected(names,pair) {
    if (!pair) return false;
    names = normalizedNames(names);
    const source=String(pair.source || ""),target=String(pair.target || "");
    return !!source && !!target && source !== target
        && names.includes(source) && names.includes(target);
}

// Only the currently requested connected pair may be restarted after exit.
function mirrorRestartAllowed(queuedRevision, currentRevision, applying, names, pair) {
    return Number.isInteger(queuedRevision) && queuedRevision === currentRevision
        && !applying && mirrorPairConnected(names, pair);
}

 
// Human-facing output identity. Keep the actual Niri connector as the command
// target; EDID make/model is informational and may be duplicated or missing.
function outputLabel(name, info) {
    const connector = String(name || "");
    const parts = [info?.make, info?.model].map(x => String(x || "").trim())
        .filter(x => x && !/^(unknown|none|n\/a)$/i.test(x));
    const description = parts.join(" ");
    return description ? description + " (" + connector + ")" : connector;
}

// Laptop panels usually expose eDP/LVDS/DSI. Do not guess that the first
// connected output is internal: it might be the very TV that just vanished.
function internalOutput(names) {
    return normalizedNames(names).find(name => /^(edp|lvds|dsi)([-_0-9]|$)/i.test(name)) || "";
}

// Only re-enable the known laptop panel for a managed external-only session
// when the external target disappeared AND no other visible output remains.
function recoveryTarget(connected, active, expectedExternal, internal) {
    connected = normalizedNames(connected);
    active = normalizedNames(active);
    expectedExternal = String(expectedExternal || "");
    internal = String(internal || "");
    if (!expectedExternal || connected.includes(expectedExternal) || active.length)
        return "";
    if (!internal || internal === expectedExternal || !connected.includes(internal))
        return "";
    return internal;
}
