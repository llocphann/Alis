pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
    id: root
    readonly property var implementation: backendLoader.item
    property string missingOperationError: ""
    property bool active: false
    property string vaultPath: ""
    property string notePath: ""
    property bool preferTasksPlugin: true
    property bool allowBasicOfflineMutation: true
    readonly property var list: root.implementation?.list ?? ([])
    readonly property bool ready: root.implementation?.ready ?? (false)
    readonly property bool busy: root.implementation?.busy ?? (false)
    readonly property bool capabilityBusy: root.implementation?.capabilityBusy ?? (false)
    readonly property string errorCode: root.implementation?.errorCode ?? (root.missingOperationError ? "integration-unavailable" : "")
    readonly property string errorMessage: root.implementation?.errorMessage ?? (root.missingOperationError)
    readonly property string noteFullPath: root.implementation?.noteFullPath ?? ("")
    readonly property var documentMeta: root.implementation?.documentMeta ?? (({}))
    readonly property var managedMeta: root.implementation?.managedMeta ?? (({}))
    readonly property var capabilities: root.implementation?.capabilities ?? (({backend:"obsidian",noteReadable:false,noteWritable:false,richMutationAvailable:false,lastError:root.missingOperationError}))
    readonly property var migrationPreview: root.implementation?.migrationPreview ?? (null)
    readonly property bool configured: root.implementation?.configured ?? (false)
    readonly property string helperPath: root.implementation?.helperPath ?? ("")
    readonly property string runtimeHelperPath: root.implementation?.runtimeHelperPath ?? ("")
    readonly property string watchPath: root.implementation?.watchPath ?? ("")
    signal migrationCommitted(var payload)
    signal migrationFinished(bool success, var payload)
    signal agendaMutationFinished(bool success,var payload)
    function deleteAgenda(link): bool {
        if(typeof root.implementation?.deleteAgenda === "function")return root.implementation.deleteAgenda(link)
        root.missingOperationError="Update the optional integration to link Agenda"
        return false
    }
    function unlinkAgenda(link): bool {
        if(typeof root.implementation?.unlinkAgenda === "function")return root.implementation.unlinkAgenda(link)
        root.missingOperationError="Update the optional integration to link Agenda"
        return false
    }
    function ensureAgenda(event): bool {
        if(typeof root.implementation?.ensureAgenda === "function")return root.implementation.ensureAgenda(event)
        root.missingOperationError="Update the optional integration to link Agenda"
        return false
    }
    function refresh(): void {
        if (root.implementation) return root.implementation.refresh()
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
    }
    function reload(): void {
        if (root.implementation) return root.implementation.reload()
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
    }
    function refreshCapabilities(): void {
        if (root.implementation) return root.implementation.refreshCapabilities()
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
    }
    function initializeSection(): bool {
        if (root.implementation) return root.implementation.initializeSection()
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
        return false
    }
    function previewInternal(internalJsonPath: string): bool {
        if (root.implementation) return root.implementation.previewInternal(internalJsonPath)
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
        return false
    }
    function migrateInternal(internalJsonPath: string, expectedInternalSha: string): bool {
        if (root.implementation) return root.implementation.migrateInternal(internalJsonPath, expectedInternalSha)
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
        return false
    }
    function addTask(text: string): bool {
        if (root.implementation) return root.implementation.addTask(text)
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
        return false
    }
    function toggleTask(taskId: string): bool {
        if (root.implementation) return root.implementation.toggleTask(taskId)
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
        return false
    }
    function deleteTask(taskId: string): bool {
        if (root.implementation) return root.implementation.deleteTask(taskId)
        root.missingOperationError = "Install and enable the Hadalird integration to use this action"
        return false
    }
    Connections {
        target: root.implementation
        ignoreUnknownSignals:true
        function onAgendaMutationFinished(success,payload): void {root.agendaMutationFinished(success,payload)}
        function onMigrationCommitted(payload): void {root.migrationCommitted(payload)}
        function onMigrationFinished(success, payload): void {root.migrationFinished(success, payload)}
    }
    Loader {
        id: backendLoader
        active: root.active && Hadalird.obsidianEnabled
        function syncSource(): void {
            if (active && String(source).length === 0)
                setSource(Hadalird.backendSource("managed"), {active:root.active, vaultPath:root.vaultPath, notePath:root.notePath, preferTasksPlugin:root.preferTasksPlugin, allowBasicOfflineMutation:root.allowBasicOfflineMutation})
            else if (!active) source = ""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
        onLoaded: {
            item.active = Qt.binding(() => root.active)
            item.vaultPath = Qt.binding(() => root.vaultPath)
            item.notePath = Qt.binding(() => root.notePath)
            item.preferTasksPlugin = Qt.binding(() => root.preferTasksPlugin)
            item.allowBasicOfflineMutation = Qt.binding(() => root.allowBasicOfflineMutation)
        }
    }
}
