// Pure decisions for classroom Project & Cast audio routing.
// Never infer the HDMI/USB-C TV from a generic USB speaker or a software DSP sink.
function name(node) {
    if (!node) return "";
    const props = node.properties || {};
    return String(props["node.name"] || node.name || "").trim();
}
function isEffects(node) {
    const props = node?.properties || {};
    const n = name(node);
    return n === "easyeffects_sink"
        || String(props["application.id"] || "") === "com.github.wwmm.easyeffects"
        || (String(props["node.virtual"] || "") === "true"
            && String(props["monitor.passthrough"] || "") === "true");
}
function isTvSink(node) {
    if (!node || node.isStream || node.isSink === false || isEffects(node))
        return false;
    const props = node.properties || {};
    const fields = [
        name(node),
        props["api.alsa.path"],
        props["api.alsa.pcm.stream"],
        props["device.profile.name"],
        props["node.description"]
    ].map(s => String(s || "").toLowerCase());
    // Explicit digital HDMI/DP route: avoid matching a coincidentally named
    // app, Bluetooth speaker, generic USB device, or network-cast sink.
    return fields.some(s => /(^|[._:/ -])(hdmi|displayport)([._:/ -]|$)/.test(s)
        || /(^|[._:/ -])dp[0-9]+([._:/ -]|$)/.test(s));
}
function chooseTvSink(devices) {
    const candidates = (devices || []).filter(isTvSink).filter(n => Number(n.id) > 0);
    // In multi-TV/audio setups no reliable mapping to one physical display.
    return candidates.length === 1 ? candidates[0] : null;
}
function findByName(devices, wanted) {
    if (!wanted) return null;
    return (devices || []).find(n => name(n) === wanted && Number(n.id) > 0) || null;
}
function safeToRestore(current, selected, previous, devices) {
    return !!selected && name(current) === selected
        && !!previous && previous !== selected
        && !!findByName(devices, previous);
}

function wirelessSinkName(uuid) {
    const id = String(uuid || "");
    // GNOME Network Displays' nd-pulseaudio.c uses %.8s of receiver UUID.
    return /^[A-Za-z0-9_.:-]{8,128}$/.test(id)
        ? "gnome_network_displays_" + id.slice(0, 8) : "";
}
function findWirelessSink(devices, uuid) {
    const wanted = wirelessSinkName(uuid).toLowerCase();
    if (!wanted) return null;
    const candidates = (devices || []).filter(node =>
        !node.isStream && node.isSink !== false && Number(node.id) > 0
        && name(node).toLowerCase() === wanted);
    return candidates.length === 1 ? candidates[0] : null;
}
