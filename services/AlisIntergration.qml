pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root
    property bool available: false
    property bool initialProbeDone: false
    property bool loadFailed: false
    property string diagnostic: "not-installed"
    property string packageRoot: ""
    property string packageLayout: ""
    property string pluginsRoot: ""
    property var pluginRoots: ({})
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
    property var viewEntries: ({})
    property var backendEntries: ({})
    property var scriptEntries: ({})
    property bool pluginMetadataAvailable: false
    property bool systemProvisionerAvailable: false
    property bool systemHelpersInstalled: false
    property bool gatewayPackageInstalled: false
    property string systemHelpersDiagnostic: "unchecked"
    property var systemHelpersByPlugin: ({})
    property string managerPluginId: ""
    readonly property bool hardwareHelpersSatisfied: {
        const hwIds = ["tlp", "thinkfan"]
        const installedHw = hwIds.filter(id => root.isPluginInstalled(id))
        if (installedHw.length === 0)
            return root.systemHelpersInstalled
        return installedHw.every(id => root.pluginHelpersReady(id))
    }
    readonly property var options: Config.options?.integrations?.alisIntergration
    readonly property bool tlpEnabled: isPluginInstalled("tlp") && Config.ready && options?.tlp === true
    readonly property bool thinkfanEnabled: isPluginInstalled("thinkfan") && Config.ready && options?.thinkfan === true
    readonly property bool nexusEnabled: isPluginInstalled("nexus") && Config.ready && options?.nexus === true
    readonly property bool spacedRepetitionEnabled: isPluginInstalled("spaced_repetition") && Config.ready && options?.spaced_repetition === true
    readonly property bool alisFilesEnabled: isPluginInstalled("alis_files") && Config.ready && options?.alis_files === true
    property bool _pendingLegacyPrefsSync: false
    property bool _explicitExercisesTrackerEnabled: false
    readonly property string exercisesTrackerPrefsPath: `${Directories.stateUserPath}/exercises-tracker/prefs.json`
    readonly property bool exercisesTrackerAvailable: available && !loadFailed && packageRoot.length > 0
    readonly property bool _exercisesTrackerExplicit: Config.ready && Config.hasPersistedKey("integrations.alisIntergration.exercises_tracker")
    readonly property bool exercisesTrackerEnabled: isPluginInstalled("exercises_tracker") && Config.ready && (
        options?.exercises_tracker === true
        || (!_exercisesTrackerExplicit && (options?.nexus === true || options?.spaced_repetition === true))
    )
    property bool spacedRepetitionDemanded: false
    property bool exercisesTrackerDemanded: false
    function demandSpacedRepetition(): void {
        if (!root.spacedRepetitionDemanded)
            root.spacedRepetitionDemanded = true
        if (root.spacedRepetition && typeof root.spacedRepetition.ensureLoaded === "function")
            root.spacedRepetition.ensureLoaded()
    }
    function demandExercisesTracker(): void {
        if (!root.exercisesTrackerDemanded)
            root.exercisesTrackerDemanded = true
    }
    readonly property bool enabled: tlpEnabled || thinkfanEnabled || nexusEnabled || spacedRepetitionEnabled || exercisesTrackerEnabled || alisFilesEnabled
    readonly property var session: worker.status === Loader.Ready ? worker.item : null
    readonly property var nexus: session?.nexus ?? null
    readonly property var alisFiles: session?.alisFiles ?? null
    readonly property var spacedRepetition: session?.spacedRepetition ?? null
    readonly property var exercisesTracker: session?.exercisesTracker ?? null
    property string _pendingNexusIpcAction: ""
    property string _pendingNexusOpenPath: ""
    property string _pendingAlisFilesIpcAction: ""
    property string _pendingAlisFilesOpenPath: ""

    function _runNexusAction(action: string): void {
        if (!root.nexus)
            return
        if (action === "toggle") root.nexus.toggle()
        else if (action === "open") root.nexus.open()
        else if (action === "openOverlay") root.nexus.openOverlay()
        else if (action === "openWindow") root.nexus.openWindow()
        else if (action === "close") root.nexus.close()
        else if (action === "daily") { root.nexus.open(); root.nexus.openDailyNote() }
        else if (action === "openPath" && root._pendingNexusOpenPath.length > 0) {
            const p = root._pendingNexusOpenPath
            root._pendingNexusOpenPath = ""
            if (typeof root.nexus.openExternalPath === "function")
                root.nexus.openExternalPath(p)
            else if (typeof root.nexus.openNote === "function")
                root.nexus.openNote(p)
            else
                root.nexus.open()
        }
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
                    : "Download & Install the Nexus integration in Settings -> Integrations.",
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
        onTriggered: {
            root._pendingNexusIpcAction = ""
            root._pendingNexusOpenPath = ""
        }
    }

    function _runAlisFilesAction(action: string): void {
        if (!root.alisFiles)
            return
        if (action === "toggle") root.alisFiles.toggle()
        else if (action === "open") root.alisFiles.open()
        else if (action === "openOverlay") root.alisFiles.openOverlay()
        else if (action === "openWindow") root.alisFiles.openWindow()
        else if (action === "close") root.alisFiles.close()
        else if (action === "openPath" && root._pendingAlisFilesOpenPath.length > 0) {
            const p = root._pendingAlisFilesOpenPath
            root._pendingAlisFilesOpenPath = ""
            root.alisFiles.openExternalPath(p)
        }
    }

    function _dispatchAlisFilesIpc(action: string): void {
        if (root.alisFiles) {
            root._pendingAlisFilesIpcAction = ""
            pendingAlisFilesIpcTimer.stop()
            root._runAlisFilesAction(action)
            return
        }
        if (!Config.ready || probe.running || (root.alisFilesEnabled && (!worker.active || worker.status === Loader.Loading))) {
            root._pendingAlisFilesIpcAction = action
            pendingAlisFilesIpcTimer.restart()
            return
        }
        if (action !== "close") {
            Quickshell.execDetached([
                "/usr/bin/notify-send",
                "Alis Files is disabled",
                root.isPluginInstalled("alis_files")
                    ? "Enable Alis Files in Settings -> Integrations to use Overlay mode."
                    : "Install Alis Files in Settings -> Integrations.",
                "-a", "Alis Files",
                "-t", "3500"
            ])
        }
    }

    onAlisFilesChanged: {
        if (root.alisFiles && root._pendingAlisFilesIpcAction.length > 0) {
            const action = root._pendingAlisFilesIpcAction
            root._pendingAlisFilesIpcAction = ""
            pendingAlisFilesIpcTimer.stop()
            root._runAlisFilesAction(action)
        }
    }

    Timer {
        id: pendingAlisFilesIpcTimer
        interval: 6000
        repeat: false
        onTriggered: {
            root._pendingAlisFilesIpcAction = ""
            root._pendingAlisFilesOpenPath = ""
        }
    }

    function isPluginInstalled(pluginId): bool {
        if (!available || loadFailed)
            return false
        if (installedPlugins.some(plugin => plugin.id === pluginId))
            return true
        return installedPluginIds.includes(pluginId)
    }

    function pluginSystemHelpersStatus(pluginId): var {
        const entry = root.systemHelpersByPlugin?.[pluginId]
        if (entry && typeof entry === "object")
            return entry
        const deps = pluginDependencies(pluginId)
        return {
            managed: deps.helpersReady === true,
            installed: deps.helpersReady === true,
            diagnostic: deps.helpersReady === true ? "ready" : "not-installed"
        }
    }

    function pluginHelpersReady(pluginId): bool {
        const deps = pluginDependencies(pluginId)
        if (!deps.requiresSystemHelpers)
            return true
        if (deps.binariesReady !== true)
            return false
        const scoped = root.systemHelpersByPlugin?.[pluginId]
        if (scoped && typeof scoped === "object")
            return scoped.installed === true
        return deps.helpersReady === true || root.systemHelpersInstalled
    }

    function pluginDependencies(pluginId): var {
        const entry = pluginDependenciesMap?.[pluginId]
        if (entry && typeof entry === "object")
            return entry
        const userSpace = pluginId === "nexus" || pluginId === "spaced_repetition" || pluginId === "exercises_tracker" || pluginId === "alis_files"
        const pythonReady = root.runtimeTools?.python3 !== false
        return {
            userSpace: userSpace,
            requiresSystemHelpers: !userSpace,
            helpersScope: userSpace ? "" : pluginId,
            satisfied: userSpace ? pythonReady : false,
            binariesReady: userSpace ? pythonReady : true,
            helpersReady: userSpace,
            provisionerReady: systemProvisionerAvailable,
            packages: userSpace ? ["python3"] : [pluginId, "alis-deps"],
            binaries: userSpace ? [{ name: "python3", installed: pythonReady }] : [],
            helpers: [],
            missing: (userSpace && !pythonReady) ? ["python3"] : [],
            setupCommand: userSpace ? "" : "./setup install-deps",
            helpersCommand: userSpace ? "" : `./setup integrations install ${pluginId}`,
            removeHelpersCommand: userSpace ? "" : `./setup integrations remove ${pluginId}`,
            note: ""
        }
    }
    function pluginEnabled(pluginId): bool {
        if (pluginId === "exercises_tracker")
            return root.exercisesTrackerEnabled
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
        if (Config.ready) {
            if (pluginId === "exercises_tracker")
                setExercisesTrackerEnabled(false)
            else
                Config.setNestedValue("integrations.alisIntergration." + pluginId, false)
        }
        _runManager("remove-plugin", pluginId)
    }

    function manage(action): void {
        if (!["check","install","install-base","install-all","remove","rollback",
                "helpers-status","helpers-install","helpers-remove","helpers-ensure",
                "gateway-status","gateway-install","gateway-remove"].includes(action))
            return
        _runManager(action, "")
    }
    function managePlugin(action, pluginId): void {
        if (!["helpers-status","helpers-install","helpers-remove","helpers-ensure","install-plugin","remove-plugin"].includes(action))
            return
        _runManager(action, pluginId)
    }
    property var _queuedManagerCmd: null
    function _runManager(action, pluginId): void {
        if (managerBusy)
            return
        managerAction = action
        managerPluginId = String(pluginId ?? "")
        managerBusy = true
        authorizationPending = ["helpers-ensure","helpers-install","helpers-remove",
            "gateway-install","gateway-remove"].includes(action)
        _restoreEmbeddedSettings = authorizationPending
            && (Config.options?.panelFamily === "abyss")
            && (GlobalStates.settingsOverlayOpen ?? false)
        if (_restoreEmbeddedSettings)
            GlobalStates.settingsOverlayOpen = false
        managerError = ""
        managerMessage = ""
        if (["install","install-base","remove","rollback","helpers-install","helpers-remove","helpers-ensure"].includes(action)
                || action === "install-all") {
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
        if (probe.running) {
            _queuedManagerCmd = cmd
            managerDeadline.restart()
            return
        }
        _queuedManagerCmd = null
        managerProcess.command = cmd
        managerProcess.running = true
        managerDeadline.restart()
    }

    function resolveEntryPath(relPath: string): string {
        if (typeof relPath !== "string" || relPath.length === 0)
            return ""
        const match = /^plugins\/([a-z][a-z0-9_-]*)\/(.+)$/.exec(relPath)
        if (match) {
            const pluginId = match[1]
            const sub = match[2]
            const perRoot = String(root.pluginRoots?.[pluginId] ?? "").trim()
            if (perRoot.length > 0)
                return perRoot.replace(/\/+$/, "") + "/" + sub
            if (root.packageLayout === "split-v2" && root.packageRoot.length > 0)
                return root.packageRoot + "/" + relPath
            return ""
        }
        return root.packageRoot.length > 0 ? (root.packageRoot + "/" + relPath) : ""
    }

    function settingsSource(integration): string {
        if (!available) return ""
        const entry = settingsEntries?.[integration]
        return typeof entry === "string" ? resolveEntryPath(entry) : ""
    }
    function spacedRepetitionDashboardSource(): string {
        if (!spacedRepetitionEnabled || !available) return ""
        const explicit = viewEntries?.spacedRepetitionDashboard
        if (typeof explicit === "string" && explicit.length > 0)
            return resolveEntryPath(explicit)
        if (packageLayout === "legacy-v1")
            return packageRoot.length > 0 ? (packageRoot + "/modules/dashboard/DashboardSpacedRepetition.qml") : ""
        return resolveEntryPath("plugins/spaced_repetition/modules/dashboard/DashboardSpacedRepetition.qml")
    }
    function spacedRepetitionLookupScriptPath(): string {
        if (!available || !isPluginInstalled("spaced_repetition")) return ""
        const explicit = scriptEntries?.spacedRepetitionLookup
        if (typeof explicit === "string" && explicit.length > 0)
            return resolveEntryPath(explicit)
        if (packageLayout === "legacy-v1")
            return packageRoot.length > 0 ? (packageRoot + "/scripts/integrations/lookup_word_level.py") : ""
        return resolveEntryPath("plugins/spaced_repetition/scripts/integrations/lookup_word_level.py")
    }
    function exercisesTrackerDashboardSource(): string {
        if (!exercisesTrackerEnabled || !available) return ""
        const explicit = viewEntries?.exercisesTrackerDashboard
        if (typeof explicit === "string" && explicit.length > 0)
            return resolveEntryPath(explicit)
        if (packageLayout === "legacy-v1")
            return packageRoot.length > 0 ? (packageRoot + "/modules/dashboard/DashboardExercisesTracker.qml") : ""
        return resolveEntryPath("plugins/exercises_tracker/modules/dashboard/DashboardExercisesTracker.qml")
    }
    function exercisesTrackerHelperPath(): string {
        if (!available || !isPluginInstalled("exercises_tracker")) return ""
        const explicit = scriptEntries?.exercisesTrackerHelper
        if (typeof explicit === "string" && explicit.length > 0)
            return resolveEntryPath(explicit)
        if (packageLayout === "legacy-v1")
            return packageRoot.length > 0 ? (packageRoot + "/scripts/integrations/exercises_tracker.py") : ""
        return resolveEntryPath("plugins/exercises_tracker/scripts/integrations/exercises_tracker.py")
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
        if (!nexusEnabled || !available) return ""
        if (kind === "managed") {
            const explicit = backendEntries?.managedTodo
            if (typeof explicit === "string" && explicit.length > 0)
                return resolveEntryPath(explicit)
            return packageLayout === "legacy-v1"
                ? (packageRoot + "/services/NexusTodoBackend.qml")
                : resolveEntryPath("plugins/nexus/services/NexusTodoBackend.qml")
        }
        if (kind === "daily") {
            const explicit = backendEntries?.dailyTodo
            if (typeof explicit === "string" && explicit.length > 0)
                return resolveEntryPath(explicit)
            return packageLayout === "legacy-v1"
                ? (packageRoot + "/services/DailyNoteTodoBackend.qml")
                : resolveEntryPath("plugins/nexus/services/DailyNoteTodoBackend.qml")
        }
        return ""
    }
    function nexusWorkspaceSource(): string {
        if (!nexusEnabled || !available) return ""
        const explicit = viewEntries?.nexusWorkspace
        if (typeof explicit === "string" && explicit.length > 0)
            return resolveEntryPath(explicit)
        if (packageLayout === "legacy-v1")
            return packageRoot.length > 0 ? (packageRoot + "/modules/nexus/NexusWorkspace.qml") : ""
        return resolveEntryPath("plugins/nexus/modules/nexus/NexusWorkspace.qml")
    }
    function alisFilesWorkspaceSource(): string {
        if (!alisFilesEnabled || !available) return ""
        const explicit = viewEntries?.alisFilesWorkspace
        if (typeof explicit === "string" && explicit.length > 0)
            return resolveEntryPath(explicit)
        return resolveEntryPath("plugins/alis_files/modules/files/AlisFilesOverlayWorkspace.qml")
    }
    function clearFeedback(): void {
        managerError = ""
        managerMessage = ""
    }
    function refresh(): void {
        if (probe.running || managerBusy) return
        loadFailed = false
        probe.running = true
        if (root.systemStatusLoaded)
            Qt.callLater(root.refreshSystemStatus)
    }
    property bool systemStatusLoaded: false
    function refreshSystemStatus(): void {
        if (systemStatusProbe.running || managerBusy) return
        systemStatusProbe.running = true
    }
    function ensureSystemStatusLoaded(): void {
        if (root.systemStatusLoaded || systemStatusProbe.running || managerBusy) return
        root.refreshSystemStatus()
    }
    function status(): string {
        return JSON.stringify({available, enabled, diagnostic, version, sourceSha, packageLayout,
            managerBusy, authorizationPending, managerError, updateAvailable, canRollback,
            systemProvisionerAvailable, systemHelpersInstalled, systemHelpersDiagnostic,
            systemHelpersByPlugin, gatewayPackageInstalled, installedPluginIds,
            alisFilesReady: root.alisFiles !== null, nexusReady: root.nexus !== null,
            integrations:{tlp:tlpEnabled,thinkfan:thinkfanEnabled,nexus:nexusEnabled,spaced_repetition:spacedRepetitionEnabled,exercises_tracker:exercisesTrackerEnabled,alis_files:alisFilesEnabled}})
    }
    Loader {
        id: worker
        active: root.enabled && root.available && root.packageRoot.length > 0
        asynchronous: status !== Loader.Ready
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
                if (root.managerBusy) {
                    root.initialProbeDone = true
                    return
                }
                try {
                    const result = JSON.parse(text)
                    root.packageRoot = String(result.root ?? "")
                    root.packageLayout = String(result.layout ?? "")
                    root.pluginsRoot = String(result.pluginsDir ?? "")
                    root.pluginRoots = result.pluginRoots && typeof result.pluginRoots === "object"
                        ? result.pluginRoots : ({})
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
                    root.viewEntries = root.available ? result.views ?? ({}) : ({})
                    root.backendEntries = root.available ? result.backends ?? ({}) : ({})
                    root.scriptEntries = root.available ? result.scripts ?? ({}) : ({})
                    root.pluginMetadataAvailable = result.pluginMetadataAvailable === true
                } catch (_error) {
                    root.available = false; root.diagnostic = "invalid-package"; root.canRollback = false
                    root.packageLayout = ""; root.pluginsRoot = ""; root.pluginRoots = ({})
                    root.installedPlugins = []; root.installedPluginIds = []
                    root.settingsEntries = ({}); root.viewEntries = ({}); root.backendEntries = ({}); root.scriptEntries = ({})
                    root.pluginMetadataAvailable = false
                } finally {
                    root.initialProbeDone = true
                }
            }
        }
        onExited: {
            if (!root.initialProbeDone) {
                Qt.callLater(() => {
                    if (!probe.running && !root.initialProbeDone)
                        root.initialProbeDone = true
                })
            }
            if (root._queuedManagerCmd && !managerProcess.running) {
                Qt.callLater(() => {
                    if (!probe.running && root._queuedManagerCmd && !managerProcess.running) {
                        const cmd = root._queuedManagerCmd
                        root._queuedManagerCmd = null
                        managerProcess.command = cmd
                        managerProcess.running = true
                    }
                })
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
            if (root.managerBusy) return
            try {
                const report = JSON.parse(String(systemStatusOutput.text ?? "").trim())
                if (exitCode !== 0 || report.ok !== true) return
                root.systemProvisionerAvailable = report.systemProvisionerAvailable === true
                root.systemHelpersInstalled = report.systemHelpersInstalled === true
                root.gatewayPackageInstalled = report.gatewayPackageInstalled === true
                root.systemHelpersDiagnostic = String(report.systemHelpersDiagnostic ?? "unchecked")
                root.systemHelpersByPlugin = report.systemHelpersByPlugin && typeof report.systemHelpersByPlugin === "object"
                    ? report.systemHelpersByPlugin : ({})
                root.systemStatusLoaded = true
            } catch (_error) {
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
                        if (result.systemHelpersByPlugin && typeof result.systemHelpersByPlugin === "object")
                            root.systemHelpersByPlugin = result.systemHelpersByPlugin
                        if (root.managerAction === "helpers-ensure")
                            root.gatewayPackageInstalled = result.gatewayPackageInstalled === true
                        root.systemHelpersDiagnostic = String(result.systemHelpersDiagnostic ?? "unknown")
                    } else {
                        root.updateAvailable = false
                        root.canRollback = result.canRollback === true
                        if (Array.isArray(result.installedPluginIds)) {
                            root.installedPluginIds = result.installedPluginIds
                            root.installedPlugins = root.installedPlugins.filter(p => result.installedPluginIds.includes(p.id))
                        }
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
            if (["install","install-base","install-all","remove","rollback","install-plugin","remove-plugin","helpers-install","helpers-remove",
                "helpers-ensure","gateway-install","gateway-remove"].includes(root.managerAction)) {
                Qt.callLater(root.refresh)
                if (exitCode === 0 && Config.isSettingsProcess) {
                    const shellRoot = Quickshell.shellPath("").replace(/\/+$/, "")
                    if (shellRoot.length > 0)
                        Quickshell.execDetached(["/usr/bin/qs", "-p", shellRoot, "ipc", "call", "integrations", "refresh"])
                }
            }
            Qt.callLater(root.refreshSystemStatus)
        }
    }
    Timer {
        id: managerDeadline
        interval: 390000
        repeat: false
        onTriggered: {
            root._queuedManagerCmd = null
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
        function openPath(absPath: string): void {
            const cleaned = String(absPath ?? "").trim()
            if (cleaned.length === 0) return
            if (root.nexus && typeof root.nexus.openExternalPath === "function") {
                root.nexus.openExternalPath(cleaned)
                return
            }
            if (root.nexus && typeof root.nexus.openNote === "function") {
                root.nexus.openNote(cleaned)
                return
            }
            root._pendingNexusOpenPath = cleaned
            root._dispatchNexusIpc("openPath")
        }
    }
    IpcHandler {
        target: "alis-files"
        function toggle(): void { root._dispatchAlisFilesIpc("toggle") }
        function open(): void { root._dispatchAlisFilesIpc("open") }
        function openOverlay(): void { root._dispatchAlisFilesIpc("openOverlay") }
        function openWindow(): void { root._dispatchAlisFilesIpc("openWindow") }
        function close(): void { root._dispatchAlisFilesIpc("close") }
        function openPath(absPath: string): void {
            const cleaned = String(absPath ?? "").trim()
            if (cleaned.length === 0) return
            if (root.alisFiles) {
                root.alisFiles.openExternalPath(cleaned)
                return
            }
            root._pendingAlisFilesOpenPath = cleaned
            root._dispatchAlisFilesIpc("openPath")
        }
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
    }
}
