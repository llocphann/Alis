pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "brightnessPolicy.js" as BrightnessPolicy
import "antiFlashbangPolicy.js" as AntiFlashbangPolicy

/**
 * For managing brightness of monitors. Supports both brightnessctl and ddcutil.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    property list<BrightnessMonitor> monitors: []
    property string backlightDevice: ""
    property bool backlightDetectionReady: false
    property int _bestBacklightMax: 0
    // last >0 level per screen.name; survives monitor recreation after dpms
    property var lastValidBrightness: ({})
    property bool asleep: false
    readonly property bool antiFlashbangActive: Config.ready
        && (Config.options?.light?.antiFlashbang?.enable ?? false)
        && !root.asleep && !GlobalStates.screenLocked
        && (!(Config.options?.light?.antiFlashbang?.darkOnly ?? true) || Appearance.m3colors.darkmode)
        && (CompositorService.isNiri || CompositorService.isHyprland)

    // Reconcile against the live screen list rather than binding to
    // Quickshell.screens: createObject() parents each monitor to root, so a
    // binding would strand a whole generation of BrightnessMonitors on every
    // screen change (hotplug, DPMS, mode switch). Still-connected screens keep
    // their existing BrightnessMonitor (and its running Timers/Processes);
    // disconnected ones are destroyed so they don't react to a dead screen.
    function _syncMonitors(): void {
        // Array.from is load-bearing: list<T> is a live view of the property, not
        // a snapshot, so holding it directly would alias the *new* list after the
        // assignment below and destroy the monitors we just built/kept.
        const prev = Array.from(root.monitors);
        const next = Quickshell.screens.map(screen => {
            const existing = prev.find(m => m.screen === screen)
                ?? prev.find(m => m.screen?.name && m.screen.name === screen?.name);
            if (existing) {
                existing.screen = screen;
                return existing;
            }
            return monitorComp.createObject(root, { screen });
        });
        root.monitors = next;
        for (const m of prev) {
            if (!next.includes(m)) m.destroy();
        }
    }

    function _detectBacklight(): void {
        root.backlightDetectionReady = false
        root.backlightDevice = ""
        root._bestBacklightMax = 0
        backlightDetectProc.running = false
        backlightDetectProc.running = true
    }

    function sleepBegin(): void {
        root.asleep = true
    }

    function restoreAfterWake(): void {
        root.asleep = false
        for (let i = 0; i < root.monitors.length; ++i)
            root.monitors[i].restoreLastGood();
    }

    Component.onCompleted: {
        root._syncMonitors()
        root._detectBacklight()
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            if (root.asleep)
                return
            root._syncMonitors();
            root._detectBacklight();
        }
    }

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    function increaseBrightness(): void {
        const focusedName = CompositorService.isNiri ? NiriService.currentOutput : Hyprland.focusedMonitor?.name;
        if (!focusedName) return;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness + 0.05);
    }

    function decreaseBrightness(): void {
        const focusedName = CompositorService.isNiri ? NiriService.currentOutput : Hyprland.focusedMonitor?.name;
        if (!focusedName) return;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness - 0.05);
    }

    reloadableId: "brightness"

    property var _ddcNext: []

    onMonitorsChanged: {
        if (root.asleep)
            return
        ddcProc.running = false
        ddcProc.running = true
    }

    Process {
        id: backlightDetectProc
        property bool timedOut: false
        property bool startObserved: false
        command: ["brightnessctl", "-l", "-m", "-c", "backlight"]
        onRunningChanged: {
            if (backlightDetectProc.running) {
                backlightDetectProc.startObserved = false
                return
            }
            if (backlightDetectProc.startObserved)
                return

            backlightDetectTimeout.stop()
            root.backlightDetectionReady = true
            root.monitors.forEach(monitor => {
                if (!monitor.isDdc)
                    monitor.initialize()
            })
            console.warn("[Brightness] Failed to start brightnessctl backlight detection")
        }
        onStarted: {
            backlightDetectProc.startObserved = true
            backlightDetectProc.timedOut = false
            backlightDetectTimeout.restart()
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                // brightnessctl machine format:
                // device,class,current,current-percent,max
                const parts = line.trim().split(",")
                if (parts.length < 5 || parts[1] !== "backlight")
                    return
                const name = parts[0]
                const max = Number(parts[parts.length - 1])
                if (!name || !Number.isFinite(max) || max <= 0)
                    return
                // Multi-backlight AMD laptops commonly expose a tiny stub and
                // the real panel device. The useful panel has the larger range.
                if (max > root._bestBacklightMax) {
                    root._bestBacklightMax = max
                    root.backlightDevice = name
                }
            }
        }
        onExited: {
            backlightDetectTimeout.stop()
            if (backlightDetectProc.timedOut)
                console.warn("[Brightness] brightnessctl backlight detection timed out")
            root.backlightDetectionReady = true
            root.monitors.forEach(monitor => {
                if (!monitor.isDdc)
                    monitor.initialize()
            })
        }
    }

    Timer {
        id: backlightDetectTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!backlightDetectProc.running)
                return
            backlightDetectProc.timedOut = true
            backlightDetectProc.running = false
        }
    }

    Process {
        id: ddcProc
        property bool timedOut: false
        property bool startObserved: false

        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                if (!data.startsWith("Display "))
                    return

                const lines = data.split("\n").map(l => l.trim())
                const monitorLine = lines.find(l => l.startsWith("Monitor:"))
                const busLine = lines.find(l => l.startsWith("I2C bus:"))
                if (!monitorLine || !busLine) {
                    console.warn("[Brightness] Ignoring malformed ddcutil display block")
                    return
                }

                const monitorParts = monitorLine.split(":")
                const model = (monitorParts.length >= 3
                    ? monitorParts.slice(2).join(":")
                    : monitorParts.slice(1).join(":"))
                    .trim()
                const busMarker = "/dev/i2c-"
                const busIndex = busLine.indexOf(busMarker)
                const busNum = busIndex >= 0
                    ? busLine.slice(busIndex + busMarker.length).trim()
                    : ""
                if (!model || !/^\d+$/.test(busNum)) {
                    console.warn("[Brightness] Ignoring invalid ddcutil monitor fields")
                    return
                }

                root._ddcNext.push({ model: model, busNum: busNum })
            }
        }
        onRunningChanged: {
            if (ddcProc.running) {
                ddcProc.startObserved = false
                root._ddcNext = []
                return
            }
            if (ddcProc.startObserved)
                return

            ddcTimeout.stop()
            root._ddcNext = []
            console.warn("[Brightness] Failed to start ddcutil detection; keeping previous monitor snapshot")
        }
        onStarted: {
            ddcProc.startObserved = true
            ddcProc.timedOut = false
            ddcTimeout.restart()
        }
        onExited: (exitCode, exitStatus) => {
            ddcTimeout.stop()
            if (ddcProc.timedOut) {
                console.warn("[Brightness] ddcutil detection timed out; keeping previous monitor snapshot")
            } else if (exitCode === 0) {
                // A successful empty probe means all DDC displays disappeared.
                // Replace the snapshot even when no blocks were parsed so stale
                // model/bus mappings cannot survive a hot-unplug.
                root.ddcMonitors = root._ddcNext
                root.ddcMonitorsChanged()
            } else {
                // Preserve the last known-good mapping on transient probe errors.
                console.warn("[Brightness] ddcutil detect failed; keeping previous monitor snapshot", exitCode, exitStatus)
            }
            root._ddcNext = []
        }
    }

    Timer {
        id: ddcTimeout
        interval: 30000
        repeat: false
        onTriggered: {
            if (!ddcProc.running)
                return
            ddcProc.timedOut = true
            ddcProc.running = false
        }
    }

    Process {
        id: setProc
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        readonly property bool isDdc: {
            const match = root.ddcMonitors.find(m => screen?.model?.includes(m.model) && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum));
            return !!match;
        }
        readonly property string busNum: {
            const match = root.ddcMonitors.find(m => screen?.model?.includes(m.model) && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum));
            return match?.busNum ?? "";
        }
        property int rawMaxBrightness: 100
        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (root.antiFlashbangActive ? brightnessMultiplier : 1)))
        property bool ready: false
        property bool animateChanges: !monitor.isDdc
        property bool writePending: false
        property int _lastSyncedRaw: -1

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.brightnessChanged();
        }

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges
            NumberAnimation {
                duration: root.antiFlashbangActive
                    ? AntiFlashbangPolicy.bounded(Config.options?.light?.antiFlashbang?.responseMs, 80, 40, 500) : 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        onMultipliedBrightnessChanged: {
            if (!monitor.ready) return
            monitor.writePending = true
            if (!setTimer.running)
                setTimer.start()
        }

        function restoreLastGood(): void {
            monitor._lastSyncedRaw = -1
            const screenName = monitor.screen?.name ?? ""
            const value = BrightnessPolicy.pickRestoreValue(
                root.lastValidBrightness[screenName],
                monitor.brightness
            )
            if (!Number.isFinite(value)) {
                initialize()
                return
            }
            if (screenName)
                root.lastValidBrightness[screenName] = value
            monitor.ready = false
            monitor.brightness = value
            monitor.ready = true
            syncBrightness()
            if (monitor.isDdc)
                ddcRetryTimer.restart()
        }

        function initialize() {
            monitor.ready = false;
            monitor._lastSyncedRaw = -1;
            if (isDdc) {
                initProc.command = ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"]
            } else if (!root.backlightDetectionReady) {
                return
            } else if (root.backlightDevice.length > 0) {
                // Pass the device as a positional shell argument instead of
                // interpolating it into the command string.
                initProc.command = [
                    "/bin/sh", "-c",
                    "printf '%s %s\\n' \"$(brightnessctl -d \"$1\" g)\" \"$(brightnessctl -d \"$1\" m)\"",
                    "_", root.backlightDevice
                ]
            } else {
                const screenName = monitor.screen?.name ?? ""
                const lastGood = root.lastValidBrightness[screenName]
                const resolved = BrightnessPolicy.resolveHardwareBrightness(Number.NaN, 0, lastGood)
                monitor.brightness = Number.isFinite(resolved.value) ? resolved.value : Number.NaN
                monitor.ready = true
                return
            }
            initProc.running = true;
        }

        function _finishInitialization(): void {
            if (monitor.ready)
                return
            const screenName = monitor.screen?.name ?? ""
            const value = BrightnessPolicy.pickRestoreValue(
                root.lastValidBrightness[screenName],
                monitor.brightness
            )
            if (Number.isFinite(value)) {
                if (screenName)
                    root.lastValidBrightness[screenName] = value
                monitor.brightness = value
                monitor.ready = true
                syncBrightness()
                return
            }
            monitor.ready = true
        }

        readonly property Process initProc: Process {
            property bool startObserved: false
            property bool timedOut: false
            stdout: SplitParser {
                onRead: data => {
                    const parts = data.trim().split(/\s+/)
                    const current = Number(parts[parts.length - 2])
                    const max = Number(parts[parts.length - 1])
                    const screenName = monitor.screen?.name ?? ""
                    const lastGood = root.lastValidBrightness[screenName]
                    const resolved = BrightnessPolicy.resolveHardwareBrightness(current, max, lastGood)
                    if (Number.isFinite(resolved.rawMax))
                        monitor.rawMaxBrightness = resolved.rawMax
                    if (Number.isFinite(resolved.value)) {
                        monitor.brightness = resolved.value
                        if (screenName && resolved.value >= 0.01)
                            root.lastValidBrightness[screenName] = resolved.value
                    }
                    monitor.ready = true
                    if (resolved.restore)
                        monitor.syncBrightness()
                }
            }
            onRunningChanged: {
                if (initProc.running) {
                    initProc.startObserved = false
                    return
                }
                if (initProc.startObserved)
                    return

                initTimeout.stop()
                console.warn("[Brightness] Failed to start monitor brightness initialization")
                monitor._finishInitialization()
            }
            onStarted: {
                initProc.startObserved = true
                initProc.timedOut = false
                initTimeout.restart()
            }
            onExited: {
                initTimeout.stop()
                if (initProc.timedOut)
                    console.warn("[Brightness] Monitor brightness initialization timed out")
                monitor._finishInitialization()
            }
        }

        property var initTimeout: Timer {
            interval: 30000
            repeat: false
            onTriggered: {
                if (!initProc.running)
                    return
                initProc.timedOut = true
                initProc.running = false
            }
        }

        property var ddcRetryTimer: Timer {
            interval: 800
            onTriggered: monitor.syncBrightness()
        }

        // Coalesce animation frames. DDC needs a longer debounce; backlight
        // devices are capped near 30 writes/second so high-range AMD devices do
        // not spawn a process for every QML animation frame. Fixes #188.
        property var setTimer: Timer {
            id: setTimer
            interval: monitor.isDdc ? 300 : 32
            onTriggered: {
                if (!monitor.writePending) return
                monitor.writePending = false
                syncBrightness();
            }
        }

        function syncBrightness() {
            const brightnessValue = monitor.multipliedBrightness
            if (!Number.isFinite(brightnessValue) || brightnessValue < 0.01)
                return
            const rawValueRounded = Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1);
            if (!isDdc && rawValueRounded === monitor._lastSyncedRaw)
                return
            monitor._lastSyncedRaw = rawValueRounded
            if (isDdc) {
                if (!busNum)
                    return
                Quickshell.execDetached(["ddcutil", "-b", busNum, "setvcp", "10", `${rawValueRounded}`]);
            } else if (root.backlightDevice.length > 0) {
                Quickshell.execDetached(["brightnessctl", "-d", root.backlightDevice,
                    "s", `${rawValueRounded}`, "--quiet"]);
            }
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            const screenName = monitor.screen?.name ?? ""
            if (screenName && value >= 0.01)
                root.lastValidBrightness[screenName] = value
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = AntiFlashbangPolicy.bounded(value, 1, .05, 1);
        }

        Component.onCompleted: {
            initialize();
        }

        onBusNumChanged: {
            initialize();
        }
    }

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    // Samples also follow content changes inside the same focused application.
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            readonly property bool samplingEnabled: root.antiFlashbangActive
            readonly property real targetMultiplier: sampler.consecutiveFailures > 2 ? 1 : AntiFlashbangPolicy.multiplier(sampler.lastLightness, {
                threshold: Config.options?.light?.antiFlashbang?.threshold,
                strength: Config.options?.light?.antiFlashbang?.strength,
                minMultiplier: Config.options?.light?.antiFlashbang?.minMultiplier
            })
            onSamplingEnabledChanged: root.getMonitorForScreen(modelData)?.setBrightnessMultiplier(1)
            onTargetMultiplierChanged: {
                if (samplingEnabled && Number.isFinite(sampler.lastLightness))
                    root.getMonitorForScreen(modelData)?.setBrightnessMultiplier(targetMultiplier)
            }
            AntiFlashbangSampler {
                id: sampler
                active: screenScope.samplingEnabled
                outputName: screenScope.modelData.name
                sampleInterval: Config.options?.light?.antiFlashbang?.sampleInterval ?? 500
                sampleScale: Config.options?.light?.antiFlashbang?.sampleScale ?? .10
            }
            Connections {
                enabled: screenScope.samplingEnabled && CompositorService.isHyprland
                target: CompositorService.isHyprland ? Hyprland : null
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name))
                        sampler.request(Config.options?.light?.antiFlashbang?.windowDelay ?? 30)
                    else if (event.name === "workspacev2")
                        sampler.request(Config.options?.light?.antiFlashbang?.workspaceDelay ?? 180)
                }
            }
            Connections {
                enabled: screenScope.samplingEnabled && CompositorService.isNiri
                target: CompositorService.isNiri ? NiriService : null
                function onActiveWindowChanged() {
                    sampler.request(Config.options?.light?.antiFlashbang?.windowDelay ?? 30)
                }
                function onFocusedWorkspaceIdChanged() {
                    sampler.request(Config.options?.light?.antiFlashbang?.workspaceDelay ?? 180)
                }
            }
        }
    }

    // External trigger points

    IpcHandler {
        target: "brightness"

        function increment(): void {
            root.increaseBrightness();
        }

        function decrement(): void {
            root.decreaseBrightness();
        }

        function sleepBegin(): void {
            root.sleepBegin();
        }

        function restoreAfterWake(): void {
            root.restoreAfterWake();
        }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Item {
            GlobalShortcut {
                name: "brightnessIncrease"
                description: "Increase brightness"
                onPressed: root.increaseBrightness()
            }

            GlobalShortcut {
                name: "brightnessDecrease"
                description: "Decrease brightness"
                onPressed: root.decreaseBrightness()
            }
        }
    }
}
