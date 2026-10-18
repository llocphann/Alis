pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// GNOME Network Displays 0.98+ native D-Bus integration. The helper owns no
// displays, networks or system configuration; it only calls the upstream API.
Singleton {
    id: root

    readonly property string bridge: Quickshell.shellPath("scripts/CAST-F01-network-displays.py")
    property var displays: []
    property string selectedUuid: ""
    property string activeUuid: ""
    property string activeUnit: ""
    property string activeName: ""
    property string phase: "idle"
    property string statusMessage: ""
    property string lastError: ""
    property bool scanning: false
    property bool backendAvailable: false
    property bool streamReady: false
    property bool _disconnectPending: false
    property int _inactiveReads: 0
    property int _connectChecks: 0
    property int _scanAttempt: 0

    readonly property bool active: activeUnit.length > 0
    readonly property bool busy: connectProcess.running || stopProcess.running
    readonly property bool streamServiceRunning: phase === "service-active"

    function _parse(output): var {
        try {
            const value = JSON.parse(String(output ?? ""))
            return value && typeof value === "object" ? value : null
        } catch (e) {
            return null
        }
    }

    function select(uuid): void {
        const target = displays.find(d => d.uuid === uuid)
        if (target) selectedUuid = target.uuid
    }

    function scan(): void {
        if (scanning || scanProcess.running) return
        scanning = true
        _scanAttempt = 0
        lastError = ""
        statusMessage = "Discovering nearby TVs…"
        _scanOnce()
    }

    function _scanOnce(): void {
        if (!scanning || scanProcess.running) return
        _scanAttempt++
        scanProcess.command = ["python3", bridge, "scan"]
        scanProcess.running = true
    }

    function connectToSelected(): void {
        const target = displays.find(d => d.uuid === selectedUuid)
        if (!target || !streamReady || scanning || active || busy) return
        lastError = ""
        _disconnectPending = false
        _inactiveReads = 0
        _connectChecks = 0
        activeUuid = target.uuid
        activeName = target.name
        phase = "connecting"
        statusMessage = "Starting " + target.name + "… Approve the system screen-share picker."
        connectProcess.command = ["python3", bridge, "start", target.uuid]
        connectProcess.running = true
    }

    function disconnect(): void {
        _disconnectPending = true
        pollTimer.stop()
        if (connectProcess.running) {
            phase = "disconnecting"
            statusMessage = "Finishing connection request before disconnect…"
            return
        }
        if (!activeUnit) {
            _reset("TV connection cancelled.")
            return
        }
        if (stopProcess.running) return
        phase = "disconnecting"
        statusMessage = "Disconnecting " + activeName + "…"
        stopProcess.command = ["python3", bridge, "stop", activeUnit]
        stopProcess.running = true
    }

    function _reset(message): void {
        pollTimer.stop()
        if (ProjectAudio.activeOutput === "wireless:" + activeUuid)
            ProjectAudio.endWired()
        activeUnit = ""
        activeUuid = ""
        activeName = ""
        phase = "idle"
        _inactiveReads = 0
        _connectChecks = 0
        _disconnectPending = false
        if (message) statusMessage = message
    }

    function _poll(): void {
        if (!activeUnit || phase === "disconnecting" || statusProcess.running) return
        statusProcess.command = ["python3", bridge, "status", activeUnit]
        statusProcess.running = true
    }

    Process {
        id: scanProcess
        stdout: StdioCollector { id: scanOutput }
        onExited: exitCode => {
            const data = exitCode === 0 ? root._parse(scanOutput.text) : null
            if (!data || !data.ok) {
                root.scanning = false
                scanRetry.stop()
                root.backendAvailable = !!data?.backend
                root.streamReady = false
                root.displays = []
                root.lastError = data?.message || "TV discovery failed."
                return
            }
            root.backendAvailable = true
            root.streamReady = data.streamReady === true
            root.displays = Array.isArray(data.displays) ? data.displays : []
            if (!root.displays.some(d => d.uuid === root.selectedUuid))
                root.selectedUuid = root.displays.length ? root.displays[0].uuid : ""

            // The daemon can acquire D-Bus before NM/mDNS providers finish
            // their first discovery. Retry for a bounded window, then stop.
            if (root.displays.length === 0 && root._scanAttempt < 5) {
                root.statusMessage = "Discovering nearby TVs… (" + root._scanAttempt + "/5)"
                scanRetry.restart()
                return
            }
            root.scanning = false
            if (!root.activeUnit)
                root.statusMessage = !root.streamReady
                    ? (data.message || "Native TV stream helper is missing. Use Open app.")
                    : root.displays.length
                        ? root.displays.length + " wireless receiver(s) found."
                        : "No TV found. Check the TV cast mode, Wi-Fi, and mDNS."
            root.lastError = ""
        }
    }

    Timer {
        id: scanRetry
        interval: 2000
        repeat: false
        onTriggered: root._scanOnce()
    }

    Process {
        id: connectProcess
        stdout: StdioCollector { id: connectOutput }
        onExited: exitCode => {
            const data = exitCode === 0 ? root._parse(connectOutput.text) : null
            if (!data?.ok || !data.unit) {
                root.lastError = data?.message || "Unable to start TV stream."
                root._reset("")
                return
            }
            root.activeUnit = String(data.unit)
            root.phase = "connecting"
            root.statusMessage = "Choose the screen or window in the system sharing dialog."
            if (root._disconnectPending) {
                Qt.callLater(() => root.disconnect())
                return
            }
            ProjectAudio.beginWireless(root.activeUuid)
            root._poll()
            pollTimer.start()
        }
    }

    Process {
        id: statusProcess
        stdout: StdioCollector { id: statusOutput }
        onExited: exitCode => {
            if (root.phase === "disconnecting" || !root.activeUnit) return
            const data = exitCode === 0 ? root._parse(statusOutput.text) : null
            root._connectChecks++
            if (data?.ok && data.state === "active") {
                root._inactiveReads = 0
                root.phase = "service-active"
                root.statusMessage = "Stream service running. Verify picture and sound on TV."
                return
            }
            if (data?.state === "activating") {
                root._inactiveReads = 0
                root.statusMessage = "Waiting for TV and screen-share permission…"
                return
            }
            if (data?.state === "failed" || data?.result === "exit-code") {
                root.lastError = "TV stream failed. Check receiver, codecs and screencast portal."
                root._reset("")
                return
            }
            // A user-systemd transient service may briefly report inactive
            // before registration; bounded grace instead of a false Connected.
            root._inactiveReads++
            if (root._inactiveReads <= 4) return
            root.lastError = "TV stream is inactive; retry Connect or use Open app."
            root._reset("")
        }
    }

    Process {
        id: stopProcess
        stdout: StdioCollector { id: stopOutput }
        onExited: exitCode => {
            const data = exitCode === 0 ? root._parse(stopOutput.text) : null
            if (!data?.ok) {
                // Keep the real unit identity for an explicit retry; never
                // claim disconnected while the upstream backend may be alive.
                root.lastError = data?.message || "TV disconnect not confirmed. Retry Disconnect."
                root.statusMessage = ""
                root.phase = "error"
                root._disconnectPending = false
                return
            }
            root._reset("TV disconnected.")
        }
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: root._poll()
    }
}
