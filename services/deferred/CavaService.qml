pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

// Single cava process shared across all visualizers (waveform/spectrum widgets,
// media player cards, lock screen, background visualizer, etc).
//
// Before this service, every CavaProcess instance spawned its own subprocess
// even though they all read the same PipeWire stream with identical config —
// 2+ cava processes idle-running at ~1.4% CPU each. See #160.
//
// Consumers subscribe()/unsubscribe() to drive lifecycle. While `_subscribers > 0`
// one process runs; bars are broadcast via the `points` property.
//
// Framerate, sensitivity, sample count and channel layout are global, so a
// single process satisfies every consumer with identical output.
Singleton {
    id: root

    property int _legacySubscribers: 0
    property var _sampleRequests: []
    property int _nextSampleRequestId: 1
    property bool _suppressConfigRestart: false
    property int _generationBars: 0
    property int _processBars: 0
    property int _warmBars: 0
    property bool _pendingConfigGeneration: false
    readonly property int _subscribers: _legacySubscribers + _sampleRequests.length
    readonly property bool active: _subscribers > 0

    // SplitParser already gives us a JS array per frame. Keep that identity
    // through the shared service instead of converting every CAVA frame into a
    // typed QML sequence before broadcasting it to consumers.
    property var points: []
    property real normalizationCeiling: 100
    property bool audioSignalActive: false
    signal framePublished()
    // Real PipeWire streams frequently peak in the 20-100 range even though
    // cava's ASCII output can represent 0-1000. Keep silence restrained without
    // flattening ordinary playback to a one-pixel line.
    readonly property real normalizationFloor: 20

    readonly property string configPath: FileUtils.trimFileProtocol(Directories.cache) + "/cava_config.txt"
    readonly property string scriptPath: FileUtils.trimFileProtocol(Directories.scriptPath) + "/cava/generate_config.sh"

    // Mirror CavaProcess's previous config schema reading
    readonly property int requestedFramerate: Math.max(15, Math.min(165,
        Number(Config.options?.appearance?.cava?.framerate ?? 30)))
    readonly property int cfgFramerate: (Config.options?.performance?.lowPower ?? false)
        ? Math.min(24, root.requestedFramerate)
        : root.requestedFramerate
    readonly property int cfgSensitivity: Config.options?.appearance?.cava?.sensitivity ?? 100
    readonly property int cfgBars: Config.options?.appearance?.cava?.bars ?? 0
    readonly property bool cfgStereo: Config.options?.appearance?.cava?.stereo ?? true
    readonly property int requestedBars: {
        let requested = 0
        for (let i = 0; i < root._sampleRequests.length; ++i)
            requested = Math.max(requested, root._sampleRequests[i].bars ?? 0)
        return requested
    }
    readonly property int effectiveBars: {
        let count = root.cfgBars > 0
            ? Math.max(2, Math.round(root.cfgBars))
            : Math.min(320, Math.max(64, root.requestedBars, root._warmBars))
        if (root.cfgStereo && count % 2 !== 0)
            count++
        return count
    }

    readonly property string playerDesktopEntry: {
        if (YtMusic.isPlaying)
            return "mpv ytmusic youtube-music"
        const player = MprisController.activePlayer
        return player?.desktopEntry || player?.identity || "__alis_music_player__"
    }

    function _afterSubscriptionChange(wasActive: bool): void {
        if (!wasActive && root.active) {
            stopDebounce.stop()
            frameClear.stop()
            if (!cavaProc.running)
                root._generateConfig()
        } else if (wasActive && !root.active) {
            stopDebounce.restart()
        }
    }

    function subscribe(requestedBars): int {
        const wasActive = root.active
        if (requestedBars === undefined) {
            root._legacySubscribers++
            root._afterSubscriptionChange(wasActive)
            return 0
        }

        const requestId = root._nextSampleRequestId++
        const previousBars = root.effectiveBars
        const next = root._sampleRequests.slice()
        next.push({
            id: requestId,
            bars: Math.max(0, Math.round(Number(requestedBars) || 0))
        })
        root._suppressConfigRestart = true
        root._sampleRequests = next
        root._suppressConfigRestart = false
        root._afterSubscriptionChange(wasActive)
        if (wasActive && root.active && root.effectiveBars !== previousBars)
            configRestart.restart()
        return requestId
    }

    function updateSubscription(requestId: int, requestedBars): void {
        if (requestId <= 0)
            return
        const previousBars = root.effectiveBars
        const bars = Math.max(0, Math.round(Number(requestedBars) || 0))
        const current=root._sampleRequests.find(request=>request.id===requestId)
        if(!current || current.bars===bars) return
        const next = root._sampleRequests.map(request =>
            request.id === requestId ? { id: request.id, bars: bars } : request)
        root._suppressConfigRestart = true
        root._sampleRequests = next
        root._suppressConfigRestart = false
        if (root.active && root.effectiveBars !== previousBars)
            configRestart.restart()
    }

    function unsubscribe(requestId): void {
        const wasActive = root.active
        const previousBars = root.effectiveBars
        if (requestId === undefined || requestId === 0) {
            root._legacySubscribers = Math.max(0, root._legacySubscribers - 1)
        } else {
            root._suppressConfigRestart = true
            root._sampleRequests = root._sampleRequests.filter(request => request.id !== requestId)
            root._suppressConfigRestart = false
        }
        root._afterSubscriptionChange(wasActive)
        if (wasActive && root.active && root.effectiveBars !== previousBars)
            configRestart.restart()
    }

    // Live config changes — restart cava with new parameters
    onCfgFramerateChanged: if (active) configRestart.restart()
    onCfgSensitivityChanged: if (active) configRestart.restart()
    onCfgStereoChanged: if (active) configRestart.restart()
    onEffectiveBarsChanged: if (active && !root._suppressConfigRestart) configRestart.restart()
    onPlayerDesktopEntryChanged: if (active) sourceRefresh.restart()

    function _publishFrame(parsed): void {
        // Wave renderers stretch short input across their full width. The raw
        // stream contract is one value per configured bar, so reject anything
        // that is not a complete frame for the running process configuration.
        if (parsed.length !== root._processBars)
            return

        // A healthy raw CAVA process emits complete frames continuously,
        // including silence. Refresh the watchdog only after a complete frame;
        // if the selected PipeWire/Pulse source stalls, regenerate the config
        // and resolve the source again instead of leaving an invisible EQ.
        dataWatchdog.restart()

        let peak = 0
        let sum = 0
        let frameChanged = parsed.length !== root.points.length
        for (let i = 0; i < parsed.length; ++i) {
            const value = parsed[i]
            peak = Math.max(peak, value)
            sum += value
            if (!frameChanged && value !== root.points[i])
                frameChanged = true
        }

        const average = sum / parsed.length
        const target = Math.max(root.normalizationFloor, peak * 1.15)
        const nextCeiling = target >= root.normalizationCeiling
            ? target
            : Math.max(root.normalizationFloor, root.normalizationCeiling * 0.995)
        const ceilingRises = nextCeiling > root.normalizationCeiling

        // Canvas.Threaded may paint as soon as either binding changes. Raise
        // the ceiling before stronger points, and lower it only after weaker
        // points, so no paint can pair a loud frame with a stale low ceiling.
        if (ceilingRises)
            root.normalizationCeiling = nextCeiling

        if (frameChanged)
            root.points = parsed

        if (!ceilingRises)
            root.normalizationCeiling = nextCeiling

        if (peak >= 2 || average >= 0.35) {
            signalRelease.stop()
            root.audioSignalActive = true
        } else if (root.audioSignalActive && !signalRelease.running) {
            signalRelease.restart()
        }
        root.framePublished()
    }

    property bool _pendingRestart: false

    function _generateConfig(): void {
        if (!root.active)
            return
        if (configGen.running) {
            root._pendingConfigGeneration = true
            return
        }
        root._generationBars = root.effectiveBars
        configGen.running = true
    }

    Connections {
        target: MprisController
        function onTrackChanged(): void {
            if (root.active)
                sourceRefresh.restart()
        }
    }

    Connections {
        target: YtMusic
        function onCurrentVideoIdChanged(): void {
            if (root.active)
                sourceRefresh.restart()
        }
    }

    Timer {
        id: sourceRefresh
        interval: 800
        repeat: false
        onTriggered: if (root.active) configRestart.restart()
    }

    Timer {
        id: signalRelease
        interval: 1800
        repeat: false
        onTriggered: root.audioSignalActive = false
    }

    // Port Serpantinum's no-data recovery idea into the shared Hadalis service.
    // Zero-amplitude frames still refresh this timer; it only fires when the
    // process itself stops producing valid frames while a consumer is active.
    Timer {
        id: dataWatchdog
        interval: 2400
        repeat: false
        onTriggered: {
            if (root.active && cavaProc.running)
                configRestart.restart()
        }
    }

    Timer {
        id: frameClear
        interval: 2600
        repeat: false
        onTriggered: {
            if (!root.active && !cavaProc.running) {
                root.points = []
                root.normalizationCeiling = root.normalizationFloor
            }
        }
    }

    Timer {
        id: configRestart
        interval: 300
        onTriggered: {
            if (configGen.running) {
                root._pendingConfigGeneration = true
            } else if (cavaProc.running) {
                root._pendingRestart = true
                cavaProc.running = false
            } else if (root.active) {
                root._generateConfig()
            }
        }
    }

    // Defer process teardown so brief unsubscribe/subscribe cycles
    // (e.g. panel close + immediate reopen) don't churn the subprocess.
    Timer {
        id: stopDebounce
        interval: 800
        repeat: false
        onTriggered: {
            if (!root.active) {
                root._pendingRestart = false
                root._pendingConfigGeneration = false
                configGen.running = false
                cavaProc.running = false
                root._warmBars = 0
                signalRelease.restart()
                frameClear.restart()
            }
        }
    }

    Process {
        id: configGen
        running: false
        command: ["/usr/bin/bash", root.scriptPath, root.configPath,
            String(root.cfgFramerate), String(root.cfgSensitivity),
            String(root._generationBars), String(root.cfgStereo),
            root.playerDesktopEntry]
        onExited: (code, status) => {
            if (root._pendingConfigGeneration && root.active) {
                root._pendingConfigGeneration = false
                root._generateConfig()
            } else if (code === 0 && root.active) {
                root._processBars = root._generationBars
                root._warmBars = root._generationBars
                cavaProc.running = true
            } else if (root.active) {
                signalRelease.restart()
                frameClear.restart()
            }
        }
    }

    Process {
        id: cavaProc
        running: false
        command: ["cava", "-p", root.configPath]
        onRunningChanged: {
            if (running) {
                dataWatchdog.restart()
            } else {
                dataWatchdog.stop()
                if (root._pendingRestart && root.active) {
                    root._pendingRestart = false
                    root._generateConfig()
                } else if (root.active) {
                    signalRelease.restart()
                    sourceRefresh.restart()
                } else if (!root.active) {
                    signalRelease.restart()
                    frameClear.restart()
                }
            }
        }
        stdout: SplitParser {
            onRead: data => {
                // SplitParser already gives us one frame-sized string. Reuse
                // the split array itself as the numeric frame instead of
                // allocating a second parsed[] array at CAVA framerate.
                const parsed = data.split(";")
                let writeIndex = 0
                for (let i = 0; i < parsed.length; ++i) {
                    const value = parseFloat(parsed[i])
                    if (!isNaN(value))
                        parsed[writeIndex++] = value
                }
                parsed.length = writeIndex
                root._publishFrame(parsed)
            }
        }
    }
}
