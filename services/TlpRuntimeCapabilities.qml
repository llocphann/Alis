pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var implementation: AlisIntergration.session?.tlpCapabilities ?? (null)
    property string missingOperationError: ""
    readonly property int safetyRefreshIntervalMs: root.implementation?.safetyRefreshIntervalMs ?? (0)
    readonly property var values: root.implementation?.values ?? (({}))
    readonly property var numberRanges: root.implementation?.numberRanges ?? (({}))
    readonly property var numberDefaults: root.implementation?.numberDefaults ?? (({}))
    readonly property string cpuScalingDriver: root.implementation?.cpuScalingDriver ?? ("")
    readonly property string intelPstateStatus: root.implementation?.intelPstateStatus ?? ("")
    readonly property string amdPstateStatus: root.implementation?.amdPstateStatus ?? ("")
    readonly property string kernelRelease: root.implementation?.kernelRelease ?? ("")
    readonly property string intelGpuDriver: root.implementation?.intelGpuDriver ?? ("")
    readonly property bool rdwProbeDone: root.implementation?.rdwProbeDone ?? (false)
    readonly property bool rdwAvailable: root.implementation?.rdwAvailable ?? (false)
    readonly property var cpuDriverModeKeys: root.implementation?.cpuDriverModeKeys ?? ([])
    readonly property var intelGpuMinKeys: root.implementation?.intelGpuMinKeys ?? ([])
    readonly property var intelGpuMaxKeys: root.implementation?.intelGpuMaxKeys ?? ([])
    readonly property var intelGpuBoostKeys: root.implementation?.intelGpuBoostKeys ?? ([])
    function isRdwSetting(key: string): bool {
        if (root.implementation) return root.implementation.isRdwSetting(key)
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
        return false
    }
    function refreshRdw(): void {
        if (root.implementation) return root.implementation.refreshRdw()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
    function refresh(): void {
        if (root.implementation) return root.implementation.refresh()
        root.missingOperationError = "Install and enable the Alis-Intergration integration to use this action"
    }
}
