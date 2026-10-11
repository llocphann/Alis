pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property string filePath: Directories.eventsPath
    property var list: []
    property int nextId: 1
    property bool ready: false
    property bool _saving: false
    property bool _saveQueued: false
    property bool _reloadAfterSaveFailure: false
    property bool _saveFailed: false
    property bool _loadQueued: false
    property string _saveSnapshotJson: ""
    property string _lastSavedJson: ""
    property string _durableSnapshotJson: ""
    property FileView _uncachedWriter: null
    property string errorMessage: ""
    readonly property bool persistenceBusy: _saving || _saveQueued || _reloadAfterSaveFailure || _saveFailed
    // Agenda linking must consume actual acknowledged bytes, never eventAdded
    // (an in-memory change) or FileView's optimistic write cache.
    signal eventsPersisted(var savedEvents)
    function getDurableEvents() {
        return root._durableSnapshotJson.length ? JSON.parse(root._durableSnapshotJson).events : []
    }

    function _reloadFailedWriteCache(): void {
        if (root._reloadAfterSaveFailure)
            eventsFileView.reload()
    }

    function _finishSave(error): void {
        if (!root._saving)
            return
        root._saving = false
        const saveAgain = root._saveQueued
        root._saveQueued = false
        if (error.length>0) {
            root._saveFailed=true
            root.errorMessage=Translation.tr("Could not save Agenda. Your changes remain in memory; retry after restoring write access.")
            console.warn("[Events] Failed to save events:",error)
            root._reloadAfterSaveFailure=true
            Qt.callLater(root._reloadFailedWriteCache)
            return
        }
        root._lastSavedJson=root._saveSnapshotJson
        root._durableSnapshotJson=root._saveSnapshotJson
        root._saveFailed=false
        root.errorMessage=""
        root.eventsPersisted(root.getDurableEvents())
        if (saveAgain) {
            root._saveQueued=true
            Qt.callLater(root.saveToFile)
        } else if (root._loadQueued) {
            root._loadQueued=false
            Qt.callLater(root.loadFromFile)
        }
    }
    function _finishUncachedSave(writer,error): void {
        if(root._uncachedWriter===writer) {
            root._uncachedWriter=null
            root._finishSave(error)
        }
        writer.destroy()
    }
    
    signal eventAdded(var event)
    signal eventRemoved(int id)
    signal eventUpdated(var event)
    signal eventTriggered(var event)

    Component.onCompleted: {
        loadFromFile()
        checkTimer.start()
    }

    function _ensureStorageDirectory(): void {
        const parentDir = root.filePath.substring(0, root.filePath.lastIndexOf('/'))
        if (parentDir.length === 0) {
            root.ready = true
            root.saveToFile()
            return
        }
        if (eventsInitDirProc.running)
            return
        eventsInitDirProc.command = ["/usr/bin/mkdir", "-p", parentDir]
        eventsInitDirProc.attempted = true
        eventsInitDirProc.running = true
    }

    FileView {
        id: eventsFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onLoaded: {
            if (root._reloadAfterSaveFailure) {
                // Refresh FileView's failed-write cache without replacing
                // unsaved edits with the older on-disk event list.
                root._reloadAfterSaveFailure = false
                const saveAgain = root._saveQueued
                root._saveQueued = false
                if (saveAgain)
                    Qt.callLater(root.saveToFile)
                return
            }
            if (root._saving)
                return

            const fileContents = eventsFileView.text()
            if (!fileContents || fileContents.trim() === "") {
                root._lastSavedJson=fileContents || ""
                root._durableSnapshotJson=""
                root.list = []
                root.nextId = 1
                root.ready = true
                return
            }
            try {
                const data = JSON.parse(fileContents)
                const events = []
                let maxId = 0
                if (Array.isArray(data?.events)) {
                    for (let i = 0; i < data.events.length; i++) {
                        const event = data.events[i]
                        if (!(event && typeof event === "object" && !Array.isArray(event)))
                            continue
                        events.push(event)
                        const id = Number(event.id)
                        if (Number.isInteger(id) && id > maxId)
                            maxId = id
                    }
                }
                const storedNextId = Number(data?.nextId)
                root.list = events
                root.nextId = Number.isInteger(storedNextId) && storedNextId > maxId
                    ? storedNextId : maxId + 1
                root._lastSavedJson=fileContents
                root._durableSnapshotJson=JSON.stringify({nextId:root.nextId,events:root.list})
                root.ready = true
                _log("[Events] Loaded", root.list.length, "events")
            } catch (e) {
                root._lastSavedJson=""
                root._durableSnapshotJson=""
                console.warn("[Events] Failed to parse file:", e)
                root.list = []
                root.nextId = 1
                root.ready = true
            }
        }
        onSaved: root._finishSave("")
        onSaveFailed: error=>root._finishSave(String(error))
        onLoadFailed: (error) => {
            if (root._reloadAfterSaveFailure) {
                root._reloadAfterSaveFailure = false
                root._saveQueued = false
                return
            }
            if (error === FileViewError.FileNotFound) {
                console.log("[Events] File not found, creating new file.")
                root.list = []
                root.nextId = 1
                root._ensureStorageDirectory()
            } else {
                console.log("[Events] Error loading file:", error)
                root.list = []
                root.nextId = 1
            }
        }
    }

    Component {
        id:uncachedEventWriter
        FileView {
            preload:false
            onSaved:root._finishUncachedSave(this,"")
            onSaveFailed:error=>root._finishUncachedSave(this,String(error))
        }
    }

    Process {
        id: eventsInitDirProc
        property bool attempted: false
        property bool startObserved: false
        running: false

        onRunningChanged: {
            if (eventsInitDirProc.running) {
                eventsInitDirProc.startObserved = false
                return
            }
            if (!eventsInitDirProc.attempted || eventsInitDirProc.startObserved)
                return
            eventsInitDirProc.attempted = false
            root.ready = true
            console.warn("[Events] Failed to start storage directory creation")
            root.saveToFile()
        }

        onStarted: eventsInitDirProc.startObserved = true

        onExited: (exitCode, exitStatus) => {
            eventsInitDirProc.attempted = false
            root.ready = true
            if (exitCode === 0)
                root.saveToFile()
            else {
                console.warn("[Events] Failed to create storage directory, exit code:", exitCode)
                root.saveToFile()
            }
        }
    }

    // Check for due events every minute
    Timer {
        id: checkTimer
        interval: 60000 // 1 minute
        running: false
        repeat: true
        onTriggered: root.checkDueEvents()
    }

    signal reminderTriggered(var event, int minutesBefore)

    function checkDueEvents() {
        if (!root.ready) return
        const now = new Date()
        const currentTime = now.getTime()
        const eventCount = root.list.length
        let needsSave = false
        
        for (let i = 0; i < eventCount; i++) {
            const event = root.list[i]
            if (!event.dateTime) continue
            
            const eventTime = new Date(event.dateTime).getTime()
            const reminderMinutes = event.reminderMinutes ?? 0
            const reminderTime = eventTime - (reminderMinutes * 60 * 1000)
            
            // Check for reminder notification (before event)
            if (reminderMinutes > 0 && !event.reminderNotified && currentTime >= reminderTime && currentTime < eventTime) {
                root.list[i].reminderNotified = true
                root.reminderTriggered(event, reminderMinutes)
                needsSave = true
            }
            
            // Check for event time notification
            if (!event.notified && currentTime >= eventTime) {
                root.list[i].notified = true
                root.eventTriggered(event)
                needsSave = true
                
                // Handle recurrence - create next occurrence
                if (event.recurrence && event.recurrence !== "none") {
                    root.createNextRecurrence(event, currentTime)
                }
            }
        }
        
        if (needsSave) root.saveToFile()
    }

    function createNextRecurrence(event, afterTime) {
        const eventDate = new Date(event.startDate || event.dateTime)
        const eventTime = eventDate.getTime()
        const targetTime = Number.isFinite(Number(afterTime)) ? Number(afterTime) : Date.now()
        if (!Number.isFinite(eventTime))
            return

        const nextDate = new Date(eventDate)
        
        switch (event.recurrence) {
            case "daily": {
                const daysBehind = Math.max(0, Math.floor((targetTime - eventTime) / 86400000))
                nextDate.setDate(nextDate.getDate() + daysBehind + 1)
                while (nextDate.getTime() <= targetTime)
                    nextDate.setDate(nextDate.getDate() + 1)
                break
            }
            case "weekly": {
                const weeksBehind = Math.max(0, Math.floor((targetTime - eventTime) / (7 * 86400000)))
                nextDate.setDate(nextDate.getDate() + (weeksBehind + 1) * 7)
                while (nextDate.getTime() <= targetTime)
                    nextDate.setDate(nextDate.getDate() + 7)
                break
            }
            case "monthly": {
                const targetDate = new Date(targetTime)
                const monthsBehind = Math.max(0,
                    (targetDate.getFullYear() - eventDate.getFullYear()) * 12
                    + targetDate.getMonth() - eventDate.getMonth())
                nextDate.setMonth(nextDate.getMonth() + Math.max(1, monthsBehind))
                while (nextDate.getTime() <= targetTime)
                    nextDate.setMonth(nextDate.getMonth() + 1)
                break
            }
            case "yearly": {
                const targetDate = new Date(targetTime)
                const yearsBehind = Math.max(1, targetDate.getFullYear() - eventDate.getFullYear())
                nextDate.setFullYear(nextDate.getFullYear() + yearsBehind)
                while (nextDate.getTime() <= targetTime)
                    nextDate.setFullYear(nextDate.getFullYear() + 1)
                break
            }
            default:
                return
        }
        
        // Preserve duration and all-day semantics for the next occurrence.
        const sourceEnd = event.endDate ? new Date(event.endDate) : null
        const durationMs = sourceEnd && Number.isFinite(sourceEnd.getTime())
            ? Math.max(0, sourceEnd.getTime() - eventTime) : 0
        const nextEnd = durationMs > 0
            ? new Date(nextDate.getTime() + durationMs).toISOString() : ""

        root.addEvent(
            event.title,
            event.description,
            nextDate.toISOString(),
            event.category,
            event.priority,
            event.reminderMinutes,
            event.recurrence,
            nextEnd,
            event.allDay === true
        )
    }

    function addEvent(title, description, dateTime, category, priority, reminderMinutes, recurrence, endDate, allDay) {
        if (!root.ready) return null
        const startIso = dateTime || new Date().toISOString()
        const event = {
            id: root.nextId++,
            title: title || "",
            description: description || "",
            // dateTime remains the compatibility start timestamp. Rich local
            // event metadata is additive so existing JSON/consumers still work.
            dateTime: startIso,
            startDate: startIso,
            endDate: endDate || "",
            allDay: allDay === true,
            category: category || "general", // general, birthday, meeting, deadline, reminder
            priority: priority || "normal", // low, normal, high
            reminderMinutes: reminderMinutes ?? 15, // 0, 5, 15, 30, 60, 1440
            recurrence: recurrence || "none", // none, daily, weekly, monthly, yearly
            notified: false,
            reminderNotified: false,
            createdAt: new Date().toISOString()
        }
        
        root.list.push(event)
        root.list = root.list // Trigger binding update
        root.eventAdded(event)
        root.saveToFile()
        return event
    }

    function removeEvent(id) {
        if (!root.ready) return false
        const index = root.list.findIndex(e => e.id === id)
        if (index !== -1) {
            root.list.splice(index, 1)
            root.list = root.list
            root.eventRemoved(id)
            root.saveToFile()
            return true
        }
        return false
    }

    function updateEvent(id, updates) {
        if (!root.ready) return false
        const index = root.list.findIndex(e => e.id === id)
        if (index !== -1) {
            root.list[index] = Object.assign({}, root.list[index], updates)
            root.list = root.list
            root.eventUpdated(root.list[index])
            root.saveToFile()
            return true
        }
        return false
    }

    function getEventsForDate(date) {
        const targetDate = new Date(date)
        targetDate.setHours(0, 0, 0, 0)
        
        return root.list.filter(event => {
            const eventDate = new Date(event.startDate || event.dateTime)
            eventDate.setHours(0, 0, 0, 0)
            // All-day events remain visible for their date even after the
            // midnight reminder/trigger has fired.
            return eventDate.getTime() === targetDate.getTime()
                && (!event.notified || event.allDay === true)
        })
    }
    
    // Get ALL events for a date (including notified/past) - for history view
    function getAllEventsForDate(date) {
        const targetDate = new Date(date)
        targetDate.setHours(0, 0, 0, 0)
        
        return root.list.filter(event => {
            const eventDate = new Date(event.startDate || event.dateTime)
            eventDate.setHours(0, 0, 0, 0)
            return eventDate.getTime() === targetDate.getTime()
        })
    }

    function getUpcomingEvents(days) {
        const now = new Date()
        const future = new Date()
        future.setDate(future.getDate() + (days || 7))
        const startTimes = new Map()
        
        return root.list.filter(event => {
            const eventDate = new Date(event.startDate || event.dateTime)
            startTimes.set(event, eventDate.getTime())
            if (event.allDay === true) {
                const end = event.endDate
                    ? new Date(event.endDate)
                    : new Date(eventDate.getTime() + 86400000)
                return end > now && eventDate <= future
            }
            return eventDate >= now && eventDate <= future && !event.notified
        }).sort((a, b) => startTimes.get(a) - startTimes.get(b))
    }

    function markAsNotified(id) {
        return root.updateEvent(id, { notified: true })
    }

    function saveToFile() {
        if (root._saving || root._reloadAfterSaveFailure) {
            root._saveQueued = true
            return
        }
        const data = {
            nextId: root.nextId,
            events: root.list
        }
        const serialized = JSON.stringify(data, null, 2)
        // Unchanged bytes emit no saved() signal. Do not acquire a write
        // lease for a no-op, or the following real edit will remain queued.
        if (!root._saveFailed && root._lastSavedJson === serialized) {
            root._saveQueued = false
            return
        }
        root._saveQueued = false
        root._saveSnapshotJson=serialized
        root._saving = true
        try {
            if(eventsFileView.text()===serialized) {
                const writer=uncachedEventWriter.createObject(root,{path:Qt.resolvedUrl(root.filePath)})
                if(!writer)throw new Error("Could not create Agenda writer")
                root._uncachedWriter=writer
                writer.setText(serialized)
            }else eventsFileView.setText(serialized)
        }catch(error){root._finishSave(String(error))}
    }

    function loadFromFile() {
        if(root.persistenceBusy) {
            root._loadQueued=true
            if(root._saveFailed && !root._saving && !root._reloadAfterSaveFailure)root.saveToFile()
            return
        }
        root.ready = false
        eventsFileView.reload()
    }

    function getCategoryIcon(category) {
        switch (category) {
            case "birthday": return "cake"
            case "meeting": return "groups"
            case "deadline": return "flag"
            case "reminder": return "notifications"
            default: return "event"
        }
    }

    // getPriorityColor removed — was dead code with hardcoded colors.
    // EventCard already resolves priority colors via Appearance tokens.
}
