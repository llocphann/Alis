pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Shared refcounted live microphone loudness & peak-hold level service.
 * Runs at most one capture helper while subscribers are active and mic is unmuted.
 */
Singleton {
    id: root

    property int _subscribers: 0
    readonly property bool active: _subscribers > 0
    property real level: 0.0
    property real peak: 0.0
    readonly property bool muted: Audio.micMuted
    readonly property int targetFps: (Config.options?.performance?.lowPower ?? false) ? 20 : 30
    readonly property string scriptPath: FileUtils.trimFileProtocol(Directories.scriptPath) + "/audio/mic-level-meter.py"
    readonly property string nativeDispatchPath: Quickshell.shellPath("scripts/native-dispatch")
    readonly property bool shouldCapture: root.active && !root.muted
    property int _consecutiveFailures: 0
    property bool _intentionalRestart: false

    function subscribe(): void {
        root._subscribers += 1
        stopDebounce.stop()
        root._consecutiveFailures = 0
        root._syncProcess()
    }

    function unsubscribe(): void {
        root._subscribers = Math.max(0, root._subscribers - 1)
        if (!root.active)
            stopDebounce.restart()
    }

    function _stopCapture(): void {
        root._intentionalRestart = false
        restartTimer.stop()
        meterProc.running = false
        root.level = 0.0
        root.peak = 0.0
    }

    function _syncProcess(): void {
        if (root.shouldCapture) {
            stopDebounce.stop()
            restartTimer.stop()
            if (!meterProc.running)
                meterProc.running = true
        } else if (root.muted || !stopDebounce.running) {
            root._stopCapture()
        }
    }

    onMutedChanged: {
        if (root.muted) {
            stopDebounce.stop()
            root._stopCapture()
        } else if (root.active) {
            stopDebounce.stop()
            root._consecutiveFailures = 0
            root._syncProcess()
        }
    }

    onTargetFpsChanged: {
        if (meterProc.running) {
            root._intentionalRestart = true
            meterProc.running = false
            restartTimer.interval = 50
            restartTimer.restart()
        }
    }

    Connections {
        target: Audio
        function onSourceChanged(): void {
            if (root.shouldCapture && meterProc.running) {
                root._intentionalRestart = true
                meterProc.running = false
                restartTimer.interval = 120
                restartTimer.restart()
            }
        }
    }

    Timer {
        id: stopDebounce
        interval: 250
        repeat: false
        onTriggered: {
            if (!root.shouldCapture)
                root._stopCapture()
        }
    }

    Timer {
        id: restartTimer
        interval: 800
        repeat: false
        onTriggered: root._syncProcess()
    }

    Process {
        id: meterProc
        running: false
        command: [root.nativeDispatchPath, "mic-meter", "--fps", String(root.targetFps)]
        stdout: SplitParser {
            onRead: data => {
                if (root.muted || !root.shouldCapture)
                    return
                const line = String(data ?? "").trim()
                if (!line.length)
                    return
                const parts = line.split(/\s+/)
                if (parts.length < 2)
                    return
                const nextLevel = Number(parts[0])
                const nextPeak = Number(parts[1])
                if (!Number.isFinite(nextLevel) || !Number.isFinite(nextPeak))
                    return
                root._consecutiveFailures = 0
                root.level = Math.max(0, Math.min(1, nextLevel))
                root.peak = Math.max(0, Math.min(1, nextPeak))
            }
        }
        onExited: (exitCode, _exitStatus) => {
            root.level = 0.0
            root.peak = 0.0
            if (root._intentionalRestart) {
                root._intentionalRestart = false
                root._consecutiveFailures = 0
                return
            }
            if (root.shouldCapture && exitCode !== 0 && root._consecutiveFailures < 3) {
                root._consecutiveFailures += 1
                restartTimer.interval = 800 * root._consecutiveFailures
                restartTimer.restart()
            }
        }
    }

    Component.onDestruction: {
        stopDebounce.stop()
        restartTimer.stop()
        meterProc.running = false
    }
}
