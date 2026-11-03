import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root

    property bool alwaysShowAllResources: false
    property real contentRotation: 0
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    activeFocusOnTab: true

    Accessible.role: Accessible.StaticText
    Accessible.name: Translation.tr("System resources")
    Accessible.focusable: true

    property QtObject resourceMonitor: ResourceUsageMonitor {
        network: false
        histories: false
        target: root
        active: !GameMode.active
    }

    RowLayout {
        id: rowLayout

        spacing: 0
        layoutDirection: root.contentRotation < 0 ? Qt.RightToLeft : Qt.LeftToRight
        anchors.fill: parent
        anchors.leftMargin: 4 * Appearance.sizes.barModuleScale
        anchors.rightMargin: 4 * Appearance.sizes.barModuleScale

        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            contentRotation: root.contentRotation
            shown: Config.options?.bar?.resources?.showMemoryIndicator ?? true
            warningThreshold: Config.options?.bar?.resources?.memoryWarningThreshold ?? 90
        }

        Resource {
            iconName: "thermostat"
            percentage: ResourceUsage.tempPercentage
            contentRotation: root.contentRotation
            shown: (Config.options?.bar?.resources?.showTempIndicator ?? true) &&
                ((Config.options?.bar?.resources?.alwaysShowTemp ?? true) ||
                    !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                    root.alwaysShowAllResources)
            Layout.leftMargin: shown ? 6 * Appearance.sizes.barModuleScale : 0
            cautionThreshold: Config.options?.bar?.resources?.tempCautionThreshold ?? 65
            warningThreshold: Config.options?.bar?.resources?.tempWarningThreshold ?? 80
        }

        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            contentRotation: root.contentRotation
            shown: (Config.options?.bar?.resources?.showCpuIndicator ?? true) &&
                ((Config.options?.bar?.resources?.alwaysShowCpu ?? true) ||
                    !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                    root.alwaysShowAllResources)
            Layout.leftMargin: shown ? 6 * Appearance.sizes.barModuleScale : 0
            warningThreshold: Config.options?.bar?.resources?.cpuWarningThreshold ?? 90
        }

        Resource {
            iconName: "memory_alt"
            percentage: ResourceUsage.gpuUsage
            contentRotation: root.contentRotation
            shown: (Config.options?.bar?.resources?.showGpuIndicator ?? true) &&
                ((Config.options?.bar?.resources?.alwaysShowGpu ?? true) ||
                    !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                    root.alwaysShowAllResources)
            Layout.leftMargin: shown ? 6 * Appearance.sizes.barModuleScale : 0
            warningThreshold: Config.options?.bar?.resources?.gpuWarningThreshold ?? 90
        }

    }

    KeyboardFocusRing {
        anchors.fill: parent
        focusVisible: root.activeFocus
    }

    ResourcesPopup {
        hoverTarget: root
        alternativeVisibleCondition: root.activeFocus
    }
}
