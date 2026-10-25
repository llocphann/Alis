pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

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
            return "Alis"
        if (root.useMarkdownNote)
            return "Obsidian · Markdown"
        return "Obsidian · " + String(Config.options?.todo?.obsidian?.notePath ?? "")
    }
    readonly property int internalItemCount: internal.list.length

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
