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

    implicitWidth: root.verticalContent
        ? (batteryProgress.valueBarHeight + Math.round(6 * Appearance.sizes.barModuleScale))
        : batteryProgress.implicitWidth
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
        rotation: -root.contentRotation
        valueBarWidth: Math.round(30 * Appearance.sizes.barModuleScale)
        valueBarHeight: Math.round(18 * Appearance.sizes.barModuleScale)
        font.pixelSize: Math.round(13 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale)
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
                spacing: 0

                MaterialSymbol {
                    id: boltIcon
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: -2 * Appearance.sizes.barModuleScale
                    Layout.rightMargin: -2 * Appearance.sizes.barModuleScale
                    fill: 1
                    text: "bolt"
                    iconSize: Math.round(Appearance.font.pixelSize.smaller * Appearance.sizes.barModuleScale)
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
                    text: batteryProgress.text
                }
            }
        }
    }

    KeyboardFocusRing {
        anchors.fill: batteryProgress
        rotation: batteryProgress.rotation
        focusVisible: root.activeFocus
        radius: batteryProgress.radius
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
        alternativeVisibleCondition: root.activeFocus
    }
}
