pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root
    property bool available: false
    property bool loadFailed: false
    property string diagnostic: "not-installed"
    property string packageRoot: ""
    property string version: ""
    property string sourceSha: ""
    property bool canRollback: false
    property bool managerBusy: false
    // Force Settings below external or shell Polkit while auth is pending.
    property bool authorizationPending: false
    property bool _restoreEmbeddedSettings: false
    property string managerAction: ""
    property string managerError: ""
    property string managerMessage: ""
    property string latestSha: ""
    property bool updateAvailable: false
    property var installedPlugins: []
    property var installedPluginIds: []
    property var pluginCatalog: []
    property var pluginDependenciesMap: ({})
    property var runtimeTools: ({})
    property var settingsEntries: ({})
    property bool pluginMetadataAvailable: false
    property bool systemProvisionerAvailable: false
    property bool systemHelpersInstalled: false
    property bool gatewayPackageInstalled: false
    property string systemHelpersDiagnostic: "unchecked"
    property string managerPluginId: ""
    readonly property bool hardwareHelpersSatisfied: {
        if (root.systemHelpersInstalled)
            return true
        const hwIds = ["tlp", "thinkfan"]
        const installedHw = hwIds.filter(id => root.isPluginInstalled(id))
        const checkIds = installedHw.length > 0 ? installedHw : hwIds
        return checkIds.every(id => root.pluginDependencies(id).satisfied === true)
    }
    readonly property var options: Config.options?.integrations?.alisIntergration
    readonly property bool tlpEnabled: isPluginInstalled("tlp") && Config.ready && options?.tlp === true
    readonly property bool thinkfanEnabled: isPluginInstalled("thinkfan") && Config.ready && options?.thinkfan === true
    readonly property bool nexusEnabled: isPluginInstalled("nexus") && Config.ready && options?.nexus === true
    readonly property bool spacedRepetitionEnabled: isPluginInstalled("spaced_repetition") && Config.ready && options?.spaced_repetition === true
    property bool _pendingLegacyPrefsSync: false
    property bool _explicitExercisesTrackerEnabled: false
    readonly property string exercisesTrackerPrefsPath: `${Directories.stateUserPath}/exercises-tracker/prefs.json`
    readonly property bool exercisesTrackerAvailable: available && !loadFailed && packageRoot.length > 0
    readonly property bool exercisesTrackerEnabled: isPluginInstalled("exercises_tracker") && Config.ready && options?.exercises_tracker === true
    readonly property bool enabled: tlpEnabled || thinkfanEnabled || nexusEnabled || spacedRepetitionEnabled || exercisesTrackerEnabled
    readonly property var session: worker.status === Loader.Ready ? worker.item : null
    readonly property var nexus: session?.nexus ?? null
    readonly property var spacedRepetition: session?.spacedRepetition ?? null
    readonly property var exercisesTracker: session?.exercisesTracker ?? null
    property string _pendingNexusIpcAction: ""

    function _runNexusAction(action: string): void {
        if (!root.nexus)
            return
        if (action === "toggle") root.nexus.toggle()
        else if (action === "open") root.nexus.open()
        else if (action === "openOverlay") root.nexus.openOverlay()
        else if (action === "openWindow") root.nexus.openWindow()
        else if (action === "close") root.nexus.close()
        else if (action === "daily") { root.nexus.open(); root.nexus.openDailyNote() }
    }

    function _dispatchNexusIpc(action: string): void {
        if (root.nexus) {
            root._pendingNexusIpcAction = ""
            pendingNexusIpcTimer.stop()
            root._runNexusAction(action)
            return
        }
        if (!Config.ready || probe.running || (root.nexusEnabled && (!worker.active || worker.status === Loader.Loading))) {
            root._pendingNexusIpcAction = action
            pendingNexusIpcTimer.restart()
            return
        }
        if (action !== "close") {
            Quickshell.execDetached([
                "/usr/bin/notify-send",
                "Nexus is disabled",
                root.isPluginInstalled("nexus")
                    ? "Enable Nexus in Settings -> Integrations to open it."
                    : "Install the Nexus integration in Settings -> Integrations.",
                "-a", "Alis Nexus",
                "-t", "3500"
            ])
        }
    }

    onNexusChanged: {
        if (root.nexus && root._pendingNexusIpcAction.length > 0) {
            const action = root._pendingNexusIpcAction
            root._pendingNexusIpcAction = ""
            pendingNexusIpcTimer.stop()
            root._runNexusAction(action)
        }
    }

    Timer {
        id: pendingNexusIpcTimer
        interval: 6000
        repeat: false
        onTriggered: root._pendingNexusIpcAction = ""
    }

    function isPluginInstalled(pluginId): bool {
        if (!available || loadFailed)
            return false
        if (installedPlugins.some(plugin => plugin.id === pluginId))
            return true
        return !pluginMetadataAvailable && installedPluginIds.includes(pluginId)
    }
    function pluginDependencies(pluginId): var {
        const entry = pluginDependenciesMap?.[pluginId]
        if (entry && typeof entry === "object")
            return entry
        const userSpace = pluginId === "nexus" || pluginId === "spaced_repetition" || pluginId === "exercises_tracker"
        return {
            userSpace: userSpace,
            requiresSystemHelpers: !userSpace,
            satisfied: userSpace,
            binariesReady: true,
            helpersReady: userSpace,
            provisionerReady: systemProvisionerAvailable,
            packages: userSpace ? (pluginId === "spaced_repetition" ? [] : ["python3"]) : [pluginId, "alis-deps"],
            binaries: [],
            helpers: [],
            missing: [],
            setupCommand: userSpace ? "" : "./setup install-deps",
            helpersCommand: userSpace ? "" : "./setup integrations",
            note: ""
        }
    }
    function pluginEnabled(pluginId): bool {
        return isPluginInstalled(pluginId) && Config.ready && options?.[pluginId] === true
    }
    function setPluginEnabled(pluginId, value): void {
        if (!managerBusy && isPluginInstalled(pluginId)) {
            if (pluginId === "exercises_tracker") {
                setExercisesTrackerEnabled(value)
                return
            }
            Config.setNestedValue("integrations.alisIntergration." + pluginId, value === true)
        }
    }
    function installPlugin(pluginId): void {
        if (typeof pluginId !== "string" || pluginId.length === 0)
            return
        _runManager("install-plugin", pluginId)
    }
    function removePlugin(pluginId): void {
        if (typeof pluginId !== "string" || pluginId.length === 0)
            return
        _runManager("remove-plugin", pluginId)
    }

    // Explicit user action only. Alis owns transport and the signed-off
    // optional-package lifecycle, not an external installer run by the user.
    function manage(action): void {
        if (!["check","install","install-all","remove","rollback",
                "helpers-status","helpers-install","helpers-remove","helpers-ensure",
                "gateway-status","gateway-install","gateway-remove"].includes(action))
            return
        _runManager(action, "")
    }
    function _runManager(action, pluginId): void {
        if (managerBusy || probe.running)
            return
        managerAction = action
        managerPluginId = String(pluginId ?? "")
        managerBusy = true
        authorizationPending = ["helpers-ensure","helpers-install","helpers-remove",
            "gateway-install","gateway-remove"].includes(action)
        // Abyss embeds Settings in another layer-shell surface. Hiding only
        // the native Settings window cannot lower that parent; temporarily
        // release the embedded surface so pkexec always remains visible.
        _restoreEmbeddedSettings = authorizationPending
            && (Config.options?.panelFamily === "abyss")
            && (GlobalStates.settingsOverlayOpen ?? false)
        if (_restoreEmbeddedSettings)
            GlobalStates.settingsOverlayOpen = false
        managerError = ""
        managerMessage = ""
        if (["install","remove","rollback","helpers-install","helpers-remove","helpers-ensure"].includes(action)
                || action === "install-all") {
            // Release all disposable workers before switching the immutable package link.
            available = false
            loadFailed = false
        }
        const cmd = ["/usr/bin/python3",
            Quickshell.shellPath("scripts/alis-intergration-manager.py"), action,
            "--shell-root", Quickshell.shellPath("")]
        if (managerPluginId.length > 0) {
            cmd.push("--plugin")
            cmd.push(managerPluginId)
        }
        managerProcess.command = cmd
        managerProcess.running = true
        managerDeadline.restart()
    }
    function settingsSource(integration): string {
        if (!available) return ""
        const entry = settingsEntries?.[integration]
        return typeof entry === "string" ? packageRoot + "/" + entry : ""
    }
    function spacedRepetitionDashboardSource(): string {
        if (!spacedRepetitionEnabled || packageRoot.length === 0) return ""
        return packageRoot + "/modules/dashboard/DashboardSpacedRepetition.qml"
    }
    function spacedRepetitionLookupScriptPath(): string {
        if (!available || packageRoot.length === 0) return ""
        return packageRoot + "/scripts/integrations/lookup_word_level.py"
    }
    function exercisesTrackerDashboardSource(): string {
        if (!exercisesTrackerEnabled || packageRoot.length === 0) return ""
        return packageRoot + "/modules/dashboard/DashboardExercisesTracker.qml"
    }
    function exercisesTrackerHelperPath(): string {
        if (!available || packageRoot.length === 0) return ""
        return packageRoot + "/scripts/integrations/exercises_tracker.py"
    }
    function _writeExercisesPrefs(enabledValue): void {
        exercisesPrefsDirProc.pendingPayload = JSON.stringify({
            schemaVersion: 2,
            enabled: enabledValue === true,
            migratedToConfig: true
        }, null, 2) + "\n"
        const dirPath = `${Directories.stateUserPath}/exercises-tracker`
        if (!exercisesPrefsDirProc.running) {
            exercisesPrefsDirProc.command = ["/usr/bin/mkdir", "-p", dirPath]
            exercisesPrefsDirProc.running = true
        }
    }
    function _syncLegacyExercisesPrefs(): void {
        if (!root._pendingLegacyPrefsSync || !Config.ready)
            return
        root._pendingLegacyPrefsSync = false
        Config.setNestedValue("integrations.alisIntergration.exercises_tracker", root._explicitExercisesTrackerEnabled)
        root._writeExercisesPrefs(root._explicitExercisesTrackerEnabled)
    }
    function setExercisesTrackerEnabled(value): void {
        if (managerBusy)
            return
        const nextVal = value === true
        root._pendingLegacyPrefsSync = false
        root._explicitExercisesTrackerEnabled = nextVal
        Config.setNestedValue("integrations.alisIntergration.exercises_tracker", nextVal)
        if (nextVal && (Config.options?.dashboard?.exercisesTracker?.enable ?? true) === false)
            Config.setNestedValue("dashboard.exercisesTracker.enable", true)
        root._writeExercisesPrefs(nextVal)
    }
    function backendSource(kind): string {
        if (!nexusEnabled) return ""
        if (kind === "managed") return packageRoot + "/services/NexusTodoBackend.qml"
        if (kind === "daily") return packageRoot + "/services/DailyNoteTodoBackend.qml"
        return ""
    }
    function nexusWorkspaceSource(): string {
        if (!nexusEnabled || packageRoot.length === 0) return ""
        return packageRoot + "/modules/nexus/NexusWorkspace.qml"
    }
    function clearFeedback(): void {
        managerError = ""
        managerMessage = ""
    }
    function refresh(): void {
        if (probe.running || managerBusy) return
        available = false
        loadFailed = false
        probe.running = true
        refreshSystemStatus()
    }
    // Always reconcile installed helper and gateway state from the local
    // system. No network, system writes, authentication or auto-install.
    function refreshSystemStatus(): void {
        if (systemStatusProbe.running || managerBusy) return
        systemStatusProbe.running = true
    }
    function status(): string {
        return JSON.stringify({available, enabled, diagnostic, version, sourceSha,
            managerBusy, authorizationPending, managerError, updateAvailable, canRollback,
            systemProvisionerAvailable, systemHelpersInstalled, systemHelpersDiagnostic,
            gatewayPackageInstalled, installedPluginIds,
            integrations:{tlp:tlpEnabled,thinkfan:thinkfanEnabled,nexus:nexusEnabled,spaced_repetition:spacedRepetitionEnabled,exercises_tracker:exercisesTrackerEnabled}})
    }
    Loader {
        id: worker
        active: root.enabled
        onActiveChanged: {
            if (active) setSource(root.packageRoot + "/AlisSession.qml", {host:root})
            else source = ""
        }
        onStatusChanged: if (status === Loader.Error) {
            root.loadFailed = true
            root.diagnostic = "load-failed"
        }
    }
    Process {
        id: probe
        command: ["/usr/bin/python3",Quickshell.shellPath("scripts/alis-intergration-status.py"),Quickshell.shellPath("")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.packageRoot = String(result.root ?? "")
                    root.version = String(result.version ?? "")
                    root.sourceSha = String(result.sourceSha ?? "")
                    root.diagnostic = String(result.diagnostic ?? "invalid-package")
                    root.available = result.available === true
                    root.canRollback = result.canRollback === true
                    root.installedPlugins = root.available && Array.isArray(result.plugins) ? result.plugins : []
                    root.installedPluginIds = root.available && Array.isArray(result.installedPluginIds)
                        ? result.installedPluginIds : root.installedPlugins.map(plugin => plugin.id)
                    root.pluginCatalog = Array.isArray(result.catalog) ? result.catalog : []
                    root.pluginDependenciesMap = result.dependencies && typeof result.dependencies === "object"
                        ? result.dependencies : ({})
                    root.runtimeTools = result.runtimeTools && typeof result.runtimeTools === "object"
                        ? result.runtimeTools : ({})
                    root.settingsEntries = root.available ? result.settings ?? ({}) : ({})
                    root.pluginMetadataAvailable = result.pluginMetadataAvailable === true
                } catch (_error) {
                    root.available=false;root.diagnostic="invalid-package";root.canRollback=false
                    root.installedPlugins=[];root.installedPluginIds=[];root.settingsEntries=({});root.pluginMetadataAvailable=false
                }
            }
        }
    }
    Process {
        id: systemStatusProbe
        command: ["/usr/bin/python3",
            Quickshell.shellPath("scripts/alis-intergration-manager.py"), "system-status",
            "--shell-root", Quickshell.shellPath("")]
        stdout: StdioCollector { id: systemStatusOutput }
        onExited: (exitCode) => {
            // Ignore a stale read while an explicit user action is underway.
            if (root.managerBusy) return
            try {
                const report = JSON.parse(String(systemStatusOutput.text ?? "").trim())
                if (exitCode !== 0 || report.ok !== true) return
                root.systemProvisionerAvailable = report.systemProvisionerAvailable === true
                root.systemHelpersInstalled = report.systemHelpersInstalled === true
                root.gatewayPackageInstalled = report.gatewayPackageInstalled === true
                root.systemHelpersDiagnostic = String(report.systemHelpersDiagnostic ?? "unchecked")
            } catch (_error) {
                // Retain last known status; an invalid receipt is not "absent".
            }
        }
    }
    Process {
        id: managerProcess
        stdout: StdioCollector { id: managerOutput }
        stderr: StdioCollector { id: managerStderr }
        onExited: (exitCode) => {
            managerDeadline.stop()
            root.managerBusy = false
            try {
                const result = JSON.parse(String(managerOutput.text ?? "").trim())
                if (exitCode !== 0 || result.ok !== true) {
                    root.managerError = String(result.error ?? "Alis-Intergration operation failed")
                } else {
                    root.managerMessage = String(result.message ?? (
                        root.managerAction === "check"
                            ? (result.updateAvailable ? "An update is available" : "Already up to date")
                            : "Operation completed"))
                    if (root.managerAction === "check") {
                        root.latestSha = String(result.latestSha ?? "")
                        root.updateAvailable = result.updateAvailable === true
                    } else if (root.managerAction.startsWith("gateway-")) {
                        root.gatewayPackageInstalled = result.gatewayPackageInstalled === true
                        root.systemProvisionerAvailable = result.systemProvisionerAvailable === true
                        root.systemHelpersDiagnostic = String(result.systemHelpersDiagnostic ?? "unchecked")
                    } else if (root.managerAction.startsWith("helpers-")) {
                        root.systemHelpersInstalled = result.systemHelpersInstalled === true
                        root.systemProvisionerAvailable = result.systemProvisionerAvailable === true
                        if (root.managerAction === "helpers-ensure")
                            root.gatewayPackageInstalled = result.gatewayPackageInstalled === true
                        root.systemHelpersDiagnostic = String(result.systemHelpersDiagnostic ?? "unknown")
                    } else {
                        root.updateAvailable = false
                        root.canRollback = result.canRollback === true
                        if (Array.isArray(result.installedPluginIds))
                            root.installedPluginIds = result.installedPluginIds
                    }
                }
            } catch (_error) {
                root.managerError = String(managerStderr.text ?? "Could not read Alis-Intergration manager result").slice(0, 256)
            }
            root.authorizationPending = false
            root.managerPluginId = ""
            if (root._restoreEmbeddedSettings) {
                root._restoreEmbeddedSettings = false
                GlobalStates.settingsOverlayOpen = true
            }
            if (["install","install-all","remove","rollback","install-plugin","remove-plugin","helpers-install","helpers-remove",
                "helpers-ensure","gateway-install","gateway-remove"].includes(root.managerAction))
                Qt.callLater(root.refresh)
            // An unsuccessful or cancelled Polkit operation may have changed
            // just one stage. Re-read reality rather than assume success/fail.
            Qt.callLater(root.refreshSystemStatus)
        }
    }
    Timer {
        id: managerDeadline
        // Chained gateway build/auth (<=260s) plus helper auth (<=80s)
        // needs a deadline longer than the sum; otherwise the UI can claim
        // failure while a privileged child transaction is still completing.
        interval: 390000
        repeat: false
        onTriggered: {
            managerProcess.running = false
            root.managerBusy = false
            root.managerError = "Alis-Intergration package operation timed out"
            root.authorizationPending = false
            if (root._restoreEmbeddedSettings) {
                root._restoreEmbeddedSettings = false
                GlobalStates.settingsOverlayOpen = true
            }
            root.refresh()
            Qt.callLater(root.refreshSystemStatus)
        }
    }
    IpcHandler {
        target: "integrations"
        function refresh(): void {root.refresh()}
        function status(): string {return root.status()}
    }
    // API 1 compatibility: both targets address this single owner.
    IpcHandler {
        target: "alis-intergration"
        function refresh(): void {root.refresh()}
        function status(): string {return root.status()}
    }
    IpcHandler {
        target: "nexus"
        function toggle(): void { root._dispatchNexusIpc("toggle") }
        function open(): void { root._dispatchNexusIpc("open") }
        function openOverlay(): void { root._dispatchNexusIpc("openOverlay") }
        function openWindow(): void { root._dispatchNexusIpc("openWindow") }
        function close(): void { root._dispatchNexusIpc("close") }
        function daily(): void { root._dispatchNexusIpc("daily") }
    }
    IpcHandler {
        target: "exercises-tracker"
        function open(): void { if (root.exercisesTracker) root.exercisesTracker.openDashboardTracker("") }
    }
    Connections {
        target: Config
        function onReadyChanged(): void {
            if (Config.ready)
                root._syncLegacyExercisesPrefs()
        }
    }
    FileView {
        id: exercisesPrefsFileView
        path: "file://" + root.exercisesTrackerPrefsPath
        preload: true
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const doc = JSON.parse(exercisesPrefsFileView.text() || "")
                if (doc && typeof doc.enabled === "boolean") {
                    root._explicitExercisesTrackerEnabled = doc.enabled
                    if (doc.migratedToConfig !== true) {
                        root._pendingLegacyPrefsSync = true
                        root._syncLegacyExercisesPrefs()
                    }
                }
            } catch (_e) {}
        }
        onLoadFailed: {}
    }
    Process {
        id: exercisesPrefsDirProc
        property string pendingPayload: ""
        running: false
        onExited: {
            if (exercisesPrefsDirProc.pendingPayload.length > 0) {
                const payload = exercisesPrefsDirProc.pendingPayload
                exercisesPrefsDirProc.pendingPayload = ""
                exercisesPrefsFileView.setText(payload)
            }
        }
    }
    Component.onCompleted: {
        root.refresh()
        root.refreshSystemStatus()
    }
}
