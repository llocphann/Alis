import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root

    property real contentRotation: 0
    readonly property bool verticalContent: Math.abs(root.contentRotation) === 90
    readonly property bool isCharging: Battery.isCharging
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= (Config.options?.battery?.low ?? 20) / 100

    implicitWidth: batteryProgress.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    activeFocusOnTab: true

    Accessible.role: Accessible.StaticText
    Accessible.name: Translation.tr("Battery") + " " + Math.round(root.percentage * 100) + "%"
    Accessible.focusable: true

    ClippedProgressBar {
        id: batteryProgress
        anchors.centerIn: parent
        valueBarWidth: Math.round((root.verticalContent ? 34 : 30) * Appearance.sizes.barModuleScale)
        valueBarHeight: Math.round((root.verticalContent ? 20 : 18) * Appearance.sizes.barModuleScale)
        font.pixelSize: Math.round((root.verticalContent ? 11 : 13) * Appearance.fontSizeScale * Appearance.sizes.barModuleScale)
        value: percentage
        highlightColor: (isLow && !isCharging)
            ? Appearance.colors.colError
            : Appearance.colors.colOnLayer0

        Item {
            anchors.centerIn: parent
            width: batteryProgress.valueBarWidth
            height: batteryProgress.valueBarHeight

            RowLayout {
                anchors.centerIn: parent
                spacing: root.verticalContent ? 1 : 0
                layoutDirection: root.contentRotation < 0 ? Qt.RightToLeft : Qt.LeftToRight

                MaterialSymbol {
                    id: boltIcon
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: root.verticalContent ? 0 : -2 * Appearance.sizes.barModuleScale
                    Layout.rightMargin: root.verticalContent ? 0 : -2 * Appearance.sizes.barModuleScale
                    fill: 1
                    text: "bolt"
                    iconSize: Math.round(Appearance.font.pixelSize.smaller * Appearance.sizes.barModuleScale)
                    rotation: -root.contentRotation
                    opacity: (isCharging && percentage < 1) ? 1 : 0
                    visible: opacity > 0
                    
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { 
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    font: batteryProgress.font
                    rotation: -root.contentRotation
                    text: batteryProgress.text
                }
            }
        }
    }

    KeyboardFocusRing {
        anchors.fill: batteryProgress
        focusVisible: root.activeFocus
        radius: batteryProgress.radius
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
        alternativeVisibleCondition: root.activeFocus
    }
}
