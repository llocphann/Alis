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
    property color contentColor: buttonWithIconRoot.colBackground.a > 0.01
        ? ColorUtils.ensureReadable(Appearance.colors.colOnLayer2,
            buttonWithIconRoot.colBackground, 4.5)
        : Appearance.colors.colOnSecondaryContainer
    property Component mainContentComponent: Component {
        StyledText {
            visible: text !== ""
            text: buttonWithIconRoot.mainText
            // Icon buttons are frequently placed inside narrow settings panes.
            // Respect the loader's assigned width instead of painting the label
            // past the button/pane boundary when the text is wider than it.
            elide: Text.ElideRight
            maximumLineCount: 1
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
    implicitHeight: 35
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            width: Math.min(parent.width, implicitWidth)
            spacing: 5
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
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
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                sourceComponent: buttonWithIconRoot.mainContentComponent
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
