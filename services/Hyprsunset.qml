pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

/**
 * Night light service with automatic mode.
 * Uses hyprsunset on Hyprland, wlsunset on Niri.
 */
Singleton {
    id: root
    property string from: Config.options?.light?.night?.from ?? "19:00" 
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: (Config.options?.light?.night?.automatic ?? true) && (Config?.ready ?? true)
    property bool manualEnabled: Config.options?.light?.night?.enabled ?? false
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool active: false
    property bool stateKnown: false
    property bool _pendingEnable: false
    property bool _pendingDisable: false
    property bool _toggleAfterProbe: false
    property bool _pendingRestart: false
    property bool _restartOwnedAfterExit: false
    property bool _destroying: false

    function _timeParts(value, fallbackHour: int, fallbackMinute: int): var {
        const match = String(value ?? "").trim().match(/^(\d{1,2}):(\d{2})$/)
        if (!match)
            return ({ hour: fallbackHour, minute: fallbackMinute })
        const hour = Number(match[1])
        const minute = Number(match[2])
        if (!Number.isInteger(hour) || !Number.isInteger(minute)
                || hour < 0 || hour > 23 || minute < 0 || minute > 59)
            return ({ hour: fallbackHour, minute: fallbackMinute })
        return ({ hour: hour, minute: minute })
    }

    readonly property var fromParts: root._timeParts(root.from, 19, 0)
    readonly property var toParts: root._timeParts(root.to, 6, 30)
    readonly property int fromHour: root.fromParts.hour
    readonly property int fromMinute: root.fromParts.minute
    readonly property int toHour: root.toParts.hour
    readonly property int toMinute: root.toParts.minute

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    // A manual toggle while automatic mode is enabled overrides the schedule
    // until the next configured boundary, rather than being undone next minute.
    property real manualOverrideUntilMs: 0

    // Debounce temperature-driven restarts of the process Alis owns. An
    // externally started night-light process is observed but never restarted.
    Timer {
        id: restartDebounce
        interval: 300
        onTriggered: {
            if (!root._pendingRestart)
                return
            root._pendingRestart = false
            root._restartOwnedProcess()
        }
    }

    Timer {
        id: stateVerifyTimer
        interval: 800
        repeat: false
        onTriggered: root.fetchState()
    }

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined
        root.manualOverrideUntilMs = 0
        root.firstEvaluation = true
        reEvaluate()
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            // Wrapped around midnight
            return (t >= from || t <= to);
        }
    }

    function _nextScheduleBoundaryMs() {
        const now = new Date()
        const nowMs = now.getTime()
        let nextMs = Number.MAX_VALUE

        for (let dayOffset = 0; dayOffset <= 1; ++dayOffset) {
            const fromDate = new Date(now)
            fromDate.setDate(fromDate.getDate() + dayOffset)
            fromDate.setHours(root.fromHour, root.fromMinute, 0, 0)
            const fromMs = fromDate.getTime()
            if (fromMs > nowMs && fromMs < nextMs)
                nextMs = fromMs

            const toDate = new Date(now)
            toDate.setDate(toDate.getDate() + dayOffset)
            toDate.setHours(root.toHour, root.toMinute, 0, 0)
            const toMs = toDate.getTime()
            if (toMs > nowMs && toMs < nextMs)
                nextMs = toMs
        }

        return nextMs === Number.MAX_VALUE
            ? nowMs + 24 * 60 * 60 * 1000
            : nextMs
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute
        const from = fromHour * 60 + fromMinute
        const to = toHour * 60 + toMinute

        if (root.manualActive !== undefined
                && root.manualOverrideUntilMs > 0
                && Date.now() >= root.manualOverrideUntilMs) {
            root.manualActive = undefined
            root.manualOverrideUntilMs = 0
        }
        root.shouldBeOn = inBetween(t, from, to)
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        } else if (root.automatic && root.manualActive === undefined
                && root.active !== root.shouldBeOn) {
            // State probes may reveal that a start/stop failed after the desired
            // schedule value stopped changing. Reconcile on the next minute so
            // automatic mode self-heals without creating a tight process loop.
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        if (root.automatic && root.manualActive !== undefined)
            return

        if (root.automatic) {
            if (root.shouldBeOn) {
                root.enable();
            } else {
                root.disable();
            }
        } else if (root.manualEnabled) {
            root.enable();
        } else {
            root.disable();
        }
    }

    function load() {
        // shell.qml calls this once during deferred initialization. Resolve the
        // configured schedule and real backend state explicitly; state probes
        // themselves stay one-shot instead of being bound permanently running.
        root.reEvaluate()
    }

    function _ownedProcessRunning(): bool {
        return CompositorService.isNiri ? wlsunsetProc.running : hyprsunsetProc.running
    }

    function _startOwnedProcess(): void {
        if (root._destroying || root._ownedProcessRunning())
            return
        root._pendingEnable = false
        if (CompositorService.isNiri)
            wlsunsetProc.running = true
        else
            hyprsunsetProc.running = true
    }

    function _stopOwnedProcess(restart: bool): void {
        root._restartOwnedAfterExit = restart
        if (CompositorService.isNiri) {
            if (wlsunsetProc.running) {
                wlsunsetProc.running = false
                return
            }
        } else if (hyprsunsetProc.running) {
            hyprsunsetProc.running = false
            return
        }

        if (restart) {
            root._restartOwnedAfterExit = false
            root._startOwnedProcess()
        }
    }

    function _restartOwnedProcess(): void {
        // Do not mutate an externally-owned process merely because Alis can
        // detect it. Only the child launched by this singleton is restartable.
        if (root._ownedProcessRunning())
            root._stopOwnedProcess(true)
    }

    function _ownedProcessStopped(): void {
        if (root._destroying)
            return
        if (root._restartOwnedAfterExit) {
            root._restartOwnedAfterExit = false
            Qt.callLater(() => root._startOwnedProcess())
            return
        }
        stateVerifyTimer.restart()
    }

    function _finishStateProbe(detectedActive: bool): void {
        root.active = detectedActive || root._ownedProcessRunning()
        root.stateKnown = true

        if (root._toggleAfterProbe) {
            root._toggleAfterProbe = false
            root._applyManualDesiredState(!root.active)
            return
        }

        if (root._pendingDisable) {
            root._pendingDisable = false
            if (root.active) {
                root._stopDetectedBackend()
                return
            }
            root.active = false
        }

        if (root._pendingEnable) {
            root._pendingEnable = false
            if (!root.active)
                root._startOwnedProcess()
        }
    }

    function enable() {
        root._pendingDisable = false

        if (backendStopProc.running) {
            root._pendingEnable = true
            return
        }
        if (root._ownedProcessRunning()) {
            root.active = true
            return
        }
        if (!root.stateKnown) {
            root._pendingEnable = true
            root.fetchState()
            return
        }
        // An already-active external backend is a valid active state. If the
        // user later changes temperature, it is migrated to an owned process.
        if (root.active)
            return
        root._startOwnedProcess()
    }

    function _stopDetectedBackend(): void {
        if (root._destroying || backendStopProc.running)
            return

        // Destruction still stops only child processes owned by this singleton.
        // This path is different: an explicit/scheduled OFF request is
        // authoritative, so a legacy detached backend must also be disabled.
        backendStopProc.command = CompositorService.isNiri
            ? ["/usr/bin/pkill", "-TERM", "-x", "wlsunset"]
            : ["/usr/bin/pkill", "-TERM", "-x", "hyprsunset"]
        backendStopProc.running = true
    }

    function disable() {
        root._pendingEnable = false
        root._pendingRestart = false
        root._restartOwnedAfterExit = false
        restartDebounce.stop()

        if (root._ownedProcessRunning()) {
            root.active = false
            root._stopOwnedProcess(false)
            stateVerifyTimer.restart()
            return
        }

        if (backendStopProc.running) {
            root._pendingDisable = true
            return
        }

        if (!root.stateKnown) {
            root._pendingDisable = true
            root.fetchState()
            return
        }

        if (root.active) {
            root._pendingDisable = true
            root._stopDetectedBackend()
            return
        }

        root._pendingDisable = false
        root.active = false
    }

    function fetchState() {
        if (CompositorService.isNiri) {
            if (!niriFetchProc.running)
                niriFetchProc.running = true;
        } else if (!fetchProc.running) {
            fetchProc.running = true;
        }
    }

    Process {
        id: backendStopProc
        running: false
        property bool startObserved: false

        onRunningChanged: {
            if (backendStopProc.running) {
                backendStopProc.startObserved = false
                return
            }
            if (backendStopProc.startObserved)
                return

            console.warn("[Hyprsunset] Night-light backend stop command failed to start")
            stateVerifyTimer.restart()
        }
        onStarted: backendStopProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            // pkill returns 1 when no matching process remains; that is already
            // the desired OFF state. A verification probe is authoritative.
            if (exitCode > 1)
                console.warn("[Hyprsunset] Night-light backend stop failed with code", exitCode)
            root.active = false
            stateVerifyTimer.restart()
        }
    }

    // === Hyprland processes ===
    Process {
        id: hyprsunsetProc
        property bool startObserved: false
        running: false
        command: ["/usr/bin/hyprsunset", "--temperature", root.colorTemperature.toString()]

        onRunningChanged: {
            if (hyprsunsetProc.running) {
                hyprsunsetProc.startObserved = false
                return
            }
            if (hyprsunsetProc.startObserved)
                return
            root.active = false
            root._ownedProcessStopped()
        }
        onStarted: {
            hyprsunsetProc.startObserved = true
            root.stateKnown = true
            root.active = true
        }
        onExited: root._ownedProcessStopped()
    }

    Process {
        id: fetchProc
        property bool startObserved: false
        property bool timedOut: false
        running: false
        command: ["/usr/bin/bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
        }
        onRunningChanged: {
            if (fetchProc.running) {
                fetchProc.startObserved = false
                return
            }
            if (fetchProc.startObserved)
                return

            hyprStateProbeTimeout.stop()
            console.warn("[Hyprsunset] Hyprland state probe failed to start")
            root._finishStateProbe(false)
        }
        onStarted: {
            fetchProc.startObserved = true
            fetchProc.timedOut = false
            hyprStateProbeTimeout.restart()
        }
        onExited: (exitCode, exitStatus) => {
            hyprStateProbeTimeout.stop()
            if (fetchProc.timedOut)
                console.warn("[Hyprsunset] Hyprland state probe timed out")
            const output = stateCollector.text.trim()
            root._finishStateProbe(!fetchProc.timedOut
                && exitCode === 0
                && output.length > 0
                && !output.startsWith("Couldn't")
                && output !== "6500")
        }
    }

    Timer {
        id: hyprStateProbeTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!fetchProc.running)
                return
            fetchProc.timedOut = true
            fetchProc.running = false
        }
    }

    // === Niri processes (wlsunset) ===
    Process {
        id: wlsunsetProc
        property bool startObserved: false
        running: false
        // Force "always night" mode: sunset at 00:00, sunrise at 23:59.
        command: [
            "/usr/bin/wlsunset",
            "-T", "6500",
            "-t", root.colorTemperature.toString(),
            "-s", "00:00",
            "-S", "23:59"
        ]

        onRunningChanged: {
            if (wlsunsetProc.running) {
                wlsunsetProc.startObserved = false
                return
            }
            if (wlsunsetProc.startObserved)
                return
            root.active = false
            root._ownedProcessStopped()
        }
        onStarted: {
            wlsunsetProc.startObserved = true
            root.stateKnown = true
            root.active = true
        }
        onExited: root._ownedProcessStopped()
    }

    Process {
        id: niriFetchProc
        property bool startObserved: false
        property bool timedOut: false
        running: false
        command: ["/usr/bin/pidof", "wlsunset"]
        onRunningChanged: {
            if (niriFetchProc.running) {
                niriFetchProc.startObserved = false
                return
            }
            if (niriFetchProc.startObserved)
                return

            niriStateProbeTimeout.stop()
            console.warn("[Hyprsunset] Niri state probe failed to start")
            root._finishStateProbe(false)
        }
        onStarted: {
            niriFetchProc.startObserved = true
            niriFetchProc.timedOut = false
            niriStateProbeTimeout.restart()
        }
        onExited: (exitCode, exitStatus) => {
            niriStateProbeTimeout.stop()
            if (niriFetchProc.timedOut)
                console.warn("[Hyprsunset] Niri state probe timed out")
            root._finishStateProbe(!niriFetchProc.timedOut && exitCode === 0)
        }
    }

    Timer {
        id: niriStateProbeTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!niriFetchProc.running)
                return
            niriFetchProc.timedOut = true
            niriFetchProc.running = false
        }
    }

    function _applyManualDesiredState(desired: bool): void {
        root.manualActive = desired
        root.manualOverrideUntilMs = root.automatic
            ? root._nextScheduleBoundaryMs()
            : 0
        Config.setNestedValue("light.night.enabled", desired)
        if (desired)
            root.enable()
        else
            root.disable()
    }

    function toggle(active = undefined) {
        if (active === undefined && !root.stateKnown) {
            // Resolve the real backend state before inverting it. The singleton
            // starts with active=false, which is not authoritative before probe.
            root._toggleAfterProbe = true
            root.fetchState()
            return
        }

        const desired = active !== undefined ? Boolean(active) : !root.active
        root._applyManualDesiredState(desired)
    }

    // React to temperature changes while active. Owned backends restart in
    // place; legacy/detached backends are migrated to an owned process.
    Connections {
        target: Config.options?.light?.night ?? null
        enabled: !!(Config.options?.light?.night)
        
        function onColorTemperatureChanged() {
            if (!root.active)
                return

            if (root._ownedProcessRunning()) {
                root._pendingRestart = true
                restartDebounce.restart()
                return
            }

            // A legacy detached backend cannot be reconfigured in place on
            // Niri. Stop it, then let the state probe start an owned instance
            // with the new temperature.
            root._pendingEnable = true
            root._stopDetectedBackend()
        }
    }

    // React to schedule changes while automatic mode is on
    Connections {
        target: Config.options?.light?.night ?? null
        enabled: root.automatic && !!(Config.options?.light?.night)
        
        function onFromChanged() {
            if (root.manualActive !== undefined)
                root.manualOverrideUntilMs = root._nextScheduleBoundaryMs()
            root.firstEvaluation = true
            root.reEvaluate()
        }
        
        function onToChanged() {
            if (root.manualActive !== undefined)
                root.manualOverrideUntilMs = root._nextScheduleBoundaryMs()
            root.firstEvaluation = true
            root.reEvaluate()
        }
    }

    Component.onDestruction: {
        root._destroying = true
        restartDebounce.stop()
        stateVerifyTimer.stop()
        hyprStateProbeTimeout.stop()
        niriStateProbeTimeout.stop()
        root._restartOwnedAfterExit = false
        root._pendingDisable = false
        root._toggleAfterProbe = false
        backendStopProc.running = false
        hyprsunsetProc.running = false
        wlsunsetProc.running = false
    }
}
