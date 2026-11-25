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
    function normalizeUrl(rawUrl): string {
        const trimmed = String(rawUrl ?? "").trim()
        if (!trimmed) return ""
        return trimmed.replace(/^webcals?:\/\//i, "https://")
    }
    function isHolidaySource(source): bool {
        if (!source || typeof source !== "object") return false
        if (source.isHoliday === true || source.kind === "holiday") return true
        const url = String(source.url ?? "").toLowerCase()
        return url.includes("%23holiday%40group.v.calendar.google.com")
            || url.includes("#holiday@group.v.calendar.google.com")
            || url.includes("/holidays/")
    }
    readonly property var holidayPresets: [
        {
            id: "preset_vn_vi",
            name: "Vietnam Holidays (VI · Solar & Lunar)",
            shortLabel: "Vietnam (VI)",
            url: "https://calendar.google.com/calendar/ical/vi.vietnamese%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#EA4335"
        },
        {
            id: "preset_vn_en",
            name: "Vietnam Holidays (EN · Solar & Lunar)",
            shortLabel: "Vietnam (EN)",
            url: "https://calendar.google.com/calendar/ical/en.vietnamese%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#E67C73"
        },
        {
            id: "preset_us",
            name: "United States Holidays",
            shortLabel: "United States",
            url: "https://calendar.google.com/calendar/ical/en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#4285F4"
        },
        {
            id: "preset_jp",
            name: "Japan Holidays",
            shortLabel: "Japan",
            url: "https://calendar.google.com/calendar/ical/en.japanese%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#D81B60"
        },
        {
            id: "preset_uk",
            name: "United Kingdom Holidays",
            shortLabel: "UK",
            url: "https://calendar.google.com/calendar/ical/en.uk%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#7986CB"
        },
        {
            id: "preset_kr",
            name: "South Korea Holidays",
            shortLabel: "South Korea",
            url: "https://calendar.google.com/calendar/ical/en.south_korea%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#FF6D01"
        },
        {
            id: "preset_sg",
            name: "Singapore Holidays",
            shortLabel: "Singapore",
            url: "https://calendar.google.com/calendar/ical/en.singapore%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#33B679"
        },
        {
            id: "preset_de",
            name: "Germany Holidays",
            shortLabel: "Germany",
            url: "https://calendar.google.com/calendar/ical/en.german%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#F6BF26"
        },
        {
            id: "preset_fr",
            name: "France Holidays",
            shortLabel: "France",
            url: "https://calendar.google.com/calendar/ical/en.french%23holiday%40group.v.calendar.google.com/public/basic.ics",
            color: "#8E24AA"
        }
    ]
    readonly property var sources: {
        const configured = Config.options?.calendar?.externalSync?.sources
        if (!configured || typeof configured.length !== "number")
            return []
        const list = Array.from(configured)
        return list
            .filter(source => source && typeof source === "object" && !Array.isArray(source))
            .map(source => {
                const normUrl = root.normalizeUrl(source.url)
                const holiday = root.isHolidaySource(source)
                return Object.assign({}, source, {
                    url: normUrl,
                    isHoliday: holiday,
                    kind: holiday ? "holiday" : (source.kind || "event")
                })
            })
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

    property bool _initialFetchPending: false
    Component.onCompleted: {
        if (!root.enabled) {
            root.ready = true
            return
        }
        root._initialFetchPending = root.sources.length > 0
        loadCache()
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
    property var _previousEventsBySource: ({})
    property bool _fetchHadError: false

    function _snapshotEventsBySource(): var {
        const map = {}
        const current = Array.isArray(root.events) ? root.events : []
        for (let i = 0; i < current.length; ++i) {
            const ev = current[i]
            const sid = String(ev?.sourceId ?? "")
            if (!sid) continue
            if (!map[sid]) map[sid] = []
            map[sid].push(ev)
        }
        return map
    }

    function _preserveCachedForSource(source, errMsg): void {
        if (!source) return
        let cached = root._previousEventsBySource[source.id]
        if (!Array.isArray(cached) || cached.length === 0) {
            cached = (Array.isArray(root.events) ? root.events : []).filter(e => String(e?.sourceId ?? "") === source.id)
        }
        const preserved = Array.isArray(cached) ? cached : []
        if (preserved.length > 0)
            root._fetchedEvents = root._fetchedEvents.concat(preserved)
        root._updateSourceStatus(source.id, {
            error: errMsg,
            stale: preserved.length > 0,
            cachedCount: preserved.length,
            lastAttempt: new Date().toISOString()
        })
        root.sourceError(source.id, errMsg)
    }

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
        root._previousEventsBySource = root._snapshotEventsBySource()
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
                root._preserveCachedForSource(source, errMsg)
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
                root._preserveCachedForSource(source, errMsg)
            } else if (!/BEGIN:VCALENDAR/i.test(rawBody)) {
                const errMsg = "Invalid calendar response (missing BEGIN:VCALENDAR)"
                root._fetchHadError = true
                _log("Error fetching", source.name, ":", errMsg)
                root._preserveCachedForSource(source, errMsg)
            } else {
                try {
                    const holiday = root.isHolidaySource(source)
                    const parsed = IcsParser.parseICS(rawBody, source.id, source.name, source.color, {
                        isHoliday: holiday,
                        kind: holiday ? "holiday" : "event"
                    })
                    root._fetchedEvents = root._fetchedEvents.concat(parsed)
                    root._updateSourceStatus(source.id, {
                        error: "",
                        stale: false,
                        lastFetch: new Date().toISOString(),
                        eventCount: parsed.length
                    })
                    _log("Parsed", parsed.length, "events from", source.name)
                } catch (e) {
                    const errMsg = `Parse error: ${e.message}`
                    root._fetchHadError = true
                    _log("Parse error for", source.name, ":", e.message)
                    root._preserveCachedForSource(source, errMsg)
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
    function addSource(name: string, url: string, color: string, isHoliday = false): void {
        const cleanUrl = root.normalizeUrl(url)
        if (!cleanUrl) return
        const holiday = Boolean(isHoliday) || root.isHolidaySource({ url: cleanUrl })
        const newSource = {
            id: _generateId(),
            name: String(name ?? "").trim() || "External Calendar",
            url: cleanUrl,
            color: color || _nextColor(),
            enabled: true,
            isHoliday: holiday,
            kind: holiday ? "holiday" : "event"
        }
        const updated = [...root.sources, newSource]
        Config.setNestedValue("calendar.externalSync.sources", updated)
    }

    function hasHolidayPreset(presetId: string): bool {
        const preset = root.holidayPresets.find(p => p.id === presetId)
        if (!preset) return false
        const targetUrl = root.normalizeUrl(preset.url).toLowerCase()
        return root.sources.some(s => s.enabled !== false && root.normalizeUrl(s.url).toLowerCase() === targetUrl)
    }

    function toggleHolidayPreset(presetId: string): void {
        const preset = root.holidayPresets.find(p => p.id === presetId)
        if (!preset) return
        const targetUrl = root.normalizeUrl(preset.url).toLowerCase()
        const existing = root.sources.find(s => root.normalizeUrl(s.url).toLowerCase() === targetUrl)
        if (existing) {
            if (existing.enabled) {
                root.removeSource(existing.id)
            } else {
                if (!root.enabled)
                    Config.setNestedValue("calendar.externalSync.enable", true)
                root.toggleSource(existing.id, true)
            }
            return
        }
        if (!root.enabled)
            Config.setNestedValue("calendar.externalSync.enable", true)
        root.addSource(preset.name, preset.url, preset.color, true)
    }

    function removeSource(sourceId: string): void {
        const updated = root.sources.filter(s => s.id !== sourceId)
        Config.setNestedValue("calendar.externalSync.sources", updated)
        // Clean cached events from this source
        root.events = root.events.filter(e => e.sourceId !== sourceId)
        root.eventsUpdated()
        root.saveCache()
    }

    function updateSource(sourceId: string, updates: var): void {
        const sources = root.sources.map(source => Object.assign({}, source))
        const idx = sources.findIndex(s => s.id === sourceId)
        if (idx !== -1) {
            const cleanUpdates = Object.assign({}, updates)
            if (typeof cleanUpdates.url === "string")
                cleanUpdates.url = root.normalizeUrl(cleanUpdates.url)
            sources[idx] = Object.assign({}, sources[idx], cleanUpdates)
            const holiday = root.isHolidaySource(sources[idx])
            sources[idx].isHoliday = holiday
            sources[idx].kind = holiday ? "holiday" : "event"
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
        root._previousEventsBySource = root._snapshotEventsBySource()
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
                if (root._initialFetchPending) {
                    root._initialFetchPending = false
                    if (root.enabled && root.sources.length > 0)
                        Qt.callLater(() => root.fetchAll())
                }
                return
            }
            try {
                const data = JSON.parse(content)
                const holidayIds = {}
                for (let sIdx = 0; sIdx < root.sources.length; ++sIdx) {
                    if (root.isHolidaySource(root.sources[sIdx]))
                        holidayIds[root.sources[sIdx].id] = true
                }
                root.events = Array.isArray(data?.events)
                    ? data.events
                        .filter(event => event && typeof event === "object" && !Array.isArray(event))
                        .map(event => {
                            const hol = event.isHoliday === true || event.kind === "holiday" || Boolean(holidayIds[event.sourceId])
                            return Object.assign({}, event, {
                                isHoliday: hol,
                                kind: hol ? "holiday" : (event.kind || "event")
                            })
                        })
                    : []
                root.sourceStatuses = data?.sourceStatuses && typeof data.sourceStatuses === "object"
                    && !Array.isArray(data.sourceStatuses) ? data.sourceStatuses : {}
                root.ready = true
                root.eventsUpdated()
                _log("Loaded cache:", root.events.length, "events")
            } catch (e) {
                _log("Cache parse error:", e.message)
                root.events = []
                root.sourceStatuses = {}
                root.ready = true
            }
            if (root._initialFetchPending) {
                root._initialFetchPending = false
                if (root.enabled && root.sources.length > 0)
                    Qt.callLater(() => root.fetchAll())
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                _log("No cache file, starting fresh")
            }
            root.ready = true
            if (root._initialFetchPending) {
                root._initialFetchPending = false
                if (root.enabled && root.sources.length > 0)
                    Qt.callLater(() => root.fetchAll())
            }
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
