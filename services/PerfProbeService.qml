pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

// Opt-in, bounded QML/JS runtime performance probe (PERF-F01 #27).
// Zero idle overhead: no timers, window listeners, or allocations run when
// `active` is false. Activated only on explicit user/CLI request via IPC.
Singleton {
    id: root

    property bool active: false
    property string sessionId: ""
    property string scenarioId: "ad-hoc"
    property real startedAtMs: 0
    property real stoppedAtMs: 0
    property bool autoStopped: false

    // Hard safety bounds so an opt-in session cannot grow unboundedly
    property int maxDurationMs: 60000
    property int maxFrameSamples: 1200
    property int maxSpans: 500
    readonly property int hardMaxDurationMs: 300000
    readonly property int hardMaxFrameSamples: 2400
    readonly property int hardMaxSpans: 1000

    property var _shellRoot: null
    property var _frameIntervals: []
    property var _slowFrameEvents: []
    property int _droppedFrameSamples: 0
    property var _spans: []
    property int _droppedSpans: 0
    property var _heartbeatJitterMs: []
    property real _heartbeatLastMs: 0
    property int _heartbeatOver16Ms: 0
    property int _heartbeatOver33Ms: 0
    property int _heartbeatOver100Ms: 0
    property real _heartbeatMaxJitterMs: 0
    property var _surfaceOpenTimestamps: ({})
    property var _startSnapshot: null

    function registerShellRoot(shellObj: var): void {
        root._shellRoot = shellObj
    }

    function _clampInt(val: var, fallback: int, minVal: int, maxVal: int): int {
        const num = Number(val)
        if (!Number.isFinite(num))
            return fallback
        return Math.max(minVal, Math.min(maxVal, Math.round(num)))
    }

    function _sanitizeLabel(raw: var, maxLen: int): string {
        const text = String(raw ?? "").trim()
        if (!text.length)
            return "unknown"
        return text.slice(0, maxLen)
    }

    function _percentile(sorted: var, p: real): var {
        const n = sorted.length
        if (!n)
            return null
        const idx = Math.min(n - 1, Math.max(0, Math.ceil(n * p) - 1))
        return Number(sorted[idx].toFixed(3))
    }

    function _computeStats(samples: var): var {
        const copy = (samples ?? []).slice().filter(v => Number.isFinite(v) && v >= 0)
        copy.sort((a, b) => a - b)
        const n = copy.length
        if (!n) {
            return {
                count: 0,
                minMs: null,
                p50Ms: null,
                p95Ms: null,
                p99Ms: null,
                maxMs: null,
                meanMs: null,
                over16msCount: 0,
                over25msCount: 0,
                over33msCount: 0
            }
        }
        const sum = copy.reduce((acc, v) => acc + v, 0)
        return {
            count: n,
            minMs: Number(copy[0].toFixed(3)),
            p50Ms: root._percentile(copy, 0.50),
            p95Ms: root._percentile(copy, 0.95),
            p99Ms: root._percentile(copy, 0.99),
            maxMs: Number(copy[n - 1].toFixed(3)),
            meanMs: Number((sum / n).toFixed(3)),
            over16msCount: copy.filter(v => v > 16.7).length,
            over25msCount: copy.filter(v => v > 25.0).length,
            over33msCount: copy.filter(v => v > 33.3).length
        }
    }

    function _buildArchitectureSnapshot(): var {
        const sr = root._shellRoot
        const bootCompleted = Number(sr?._bootCompletedAt ?? 0)
        const bootConfig = Number(sr?._bootConfigReadyAt ?? 0)
        const bootEntry = Number(sr?._bootShellEntryAt ?? 0)
        const bootDeferred = Number(sr?._bootDeferredAt ?? 0)
        const bootLate = Number(sr?._bootLateFeaturesAt ?? 0)
        return {
            timestampMs: Date.now(),
            shellPid: Quickshell.processId,
            shellPath: String(Quickshell.shellPath("") ?? ""),
            activePanelFamily: String(sr?.activePanelFamily ?? Config.options?.panelFamily ?? "ii"),
            mountedPanelFamily: String(sr?.mountedPanelFamily ?? ""),
            familyMountReady: Boolean(sr?.familyMountReady ?? false),
            shellEntryReady: Boolean(GlobalStates.shellEntryReady),
            deferredPanelsReady: Boolean(GlobalStates.deferredPanelsReady),
            screenCount: Number(Quickshell.screens?.length ?? 0),
            animationsEnabled: Boolean(Appearance.animationsEnabled),
            bootPhases: {
                componentCompletedAtMs: bootCompleted,
                configReadyDeltaMs: bootCompleted > 0 && bootConfig >= bootCompleted ? Math.round(bootConfig - bootCompleted) : null,
                shellEntryDeltaMs: bootConfig > 0 && bootEntry >= bootConfig ? Math.round(bootEntry - bootConfig) : null,
                deferredReadyDeltaMs: bootEntry > 0 && bootDeferred >= bootEntry ? Math.round(bootDeferred - bootEntry) : null,
                lateFeaturesDeltaMs: bootDeferred > 0 && bootLate >= bootDeferred ? Math.round(bootLate - bootDeferred) : null
            },
            openSurfaces: {
                dashboard: Boolean(GlobalStates.dashboardOpen),
                overview: Boolean(GlobalStates.overviewOpen),
                controlPanel: Boolean(GlobalStates.controlPanelOpen),
                notificationCenter: Boolean(GlobalStates.notificationCenterOpen),
                sidebarLeft: Boolean(GlobalStates.sidebarLeftOpen),
                sidebarRight: Boolean(GlobalStates.sidebarRightOpen),
                mediaControls: Boolean(GlobalStates.mediaControlsOpen),
                settingsOverlay: Boolean(GlobalStates.settingsOverlayOpen),
                abyssPopupKind: root._sanitizeLabel(GlobalStates.abyssPopupKind, 32),
                waffleActionCenter: Boolean(GlobalStates.waffleActionCenterOpen),
                waffleNotificationCenter: Boolean(GlobalStates.waffleNotificationCenterOpen),
                waffleWidgets: Boolean(GlobalStates.waffleWidgetsOpen),
                search: Boolean(GlobalStates.searchOpen)
            },
            memoryPressure: {
                deletedJsGcMappings: Number(MemoryPressureService.currentDeletedMappings ?? 0),
                totalJsGcMappings: Number(MemoryPressureService.currentTotalMappings ?? 0),
                threshold: Number(MemoryPressureService.deletedMappingsThreshold ?? 300),
                monitoringEnabled: Boolean(MemoryPressureService.enabled)
            }
        }
    }

    function recordFrameInterval(surfaceId: string, intervalMs: real): void {
        if (!root.active)
            return
        const ms = Number(intervalMs)
        if (!Number.isFinite(ms) || ms < 0)
            return
        if (root._frameIntervals.length < root.maxFrameSamples) {
            root._frameIntervals.push(ms)
            if (ms > 25.0 && root._slowFrameEvents.length < 64) {
                root._slowFrameEvents.push({
                    timestampMs: Date.now(),
                    surfaceId: root._sanitizeLabel(surfaceId, 48),
                    intervalMs: Number(ms.toFixed(3)),
                    attribution: "instrumented_span"
                })
            }
        } else {
            root._droppedFrameSamples++
        }
    }

    function _appendSpan(moduleId: string, spanName: string, durationMs: real, category: string): bool {
        if (!root.active)
            return false
        const dur = Number(durationMs)
        if (!Number.isFinite(dur) || dur < 0)
            return false
        if (root._spans.length >= root.maxSpans) {
            root._droppedSpans++
            return false
        }
        root._spans.push({
            timestampMs: Date.now(),
            moduleId: root._sanitizeLabel(moduleId, 48),
            spanName: root._sanitizeLabel(spanName, 64),
            durationMs: Number(dur.toFixed(3)),
            category: root._sanitizeLabel(category, 32),
            attribution: "instrumented_span"
        })
        return true
    }

    function _trackSurfaceToggle(surfaceId: string, isOpen: bool): void {
        if (!root.active)
            return
        const now = Date.now()
        const map = root._surfaceOpenTimestamps ?? ({})
        if (isOpen) {
            map[surfaceId] = now
            root._surfaceOpenTimestamps = map
            root._appendSpan(surfaceId, "surface_open_trigger", 0, "lifecycle")
        } else {
            const openedAt = Number(map[surfaceId] ?? 0)
            const residencyMs = openedAt > 0 && now >= openedAt ? (now - openedAt) : 0
            delete map[surfaceId]
            root._surfaceOpenTimestamps = map
            root._appendSpan(surfaceId, "surface_close_residency", residencyMs, "lifecycle")
        }
    }

    function startSession(optionsJson: string): string {
        let opts = ({})
        const raw = String(optionsJson ?? "").trim()
        if (raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                if (parsed && typeof parsed === "object")
                    opts = parsed
            } catch (e) {
                return JSON.stringify({
                    ok: false,
                    errorCode: "INVALID_OPTIONS_JSON",
                    message: String(e)
                })
            }
        }

        root.maxDurationMs = root._clampInt(opts.maxDurationMs, 60000, 1000, root.hardMaxDurationMs)
        root.maxFrameSamples = root._clampInt(opts.maxFrameSamples, 1200, 60, root.hardMaxFrameSamples)
        root.maxSpans = root._clampInt(opts.maxSpans, 500, 32, root.hardMaxSpans)
        root.scenarioId = root._sanitizeLabel(opts.scenarioId ?? "ad-hoc", 64)
        root.sessionId = "perf-" + String(Date.now()) + "-" + String(Quickshell.processId)
        root.startedAtMs = Date.now()
        root.stoppedAtMs = 0
        root.autoStopped = false

        root._frameIntervals = []
        root._slowFrameEvents = []
        root._droppedFrameSamples = 0
        root._spans = []
        root._droppedSpans = 0
        root._heartbeatJitterMs = []
        root._heartbeatLastMs = Date.now()
        root._heartbeatOver16Ms = 0
        root._heartbeatOver33Ms = 0
        root._heartbeatOver100Ms = 0
        root._heartbeatMaxJitterMs = 0
        root._surfaceOpenTimestamps = ({})
        root._startSnapshot = root._buildArchitectureSnapshot()
        root.active = true

        return JSON.stringify({
            ok: true,
            active: true,
            sessionId: root.sessionId,
            scenarioId: root.scenarioId,
            startedAtMs: root.startedAtMs,
            shellPid: Quickshell.processId,
            shellPath: String(Quickshell.shellPath("") ?? ""),
            activePanelFamily: String(root._startSnapshot.activePanelFamily),
            budgets: {
                maxDurationMs: root.maxDurationMs,
                maxFrameSamples: root.maxFrameSamples,
                maxSpans: root.maxSpans
            }
        })
    }

    function stopSession(wasAutoStopped: bool): string {
        const wasActive = root.active
        root.active = false
        root.stoppedAtMs = Date.now()
        root.autoStopped = wasAutoStopped
        const endSnapshot = root._buildArchitectureSnapshot()
        const frameStats = root._computeStats(root._frameIntervals)
        const jitterStats = root._computeStats(root._heartbeatJitterMs)

        return JSON.stringify({
            ok: true,
            wasActive: wasActive,
            autoStopped: root.autoStopped,
            sessionId: root.sessionId,
            scenarioId: root.scenarioId,
            startedAtMs: root.startedAtMs,
            stoppedAtMs: root.stoppedAtMs,
            durationMs: root.startedAtMs > 0 ? Math.max(0, root.stoppedAtMs - root.startedAtMs) : 0,
            shellPid: Quickshell.processId,
            shellPath: String(Quickshell.shellPath("") ?? ""),
            attributionNote: "QQuickWindow frameSwapped and event-loop heartbeat are wall-clock callback intervals (instrumented_span), not compositor hardware presentation or per-object GPU counters.",
            frameTiming: {
                attribution: "instrumented_span",
                sampleSource: "QQuickWindow.frameSwapped wall-clock delta (ms)",
                stats: frameStats,
                droppedSamples: root._droppedFrameSamples,
                slowEvents: root._slowFrameEvents.slice()
            },
            eventLoopHeartbeat: {
                attribution: "instrumented_span",
                sampleSource: "Qt main-thread 100ms Timer dispatch jitter (ms)",
                intervalTargetMs: 100,
                stats: jitterStats,
                over16msStallCount: root._heartbeatOver16Ms,
                over33msStallCount: root._heartbeatOver33Ms,
                over100msStallCount: root._heartbeatOver100Ms,
                maxJitterMs: Number(root._heartbeatMaxJitterMs.toFixed(3))
            },
            spans: {
                attribution: "instrumented_span",
                count: root._spans.length,
                droppedSpans: root._droppedSpans,
                records: root._spans.slice()
            },
            startSnapshot: root._startSnapshot,
            endSnapshot: endSnapshot
        })
    }

    function cancelSession(): string {
        root.active = false
        root.stoppedAtMs = Date.now()
        root._frameIntervals = []
        root._slowFrameEvents = []
        root._droppedFrameSamples = 0
        root._spans = []
        root._droppedSpans = 0
        root._heartbeatJitterMs = []
        root._surfaceOpenTimestamps = ({})
        return JSON.stringify({
            ok: true,
            active: false,
            cancelled: true,
            sessionId: root.sessionId,
            shellPid: Quickshell.processId
        })
    }

    function getStatus(): string {
        return JSON.stringify({
            ok: true,
            active: root.active,
            sessionId: root.sessionId,
            scenarioId: root.scenarioId,
            startedAtMs: root.startedAtMs,
            elapsedMs: root.active && root.startedAtMs > 0 ? Math.max(0, Date.now() - root.startedAtMs) : 0,
            frameSampleCount: root._frameIntervals.length,
            spanCount: root._spans.length,
            heartbeatSampleCount: root._heartbeatJitterMs.length,
            budgets: {
                maxDurationMs: root.maxDurationMs,
                maxFrameSamples: root.maxFrameSamples,
                maxSpans: root.maxSpans
            },
            snapshot: root._buildArchitectureSnapshot()
        })
    }

    Timer {
        id: heartbeatTimer
        interval: 100
        repeat: true
        running: root.active
        onTriggered: {
            const now = Date.now()
            const prev = root._heartbeatLastMs
            root._heartbeatLastMs = now
            if (prev <= 0)
                return
            const elapsed = Math.max(0, now - prev)
            const jitter = Math.max(0, elapsed - heartbeatTimer.interval)
            if (root._heartbeatJitterMs.length < root.maxFrameSamples)
                root._heartbeatJitterMs.push(jitter)
            if (jitter > root._heartbeatMaxJitterMs)
                root._heartbeatMaxJitterMs = jitter
            if (jitter > 16.7)
                root._heartbeatOver16Ms++
            if (jitter > 33.3)
                root._heartbeatOver33Ms++
            if (jitter > 100.0) {
                root._heartbeatOver100Ms++
                root._appendSpan("mainEventLoop", "heartbeat_stall_over_100ms", jitter, "event_loop")
            }
        }
    }

    Timer {
        id: autoStopTimer
        interval: root.maxDurationMs
        repeat: false
        running: root.active
        onTriggered: {
            root.stopSession(true)
        }
    }

    Connections {
        target: GlobalStates
        enabled: root.active
        function onDashboardOpenChanged(): void {
            root._trackSurfaceToggle("dashboard", GlobalStates.dashboardOpen)
        }
        function onOverviewOpenChanged(): void {
            root._trackSurfaceToggle("overview", GlobalStates.overviewOpen)
        }
        function onControlPanelOpenChanged(): void {
            root._trackSurfaceToggle("controlPanel", GlobalStates.controlPanelOpen)
        }
        function onNotificationCenterOpenChanged(): void {
            root._trackSurfaceToggle("notificationCenter", GlobalStates.notificationCenterOpen)
        }
        function onSidebarLeftOpenChanged(): void {
            root._trackSurfaceToggle("sidebarLeft", GlobalStates.sidebarLeftOpen)
        }
        function onSidebarRightOpenChanged(): void {
            root._trackSurfaceToggle("sidebarRight", GlobalStates.sidebarRightOpen)
        }
        function onMediaControlsOpenChanged(): void {
            root._trackSurfaceToggle("mediaControls", GlobalStates.mediaControlsOpen)
        }
        function onSettingsOverlayOpenChanged(): void {
            root._trackSurfaceToggle("settingsOverlay", GlobalStates.settingsOverlayOpen)
        }
        function onWaffleActionCenterOpenChanged(): void {
            root._trackSurfaceToggle("waffleActionCenter", GlobalStates.waffleActionCenterOpen)
        }
        function onWaffleNotificationCenterOpenChanged(): void {
            root._trackSurfaceToggle("waffleNotificationCenter", GlobalStates.waffleNotificationCenterOpen)
        }
        function onWaffleWidgetsOpenChanged(): void {
            root._trackSurfaceToggle("waffleWidgets", GlobalStates.waffleWidgetsOpen)
        }
        function onSearchOpenChanged(): void {
            root._trackSurfaceToggle("waffleSearch", GlobalStates.searchOpen)
        }
        function onAbyssPopupKindChanged(): void {
            const kind = String(GlobalStates.abyssPopupKind ?? "")
            root._trackSurfaceToggle("abyssPopup:" + (kind.length ? kind : "none"), kind.length > 0)
        }
    }

    IpcHandler {
        target: "perfProbe"
        function start(optionsJson: string): string {
            return root.startSession(optionsJson)
        }
        function status(): string {
            return root.getStatus()
        }
        function stop(): string {
            return root.stopSession(false)
        }
        function cancel(): string {
            return root.cancelSession()
        }
        function snapshot(): string {
            return JSON.stringify({
                ok: true,
                snapshot: root._buildArchitectureSnapshot()
            })
        }
        function recordSpan(moduleId: string, spanName: string, durationMs: string): string {
            const recorded = root._appendSpan(moduleId, spanName, Number(durationMs), "custom")
            return JSON.stringify({
                ok: recorded,
                active: root.active,
                spanCount: root._spans.length
            })
        }
    }
}
