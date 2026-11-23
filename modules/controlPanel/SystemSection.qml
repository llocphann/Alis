pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Compact system-status surface. Global Theme routing is Material-only in v1.0;
// explicit Control Panel island skin still owns its surface when selected.
PanelSurface {
    id: root
    islandSkin: (Config.options?.controlPanel?.style ?? "panel") === "island"
    Layout.fillWidth: true
    implicitHeight: statsRow.implicitHeight + 12
    elevation: 1
    radiusOverride: islandSkin ? -1 : Appearance.rounding.small

    readonly property bool compactMode: Config.options?.controlPanel?.compactMode ?? true
    readonly property real _contentHPad: root.compactMode ? 5 : 6
    readonly property real _contentVPad: root.compactMode ? 5 : 6

    RowLayout {
        id: statsRow
        anchors.fill: parent
        anchors.leftMargin: root._contentHPad
        anchors.rightMargin: root._contentHPad
        anchors.topMargin: root._contentVPad
        anchors.bottomMargin: root._contentVPad
        spacing: root.compactMode ? 6 : 8

        StatBar {
            Layout.fillWidth: true
            label: "CPU"
            value: (ResourceUsage.cpuUsage ?? 0) * 100
            barColor: value > 80
                ? Appearance.colors.colError : Appearance.colors.colPrimary
        }

        StatBar {
            Layout.fillWidth: true
            label: "RAM"
            value: (ResourceUsage.memoryUsedPercentage ?? 0) * 100
            barColor: (ResourceUsage.memoryUsedPercentage ?? 0) > 0.85
                ? Appearance.colors.colError : Appearance.colors.colPrimary
        }

        Loader {
            Layout.fillWidth: Battery.available
            visible: active
            active: Battery.available
            sourceComponent: StatBar {
                label: "BAT"
                value: (Battery.percentage ?? 0) * 100
                barColor: value < 20
                    ? Appearance.colors.colError
                    : Battery.isCharging
                        ? Appearance.colors.colSuccess
                        : Appearance.colors.colPrimary
            }
        }
    }

    component StatBar: ColumnLayout {
        id: bar
        property string label
        property real value: 0
        property color barColor: Appearance.colors.colPrimary

        spacing: 2

        RowLayout {
            spacing: 4

            StyledText {
                text: bar.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: Math.round(bar.value) + "%"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colOnLayer1
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: root.compactMode ? 3 : 4

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: Appearance.colors.colLayer2

                Rectangle {
                    width: parent.width * Math.min(1, Math.max(0, bar.value / 100))
                    height: parent.height
                    radius: 2
                    color: bar.barColor

                    Behavior on width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
