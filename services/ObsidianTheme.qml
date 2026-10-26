pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var implementation: AlisIntergration.session?.obsidianTheme ?? (null)
    property string missingOperationError: ""
    readonly property var options: root.implementation?.options ?? (null)
    readonly property bool enabled: root.implementation?.enabled ?? (false)
    readonly property string vaultPath: root.implementation?.vaultPath ?? ("")
    readonly property string configPath: root.implementation?.configPath ?? ("")
    readonly property string applicationConfigPath: root.implementation?.applicationConfigPath ?? ("")
    readonly property var palette: root.implementation?.palette ?? (({}))
    readonly property string signature: root.implementation?.signature ?? ("")
    readonly property bool busy: root.implementation?.busy ?? (false)
    readonly property var info: root.implementation?.info ?? (({}))
    readonly property string error: root.implementation?.error ?? (root.missingOperationError)
    readonly property var queued: root.implementation?.queued ?? (null)
    readonly property var current: root.implementation?.current ?? (null)
    function request(action): void {
        if (root.implementation) return root.implementation.request(action)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function runNext(): void {
        if (root.implementation) return root.implementation.runNext()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function inspect(): void {
        if (root.implementation) return root.implementation.inspect()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function apply(): void {
        if (root.implementation) return root.implementation.apply()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function restore(): void {
        if (root.implementation) return root.implementation.restore()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
}
