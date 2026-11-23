pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property bool isRecording: false
    property int recorderPid: 0
    property string requestedAudioMode: "none"
    property string activeAudioMode: "none"
    property bool audioFallback: false
    property bool hasAudioMetadata: false
    property bool hasStoredAudioMode: false
    property bool hasStoredSystemAudioSource: false
    property bool hasStoredMicrophoneSource: false
    property string legacyAudioSource: ""
    readonly property string configuredAudioMode: root.hasStoredAudioMode
        ? root.normalizeAudioMode(Config.options?.screenRecord?.audioMode ?? "system")
        : root.audioModeFromLegacySource(root.legacyAudioSource)
    readonly property string configuredSystemAudioSource: {
        const configured = String(Config.options?.screenRecord?.systemAudioSource ?? "")
        if (root.hasStoredSystemAudioSource)
            return configured
        return root.legacyAudioSource.endsWith(".monitor") ? root.legacyAudioSource : configured
    }
    readonly property string configuredMicrophoneSource: {
        const configured = String(Config.options?.screenRecord?.microphoneSource ?? "")
        if (root.hasStoredMicrophoneSource)
            return configured
        return root.legacyAudioSource.length > 0 && !root.legacyAudioSource.endsWith(".monitor")
            ? root.legacyAudioSource : configured
    }
    readonly property string effectiveAudioMode: isRecording && hasAudioMetadata ? activeAudioMode : configuredAudioMode
    readonly property string recorderStatusPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/alis/recorder-status.json"
    // Timestamp (ms since epoch) when recording started, 0 when not recording
    property real recordingStartTime: 0
    // Elapsed seconds since recording started, updated every second
    property int elapsedSeconds: 0

    function normalizeAudioMode(mode: string): string {
        switch (mode) {
        case "none":
        case "system":
        case "microphone":
        case "both":
            return mode
        default:
            return "system"
        }
    }

    function audioModeFromLegacySource(source: string): string {
        if (source.length > 0 && !source.endsWith(".monitor"))
            return "microphone"
        return "system"
    }

    function setConfiguredAudioMode(mode: string): void {
        Config.setNestedValue("screenRecord.audioMode", root.normalizeAudioMode(mode))
        root.hasStoredAudioMode = true
    }

    function setConfiguredSystemAudioSource(source): void {
        Config.setNestedValue("screenRecord.systemAudioSource", String(source ?? ""))
        root.hasStoredSystemAudioSource = true
    }

    function setConfiguredMicrophoneSource(source): void {
        Config.setNestedValue("screenRecord.microphoneSource", String(source ?? ""))
        root.hasStoredMicrophoneSource = true
    }

    function resetStoredAudioConfig(): void {
        root.hasStoredAudioMode = false
        root.hasStoredSystemAudioSource = false
        root.hasStoredMicrophoneSource = false
        root.legacyAudioSource = ""
    }

    function parseStoredAudioConfig(payloadText: string): void {
        try {
            const payload = JSON.parse(payloadText.trim() || "{}")
            const screenRecord = payload?.screenRecord
            if (screenRecord === null || typeof screenRecord !== "object" || Array.isArray(screenRecord)) {
                root.resetStoredAudioConfig()
                return
            }
            root.hasStoredAudioMode = Object.prototype.hasOwnProperty.call(screenRecord, "audioMode")
            root.hasStoredSystemAudioSource = Object.prototype.hasOwnProperty.call(screenRecord, "systemAudioSource")
            root.hasStoredMicrophoneSource = Object.prototype.hasOwnProperty.call(screenRecord, "microphoneSource")
            root.legacyAudioSource = typeof screenRecord.audioSource === "string"
                ? screenRecord.audioSource : ""
        } catch (error) {
            root.resetStoredAudioConfig()
        }
    }

    function refreshStoredAudioConfig(): void {
        if (Config.ready && !storedConfigProcess.running)
            storedConfigProcess.running = true
    }

    function resetAudioMetadata(): void {
        requestedAudioMode = "none"
        activeAudioMode = "none"
        audioFallback = false
        hasAudioMetadata = false
    }

    function loadAudioMetadata(): void {
        if (!metadataProcess.running)
            metadataProcess.running = true
    }

    onIsRecordingChanged: {
        if (isRecording) {
            recordingStartTime = Date.now()
            elapsedSeconds = 0
        } else {
            recordingStartTime = 0
            elapsedSeconds = 0
            recorderPid = 0
            resetAudioMetadata()
        }
    }

    function refreshStatus() {
        if (!checkProcess.running)
            checkProcess.running = true
    }

    readonly property int idlePollIntervalMs:
        (Config.options?.performance?.lowPower ?? false) ? 30000 : 15000

    property var _fastDemandOwners: ({})
    property int fastDemandCount: 0
    readonly property bool fastStatusDemand: root.fastDemandCount > 0

    function setFastStatusDemand(owner: string, active: bool): void {
        const demandOwner = String(owner ?? "").trim()
        if (demandOwner.length === 0)
            return

        const current = root._fastDemandOwners
        const alreadyActive = current[demandOwner] === true
        if (alreadyActive === active)
            return

        const next = ({})
        const keys = Object.keys(current)
        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i]
            if (current[key] === true)
                next[key] = true
        }
        if (active)
            next[demandOwner] = true
        else
            delete next[demandOwner]

        root._fastDemandOwners = next
        root.fastDemandCount = Object.keys(next).length
    }

    onFastStatusDemandChanged: {
        if (root.fastStatusDemand && Config.ready)
            Qt.callLater(root.refreshStatus)
    }

    // External recorders are uncommon, and in-shell recording actions already
    // schedule a fast bounded recheck. Avoid spawning pgrep every five seconds
    // for the entire desktop session just to discover an external recorder.
    Timer {
        id: idlePollTimer
        interval: root.idlePollIntervalMs
        running: Config.ready && !root.isRecording && !root.fastStatusDemand
        repeat: true
        onTriggered: root.refreshStatus()
    }

    // Visible recorder controls need quicker reconciliation, especially for
    // externally started/stopped wf-recorder instances. Keep this demand-owned
    // so the shell does not pay a permanent 1s pgrep cost.
    Timer {
        id: fastPollTimer
        interval: 1000
        running: Config.ready
            && !root.isRecording
            && root.fastStatusDemand
            && !quickCheckTimer.running
        repeat: true
        onTriggered: root.refreshStatus()
    }

    // Active poll: 1s tick while recording (elapsed counter + stop detection)
    Timer {
        id: activePollTimer
        interval: 1000
        running: root.isRecording
        repeat: true
        onTriggered: {
            if (root.recordingStartTime > 0)
                root.elapsedSeconds = Math.floor((Date.now() - root.recordingStartTime) / 1000)
            root.refreshStatus()
        }
    }

    // Quick recheck after a recording action (start/stop) to catch state change fast
    function scheduleQuickCheck(): void {
        quickCheckTimer.initialRecordingState = root.isRecording
        quickCheckTimer.attemptsRemaining = 6
        quickCheckTimer.restart()
    }
    Timer {
        id: quickCheckTimer
        property bool initialRecordingState: false
        property int attemptsRemaining: 0
        interval: 350
        repeat: true
        onTriggered: {
            root.refreshStatus()
            attemptsRemaining = Math.max(0, attemptsRemaining - 1)
            if (root.isRecording !== initialRecordingState || attemptsRemaining <= 0)
                stop()
        }
    }

    Connections {
        target: Config
        function onReadyChanged(): void {
            if (Config.ready)
                Qt.callLater(root.refreshStoredAudioConfig)
        }
    }

    Component.onCompleted: {
        Qt.callLater(root.refreshStatus)
        Qt.callLater(root.refreshStoredAudioConfig)
    }

    Process {
        id: storedConfigProcess
        property bool startObserved: false
        property bool _exited: false
        property int _exitCode: -1
        property bool _stdoutDone: false
        property bool _finalized: false
        command: ["/usr/bin/cat", Config.filePath]
        function _finalizeStoredConfig(): void {
            if (_finalized)
                return
            _finalized = true
            storedConfigFlushTimer.stop()
            if (_exitCode === 0)
                root.parseStoredAudioConfig(storedConfigCollector.text)
            else
                root.resetStoredAudioConfig()
        }
        stdout: StdioCollector {
            id: storedConfigCollector
            onStreamFinished: {
                storedConfigProcess._stdoutDone = true
                if (storedConfigProcess._exited)
                    storedConfigProcess._finalizeStoredConfig()
            }
        }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (storedConfigProcess.running) {
                storedConfigProcess.startObserved = false
                storedConfigProcess._exited = false
                storedConfigProcess._exitCode = -1
                storedConfigProcess._stdoutDone = false
                storedConfigProcess._finalized = false
                storedConfigFlushTimer.stop()
                return
            }
            if (storedConfigProcess.startObserved)
                return
            root.resetStoredAudioConfig()
        }
        onStarted: storedConfigProcess.startObserved = true
        onExited: (exitCode, exitStatus) => {
            storedConfigProcess._exited = true
            storedConfigProcess._exitCode = exitCode
            if (storedConfigProcess._stdoutDone)
                storedConfigProcess._finalizeStoredConfig()
            else
                storedConfigFlushTimer.restart()
        }
    }

    Timer {
        id: storedConfigFlushTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (storedConfigProcess._exited && !storedConfigProcess._finalized)
                storedConfigProcess._finalizeStoredConfig()
        }
    }

    Process {
        id: metadataProcess
        property bool startObserved: false
        property bool _exited: false
        property int _exitCode: -1
        property bool _stdoutDone: false
        property bool _finalized: false
        command: ["/usr/bin/cat", root.recorderStatusPath]
        function _finalizeMetadata(): void {
            if (_finalized)
                return
            _finalized = true
            metadataFlushTimer.stop()
            if (_exitCode !== 0) {
                root.resetAudioMetadata()
                return
            }
            try {
                const payload = JSON.parse(metadataCollector.text)
                const payloadPid = Number(payload.recorderPid ?? 0)
                if (!root.isRecording || payloadPid <= 0 || payloadPid !== root.recorderPid) {
                    root.resetAudioMetadata()
                    return
                }
                root.requestedAudioMode = root.normalizeAudioMode(String(payload.requestedAudioMode ?? "system"))
                root.activeAudioMode = root.normalizeAudioMode(String(payload.activeAudioMode ?? "none"))
                root.audioFallback = payload.audioFallback === true
                root.hasAudioMetadata = true
            } catch (error) {
                root.resetAudioMetadata()
            }
        }
        stdout: StdioCollector {
            id: metadataCollector
            onStreamFinished: {
                metadataProcess._stdoutDone = true
                if (metadataProcess._exited)
                    metadataProcess._finalizeMetadata()
            }
        }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (metadataProcess.running) {
                metadataProcess.startObserved = false
                metadataProcess._exited = false
                metadataProcess._exitCode = -1
                metadataProcess._stdoutDone = false
                metadataProcess._finalized = false
                metadataFlushTimer.stop()
                return
            }
            if (metadataProcess.startObserved)
                return
            root.resetAudioMetadata()
        }
        onStarted: metadataProcess.startObserved = true
        onExited: (exitCode, exitStatus) => {
            metadataProcess._exited = true
            metadataProcess._exitCode = exitCode
            if (metadataProcess._stdoutDone)
                metadataProcess._finalizeMetadata()
            else
                metadataFlushTimer.restart()
        }
    }

    Timer {
        id: metadataFlushTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (metadataProcess._exited && !metadataProcess._finalized)
                metadataProcess._finalizeMetadata()
        }
    }

    Process {
        id: checkProcess
        property bool startObserved: false
        property bool _exited: false
        property int _exitCode: -1
        property bool _stdoutDone: false
        property bool _finalized: false
        command: ["/usr/bin/pgrep", "-xo", "wf-recorder"]
        function _finalizeCheck(): void {
            if (_finalized)
                return
            _finalized = true
            checkProcessFlushTimer.stop()
            const previousPid = root.recorderPid
            const parsedPid = parseInt(recorderPidCollector.text.trim(), 10)
            root.recorderPid = _exitCode === 0 && !isNaN(parsedPid) ? parsedPid : 0
            root.isRecording = root.recorderPid > 0
            if (root.isRecording && (!root.hasAudioMetadata || root.recorderPid !== previousPid))
                root.loadAudioMetadata()
        }
        stdout: StdioCollector {
            id: recorderPidCollector
            onStreamFinished: {
                checkProcess._stdoutDone = true
                if (checkProcess._exited)
                    checkProcess._finalizeCheck()
            }
        }
        onRunningChanged: {
            if (checkProcess.running) {
                checkProcess.startObserved = false
                checkProcess._exited = false
                checkProcess._exitCode = -1
                checkProcess._stdoutDone = false
                checkProcess._finalized = false
                checkProcessFlushTimer.stop()
                return
            }
            if (checkProcess.startObserved)
                return
            root.recorderPid = 0
            root.isRecording = false
        }
        onStarted: checkProcess.startObserved = true
        onExited: (exitCode, exitStatus) => {
            checkProcess._exited = true
            checkProcess._exitCode = exitCode
            if (checkProcess._stdoutDone)
                checkProcess._finalizeCheck()
            else
                checkProcessFlushTimer.restart()
        }
    }

    Timer {
        id: checkProcessFlushTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (checkProcess._exited && !checkProcess._finalized)
                checkProcess._finalizeCheck()
        }
    }
}
