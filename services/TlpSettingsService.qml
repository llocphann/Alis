pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var implementation: AlisIntergration.session?.tlpSettings ?? (null)
    property string missingOperationError: ""
    readonly property string helperPath: root.implementation?.helperPath ?? ("/usr/libexec/alis-battery-charge-limit")
    readonly property string schemaPath: root.implementation?.schemaPath ?? ("")
    readonly property var categories: root.implementation?.categories ?? ([])
    readonly property var navigationCategories: root.implementation?.navigationCategories ?? ([])
    readonly property var effectiveValues: root.implementation?.effectiveValues ?? (({}))
    readonly property var managedValues: root.implementation?.managedValues ?? (({}))
    readonly property var runtimeValues: root.implementation?.runtimeValues ?? (({}))
    readonly property var pendingValues: root.implementation?.pendingValues ?? (({}))
    readonly property var pendingChargePolicy: root.implementation?.pendingChargePolicy ?? (null)
    readonly property bool schemaLoaded: root.implementation?.schemaLoaded ?? (false)
    readonly property int safetyRefreshIntervalMs: root.implementation?.safetyRefreshIntervalMs ?? (0)
    readonly property bool statusLoaded: root.implementation?.statusLoaded ?? (false)
    readonly property bool available: root.implementation?.available ?? (false)
    readonly property bool supported: root.implementation?.supported ?? (false)
    readonly property bool configAvailable: root.implementation?.configAvailable ?? (false)
    readonly property bool enabled: root.implementation?.enabled ?? (false)
    readonly property bool busy: root.implementation?.busy ?? (false)
    readonly property string tlpVersion: root.implementation?.tlpVersion ?? ("")
    readonly property string statusReason: root.implementation?.statusReason ?? (AlisIntergration.available ? "integration-disabled" : "integration-not-installed")
    readonly property string configFile: root.implementation?.configFile ?? ("/etc/tlp.conf")
    readonly property string lastError: root.implementation?.lastError ?? (root.missingOperationError)
    readonly property bool hasPendingChanges: root.implementation?.hasPendingChanges ?? (false)
    readonly property int pendingCount: root.implementation?.pendingCount ?? (0)
    readonly property int managedCount: root.implementation?.managedCount ?? (0)
    readonly property bool managedConfigPresent: root.implementation?.managedConfigPresent ?? (false)
    readonly property bool canResetOverrides: root.implementation?.canResetOverrides ?? (false)
    signal mutationFinished(string kind, bool success)
    function settingAvailable(definition): bool {
        if (root.implementation) return root.implementation.settingAvailable(definition)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    // Existing shared/Waffle setting rows use these value adapters.
    function _array(value): var {
        return root.implementation ? root.implementation._array(value) : []
    }
    function _settingsUseCompactProfileRows(settings): bool {
        return root.implementation ? root.implementation._settingsUseCompactProfileRows(settings) : false
    }
    function settingsForCategory(category): var {
        if (root.implementation) return root.implementation.settingsForCategory(category)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return []
    }
    function categoryLabel(category): string {
        if (root.implementation) return root.implementation.categoryLabel(category)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function groupsForCategory(category, filterText): var {
        if (root.implementation) return root.implementation.groupsForCategory(category, filterText)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return []
    }
    function settingLabel(definition): string {
        if (root.implementation) return root.implementation.settingLabel(definition)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function groupLabel(groupId: string, fallbackTitle: string): string {
        if (root.implementation) return root.implementation.groupLabel(groupId, fallbackTitle)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function groupUsesCompactProfileRows(group): bool {
        if (root.implementation) return root.implementation.groupUsesCompactProfileRows(group)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function exampleValue(definition): string {
        if (root.implementation) return root.implementation.exampleValue(definition)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function optionValues(definition): var {
        if (root.implementation) return root.implementation.optionValues(definition)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return []
    }
    function profileLabel(profile): string {
        if (root.implementation) return root.implementation.profileLabel(profile)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function displayValue(definition, value): string {
        if (root.implementation) return root.implementation.displayValue(definition, value)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function settingNotice(definition): string {
        if (root.implementation) return root.implementation.settingNotice(definition)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function isManaged(key: string): bool {
        if (root.implementation) return root.implementation.isManaged(key)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function value(key: string): string {
        if (root.implementation) return root.implementation.value(key)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function effectiveValue(key: string): string {
        if (root.implementation) return root.implementation.effectiveValue(key)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return ""
    }
    function chargeEnabled(): bool {
        if (root.implementation) return root.implementation.chargeEnabled()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function chargeThreshold(): int {
        if (root.implementation) return root.implementation.chargeThreshold()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return 80
    }
    function stageChargeEnabled(enabled: bool, threshold: int): void {
        if (root.implementation) return root.implementation.stageChargeEnabled(enabled, threshold)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function stageChargeThreshold(threshold: int): void {
        if (root.implementation) return root.implementation.stageChargeThreshold(threshold)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function stageSet(key: string, value): void {
        if (root.implementation) return root.implementation.stageSet(key, value)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function stageUnset(key: string): void {
        if (root.implementation) return root.implementation.stageUnset(key)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function discard(): void {
        if (root.implementation) return root.implementation.discard()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function refresh(): void {
        if (root.implementation) return root.implementation.refresh()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function apply(): bool {
        if (root.implementation) return root.implementation.apply()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function reset(): void {
        if (root.implementation) return root.implementation.reset()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    Connections {
        target: root.implementation
        function onMutationFinished(kind, success): void {root.mutationFinished(kind, success)}
    }
}
