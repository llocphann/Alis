pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool active: false
    property int requestId: 0
    property string result: "cancelled"
    property var resultHistory: ({})
    property var recentColors: []
    property string lastFormattedValue: ""
    property string lastError: ""
    // Native capture/window objects belong exclusively to the disposable worker.
    readonly property var overlays: []
    readonly property var workerProcessId: worker.processId
    property int workerTicket: 0
    property var workerReply: null
    property string pendingClipboardValue: ""
    property double _lastOverlayDismissMs: 0
    property string _sandboxEntryPath: ""
    property bool _workerLaunchedFromSandbox: false
    property bool _sandboxFallbackRetried: false
    readonly property string _workerEntryPath: root._sandboxEntryPath.length > 0
        ? root._sandboxEntryPath
        : (Quickshell.shellDir + "/color-picker-worker.qml")
    signal picked(string value)

    function _markOverlayDismissed(isOpen: bool): void {
        if (!isOpen)
            root._lastOverlayDismissMs = Date.now()
    }

    function _computeLaunchDelayMs(): int {
        const anyOverlayOpen = Boolean(
            GlobalStates.sidebarLeftOpen
            || GlobalStates.sidebarRightOpen
            || GlobalStates.regionSelectorOpen
            || GlobalStates.controlPanelOpen
            || GlobalStates.overviewOpen
            || GlobalStates.dashboardOpen
            || GlobalStates.waffleActionCenterOpen
            || GlobalStates.notificationCenterOpen
            || GlobalStates.searchOpen)
        if (anyOverlayOpen)
            return 220
        const sinceDismiss = root._lastOverlayDismissMs > 0
            ? (Date.now() - root._lastOverlayDismissMs)
            : 9999
        if (sinceDismiss >= 0 && sinceDismiss < 220)
            return Math.max(16, Math.round(220 - sinceDismiss))
        return 1
    }

    function _prepareSandbox(): void {
        if (sandboxPrep.running)
            return
        const shellDir = String(Quickshell.shellDir ?? "")
        if (!shellDir)
            return
        const key = Qt.md5(shellDir).slice(0, 16)
        sandboxPrep.command = [
            "/usr/bin/sh", "-c",
            "base=\"${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/alis/colorpicker-sandbox\"; " +
            "dir=\"$base/$2\"; " +
            "mkdir -p \"$dir/services\" && " +
            "ln -sfn \"$1/color-picker-worker.qml\" \"$dir/color-picker-worker.qml\" && " +
            "for existing in \"$dir\"/services/ColorPicker*.qml; do " +
            "[ -L \"$existing\" ] && [ ! -e \"$existing\" ] && rm -f \"$existing\"; " +
            "done; " +
            "tmp=\"$dir/services/qmldir.tmp.$$\"; " +
            "{ printf 'module qs.services\\n'; " +
            "for f in \"$1\"/services/ColorPicker*.qml; do " +
            "[ -e \"$f\" ] || continue; b=$(basename \"$f\"); " +
            "case \"$b\" in *Service.qml) continue ;; esac; " +
            "ln -sfn \"$f\" \"$dir/services/$b\"; " +
            "printf '%s 1.0 %s\\n' \"${b%.qml}\" \"$b\"; " +
            "done; } > \"$tmp\" && mv -f \"$tmp\" \"$dir/services/qmldir\" && " +
            "for old in \"$base\"/*; do " +
            "[ -d \"$old\" ] && [ \"$old\" != \"$dir\" ] && [ ! -e \"$old/color-picker-worker.qml\" ] && rm -rf \"$old\"; " +
            "done; " +
            "printf '%s\\n' \"$dir/color-picker-worker.qml\"",
            "alis-colorpicker-sandbox", shellDir, key
        ]
        sandboxPrep.running = true
    }

    function _opaqueHexOr(c, fallback: string): string {
        try {
            if (c === null || c === undefined || c === "") return fallback
            const col = Qt.color(c)
            if (!col || isNaN(col.r) || isNaN(col.g) || isNaN(col.b)) return fallback
            const h = v => Math.max(0, Math.min(255, Math.round(v * 255))).toString(16).padStart(2, "0")
            return "#" + h(col.r) + h(col.g) + h(col.b)
        } catch (e) {
            return fallback
        }
    }

    function _buildThemePayload(): string {
        const colors = Appearance?.colors
        const dark = Boolean(Appearance?.m3colors?.darkmode ?? true)
        const base0 = root._opaqueHexOr(colors?.colLayer0Base ?? colors?.colLayer0, dark ? "#14161b" : "#f4f6fa")
        const base1Raw = colors?.colLayer1Base ?? colors?.colLayer1
        const base1Col = base1Raw ? Qt.color(base1Raw) : ColorUtils.tonalStep(base0, 0.021, 0.01)
        const dir1 = (base1Col.hslLightness > 0.86) ? -1 : 1
        const layer1 = root._opaqueHexOr(base1Col, dark ? "#1c1f26" : "#eaeef5")
        const layer2 = root._opaqueHexOr(ColorUtils.tonalStep(layer1, dir1 * 0.022, 0.01), dark ? "#242832" : "#dfe5f0")
        const payload = {
            darkmode: dark,
            colLayer0: base0,
            colLayer1: layer1,
            colLayer2: layer2,
            colPrimary: root._opaqueHexOr(colors?.colPrimary, "#89b4fa"),
            colOnPrimary: root._opaqueHexOr(colors?.colOnPrimary, dark ? "#0d1117" : "#ffffff"),
            colSecondary: root._opaqueHexOr(colors?.colSecondary, "#94e2d5"),
            colTertiary: root._opaqueHexOr(colors?.colTertiary, "#cba6f7"),
            colOnLayer0: root._opaqueHexOr(colors?.colOnLayer0, dark ? "#e6eaf2" : "#181b22"),
            colSubtext: root._opaqueHexOr(colors?.colSubtext, dark ? "#9ea6b8" : "#556070"),
            colOutline: root._opaqueHexOr(colors?.colLayer0Border ?? colors?.colOutline, dark ? "#333947" : "#c6cfde"),
            recentColors: Array.isArray(root.recentColors) ? root.recentColors.slice(0, 6) : []
        }
        return JSON.stringify(payload)
    }

    function _recordRecentColor(hex: string): void {
        if (!/^#[0-9A-F]{6}$/.test(hex)) return
        const next = [hex].concat((root.recentColors ?? []).filter(c => c !== hex)).slice(0, 6)
        root.recentColors = next
    }

    function start(): string {
        if (result === "pending") return String(requestId)
        requestId++
        result = "pending"
        lastError = ""
        root._sandboxFallbackRetried = false
        if (root._sandboxEntryPath.length === 0 && !sandboxPrep.running)
            root._prepareSandbox()
        launch.interval = root._computeLaunchDelayMs()
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
            "dispatch=\"$2/scripts/native-dispatch\"; " +
            "if [ -x \"$dispatch\" ]; then printf '%s' \"$1\" | \"$dispatch\" clipboard store >/dev/null 2>&1 || true; " +
            "\"$dispatch\" clipboard copy --type 'text/plain;charset=utf-8' -- \"$1\" </dev/null >/dev/null 2>&1 || true; " +
            "else " +
            "if command -v cliphist >/dev/null 2>&1; then printf '%s' \"$1\" | cliphist store >/dev/null 2>&1 || true; fi; " +
            "if command -v wl-copy >/dev/null 2>&1; then wl-copy --type 'text/plain;charset=utf-8' -- \"$1\" </dev/null >/dev/null 2>&1 || true; fi; " +
            "fi; " +
            "sleep 0.06; " +
            "if [ -n \"$2\" ] && command -v qs >/dev/null 2>&1; then qs -p \"$2\" ipc call cliphistService update >/dev/null 2>&1 || true; fi",
            "alis-colorpicker-copy", nextValue, Quickshell.shellDir]
        clipboardSync.running = true
    }
    function finish(ticket: int, value: string, formatted = ""): void {
        if (!active || result !== "pending" || ticket !== requestId || !/^#[0-9A-F]{6}$/.test(value)) return
        const clipValue = (formatted && formatted.length > 0 && formatted.length <= 64) ? formatted : value
        root.lastFormattedValue = clipValue
        root._recordRecentColor(value)
        // The host retains clipboard ownership after the worker exits, and
        // publishes via wlr-data-control + cliphist so unfocused picks land in
        // both the compositor clipboard and Alis Clipboard History.
        if (Quickshell.clipboardText === clipValue)
            Quickshell.clipboardText = ""
        if (clipValue === value) {
            Quickshell.clipboardText = value
        } else {
            Quickshell.clipboardText = clipValue
        }
        syncClipboardHistory(clipValue)
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
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() { root._markOverlayDismissed(GlobalStates.sidebarLeftOpen) }
        function onSidebarRightOpenChanged() { root._markOverlayDismissed(GlobalStates.sidebarRightOpen) }
        function onRegionSelectorOpenChanged() { root._markOverlayDismissed(GlobalStates.regionSelectorOpen) }
        function onControlPanelOpenChanged() { root._markOverlayDismissed(GlobalStates.controlPanelOpen) }
        function onOverviewOpenChanged() { root._markOverlayDismissed(GlobalStates.overviewOpen) }
        function onDashboardOpenChanged() { root._markOverlayDismissed(GlobalStates.dashboardOpen) }
        function onWaffleActionCenterOpenChanged() { root._markOverlayDismissed(GlobalStates.waffleActionCenterOpen) }
        function onNotificationCenterOpenChanged() { root._markOverlayDismissed(GlobalStates.notificationCenterOpen) }
        function onSearchOpenChanged() { root._markOverlayDismissed(GlobalStates.searchOpen) }
    }
    // Build a minimal 3-file symlink sandbox in $XDG_CACHE_HOME once after shell
    // startup so `qs -p` skips scanning the entire Alis QML tree (~6-15x faster launch).
    Timer {
        id: sandboxPrepTimer
        interval: 800
        running: true
        onTriggered: root._prepareSandbox()
    }
    Process {
        id: sandboxPrep
        stdout: SplitParser {
            onRead: line => {
                const path = String(line ?? "").trim()
                if (path.endsWith("/color-picker-worker.qml"))
                    root._sandboxEntryPath = path
            }
        }
    }
    // Wait briefly only when an invoking sidebar/snipping overlay just dismissed,
    // or while an older cancelled process finishes reaping.
    Timer {
        id: launch
        interval: 1
        onTriggered: {
            if (root.result !== "pending") return
            if (worker.running) { interval = 40; restart(); return }
            root.workerTicket = root.requestId
            root.workerReply = null
            root._workerLaunchedFromSandbox = (root._sandboxEntryPath.length > 0)
            root.active = true
            worker.environment = ({
                ALIS_COLOR_PICKER_TICKET: String(root.workerTicket),
                ALIS_COLOR_PICKER_THEME: root._buildThemePayload(),
                QS_CONFIG_NAME: null, QS_CONFIG_PATH: null, QS_MANIFEST: null,
                QS_DISABLE_CRASH_HANDLER: "1"
            })
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
        command: ["qs", "-p", root._workerEntryPath, "--no-color"]
        stdout: SplitParser { onRead: line => root.readReply(line) }
        stderr: SplitParser { onRead: line => root.readReply(line) }
        onExited: (code, status) => {
            reap.stop()
            if (root.workerTicket !== root.requestId || root.result !== "pending") return
            const reply = root.workerReply
            if (code !== 0 && !reply && root._workerLaunchedFromSandbox && !root._sandboxFallbackRetried) {
                // Self-heal if $XDG_CACHE_HOME/alis/colorpicker-sandbox was cleared while shell was running.
                root._sandboxFallbackRetried = true
                root._sandboxEntryPath = ""
                root._prepareSandbox()
                launch.interval = 1
                launch.restart()
                return
            }
            if (code !== 0 || status !== 0 || !reply) {
                root.fail(root.workerTicket, "Color picker stopped unexpectedly")
            } else if (reply.status === "picked") {
                const fmt = (typeof reply.formatted === "string") ? reply.formatted.trim() : ""
                root.finish(root.workerTicket, reply.value, fmt)
            } else if (reply.status === "cancelled") {
                root.settle("cancelled")
            } else {
                root.fail(root.workerTicket, String(reply.message || "Screen capture is unavailable").slice(0, 160))
            }
        }
        onRunningChanged: if (!running && root.active) {
            // FailedToStart has no exited signal. Defer until a normal onExited
            // (including a single-shot sandbox fallback retry) has had its chance
            // to settle or relaunch this same ticket.
            const ticket = root.workerTicket
            Qt.callLater(() => {
                if (!worker.running && !launch.running && ticket === root.requestId && root.result === "pending")
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
