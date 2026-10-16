pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import "DisplayModePlan.js" as DisplayPlan

Singleton {
    id: root

    readonly property string nativeDispatchPath: Quickshell.shellPath("scripts/native-dispatch")
    readonly property var connectedOutputs: DisplayPlan.normalizedNames(Object.keys(NiriService.outputs ?? {}))
    readonly property var activeOutputs: DisplayPlan.activeNames(NiriService.outputs ?? {})
    readonly property string primaryOutput: DisplayPlan.primary(
        connectedOutputs, Config.options?.display?.primaryMonitor ?? "")

    property string selectedSecondary: ""
    property string mirrorSource: ""
    property string mirrorTarget: ""
    property bool mirrorAvailable: false
    property bool mirrorProbeComplete: false
    property bool applying: false
    property string statusMessage: ""
    property string lastError: ""

    property var _queue: []
    property var _previousActive: []
    property var _pendingMirror: null
    property var _pendingMirrorRestart: null
    // Immutable identity of the launched wl-mirror process. UI dropdown
    // selections are normalized on hotplug and must not mask a disconnect.
    property var _runningMirrorPair: null
    property bool _manualMirrorStop: false
    property var _currentAction: null
    property bool _rollingBack: false
    property bool _stoppingMirror: false
    property string _operationFailure: ""
    property string _requestedMode: ""

    readonly property string currentMode: {
        if (mirrorProcess.running) return "mirror"
        if (!activeOutputs.length) return "none"
        if (connectedOutputs.length > 1 && activeOutputs.length === connectedOutputs.length)
            return "extend"
        if (activeOutputs.length === 1 && activeOutputs[0] === primaryOutput)
            return "primary-only"
        if (activeOutputs.length === 1)
            return "second-only"
        return "custom"
    }

    function normalizeSelections(): void {
        const names = connectedOutputs
        if (mirrorProcess.running
                && !DisplayPlan.mirrorPairConnected(names, _runningMirrorPair)) {
            stopMirror()
            statusMessage = ""
            lastError = "Display mirroring stopped because one of its outputs disconnected."
        }
        if (!names.length) {
            selectedSecondary = ""
            mirrorSource = ""
            mirrorTarget = ""
            return
        }
        const secondaryNames = names.filter(name => name !== primaryOutput)
        if (!secondaryNames.includes(selectedSecondary))
            selectedSecondary = secondaryNames[0] ?? ""
        if (!names.includes(mirrorSource))
            mirrorSource = primaryOutput || names[0]
        const mirrorTargets = names.filter(name => name !== mirrorSource)
        if (!mirrorTargets.includes(mirrorTarget))
            mirrorTarget = mirrorTargets[0] ?? ""
    }

    function setMirrorSource(name): void {
        const value = String(name ?? "")
        if (!connectedOutputs.includes(value)) return
        mirrorSource = value
        if (mirrorTarget === value || !connectedOutputs.includes(mirrorTarget))
            mirrorTarget = connectedOutputs.find(output => output !== value) ?? ""
    }

    function setMirrorTarget(name): void {
        const value = String(name ?? "")
        if (connectedOutputs.includes(value) && value !== mirrorSource)
            mirrorTarget = value
    }

    function probeMirrorHelper(): void {
        if (!mirrorProbe.running)
            mirrorProbe.running = true
    }

    function apply(mode): void {
        if (applying) return
        lastError = ""
        statusMessage = ""
        if (!CompositorService.isNiri) {
            lastError = "Display modes are currently available on Niri only."
            return
        }

        normalizeSelections()
        const plan = DisplayPlan.plan(mode, connectedOutputs, primaryOutput,
            selectedSecondary, mirrorSource, mirrorTarget)
        if (!plan.ok) {
            lastError = plan.error
            return
        }
        if (mode === "mirror" && !mirrorAvailable) {
            lastError = mirrorProbeComplete
                ? "Mirror requires wl-mirror. Install it and retry."
                : "Checking for wl-mirror…"
            probeMirrorHelper()
            return
        }

        _previousActive = activeOutputs.slice()
        _queue = plan.actions.slice()
        _pendingMirror = plan.mirror
        // A later explicit Apply takes ownership of the status; do not let a
        // still-pending earlier manual Stop overwrite the new mode's result.
        _manualMirrorStop = false
        _rollingBack = false
        _operationFailure = ""
        _requestedMode = mode
        applying = true
        statusMessage = "Applying display mode…"
        stopMirror()
        _runNextAction()
    }

    function _runNextAction(): void {
        if (!applying) return
        if (_queue.length === 0) {
            const restored = _rollingBack
            _rollingBack = false
            applying = false
            _currentAction = null
            NiriService.fetchOutputs()
            if (restored) {
                statusMessage = ""
                lastError = _operationFailure
                    + " The previous active-output set was restored."
                return
            }
            if (_requestedMode === "mirror" && _pendingMirror)
                _startMirror(_pendingMirror)
            else
                statusMessage = "Display mode applied for this Niri session."
            _pendingMirror = null
            return
        }

        _currentAction = _queue[0]
        _queue = _queue.slice(1)
        actionProcess.command = [
            nativeDispatchPath, "niri", "apply-output",
            _currentAction.output, "dpms=" + _currentAction.power
        ]
        actionProcess.running = true
    }

    function _actionFailed(detail): void {
        const action = _currentAction
        const summary = "Could not turn " + (action?.power ?? "")
            + " output " + (action?.output ?? "") + "."
        if (_rollingBack) {
            applying = false
            _queue = []
            _pendingMirror = null
            statusMessage = ""
            lastError = _operationFailure + " Rollback also failed. "
                + summary + (detail.length ? " " + detail : "")
            NiriService.fetchOutputs()
            return
        }

        _operationFailure = summary + (detail.length ? " " + detail : "")
        _rollingBack = true
        _pendingMirror = null
        const rollback = DisplayPlan.restore(
            connectedOutputs, _previousActive, primaryOutput)
        if (!rollback.ok) {
            applying = false
            _queue = []
            statusMessage = ""
            lastError = _operationFailure + " " + rollback.error
            NiriService.fetchOutputs()
            return
        }
        statusMessage = "Display change failed; restoring the previous output state…"
        _queue = rollback.actions.slice()
        _runNextAction()
    }

    // Cancel even an already scheduled callback when Stop/Apply supersedes it.
    property int _mirrorIntentRevision: 0

    function stopMirror(manual=false): void {
        _mirrorIntentRevision += 1
        _pendingMirrorRestart = null
        if (!mirrorProcess.running) return
        // A manual Stop deserves a confirmation; a stop as part of a new
        // display mode or a hotplug must not override that operation's status.
        _manualMirrorStop = !!manual
        _stoppingMirror = true
        mirrorProcess.running = false
    }

    function _startMirror(spec): void {
        if (!spec) return
        if (!mirrorAvailable) {
            lastError = "Mirror requires wl-mirror."
            statusMessage = ""
            return
        }
        if (mirrorProcess.running || _stoppingMirror) {
            _pendingMirrorRestart = spec
            if (mirrorProcess.running) {
                _stoppingMirror = true
                mirrorProcess.running = false
            }
            return
        }
        _launchMirror(spec)
    }

    function _launchMirror(spec): void {
        // A delayed restart after an expected stop can race with unplugging
        // either monitor. Never spawn wl-mirror against a vanished output.
        if (!DisplayPlan.mirrorPairConnected(connectedOutputs, spec)) {
            statusMessage = ""
            lastError = "Display mirroring cancelled because its outputs changed."
            return
        }
        _runningMirrorPair = {source: spec.source, target: spec.target}
        mirrorSource = spec.source
        mirrorTarget = spec.target
        mirrorProcess.command = [
            "wl-mirror", "--fullscreen-output", spec.target, spec.source
        ]
        statusMessage = "Starting display mirror…"
        mirrorProcess.running = true
    }

    onConnectedOutputsChanged: Qt.callLater(normalizeSelections)

    Component.onCompleted: {
        normalizeSelections()
        probeMirrorHelper()
    }

    Process {
        id: actionProcess
        stderr: StdioCollector { id: actionError }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root._actionFailed(actionError.text.trim())
                return
            }
            root._runNextAction()
        }
    }

    Process {
        id: mirrorProbe
        command: ["/bin/sh", "-c", "command -v wl-mirror >/dev/null 2>&1"]
        onExited: exitCode => {
            root.mirrorAvailable = exitCode === 0
            root.mirrorProbeComplete = true
        }
    }

    Process {
        id: mirrorProcess
        stderr: StdioCollector { id: mirrorError }
        onStarted: {
            // Show the running process identity, not dropdowns changed after
            // the command was launched.
            if (root._runningMirrorPair)
                root.statusMessage = DisplayPlan.mirrorRunningMessage(root._runningMirrorPair)
        }
        onExited: exitCode => {
            const expectedStop = root._stoppingMirror
            const manualStop = root._manualMirrorStop
            root._manualMirrorStop = false
            root._stoppingMirror = false
            root._runningMirrorPair = null
            if (root._pendingMirrorRestart) {
                const restart = root._pendingMirrorRestart
                root._pendingMirrorRestart = null
                const revision = root._mirrorIntentRevision
                Qt.callLater(() => {
                    // The queued callback must not revive a superseded mirror.
                    if (DisplayPlan.mirrorRestartAllowed(revision,
                            root._mirrorIntentRevision, root.applying,
                            root.connectedOutputs, restart))
                        root._launchMirror(restart)
                })
                return
            }
            const stoppedMessage=DisplayPlan.mirrorStoppedMessage(expectedStop,manualStop)
            if (stoppedMessage.length) root.statusMessage = stoppedMessage
            if (!expectedStop) {
                if (exitCode !== 0)
                    root.lastError = "wl-mirror exited with an error."
                        + (mirrorError.text.trim().length ? " " + mirrorError.text.trim() : "")
            }
        }
    }
}
