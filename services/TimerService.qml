pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    // Pomodoro config - use explicit properties to ensure reactivity
    property int focusTime: 1500
    property int breakTime: 300
    property int longBreakTime: 900
    property int cyclesBeforeLongBreak: 4

    // Study-Tracker adapted presets & subject tags
    readonly property var tagColorPalette: [
        "#f38ba8", "#fab387", "#f9e2af", "#a6e3a1",
        "#94e2d5", "#89dceb", "#74c7ec", "#89b4fa",
        "#b4befe", "#cba6f7", "#f5c2e7", "#eba0ac"
    ]

    readonly property var pomodoroPresets: ({
        standard: { key: "standard", label: "Standard", focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, cycles: 4 },
        deep: { key: "deep", label: "Deep Work", focusMinutes: 50, breakMinutes: 10, longBreakMinutes: 30, cycles: 4 },
        ultradian: { key: "ultradian", label: "Ultradian", focusMinutes: 90, breakMinutes: 20, longBreakMinutes: 20, cycles: 1 }
    })

    readonly property string activePreset: {
        const f = Math.round(root.focusTime / 60)
        const b = Math.round(root.breakTime / 60)
        const l = Math.round(root.longBreakTime / 60)
        const c = root.cyclesBeforeLongBreak
        if (f === 25 && b === 5 && l === 15 && c === 4) return "standard"
        if (f === 50 && b === 10 && l === 30 && c === 4) return "deep"
        if (f === 90 && b === 20 && (c === 1 || l === 20)) return "ultradian"
        return "custom"
    }

    readonly property string activeTag: {
        const raw = String(Persistent.states?.timer?.pomodoro?.activeTag ?? "Study").trim()
        return raw.length > 0 ? raw : "Study"
    }

    readonly property var tags: {
        const raw = Persistent.states?.timer?.pomodoro?.tags
        if (Array.isArray(raw) && raw.length > 0) return raw
        if (raw && raw.length !== undefined && raw.length > 0) {
            let out = []
            for (let i = 0; i < raw.length; i++) out.push(String(raw[i]))
            return out
        }
        return ["General", "Study", "Coding", "Reading"]
    }

    readonly property var archivedTags: {
        const raw = Persistent.states?.timer?.pomodoro?.archivedTags
        if (Array.isArray(raw)) return raw
        if (raw && raw.length !== undefined) {
            let out = []
            for (let i = 0; i < raw.length; i++) out.push(String(raw[i]))
            return out
        }
        return []
    }

    readonly property var tagColors: {
        const raw = String(Persistent.states?.timer?.pomodoro?.tagColorsJson ?? "{}")
        try {
            const parsed = JSON.parse(raw)
            return (parsed && typeof parsed === "object") ? parsed : ({})
        } catch (e) {
            return ({})
        }
    }

    function _todayIsoDate(): string {
        const d = new Date()
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return `${y}-${m}-${day}`
    }

    readonly property int todayFocusSeconds: {
        if (!Persistent.ready) return 0
        return String(Persistent.states?.timer?.pomodoro?.todayDate ?? "") === root._todayIsoDate()
            ? Math.max(0, Number(Persistent.states?.timer?.pomodoro?.todayFocusSeconds ?? 0))
            : 0
    }

    readonly property int todaySessions: {
        if (!Persistent.ready) return 0
        return String(Persistent.states?.timer?.pomodoro?.todayDate ?? "") === root._todayIsoDate()
            ? Math.max(0, Number(Persistent.states?.timer?.pomodoro?.todaySessions ?? 0))
            : 0
    }

    function getTagColor(tagName: string): string {
        const name = String(tagName || "Study").trim()
        const map = root.tagColors
        if (map && map[name]) return String(map[name])
        let hash = 0
        for (let i = 0; i < name.length; i++) {
            hash = name.charCodeAt(i) + ((hash << 5) - hash)
        }
        const idx = Math.abs(hash) % root.tagColorPalette.length
        return root.tagColorPalette[idx]
    }

    function setActiveTag(tagName: string): void {
        if (!Persistent.ready) return
        const clean = String(tagName || "").trim()
        if (!clean) return
        Persistent.states.timer.pomodoro.activeTag = clean
    }

    function setTagColor(tagName: string, colorHex: string): void {
        if (!Persistent.ready) return
        const clean = String(tagName || "").trim()
        const col = String(colorHex || "").trim()
        if (!clean || !col) return
        let next = Object.assign({}, root.tagColors)
        next[clean] = col
        Persistent.states.timer.pomodoro.tagColorsJson = JSON.stringify(next)
    }

    function addTag(tagName: string, colorHex: string): bool {
        if (!Persistent.ready) return false
        const clean = String(tagName || "").trim()
        if (!clean) return false
        let current = root.tags.slice()
        const exists = current.some(t => String(t).toLowerCase() === clean.toLowerCase())
        if (exists) {
            const match = current.find(t => String(t).toLowerCase() === clean.toLowerCase())
            Persistent.states.timer.pomodoro.activeTag = match
            if (colorHex) root.setTagColor(match, colorHex)
            return true
        }
        let archived = root.archivedTags.filter(t => String(t).toLowerCase() !== clean.toLowerCase())
        current.push(clean)
        Persistent.states.timer.pomodoro.tags = current
        Persistent.states.timer.pomodoro.archivedTags = archived
        if (colorHex) root.setTagColor(clean, colorHex)
        Persistent.states.timer.pomodoro.activeTag = clean
        return true
    }

    function removeTag(tagName: string): void {
        if (!Persistent.ready) return
        const clean = String(tagName || "").trim()
        let current = root.tags.slice()
        if (current.length <= 1) return
        const next = current.filter(t => t !== clean)
        if (next.length === current.length) return
        let archived = root.archivedTags.slice()
        if (!archived.includes(clean)) archived.push(clean)
        Persistent.states.timer.pomodoro.tags = next
        Persistent.states.timer.pomodoro.archivedTags = archived
        if (root.activeTag === clean) {
            Persistent.states.timer.pomodoro.activeTag = next[0] || "General"
        }
    }

    function recoverTag(tagName: string): void {
        if (!Persistent.ready) return
        const clean = String(tagName || "").trim()
        if (!clean) return
        let archived = root.archivedTags.filter(t => t !== clean)
        let current = root.tags.slice()
        if (!current.includes(clean)) current.push(clean)
        Persistent.states.timer.pomodoro.archivedTags = archived
        Persistent.states.timer.pomodoro.tags = current
        Persistent.states.timer.pomodoro.activeTag = clean
    }

    function applyPomodoroPreset(presetKey: string): void {
        const preset = root.pomodoroPresets[presetKey]
        if (!preset) return
        Config.setNestedValues({
            "time.pomodoro.focus": preset.focusMinutes * 60,
            "time.pomodoro.breakTime": preset.breakMinutes * 60,
            "time.pomodoro.longBreak": preset.longBreakMinutes * 60,
            "time.pomodoro.cyclesBeforeLongBreak": preset.cycles
        })
        if (root.pomodoroRunning) {
            root.resetPomodoro()
        }
    }

    function _recordCompletedFocusLap(seconds: int): void {
        if (!Persistent.ready || seconds <= 0) return
        const today = root._todayIsoDate()
        if (String(Persistent.states.timer.pomodoro.todayDate ?? "") !== today) {
            Persistent.states.timer.pomodoro.todayDate = today
            Persistent.states.timer.pomodoro.todayFocusSeconds = seconds
            Persistent.states.timer.pomodoro.todaySessions = 1
        } else {
            Persistent.states.timer.pomodoro.todayFocusSeconds = Math.max(0, Number(Persistent.states.timer.pomodoro.todayFocusSeconds ?? 0)) + seconds
            Persistent.states.timer.pomodoro.todaySessions = Math.max(0, Number(Persistent.states.timer.pomodoro.todaySessions ?? 0)) + 1
        }
    }

    function _positiveInt(value, fallback: int): int {
        const parsed = Number(value)
        return Number.isFinite(parsed) && parsed > 0 ? Math.max(1, Math.round(parsed)) : fallback
    }

    function _stopwatchTick(value): int {
        const parsed = Number(value)
        if (!Number.isFinite(parsed)) return 0

        // Keep 10 ms wall-clock ticks inside the signed 32-bit range used by
        // Persistent.states.timer.stopwatch.start and stopwatchTime. Elapsed
        // values use the same modulus, so wraparound remains monotonic for the
        // full duration an int stopwatch can represent (~248 days).
        const modulus = 2147483648
        const tick = Math.floor(parsed)
        return ((tick % modulus) + modulus) % modulus
    }

    // While a timer is paused, reuse its persisted `start` field to hold the
    // frozen progress. Negative values distinguish this encoding from legacy
    // positive wall-clock/tick starts without expanding the persistent schema.
    function _encodePausedValue(value): int {
        const parsed = Number(value)
        const normalized = Number.isFinite(parsed) ? Math.max(0, Math.round(parsed)) : 0
        return -normalized - 1
    }

    function _decodePausedValue(value, fallback: int, maximum: int): int {
        const parsed = Number(value)
        let decoded = Number.isFinite(parsed) && parsed < 0
            ? Math.max(0, -Math.round(parsed) - 1)
            : Math.max(0, fallback)
        if (maximum >= 0)
            decoded = Math.min(decoded, maximum)
        return decoded
    }

    // Helper to sync all pomodoro values from Config
    function _syncPomodoroConfig() {
        root.focusTime = root._positiveInt(Config.options?.time?.pomodoro?.focus, 1500)
        root.breakTime = root._positiveInt(Config.options?.time?.pomodoro?.breakTime, 300)
        root.longBreakTime = root._positiveInt(Config.options?.time?.pomodoro?.longBreak, 900)
        root.cyclesBeforeLongBreak = root._positiveInt(Config.options?.time?.pomodoro?.cyclesBeforeLongBreak, 4)
    }

    // Sync pomodoro config on ANY config change (reliable - survives object recreation after file reload)
    Connections {
        target: Config
        function onConfigChanged() { root._syncPomodoroConfig() }
        function onReadyChanged() {
            if (Config.ready) {
                root._syncPomodoroConfig()
                if (Persistent.ready)
                    root._restorePersistedTimers()
            }
        }
    }

    Component.onCompleted: {
        if (Config.ready) root._syncPomodoroConfig()
        if (Persistent.ready) root._restorePersistedTimers()
    }

    property bool pomodoroRunning: Persistent.states?.timer?.pomodoro?.running ?? false
    property bool pomodoroPaused: Persistent.states?.timer?.pomodoro?.paused ?? false
    property bool pomodoroBreak: Persistent.states?.timer?.pomodoro?.isBreak ?? false
    property bool pomodoroLongBreak: pomodoroBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime
    property int pomodoroSecondsLeft: pomodoroLapDuration
    property int pomodoroCycle: Persistent.states?.timer?.pomodoro?.cycle ?? 0

    // When focusTime changes and timer is not running, reset pomodoroSecondsLeft
    onFocusTimeChanged: {
        if (!pomodoroRunning && !pomodoroBreak) {
            pomodoroSecondsLeft = focusTime
        }
    }
    onBreakTimeChanged: {
        if (!pomodoroRunning && pomodoroBreak && !pomodoroLongBreak) {
            pomodoroSecondsLeft = breakTime
        }
    }
    onLongBreakTimeChanged: {
        if (!pomodoroRunning && pomodoroLongBreak) {
            pomodoroSecondsLeft = longBreakTime
        }
    }

    property bool stopwatchRunning: Persistent.states?.timer?.stopwatch?.running ?? false
    property bool stopwatchPaused: Persistent.states?.timer?.stopwatch?.paused ?? false
    property int stopwatchTime: 0
    property int stopwatchStart: root._stopwatchTick(Persistent.states?.timer?.stopwatch?.start ?? 0)
    property var stopwatchLaps: {
        const stored = Persistent.states?.timer?.stopwatch?.laps
        return Array.isArray(stored) ? stored : []
    }

    // Countdown Timer
    property bool countdownRunning: Persistent.states?.timer?.countdown?.running ?? false
    property bool countdownPaused: Persistent.states?.timer?.countdown?.paused ?? false
    property int countdownDuration: root._positiveInt(Persistent.states?.timer?.countdown?.duration, 300)
    property int countdownSecondsLeft: countdownDuration

    function _restorePersistedTimers(): void {
        if (!Persistent.ready)
            return

        if (root.pomodoroRunning) {
            if (root.pomodoroPaused) {
                root.pomodoroSecondsLeft = root._decodePausedValue(
                    Persistent.states.timer.pomodoro.start,
                    root.pomodoroLapDuration,
                    root.pomodoroLapDuration)
            } else {
                root.refreshPomodoro()
            }
        }

        if (!root.stopwatchRunning) {
            root.stopwatchTime = 0
        } else if (root.stopwatchPaused
                && Number(Persistent.states.timer.stopwatch.start) < 0) {
            root.stopwatchTime = root._decodePausedValue(
                Persistent.states.timer.stopwatch.start, 0, -1)
        } else {
            // Preserve legacy paused states that stored a positive start value;
            // future pauses use the negative frozen-progress encoding above.
            root.refreshStopwatch()
        }

        if (!root.countdownRunning) {
            root.countdownSecondsLeft = root.countdownDuration
        } else if (root.countdownPaused) {
            root.countdownSecondsLeft = root._decodePausedValue(
                Persistent.states.timer.countdown.start,
                root.countdownDuration,
                root.countdownDuration)
        } else {
            root.refreshCountdown()
        }
    }

    // Initialize when Persistent is ready
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root._restorePersistedTimers()
        }
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms ticks kept in int range
        return root._stopwatchTick(Date.now() / 10);
    }

    // Pomodoro
    function refreshPomodoro() {
        // Work <-> break ?
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            const wasBreak = Persistent.states.timer.pomodoro.isBreak;
            const completedFocusSeconds = wasBreak ? 0 : root.focusTime;
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !wasBreak;
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
            if (!wasBreak) {
                root._recordCompletedFocusLap(completedFocusSeconds);
            }

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Notifications.sendInternal({
                summary: "Pomodoro",
                body: notificationMessage,
                appName: "Shell",
            });
            if (Config.options?.sounds?.pomodoro ?? false) {
                Audio.playEvent("pomodoroDone")
            }

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }
        }

        pomodoroSecondsLeft = pomodoroLapDuration - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    function skipPomodoroPhase() {
        if (!Persistent.ready) return;
        const wasBreak = Persistent.states.timer.pomodoro.isBreak;
        Persistent.states.timer.pomodoro.isBreak = !wasBreak;
        if (wasBreak) {
            Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
        }
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.paused = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        pomodoroSecondsLeft = pomodoroLapDuration;
    }

    function refreshSecondTimers(): void {
        if (!Persistent.ready)
            return
        if (root.pomodoroRunning && !root.pomodoroPaused)
            root.refreshPomodoro()
        if (root.countdownRunning && !root.countdownPaused)
            root.refreshCountdown()
    }

    // Pomodoro and countdown expose whole-second state. Drive both from one
    // second-aligned clock instead of two permanent 200 ms timers. Stopwatch
    // keeps its independent 33 ms cadence because it exposes 10 ms ticks.
    SystemClock {
        precision: SystemClock.Seconds
        enabled: Persistent.ready
            && ((root.pomodoroRunning && !root.pomodoroPaused)
                || (root.countdownRunning && !root.countdownPaused))
        // Start/resume mutates persisted timestamps synchronously; defer the
        // aligned tick so those writes are visible before refreshing.
        onDateChanged: Qt.callLater(root.refreshSecondTimers)
    }

    function togglePomodoro() {
        if (pomodoroRunning) {
            if (pomodoroPaused) {
                const remaining = root._decodePausedValue(
                    Persistent.states.timer.pomodoro.start,
                    pomodoroSecondsLeft,
                    pomodoroLapDuration)
                pomodoroSecondsLeft = remaining
                Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds()
                    + remaining - pomodoroLapDuration
                Persistent.states.timer.pomodoro.paused = false
            } else {
                root.refreshPomodoro()
                Persistent.states.timer.pomodoro.start = root._encodePausedValue(pomodoroSecondsLeft)
                Persistent.states.timer.pomodoro.paused = true
            }
        } else {
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds()
                + pomodoroSecondsLeft - pomodoroLapDuration
            Persistent.states.timer.pomodoro.paused = false
            Persistent.states.timer.pomodoro.running = true
        }
    }

    function stopPomodoro() {
        resetPomodoro();
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.paused = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        refreshPomodoro();
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores elapsed time in 10ms ticks
        stopwatchTime = root._stopwatchTick(getCurrentTimeIn10ms() - stopwatchStart);
    }

    Timer {
        id: stopwatchTimer
        interval: 33
        running: root.stopwatchRunning && !root.stopwatchPaused
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning) {
            if (root.stopwatchPaused)
                root.stopwatchResume()
            else
                root.stopwatchPause()
        } else {
            if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
            Persistent.states.timer.stopwatch.start = root._stopwatchTick(getCurrentTimeIn10ms() - stopwatchTime);
            Persistent.states.timer.stopwatch.paused = false;
            Persistent.states.timer.stopwatch.running = true;
        }
    }

    function stopStopwatch() {
        stopwatchReset();
    }

    function stopwatchPause() {
        if (!root.stopwatchRunning || root.stopwatchPaused)
            return
        root.refreshStopwatch()
        Persistent.states.timer.stopwatch.start = root._encodePausedValue(stopwatchTime)
        Persistent.states.timer.stopwatch.paused = true;
    }

    function stopwatchResume() {
        let elapsed = stopwatchTime
        if (root.stopwatchPaused) {
            elapsed = root._decodePausedValue(
                Persistent.states.timer.stopwatch.start,
                stopwatchTime,
                -1)
        }
        if (elapsed === 0) Persistent.states.timer.stopwatch.laps = [];
        root.stopwatchTime = elapsed
        Persistent.states.timer.stopwatch.start = root._stopwatchTick(getCurrentTimeIn10ms() - elapsed);
        Persistent.states.timer.stopwatch.paused = false;
        if (!stopwatchRunning) Persistent.states.timer.stopwatch.running = true;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
        Persistent.states.timer.stopwatch.paused = false;
        Persistent.states.timer.stopwatch.start = 0;
    }

    function stopwatchRecordLap() {
        const stored = Persistent.states?.timer?.stopwatch?.laps
        const laps = Array.isArray(stored) ? stored.slice() : []
        laps.push(stopwatchTime)
        Persistent.states.timer.stopwatch.laps = laps
    }

    // Countdown Timer
    function refreshCountdown() {
        const elapsed = getCurrentTimeInSeconds() - Persistent.states.timer.countdown.start;
        countdownSecondsLeft = Math.max(0, countdownDuration - elapsed);
        
        if (countdownSecondsLeft <= 0 && countdownRunning) {
            Persistent.states.timer.countdown.running = false;
            Persistent.states.timer.countdown.paused = false;
            Notifications.sendInternal({
                summary: "Timer",
                body: Translation.tr("Time's up!"),
                appName: "Shell",
                appIcon: "alarm-symbolic",
            });
            if (Config.options?.sounds?.timer ?? false) {
                Audio.playEvent("timerDone");
            }
        }
    }

    function toggleCountdown(): void {
        if (countdownRunning) {
            if (countdownPaused) {
                const remaining = root._decodePausedValue(
                    Persistent.states.timer.countdown.start,
                    countdownSecondsLeft,
                    countdownDuration)
                countdownSecondsLeft = remaining
                Persistent.states.timer.countdown.start = getCurrentTimeInSeconds()
                    - (countdownDuration - remaining)
                Persistent.states.timer.countdown.paused = false
            } else {
                root.refreshCountdown()
                if (!root.countdownRunning)
                    return
                Persistent.states.timer.countdown.start = root._encodePausedValue(countdownSecondsLeft)
                Persistent.states.timer.countdown.paused = true
            }
        } else {
            Persistent.states.timer.countdown.start = getCurrentTimeInSeconds()
                - (countdownDuration - countdownSecondsLeft)
            Persistent.states.timer.countdown.paused = false;
            Persistent.states.timer.countdown.running = true;
        }
    }

    function stopCountdown(): void {
        resetCountdown();
    }

    function resetCountdown(): void {
        Persistent.states.timer.countdown.running = false;
        Persistent.states.timer.countdown.paused = false;
        countdownSecondsLeft = countdownDuration;
        Persistent.states.timer.countdown.start = getCurrentTimeInSeconds();
    }

    function setCountdownDuration(seconds: int): void {
        const normalized = root._positiveInt(seconds, 300)
        Persistent.states.timer.countdown.duration = normalized;
        if (!countdownRunning) {
            countdownSecondsLeft = normalized;
        }
    }
}
