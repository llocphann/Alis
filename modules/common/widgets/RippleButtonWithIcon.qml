import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RippleButton {
    id: buttonWithIconRoot
    property string nerdIcon  // Manual override (empty = auto from MaterialSymbol)
    property string materialIcon
    property bool materialIconFill: true
    property string mainText: "Button text"
    readonly property bool _hasIcon: (buttonWithIconRoot.nerdIcon || buttonWithIconRoot.materialIcon).length > 0
    readonly property bool _hasText: buttonWithIconRoot.mainText.length > 0 || buttonWithIconRoot.mainContentComponent !== defaultMainContentComponent
    property color contentColor: buttonWithIconRoot.colBackground.a > 0.01
        ? ColorUtils.ensureReadable(Appearance.colors.colOnLayer2,
            buttonWithIconRoot.colBackground, 4.5)
        : Appearance.colors.colOnSecondaryContainer
    property Component defaultMainContentComponent: Component {
        StyledText {
            visible: text !== ""
            text: buttonWithIconRoot.mainText
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: buttonWithIconRoot.contentColor
            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
        }
    }
    property Component mainContentComponent: defaultMainContentComponent
    implicitHeight: 35
    horizontalPadding: 12
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            width: Math.min(parent.width, implicitWidth)
            spacing: (buttonWithIconRoot._hasIcon && buttonWithIconRoot._hasText) ? 6 : 0
            MaterialSymbol {
                visible: buttonWithIconRoot._hasIcon
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: buttonWithIconRoot.nerdIcon || buttonWithIconRoot.materialIcon
                iconSize: Appearance.font.pixelSize.larger
                color: buttonWithIconRoot.contentColor
                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                animateFill: true
                forceNerd: buttonWithIconRoot.nerdIcon !== ""
            }
            Loader {
                visible: buttonWithIconRoot._hasText
                active: buttonWithIconRoot._hasText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                sourceComponent: buttonWithIconRoot.mainContentComponent
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
