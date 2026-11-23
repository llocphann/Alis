pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * GameMode service - detects fullscreen windows and disables effects for performance.
 * 
 * Two activation modes:
 * - Manual: user toggle via toggle()/activate()/deactivate(). Persists to file.
 * - Auto-detect: activates when focused window is fullscreen, deactivates
 *   immediately when leaving fullscreen. Applies the same performance
 *   optimizations as manual mode (no panel/background hiding).
 */
Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    // Public API
    // Keep fullscreen activation reactive even if the debounced check or the
    // manual-state FileView has not completed yet. Visible fullscreen state is
    // already maintained by NiriService and is the source used by per-output
    // surface gates.
    readonly property bool _reactiveAutoActive: autoDetect && hasVisibleFullscreenWindow
    property bool active: _manualActive || _autoActive || _reactiveAutoActive
    readonly property bool autoDetect: Config.options?.gameMode?.autoDetect ?? true
    property bool manuallyActivated: _manualActive
    readonly property bool autoActivated: !_manualActive
        && (_autoActive || _reactiveAutoActive)

    // Surface mapping caused native crash loops; GameMode only suppresses work.
    
    // When autoDetect is disabled, immediately clear auto state
    onAutoDetectChanged: {
        if (!autoDetect) {
            _autoActive = false
            root._log("[GameMode] autoDetect disabled, clearing auto state")
        } else {
            // Re-check when enabled
            checkFullscreen()
        }
    }
    
    // True if ANY window in ANY workspace is fullscreen (for toast suppression)
    readonly property bool hasAnyFullscreenWindow: checkAnyFullscreenWindow()

    // Niri keeps fullscreen windows in the scrolling layout after they
    // lose focus. Only the *selected* window on each output's active workspace
    // actually covers that output; a fullscreen neighbor must not hide shell
    // chrome while the user is working in another window.
    readonly property bool hasVisibleFullscreenWindow: CompositorService.isNiri
        ? hasFullscreenOnOutput("") : hasAnyFullscreenWindow
    
    // Suppress niri reload toast briefly after GameMode changes
    property bool suppressNiriToast: false

    // Internal state
    property bool _manualActive: false
    property bool _autoActive: false
    property bool _initialized: false
    property bool _focusedIsFullscreen: false

    // Config-driven behavior (reactive bindings - re-evaluated when Config changes)
    readonly property bool disableAnimations: Config.options?.gameMode?.disableAnimations ?? true
    readonly property bool disableEffects: Config.options?.gameMode?.disableEffects ?? true
    readonly property bool disableReloadToasts: Config.options?.gameMode?.disableReloadToasts ?? true
    readonly property bool minimalMode: Config.options?.gameMode?.minimalMode ?? true
    readonly property int checkInterval: {
        const configured = Number(Config.options?.gameMode?.checkInterval ?? 10000)
        return Number.isFinite(configured) ? Math.max(10000, Math.round(configured)) : 10000
    }
    readonly property bool controlNiriAnimations: Config.options?.gameMode?.disableNiriAnimations ?? true
    
    // React to controlNiriAnimations changes while active
    onControlNiriAnimationsChanged: {
        if (active && CompositorService.isNiri) {
            // When setting enabled AND gamemode active -> disable niri animations
            // When setting disabled -> re-enable niri animations
            const shouldEnable = !active || !controlNiriAnimations
            _lastNiriAnimState = shouldEnable
            setNiriAnimations(shouldEnable)
        }
    }

    // External process control (optional)
    readonly property bool disableDiscoverOverlay: Config.options?.gameMode?.disableDiscoverOverlay ?? true
    readonly property bool suppressNotifications: Config.options?.gameMode?.suppressNotifications ?? true
    readonly property string _discoverOverlayServiceName: "discover-overlay.service"

    // State file path
    readonly property string _stateFile: Directories.stateUserPath + "/gamemode_active"
    property bool _stateWriteInFlight: false
    property bool _stateWriteQueued: false

    // IPC handler for external control
    IpcHandler {
        target: "gamemode"
        function toggle(): void { root.toggle() }
        function activate(): void { root.activate() }
        function deactivate(): void { root.deactivate() }
        function status(): string {
            const state = root.active ? "active" : "inactive";
            const detail = root._manualActive ? "manual" : root.autoActivated ? "auto" : "off";
            return state + " (" + detail + ")";
        }
    }

    function toggle() {
        _manualActive = !_manualActive
        _saveState()
        root._log("[GameMode] Toggled manually:", _manualActive)
    }

    function activate() {
        _manualActive = true
        _saveState()
        root._log("[GameMode] Activated manually")
    }

    function deactivate() {
        _manualActive = false
        _saveState()
        root._log("[GameMode] Deactivated manually")
    }

    function _saveState() {
        if (root._stateWriteInFlight) {
            root._stateWriteQueued = true
            return
        }

        root._stateWriteQueued = false
        root._stateWriteInFlight = true
        stateWriter.setText(root._manualActive ? "1\n" : "0\n")
    }

    function _finishStateWrite(): void {
        if (!root._stateWriteInFlight)
            return
        root._stateWriteInFlight = false
        const saveAgain = root._stateWriteQueued
        root._stateWriteQueued = false
        root._log("[GameMode] State saved:", root._manualActive)
        if (saveAgain)
            Qt.callLater(() => root._saveState())
    }

    function _loadState() {
        stateReader.reload()
    }

    // Check if a window is fullscreen.
    // Niri 25.11+ doesn't expose is_fullscreen on windows.
    // We detect fullscreen by comparing window_size to the output's logical
    // resolution (via workspace → output mapping). A small tolerance (2px)
    // accounts for sub-pixel rounding differences.
    function _isWindowFullscreenWithWorkspace(window, workspace, workspaceResolved) {
        if (!window) return false
        if (!CompositorService.isNiri) return false

        // If niri ever adds is_fullscreen back, prefer it
        if (window.is_fullscreen === true) return true

        // Fallback: compare window size to output logical size
        const winSize = window.layout?.window_size
        if (!winSize || winSize.length < 2) return false

        const ws = workspaceResolved
            ? workspace
            : NiriService.workspaces[window.workspace_id]
        let output = ws ? NiriService.outputs[ws.output] : null
        // Niri can deliver WindowLayoutsChanged before the matching workspace
        // snapshot reaches the service. On a single-output session the target
        // is unambiguous, so do not miss that fullscreen transition.
        if (!output) {
            const outputs = NiriService.outputs ?? {}
            let onlyOutput = null
            let outputCount = 0
            for (const key in outputs) {
                if (!Object.prototype.hasOwnProperty.call(outputs, key))
                    continue
                outputCount++
                if (outputCount === 1)
                    onlyOutput = outputs[key]
                else {
                    onlyOutput = null
                    break
                }
            }
            if (outputCount === 1)
                output = onlyOutput
        }
        if (!output?.logical) return false

        const tolerance = 2
        return Math.abs(winSize[0] - output.logical.width) <= tolerance
            && Math.abs(winSize[1] - output.logical.height) <= tolerance
    }

    function isWindowFullscreen(window) {
        return root._isWindowFullscreenWithWorkspace(window, null, false)
    }
    
    // Select the frontmost window in a Niri workspace, not every window
    // whose geometry happens to remain fullscreen in a hidden column.
    // NiriService stores workspace.active_window_id from native events.
    // On cold boot the first active-window event may not have arrived yet:
    // use the focused window, or an unambiguous singleton, as fallback.
    function _selectedWindowForWorkspace(ws, windows) {
        if (!ws || !Array.isArray(windows)) return null
        const matching = windows.filter(w =>
            String(w?.workspace_id) === String(ws.id))
        const activeId = ws.active_window_id
        if (activeId !== undefined && activeId !== null)
            return matching.find(w => String(w.id) === String(activeId)) ?? null
        const focused = matching.find(w => w.is_focused === true)
        return focused ?? (matching.length === 1 ? matching[0] : null)
    }

    // True when the foreground fullscreen window covers this output
    // (empty name = any output). Do not gate per-monitor surfaces on a
    // fullscreen-sized neighbor in an inactive column or workspace.
    function hasFullscreenOnOutput(outputName: string): bool {
        if (!CompositorService.isNiri) return false
        const windows = NiriService.windows
        if (!Array.isArray(windows)) return false
        const workspaces = NiriService.workspaces ?? {}

        for (const ws of Object.values(workspaces)) {
            if (!ws?.is_active) continue
            if (outputName.length > 0 && ws.output !== outputName) continue
            const selected = root._selectedWindowForWorkspace(ws, windows)
            if (selected && root._isWindowFullscreenWithWorkspace(selected, ws, true))
                return true
        }
        return false
    }

    // Check if ANY window across all workspaces is fullscreen
    function checkAnyFullscreenWindow(): bool {
        if (!CompositorService.isNiri) return false
        const windows = NiriService.windows
        if (!windows || !Array.isArray(windows)) return false
        
        for (let i = 0; i < windows.length; i++) {
            if (isWindowFullscreen(windows[i])) return true
        }
        return false
    }

    // Debounce timer for fullscreen checks
    Timer {
        id: checkDebounce
        interval: 300
        onTriggered: root._doCheckFullscreen()
    }

    // Auto-detection: check focused window (debounced)
    function checkFullscreen() {
        checkDebounce.restart()
    }

    function _doCheckFullscreen() {
        if (!CompositorService.isNiri) {
            _autoActive = false
            _focusedIsFullscreen = false
            return
        }

        // Find focused window from the current windows array, not activeWindow.
        // activeWindow is only refreshed on focus-change events, so it's stale
        // when a window changes fullscreen state without changing focus
        // (e.g. pressing F11 on the already-focused window).
        const windows = NiriService.windows
        const focusedWindow = (Array.isArray(windows) && windows.find(w => w.is_focused))
            || NiriService.activeWindow

        // Focus flags can lag behind WindowLayoutsChanged on Niri. The
        // per-output path is already reactive and is what background surfaces
        // use, so keep the focused-window fast path but never miss a fullscreen
        // window that is visible on an active workspace.
        const isFullscreen = isWindowFullscreen(focusedWindow)
            || root.hasVisibleFullscreenWindow
        _focusedIsFullscreen = isFullscreen

        if (!autoDetect) {
            _autoActive = false
            return
        }
        
        // Auto-detect: activate when focused window is fullscreen,
        // deactivate immediately when it's not. Same behavior as manual
        // mode but triggered by fullscreen detection.
        if (isFullscreen !== _autoActive) {
            _autoActive = isFullscreen
            root._log("[GameMode] Auto-detect:", _autoActive ? "fullscreen detected" : "no fullscreen")
        }
    }

    // State persistence - read
    FileView {
        id: stateReader
        path: root._stateFile

        onLoaded: {
            const content = stateReader.text()
            root._manualActive = (content.trim() === "1")
            root._initialized = true
            root._log("[GameMode] Initialized, manual:", root._manualActive)
        }

        onLoadFailed: (error) => {
            // File doesn't exist yet, that's fine
            root._manualActive = false
            root._initialized = true
            root._log("[GameMode] Initialized (no saved state)")
        }
    }

    // State persistence - write in-process. Directories owns stateUserPath
    // creation, so GameMode does not need a per-start mkdir or per-toggle shell.
    FileView {
        id: stateWriter
        path: root._stateFile
        watchChanges: false
        atomicWrites: true

        onSaved: root._finishStateWrite()

        onSaveFailed: error => {
            root._stateWriteInFlight = false
            const retry = root._stateWriteQueued
            root._stateWriteQueued = false
            console.warn("[GameMode] Failed to save state:", error)
            if (retry)
                Qt.callLater(() => root._saveState())
        }
    }

    // React to window changes
    Connections {
        target: NiriService
        enabled: CompositorService.isNiri && root._initialized

        function onActiveWindowChanged() {
            root.checkFullscreen()
        }

        function onWindowsChanged() {
            // A window property changed (incl. is_fullscreen). Trigger full
            // auto-detection — not just hasAnyFullscreenWindow — so we catch
            // the focused window going fullscreen without a focus change.
            root.checkFullscreen()
        }
    }

    // Periodic check as fallback - uses config interval
    Timer {
        id: fallbackTimer
        interval: root.checkInterval
        running: root.autoDetect && CompositorService.isNiri && root._initialized
        repeat: true
        onTriggered: {
            if (!checkDebounce.running) {
                root.checkFullscreen()
            }
        }
    }

    // Initial setup
    Component.onCompleted: {
        root._log("[GameMode] Service starting...")
        initTimer.restart()
    }

    Timer {
        id: initTimer
        interval: 200
        onTriggered: {
            root._loadState()
            if (CompositorService.isNiri) {
                root.checkFullscreen()
                startupNiriSyncTimer.restart()
            }
        }
    }

    Timer {
        id: startupNiriSyncTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (!CompositorService.isNiri || !root.controlNiriAnimations)
                return
            const shouldEnable = !root.active
            root._lastNiriAnimState = shouldEnable
            root.setNiriAnimations(shouldEnable)
        }
    }

    // Niri animations control — targets the modular animations file
    readonly property string niriAnimationsPath: {
        const configDir = (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
        const modularPath = configDir + "/niri/config.d/60-animations.kdl"
        return modularPath
    }
    readonly property string niriConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/niri/config.kdl"

    function setNiriAnimations(enabled) {
        if (!controlNiriAnimations && !enabled) return
        if (niriAnimProcess.running) {
            niriAnimProcess.pendingEnabled = enabled
            niriAnimProcess.rerunAfterExit = true
            return
        }

        niriAnimProcess.pendingEnabled = enabled
        niriAnimProcess.rerunAfterExit = false

        // Try modular file first, fall back to root config.kdl
        const targetFile = niriAnimationsPath
        const fallbackFile = niriConfigPath
        const sedExpr = enabled
            ? "sed -i '/^animations {/,/^}/ s/^\\([ \\t]*\\)off$/\\1\\/\\/off/'"
            : "sed -i '/^animations {/,/^}/ s/^\\([ \\t]*\\)\\/\\/off$/\\1off/'"

        niriAnimProcess.command = [
            "/usr/bin/bash",
            "-c",
            "if [ -f \"" + targetFile + "\" ]; then " + sedExpr + " \"" + targetFile + "\"; " +
            "else " + sedExpr + " \"" + fallbackFile + "\"; fi\n" +
            "/usr/bin/niri msg action reload-config"
        ]
        niriAnimProcess.running = true
    }

    function _finishNiriAnimationMutation(code: int, spawnFailed: bool): void {
        if (spawnFailed)
            root._log("[GameMode] Niri animation update failed to start")
        else if (code === 0)
            root._log("[GameMode] Niri animations updated")

        // Toast suppression is a temporary UI gate, not process ownership.
        // Release it even when the helper cannot be spawned so a failed update
        // cannot mute later compositor reload notifications indefinitely.
        suppressClearTimer.restart()

        if (niriAnimProcess.rerunAfterExit) {
            const pending = niriAnimProcess.pendingEnabled
            niriAnimProcess.rerunAfterExit = false
            Qt.callLater(() => root.setNiriAnimations(pending))
        }
    }

    Process {
        id: niriAnimProcess
        property bool pendingEnabled: true
        property bool rerunAfterExit: false
        property bool startObserved: false
        onRunningChanged: {
            if (niriAnimProcess.running) {
                niriAnimProcess.startObserved = false
                return
            }
            if (niriAnimProcess.startObserved)
                return

            root._finishNiriAnimationMutation(-1, true)
        }
        onStarted: niriAnimProcess.startObserved = true
        onExited: (code, status) => root._finishNiriAnimationMutation(code, false)
    }

    Timer {
        id: suppressClearTimer
        interval: 2000
        onTriggered: {
            root._log("[GameMode] Clearing suppressNiriToast")
            root.suppressNiriToast = false
        }
    }

    // Track last niri animation state to avoid redundant updates
    property bool _lastNiriAnimState: true

    // Debounce timer for niri animation changes
    Timer {
        id: niriAnimDebounce
        interval: 500
        onTriggered: {
            const shouldEnable = !root.active
            if (shouldEnable !== root._lastNiriAnimState) {
                root._lastNiriAnimState = shouldEnable
                root.setNiriAnimations(shouldEnable)
            } else {
                suppressClearTimer.restart()
            }
        }
    }

    onActiveChanged: {
        root._log("[GameMode] Active:", active, "(manual:", _manualActive, "auto:", _autoActive, ")")
        if (CompositorService.isNiri && controlNiriAnimations) {
            root.suppressNiriToast = true
            niriAnimDebounce.restart()
        }

        // External processes control
        if (root.disableDiscoverOverlay) {
            discoverOverlayDebounce.restart()
        }
    }

    // Track the service state we actually changed. GameMode must not kill a
    // manually launched process or start a service that was already inactive.
    property bool _lastDiscoverOverlayGameState: false
    property bool _discoverOverlayWasActive: false

    Timer {
        id: discoverOverlayDebounce
        interval: 800
        repeat: false
        onTriggered: {
            if (!root.disableDiscoverOverlay)
                return

            const shouldStop = root.active
            if (shouldStop === root._lastDiscoverOverlayGameState)
                return
            root._lastDiscoverOverlayGameState = shouldStop

            if (shouldStop) {
                root._log("[GameMode] Stopping managed", root._discoverOverlayServiceName)
                if (!discoverOverlayStopProc.running)
                    discoverOverlayStopProc.running = true
            } else if (root._discoverOverlayWasActive) {
                root._discoverOverlayWasActive = false
                root._log("[GameMode] Restoring", root._discoverOverlayServiceName)
                if (!discoverOverlayStartProc.running)
                    discoverOverlayStartProc.running = true
            }
        }
    }

    Process {
        id: discoverOverlayStopProc
        command: [
            "/usr/bin/bash",
            "-c",
            "if /usr/bin/systemctl --user is-active --quiet " + root._discoverOverlayServiceName + "; then " +
            "/usr/bin/systemctl --user stop " + root._discoverOverlayServiceName + "; else exit 3; fi"
        ]
        onExited: (code, status) => {
            const stoppedManagedService = code === 0
            root._discoverOverlayWasActive = stoppedManagedService
            root._log("[GameMode] managed discover-overlay stop exited:", code)
            // If GameMode ended while systemctl was still stopping the unit,
            // restore it now rather than leaving a previously-active service off.
            if (stoppedManagedService && !root.active) {
                root._discoverOverlayWasActive = false
                if (!discoverOverlayStartProc.running)
                    discoverOverlayStartProc.running = true
            }
        }
    }

    Process {
        id: discoverOverlayStartProc
        command: [
            "/usr/bin/systemctl",
            "--user",
            "start",
            root._discoverOverlayServiceName
        ]
        onExited: (code, status) => {
            root._log("[GameMode] systemctl start exited:", code)
        }
    }
}
