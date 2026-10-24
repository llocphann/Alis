pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "EventOccurrences.js" as Occurrences
import "EventBatchPolicy.js" as EventBatch
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
    property bool _checkingDue: false
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
    // Historical todoUnlinks and per-event todoLink are read and serialized
    // unchanged. No Agenda mutation is forwarded to the Todo backend.

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
        if (!root.ready || root._checkingDue) return
        root._checkingDue=true
        try {
        const now = new Date()
        const currentTime = now.getTime()
        const eventCount = root.list.length
        let needsSave = false
        
        for (let i = 0; i < eventCount; i++) {
            const event = root.list[i]
            const slots = Occurrences.entries(event)
            let changed = false
            const originalSlots=slots.map(slot=>Object.assign({},slot,{
                startDate:slot.plannerSeriesStartDate || slot.startDate,
                endDate:slot.plannerSeriesEndDate || slot.endDate
            }))
            // Edited occurrence-backed schedules can predate repeatTemplate.
            // A selectedTemplate denotes the active suffix, not old history.
            const pattern=Array.isArray(event.selectedTemplate) && event.selectedTemplate.length
                ? Occurrences.entries({occurrences:event.selectedTemplate}) : originalSlots
            const patternStart=slots.length-pattern.length
            if (Array.isArray(event.occurrences) && !event.repeatTemplate?.length
                    && event.recurrence && event.recurrence!=="none"
                    && patternStart>=0
                    && pattern.every((slot,index)=>
                        slot.startDate===originalSlots[patternStart+index].startDate
                        && slot.endDate===originalSlots[patternStart+index].endDate)
                    && RepeatPolicy.templateAllowed(pattern,event.recurrence)) {
                event.repeatTemplate=pattern.map(slot=>({
                    startDate:slot.startDate,endDate:slot.endDate
                }))
                event.repeatCycleStart=patternStart
                changed=true
            }
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
            // Event ID, original template and occurrence history.
            // Advance by the original cycle, not a moved instance's new date.
            // A pending exception retains its reminder/notification flags and
            // is still processed above, without delaying everyone else's week.
            const activeSlots=slots.slice(Math.max(0,Number(event.repeatCycleStart || 0)))
            const cycleElapsed=activeSlots.length>0 && activeSlots.every(slot=>
                new Date(slot.plannerSeriesStartDate || slot.startDate).getTime()<=currentTime)
            if (Array.isArray(event.repeatTemplate) && event.repeatTemplate.length>0
                    && event.recurrence!=="none" && cycleElapsed) {
                const future=RepeatPolicy.nextCycle(event.repeatTemplate,
                    event.recurrence,currentTime)
                if (future && future.length) {
                    // Projection uses this boundary to avoid projecting each
                    // archived cycle again while keeping every selected weekday
                    // alive until the entire current cycle has elapsed.
                    event.repeatCycleStart=slots.length
                    const materialized=Occurrences.materializeProjectedRecurring(
                        event,future,slots.length,event.id)
                    if (Array.isArray(event.plannerOverrides))
                        event.plannerOverrides=materialized.overrides
                    slots.push(...materialized.slots)
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
        } finally {root._checkingDue=false}
    }

    function createNextRecurrence(event, afterTime) {
        // A legacy repeating Event may have one edited occurrence but no
        // stored occurrences array. Its next event must still follow the
        // original series anchor, not the moved instance's time.
        const eventDate = new Date(event.plannerSeriesStartDate
            || event.startDate || event.dateTime)
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
        const scheduledEnd = event.plannerSeriesEndDate || event.endDate
        const sourceEnd = scheduledEnd ? new Date(scheduledEnd) : null
        const durationMs = sourceEnd && Number.isFinite(sourceEnd.getTime())
            ? Math.max(0, sourceEnd.getTime() - eventTime) : 0
        const nextEnd = durationMs > 0
            ? new Date(nextDate.getTime() + durationMs).toISOString() : ""

        let nextStart=nextDate.toISOString(),actualEnd=nextEnd,plannerState=null
        let originalOverrides=null
        if (Array.isArray(event.plannerOverrides) && event.plannerOverrides.length) {
            originalOverrides=event.plannerOverrides
            const originalEnd=nextEnd || new Date(nextDate.getTime()+3600000).toISOString()
            const materialized=Occurrences.materializeProjectedRecurring(event,
                [{startDate:nextStart,endDate:originalEnd}],0,root.nextId)
            const nextSlot=materialized.slots[0]
            nextStart=nextSlot.startDate;actualEnd=nextSlot.endDate
            const pending=materialized.overrides.filter(item=>
                item.materializedOccurrenceIndex===undefined && item.forwardedEventId===undefined)
            plannerState={startDate:nextDate.toISOString(),endDate:originalEnd,overrides:pending}
            // Retain older receipts, forwarding only their live responsibility.
            // addEvent defers persistence inside this due-handler transaction.
            event.plannerOverrides=materialized.overrides.map(item=>pending.includes(item)
                ? Object.assign({},item,{forwardedEventId:root.nextId}) : item)
        }
        const created=root.addEvent(
            event.title,
            event.description,
            nextStart,
            event.category,
            event.priority,
            event.reminderMinutes,
            event.recurrence,
            actualEnd,
            event.allDay === true,
            undefined,plannerState
        )
        if (!created && originalOverrides) event.plannerOverrides=originalOverrides
    }

    function addEvent(title, description, dateTime, category, priority, reminderMinutes, recurrence, endDate, allDay, occurrenceRanges, plannerState) {
        if (!root.ready) return null
        // A selected date group is one independent Agenda Event ID,
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
            createdAt: new Date().toISOString()
            // Independent Agenda: no generated Todo link or task
        }
        
        // Internal legacy recurrence handoff keeps its existing separate-ID
        // behavior while carrying immutable cadence and pending exceptions.
        if (!bulk && plannerState && Occurrences.valid(plannerState.startDate)) {
            event.plannerSeriesStartDate=plannerState.startDate
            event.plannerSeriesEndDate=plannerState.endDate
            event.plannerOverrides=plannerState.overrides
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
        if (!root._checkingDue) root.saveToFile()
        return event
    }

    // Edit the entire explicitly-selected Event ID, not just the occurrence
    // used to open the dialog. Keep prior notifications/history when the
    // template is unchanged; preserve past fired recurring cycles when
    // changing a pattern. Never create, update or delete a Todo.
    function updateEventGroup(id, fields, ranges) {
        if (!root.ready || !Array.isArray(ranges)
                || ranges.length<1 || ranges.length>512) return false
        const position=root.list.findIndex(event=>event.id===id)
        if (position<0) return false
        const previous=root.list[position]
        const mode=fields?.recurrence || "none"
        const slots=[]
        for (const span of ranges) {
            const start=new Date(span?.startDate),end=new Date(span?.endDate)
            if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())
                    || end<=start) return false
            const slot=Occurrences.entry(start,end,false,false)
            if (slots.some(old=>old.startDate===slot.startDate)) return false
            slots.push(slot)
        }
        slots.sort((a,b)=>a.startDate.localeCompare(b.startDate))
        if (slots.length>1 && !RepeatPolicy.templateAllowed(slots,mode))
            return false
        const original=Array.isArray(previous.repeatTemplate)
            && previous.repeatTemplate.length>0
            ? previous.repeatTemplate
            : Array.isArray(previous.selectedTemplate)
                && previous.selectedTemplate.length>0
                ? previous.selectedTemplate : Occurrences.entries(previous)
        const sameMode=(previous.recurrence || "none")===mode
        const samePattern=original.length===slots.length
            && original.every((old,i)=>
                old.startDate===slots[i].startDate
                && old.endDate===slots[i].endDate)
        const updates={
            title:String(fields.title || "").trim(),
            description:String(fields.description || ""),
            category:fields.category || "general",
            priority:fields.priority || "normal",
            reminderMinutes:fields.reminderMinutes ?? 15,
            allDay:fields.allDay===true,
            recurrence:mode
        }
        if (!updates.title.length) return false
        let result=Object.assign({},previous,updates)
        if (!sameMode || !samePattern) {
            const previousSlots=Occurrences.entries(previous)
            const selectedStart=previousSlots.length-original.length
            const selectedSuffix=Array.isArray(previous.selectedTemplate)
                && selectedStart>=0 && original.every((slot,index)=>
                    new Date(slot.startDate).getTime()===new Date(previousSlots[selectedStart+index].startDate).getTime()
                    && new Date(slot.endDate).getTime()===new Date(previousSlots[selectedStart+index].endDate).getTime())
            const history=Array.isArray(previous.repeatTemplate)
                ? previousSlots.slice(0,Math.max(0,Number(previous.repeatCycleStart || 0)))
                : selectedSuffix ? previousSlots.slice(0,selectedStart) : []
            result=Occurrences.store(result,history.concat(slots))
            if (mode!=="none") {
                result.repeatTemplate=slots.map(slot=>({
                    startDate:slot.startDate,endDate:slot.endDate
                }))
                result.repeatCycleStart=history.length
                delete result.selectedTemplate
            } else {
                delete result.repeatTemplate
                delete result.repeatCycleStart
                // If a repeating Event is converted to one-time, its
                // historical fired occurrences remain for history, but the
                // editor re-selects only the explicitly chosen current dates.
                if (history.length>0) {
                    result.selectedTemplate=slots.map(slot=>({
                        startDate:slot.startDate,endDate:slot.endDate
                    }))
                } else delete result.selectedTemplate
            }
        }
        root.list[position]=result
        root.list=root.list.slice()
        root.eventUpdated(result)
        root.saveToFile()
        return true
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

    // A single saved instance in an existing recurring series may be moved or
    // resized without rewriting the series template or its occurrence history.
    // Virtual instances (not stored yet) are intentionally not accepted.
    function rescheduleRecurringOccurrence(id, index, startIso, endIso) {
        if (!root.ready) return false
        const position=root.list.findIndex(event=>event.id===id)
        if (position<0) return false
        const updated=Occurrences.rescheduleSavedRecurring(
            root.list[position],index,startIso,endIso)
        if (!updated) return false
        root.list[position]=updated
        root.list=root.list.slice()
        root.eventUpdated(updated)
        root.saveToFile()
        return true
    }

    // Persist an exception to one projected recurring occurrence. Do not
    // promote every future week into stored Events or edit the series template.
    function rescheduleProjectedRecurring(id, index, originalIso, startIso, endIso) {
        if (!root.ready) return false
        const position=root.list.findIndex(event=>event.id===id)
        if (position<0) return false
        const updated=Occurrences.rescheduleProjectedRecurring(
            root.list[position],index,originalIso,startIso,endIso)
        if (!updated) return false
        root.list[position]=updated
        root.list=root.list.slice()
        root.eventUpdated(updated)
        root.saveToFile()
        return true
    }

    // Atomic Weekly Planner group edits: validate every operation before
    // changing any canonical event; emit updates and persist once.
    function applyPlannerOccurrenceBatch(operations) {
        if (!root.ready) return false
        const result=EventBatch.apply(root.list,operations,Occurrences)
        if (!result) return false
        root.list=result.list
        for (const event of result.updated) root.eventUpdated(event)
        for (const id of result.removed) root.eventRemoved(id)
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
            root.list.splice(index, 1)
            root.list = root.list.slice(0)
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

    // Preserve the canonical Event-ID view for existing consumers.
    function getAllEventsForDate(date) {
        return root.list.filter(event => Occurrences.intersectsDay(event,date,true))
    }

    // Calendar dots represent every saved slot, not just distinct Event IDs.
    // Return the parent event once per matching slot for consistent colors;
    // include fired history without modifying Agenda persistence.
    function getAllEventOccurrencesForDate(date) {
        const matches = []
        for (const event of root.list) {
            const slots = Occurrences.occurrencesForDay(event,date,true)
            for (let i = 0; i < slots.length; i++)
                matches.push(event)
        }
        return matches
    }

    function getUpcomingEvents(days) {
        const now=new Date()
        const future=new Date(now)
        future.setDate(future.getDate()+(days||7))
        // Qt's QML JavaScript runtime does not consistently provide
        // Array.prototype.flatMap. Use explicit accumulation to preserve
        // occurrence identity, filtering, and chronological ordering.
        const upcoming=[]
        for (const event of root.list) {
            const slots=Occurrences.entries(event)
            for (let index=0;index<slots.length;index++) {
                const slot=slots[index]
                const start=new Date(slot.startDate)
                const end=new Date(slot.endDate)
                const show=event.allDay===true
                    ? end>now && start<=future
                    : start>=now && start<=future && !slot.notified
                if (!show) continue
                upcoming.push(Object.assign({},event,{
                    _canonicalEvent:Object.assign({},event,{_editOccurrenceIndex:index}),
                    dateTime:slot.startDate,startDate:slot.startDate,
                    endDate:slot.endDate
                }))
            }
        }
        upcoming.sort((a,b)=>new Date(a.startDate)-new Date(b.startDate))
        return upcoming
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
