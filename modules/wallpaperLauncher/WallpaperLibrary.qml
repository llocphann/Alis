pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // The views filter complete snapshots. Keep their records in the JS engine.
    property var staticEntries: []
    property var animatedEntries: []
    property var colorTagsByPath: ({})
    property var _lastScanRoots: []
    property bool scanning: false
    property string directory: ""
    property string _scanSignature: ""
    property int _scanRevision: 0
    property string _lastRawOutput: ""
    property var _pendingRefresh: null
    property var _lastScanOrder: null
    readonly property var _pathIndexCache: ({ staticMap: Object.create(null), animatedMap: Object.create(null) })

    signal refreshed()

    function _normPath(rawPath: string): string {
        let p = String(rawPath ?? "").trim()
        if (!p)
            return ""
        if (p.startsWith("file://")) {
            p = p.slice(7)
            try {
                p = decodeURIComponent(p)
            } catch (_e) {}
        }
        return p.replace(/\/+$/, "")
    }

    function _buildPathIndex(items) {
        const map = Object.create(null)
        for (let i = 0; i < items.length; ++i) {
            const norm = root._normPath(items[i]?.path)
            if (norm && map[norm] === undefined)
                map[norm] = i
        }
        return map
    }

    function _applyPathIndex(staticMap, animatedMap): void {
        root._pathIndexCache.staticMap = staticMap ?? Object.create(null)
        root._pathIndexCache.animatedMap = animatedMap ?? Object.create(null)
    }

    function indexOfPath(normPath: string, mode: string): int {
        const clean = root._normPath(normPath)
        if (!clean)
            return -1
        const map = mode === "animated" ? root._pathIndexCache.animatedMap : root._pathIndexCache.staticMap
        const idx = map ? map[clean] : undefined
        return idx !== undefined ? idx : -1
    }

    function _buildRoots(path: string, extraPaths = []): var {
        const cleanPath = FileUtils.trimFileProtocol(String(path ?? ""))
        if (!cleanPath)
            return null
        const roots = [cleanPath]
        for (const rawExtra of (extraPaths ?? [])) {
            const extra = FileUtils.trimFileProtocol(String(rawExtra ?? ""))
            if (!extra) continue
            const redundant = roots.some(existing => {
                const existingPrefix = existing.endsWith("/") ? existing : existing + "/"
                const extraPrefix = extra.endsWith("/") ? extra : extra + "/"
                return extra === existing || extra.startsWith(existingPrefix)
                    || existing.startsWith(extraPrefix)
            })
            if (!redundant) roots.push(extra)
        }
        return { cleanPath, roots, signature: JSON.stringify(roots) }
    }

    function _findCommand(roots): var {
        return [
            "/usr/bin/nice", "-n", "10",
            "find", "-L", ...roots, "-type", "f", "(",
            "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o",
            "-iname", "*.png", "-o", "-iname", "*.webp", "-o",
            "-iname", "*.avif", "-o", "-iname", "*.bmp", "-o",
            "-iname", "*.svg", "-o", "-iname", "*.gif", "-o",
            "-iname", "*.mp4", "-o", "-iname", "*.webm", "-o",
            "-iname", "*.mkv", "-o", "-iname", "*.avi", "-o",
            "-iname", "*.mov", ")", "-print0"
        ]
    }

    function ensureColorTags(): void {
        if (colorTagsProcess.running || root._lastScanRoots.length === 0)
            return
        colorTagsTimer.stop()
        colorTagsProcess.revision = root._scanRevision
        colorTagsProcess.exec([
            "/usr/bin/nice", "-n", "19",
            `${Directories.scriptsPath}/native-dispatch`,
            "color-tags",
            "--roots",
            ...root._lastScanRoots
        ])
    }

    function refresh(path: string, extraPaths = [], force = false): void {
        const spec = root._buildRoots(path, extraPaths)
        if (!spec) return
        const { cleanPath, roots, signature } = spec

        // Even a cache hit is a newer choice than a queued folder.
        root._pendingRefresh = null
        if (!force && signature === root._scanSignature
                && (root.staticEntries.length > 0 || root.animatedEntries.length > 0))
            return

        if (!force) {
            const prefix = cleanPath.endsWith("/") ? cleanPath : cleanPath + "/"
            const cached = Wallpapers.getCachedLibraryScan(signature)
            if (cached && cached.prefix === prefix) {
                root.directory = cleanPath
                root._scanSignature = signature
                root._scanRevision++
                root._lastScanRoots = roots
                root._lastRawOutput = cached.rawOutput ?? ""
                root._lastScanOrder = cached.scanOrder ?? null
                root._applyPathIndex(cached.staticIndexMap, cached.animatedIndexMap)
                const clone = entry => ({
                    path: entry.path,
                    name: entry.name,
                    relativePath: entry.relativePath,
                    kind: entry.kind,
                    searchKey: entry.searchKey
                })
                root.staticEntries = (cached.staticEntries ?? []).map(clone)
                root.animatedEntries = (cached.animatedEntries ?? []).map(clone)
                root.scanning = false
                Wallpapers.preloadKnownThumbnails()
                root.refreshed()
                return
            }
        }

        if (root.scanning) {
            root._pendingRefresh = ({ path: cleanPath, extraPaths, force })
            return
        }

        root.directory = cleanPath
        root._scanSignature = signature
        root._scanRevision++
        root._lastScanRoots = roots
        root.scanning = true
        Wallpapers.preloadKnownThumbnails()
        scanProcess.exec(root._findCommand(roots))
    }

    function silentSync(path: string, extraPaths = []): void {
        if (root.scanning || silentScanProcess.running)
            return
        const spec = root._buildRoots(path, extraPaths)
        if (!spec || spec.signature !== root._scanSignature)
            return
        silentScanProcess._syncSignature = spec.signature
        silentScanProcess.exec(root._findCommand(spec.roots))
    }

    function consume(rawOutput: string, separator = "\n"): void {
        const staticItems = []
        const animatedItems = []
        const prefix = root.directory.endsWith("/") ? root.directory : root.directory + "/"
        const localeName = Qt.locale().name
        const previous = root._lastScanOrder
        const sameScan = previous && previous.raw === rawOutput && previous.prefix === prefix
            && previous.separator === separator && previous.localeName === localeName
        const records = sameScan ? previous.paths : rawOutput.split(separator)
        // Scan roots can overlap (the current wallpaper's folder may contain the
        // configured root), so the same file can be printed twice.
        const seen = sameScan ? null : Object.create(null)
        const videoExtensions = new Set([".mp4", ".webm", ".mkv", ".avi", ".mov"])
        for (const record of records) {
            const path = !sameScan && separator === "\n" ? record.trim() : record
            if (!path || (seen && seen[path])) continue
            if (seen) seen[path] = true
            const extension = path.slice(path.lastIndexOf(".")).toLowerCase()
            const isVideo = videoExtensions.has(extension)
            const isGif = extension === ".gif"
            const name = FileUtils.fileNameForPath(path)
            const relativePath = path.startsWith(prefix) ? path.slice(prefix.length) : path
            const kind = isVideo ? "video" : isGif ? "gif" : "static"
            const entry = {
                path: path,
                name: name,
                relativePath: relativePath,
                kind: kind,
                searchKey: `${relativePath} ${name} ${kind}`.toLowerCase()
            }
            // Animated = anything that moves, wherever it lives. A video outside a
            // conventional folder must not vanish from both lists.
            if (isVideo || isGif)
                animatedItems.push(entry)
            else
                staticItems.push(entry)
        }
        if (!sameScan) {
            const sortEntries = items => {
                const paired = items.map(entry => ({
                    key: entry.relativePath.toLowerCase(),
                    rel: entry.relativePath,
                    entry
                }))
                paired.sort((left, right) =>
                    left.key < right.key ? -1 : (left.key > right.key ? 1 : (left.rel < right.rel ? -1 : (left.rel > right.rel ? 1 : 0))))
                for (let i = 0; i < paired.length; ++i)
                    items[i] = paired[i].entry
            }
            sortEntries(staticItems)
            sortEntries(animatedItems)
            // Reuse only the order of an identical scan. Refresh still publishes
            // fresh entries, including when an image was replaced at the same path.
            root._lastScanOrder = { raw: rawOutput, prefix, separator, localeName,
                paths: staticItems.concat(animatedItems).map(entry => entry.path) }
        }
        const staticIndexMap = root._buildPathIndex(staticItems)
        const animatedIndexMap = root._buildPathIndex(animatedItems)
        root._lastRawOutput = rawOutput
        root._applyPathIndex(staticIndexMap, animatedIndexMap)
        if (root._scanSignature && separator === "\0") {
            Wallpapers.setCachedLibraryScan(root._scanSignature, {
                rawOutput,
                prefix,
                scanOrder: root._lastScanOrder,
                staticEntries: staticItems,
                animatedEntries: animatedItems,
                staticIndexMap,
                animatedIndexMap
            })
        }
        root.staticEntries = staticItems
        root.animatedEntries = animatedItems
        root.refreshed()
    }

    function _finishScan(): void {
        root.scanning = false
        // Observers may synchronously request a newer scan on this transition.
        const pending = root._pendingRefresh
        if (!root.scanning && pending)
            root.refresh(pending.path, pending.extraPaths, pending.force)
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: root.consume(text, "\0")
        }
        onExited: (exitCode, exitStatus) => {
            // One unreadable root makes find exit nonzero even though the other
            // roots produced results — only report empty when nothing was found.
            if (exitCode !== 0 && root.staticEntries.length === 0
                    && root.animatedEntries.length === 0)
                root.refreshed()

            root._finishScan()
        }
        onRunningChanged: {
            // Quickshell reports a failed start without an exited signal.
            if (!running && root.scanning) {
                root._scanSignature = ""
                root._finishScan()
            }
        }
    }

    Process {
        id: silentScanProcess
        property string _syncSignature: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.scanning || silentScanProcess._syncSignature !== root._scanSignature)
                    return
                if (text === root._lastRawOutput)
                    return
                if (text.length > 0 || root.staticEntries.length > 0 || root.animatedEntries.length > 0)
                    root.consume(text, "\0")
            }
        }
    }

    Timer {
        id: colorTagsTimer
        interval: 1800
        repeat: false
        onTriggered: root.ensureColorTags()
    }

    Process {
        id: colorTagsProcess
        property int revision
        stdout: StdioCollector { id: tagOutput; waitForEnd: true }
        onExited: exitCode => {
            if (revision !== root._scanRevision) {
                root.ensureColorTags()
                return
            }
            if (exitCode !== 0) return
            try {
                const tags = JSON.parse(tagOutput.text)
                if (tags && typeof tags === "object" && !Array.isArray(tags))
                    root.colorTagsByPath = tags
            } catch (e) {}
        }
    }
}
