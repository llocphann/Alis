pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import "WindowPreviewPolicy.js" as PreviewPolicy

/**
 * WindowPreviewService - cached Niri window previews for Overview/TaskView
 *
 * Strategy:
 * - Pre-capture newly observed windows so the first presentation is immediate
 * - Reuse snapshots for hover/task surfaces without an arbitrary wall-clock TTL
 * - Refresh only the bounded visible window set when Overview opens
 * - Cache in ~/.cache/alis/window-previews/ and clean up on window close/session reset
 */
Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    readonly property string previewDir: FileUtils.trimFileProtocol(Directories.genericCache) + "/alis/window-previews"
    readonly property string sessionMarkerPath: previewDir + "/.niri-session"
    readonly property string sessionKey: NiriService.socketPath ?? ""
    
    // Map of windowId -> { path, timestamp }; timestamp revises URLs on capture.
    property var previewCache: ({})
    
    property bool initialized: false
    property bool sessionReady: false
    property bool captureRequestedWhileInitializing: false
    property bool forceRefreshRequestedWhileInitializing: false
    property bool capturing: false
    property bool captureAllRequested: false
    property var requestedWindowIds: []
    // Overview is a spatial snapshot, so it may refresh the bounded set of
    // currently visible windows without invalidating the session cache used by
    // hover previews. These IDs bypass needsCapture for one consumed batch.
    property var forceRequestedWindowIds: []
    property var observedWindowIds: []

    // Decoded CPU pixmaps outlive StyledPopup's lazy visual delegate, without
    // holding the popup window or its FBO. At most 12 x 768 x 512 x 4 bytes
    // (~18 MiB of pixel data) are resident in this independent cache.
    readonly property int overviewWarmLimit: 12
    readonly property int overviewWarmDecodeWidth: 768
    readonly property int overviewWarmDecodeHeight: 512
    property var overviewWarmImages: ({})
    property var overviewWarmOrder: []
    property var overviewWarmRequestedIds: []

    Component {
        id: overviewWarmImageComponent
        Image {
            width: 0
            height: 0
            visible: false
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.overviewWarmDecodeWidth, root.overviewWarmDecodeHeight)
        }
    }

    function _dropOverviewWarmImage(windowId): void {
        const item = overviewWarmImages[windowId]
        if (item) {
            item.image.destroy()
            delete overviewWarmImages[windowId]
        }
        overviewWarmOrder = overviewWarmOrder.filter(id => id !== Number(windowId))
    }

    function _clearOverviewWarmImages(): void {
        for (const id of Object.keys(overviewWarmImages))
            overviewWarmImages[id].image.destroy()
        overviewWarmImages = ({})
        overviewWarmOrder = []
    }

    function _touchOverviewWarmImage(windowId): void {
        const cached = previewCache[windowId]
        if (PreviewPolicy.needsCapture(cached)) {
            root._dropOverviewWarmImage(windowId)
            return
        }
        const url = PreviewPolicy.previewUrl(cached)
        if (!url) {
            root._dropOverviewWarmImage(windowId)
            return
        }
        const previous = overviewWarmImages[windowId]
        if (!previous || previous.url !== url) {
            if (previous)
                previous.image.destroy()
            // The singleton is not a QQuickItem. Parenting an Image to it makes
            // Qt warn that the graphical object was not placed in a scene.
            // Keep the predecoder deliberately parentless; the JS cache owns
            // the reference and every lifecycle path explicitly destroy()s it.
            const image = overviewWarmImageComponent.createObject(
                null, { source: url })
            if (!image) {
                delete overviewWarmImages[windowId]
                return
            }
            overviewWarmImages[windowId] = { image: image, url: url }
        }
        overviewWarmOrder = overviewWarmOrder.filter(id => id !== windowId).concat([windowId])
        while (overviewWarmOrder.length > overviewWarmLimit)
            root._dropOverviewWarmImage(overviewWarmOrder[0])
    }

    function _syncOverviewWarmImages(): void {
        for (const id of overviewWarmRequestedIds)
            root._touchOverviewWarmImage(id)
    }

    function warmForOverview(windowIds): void {
        overviewWarmRequestedIds = PreviewPolicy.boundedWindowIds(windowIds, overviewWarmLimit)
        root._syncOverviewWarmImages()
    }

    function _primeCachedPreviews(): void {
        if (!NiriService.windowListReady)
            return
        // Warm only a bounded initial set restored from disk; newly completed
        // screenshots are warmed separately at publication time.
        const ids = PreviewPolicy.boundedWindowIds(
            (NiriService.windows ?? []).map(window => window.id), overviewWarmLimit)
        for (const id of ids) {
            if (!PreviewPolicy.needsCapture(previewCache[id]))
                root._touchOverviewWarmImage(id)
        }
    }

    // Debounce: coalesce rapid capture requests (e.g. hovering across multiple dock icons)
    Timer {
        id: captureDebounceTimer
        interval: 100  // 100ms debounce — fast enough to feel instant, slow enough to coalesce
        repeat: false
        onTriggered: root._doCapture()
    }

    
    signal captureComplete()
    signal previewUpdated(int windowId)

    // Prime missing snapshots from the compositor event stream, rather than
    // starting the first screenshot only after a user hovers Overview.
    Component.onCompleted: root._startPrewarming()

    Connections {
        target: CompositorService
        function onIsNiriChanged(): void {
            root._startPrewarming()
        }
    }

    function _startPrewarming(): void {
        if (!CompositorService.isNiri)
            return
        root.initialize()
        root._observeWindowSet()
    }

    function _observeWindowSet(): void {
        if (!NiriService.windowListReady)
            return
        const ids = (NiriService.windows ?? []).map(window => window.id)
            .filter(id => Number.isSafeInteger(id) && id > 0)
        const previousIds = new Set(observedWindowIds)
        observedWindowIds = ids
        cleanupTimer.restart()
        const newIds = ids.filter(id => !previousIds.has(id))
        for (const id of newIds) {
            if (!PreviewPolicy.needsCapture(previewCache[id]))
                root._touchOverviewWarmImage(id)
        }
        if (newIds.length > 0)
            root.captureForTaskView(newIds)
    }

    function initialize(): void {
        if (initialized) return
        initialized = true
        ensureDirProcess.running = true
    }

    function _resumeRequestedCapture(): void {
        if (forceRefreshRequestedWhileInitializing) {
            forceRefreshRequestedWhileInitializing = false
            root.captureAllWindows()
        }
        if (!captureRequestedWhileInitializing)
            return
        captureRequestedWhileInitializing = false
        captureDebounceTimer.restart()
    }

    function _queueWindowIds(windowIds): void {
        if (windowIds === null || windowIds === undefined) {
            captureAllRequested = true
            requestedWindowIds = []
            return
        }
        if (captureAllRequested || !Array.isArray(windowIds))
            return
        const merged = new Set(requestedWindowIds)
        for (const rawId of windowIds) {
            const id = Number(rawId)
            if (Number.isFinite(id) && id > 0)
                merged.add(id)
        }
        requestedWindowIds = Array.from(merged)
    }

    function _queueForcedWindowIds(windowIds): void {
        if (!Array.isArray(windowIds))
            return
        const merged = new Set(forceRequestedWindowIds)
        for (const rawId of windowIds) {
            const id = Number(rawId)
            if (Number.isSafeInteger(id) && id > 0)
                merged.add(id)
        }
        forceRequestedWindowIds = Array.from(merged)
    }

    function _hasPendingCaptureRequest(): bool {
        return captureAllRequested
            || requestedWindowIds.length > 0
            || forceRequestedWindowIds.length > 0
    }

    function _clearCaptureRequest(): void {
        captureAllRequested = false
        requestedWindowIds = []
        forceRequestedWindowIds = []
    }

    function _pendingRequestNeedsCapture(): bool {
        if (forceRequestedWindowIds.length > 0)
            return true
        const currentIds = captureAllRequested
            ? (NiriService.windows ?? []).map(window => window.id)
            : requestedWindowIds
        for (const id of currentIds) {
            if (PreviewPolicy.needsCapture(previewCache[id]))
                return true
        }
        return false
    }

    function _resetForCurrentSession(): void {
        sessionResetProcess.running = true
    }

    function _completeSessionReset(): void {
        root._clearOverviewWarmImages()
        root.previewCache = ({})
        root.sessionReady = true
        if (root.sessionKey.length > 0)
            sessionFileView.setText(root.sessionKey + "\n")
        root.captureComplete()
        root._resumeRequestedCapture()
    }
    
    Process {
        id: ensureDirProcess
        property bool startObserved: false
        command: ["/usr/bin/mkdir", "-p", root.previewDir]
        onRunningChanged: {
            if (ensureDirProcess.running) {
                ensureDirProcess.startObserved = false
                return
            }
            if (ensureDirProcess.startObserved)
                return

            console.warn("[WindowPreviewService] preview directory helper failed to start")
            root._readSessionMarker()
        }
        onStarted: ensureDirProcess.startObserved = true
        onExited: root._readSessionMarker()
    }

    function _readSessionMarker(): void {
        if (!root.initialized || root.sessionReady || sessionFileView.readPending)
            return
        sessionFileView.readPending = true
        sessionFileView.reload()
    }

    FileView {
        id: sessionFileView
        property bool readPending: false
        path: root.sessionMarkerPath
        blockLoading: true
        atomicWrites: true
        printErrors: false

        onLoaded: {
            if (!sessionFileView.readPending)
                return
            sessionFileView.readPending = false
            const previousKey = sessionFileView.text().trim()
            if (root.sessionKey.length > 0 && previousKey === root.sessionKey)
                scanProcess.running = true
            else
                root._resetForCurrentSession()
        }

        onLoadFailed: {
            if (!sessionFileView.readPending)
                return
            sessionFileView.readPending = false
            if (root.initialized && !root.sessionReady)
                root._resetForCurrentSession()
        }
    }

    Process {
        id: sessionResetProcess
        property bool startObserved: false
        command: [
            "/usr/bin/find", root.previewDir,
            "-maxdepth", "1", "-type", "f",
            "-name", "window-*.png", "-delete"
        ]
        onRunningChanged: {
            if (sessionResetProcess.running) {
                sessionResetProcess.startObserved = false
                return
            }
            if (sessionResetProcess.startObserved)
                return

            console.warn("[WindowPreviewService] session reset helper failed to start")
            root._completeSessionReset()
        }
        onStarted: sessionResetProcess.startObserved = true
        onExited: {
            root._completeSessionReset()
        }
    }
    
    Process {
        id: scanProcess
        property bool startObserved: false
        command: ["/usr/bin/ls", "-1", root.previewDir]
        stdout: SplitParser {
            onRead: data => {
                const filename = data.trim()
                const match = filename.match(/^window-(\d+)\.png$/)
                if (match) {
                    const id = parseInt(match[1])
                    root.previewCache[id] = {
                        path: root.previewDir + "/" + filename,
                        timestamp: Date.now()
                    }
                }
            }
        }
        onRunningChanged: {
            if (scanProcess.running) {
                scanProcess.startObserved = false
                return
            }
            if (scanProcess.startObserved)
                return

            console.warn("[WindowPreviewService] preview cache scan failed to start")
            root.cleanupOrphans()
            root.previewCache = Object.assign({}, root.previewCache)
            root.sessionReady = true
            root._primeCachedPreviews()
            root._syncOverviewWarmImages()
            root.captureComplete()
            root._resumeRequestedCapture()
        }
        onStarted: scanProcess.startObserved = true
        onExited: {
            _log("[WindowPreviewService] Loaded", Object.keys(root.previewCache).length, "cached previews")
            root.cleanupOrphans()
            root.previewCache = Object.assign({}, root.previewCache)
            root.sessionReady = true
            root._primeCachedPreviews()
            root._syncOverviewWarmImages()
            root.captureComplete()
            root._resumeRequestedCapture()
        }
    }
    
    // Remove previews only against an authoritative compositor window list.
    function cleanupOrphans(): void {
        if (!NiriService.windowListReady)
            return
        const windows = NiriService.windows ?? []
        const windowIds = new Set(windows.map(w => w.id))
        
        const toDelete = []
        for (const id in previewCache) {
            if (!windowIds.has(parseInt(id))) {
                toDelete.push(id)
            }
        }
        
        if (toDelete.length > 0) {
            for (const id of toDelete) {
                delete previewCache[id]
                root._dropOverviewWarmImage(id)
            }
            overviewWarmRequestedIds = overviewWarmRequestedIds.filter(id => windowIds.has(id))
            previewCache = Object.assign({}, previewCache)
            
            // Delete files
            const cmd = ["/usr/bin/rm", "-f"]
            for (const id of toDelete) {
                cmd.push(root.previewDir + "/window-" + id + ".png")
            }
            Quickshell.execDetached(cmd)
        }
    }


    
    // Called when TaskView/dock preview opens - debounced to coalesce rapid hover events
    function captureForTaskView(windowIds = null): void {
        root._queueWindowIds(windowIds)
        if (!initialized) initialize()

        // Always emit captureComplete immediately so cached previews show instantly
        root.captureComplete()

        if (!sessionReady) {
            captureRequestedWhileInitializing = true
            return
        }

        if (capturing) return

        // A prior capture is a cache hit even after hours of idle.
        if (!root._pendingRequestNeedsCapture()) {
            root._clearCaptureRequest()
            return
        }

        captureDebounceTimer.restart()
    }

    // Unlike a hover preview, Overview represents the current workspace state.
    // Keep the cached image on screen immediately, then refresh only the bounded
    // set of visible window IDs so long-lived Kitty/browser windows do not keep
    // the snapshot they happened to have when they were first created.
    function refreshForOverview(windowIds): void {
        const ids = PreviewPolicy.boundedWindowIds(windowIds, overviewWarmLimit)
        if (ids.length === 0)
            return

        root.warmForOverview(ids)
        root._queueForcedWindowIds(ids)
        if (!initialized) initialize()

        root.captureComplete()

        if (!sessionReady) {
            captureRequestedWhileInitializing = true
            return
        }

        if (capturing)
            return

        captureDebounceTimer.restart()
    }

    // Internal: actual capture logic, called after debounce
    function _doCapture(): void {
        if (capturing) return
        
        const allWindows = NiriService.windows ?? []
        const requestedIds = new Set(root.requestedWindowIds)
        const forcedIds = new Set(root.forceRequestedWindowIds)
        const captureEverything = root.captureAllRequested
        root._clearCaptureRequest()
        const windows = captureEverything
            ? allWindows
            : allWindows.filter(window =>
                requestedIds.has(window.id) || forcedIds.has(window.id))
        if (windows.length === 0) return
        
        const idsToCapture = []
        
        for (const win of windows) {
            const cached = previewCache[win.id]
            // Normal requests only fill missing previews. Overview may force one
            // bounded visible ID so an existing snapshot can be refreshed.
            if (forcedIds.has(win.id) || PreviewPolicy.needsCapture(cached)) {
                idsToCapture.push(win.id)
            }
        }
        
        if (idsToCapture.length === 0) {
            root.captureComplete()
            return
        }
        
        _log("[WindowPreviewService] Capturing", idsToCapture.length, "windows")
        capturing = true
        Cliphist.suppressRefresh = true
        
        // Build command with IDs
        const cmd = ShellExec.supportsFish()
            ? ["/usr/bin/fish", Quickshell.shellPath("scripts/capture-windows.fish")]
            : ["/usr/bin/bash", Quickshell.shellPath("scripts/capture-windows.sh")]
        for (const id of idsToCapture) {
            cmd.push(id.toString())
        }
        
        captureProcess.idsToCapture = idsToCapture
        captureProcess.publishedIds = []
        captureProcess.captureSessionKey = root.sessionKey
        captureProcess.command = cmd
        captureProcess.running = true
    }

    // The capture script writes each PNG by atomic rename and immediately
    // reports it on stdout. Publish that window before clipboard cleanup and
    // before slower members of the same batch finish.
    function _publishCapturedPreview(windowId: int): void {
        if (!root.capturing || !captureProcess.idsToCapture.includes(windowId)
                || captureProcess.publishedIds.includes(windowId)
                || captureProcess.captureSessionKey !== root.sessionKey
                || !(NiriService.windows ?? []).some(window => window.id === windowId))
            return

        const path = root.previewDir + "/window-" + windowId + ".png"
        const previous = root.previewCache[windowId]
        root.previewCache[windowId] = {
            path: path,
            timestamp: PreviewPolicy.nextRevision(previous?.timestamp, Date.now())
        }
        captureProcess.publishedIds = captureProcess.publishedIds.concat([windowId])
        root.previewCache = Object.assign({}, root.previewCache)
        // Decode immediately, even before Overview has been opened once.
        // The bounded resident cache survives the popup's LazyLoader teardown.
        root._touchOverviewWarmImage(windowId)
        root.previewUpdated(windowId)
    }

    function _handleCaptureOutput(line: string): void {
        const match = String(line).trim().match(/^PREVIEW_READY ([1-9][0-9]*)$/)
        if (match)
            root._publishCapturedPreview(Number(match[1]))
        else
            root._log("[WindowPreviewService:capture]", line)
    }
    
    // Recover completion records which QProcess may flush only at exit. The
    // helper returns zero only when every explicitly requested PNG was
    // successfully published by atomic rename.
    function _completeCapture(exitCode: int, exitStatus: var): void {
        if (exitCode === 0) {
            for (const id of captureProcess.idsToCapture)
                root._publishCapturedPreview(id)
        } else {
            console.warn("[WindowPreviewService] capture process failed", exitCode, exitStatus)
        }
        capturing = false
        captureProcess.idsToCapture = []
        captureProcess.publishedIds = []
        captureProcess.captureSessionKey = ""
        root.cleanupOrphans()
        Cliphist.suppressRefresh = false
        Cliphist.refresh()
        root.captureComplete()
        if (root._hasPendingCaptureRequest())
            captureDebounceTimer.restart()
    }

    // Capture ALL windows (force refresh)
    function captureAllWindows(): void {
        if (capturing) return

        if (!initialized) initialize()
        if (!sessionReady) {
            forceRefreshRequestedWhileInitializing = true
            return
        }

        const windows = NiriService.windows ?? []
        if (windows.length === 0) return

        _log("[WindowPreviewService] Force capturing all", windows.length, "windows")
        capturing = true
        Cliphist.suppressRefresh = true
        
        const ids = windows.map(w => w.id)
        captureProcess.idsToCapture = ids
        captureProcess.publishedIds = []
        captureProcess.captureSessionKey = root.sessionKey
        const cmd = ShellExec.supportsFish()
            ? ["/usr/bin/fish", Quickshell.shellPath("scripts/capture-windows.fish")]
            : ["/usr/bin/bash", Quickshell.shellPath("scripts/capture-windows.sh")]
        // Pass the exact snapshot of requested IDs. The helper now fails if
        // even one ID is no longer available, so clean exit cannot falsely
        // publish a file left behind by a previous capture.
        for (const id of ids)
            cmd.push(id.toString())
        captureProcess.command = cmd
        captureProcess.running = true
    }
    
    Process {
        id: captureProcess
        property var idsToCapture: []
        property var publishedIds: []
        property string captureSessionKey: ""
        property bool startObserved: false

        stdout: SplitParser {
            onRead: line => root._handleCaptureOutput(line)
        }
        stderr: SplitParser {
            onRead: (line) => _log("[WindowPreviewService:capture][err]", line)
        }

        onRunningChanged: {
            if (captureProcess.running) {
                captureProcess.startObserved = false
                return
            }
            if (captureProcess.startObserved)
                return

            console.warn("[WindowPreviewService] capture process failed to start")
            root.capturing = false
            idsToCapture = []
            publishedIds = []
            captureSessionKey = ""
            Cliphist.suppressRefresh = false
            Cliphist.refresh()
            root.captureComplete()
            if (root._hasPendingCaptureRequest())
                captureDebounceTimer.restart()
        }
        onStarted: captureProcess.startObserved = true
        
        onExited: (exitCode, exitStatus) => root._completeCapture(exitCode, exitStatus)
    }
    
    // Clean up when window closes
    Connections {
        target: NiriService
        enabled: root.initialized  // Skip event processing until initialized
        
        function onWindowsChanged(): void {
            root._observeWindowSet()
        }
        function onWindowListReadyChanged(): void {
            if (NiriService.windowListReady)
                root._observeWindowSet()
            else
                root.observedWindowIds = []
        }
    }
    
    Timer {
        id: cleanupTimer
        interval: 1000
        onTriggered: root.cleanupOrphans()
    }
    
    // Public API
    function getPreviewUrl(windowId: int): string {
        return PreviewPolicy.previewUrl(previewCache[windowId])
    }
    
    function hasPreview(windowId: int): bool {
        return !PreviewPolicy.needsCapture(previewCache[windowId])
    }
    
    function clearPreviews(): void {
        root._clearOverviewWarmImages()
        Quickshell.execDetached(["/usr/bin/rm", "-rf", previewDir])
        previewCache = {}
    }
}
