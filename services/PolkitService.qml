pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * PolkitService - Wrapper that gracefully handles missing Quickshell.Services.Polkit module
 * 
 * The Polkit module is optional in Quickshell and may not be compiled in all builds.
 * This wrapper provides a stub interface when the module is unavailable, preventing
 * the entire shell from failing to load.
 */
Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    // Public API - matches PolkitServiceImpl
    property var agent: impl?.agent ?? null
    property bool active: impl?.active ?? false
    property var flow: impl?.flow ?? null
    property bool interactionAvailable: impl?.interactionAvailable ?? false

    readonly property string rawMessage: String(flow?.message ?? "").trim()
    readonly property bool batteryChargeLimitRequest: rawMessage.includes("battery-charge-limit")
    readonly property string cleanMessage: {
        if (batteryChargeLimitRequest)
            return Translation.tr("Do you want to allow this app to make changes to your device?")
        return rawMessage.endsWith(".") ? rawMessage.slice(0, -1) : rawMessage
    }
    readonly property string cleanPrompt: {
        const prompt = String(flow?.inputPrompt ?? "").trim()
        const cleaned = prompt.endsWith(":") ? prompt.slice(0, -1) : prompt
        if (cleaned.length > 0)
            return cleaned
        return flow?.responseVisible
            ? Translation.tr("Input")
            : Translation.tr("Password")
    }
    readonly property string actionLabel: batteryChargeLimitRequest
        ? Translation.tr("Charge limit")
        : Translation.tr("Authentication")
    
    // Whether the Polkit module is available
    readonly property bool available: impl !== null
    
    function cancel(): void {
        if (impl) impl.cancel()
    }
    
    function submit(text: string): void {
        if (impl) impl.submit(text)
    }
    
    // Private: actual implementation loaded dynamically
    property var impl: null

    function _loadImpl(): void {
        // Try to load the real implementation
        const component = Qt.createComponent("PolkitServiceImpl.qml", Component.Asynchronous)

        function finishCreation() {
            if (component.status === Component.Ready) {
                root.impl = component.createObject(root)
                _log("[PolkitService] Polkit module loaded successfully")
            } else if (component.status === Component.Error) {
                _log("[PolkitService] Polkit module not available - polkit agent disabled")
                _log("[PolkitService] To enable, rebuild quickshell with -DSERVICE_POLKIT=ON")
            }
        }

        if (component.status === Component.Ready || component.status === Component.Error) {
            finishCreation()
        } else {
            component.statusChanged.connect(finishCreation)
        }
    }
    
    Component.onCompleted: {
        if (Quickshell.env("QS_DISABLE_POLKIT") === "1") {
            return
        }
        if (!(Config.options?.modules?.polkit ?? true)) {
            return
        }

        // If another authentication agent already exists, registering will fail and spam warnings.
        // Best-effort detection: if we can see a known agent process, skip our agent.
        polkitAgentCheck.running = true
    }

    Process {
        id: polkitAgentCheck
        running: false
        property bool startObserved: false

        // Note: pidof returns 0 if ANY process exists. A nonzero exit means no known agent.
        command: [
            "/usr/bin/pidof",
            "polkit-gnome-authentication-agent-1",
            "lxqt-policykit-agent",
            "polkit-kde-authentication-agent-1",
            "mate-polkit"
        ]

        onRunningChanged: {
            if (polkitAgentCheck.running) {
                polkitAgentCheck.startObserved = false
                return
            }
            if (polkitAgentCheck.startObserved)
                return

            // FailedToStart does not emit exited; lack of pidof must not disable
            // Alis' own authentication agent.
            root._loadImpl()
        }

        onStarted: polkitAgentCheck.startObserved = true

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Another agent exists; avoid the Quickshell polkit listener warning.
                return
            }
            root._loadImpl()
        }
    }
}
