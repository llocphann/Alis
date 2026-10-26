pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var implementation: AlisIntergration.session?.tlp ?? (null)
    property string missingOperationError: ""
    readonly property bool available: root.implementation?.available ?? (false)
    readonly property bool supported: root.implementation?.supported ?? (false)
    readonly property bool adjustable: root.implementation?.adjustable ?? (false)
    readonly property bool stateKnown: root.implementation?.stateKnown ?? (false)
    readonly property bool active: root.implementation?.active ?? (false)
    readonly property bool managed: root.implementation?.managed ?? (false)
    readonly property int currentLimit: root.implementation?.currentLimit ?? (-1)
    readonly property int currentStart: root.implementation?.currentStart ?? (-1)
    readonly property string backend: root.implementation?.backend ?? ("")
    readonly property string tlpVersion: root.implementation?.tlpVersion ?? ("")
    readonly property string statusReason: root.implementation?.statusReason ?? (AlisIntergration.available ? "integration-disabled" : "integration-not-installed")
    readonly property string limitKind: root.implementation?.limitKind ?? ("none")
    readonly property int minimumLimit: root.implementation?.minimumLimit ?? (1)
    readonly property int maximumLimit: root.implementation?.maximumLimit ?? (100)
    readonly property int limitStepSize: root.implementation?.limitStepSize ?? (1)
    readonly property var allowedLimits: root.implementation?.allowedLimits ?? ([])
    readonly property int fixedLimit: root.implementation?.fixedLimit ?? (-1)
    readonly property string configBattery: root.implementation?.configBattery ?? ("")
    readonly property string managedBattery: root.implementation?.managedBattery ?? ("")
    readonly property int managedLimit: root.implementation?.managedLimit ?? (-1)
    readonly property bool busy: root.implementation?.busy ?? (false)
    readonly property int requestedLimit: root.implementation?.requestedLimit ?? (80)
    readonly property int effectiveRequestedLimit: root.implementation?.effectiveRequestedLimit ?? (80)
    readonly property bool enabled: root.implementation?.enabled ?? (false)
    readonly property bool discrete: root.implementation?.discrete ?? (false)
    readonly property bool continuous: root.implementation?.continuous ?? (false)
    function refresh(): void {
        if (root.implementation) return root.implementation.refresh()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function apply(): void {
        if (root.implementation) return root.implementation.apply()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
}
