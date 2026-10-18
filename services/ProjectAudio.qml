pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "ProjectAudioPolicy.js" as Policy

// CAST-F01: an optional, session-scoped HDMI/DP audio route.
// This never changes microphones, DSP config, per-app streams or network settings.
Singleton {
    id: root

    property string statusMessage: ""
    property string lastError: ""
    property string _sessionOutput: ""
    property string _previousName: ""
    property string _selectedName: ""
    property bool _owned: false
    property bool _manualOverride: false
    property bool _endRequested: false
    property string _operation: ""
    property int _probeAttempts: 0
    property int _restoreAttempts: 0

    readonly property bool active: _sessionOutput.length > 0
    readonly property string activeOutput: _sessionOutput
    readonly property bool busy: routeProcess.running || _endRequested
    readonly property bool audioRoutedToTv: _owned
        && Policy.name(Audio.rawSink) === _selectedName

    function beginWired(outputName): void {
        const output = String(outputName || "")
        if (!output || _sessionOutput === output || routeProcess.running
                || _endRequested || restoreTimer.running)
            return
        // End the previous session first rather than silently stealing its
        // restore token. A manual output choice must not be overridden.
        if (_sessionOutput && _sessionOutput !== output) {
            endWired()
            return
        }
        const previous = Policy.name(Audio.rawSink)
        if (!previous) {
            statusMessage = "Audio output is not ready; use Sound to select the TV."
            return
        }
        if (Policy.isEffects(Audio.rawSink)) {
            statusMessage = "Audio effects are active. Select the TV output in Sound if needed."
            return
        }
        _sessionOutput = output
        _previousName = previous
        _selectedName = ""
        _owned = false
        _manualOverride = false
        _endRequested = false
        _probeAttempts = 0
        statusMessage = "Checking for TV audio…"
        lastError = ""
        probeTimer.start()
        _probe()
    }

    function _probe(): void {
        if (!_sessionOutput || _manualOverride || _endRequested || routeProcess.running)
            return
        const found = Policy.chooseTvSink(Audio.outputDevices)
        if (found) {
            probeTimer.stop()
            _selectedName = Policy.name(found)
            if (_selectedName === Policy.name(Audio.rawSink)) {
                statusMessage = "TV audio was already selected."
                return // Alis does not own the pre-existing user choice
            }
            const id = Number(found.id ?? 0)
            if (!Number.isFinite(id) || id <= 0) return
            _operation = "select"
            routeProcess.command = ["wpctl", "set-default", String(id)]
            routeProcess.running = true
            statusMessage = "Switching playback to TV…"
            return
        }
        _probeAttempts++
        if (_probeAttempts >= 10) {
            probeTimer.stop()
            statusMessage = "TV audio not uniquely identified. Choose an output in Sound."
        }
    }

    function releaseOwnership(): void {
        // Called BEFORE the user manually chooses another sound output in
        // Utilities. End this automatic session without trying to restore it.
        _manualOverride = true
        _owned = false
        _previousName = ""
        _selectedName = ""
        probeTimer.stop()
        restoreTimer.stop()
        statusMessage = "Manual sound output selected."
    }

    function endWired(): void {
        probeTimer.stop()
        if (!_sessionOutput && !_endRequested) return
        _sessionOutput = ""
        _endRequested = true
        _restoreAttempts = 0
        if (routeProcess.running) return // finish selection, then restore
        _maybeRestore()
    }

    function _forgetRoute(): void {
        _owned = false
        _manualOverride = false
        _endRequested = false
        _previousName = ""
        _selectedName = ""
        _restoreAttempts = 0
        restoreTimer.stop()
    }

    function _maybeRestore(): void {
        if (!_endRequested || routeProcess.running) return
        if (!_owned || _manualOverride || !_previousName || !_selectedName) {
            _forgetRoute()
            return
        }
        if (Policy.safeToRestore(Audio.rawSink, _selectedName,
                _previousName, Audio.outputDevices)) {
            const oldDevice = Policy.findByName(Audio.outputDevices, _previousName)
            if (!oldDevice) {
                _forgetRoute()
                return
            }
            _operation = "restore"
            routeProcess.command = ["wpctl", "set-default", String(oldDevice.id)]
            routeProcess.running = true
            statusMessage = "Restoring previous sound output…"
            return
        }
        const current = Policy.name(Audio.rawSink)
        if (current && current !== _selectedName) {
            // PipeWire may still be settling after wpctl returns. Wait briefly
            // while the previous route is still selected, but never overwrite
            // a third output chosen by the user or the system.
            if (current === _previousName && _restoreAttempts < 8) {
                _restoreAttempts++
                restoreTimer.restart()
                return
            }
            statusMessage = "Audio output is managed by the system or user."
            _forgetRoute()
            return
        }
        _restoreAttempts++
        if (_restoreAttempts >= 10) {
            lastError = "Previous sound output could not be confirmed for restoration."
            _forgetRoute()
        } else {
            restoreTimer.restart()
        }
    }

    Timer {
        id: probeTimer
        interval: 400
        repeat: true
        onTriggered: root._probe()
    }

    Timer {
        id: restoreTimer
        interval: 200
        repeat: false
        onTriggered: root._maybeRestore()
    }

    Process {
        id: routeProcess
        stderr: StdioCollector { id: routeError }
        onExited: exitCode => {
            const op = root._operation
            root._operation = ""
            if (exitCode !== 0) {
                root.lastError = "TV sound routing failed: " + routeError.text.trim()
                root.statusMessage = ""
                root._forgetRoute()
                root._sessionOutput = ""
                return
            }
            if (op === "select") {
                root._owned = !root._manualOverride
                root.statusMessage = "TV sound output requested. Verify playback on TV."
                if (root._endRequested)
                    Qt.callLater(() => root._maybeRestore())
            } else if (op === "restore") {
                root.statusMessage = "Previous sound output restoration requested."
                root._forgetRoute()
            }
        }
    }
}
