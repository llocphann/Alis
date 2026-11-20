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
    property var _pendingRefresh: null
    property var _lastScanOrder: null

    signal refreshed()

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
        const cleanPath = FileUtils.trimFileProtocol(String(path ?? ""))
        if (!cleanPath) return

        // Scan the configured root plus every other folder the user is actually
        // working in. Deriving roots from one source made the list unstable:
        // videos appeared only while a wallpaper from their folder happened to
        // be applied.
        const roots = [cleanPath]
        for (const rawExtra of (extraPaths ?? [])) {
            const extra = FileUtils.trimFileProtocol(String(rawExtra ?? ""))
            if (!extra) continue
            // Skip anything already covered by, or covering, an accepted root.
            const redundant = roots.some(existing => {
                const existingPrefix = existing.endsWith("/") ? existing : existing + "/"
                const extraPrefix = extra.endsWith("/") ? extra : extra + "/"
                return extra === existing || extra.startsWith(existingPrefix)
                    || existing.startsWith(extraPrefix)
            })
            if (!redundant) roots.push(extra)
        }

        const signature = JSON.stringify(roots)
        // Even a cache hit is a newer choice than a queued folder.
        root._pendingRefresh = null
        if (!force && signature === root._scanSignature
                && (root.staticEntries.length > 0 || root.animatedEntries.length > 0))
            return

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
        colorTagsTimer.restart()
        scanProcess.exec([
            "find", "-L", ...roots, "-type", "f", "(",
            "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o",
            "-iname", "*.png", "-o", "-iname", "*.webp", "-o",
            "-iname", "*.avif", "-o", "-iname", "*.bmp", "-o",
            "-iname", "*.svg", "-o", "-iname", "*.gif", "-o",
            "-iname", "*.mp4", "-o", "-iname", "*.webm", "-o",
            "-iname", "*.mkv", "-o", "-iname", "*.avi", "-o",
            "-iname", "*.mov", ")", "-print0"
        ])
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
            const byName = (left, right) => left.relativePath.localeCompare(right.relativePath)
            staticItems.sort(byName)
            animatedItems.sort(byName)
            // Reuse only the order of an identical scan. Refresh still publishes
            // fresh entries, including when an image was replaced at the same path.
            root._lastScanOrder = { raw: rawOutput, prefix, separator, localeName,
                paths: staticItems.concat(animatedItems).map(entry => entry.path) }
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
