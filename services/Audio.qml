pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services.deferred
import "root:modules/common/functions/audioRouting.js" as AudioRouting

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: sink?.ready ?? rawSink?.ready ?? false
    readonly property PwNode rawSink: Pipewire.defaultAudioSink
    property PwNode _pendingSink: null
    readonly property PwNode defaultSink: root._pendingSink ?? rawSink
    property PwNode sink: root.resolveControllableSink(defaultSink)
    property PwNode source: Pipewire.defaultAudioSource

    // When QS catches up and rawSink changes, clear the pending override
    onRawSinkChanged: {
        if (root._pendingSink) root._pendingSink = null
    }
    readonly property real hardMaxValue: 2.00
    property string audioTheme: Config.options?.sounds?.theme ?? "freedesktop"
    property real value: sink?.audio?.volume ?? rawSink?.audio?.volume ?? 0
    // A device-route-level change can be invisible to PwNode.audio.volume.
    // OSD prefers a verified wpctl read-back when the QML value stays stale.
    property real _sinkSampleVolume: NaN
    property string _sinkSampleTarget: ""
    property int _sinkWriteGeneration: 0
    property int _sinkReadGeneration: 0
    property string _sinkReadTarget: ""
    readonly property real osdSinkVolume: root._sinkSampleTarget === root._sinkControlTarget()
        && Number.isFinite(root._sinkSampleVolume) ? root._sinkSampleVolume : root.value
    property bool micBeingAccessed: (Pipewire.links?.values ?? []).some(link =>
        !(link?.source?.isStream ?? true)
            && !(link?.source?.isSink ?? true)
            && (link?.target?.isStream ?? false)
            && !root.isInternalMicMonitorNode(link?.target)
    )

    function isInternalMicMonitorNode(node): bool {
        if (!node)
            return false
        const props = node.properties ?? ({})
        const rawName = String(node.name ?? "").toLowerCase()
        const nodeName = String(props["node.name"] ?? node.name ?? "").toLowerCase()
        const appName = String(props["application.name"] ?? "").toLowerCase()
        const mediaName = String(props["media.name"] ?? "").toLowerCase()
        return rawName === "alis-mic-meter"
            || nodeName === "alis-mic-meter"
            || appName === "alis-mic-meter"
            || mediaName === "alis mic meter"
    }

    property bool _micMuted: false
    property bool micStateKnown: false
    property int micStateRevision: 0
    // Tracked explicitly rather than bound to source.audio.volume: setSourceVolume()
    // assigns to this imperatively, which would destroy a declarative binding for
    // good — after the first mic adjustment the shell would stop seeing volume
    // changes made anywhere else (pavucontrol, another app).
    property real _micVolume: 0
    readonly property bool micMuted: _micMuted
    readonly property real micVolume: _micVolume

    Connections {
        target: root.source?.audio ?? null
        function onVolumeChanged(): void {
            root._micVolume = root.source?.audio?.volume ?? 0
        }
        function onMutedChanged(): void {
            root._refreshMicState()
        }
    }

    onSourceChanged: {
        root._micVolume = root.source?.audio?.volume ?? 0
        _refreshMicState()
    }

    function friendlyDeviceName(node) {
        return node ? (node.nickname || node.description || Translation.tr("Unknown")) : Translation.tr("Unknown");
    }
    function appNodeDisplayName(node) {
        if (!node) return Translation.tr("Unknown");
        return (node.properties?.["application.name"] || node.description || node.name || Translation.tr("Unknown"))
    }

    function resolveControllableSink(node) {
        return AudioRouting.resolveSink(node, Pipewire.nodes.values, Pipewire.links.values,
            [root._nativeEffectsOutput, root._flatpakEffectsOutput])
    }

    readonly property bool _effectsOutputWanted: AudioRouting.isEffectsSink(root.defaultSink)
    property string _nativeEffectsOutput: ""
    property string _flatpakEffectsOutput: ""
    FileView {
        id: nativeEffectsConfig
        path: root._effectsOutputWanted ? Directories.configPath + "/easyeffects/db/easyeffectsrc" : ""
        printErrors: false
        watchChanges: root._effectsOutputWanted
        onLoaded: root._nativeEffectsOutput = AudioRouting.outputDevice(text())
        onFileChanged: reload()
        onLoadFailed: root._nativeEffectsOutput = ""
    }
    FileView {
        id: flatpakEffectsConfig
        path: root._effectsOutputWanted ? Directories.homePath + "/.var/app/com.github.wwmm.easyeffects/config/easyeffects/db/easyeffectsrc" : ""
        printErrors: false
        watchChanges: root._effectsOutputWanted
        onLoaded: root._flatpakEffectsOutput = AudioRouting.outputDevice(text())
        onFileChanged: reload()
        onLoadFailed: root._flatpakEffectsOutput = ""
    }

    function _sinkControlTarget(): string {
        const id = Number(root.sink?.id ?? 0)
        return Number.isFinite(id) && id > 0 ? String(id) : "@DEFAULT_AUDIO_SINK@"
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => {
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    function _isExcludedVisualizerNode(node): bool {
        if (!node || Boolean(node.audio?.muted))
            return true
        const props = node.properties ?? {}
        if (String(props["pulse.corked"] ?? "").toLowerCase() === "true")
            return true
        const binary = String(props["application.process.binary"] ?? "").toLowerCase()
        const appName = String(props["application.name"] ?? "").toLowerCase()
        const nodeName = String(props["node.name"] ?? node.name ?? "").toLowerCase()
        const appId = String(props["application.id"] ?? props["pipewire.access.portal.app_id"] ?? "").toLowerCase()
        const mediaRole = String(props["media.role"] ?? "").toLowerCase()

        const excludedApps = [
            "cava", "pavucontrol", "pwvucontrol", "helvum", "qpwgraph", "carla",
            "easyeffects", "jamesdsp", "sonusmix", "quickshell", "qs",
            "alis-mic-meter",
            "discord", "vesktop", "webrtc", "teams", "zoom", "slack",
            "telegram-desktop", "element", "speech-dispatcher", "sd_dummy"
        ]
        for (let i = 0; i < excludedApps.length; ++i) {
            const tok = excludedApps[i]
            if (binary === tok || appName === tok || nodeName === tok
                    || appName.indexOf(tok) >= 0)
                return true
        }
        if (appId === "com.github.wwmm.easyeffects" || appId === "me.timschneeberger.jdsp4linux")
            return true
        if (["event", "notification", "bell", "alert", "a11y", "test", "communication", "phone"].includes(mediaRole))
            return true
        return false
    }

    readonly property var activeOutputAppNodes: {
        const nodes = root.outputAppNodes ?? []
        const links = Pipewire.links?.values ?? []
        const active = []
        for (let i = 0; i < nodes.length; ++i) {
            const node = nodes[i]
            if (root._isExcludedVisualizerNode(node))
                continue
            let linked = false
            for (let j = 0; j < links.length; ++j) {
                const link = links[j]
                if (!link || link.source !== node || link.state !== PwLinkState.Active)
                    continue
                const targetName = String(link.target?.name ?? "").toLowerCase()
                const targetBin = String(link.target?.properties?.["application.process.binary"] ?? "").toLowerCase()
                if (targetName === "cava" || targetBin === "cava")
                    continue
                linked = true
                break
            }
            if (linked)
                active.push(node)
        }
        return active
    }
    readonly property bool hasActivePlayback: (root.activeOutputAppNodes?.length ?? 0) > 0
    readonly property string activePlaybackSignature: {
        const nodes = root.activeOutputAppNodes ?? []
        if (nodes.length === 0)
            return ""
        const keys = []
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i]
            keys.push(String(n?.id ?? 0) + ":" + String(n?.properties?.["object.serial"] ?? ""))
        }
        keys.sort()
        return keys.join(",")
    }

    // Signals
    signal sinkProtectionTriggered(string reason);
    // Immediate IPC/slider feedback even when PipeWire omits a volume event.
    signal sinkControlRequested();

    // Controls
    function toggleMute() {
        if (!root.sink?.audio) return;
        root.sink.audio.muted = !root.sink.audio.muted
        root.sinkControlRequested()
    }

    function setSourceVolume(target: real): void {
        const clamped = Math.max(0, Math.min(root.hardMaxValue, target))
        root._micVolume = clamped
        root._queueSourceVolume(clamped)
    }

    function setMicMuted(muted: bool): void {
        const shouldMute = Boolean(muted)
        root._micMuted = shouldMute
        const muteVal = shouldMute ? "1" : "0"
        // Mute every source device (hardware + virtual like EasyEffects)
        // so apps reading directly from hardware are also silenced.
        for (const dev of root.inputDevices) {
            const nodeId = Number(dev.id ?? 0)
            if (Number.isFinite(nodeId) && nodeId > 0)
                Quickshell.execDetached(["wpctl", "set-mute", String(nodeId), muteVal])
        }
        wpctlSetMicMute.exec(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", muteVal])
    }

    function toggleMicMute() {
        root.setMicMuted(!root._micMuted)
    }

    function _isVirtualSource(dev): bool {
        if (!dev)
            return true
        const props = dev.properties ?? {}
        const nodeName = String(props["node.name"] ?? dev.name ?? "")
        const appId = String(props["application.id"] ?? "")
        const isVirtual = String(props["node.virtual"] ?? "false") === "true"
        return nodeName === "easyeffects_source"
            || appId === "com.github.wwmm.easyeffects"
            || isVirtual
    }

    function _hardwareSourceId(): int {
        if (root.source && !root._isVirtualSource(root.source)) {
            const defaultId = Number(root.source.id ?? 0)
            if (Number.isFinite(defaultId) && defaultId > 0)
                return defaultId
        }
        for (const dev of root.inputDevices) {
            if (root._isVirtualSource(dev))
                continue
            const id = Number(dev.id ?? 0)
            if (Number.isFinite(id) && id > 0) return id
        }
        return 0
    }

    function _refreshMicState(): void {
        if (_wpctlGetMicState.running)
            return
        const hwId = root._hardwareSourceId()
        const target = hwId > 0 ? String(hwId) : "@DEFAULT_AUDIO_SOURCE@"
        _wpctlGetMicState.exec(["wpctl", "get-volume", target])
    }

    Process {
        id: wpctlSetDefaultDevice
        command: ["wpctl", "set-default", "0"]
        onExited: {
            // After switching default sink, immediately nudge volume via wpctl so
            // USB/device-route sinks (e.g. USB mic used as output) get their volume
            // state initialised in PipeWire without requiring pavucontrol interaction.
            root._queueSinkVolume(root.sink?.audio?.volume ?? 0.5)
        }
    }

    function _invalidateSinkSample(): void {
        root._sinkSampleTarget = ""
        root._sinkSampleVolume = NaN
        root._sinkWriteGeneration++
        sinkVolumeSampleTimer.stop()
    }

    property real _queuedSinkVolume: 0
    property string _queuedSinkTarget: ""
    property bool _sinkVolumePending: false
    property real _queuedSourceVolume: 0
    property bool _sourceVolumePending: false

    function _queueSinkVolume(value: real): void {
        root._invalidateSinkSample()
        root._queuedSinkVolume = value
        root._queuedSinkTarget = root._sinkControlTarget()
        root._sinkVolumePending = true
        if (!wpctlSetSinkVolume.running && !sinkVolumeDispatch.running)
            sinkVolumeDispatch.start()
    }

    function _queueSourceVolume(value: real): void {
        root._queuedSourceVolume = value
        root._sourceVolumePending = true
        if (!wpctlSetSourceVolume.running && !sourceVolumeDispatch.running)
            sourceVolumeDispatch.start()
    }

    Timer {
        id: sinkVolumeDispatch
        interval: 16
        onTriggered: {
            if (wpctlSetSinkVolume.running || !root._sinkVolumePending)
                return
            root._sinkVolumePending = false
            wpctlSetSinkVolume.command = ["wpctl", "set-volume", root._queuedSinkTarget, String(root._queuedSinkVolume)]
            wpctlSetSinkVolume.running = true
        }
    }

    Timer {
        id: sourceVolumeDispatch
        interval: 16
        onTriggered: {
            if (wpctlSetSourceVolume.running || !root._sourceVolumePending)
                return
            root._sourceVolumePending = false
            wpctlSetSourceVolume.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", String(root._queuedSourceVolume)]
            wpctlSetSourceVolume.running = true
        }
    }

    // Sink volume via wpctl — fallback for devices whose volume control lives at
    // the PipeWire device-route level and is not reachable through the QML binding.
    Process {
        id: wpctlSetSinkVolume
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "1.0"]
        onExited: {
            if (root._sinkVolumePending)
                sinkVolumeDispatch.restart()
            else
                sinkVolumeSampleTimer.restart()
        }
    }

    // Serialize relative steps so held keys and alternating presses cannot drop
    // input or race each other. Each step keeps the device selected at the press.
    property var _sinkSteps: []
    function _queueSinkStep(direction: string): void {
        root._invalidateSinkSample()
        root.sinkControlRequested()
        root._sinkSteps.push({target: root._sinkControlTarget(), direction: direction})
        root._dispatchSinkStep()
    }
    function _dispatchSinkStep(): void {
        if (wpctlSinkStep.running || root._sinkSteps.length === 0)
            return
        const step = root._sinkSteps.shift()
        wpctlSinkStep.exec(["wpctl", "set-volume", step.target, step.direction])
    }
    Process {
        id: wpctlSinkStep
        onExited: Qt.callLater(() => {
            root._dispatchSinkStep()
            if (!wpctlSinkStep.running && root._sinkSteps.length === 0)
                sinkVolumeSampleTimer.restart()
        })
    }

    // Coalesce rapid key repeats; reject observations from older writes
    // or a different output. This does not change the default sink.
    Timer {
        id: sinkVolumeSampleTimer
        interval: 80
        onTriggered: {
            if (wpctlSinkStep.running || root._sinkSteps.length > 0
                    || wpctlSetSinkVolume.running || root._sinkVolumePending
                    || _rampTimerInternal.running || wpctlGetSinkVolume.running) {
                restart()
                return
            }
            root._sinkReadTarget = root._sinkControlTarget()
            root._sinkReadGeneration = root._sinkWriteGeneration
            wpctlGetSinkVolume.exec(["wpctl", "get-volume", root._sinkReadTarget])
        }
    }
    Process {
        id: wpctlGetSinkVolume
        stdout: StdioCollector { id: sinkVolumeSampleCollector }
        onExited: (exitCode, _exitStatus) => {
            if (exitCode !== 0 || root._sinkReadGeneration !== root._sinkWriteGeneration
                    || root._sinkReadTarget !== root._sinkControlTarget())
                return
            const result = String(sinkVolumeSampleCollector.text ?? "")
            const match = result.match(/Volume:\s*([0-9]*\.?[0-9]+)/i)
            if (!match) return
            const volume = Number(match[1])
            if (!Number.isFinite(volume)) return
            root._sinkSampleTarget = root._sinkReadTarget
            root._sinkSampleVolume = Math.max(0, Math.min(root.hardMaxValue, volume))
        }
    }

    Process {
        id: wpctlSetMicMute
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "1"]
        onExited: root._refreshMicState()
    }

    Process {
        id: wpctlSetSourceVolume
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", "1.0"]
        onExited: {
            if (root._sourceVolumePending)
                sourceVolumeDispatch.restart()
            else
                root._refreshMicState()
        }
    }

    Process {
        id: _wpctlGetMicState
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector { id: _micStateCollector }
        onExited: (exitCode, _exitStatus) => {
            if (exitCode !== 0) return
            const out = (_micStateCollector.text?.trim() ?? "")
            if (!out.length) return
            root._micMuted = out.toUpperCase().includes("MUTED")
            const match = out.match(/Volume:\s*([0-9]*\.?[0-9]+)/i)
            if (match && match[1] !== undefined) {
                const parsed = Number(match[1])
                if (Number.isFinite(parsed))
                    root._micVolume = Math.max(0, Math.min(root.hardMaxValue, parsed))
            }
            root.micStateKnown = true
            root.micStateRevision += 1
        }
    }

    // Set sink volume safely. When protection is enabled, large jumps are rejected as "Illegal increment".
    // To keep UX consistent with brightness (click anywhere on slider), we ramp in small steps.
    // The queued wpctl path also works while Quickshell is rebuilding its node bindings.
    function setSinkVolume(target: real): void {
        const maxAllowed = (Config.options?.audio?.protection?.maxAllowed ?? 100) / 100;
        const clamped = Math.max(0, Math.min(Math.min(maxAllowed, root.hardMaxValue), target));

        const protectionEnabled = (Config.options?.audio?.protection?.enable ?? false);
        root.sinkControlRequested()
        if (!protectionEnabled) {
            root._queueSinkVolume(clamped)
            return;
        }

        root._rampTarget = clamped;
        root._rampTimer.restart();
    }

    // Ramp helper (prevents "Illegal increment" when user clicks far away on slider)
    property real _rampTarget: 0
    property alias _rampTimer: _rampTimerInternal
    Timer {
        id: _rampTimerInternal
        interval: 16
        repeat: true
        running: false
        onTriggered: {
            if (!root.sink?.audio) {
                root._queueSinkVolume(root._rampTarget)
                running = false;
                return;
            }

            const protectionEnabled = (Config.options?.audio?.protection?.enable ?? false);
            if (!protectionEnabled) {
                root._queueSinkVolume(root._rampTarget)
                running = false;
                return;
            }

            const maxStep = (Config.options?.audio?.protection?.maxAllowedIncrease ?? 10) / 100;
            const step = Math.max(0.005, maxStep * 0.8); // Stay below protection threshold
            const current = root.sink.audio.volume;
            const diff = root._rampTarget - current;
            if (Math.abs(diff) <= step) {
                root._queueSinkVolume(root._rampTarget)
                running = false;
                return;
            }
            root._queueSinkVolume(current + Math.sign(diff) * step)
        }
    }

    function incrementVolume() {
        root._queueSinkStep("2%+")
    }

    function decrementVolume() {
        root._queueSinkStep("2%-")
    }

    function setDefaultNode(node, isSink: bool): void {
        if (!node) return

        if (isSink) {
            root._pendingSink = node
            Pipewire.preferredDefaultAudioSink = node;
        } else {
            Pipewire.preferredDefaultAudioSource = node;
        }

        const nodeId = Number(node.id ?? 0)
        if (!Number.isFinite(nodeId) || nodeId <= 0 || wpctlSetDefaultDevice.running)
            return

        wpctlSetDefaultDevice.command = ["wpctl", "set-default", String(nodeId)]
        wpctlSetDefaultDevice.running = true
    }

    function setDefaultSink(node) {
        root.setDefaultNode(node, true)
    }

    function setDefaultSource(node) {
        root.setDefaultNode(node, false)
    }

    // Internals
    PwObjectTracker {
        objects: {
            const nodes = [rawSink, sink, source]
            const outputNodes = root.outputAppNodes ?? []
            for (let i = 0; i < outputNodes.length; i++)
                nodes.push(outputNodes[i])
            const inputNodes = root.inputAppNodes ?? []
            for (let i = 0; i < inputNodes.length; i++)
                nodes.push(inputNodes[i])
            const links = Pipewire.links?.values ?? []
            for (let i = 0; i < links.length; i++) {
                const link = links[i]
                if (link?.source?.isStream && link?.source?.isSink)
                    nodes.push(link)
            }

            let writeCount = 0
            for (let i = 0; i < nodes.length; i++) {
                const node = nodes[i]
                if (node)
                    nodes[writeCount++] = node
            }
            nodes.length = writeCount
            return nodes
        }
    }

    // Reset protection state and stop any in-flight ramp when sink changes so
    // the new sink's initial volume isn't compared against the old sink's level
    // and we don't apply a stale ramp target to the wrong device.
    onSinkChanged: {
        root._invalidateSinkSample()
        _sinkProtectionConn.lastReady = false
        _sinkProtectionConn.lastVolume = 0
        _rampTimerInternal.running = false
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged(): void {
            root._sinkSampleTarget = ""
            root._sinkSampleVolume = NaN
        }
    }

    Connections { // Protection against sudden volume changes
        id: _sinkProtectionConn
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!(Config.options?.audio?.protection?.enable ?? false)) return;
            if (!sink?.ready || !sink?.audio) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = (Config.options?.audio?.protection?.maxAllowedIncrease ?? 10) / 100; 
            const maxAllowed = (Config.options?.audio?.protection?.maxAllowed ?? 99) / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                root._queueSinkVolume(lastVolume)
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
                return
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                lastVolume = Math.min(lastVolume, maxAllowed)
                root._queueSinkVolume(lastVolume)
                return
            }
            lastVolume = newVolume;
        }
    }

    // Event catalog: eventId → freedesktop sound name used when the user
    // hasn't overridden it via sounds.events.<id> in config
    readonly property var soundEvents: ({
        notification: "message-new-instant",
        notificationCritical: "dialog-warning",
        batteryLow: "dialog-warning",
        batteryCritical: "suspend-error",
        batteryFull: "complete",
        powerPlug: "power-plug",
        powerUnplug: "power-unplug",
        pomodoroDone: "alarm-clock-elapsed",
        timerDone: "alarm-clock-elapsed"
    })

    // Sound names available in the current theme (feeds settings pickers)
    property var themeSounds: []
    onAudioThemeChanged: themeSoundsProc.running = true
    Process {
        id: themeSoundsProc
        command: ["/bin/sh", "-c", `ls /usr/share/sounds/${root.audioTheme}/stereo/ 2>/dev/null | sed 's/\\.[^.]*$//' | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: root.themeSounds = text.trim().length > 0 ? text.trim().split("\n") : []
        }
    }

    // Play a shell event sound honoring the user's per-event override:
    // "" = theme default; bare name = that sound from the current theme;
    // absolute path or file:// = play the file directly
    function playEvent(eventId) {
        const override = Config.options?.sounds?.events?.[eventId] ?? "";
        if (override.startsWith("/") || override.startsWith("file://")) {
            const volume = Config.options?.sounds?.volume ?? 0.5;
            const path = override.startsWith("file://") ? override.slice(7) : override;
            Quickshell.execDetached(["/usr/bin/pw-play", "--volume", volume.toString(), path]);
            return;
        }
        playSystemSound(override.length > 0 ? override : (root.soundEvents[eventId] ?? "bell"));
    }

    function playSystemSound(soundName) {
        const volume = Config.options?.sounds?.volume ?? 0.5;
        const base = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}`;
        const q = s => `'${s.replace(/'/g, `'\\''`)}'`;
        // pw-play volume range: 0.0 to 1.0. Try .oga then .ogg — firing
        // both blindly double-played on themes shipping both extensions.
        Quickshell.execDetached(["/bin/sh", "-c",
            `pw-play --volume ${volume} ${q(base + ".oga")} 2>/dev/null || pw-play --volume ${volume} ${q(base + ".ogg")}`]);
    }

    Component.onCompleted: {
        _refreshMicState();
        themeSoundsProc.running = true;
    }

    // IPC handlers for external control (keybinds, etc.)
    IpcHandler {
        target: "audio"

        function volumeUp(): void {
            root.incrementVolume();
        }

        function volumeDown(): void {
            root.decrementVolume();
        }

        function mute(): void {
            root.toggleMute();
        }

        function playEvent(event: string): void {
            root.playEvent(event);
        }

        function micMute(): void {
            root.toggleMicMute();
        }
    }
}
