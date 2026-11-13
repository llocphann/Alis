pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Todo service facade.
 *
 * Existing installs remain on InternalTodoBackend because the append-only
 * config default is "internal". Nexus becomes canonical only after the
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
    // New edits write todo.nexus.vaultPath and retire the legacy override.
    readonly property string sharedVaultPath: {
        const canonical = String(Config.options?.todo?.nexus?.vaultPath ?? "").trim()
        return canonical.length > 0
            ? canonical
            : String(Config.options?.notes?.zettelkasten?.vaultPath ?? "").trim()
    }
    readonly property bool useNexus: root.requestedBackend === "nexus"
    readonly property string backend: root.useNexus ? "nexus" : "internal"
    readonly property string nexusSourceMode:
        String(Config.options?.todo?.nexus?.sourceMode ?? "markdown-note")
    // One heading-based Markdown task source is the normal path. The old
    // managed-marker backend remains only as a persisted compatibility mode.
    readonly property bool useLegacyManagedNote:
        root.nexusSourceMode === "managed-note"
    readonly property bool useMarkdownNote:
        !root.useLegacyManagedNote
    readonly property var nexusBackend:
        root.useLegacyManagedNote ? nexus : dailyNexus

    // Setup is deliberately separate from canonical ownership. While this is
    // true the Nexus backend may scan/initialize/preview, but public Todo
    // consumers continue to see the internal backend until activation commits.
    property bool _nexusSetupActive: false
    property bool _activateAfterMigration: false
    property bool _migrationInFlight: false
    readonly property bool nexusSetupActive: root._nexusSetupActive
    readonly property bool nexusConfigured: root.nexusBackend.configured
    readonly property bool nexusReady: root.nexusBackend.ready
    readonly property bool nexusBusy: root.nexusBackend.busy
    readonly property string nexusErrorCode: root.nexusBackend.errorCode
    readonly property string nexusErrorMessage: root.nexusBackend.errorMessage
    readonly property var nexusCapabilities: root.nexusBackend.capabilities
    readonly property var nexusMigrationPreview: root.nexusBackend.migrationPreview
    readonly property var nexusList: root.nexusBackend.list
    readonly property string nexusNoteFullPath: root.nexusBackend.noteFullPath
    readonly property bool internalPersistenceBusy: internal.persistenceBusy

    readonly property var list: root.useNexus ? root.nexusBackend.list : internal.list
    readonly property bool ready: root.useNexus ? root.nexusBackend.ready : internal.ready
    readonly property bool busy: root.useNexus ? root.nexusBackend.busy : root._migrationInFlight
    readonly property string errorMessage: root.useNexus ? root.nexusBackend.errorMessage : internal.errorMessage
    readonly property string errorCode: root.useNexus ? root.nexusBackend.errorCode : internal.errorCode
    readonly property var capabilities: root.useNexus
        ? root.nexusBackend.capabilities
        : ({
            backend: "internal",
            noteReadable: true,
            noteWritable: true,
            richMutationAvailable: false,
            lastError: internal.errorMessage
        })
    readonly property string sourceLabel: {
        if (!root.useNexus)
            return "Alis"
        if (root.useMarkdownNote)
            return "Nexus · Markdown"
        return "Nexus · " + String(Config.options?.todo?.nexus?.notePath ?? "")
    }
    readonly property int internalItemCount: internal.list.length

    // Compatibility paths remain the internal store paths. New UI must use
    // openSource() instead of assuming Todo.txtFilePath is canonical.
    property alias filePath: internal.filePath
    property alias txtFilePath: internal.txtFilePath

    InternalTodoBackend {
        id: internal
    }

    NexusTodoBackend {
        id: nexus
        active: (root.useNexus || root._nexusSetupActive) && root.useLegacyManagedNote
        vaultPath: root.sharedVaultPath
        notePath: String(Config.options?.todo?.nexus?.notePath ?? "Alis/Todo.md")
        preferTasksPlugin: Config.options?.todo?.nexus?.preferTasksPlugin ?? true
        allowBasicOfflineMutation:
            Config.options?.todo?.nexus?.allowBasicOfflineMutation ?? true
    }

    DailyNoteTodoBackend {
        id: dailyNexus
        active: (root.useNexus || root._nexusSetupActive) && root.useMarkdownNote
        vaultPath: root.sharedVaultPath
        folder: String(Config.options?.todo?.nexus?.dailyNote?.folder
            ?? "00_Capture/01_Journal")
        noteFormat: String(Config.options?.todo?.nexus?.dailyNote?.format
            ?? "YYYY/MMMM/DD-MM-YYYY-dddd")
        plannerHeading: String(Config.options?.todo?.nexus?.dailyNote?.plannerHeading
            ?? "Tasks")
        plannerHeadingLevel: Number(
            Config.options?.todo?.nexus?.dailyNote?.plannerHeadingLevel ?? 2)
        defaultDurationMinutes: Number(
            Config.options?.todo?.nexus?.dailyNote?.defaultDurationMinutes ?? 30)
    }

    Connections {
        target: root.nexusBackend

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
            // and NexusTodoBackend applied that fresh payload before this
            // signal is emitted. Only now may ownership move to Nexus.
            Config.setNestedValue("todo.backend", "nexus")
            root._nexusSetupActive = false
        }
    }

    function _itemAt(index): var {
        if (!Number.isInteger(index) || index < 0 || index >= root.list.length)
            return null
        return root.list[index]
    }

    function beginNexusSetup(): bool {
        if (root.useNexus)
            return true
        root._activateAfterMigration = false
        root._nexusSetupActive = true
        Qt.callLater(() => root.nexusBackend.reload())
        return true
    }

    function cancelNexusSetup(): void {
        if (root.useNexus || root._migrationInFlight)
            return
        root._activateAfterMigration = false
        root._nexusSetupActive = false
    }

    function refreshNexusSetup(): bool {
        if (!root.useNexus && !root._nexusSetupActive)
            return false
        root.nexusBackend.reload()
        return true
    }

    function initializeSection() {
        if (!root.useNexus && !root._nexusSetupActive)
            return false
        return root.nexusBackend.initializeSection()
    }

    function previewInternalToNexus(): bool {
        if ((!root.useNexus && !root._nexusSetupActive)
                || !internal.ready
                || internal.persistenceBusy)
            return false
        return root.nexusBackend.previewInternal(internal.filePath)
    }

    function migrateInternalToNexus(expectedInternalSha) {
        if ((!root.useNexus && !root._nexusSetupActive)
                || !internal.ready
                || internal.persistenceBusy
                || root._migrationInFlight)
            return false

        const staging = !root.useNexus
        root._activateAfterMigration = staging
        const started = root.nexusBackend.migrateInternal(
            internal.filePath,
            String(expectedInternalSha ?? "")
        )
        if (started)
            root._migrationInFlight = staging
        else
            root._activateAfterMigration = false
        return started
    }

    function activateNexus(): bool {
        if (root.useNexus)
            return true
        if (!root._nexusSetupActive || !root.nexusBackend.ready || root.nexusBackend.busy)
            return false

        Config.setNestedValue("todo.backend", "nexus")
        root._activateAfterMigration = false
        root._nexusSetupActive = false
        return true
    }

    function reactivateInternal(): bool {
        if (root._migrationInFlight)
            return false
        root._activateAfterMigration = false
        root._nexusSetupActive = false
        Config.setNestedValue("todo.backend", "internal")
        return true
    }


    function addItem(item) {
        if (!root.useNexus) {
            if (root._migrationInFlight)
                return false
            return internal.addItem(item)
        }
        const content = String(item?.content ?? item?.description ?? "")
        return root.useMarkdownNote
            ? dailyNexus.addTask(content, "", "")
            : nexus.addTask(content)
    }

    function addTask(desc) {
        return root.addTaskWithTime(desc, "", "")
    }

    function addTaskWithTime(desc, startTime, endTime) {
        if (!root.useNexus) {
            if (root._migrationInFlight)
                return false
            return internal.addTask(desc)
        }
        const content = String(desc ?? "")
        if (root.useMarkdownNote)
            return dailyNexus.addTask(
                content,
                String(startTime ?? ""),
                String(endTime ?? "")
            )
        return nexus.addTask(content)
    }

    function toggleTask(taskId) {
        if (!root.useNexus) {
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
        return root.nexusBackend.toggleTask(String(taskId ?? ""))
    }

    function deleteTask(taskId) {
        if (!root.useNexus) {
            if (root._migrationInFlight)
                return false
            const id = String(taskId ?? "")
            for (let i = 0; i < internal.list.length; ++i) {
                if (String(internal.list[i]?.id ?? "") === id)
                    return internal.deleteItem(i)
            }
            return false
        }
        return root.nexusBackend.deleteTask(String(taskId ?? ""))
    }

    // Compatibility wrappers for the existing TodoWidget/Dashboard delegates.
    // They resolve the current item first so Nexus never mutates by index.
    function markDone(index) {
        if (!root.useNexus) {
            if (root._migrationInFlight)
                return false
            return internal.markDone(index)
        }
        const item = root._itemAt(index)
        if (!item)
            return false
        if (item.done === true)
            return true
        return root.nexusBackend.toggleTask(String(item.id ?? ""))
    }

    function markUnfinished(index) {
        if (!root.useNexus) {
            if (root._migrationInFlight)
                return false
            return internal.markUnfinished(index)
        }
        const item = root._itemAt(index)
        if (!item)
            return false
        if (item.done !== true)
            return true
        return root.nexusBackend.toggleTask(String(item.id ?? ""))
    }

    function deleteItem(index) {
        if (!root.useNexus) {
            if (root._migrationInFlight)
                return false
            return internal.deleteItem(index)
        }
        const item = root._itemAt(index)
        if (!item)
            return false
        return root.nexusBackend.deleteTask(String(item.id ?? ""))
    }

    function refresh() {
        if (root.useNexus)
            root.nexusBackend.reload()
        else
            internal.refresh()
    }

    function reload() {
        root.refresh()
    }

    function openNexusSource(): bool {
        if ((!root.useNexus && !root._nexusSetupActive)
                || !root.nexusBackend.noteFullPath
                || root.nexusBackend.noteFullPath.length === 0)
            return false
        if (AlisIntergration.nexus && typeof AlisIntergration.nexus.openNote === "function") {
            AlisIntergration.nexus.openNote(root.nexusBackend.noteFullPath)
            return true
        }
        const uri = "nexus://open?path=" + encodeURIComponent(root.nexusBackend.noteFullPath)
        Quickshell.execDetached(["xdg-open", uri])
        return true
    }

    function openSource(taskId) {
        if (!root.useNexus) {
            Quickshell.execDetached(["xdg-open", internal.txtFilePath])
            return true
        }
        return root.openNexusSource()
    }

    onUseNexusChanged: {
        if (root.useNexus) {
            root._migrationInFlight = false
            root._activateAfterMigration = false
            root._nexusSetupActive = false
        }
    }
}
