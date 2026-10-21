pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    // Limit how many entries we keep/read to avoid huge models and heavy fuzzy search
    property int maxEntries: 400
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    property int _readAttempts: 0
    property bool _refreshQueued: false
    property int _entriesRevision: 0
    property int _preparedEntriesRevision: -1
    property var _preparedEntriesCache: []
    property int _filterEntriesRevision: -1
    property var _filterEntriesCache: []

    onEntriesChanged: {
        root._entriesRevision++
        root._preparedEntriesRevision = -1
        root._preparedEntriesCache = []
        root._filterEntriesRevision = -1
        root._filterEntriesCache = []
    }

    function filterEntries(): var {
        if (root._filterEntriesRevision === root._entriesRevision)
            return root._filterEntriesCache

        const source = root.entries
        const prepared = new Array(source.length)
        for (let i = 0; i < source.length; ++i) {
            const entry = source[i]
            let cleaned = StringUtils.cleanCliphistEntry(entry)
            if (root.entryIsImage(entry))
                cleaned = cleaned.replace(/^\s*\[\[.*?\]\]\s*/, "")
            const unwrapped = StringUtils.cliphistMarkupPreview(cleaned)
            if (unwrapped !== cleaned)
                cleaned = unwrapped.length > 0 ? unwrapped : Translation.tr("Rich text")
            prepared[i] = {
                entry: entry,
                iiKey: StringUtils.sanitizeDisplayText(cleaned).trim().toLowerCase(),
                waffleKey: cleaned.trim().toLowerCase()
            }
        }
        root._filterEntriesCache = prepared
        root._filterEntriesRevision = root._entriesRevision
        return prepared
    }

    function _ensurePreparedEntries(): var {
        if (root._preparedEntriesRevision === root._entriesRevision)
            return root._preparedEntriesCache

        const source = root.entries
        const prepared = new Array(source.length)
        for (let i = 0; i < source.length; ++i) {
            const entry = source[i]
            prepared[i] = {
                name: Fuzzy.prepare(`${entry.replace(/^\s*\S+\s+/, "")}`),
                entry: entry
            }
        }
        root._preparedEntriesCache = prepared
        root._preparedEntriesRevision = root._entriesRevision
        return prepared
    }

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    function _entriesEqual(nextEntries): bool {
        if (!nextEntries || nextEntries.length !== root.entries.length)
            return false
        for (let i = 0; i < nextEntries.length; ++i) {
            if (nextEntries[i] !== root.entries[i])
                return false
        }
        return true
    }

    function _insertTopScored(top, candidate, limit): void {
        let low = 0
        let high = top.length
        while (low < high) {
            const mid = (low + high) >> 1
            if (candidate.score > top[mid].score)
                high = mid
            else
                low = mid + 1
        }
        top.splice(low, 0, candidate)
        if (top.length > limit)
            top.pop()
    }

    function fuzzyQuery(search: string, limit): var {
        if (search.trim() === "") {
            const count = limit > 0 ? Math.min(limit, root.maxEntries) : root.maxEntries
            return entries.slice(0, count);
        }
        if (root.sloppySearch) {
            const searchLower = search.toLowerCase()
            const count = Math.min(100, root.maxEntries)
            if (limit > 0) {
                const top = []
                for (let i = 0; i < count; ++i) {
                    const entry = entries[i]
                    const score = Levendist.computeTextMatchScore(
                        entry.toLowerCase(), searchLower)
                    if (score > root.scoreThreshold)
                        root._insertTopScored(top,
                            { entry: entry, score: score }, limit)
                }
                return top.map(item => item.entry)
            }

            const results = new Array(count)
            let resultCount = 0
            for (let i = 0; i < count; ++i) {
                const entry = entries[i]
                const score = Levendist.computeTextMatchScore(
                    entry.toLowerCase(), searchLower)
                if (score > root.scoreThreshold)
                    results[resultCount++] = { entry: entry, score: score }
            }
            results.length = resultCount
            results.sort((a, b) => b.score - a.score)
            return results.map(item => item.entry)
        }

        const results = Fuzzy.go(search, root._ensurePreparedEntries(), {
            all: true,
            key: "name",
            limit: limit > 0 ? limit : undefined
        })
        return results.map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry): bool {
        const raw = String(entry ?? "")
        // cliphist versions/builds do not all render the list separator the
        // same way. Classify the preview payload itself instead of requiring
        // exactly "ID<TAB>metadata". This also covers the owner's observed
        // "[[ binary data ... png 1194x863 ]]" rows.
        const preview = raw.replace(/^\s*\d+(?:\t|\s+)/, "").trim()
        // Owner cliphist output can append/retain extra preview material around
        // the binary marker. Treat the marker as the authoritative signal
        // instead of requiring it to occupy the whole list line.
        if (!/\[\[\s*binary data\b[\s\S]*?\]\]/i.test(preview))
            return false
        return /\b(?:image\/[a-z0-9.+-]+|png|jpe?g|webp|gif|bmp|tiff?|avif|heic|heif)\b/i.test(preview)
            || /\b\d{1,6}\s*[x×]\s*\d{1,6}\b/i.test(preview)
    }

    function entryImageMime(entry): string {
        if (!root.entryIsImage(entry))
            return ""
        const preview = String(entry ?? "")
            .replace(/^\s*\d+(?:\t|\s+)/, "").toLowerCase()
        if (/\b(?:png|image\/png)\b/.test(preview)) return "image/png"
        if (/\b(?:jpe?g|image\/jpe?g)\b/.test(preview)) return "image/jpeg"
        if (/\b(?:webp|image\/webp)\b/.test(preview)) return "image/webp"
        if (/\b(?:gif|image\/gif)\b/.test(preview)) return "image/gif"
        if (/\b(?:bmp|image\/bmp)\b/.test(preview)) return "image/bmp"
        if (/\b(?:tiff?|image\/tiff?)\b/.test(preview)) return "image/tiff"
        if (/\b(?:avif|image\/avif)\b/.test(preview)) return "image/avif"
        if (/\b(?:heic|image\/heic)\b/.test(preview)) return "image/heic"
        if (/\b(?:heif|image\/heif)\b/.test(preview)) return "image/heif"
        const explicit = preview.match(/\b(image\/[a-z0-9.+-]+)\b/)
        return explicit ? explicit[1] : ""
    }

    function entryId(entry): string {
        const match = String(entry ?? "").match(/^\s*(\d+)/)
        return match ? match[1] : ""
    }

    // Entries captured before the watcher started stripping browser markup still
    // hold it, and they outlive the fix — so clean on the way out as well. The
    // filter forwards anything that is not a browser text/html payload byte for
    // byte, which keeps images intact.
    readonly property string _markupFilter: `'${Directories.scriptsPath}/native-dispatch' clipboard-store --filter`

    function decodeCommand(entry): string {
        if (root.cliphistBinary.includes("cliphist")) {
            const id = root.entryId(entry)
            if (id.length > 0)
                return `${root.cliphistBinary} decode ${id} | ${root._markupFilter}`
            return `printf '%s\n' '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | ${root._markupFilter}`
        }

        const entryNumber = String(entry ?? "").split("\t")[0]
        return `${root.cliphistBinary} decode ${entryNumber} | ${root._markupFilter}`
    }

    function wlCopyCommand(entry): string {
        const mime = root.entryImageMime(entry)
        const typeArg = mime.length > 0
            ? ` --type '${StringUtils.shellSingleQuoteEscape(mime)}'`
            : ""
        return `${root.decodeCommand(entry)} | /usr/bin/wl-copy${typeArg}`
    }

    function refresh() {
        if (readProc.running) {
            root._refreshQueued = true
            return
        }
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        root._log("[Cliphist] copy()", String(entry).slice(0, 120))
        root._selfCopy = true
        selfCopyResetTimer.restart()
        Quickshell.execDetached(["/usr/bin/bash", "-c",
            root.wlCopyCommand(entry)]);
    }

    function paste(entry) {
        root._selfCopy = true
        Quickshell.execDetached(["/usr/bin/bash", "-c",
            `${root.wlCopyCommand(entry)}\n${root.pressPasteCommand}`]);
    }

    function superpaste(count, isImage = false) {
        // Find entries
        let targetEntries
        if (Number.isInteger(count) && count >= 0) {
            targetEntries = []
            if (count > 0) {
                for (const entry of entries) {
                    if (isImage && !entryIsImage(entry))
                        continue
                    targetEntries.push(entry)
                    if (targetEntries.length >= count)
                        break
                }
            }
        } else {
            targetEntries = entries.filter(entry => {
                if (!isImage) return true;
                return entryIsImage(entry);
            }).slice(0, count)
        }

        const pasteCommands = []
        for (let i = targetEntries.length - 1; i >= 0; i--) {
            const entry = targetEntries[i]
            pasteCommands.push(
                `${root.wlCopyCommand(entry)}\n/usr/bin/sleep ${root.pasteDelay}\n${root.pressPasteCommand}`)
        }
        // Act
        Quickshell.execDetached(["/usr/bin/bash", "-c", pasteCommands.join(`\n/usr/bin/sleep ${root.pasteDelay}\n`)]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: [root.cliphistBinary, "delete"]
        stdinEnabled: true
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.stdinEnabled = true
            deleteProc.running = true;
        }
        onRunningChanged: {
            if (deleteProc.running) {
                const toWrite = deleteProc.entry
                deleteProc.write(toWrite)
                deleteProc.write("\n")
                deleteProc.stdinEnabled = false
            } else {
                deleteProc.stdinEnabled = true
            }
        }
        onExited: (exitCode, exitStatus) => {
            deleteProc.entry = "";
            root.refresh();
        }
    }

    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        wipeProc.running = true;
    }

    // Pins store the decoded text, not the cliphist id: ids are recycled and
    // entries fall out of the store once maxEntries rotates past them.
    readonly property var pinned: Config.options?.clipboard?.pinned ?? []
    property int maxPinLength: 8000

    function isPinnable(entry): bool {
        return String(entry ?? "").length > 0 && !root.entryIsImage(entry)
    }

    function pinPreview(text): string {
        const value = String(text ?? "")
        let start = 0
        while (start <= value.length) {
            const newline = value.indexOf("\n", start)
            const end = newline >= 0 ? newline : value.length
            const line = value.slice(start, end)
            if (line.trim().length > 0)
                return line.trim()
            if (newline < 0)
                break
            start = newline + 1
        }
        return ""
    }

    function isPinned(text): bool {
        return root.pinned.indexOf(text) !== -1
    }

    // Pins hold decoded text; list entries are "id<TAB>preview". Decoding every
    // visible row to compare would mean a subprocess per item, so match on the
    // preview instead.
    //
    // cliphist truncates that preview at 100 characters. Below the cut the
    // preview IS the whole entry, so it has to match exactly: prefix-matching a
    // short preview would mark every entry that merely starts a longer pin as
    // pinned. At or above the cut the preview is a prefix of the pinned text.
    readonly property int previewLimit: 100

    function _previewKey(text): string {
        return String(text ?? "").replace(/\s+/g, " ").trim()
    }

    function pinnedTextFor(entry): string {
        const raw = String(entry ?? "")
        const tab = raw.indexOf("\t")
        if (tab < 0) return ""
        const preview = root._previewKey(raw.slice(tab + 1))
        if (preview.length === 0) return ""
        const truncated = preview.length >= root.previewLimit
        return root.pinned.find(p => {
            const key = root._previewKey(p)
            return truncated ? key.startsWith(preview) : key === preview
        }) ?? ""
    }

    function unpin(text): void {
        Config.setNestedValue("clipboard.pinned", root.pinned.filter(p => p !== text))
    }

    function pinEntry(entry): void {
        if (!root.isPinnable(entry)) return
        pinProc.command = ["/usr/bin/bash", "-c", root.decodeCommand(entry)]
        pinProc.running = true
    }

    Process {
        id: pinProc
        stdout: StdioCollector {
            onStreamFinished: {
                // Entries stored before the watcher stripped browser markup still
                // carry it, and a pin keeps the decoded text forever — so clean it
                // here too, or pinning an old entry pins the markup with it.
                const decoded = root.stripBrowserMarkup(text).slice(0, root.maxPinLength)
                if (decoded.length === 0 || root.isPinned(decoded)) return
                Config.setNestedValue("clipboard.pinned", [decoded, ...root.pinned])
            }
        }
    }

    // Two wrappers mark a text/html payload: Firefox's content-type meta tag and
    // the CF_HTML fragment markers Chromium and Electron apps emit. They are the
    // only reliable sign that the content is markup rather than text that happens
    // to contain tags. Kept in sync with scripts/clipboard-store.py.
    function isBrowserMarkup(str): bool {
        return str.startsWith('<meta http-equiv="content-type" content="text/html')
            || str.indexOf("<!--StartFragment-->") !== -1
    }

    function stripBrowserMarkup(text): string {
        const str = String(text ?? "")
        if (!root.isBrowserMarkup(str))
            return str
        return StringUtils.stripHtmlTags(str.replace(/<!--[\s\S]*?-->/g, "")).trim()
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            // Skip refresh if clipboard text matches what we just copied ourselves
            if (root._selfCopy) {
                root._selfCopy = false;
                selfCopyResetTimer.stop();
                return;
            }
            // Skip refresh while window previews are being captured
            // (screenshots pollute clipboard temporarily, script cleans them up)
            if (root.suppressRefresh) return;
            delayedUpdateTimer.restart()
        }
    }

    property bool _selfCopy: false
    property bool suppressRefresh: false

    // Safety: reset _selfCopy if onClipboardTextChanged never fires (e.g. pipeline failed)
    Timer {
        id: selfCopyResetTimer
        interval: 2000
        onTriggered: {
            if (root._selfCopy) {
                root._log("[Cliphist] _selfCopy reset by timeout (pipeline may have failed)")
                root._selfCopy = false
            }
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: 800
        repeat: false
        onTriggered: {
            // Only refresh if not already running a read
            if (!readProc.running) root.refresh()
        }
    }

    Timer {
        id: readRetryTimer
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: readProc
        property list<string> buffer: []

        // Hide byte-identical text copies in every presentation while retaining
        // all original IDs/payloads on disk. Preview collisions remain distinct.
        command: ["/usr/bin/python3", `${Directories.scriptsPath}/clipboard-history.py`,
            "--binary", root.cliphistBinary, "--limit", String(root.maxEntries)]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Cap the number of entries we keep and do not emit a false
                // entriesChanged when an explicit refresh returns the same list.
                const nextEntries = readProc.buffer.slice(0, root.maxEntries)
                if (!root._entriesEqual(nextEntries))
                    root.entries = nextEntries
                root._readAttempts = 0
                if (root._refreshQueued) {
                    root._refreshQueued = false
                    root.refresh()
                }
            } else {
                if (root._readAttempts < 3) {
                    root._readAttempts++
                    readRetryTimer.interval = 250 * root._readAttempts
                    readRetryTimer.restart()
                } else {
                    root._readAttempts = 0
                    console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
                }
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
