// Shared Quick Notes Markdown presentation/formatting policy.
// Only Notepad.qml persists source; the preview is never written to disk.
function safeReading(source) {
    var raw = String(source === undefined || source === null ? "" : source).slice(0, 160000);
    // Leave fenced-code payloads untouched, but never load Markdown image URLs.
    // The existing preview uses only owned attachment images.
    return raw.split(/(\x60{3}[\s\S]*?\x60{3}|~{3}[\s\S]*?~{3})/g).map(function(part, index) {
        if (index % 2) return part;
        return part.replace(/!\[([^\]\r\n]*)\](?:\((?:\\.|[^)\r\n])*\)|\[[^\]\r\n]*\])?/g,
                function(_, alt) { return "[Image: " + alt + "]"; })
            .replace(/</g, "&lt;");
    }).join("");
}

// Offset indices use UTF-16 units, like QML TextArea.
function format(source, first, last, kind) {
    var raw = String(source === undefined || source === null ? "" : source);
    var a = Math.max(0, Math.min(raw.length, Number(first) || 0));
    var b = Math.max(a, Math.min(raw.length, Number(last) || 0));
    var selected = raw.slice(a, b);
    if (kind === "link") {
        return {from:a, to:b, insert:"[" + selected + "](https://)",
            selectionStart:selected.length ? a + 3 + selected.length : a + 1,
            selectionEnd:selected.length ? a + 11 + selected.length : a + 1};
    }
    var marker = kind === "bold" ? "**" : kind === "italic" ? "*" : kind === "code" ? "\x60" : "";
    if (!marker) return null;
    var n = marker.length;
    if (a >= n && raw.slice(a-n, a) === marker && raw.slice(b, b+n) === marker) {
        return {from:a-n, to:b+n, insert:selected,
            selectionStart:a-n, selectionEnd:a-n+selected.length};
    }
    if (selected.length >= 2*n && selected.startsWith(marker) && selected.endsWith(marker)) {
        var inner = selected.slice(n, -n);
        return {from:a, to:b, insert:inner, selectionStart:a, selectionEnd:a+inner.length};
    }
    return {from:a, to:b, insert:marker + selected + marker,
        selectionStart:a+n, selectionEnd:a+n+selected.length};
}

// The persistent image helper saves files with SHA256 basenames and owned URLs.
function attachmentUrls(source, directory) {
    var result = [], raw = String(source || "");
    var owner = String(directory || "").replace(/\/+$/, "");
    var pattern = /!\[[^\]\r\n]*\]\((file:\/\/[^)\r\n]+)\)/g, match;
    while ((match = pattern.exec(raw)) !== null) {
        var url = match[1], path;
        try { path = decodeURIComponent(url.slice(7)); }
        catch (error) { continue; }
        if (!path.startsWith(owner + "/")) continue;
        var file = path.slice(owner.length + 1);
        if (!/^[a-f0-9]{64}\.(?:png|jpg|webp|gif|bmp|tiff)$/.test(file)) continue;
        if (!result.includes(url)) result.push(url);
        if (result.length >= 32) break;
    }
    return result;
}
