pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var implementation: AlisIntergration.session?.zettelkasten ?? (null)
    property string missingOperationError: ""
    readonly property string configuredVaultPath: root.implementation?.configuredVaultPath ?? ("")
    readonly property string folder: root.implementation?.folder ?? ("")
    readonly property string defaultType: root.implementation?.defaultType ?? ("")
    readonly property bool ready: root.implementation?.ready ?? (false)
    readonly property bool busy: root.implementation?.busy ?? (false)
    readonly property string errorCode: root.missingOperationError ? "integration-unavailable" : (root.implementation?.errorCode ?? "")
    readonly property string errorMessage: root.missingOperationError || (root.implementation?.errorMessage ?? "")
    readonly property string lastCreatedPath: root.implementation?.lastCreatedPath ?? ("")
    readonly property string lastCreatedFullPath: root.implementation?.lastCreatedFullPath ?? ("")
    readonly property string helperPath: root.implementation?.helperPath ?? ("")
    signal captured(var payload)
    function capture(title, body): bool {
        if (root.implementation) {
            root.missingOperationError = ""
            return root.implementation.capture(title, body)
        }
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function captureWithAttachments(title, body, attachmentRoot): bool {
        if (root.implementation?.captureWithAttachments) {
            root.missingOperationError = ""
            return root.implementation.captureWithAttachments(title, body, attachmentRoot)
        }
        root.missingOperationError = "Update and enable Alis-Intergration to export note images"
        return false
    }
    function openLast(): bool {
        if (root.implementation) return root.implementation.openLast()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    Connections {
        target: root.implementation
        function onCaptured(payload): void {root.captured(payload)}
    }
}
