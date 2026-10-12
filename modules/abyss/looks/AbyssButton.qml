import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

AbstractButton {
    id: root
    property string glyph: ""
    property bool compact: false
    property bool editorSquare: false
    readonly property bool iconOnly: compact || text.length === 0
    property bool outlined: true
    property bool toolTipEnabled: true
    property string description: text
    readonly property color baseInk: Appearance.m3colors.darkmode
        ? AbyssStyle.textColor : "#000000"
    readonly property color activeInk: Appearance.m3colors.darkmode
        ? AbyssStyle.accent : "#000000"
    hoverEnabled: true
    implicitHeight: editorSquare && iconOnly ? 30 * Appearance.fontSizeScale : 36
    implicitWidth: editorSquare && iconOnly ? 30 * Appearance.fontSizeScale
        : Math.max(36, contentItem.implicitWidth + 24)
    Accessible.name: description
    Accessible.role: Accessible.Button
    font.family: AbyssStyle.fontFamily
    font.pixelSize: AbyssStyle.fontSize
    leftPadding: editorSquare && iconOnly ? 0 : 12
    rightPadding: editorSquare && iconOnly ? 0 : 12
    topPadding: editorSquare && iconOnly ? 0 : padding
    bottomPadding: editorSquare && iconOnly ? 0 : padding
    background: Rectangle {
        radius: root.editorSquare && root.iconOnly
            ? Math.min(height/2, 8 * Appearance.fontSizeScale) : height/2
        color: Qt.alpha(AbyssStyle.accent,root.down ? .24 : root.checked ? .2 : root.hovered ? .12 : .05)
        border.width: root.visualFocus ? 2 : root.outlined ? 1 : 0
        border.color: Qt.alpha(AbyssStyle.accent,root.activeFocus ? .8 : root.hovered || root.checked ? .35 : .15)
        Behavior on color { enabled: AbyssStyle.motionEnabled; ColorAnimation { duration: AbyssStyle.motionFast } }
        Behavior on border.color { enabled: AbyssStyle.motionEnabled; ColorAnimation { duration: AbyssStyle.motionFast } }
    }
    opacity: enabled ? (down ? 0.70 : 1) : 0.4
    contentItem: Item {
        implicitWidth: root.iconOnly ? 19 : labelledRow.implicitWidth
        implicitHeight: root.iconOnly ? 19 : Math.max(20,labelledRow.implicitHeight)
        MaterialSymbol {
            objectName:"abyssButtonCenteredGlyph"
            anchors.centerIn: parent
            visible: root.iconOnly && root.glyph.length > 0
            text: root.glyph
            iconSize: root.editorSquare ? 17 * Appearance.fontSizeScale : 20
            color: root.hovered || root.checked ? root.activeInk : root.baseInk
        }
        RowLayout {
            id: labelledRow
            anchors.fill: parent
            visible: !root.iconOnly
            spacing: 6
            MaterialSymbol {
                visible: root.glyph.length > 0
                text: root.glyph
                iconSize: 20
                color: root.hovered || root.checked ? root.activeInk : root.baseInk
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: root.text
                color: root.hovered || root.checked ? root.activeInk : root.baseInk
                font: root.font
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
    StyledToolTip {
        objectName:"abyssButtonToolTip"
        enabled:root.toolTipEnabled && (root.compact || root.text.length === 0)
        text:root.description
        delay:700
    }
}
