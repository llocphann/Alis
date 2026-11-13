pragma Singleton
pragma ComponentBehavior: Bound
import qs
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool active: false
    property int requestId: 0
    property string result: "cancelled"
    property var resultHistory: ({})
    property string lastError: ""
    // Native capture/window objects belong exclusively to the disposable worker.
    readonly property var overlays: []
    readonly property var workerProcessId: worker.processId
    property int workerTicket: 0
    property var workerReply: null
    property string pendingClipboardValue: ""
    signal picked(string value)

    function start(): string {
        if (result === "pending") return String(requestId)
        requestId++
        result = "pending"
        lastError = ""
        launch.restart()
        return String(requestId)
    }
    function status(ticket: string): string {
        return ticket === String(requestId) ? result : (resultHistory[ticket] ?? "cancelled")
    }
    function settle(value: string): void {
        result = value
        active = false
        launch.stop()
        deadline.stop()
        exitGrace.stop()
        const history = Object.assign({}, resultHistory)
        history[String(requestId)] = value
        for (const ticket of Object.keys(history))
            if (Number(ticket) <= requestId - 16) delete history[ticket]
        resultHistory = history
    }
    function stopWorker(): void {
        if (!worker.running) return
        worker.signal(15)
        reap.restart()
    }
    function cancel(ticket: int): void {
        if (ticket !== requestId || result !== "pending") return
        settle("cancelled")
        if (workerTicket === ticket) stopWorker()
    }
    function syncClipboardHistory(value: string): void {
        pendingClipboardValue = value
        if (!clipboardSync.running)
            startClipboardSync()
    }
    function startClipboardSync(): void {
        if (!pendingClipboardValue || clipboardSync.running) return
        const nextValue = pendingClipboardValue
        pendingClipboardValue = ""
        clipboardSync.command = ["/usr/bin/sh", "-c",
            "if command -v cliphist >/dev/null 2>&1; then printf '%s' \"$1\" | cliphist store >/dev/null 2>&1 || true; fi; " +
            "if command -v wl-copy >/dev/null 2>&1; then wl-copy --type 'text/plain;charset=utf-8' -- \"$1\" </dev/null >/dev/null 2>&1 || true; fi; " +
            "sleep 0.06; " +
            "if [ -n \"$2\" ] && command -v qs >/dev/null 2>&1; then qs -p \"$2\" ipc call cliphistService update >/dev/null 2>&1 || true; fi",
            "alis-colorpicker-copy", nextValue, Quickshell.shellDir]
        clipboardSync.running = true
    }
    function finish(ticket: int, value: string): void {
        if (!active || result !== "pending" || ticket !== requestId || !/^#[0-9A-F]{6}$/.test(value)) return
        // The host retains clipboard ownership after the worker exits, and
        // publishes via wlr-data-control + cliphist so unfocused picks land in
        // both the compositor clipboard and Alis Clipboard History.
        if (Quickshell.clipboardText === value)
            Quickshell.clipboardText = ""
        Quickshell.clipboardText = value
        syncClipboardHistory(value)
        settle(value)
        picked(value)
    }
    function fail(ticket: int, message: string): void {
        if (ticket !== requestId || result !== "pending") return
        lastError = message
        settle("failed")
        if (workerTicket === ticket) stopWorker()
        console.error("Alis Color Picker:", message)
        GlobalStates.toastManager?.addToast("Color Picker", message, "error", true, 6000, "color-picker")
    }
    function readReply(line: string): void {
        const marker = "ALIS_COLOR_PICKER_RESULT "
        const index = line.indexOf(marker)
        if (index < 0 || line.length > 2048 || workerReply) return
        try {
            const reply = JSON.parse(line.slice(index + marker.length))
            if (reply.ticket !== workerTicket) return
            if (reply.status === "ready") { deadline.stop(); return }
            if (!["picked", "cancelled", "failed"].includes(reply.status)) return
            if (reply.status === "picked" && !/^#[0-9A-F]{6}$/.test(reply.value)) return
            workerReply = reply
            exitGrace.restart()
        } catch (error) {}
    }
    // Delay until the invoking sidebar/snipping overlay has dismissed. Wait for
    // an older cancelled process to be reaped before reusing its transport.
    Timer {
        id: launch
        interval: 300
        onTriggered: {
            if (root.result !== "pending") return
            if (worker.running) { restart(); return }
            root.workerTicket = root.requestId
            root.workerReply = null
            root.active = true
            worker.environment = ({ ALIS_COLOR_PICKER_TICKET: String(root.workerTicket),
                QS_CONFIG_NAME: null, QS_CONFIG_PATH: null, QS_MANIFEST: null,
                QS_DISABLE_CRASH_HANDLER: "1" })
            worker.running = true
            deadline.restart()
        }
    }
    Timer {
        id: deadline
        interval: 10000
        onTriggered: root.fail(root.requestId, "Color picker capture timed out")
    }
    Timer {
        id: exitGrace
        interval: 3000
        onTriggered: root.fail(root.workerTicket, "Color picker did not exit")
    }
    Timer {
        id: reap
        interval: 500
        onTriggered: if (worker.running) worker.signal(9)
    }
    Process {
        id: worker
        command: ["qs", "-p", Quickshell.shellDir + "/color-picker-worker.qml", "--no-color"]
        stdout: SplitParser { onRead: line => root.readReply(line) }
        stderr: SplitParser { onRead: line => root.readReply(line) }
        onExited: (code, status) => {
            reap.stop()
            if (root.workerTicket !== root.requestId || root.result !== "pending") return
            const reply = root.workerReply
            if (code !== 0 || status !== 0 || !reply) {
                root.fail(root.workerTicket, "Color picker stopped unexpectedly")
            } else if (reply.status === "picked") {
                root.finish(root.workerTicket, reply.value)
            } else if (reply.status === "cancelled") {
                root.settle("cancelled")
            } else {
                root.fail(root.workerTicket, String(reply.message || "Screen capture is unavailable").slice(0, 160))
            }
        }
        onRunningChanged: if (!running && root.active) {
            // FailedToStart has no exited signal. Defer until a normal onExited
            // has had its opportunity to settle this same ticket.
            const ticket = root.workerTicket
            Qt.callLater(() => {
                if (!worker.running && ticket === root.requestId && root.result === "pending")
                    root.fail(ticket, "Could not start color picker")
            })
        }
    }
    Process {
        id: clipboardSync
        onExited: (code, status) => {
            if (root.pendingClipboardValue)
                root.startClipboardSync()
        }
    }
    IpcHandler {
        target: "colorpicker"
        function start(): string { return root.start() }
        function status(ticket: string): string { return root.status(ticket) }
        function cancel(ticket: string): void { root.cancel(Number(ticket)) }
    }
}
