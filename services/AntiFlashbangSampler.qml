pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "antiFlashbangPolicy.js" as Policy

// Capture only small, in-memory images. This component never writes brightness.
Scope {
    id: root
    property bool active: false
    property string outputName: ""
    property real sampleScale: .10
    property int sampleInterval: 500
    property int timeoutMs: 1200
    property list<string> captureCommand: ["timeout", "--kill-after=0.2s",
        String(Policy.bounded(timeoutMs, 1200, 100, 3000) / 1000) + "s", "/bin/bash", "-o", "pipefail", "-c",
        "if [ -x \"$3\" ]; then exec \"$3\" screencopy -o \"$1\" -s \"$2\" --luma; fi; grim -o \"$1\" -s \"$2\" -t ppm - | magick ppm:- -colorspace Gray -format '%[fx:mean*100]' info:",
        "_", outputName, String(Policy.bounded(sampleScale, .10, .05, .50)), Quickshell.shellPath("scripts/native-dispatch")]
    readonly property bool capturing: capture.busy
    property real lastLightness: Number.NaN
    property real lastDurationMs: 0
    property int successes: 0
    property int failures: 0
    property int consecutiveFailures: 0
    property int generation: 0
    property bool pending: false
    signal sampled(real lightness)

    function request(delay = 0): void {
        if (!active || !outputName) return
        pending = true
        if (capture.busy) return
        debounce.interval = Policy.bounded(delay, 0, 0, 1500)
        debounce.restart()
    }
    function reset(): void {
        generation++
        pending = false
        debounce.stop();watchdog.stop();capture.running = false
        lastLightness = Number.NaN
        consecutiveFailures = 0
        if (active) request()
    }
    onActiveChanged: reset()
    onOutputNameChanged: reset()
    Component.onCompleted: if (active) request()
    Timer {
        id: periodic
        interval: Math.max(Policy.bounded(root.sampleInterval, 500, 250, 3000),
            root.consecutiveFailures > 0 ? Math.min(10000, 1000 * root.consecutiveFailures) : 0)
        running: root.active && root.outputName.length > 0
        repeat: true
        onTriggered: root.request()
    }
    Timer {
        id: debounce
        onTriggered: {
            if (!root.active || !root.outputName || capture.busy) return
            root.pending = false
            capture.captureGeneration = root.generation
            capture.startObserved = false
            capture.timedOut = false
            capture.startedAt = Date.now()
            capture.exitObserved = false;capture.streamObserved = false
            capture.sampleText = "";capture.finalized = false
            capture.busy = true
            capture.running = true
        }
    }
    Timer {
        id: watchdog
        interval: Policy.bounded(root.timeoutMs, 1200, 100, 3000)
        onTriggered: {
            capture.timedOut = true
            capture.running = false
        }
    }
    Process {
        id: capture
        property int captureGeneration: -1
        property bool startObserved: false
        property bool timedOut: false
        property real startedAt: 0
        property bool exitObserved: false
        property bool streamObserved: false
        property bool finalized: false
        property int sampleExitCode: -1
        property string sampleText: ""
        property bool busy: false
        command: root.captureCommand
        stdout: StdioCollector {
            onStreamFinished: {
                capture.sampleText = text
                capture.streamObserved = true
                capture.finish()
            }
        }
        onStarted: { startObserved = true;watchdog.restart() }
        onRunningChanged: {
            if (!running && !startObserved) {
                watchdog.stop();busy = false;finalized = true
                if (captureGeneration === root.generation && root.active) {
                    root.failures++;root.consecutiveFailures++
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            watchdog.stop()
            sampleExitCode = exitCode;exitObserved = true
            finish()
        }
        function finish(): void {
            // Stream completion and process exit are independent callbacks.
            if (finalized || !exitObserved || !streamObserved) return
            finalized = true
            busy = false
            if (!root.active || captureGeneration !== root.generation) {
                if (root.active && root.pending) Qt.callLater(() => root.request())
                return
            }
            root.lastDurationMs = Date.now() - startedAt
            const text = sampleText.trim(), value = text.length ? Number(text) : Number.NaN
            if (sampleExitCode === 0 && !timedOut && Number.isFinite(value) && value >= 0 && value <= 100) {
                root.lastLightness = value;root.successes++;root.consecutiveFailures = 0
                root.sampled(value)
            } else {
                root.failures++;root.consecutiveFailures++
            }
            if (root.pending && root.consecutiveFailures === 0) Qt.callLater(() => root.request())
            else root.pending = false
        }
    }
}
