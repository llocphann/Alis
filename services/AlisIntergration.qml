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
    property var pluginCatalog: []
    property var settingsEntries: ({})
    property bool pluginMetadataAvailable: false
    property bool systemProvisionerAvailable: false
    property bool systemHelpersInstalled: false
    property bool gatewayPackageInstalled: false
    property string systemHelpersDiagnostic: "unchecked"
    readonly property var options: Config.options?.integrations?.alisIntergration
    readonly property bool tlpEnabled: available && !loadFailed && Config.ready && options?.tlp === true
    readonly property bool thinkfanEnabled: available && !loadFailed && Config.ready && options?.thinkfan === true
    readonly property bool obsidianEnabled: available && !loadFailed && Config.ready && options?.obsidian === true
    readonly property bool enabled: tlpEnabled || thinkfanEnabled || obsidianEnabled
    readonly property var session: worker.status === Loader.Ready ? worker.item : null

    function pluginEnabled(pluginId): bool {
        return available && !loadFailed && Config.ready && options?.[pluginId] === true
    }
    function setPluginEnabled(pluginId, value): void {
        if (!managerBusy && installedPlugins.some(plugin => plugin.id === pluginId))
            Config.setNestedValue("integrations.alisIntergration." + pluginId, value === true)
    }

    // Explicit user action only. Alis owns transport and the signed-off
    // optional-package lifecycle, not an external installer run by the user.
    function manage(action): void {
        if (managerBusy || probe.running || !["check","install","remove","rollback",
                "helpers-status","helpers-install","helpers-remove","helpers-ensure",
                "gateway-status","gateway-install","gateway-remove"].includes(action))
            return
        managerAction = action
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
        if (["install","remove","rollback","helpers-install","helpers-remove","helpers-ensure"].includes(action)) {
            // Release all disposable workers before switching the immutable package link.
            available = false
            loadFailed = false
        }
        managerProcess.command = ["/usr/bin/python3",
            Quickshell.shellPath("scripts/alis-intergration-manager.py"), action,
            "--shell-root", Quickshell.shellPath("")]
        managerProcess.running = true
        managerDeadline.restart()
    }
    function settingsSource(integration): string {
        if (!available) return ""
        const entry = settingsEntries?.[integration]
        return typeof entry === "string" ? packageRoot + "/" + entry : ""
    }
    function backendSource(kind): string {
        if (!obsidianEnabled) return ""
        if (kind === "managed") return packageRoot + "/services/ObsidianTodoBackend.qml"
        if (kind === "daily") return packageRoot + "/services/DailyNoteTodoBackend.qml"
        return ""
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
            gatewayPackageInstalled,
            integrations:{tlp:tlpEnabled,thinkfan:thinkfanEnabled,obsidian:obsidianEnabled}})
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
                    root.pluginCatalog = Array.isArray(result.catalog) ? result.catalog : []
                    root.settingsEntries = root.available ? result.settings ?? ({}) : ({})
                    root.pluginMetadataAvailable = result.pluginMetadataAvailable === true
                } catch (_error) {
                    root.available=false;root.diagnostic="invalid-package";root.canRollback=false
                    root.installedPlugins=[];root.settingsEntries=({});root.pluginMetadataAvailable=false
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
            let chainHelpersEnsure = false
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
                        if (root.managerAction === "install" && !root.systemHelpersInstalled)
                            chainHelpersEnsure = true
                    }
                }
            } catch (_error) {
                root.managerError = String(managerStderr.text ?? "Could not read Alis-Intergration manager result").slice(0, 256)
            }
            root.authorizationPending = false
            if (root._restoreEmbeddedSettings) {
                root._restoreEmbeddedSettings = false
                GlobalStates.settingsOverlayOpen = true
            }
            if (chainHelpersEnsure) {
                Qt.callLater(() => root.manage("helpers-ensure"))
                return
            }
            if (["install","remove","rollback","helpers-install","helpers-remove",
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
    Component.onCompleted: {
        root.refresh()
        root.refreshSystemStatus()
    }
}
