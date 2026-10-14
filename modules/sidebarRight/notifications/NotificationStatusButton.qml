import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonIcon: ""
    property string buttonText: ""

    Accessible.name: button.buttonText.length > 0
        ? button.buttonText
        : button.buttonIcon.replace(/_/g, " ")

    baseHeight: 36
    baseWidth: content.implicitWidth + 46
    clickedWidth: baseWidth + 6

    buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius
        : Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.alisEverywhere ? Appearance.alis.roundingSmall : baseHeight / 2
    buttonRadiusPressed: Appearance.zzzEverywhere ? Appearance.zzz.cornerRadius
        : Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
    colBackground: Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
        : Appearance.auroraEverywhere ? "transparent" : Appearance.colors.colLayer2
    colBackgroundHover: Appearance.zzzEverywhere ? Appearance.zzz.chrome
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover : Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.zzzEverywhere ? Appearance.zzz.sticker
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive : Appearance.colors.colLayer2Active
    property color colText: Appearance.zzzEverywhere
        ? (toggled ? Appearance.zzz.onSticker : Appearance.zzz.ink)
        : Appearance.alisEverywhere
        ? (toggled ? Appearance.alis.colOnPrimaryContainer : Appearance.alis.colText)
        : (toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)

    contentItem: Item {
        id: content
        anchors.fill: parent
        implicitWidth: contentRowLayout.implicitWidth
        implicitHeight: contentRowLayout.implicitHeight
        RowLayout {
            id: contentRowLayout
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                visible: buttonIcon !== ""
                text: buttonIcon
                iconSize: Appearance.font.pixelSize.huge
                color: button.colText
            }
            StyledText {
                visible: buttonText !== ""
                text: buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                color: button.colText
            }
        }
    }

}