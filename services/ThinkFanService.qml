pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var implementation: AlisIntergration.session?.thinkfan ?? (null)
    property string missingOperationError: ""
    readonly property bool available: root.implementation?.available ?? (false)
    readonly property bool serviceInstalled: root.implementation?.serviceInstalled ?? (false)
    readonly property bool active: root.implementation?.active ?? (false)
    readonly property bool enabled: root.implementation?.enabled ?? (false)
    readonly property bool directControlAvailable: root.implementation?.directControlAvailable ?? (false)
    readonly property bool fanLevelControlSupported: root.implementation?.fanLevelControlSupported ?? (false)
    readonly property bool stateKnown: root.implementation?.stateKnown ?? (false)
    readonly property bool busy: root.implementation?.busy ?? (false)
    readonly property string profile: root.implementation?.profile ?? ("firmware")
    readonly property int fanRpm: root.implementation?.fanRpm ?? (-1)
    readonly property string fanLevel: root.implementation?.fanLevel ?? ("")
    readonly property string configPath: root.implementation?.configPath ?? ("")
    readonly property string statusReason: root.implementation?.statusReason ?? (AlisIntergration.available ? "integration-disabled" : "integration-not-installed")
    readonly property bool lastApplySucceeded: root.implementation?.lastApplySucceeded ?? (false)
    readonly property string lastApplyError: root.implementation?.lastApplyError ?? ("")
    readonly property string pendingOperation: root.implementation?.pendingOperation ?? ("")
    readonly property bool profileFanControlEnabled: root.implementation?.profileFanControlEnabled ?? (false)
    readonly property string activePowerProfileKey: root.implementation?.activePowerProfileKey ?? ("")
    readonly property int configuredActiveFanLevel: root.implementation?.configuredActiveFanLevel ?? (0)
    function configuredFanLevel(key: string): int {
        if (root.implementation) return root.implementation.configuredFanLevel(key)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return 0
    }
    function refresh(): void {
        if (root.implementation) return root.implementation.refresh()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function setConfiguredFanLevel(key: string, requestedLevel): bool {
        if (root.implementation) return root.implementation.setConfiguredFanLevel(key, requestedLevel)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function setProfileFanControlEnabled(requestedEnabled: bool): bool {
        if (root.implementation) return root.implementation.setProfileFanControlEnabled(requestedEnabled)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function applyProfile(requestedProfile: string): bool {
        if (root.implementation) return root.implementation.applyProfile(requestedProfile)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function applyFanLevel(requestedLevel): bool {
        if (root.implementation) return root.implementation.applyFanLevel(requestedLevel)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function applyConfiguredPowerProfileFanLevel(): bool {
        if (root.implementation) return root.implementation.applyConfiguredPowerProfileFanLevel()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
}
