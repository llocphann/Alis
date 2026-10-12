pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "AgendaTodoPolicy.js" as AgendaTodoPolicy
import "EventOccurrences.js" as Occurrences
import "EventRepeatPolicy.js" as RepeatPolicy

Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property string filePath: Directories.eventsPath
    property var list: []
    property var todoUnlinks: []
    // Retain unknown top-level keys from existing Events files untouched.
    // This preserves old backups without running any migration or rewriting them.
    property var retainedStorageFields: ({})
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
    function getDurableTodoUnlinks() {
        return root._durableSnapshotJson.length ? (JSON.parse(root._durableSnapshotJson).todoUnlinks || []) : []
    }
    function _queueTodoUnlink(event,deleteTask) {
        const link=event?.todoLink
        if(!AgendaTodoPolicy.validLink(link) || !link.provider)return
        const existing=root.todoUnlinks.find(value=>value.key===link.key && value.provider===link.provider)
        if(existing) {
            if(deleteTask && !existing.deleteTask)root.todoUnlinks=root.todoUnlinks.map(value=>value===existing?Object.assign({},value,{deleteTask:true}):value)
        } else root.todoUnlinks=root.todoUnlinks.concat([Object.assign({},link,{eventId:event.id,deleteTask:deleteTask===true})])
    }
    function finishTodoUnlink(key,provider) {
        const next=root.todoUnlinks.filter(value=>value.key!==key || value.provider!==provider)
        if(next.length===root.todoUnlinks.length)return false
        root.todoUnlinks=next;root.saveToFile();return true
    }
    function _notifyAgendaLinks() {
        if(root.getDurableEvents().some(event=>AgendaTodoPolicy.validLink(event.todoLink) && event.todoLink.state!=="detached") || root.getDurableTodoUnlinks().some(link=>AgendaTodoPolicy.validLink(link) && link.provider))
            Qt.callLater(()=>Todo._scheduleAgenda())
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
        root._notifyAgendaLinks()
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
                root.todoUnlinks = []
                root.retainedStorageFields = ({})
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
                const nextId = Number.isInteger(storedNextId) && storedNextId > maxId
                    ? storedNextId : maxId + 1
                const unlinks=Array.isArray(data?.todoUnlinks)?data.todoUnlinks:[]
                // Load existing files verbatim. Never automatically group,
                // normalize, migrate, or delete previously persisted Events.
                // Preserve legacy/unknown top-level JSON metadata on save.
                const retained=({})
                for (const key of Object.keys(data)) {
                    if (key!=="schemaVersion" && key!=="nextId"
                            && key!=="events" && key!=="todoUnlinks")
                        Object.defineProperty(retained,key,{
                            value:data[key],enumerable:true,writable:true,configurable:true
                        })
                }
                root.retainedStorageFields=retained
                root.list=events
                root.todoUnlinks=unlinks
                root.nextId=nextId
                root._lastSavedJson=fileContents
                root._durableSnapshotJson=JSON.stringify({
                    nextId:nextId,events:events,todoUnlinks:unlinks
                })
                root.errorMessage=""
                root.ready=true
                root._notifyAgendaLinks()
                _log("[Events] Loaded",root.list.length,"events")
            } catch (e) {
                console.warn("[Events] Failed to parse file:", e)
                // An unreadable store is not an empty Agenda. Keep the last
                // usable snapshot and forbid link/unlink mutations until repaired.
                root.errorMessage="Could not read Agenda. Restore the file and retry."
                root.ready = false
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
            const slots = Occurrences.entries(event)
            let changed = false
            for (let index = 0; index < slots.length; ++index) {
                const slot = slots[index]
                const startMs = new Date(slot.startDate).getTime()
                if (!Number.isFinite(startMs)) continue
                const reminderMinutes = event.reminderMinutes ?? 0
                const reminderTime = startMs - reminderMinutes * 60000
                const notificationEvent = Object.assign({},event,{
                    dateTime:slot.startDate,startDate:slot.startDate,
                    endDate:slot.endDate,occurrenceIndex:index
                })
                if (reminderMinutes > 0 && !slot.reminderNotified
                        && currentTime >= reminderTime && currentTime < startMs) {
                    slot.reminderNotified = true
                    root.reminderTriggered(notificationEvent,reminderMinutes)
                    changed = true
                }
                if (!slot.notified && currentTime >= startMs) {
                    slot.notified = true
                    root.eventTriggered(notificationEvent)
                    changed = true
                    if (slots.length===1 && !Array.isArray(event.occurrences)
                            && event.recurrence && event.recurrence!=="none")
                        root.createNextRecurrence(event,currentTime)
                }
            }
            // The explicit group repeats as a unit, retaining its single
            // Agenda ID, Todo link, original template and occurrence history.
            // Wait for every selected day to fire before creating the next
            // complete calendar cycle; preserve existing single-day behavior.
            if (Array.isArray(event.repeatTemplate) && event.repeatTemplate.length>1
                    && event.recurrence!=="none" && slots.every(slot=>slot.notified)) {
                const future=RepeatPolicy.nextCycle(event.repeatTemplate,
                    event.recurrence,currentTime)
                if (future && future.length) {
                    // Projection uses this boundary to avoid projecting each
                    // archived cycle again while keeping every selected weekday
                    // alive until the entire current cycle has elapsed.
                    event.repeatCycleStart=slots.length
                    slots.push(...future)
                    changed=true
                }
            }
            if (changed) {
                root.list[i] = Array.isArray(event.occurrences)
                    ? Occurrences.store(event,slots)
                    : Object.assign({},event,{notified:slots[0].notified,
                        reminderNotified:slots[0].reminderNotified})
                needsSave = true
            }
        }
        if (needsSave) {
            root.list = root.list.slice()
            root.saveToFile()
        }
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

    function addEvent(title, description, dateTime, category, priority, reminderMinutes, recurrence, endDate, allDay, occurrenceRanges) {
        if (!root.ready) return null
        // A selected date group is one Agenda with one ID and Todo link,
        // whether one-time or repeating as a calendar-cycle template.
        const supplied=Array.isArray(occurrenceRanges) ? occurrenceRanges : []
        if (supplied.length>512) return null
        const explicitSlots=[]
        if (supplied.length>1) {
            for (const range of supplied) {
                const slot=Occurrences.entry(range?.startDate,range?.endDate,false,false)
                const start=new Date(range?.startDate),end=new Date(range?.endDate)
                if (!slot || !Number.isFinite(start.getTime())
                        || !Number.isFinite(end.getTime()) || end<=start
                        || explicitSlots.some(existing=>
                            existing.startDate===slot.startDate
                            && existing.endDate===slot.endDate)) return null
                explicitSlots.push(slot)
            }
            explicitSlots.sort((a,b)=>a.startDate.localeCompare(b.startDate))
            if (!RepeatPolicy.templateAllowed(explicitSlots,recurrence || "none"))
                return null
        }
        const bulk=explicitSlots.length>1
        const startIso=bulk ? explicitSlots[0].startDate
            : (dateTime || new Date().toISOString())
        const firstEnd=bulk ? explicitSlots[0].endDate : (endDate || "")
        // A matching, non-recurring title with compatible metadata denotes a
        // second time slot of the same event, not a second Todo-linked event.
        // Never merge existing records on load or conflate different details.
        const incoming = {title:title || "",description:description || "",
            startDate:startIso,endDate:firstEnd,category:category || "general",
            priority:priority || "normal",reminderMinutes:reminderMinutes ?? 15,
            recurrence:recurrence || "none",allDay:allDay === true};
        const groupIndex = bulk ? -1
            : root.list.findIndex(old => Occurrences.compatible(old,incoming))
        if (groupIndex >= 0) {
            const result = Occurrences.append(root.list[groupIndex],incoming)
            if (result) {
                if (!result.duplicate) {
                    root.list[groupIndex] = result.event
                    root.list = root.list.slice()
                    root.eventUpdated(result.event)
                    root.saveToFile()
                }
                return root.list[groupIndex]
            }
        }
        let event = {
            id: root.nextId++,
            title: title || "",
            description: description || "",
            // dateTime remains the compatibility start timestamp. Rich local
            // event metadata is additive so existing JSON/consumers still work.
            dateTime: startIso,
            startDate: startIso,
            endDate: firstEnd,
            allDay: allDay === true,
            category: category || "general", // general, birthday, meeting, deadline, reminder
            priority: priority || "normal", // low, normal, high
            reminderMinutes: reminderMinutes ?? 15, // 0, 5, 15, 30, 60, 1440
            recurrence: recurrence || "none", // none, daily, weekly, monthly, yearly
            notified: false,
            reminderNotified: false,
            createdAt: new Date().toISOString(),
            todoLink: AgendaTodoPolicy.newLink(root.nextId - 1, Date.now(), Math.random().toString(36).slice(2, 14))
        }
        
        if (bulk) {
            event=Occurrences.store(event,explicitSlots)
            if ((recurrence || "none")!=="none") {
                // Immutable civil-time template: further cycles are generated
                // from these originals, not the previous shifted cycle.
                event.repeatTemplate=explicitSlots.map(slot=>({
                    startDate:slot.startDate,endDate:slot.endDate
                }))
                event.repeatCycleStart=0
            }
        }
        root.list.push(event)
        root.list = root.list.slice(0)
        root.eventAdded(event)
        root.saveToFile()
        return event
    }

    // Reschedule one stored occurrence. Protect the series ID, imported
    // providers and one-way Agenda/Todo relationship from pointer edits.
    function rescheduleOccurrence(id, index, startIso, endIso, metadata) {
        if (!root.ready) return false
        const position = root.list.findIndex(e => e.id === id)
        if (position < 0) return false
        const updated = Occurrences.reschedule(root.list[position],index,startIso,endIso)
        if (!updated) return false
        // Metadata updates and occurrence time edits share one durable write.
        const merged = Object.assign({},updated,metadata || {})
        root.list[position] = merged
        root.list = root.list.slice()
        root.eventUpdated(merged)
        root.saveToFile()
        return true
    }

    function removeOccurrence(id, index) {
        if (!root.ready) return false
        const position = root.list.findIndex(e => e.id === id)
        if (position < 0) return false
        const event = root.list[position]
        const slots = Occurrences.entries(event)
        if (!Number.isInteger(index) || index < 0 || index >= slots.length) return false
        // Removing the last date is the same as deleting the event and its Todo.
        if (slots.length === 1) return root.removeEvent(id)
        slots.splice(index,1)
        root.list[position] = Occurrences.store(event,slots)
        root.list = root.list.slice()
        root.eventUpdated(root.list[position])
        root.saveToFile()
        return true
    }

    function removeEvent(id) {
        if (!root.ready) return false
        const index = root.list.findIndex(e => e.id === id)
        if (index !== -1) {
            root._queueTodoUnlink(root.list[index])
            root.list.splice(index, 1)
            root.list = root.list.slice(0)
            root.eventRemoved(id)
            root.saveToFile()
            return true
        }
        return false
    }

    function setTodoLink(id, key, patch) {
        const event = root.list.find(value => value.id === id)
        if (!event || !AgendaTodoPolicy.validLink(event.todoLink) || event.todoLink.key !== key)
            return false
        return root.updateEvent(id, {todoLink: Object.assign({}, event.todoLink, patch)})
    }

    function unlinkTodo(id,deleteTask) {
        const event = root.list.find(value => value.id === id)
        root._queueTodoUnlink(event,deleteTask)
        return event && AgendaTodoPolicy.validLink(event.todoLink)
            ? root.setTodoLink(id, event.todoLink.key, {state:"detached"}) : false
    }

    function updateEvent(id, updates) {
        if (!root.ready) return false
        const index = root.list.findIndex(e => e.id === id)
        if (index !== -1) {
            let updated = Object.assign({}, root.list[index], updates)
            // Older callers still edit startDate/endDate directly. Preserve
            // additional dates instead of replacing the whole series.
            if (Array.isArray(root.list[index].occurrences)
                && !Object.prototype.hasOwnProperty.call(updates,"occurrences")
                && ("startDate" in updates || "dateTime" in updates || "endDate" in updates)) {
                const slots = Occurrences.entries(root.list[index])
                const first = slots[0]
                if (first) {
                    first.startDate = updates.startDate || updates.dateTime || first.startDate
                    first.endDate = updates.endDate || first.endDate
                    first.notified = updates.notified === true
                    first.reminderNotified = updates.reminderNotified === true
                    updated = Occurrences.store(updated,slots)
                }
            }
            root.list[index] = updated
            root.list = root.list.slice(0)
            root.eventUpdated(root.list[index])
            root.saveToFile()
            return true
        }
        return false
    }

    function getEventsForDate(date) {
        return root.list.filter(event => Occurrences.intersectsDay(event,date,false))
    }

    // History and calendar dots include previously fired occurrences.
    function getAllEventsForDate(date) {
        return root.list.filter(event => Occurrences.intersectsDay(event,date,true))
    }

    function getUpcomingEvents(days) {
        const now=new Date()
        const future=new Date(now)
        future.setDate(future.getDate()+(days||7))
        return root.list.flatMap(event=> {
            const slots=Occurrences.entries(event)
            const entries=[]
            for (let index=0;index<slots.length;index++) {
                const slot=slots[index]
                const start=new Date(slot.startDate)
                const end=new Date(slot.endDate)
                const show=event.allDay===true
                    ? end>now && start<=future
                    : start>=now && start<=future && !slot.notified
                if (!show) continue
                entries.push(Object.assign({},event,{
                    _canonicalEvent:Object.assign({},event,{_editOccurrenceIndex:index}),
                    dateTime:slot.startDate,startDate:slot.startDate,
                    endDate:slot.endDate
                }))
            }
            return entries
        }).sort((a,b)=>new Date(a.startDate)-new Date(b.startDate))
    }

    function markAsNotified(id) {
        return root.updateEvent(id, { notified: true })
    }

    function saveToFile() {
        if (root._saving || root._reloadAfterSaveFailure) {
            root._saveQueued = true
            return
        }
        const data = Object.assign({},root.retainedStorageFields,{
            schemaVersion: 2,
            nextId: root.nextId,
            events: root.list,
            todoUnlinks: root.todoUnlinks
        })
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
