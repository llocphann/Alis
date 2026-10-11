pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "AgendaTodoPolicy.js" as AgendaTodoPolicy

/**
 * Todo service facade.
 *
 * Existing installs remain on InternalTodoBackend because the append-only
 * config default is "internal". Obsidian becomes canonical only after the
 * backend value is explicitly changed by a setup/migration flow (or by an
 * advanced user editing config directly).
 */
Singleton {
    id: root

    readonly property string requestedBackend:
        String(Config.options?.todo?.backend ?? "internal")
    // Shared vault for Todo and Zettelkasten. Older installations may have
    // configured only the former Quick Notes override; reuse it when the
    // canonical Todo vault is empty rather than losing their capture target.
    // New edits write todo.obsidian.vaultPath and retire the legacy override.
    readonly property string sharedVaultPath: {
        const canonical = String(Config.options?.todo?.obsidian?.vaultPath ?? "").trim()
        return canonical.length > 0
            ? canonical
            : String(Config.options?.notes?.zettelkasten?.vaultPath ?? "").trim()
    }
    readonly property bool useObsidian: root.requestedBackend === "obsidian"
    readonly property string backend: root.useObsidian ? "obsidian" : "internal"
    readonly property string obsidianSourceMode:
        String(Config.options?.todo?.obsidian?.sourceMode ?? "markdown-note")
    // One heading-based Markdown task source is the normal path. The old
    // managed-marker backend remains only as a persisted compatibility mode.
    readonly property bool useLegacyManagedNote:
        root.obsidianSourceMode === "managed-note"
    readonly property bool useMarkdownNote:
        !root.useLegacyManagedNote
    readonly property var obsidianBackend:
        root.useLegacyManagedNote ? obsidian : dailyObsidian

    // Setup is deliberately separate from canonical ownership. While this is
    // true the Obsidian backend may scan/initialize/preview, but public Todo
    // consumers continue to see the internal backend until activation commits.
    property bool _obsidianSetupActive: false
    property bool _activateAfterMigration: false
    property bool _migrationInFlight: false
    readonly property bool obsidianSetupActive: root._obsidianSetupActive
    readonly property bool obsidianConfigured: root.obsidianBackend.configured
    readonly property bool obsidianReady: root.obsidianBackend.ready
    readonly property bool obsidianBusy: root.obsidianBackend.busy
    readonly property string obsidianErrorCode: root.obsidianBackend.errorCode
    readonly property string obsidianErrorMessage: root.obsidianBackend.errorMessage
    readonly property var obsidianCapabilities: root.obsidianBackend.capabilities
    readonly property var obsidianMigrationPreview: root.obsidianBackend.migrationPreview
    readonly property var obsidianList: root.obsidianBackend.list
    readonly property string obsidianNoteFullPath: root.obsidianBackend.noteFullPath
    readonly property bool internalPersistenceBusy: internal.persistenceBusy

    readonly property var list: root.useObsidian ? root.obsidianBackend.list : internal.list
    readonly property bool ready: root.useObsidian ? root.obsidianBackend.ready : internal.ready
    readonly property bool busy: root.useObsidian ? root.obsidianBackend.busy : root._migrationInFlight
    readonly property string errorMessage: root.useObsidian ? root.obsidianBackend.errorMessage : internal.errorMessage
    readonly property string errorCode: root.useObsidian ? root.obsidianBackend.errorCode : internal.errorCode
    readonly property var capabilities: root.useObsidian
        ? root.obsidianBackend.capabilities
        : ({
            backend: "internal",
            noteReadable: true,
            noteWritable: true,
            richMutationAvailable: false,
            lastError: internal.errorMessage
        })
    readonly property string sourceLabel: {
        if (!root.useObsidian)
            return "Hadalis"
        if (root.useMarkdownNote)
            return "Obsidian · Markdown"
        return "Obsidian · " + String(Config.options?.todo?.obsidian?.notePath ?? "")
    }
    readonly property int internalItemCount: internal.list.length

    readonly property string agendaProvider: !root.useObsidian ? "internal" : JSON.stringify([
        "obsidian",root.sharedVaultPath,root.obsidianSourceMode,
        root.useMarkdownNote ? [dailyObsidian.folder,dailyObsidian.noteFormat,dailyObsidian.plannerHeading,dailyObsidian.plannerHeadingLevel] : obsidian.notePath])
    property string agendaError: ""
    property int _agendaRetries: 0
    property var _agendaReceipt: null
    property var _agendaAttempt: null
    property var _agendaFailures: ({})
    function _scheduleAgenda() { Qt.callLater(root._reconcileAgenda) }
    function retryAgendaLinks() {
        root._agendaRetries=0;root.agendaError=""
        root._agendaFailures=({})
        if(!root.useObsidian && internal.errorMessage)internal.retrySave()
        if(root.useObsidian)root.obsidianBackend.reload()
        if(Events.errorMessage)Events.saveToFile()
        root._scheduleAgenda()
    }
    function agendaStatus(event) {
        if(!AgendaTodoPolicy.validLink(event?.todoLink))return ""
        if(event.todoLink.state==="detached")return Events.todoUnlinks.some(link=>link.key===event.todoLink.key && link.deleteTask)?"To-do removal pending":""
        const link=event.todoLink
        if(link.provider && link.provider!==root.agendaProvider)return "To-do in another source"
        const sourceVisible=!root.useObsidian || root.useLegacyManagedNote || link.sourceDate===root.obsidianBackend.sourceDate
        if(link.taskMissing || (link.state==="linked" && sourceVisible && root.ready && !root.list.some(item=>item.agenda?.key===link.key)))return "To-do removed"
        if(link.state!=="linked" || link.fingerprint!==AgendaTodoPolicy.fingerprint(event))return "To-do pending"
        if(!root.useObsidian && !root.list.some(item=>item.agenda?.key===link.key))return "To-do removed"
        return "Linked To-do"
    }
    function _reconcileAgenda() {
        if(!Events.ready || Events.persistenceBusy || agendaRetry.running)return
        const events=Events.getDurableEvents()
        const eligible=events.filter(event=>AgendaTodoPolicy.validLink(event.todoLink) && event.todoLink.state!=="detached")
        if(!root.ready || root.busy || (!root.useObsidian && internal.persistenceBusy)) {
            if(eligible.length)root.agendaError="To-do link pending"
            return
        }
        const items=root.useObsidian ? root.list : internal.getDurableItems()
        const unlink=Events.getDurableTodoUnlinks().find(value=>AgendaTodoPolicy.validLink(value) && value.provider===root.agendaProvider)
        if(unlink) {
            if(!root.useObsidian) {
                if(!items.some(item=>item.agenda?.key===unlink.key))Events.finishTodoUnlink(unlink.key,root.agendaProvider)
                else if(unlink.deleteTask)internal.deleteItem(root.list.findIndex(item=>item.agenda?.key===unlink.key))
                else internal.unlinkAgenda(unlink.key)
            } else if(root._agendaReceipt?.kind===(unlink.deleteTask?"delete":"unlink") && root._agendaReceipt?.key===unlink.key && root._agendaReceipt?.provider===root.agendaProvider) {
                Events.finishTodoUnlink(unlink.key,root.agendaProvider)
            } else root._startExternalAgenda(unlink.deleteTask?"delete":"unlink",unlink,unlink)
            return
        }
        for(const event of eligible) {
            const link=event.todoLink
            if(link.provider && link.provider!==root.agendaProvider)continue
            if(!link.provider) {
                Events.setTodoLink(event.id,link.key,{provider:root.agendaProvider,sourceDate:root.useMarkdownNote && root.useObsidian ? root.obsidianBackend.sourceDate : ""})
                return
            }
            const wanted=AgendaTodoPolicy.fingerprint(event)
            const token=root.agendaProvider+"|"+link.key+"|ensure|"+wanted
            const task=items.find(item=>item.agenda?.key===link.key)
            const receipt=root._agendaReceipt
            const acknowledged=task?.agenda?.fingerprint===wanted || (receipt?.key===link.key && receipt?.provider===root.agendaProvider && receipt?.fingerprint===wanted)
            if(acknowledged) {
                if(link.state!=="linked" || link.fingerprint!==wanted) {
                    Events.setTodoLink(event.id,link.key,{state:"linked",fingerprint:wanted,taskMissing:!task && receipt?.taskMissing===true});return
                }
                continue
            }
            // Missing after a completed link means deliberate task deletion.
            if(link.state==="linked" && link.fingerprint===wanted)continue
            if(link.state==="linked" && !task && !root.useObsidian)continue
            if((root._agendaFailures[token] || 0)>=3)continue
            root.agendaError="To-do link pending"
            const accepted=root.useObsidian ? root._startExternalAgenda("ensure",event,Object.assign({},event,{agendaDesired:AgendaTodoPolicy.desired(event),agendaFingerprint:wanted})) : internal.ensureAgenda(event)
            if(!accepted) {
                root.agendaError="To-do link pending"
                if(!root.useObsidian) {
                    root._agendaFailures=Object.assign({},root._agendaFailures,{[token]:(root._agendaFailures[token] || 0)+1})
                    if(root._agendaFailures[token]<3)agendaRetry.restart()
                }
            }
            return
        }
        if(!root.useObsidian) {
            const live=eligible.map(event=>event.todoLink.key)
            const orphan=items.find(item=>item.agenda && live.indexOf(item.agenda.key)<0)
            if(orphan){internal.unlinkAgenda(orphan.agenda.key);return}
        } else {
            const orphan=items.find(item=>item.agenda && !eligible.some(event=>event.todoLink.key===item.agenda.key))
            if(orphan){root._startExternalAgenda("unlink",orphan.agenda,orphan.agenda);return}
        }
        root.agendaError="";root._agendaRetries=0;agendaRetry.stop()
    }
    function _startExternalAgenda(kind,event,payload) {
        const link=event.todoLink || event
        const fingerprint=payload.agendaFingerprint || ""
        const token=root.agendaProvider+"|"+link.key+"|"+kind+"|"+fingerprint
        if((root._agendaFailures[token] || 0)>=3)return false
        root._agendaAttempt={key:link.key,kind:kind,fingerprint:fingerprint,provider:root.agendaProvider,token:token}
        const accepted=kind==="ensure" ? root.obsidianBackend.ensureAgenda(payload) : kind==="delete" ? root.obsidianBackend.deleteAgenda(payload) : root.obsidianBackend.unlinkAgenda(payload)
        if(!accepted)root._agendaFinished(false,null)
        return accepted
    }
    function _agendaFinished(success,payload) {
        const attempt=root._agendaAttempt
        root._agendaAttempt=null
        if(!attempt || attempt.provider!==root.agendaProvider)return
        if(success) {
            root._agendaReceipt=Object.assign({},payload?.agendaReceipt || {},attempt)
        } else {
            root.agendaError="To-do link pending"
            root._agendaFailures=Object.assign({},root._agendaFailures,{[attempt.token]:(root._agendaFailures[attempt.token] || 0)+1})
            if(root._agendaFailures[attempt.token]<3)agendaRetry.restart()
        }
        root._scheduleAgenda()
    }
    Timer {id:agendaRetry;interval:1000;repeat:false;onTriggered:root._scheduleAgenda()}
    Connections {
        target:Events
        function onEventsPersisted(savedEvents) {root._scheduleAgenda()}
        function onReadyChanged() {root._scheduleAgenda()}
        function onPersistenceBusyChanged() {if(!Events.persistenceBusy)root._scheduleAgenda()}
    }
    Connections {
        target:internal
        function onItemsPersisted(savedItems) {root._scheduleAgenda()}
        function onReadyChanged() {root._scheduleAgenda()}
        function onPersistenceBusyChanged() {if(!internal.persistenceBusy)root._scheduleAgenda()}
    }
    onReadyChanged:root._scheduleAgenda()
    onBusyChanged:if(!root.busy)root._scheduleAgenda()
    onAgendaProviderChanged: {root._agendaReceipt=null;root._scheduleAgenda()}
    function _deferAgendaDeletion(item) {
        if(!item?.agenda || !root.ready || root.busy)return false
        const event=Events.list.find(value=>value.todoLink?.key===item.agenda.key)
        if(!event)return false
        Events.unlinkTodo(event.id,true)
        return true
    }

    // Compatibility paths remain the internal store paths. New UI must use
    // openSource() instead of assuming Todo.txtFilePath is canonical.
    property alias filePath: internal.filePath
    property alias txtFilePath: internal.txtFilePath

    InternalTodoBackend {
        id: internal
    }

    ObsidianTodoBackend {
        id: obsidian
        active: (root.useObsidian || root._obsidianSetupActive) && root.useLegacyManagedNote
        vaultPath: root.sharedVaultPath
        notePath: String(Config.options?.todo?.obsidian?.notePath ?? "Hadalis/Todo.md")
        preferTasksPlugin: Config.options?.todo?.obsidian?.preferTasksPlugin ?? true
        allowBasicOfflineMutation:
            Config.options?.todo?.obsidian?.allowBasicOfflineMutation ?? true
    }

    DailyNoteTodoBackend {
        id: dailyObsidian
        active: (root.useObsidian || root._obsidianSetupActive) && root.useMarkdownNote
        vaultPath: root.sharedVaultPath
        folder: String(Config.options?.todo?.obsidian?.dailyNote?.folder
            ?? "00_Capture/01_Journal")
        noteFormat: String(Config.options?.todo?.obsidian?.dailyNote?.format
            ?? "YYYY/MMMM/DD-MM-YYYY-dddd")
        plannerHeading: String(Config.options?.todo?.obsidian?.dailyNote?.plannerHeading
            ?? "Tasks")
        plannerHeadingLevel: Number(
            Config.options?.todo?.obsidian?.dailyNote?.plannerHeadingLevel ?? 2)
        defaultDurationMinutes: Number(
            Config.options?.todo?.obsidian?.dailyNote?.defaultDurationMinutes ?? 30)
    }

    Connections {
        target: root.obsidianBackend

        function onAgendaMutationFinished(success,payload): void {root._agendaFinished(success,payload)}

        function onMigrationFinished(success, payload): void {
            root._migrationInFlight = false
            if (!success)
                root._activateAfterMigration = false
        }

        function onMigrationCommitted(payload): void {
            root._migrationInFlight = false
            if (!root._activateAfterMigration)
                return
            root._activateAfterMigration = false

            // The migration helper has already re-scanned the canonical note
            // and ObsidianTodoBackend applied that fresh payload before this
            // signal is emitted. Only now may ownership move to Obsidian.
            Config.setNestedValue("todo.backend", "obsidian")
            root._obsidianSetupActive = false
        }
    }

    function _itemAt(index): var {
        if (!Number.isInteger(index) || index < 0 || index >= root.list.length)
            return null
        return root.list[index]
    }

    function beginObsidianSetup(): bool {
        if (root.useObsidian)
            return true
        root._activateAfterMigration = false
        root._obsidianSetupActive = true
        Qt.callLater(() => root.obsidianBackend.reload())
        return true
    }

    function cancelObsidianSetup(): void {
        if (root.useObsidian || root._migrationInFlight)
            return
        root._activateAfterMigration = false
        root._obsidianSetupActive = false
    }

    function refreshObsidianSetup(): bool {
        if (!root.useObsidian && !root._obsidianSetupActive)
            return false
        root.obsidianBackend.reload()
        return true
    }

    function initializeSection() {
        if (!root.useObsidian && !root._obsidianSetupActive)
            return false
        return root.obsidianBackend.initializeSection()
    }

    function previewInternalToObsidian(): bool {
        if ((!root.useObsidian && !root._obsidianSetupActive)
                || !internal.ready
                || internal.persistenceBusy)
            return false
        return root.obsidianBackend.previewInternal(internal.filePath)
    }

    function migrateInternalToObsidian(expectedInternalSha) {
        if ((!root.useObsidian && !root._obsidianSetupActive)
                || !internal.ready
                || internal.persistenceBusy
                || root._migrationInFlight)
            return false

        const staging = !root.useObsidian
        root._activateAfterMigration = staging
        const started = root.obsidianBackend.migrateInternal(
            internal.filePath,
            String(expectedInternalSha ?? "")
        )
        if (started)
            root._migrationInFlight = staging
        else
            root._activateAfterMigration = false
        return started
    }

    function activateObsidian(): bool {
        if (root.useObsidian)
            return true
        if (!root._obsidianSetupActive || !root.obsidianBackend.ready || root.obsidianBackend.busy)
            return false

        Config.setNestedValue("todo.backend", "obsidian")
        root._activateAfterMigration = false
        root._obsidianSetupActive = false
        return true
    }

    function reactivateInternal(): bool {
        if (root._migrationInFlight)
            return false
        root._activateAfterMigration = false
        root._obsidianSetupActive = false
        Config.setNestedValue("todo.backend", "internal")
        return true
    }


    function addItem(item) {
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            return internal.addItem(item)
        }
        const content = String(item?.content ?? item?.description ?? "")
        return root.useMarkdownNote
            ? dailyObsidian.addTask(content, "", "")
            : obsidian.addTask(content)
    }

    function addTask(desc) {
        return root.addTaskWithTime(desc, "", "")
    }

    function addTaskWithTime(desc, startTime, endTime) {
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            return internal.addTask(desc)
        }
        const content = String(desc ?? "")
        if (root.useMarkdownNote)
            return dailyObsidian.addTask(
                content,
                String(startTime ?? ""),
                String(endTime ?? "")
            )
        return obsidian.addTask(content)
    }

    function toggleTask(taskId) {
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            const id = String(taskId ?? "")
            for (let i = 0; i < internal.list.length; ++i) {
                if (String(internal.list[i]?.id ?? "") === id) {
                    if (internal.list[i]?.done)
                        return internal.markUnfinished(i)
                    return internal.markDone(i)
                }
            }
            return false
        }
        return root.obsidianBackend.toggleTask(String(taskId ?? ""))
    }

    function deleteTask(taskId) {
        const linked=root.list.find(item=>String(item.id ?? "")===String(taskId ?? ""))
        if(root._deferAgendaDeletion(linked))return true
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            const id = String(taskId ?? "")
            for (let i = 0; i < internal.list.length; ++i) {
                if (String(internal.list[i]?.id ?? "") === id)
                    return internal.deleteItem(i)
            }
            return false
        }
        return root.obsidianBackend.deleteTask(String(taskId ?? ""))
    }

    // Compatibility wrappers for the existing TodoWidget/Dashboard delegates.
    // They resolve the current item first so Obsidian never mutates by index.
    function markDone(index) {
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            return internal.markDone(index)
        }
        const item = root._itemAt(index)
        if (!item)
            return false
        if (item.done === true)
            return true
        return root.obsidianBackend.toggleTask(String(item.id ?? ""))
    }

    function markUnfinished(index) {
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            return internal.markUnfinished(index)
        }
        const item = root._itemAt(index)
        if (!item)
            return false
        if (item.done !== true)
            return true
        return root.obsidianBackend.toggleTask(String(item.id ?? ""))
    }

    function deleteItem(index) {
        if(root._deferAgendaDeletion(root._itemAt(index)))return true
        if (!root.useObsidian) {
            if (root._migrationInFlight)
                return false
            return internal.deleteItem(index)
        }
        const item = root._itemAt(index)
        if (!item)
            return false
        return root.obsidianBackend.deleteTask(String(item.id ?? ""))
    }

    function refresh() {
        if (root.useObsidian)
            root.obsidianBackend.reload()
        else
            internal.refresh()
    }

    function reload() {
        root.refresh()
    }

    function openObsidianSource(): bool {
        if ((!root.useObsidian && !root._obsidianSetupActive)
                || !root.obsidianBackend.noteFullPath
                || root.obsidianBackend.noteFullPath.length === 0)
            return false
        const uri = "obsidian://open?path=" + encodeURIComponent(root.obsidianBackend.noteFullPath)
        Quickshell.execDetached(["xdg-open", uri])
        return true
    }

    function openSource(taskId) {
        if (!root.useObsidian) {
            Quickshell.execDetached(["xdg-open", internal.txtFilePath])
            return true
        }
        return root.openObsidianSource()
    }

    onUseObsidianChanged: {
        if (root.useObsidian) {
            root._migrationInFlight = false
            root._activateAfterMigration = false
            root._obsidianSetupActive = false
        }
    }
}
