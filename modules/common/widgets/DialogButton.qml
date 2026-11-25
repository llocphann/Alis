import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

/**
 * Material 3 dialog button. See https://m3.material.io/components/dialogs/overview
 */
RippleButton {
    id: root

    property string buttonText
    padding: 14
    implicitHeight: 36
    implicitWidth: buttonTextWidget.implicitWidth + padding * 2
    buttonRadius: Appearance?.rounding.full ?? 9999

    property color colEnabled: Appearance.colors.colPrimary
    property color colDisabled: Appearance.colors.colOutline
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    property alias colText: buttonTextWidget.color

    contentItem: StyledText {
        id: buttonTextWidget
        anchors.fill: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        text: root.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Appearance?.font.pixelSize.small ?? 12
        font.family: Appearance.font.family.main
        font.weight: Font.Medium
        font.italic: false
        color: root.enabled ? root.colEnabled : root.colDisabled

        Behavior on color {
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

}
