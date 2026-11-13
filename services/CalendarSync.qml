pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "calendar_ics.js" as IcsParser

// External calendar sync via ICS/iCal URLs.
// Fetches calendars periodically, parses ICS to JSON, and caches results.
// Zero external deps — uses curl for fetching and JS for parsing.
Singleton {
    id: root

    readonly property bool enabled: Config.options?.calendar?.externalSync?.enable ?? false
    readonly property var sources: {
        const configured = Config.options?.calendar?.externalSync?.sources
        if (!Array.isArray(configured))
            return []
        return configured.filter(source => source && typeof source === "object" && !Array.isArray(source))
    }
    readonly property int refreshMinutes: {
        const configured = Number(Config.options?.calendar?.externalSync?.refreshMinutes)
        return Number.isFinite(configured) && configured > 0
            ? Math.max(1, Math.round(configured)) : 15
    }
    readonly property int fetchIntervalMs: root.refreshMinutes * 60 * 1000

    // All external events, merged from every enabled source
    property var events: []
    // Per-source metadata (id, name, color, lastFetch, eventCount, error)
    property var sourceStatuses: ({})
    property bool fetching: false
    property bool ready: false

    signal eventsUpdated()
    signal fetchStarted()
    signal fetchFinished(bool success)
    signal sourceError(string sourceId, string error)

    // Cache file for persisting between sessions
    readonly property string cachePath: Directories.calendarSyncCachePath

    Component.onCompleted: {
        if (!root.enabled) {
            root.ready = true
            return
        }
        loadCache()
        if (root.sources.length > 0) {
            Qt.callLater(() => root.fetchAll())
        }
    }

    // React to config changes — re-fetch when sources change
    property string _lastSourcesHash: ""
    property bool _sourcesRefreshPending: false
    onSourcesChanged: {
        const hash = JSON.stringify(root.sources)
        if (hash !== root._lastSourcesHash) {
            root._lastSourcesHash = hash
            if (root.enabled) {
                if (root.fetching)
                    root._sourcesRefreshPending = true
                else
                    Qt.callLater(() => root.fetchAll())
            }
        }
    }

    onEnabledChanged: {
        if (root.enabled && root.sources.length > 0) {
            Qt.callLater(() => root.fetchAll())
            return
        }
        if (!root.enabled) {
            root._sourcesRefreshPending = false
            if (fetchProc.running)
                fetchProc.running = false
            root.events = []
            root.ready = true
            root.eventsUpdated()
        }
    }

    // Periodic refresh
    Timer {
        id: fetchTimer
        running: root.enabled && Config.ready && root.sources.length > 0
        repeat: true
        interval: root.fetchIntervalMs
        onTriggered: root.fetchAll()
    }

    // Sequential source fetcher — fetches one source at a time to avoid
    // spawning many curl processes simultaneously
    property int _fetchIndex: -1
    property var _pendingSources: []
    property var _fetchedEvents: []
    property bool _fetchHadError: false

    function fetchAll(): void {
        if (!root.enabled || root.fetching) return
        const enabledSources = root.sources.filter(s => s.enabled
            && typeof s.url === "string" && s.url.trim() !== "")
        if (enabledSources.length === 0) {
            root.events = []
            root.ready = true
            root.eventsUpdated()
            return
        }

        root.fetching = true
        root._pendingSources = enabledSources
        root._fetchedEvents = []
        root._fetchHadError = false
        root._fetchIndex = 0
        root.fetchStarted()
        _log("Fetching", enabledSources.length, "calendar sources")
        _fetchNext()
    }

    function _fetchNext(): void {
        if (!root.enabled) {
            root._sourcesRefreshPending = false
            root._pendingSources = []
            root._fetchedEvents = []
            root._fetchIndex = -1
            root.fetching = false
            root.ready = true
            root.events = []
            root.eventsUpdated()
            root.fetchFinished(false)
            return
        }

        if (root._fetchIndex >= root._pendingSources.length) {
            if (root._sourcesRefreshPending) {
                root._sourcesRefreshPending = false
                root._pendingSources = []
                root._fetchedEvents = []
                root._fetchIndex = -1
                root.fetching = false
                root.fetchFinished(false)
                Qt.callLater(() => root.fetchAll())
                return
            }

            // All done
            root.events = root._fetchedEvents
            root.fetching = false
            root.ready = true
            root.eventsUpdated()
            root.fetchFinished(!root._fetchHadError)
            root.saveCache()
            _log("Fetch complete:", root.events.length, "events from", root._pendingSources.length, "sources")
            return
        }

        const source = root._pendingSources[root._fetchIndex]
        // ICS subscription URLs can contain bearer tokens; never persist them in logs.
        _log("Fetching source:", source.name, "(URL redacted)")
        _currentFetchSource = source
        fetchProc.command = ["/usr/bin/curl", "-sL", "--max-time", "30",
            "--compressed", "-H", "Accept: text/calendar", source.url]
        fetchProc.running = true
    }

    property var _currentFetchSource: null

    Process {
        id: fetchProc
        running: false
        stdout: StdioCollector {
            id: fetchStdoutCollector
        }
        property string _rawData: ""
        property bool startObserved: false

        onRunningChanged: {
            if (running) {
                fetchProc._rawData = ""
                fetchProc.startObserved = false
                return
            }
            if (fetchProc.startObserved)
                return

            const source = root._currentFetchSource
            const errMsg = "curl failed to start"
            root._fetchHadError = true
            if (source) {
                _log("Error fetching", source.name, ":", errMsg)
                root._updateSourceStatus(source.id, { error: errMsg, lastFetch: new Date().toISOString() })
                root.sourceError(source.id, errMsg)
            }
            root._fetchIndex++
            Qt.callLater(() => root._fetchNext())
        }

        onStarted: fetchProc.startObserved = true

        onExited: (code, status) => {
            const source = root._currentFetchSource
            if (!source) {
                root._fetchHadError = true
                root._fetchIndex++
                root._fetchNext()
                return
            }

            const rawBody = String(fetchStdoutCollector.text ?? "")
            if (code !== 0 || rawBody.trim() === "") {
                const errMsg = code !== 0 ? `curl exited with code ${code}` : "Empty response"
                root._fetchHadError = true
                _log("Error fetching", source.name, ":", errMsg)
                root._updateSourceStatus(source.id, { error: errMsg, lastFetch: new Date().toISOString() })
                root.sourceError(source.id, errMsg)
            } else {
                try {
                    const parsed = IcsParser.parseICS(rawBody, source.id, source.name, source.color)
                    root._fetchedEvents = root._fetchedEvents.concat(parsed)
                    root._updateSourceStatus(source.id, {
                        error: "",
                        lastFetch: new Date().toISOString(),
                        eventCount: parsed.length
                    })
                    _log("Parsed", parsed.length, "events from", source.name)
                } catch (e) {
                    const errMsg = `Parse error: ${e.message}`
                    root._fetchHadError = true
                    _log("Parse error for", source.name, ":", e.message)
                    root._updateSourceStatus(source.id, { error: errMsg, lastFetch: new Date().toISOString() })
                    root.sourceError(source.id, errMsg)
                }
            }

            root._fetchIndex++
            root._fetchNext()
        }
    }

    function _updateSourceStatus(sourceId: string, updates: var): void {
        const statuses = Object.assign({}, root.sourceStatuses)
        statuses[sourceId] = Object.assign(statuses[sourceId] || {}, updates)
        root.sourceStatuses = statuses
    }

    // Query: get external events for a specific date
    function getEventsForDate(date: var): var {
        const target = new Date(date)
        target.setHours(0, 0, 0, 0)
        const targetTime = target.getTime()

        return root.events.filter(event => {
            if (event.allDay) {
                const start = new Date(event.startDate)
                start.setHours(0, 0, 0, 0)
                const end = event.endDate ? new Date(event.endDate) : new Date(start)
                end.setHours(0, 0, 0, 0)
                const startTime = start.getTime()
                const endTime = end.getTime()
                // RFC 5545 DTEND is exclusive for all-day events. The parser
                // uses startDate as endDate when DTEND is absent, so preserve
                // that single-day fallback instead of making it disappear.
                if (endTime <= startTime)
                    return targetTime === startTime
                return targetTime >= startTime && targetTime < endTime
            }
            const evtDate = new Date(event.startDate)
            evtDate.setHours(0, 0, 0, 0)
            return evtDate.getTime() === targetTime
        })
    }

    function _getEventBucketsForDates(dates: var): var {
        const targetTimes = []
        const buckets = []
        for (let i = 0; i < dates.length; i++) {
            const target = new Date(dates[i])
            target.setHours(0, 0, 0, 0)
            targetTimes.push(target.getTime())
            buckets.push([])
        }

        for (const event of root.events) {
            if (event.allDay) {
                const start = new Date(event.startDate)
                start.setHours(0, 0, 0, 0)
                const end = event.endDate ? new Date(event.endDate) : new Date(start)
                end.setHours(0, 0, 0, 0)
                const startTime = start.getTime()
                const endTime = end.getTime()
                for (let i = 0; i < targetTimes.length; i++) {
                    const targetTime = targetTimes[i]
                    if (endTime <= startTime) {
                        if (targetTime === startTime)
                            buckets[i].push(event)
                    } else if (targetTime >= startTime && targetTime < endTime) {
                        buckets[i].push(event)
                    }
                }
                continue
            }

            const evtDate = new Date(event.startDate)
            evtDate.setHours(0, 0, 0, 0)
            const eventTime = evtDate.getTime()
            for (let i = 0; i < targetTimes.length; i++) {
                if (eventTime === targetTimes[i])
                    buckets[i].push(event)
            }
        }

        return buckets
    }

    // Query: get all events in a date range (for upcoming view)
    function getUpcomingEvents(days: int): var {
        const now = new Date()
        const today = new Date(now)
        today.setHours(0, 0, 0, 0)
        const future = new Date()
        future.setDate(future.getDate() + (days || 7))
        const startTimes = new Map()

        return root.events.filter(event => {
            if (event.allDay) {
                const start = new Date(event.startDate)
                startTimes.set(event, start.getTime())
                start.setHours(0, 0, 0, 0)
                const end = event.endDate ? new Date(event.endDate) : new Date(start)
                end.setHours(0, 0, 0, 0)
                const startTime = start.getTime()
                const endTime = end.getTime()
                if (endTime <= startTime)
                    return start >= today && start <= future
                // All-day DTEND is exclusive, so include any event whose date
                // span overlaps today through the requested upcoming horizon.
                return start <= future && end > today
            }
            const evtDate = new Date(event.startDate)
            startTimes.set(event, evtDate.getTime())
            return evtDate >= now && evtDate <= future
        }).sort((a, b) => startTimes.get(a) - startTimes.get(b))
    }

    // Query: distinct source colors for events on a given date
    function getSourceColorsForDate(date: var): var {
        const dayEvents = getEventsForDate(date)
        const colors = []
        const seen = new Set()
        for (const evt of dayEvents) {
            if (!seen.has(evt.sourceId)) {
                seen.add(evt.sourceId)
                colors.push(evt.sourceColor)
            }
        }
        return colors
    }

    // Source management (called from Settings UI)
    function addSource(name: string, url: string, color: string): void {
        const newSource = {
            id: _generateId(),
            name: name,
            url: url,
            color: color || _nextColor(),
            enabled: true
        }
        const updated = [...root.sources, newSource]
        Config.setNestedValue("calendar.externalSync.sources", updated)
    }

    function removeSource(sourceId: string): void {
        const updated = root.sources.filter(s => s.id !== sourceId)
        Config.setNestedValue("calendar.externalSync.sources", updated)
        // Clean cached events from this source
        root.events = root.events.filter(e => e.sourceId !== sourceId)
        root.eventsUpdated()
    }

    function updateSource(sourceId: string, updates: var): void {
        const sources = root.sources.map(source => Object.assign({}, source))
        const idx = sources.findIndex(s => s.id === sourceId)
        if (idx !== -1) {
            sources[idx] = Object.assign({}, sources[idx], updates)
            Config.setNestedValue("calendar.externalSync.sources", sources)
        }
    }

    function toggleSource(sourceId: string, enabled: bool): void {
        updateSource(sourceId, { enabled: enabled })
        if (!enabled) {
            root.events = root.events.filter(e => e.sourceId !== sourceId)
            root.eventsUpdated()
        } else {
            Qt.callLater(() => root.fetchAll())
        }
    }

    // Force refresh a single source or all
    function refreshSource(sourceId: string): void {
        if (!root.enabled || root.fetching)
            return

        const source = root.sources.find(s => s.id === sourceId && s.enabled
            && typeof s.url === "string" && s.url.trim() !== "")
        if (!source)
            return

        root.fetching = true
        root._pendingSources = [source]
        root._fetchedEvents = root.events.filter(event => event.sourceId !== sourceId)
        root._fetchHadError = false
        root._fetchIndex = 0
        root.fetchStarted()
        _log("Fetching calendar source:", source.name)
        root._fetchNext()
    }

    function forceRefreshAll(): void {
        Qt.callLater(() => root.fetchAll())
    }

    // Cache persistence
    function saveCache(): void {
        const data = {
            events: root.events,
            sourceStatuses: root.sourceStatuses,
            savedAt: new Date().toISOString()
        }
        cacheFileView.setText(JSON.stringify(data))
    }

    function loadCache(): void {
        cacheFileView.reload()
    }

    FileView {
        id: cacheFileView
        path: root.cachePath
        watchChanges: false
        printErrors: false
        onLoaded: {
            const content = cacheFileView.text()
            if (!content || content.trim() === "") {
                root.ready = true
                return
            }
            try {
                const data = JSON.parse(content)
                root.events = Array.isArray(data?.events)
                    ? data.events.filter(event => event && typeof event === "object" && !Array.isArray(event))
                    : []
                root.sourceStatuses = data?.sourceStatuses && typeof data.sourceStatuses === "object"
                    && !Array.isArray(data.sourceStatuses) ? data.sourceStatuses : {}
                root.ready = true
                _log("Loaded cache:", root.events.length, "events")
            } catch (e) {
                _log("Cache parse error:", e.message)
                root.events = []
                root.sourceStatuses = {}
                root.ready = true
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                _log("No cache file, starting fresh")
            }
            root.ready = true
        }
    }

    // Preset colors for calendar sources
    readonly property var presetColors: [
        "#4285F4", // Google Blue
        "#EA4335", // Google Red
        "#34A853", // Google Green
        "#FBBC05", // Google Yellow
        "#FF6D01", // Orange
        "#46BDC6", // Teal
        "#7986CB", // Indigo
        "#E67C73", // Flamingo
        "#F6BF26", // Banana
        "#33B679", // Sage
        "#8E24AA", // Grape
        "#D81B60", // Lavender
    ]

    property int _colorIndex: 0

    function _nextColor(): string {
        const color = root.presetColors[root._colorIndex % root.presetColors.length]
        root._colorIndex++
        return color
    }

    function _generateId(): string {
        return "cal_" + Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 6)
    }

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1")
            console.log("[CalendarSync]", ...args)
    }
}
