import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property string iconName
    required property double percentage
    property real warningThreshold: 100
    property real cautionThreshold: 0  // 0 = disabled
    property bool shown: true
    property real contentRotation: 0
    readonly property real normalizedPercentage: Number.isFinite(root.percentage)
        ? Math.max(0, Math.min(1, root.percentage)) : 0
    clip: true
    visible: width > 0 && height > 0
    implicitWidth: resourceRowLayout.x < 0 ? 0 : resourceRowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight
    property bool warning: normalizedPercentage * 100 >= warningThreshold
    property bool caution: cautionThreshold > 0 && normalizedPercentage * 100 >= cautionThreshold && !warning

    RowLayout {
        id: resourceRowLayout
        spacing: 2 * Appearance.sizes.barModuleScale
        layoutDirection: root.contentRotation < 0 ? Qt.RightToLeft : Qt.LeftToRight
        x: shown ? 0 : -resourceRowLayout.width
        anchors {
            verticalCenter: parent.verticalCenter
        }

        ClippedFilledCircularProgress {
            id: resourceCircProg
            visible: true
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Math.round(Appearance.rounding.unsharpen * Appearance.sizes.barModuleScale)
            value: root.normalizedPercentage
            implicitSize: Math.round(20 * Appearance.sizes.barModuleScale)
            colPrimary: root.warning ? Appearance.colors.colError
                : root.caution ? Appearance.colors.colTertiary
                : Appearance.colors.colOnSurfaceVariant
            accountForLightBleeding: !root.warning && !root.caution
            enableAnimation: false

            Item {
                anchors.centerIn: parent
                width: resourceCircProg.implicitSize
                height: resourceCircProg.implicitSize
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: Font.DemiBold
                    fill: 1
                    text: iconName
                    iconSize: Math.round(Appearance.font.pixelSize.normal * Appearance.sizes.barModuleScale)
                    rotation: -root.contentRotation
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: fullPercentageTextMetrics.width
            implicitHeight: percentageText.implicitHeight

            TextMetrics {
                id: fullPercentageTextMetrics
                text: "100"
                font.pixelSize: Math.round(Appearance.font.pixelSize.small * Appearance.sizes.barModuleScale)
            }

            StyledText {
                id: percentageText
                anchors.centerIn: parent
                color: root.warning ? Appearance.colors.colError
                    : root.caution ? Appearance.colors.colTertiary
                    : Appearance.colors.colOnLayer1
                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                font.pixelSize: Math.round(Appearance.font.pixelSize.small * Appearance.sizes.barModuleScale)
                font.family: Appearance.font.family.main
                font.weight: Font.Normal
                font.italic: false
                rotation: -root.contentRotation
                text: `${Math.round(root.normalizedPercentage * 100).toString()}`
            }
        }

        Behavior on x {
            animation: NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
        }
    }

    Behavior on implicitWidth {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
}
