pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Optional 10-band DSP Equalizer facade for the Media Popup.
 *
 * Alis keeps one EqualizerService/backend boundary. The helper feature-probes
 * EasyEffects' local property API, applies the 10-to-32-band curve directly to
 * the active Equalizer instance, and persists only those Equalizer fields into
 * the currently selected preset. It never reloads the preset, so Convolver,
 * Limiter, ordering, and unsaved live pipeline state are not reconstructed.
 * The helper talks to EasyEffectsServer directly with Python's AF_UNIX socket;
 * socat is not required for the DSP path.
 */
 
Singleton {
    id: root

    property bool enabled: false
    readonly property string backendName: "EasyEffects"
    readonly property bool backendAvailable:
        root.enabled && EasyEffects.available && root._transportAvailable
    readonly property bool backendRunning: root.enabled && EasyEffects.active
    readonly property bool available:
        root.backendAvailable && root.backendRunning && root._stateReady

    readonly property real minimumBandGain: -12
    readonly property real maximumBandGain: 12
    readonly property real dspMinimumBandGain: -12
    readonly property real dspMaximumBandGain: 12
    readonly property var dspFrequencies:
        [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var dspLabels:
        ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property var dspPresetCurves: ({
        "Flat":    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":    [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
        "Treble":  [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
        "Vocal":   [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
        "Pop":     [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
        "Rock":    [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
        "Jazz":    [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
        "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4]
    })

    property string error: ""
    property int _consumerCount: 0
    property bool _transportChecked: false
    property bool _transportAvailable: false
    property bool _stateReady: false
    property var _dspGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string _presetName: "Flat"
    property var _pendingGains: []
    property string _pendingPresetName: ""
    property int _lifecycleGeneration: 0

    readonly property bool busy: applyProc.running
    readonly property bool dspControlAvailable:
        root.available && !root.busy
    readonly property string dspPresetName: root._presetName
    readonly property var dspBands: {
        const result = []
        for (let i = 0; i < root.dspFrequencies.length; ++i) {
            result.push({
                dspIndex: i,
                backendIndex: i,
                frequency: root.dspFrequencies[i],
                label: root.dspLabels[i],
                gain: Number(root._dspGains[i]) || 0,
                synced: root._stateReady
            })
        }
        return result
    }

    function registerConsumer() {
        root._consumerCount++
        if (!root.enabled) {
            root.enabled = true
        } else {
            if (!root._transportChecked
                    && (root.error === "transport-unavailable"
                        || root.error === "transport-probe-failed"))
                root.error = ""
            root.refresh()
        }
    }

    function unregisterConsumer() {
        root._consumerCount = Math.max(0, root._consumerCount - 1)
        // A presentation lease must never interrupt a user-authorized DSP
        // transaction halfway through its live band writes.
        if (root._consumerCount === 0 && !root.busy)
            root.enabled = false
    }

    function _releaseAfterApply() {
        Qt.callLater(() => {
            if (root._consumerCount === 0 && !root.busy)
                root.enabled = false
        })
    }

    function startBackend() {
        if (!root.enabled)
            root.enabled = true
        if (!EasyEffects.available) {
            EasyEffects.fetchAvailability()
            root.error = "backend-unavailable"
            return false
        }
        EasyEffects.enable()
        backendRefreshTimer.restart()
        return true
    }

    function _startTransportProbe() {
        if (!root.enabled || transportProbe.running)
            return
        transportProbe.generation = root._lifecycleGeneration
        transportProbe.running = true
    }

    function _retryStaleTransportProbe(generation) {
        if (!root.enabled
                || generation === root._lifecycleGeneration
                || root._transportChecked)
            return
        // Process.running may still be true while onExited is unwinding. Queue
        // the replacement probe after the stale process has fully settled.
        Qt.callLater(() => {
            if (root.enabled && !root._transportChecked)
                root._startTransportProbe()
        })
    }

    function refresh() {
        if (!root.enabled)
            return
        EasyEffects.fetchAvailability()
        if (!root._transportChecked) {
            root._startTransportProbe()
            return
        }
        root._refreshBackendState()
    }

    function _refreshBackendState() {
        if (!root.enabled)
            return
        // "false" is the default transport value before any valid probe has
        // completed. Do not publish an unavailable error for that unknown state.
        // This path also restarts a probe invalidated by an EasyEffects lifecycle
        // generation change during shell boot/reload.
        if (!root._transportChecked) {
            root._startTransportProbe()
            return
        }
        if (!root._transportAvailable) {
            root.error = "transport-unavailable"
            root._stateReady = false
            return
        }
        if (!EasyEffects.available) {
            root.error = "backend-unavailable"
            root._stateReady = false
            return
        }
        EasyEffects.fetchActiveState()
        if (!EasyEffects.active) {
            root.error = "backend-not-running"
            root._stateReady = false
            return
        }
        root._readState()
    }

    function _readState() {
        if (!root.enabled || stateReadProc.running)
            return
        stateReadProc.generation = root._lifecycleGeneration
        stateReadProc.running = true
    }

    function _normalizeGains(values) {
        if (!values || values.length !== root.dspFrequencies.length)
            return null
        const result = []
        for (let i = 0; i < values.length; ++i) {
            const value = Number(values[i])
            if (!isFinite(value))
                return null
            result.push(Math.max(root.dspMinimumBandGain,
                Math.min(root.dspMaximumBandGain, value)))
        }
        return result
    }

    function _normalizeGainsInPlace(values) {
        if (!values || values.length !== root.dspFrequencies.length)
            return null
        for (let i = 0; i < values.length; ++i) {
            const value = Number(values[i])
            if (!isFinite(value))
                return null
            values[i] = Math.max(root.dspMinimumBandGain,
                Math.min(root.dspMaximumBandGain, value))
        }
        return values
    }

    function _applyStateInternal(gains, presetName, normalizeInPlace) {
        if (!root.enabled) {
            root.error = "feature-disabled"
            return false
        }
        if (!root._transportAvailable) {
            root.error = "transport-unavailable"
            return false
        }
        if (!EasyEffects.available) {
            root.error = "backend-unavailable"
            return false
        }
        if (!root.backendRunning) {
            root.error = "backend-not-running"
            return false
        }
        if (root.busy) {
            root.error = "backend-busy"
            return false
        }

        const normalized = normalizeInPlace
            ? root._normalizeGainsInPlace(gains)
            : root._normalizeGains(gains)
        if (!normalized) {
            root.error = "invalid-dsp-state"
            return false
        }

        const label = String(presetName ?? "Custom").trim()
        if (label.length === 0 || label.includes(":")
                || label.includes("\n") || label.includes("\r")) {
            root.error = "invalid-dsp-preset"
            return false
        }

        root._pendingGains = normalized
        root._pendingPresetName = label
        root.error = ""

        const command = [
            Quickshell.shellPath("scripts/equalizer-control.sh"),
            "apply",
            EasyEffects.nativeInstalled ? "native" : "flatpak",
            label
        ]
        for (const gain of normalized)
            command.push(String(gain))

        applyProc.generation = root._lifecycleGeneration
        applyProc.command = command
        applyProc.running = true
        return true
    }

    function _applyState(gains, presetName) {
        return root._applyStateInternal(gains, presetName, false)
    }

    function setDspBandGain(index, gain) {
        const dspIndex = Number(index)
        const requestedGain = Number(gain)
        if (!root.dspControlAvailable) {
            root.error = root.backendRunning ? "dsp-unavailable" : "backend-not-running"
            return false
        }
        if (!isFinite(dspIndex) || Math.floor(dspIndex) !== dspIndex
                || dspIndex < 0 || dspIndex >= root.dspFrequencies.length
                || !isFinite(requestedGain)) {
            root.error = "invalid-dsp-band"
            return false
        }
        const next = root._dspGains.slice()
        next[dspIndex] = Math.max(root.dspMinimumBandGain,
            Math.min(root.dspMaximumBandGain, requestedGain))
        return root._applyStateInternal(next, "Custom", true)
    }

    function applyDspPreset(name) {
        const preset = String(name ?? "").trim()
        const curve = root.dspPresetCurves[preset]
        if (!curve) {
            root.error = "invalid-dsp-preset"
            return false
        }
        return root._applyState(curve, preset)
    }

    onEnabledChanged: {
        root._lifecycleGeneration++
        transportProbe.running = false
        stateReadProc.running = false
        applyProc.running = false
        root._pendingGains = []
        root._pendingPresetName = ""

        if (root.enabled) {
            root.refresh()
        } else {
            root.error = ""
            root._transportChecked = false
            root._transportAvailable = false
            root._stateReady = false
        }
    }

    Connections {
        target: root.enabled ? EasyEffects : null

        function onAvailableChanged() {
            root._lifecycleGeneration++
            applyProc.running = false
            stateReadProc.running = false
            if (!EasyEffects.available) {
                root._stateReady = false
                root.error = "backend-unavailable"
                return
            }
            if (root._transportChecked)
                root._refreshBackendState()
        }

        function onActiveChanged() {
            root._lifecycleGeneration++
            applyProc.running = false
            stateReadProc.running = false
            if (!root.enabled)
                return
            if (!EasyEffects.active) {
                root._stateReady = false
                if (root._transportAvailable)
                    root.error = "backend-not-running"
                return
            }
            backendRefreshTimer.restart()
        }
    }

    Timer {
        id: backendRefreshTimer
        interval: 350
        repeat: false
        onTriggered: root._refreshBackendState()
    }

    Process {
        id: transportProbe
        property int generation: 0
        command: ["/usr/bin/env", "sh", "-c",
            "command -v python3 >/dev/null 2>&1"]

        onExited: (exitCode, exitStatus) => {
            if (!root.enabled)
                return
            if (generation !== root._lifecycleGeneration) {
                root._retryStaleTransportProbe(generation)
                return
            }
            root._transportChecked = true
            root._transportAvailable = exitCode === 0
            if (!root._transportAvailable) {
                root._stateReady = false
                root.error = "transport-unavailable"
                return
            }
            root._refreshBackendState()
        }
    }

    Process {
        id: stateReadProc
        property int generation: 0
        command: [Quickshell.shellPath("scripts/equalizer-control.sh"), "get"]
        stdout: StdioCollector {
            id: stateCollector
        }

        onExited: (exitCode, exitStatus) => {
            if (!root.enabled || generation !== root._lifecycleGeneration)
                return
            if (exitCode !== 0) {
                root._stateReady = false
                root.error = "dsp-state-read-failed"
                return
            }
            try {
                const state = JSON.parse(stateCollector.text ?? "")
                const normalized = root._normalizeGains(state?.gains)
                if (!normalized) {
                    root._stateReady = false
                    root.error = "malformed-dsp-state"
                    return
                }
                root._dspGains = normalized
                const label = String(state?.preset ?? "Custom").trim()
                root._presetName = label.length > 0 ? label : "Custom"
                root._stateReady = true
                root.error = ""
            } catch (error) {
                root._stateReady = false
                root.error = "malformed-dsp-state"
            }
        }
    }

    Process {
        id: applyProc
        property int generation: 0

        onExited: (exitCode, exitStatus) => {
            root._releaseAfterApply()
            if (!root.enabled || generation !== root._lifecycleGeneration)
                return
            if (exitCode !== 0) {
                root._pendingGains = []
                root._pendingPresetName = ""
                if (exitCode === 65)
                    root.error = "backend-not-running"
                else if (exitCode === 127) {
                    root._transportAvailable = false
                    root.error = "transport-unavailable"
                } else
                    root.error = "dsp-apply-failed"
                return
            }

            const normalized = root._normalizeGains(root._pendingGains)
            if (normalized)
                root._dspGains = normalized
            root._presetName = root._pendingPresetName || "Custom"
            root._pendingGains = []
            root._pendingPresetName = ""
            root._stateReady = true
            root.error = ""
        }
    }
}
