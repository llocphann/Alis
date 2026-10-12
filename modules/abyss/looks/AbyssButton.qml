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
    property bool outlined: true
    property bool toolTipEnabled: true
    property string description: text
    readonly property color baseInk: Appearance.m3colors.darkmode
        ? AbyssStyle.textColor : "#000000"
    readonly property color activeInk: Appearance.m3colors.darkmode
        ? AbyssStyle.accent : "#000000"
    hoverEnabled: true
    implicitHeight: 36
    implicitWidth: Math.max(36, contentItem.implicitWidth + 24)
    Accessible.name: description
    Accessible.role: Accessible.Button
    font.family: AbyssStyle.fontFamily
    font.pixelSize: AbyssStyle.fontSize
    leftPadding: 12
    rightPadding: 12
    background: Rectangle {
        radius: height/2
        color: Qt.alpha(AbyssStyle.accent,root.down ? .24 : root.checked ? .2 : root.hovered ? .12 : .05)
        border.width: root.visualFocus ? 2 : root.outlined ? 1 : 0
        border.color: Qt.alpha(AbyssStyle.accent,root.activeFocus ? .8 : root.hovered || root.checked ? .35 : .15)
        Behavior on color { enabled: AbyssStyle.motionEnabled; ColorAnimation { duration: AbyssStyle.motionFast } }
        Behavior on border.color { enabled: AbyssStyle.motionEnabled; ColorAnimation { duration: AbyssStyle.motionFast } }
    }
    opacity: enabled ? (down ? 0.70 : 1) : 0.4
    contentItem: RowLayout {
        spacing: root.compact || root.text.length === 0 ? 0 : 6
        // Equal gutters center the glyph in a stretched icon-only button.
        Item {
            visible: root.compact || root.text.length === 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
        }
        MaterialSymbol {
            visible: root.glyph.length > 0
            text: root.glyph
            iconSize: 20
            color: root.hovered || root.checked ? root.activeInk : root.baseInk
            Layout.alignment: Qt.AlignVCenter
        }
        Item {
            visible: root.compact || root.text.length === 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
        }
        Text {
            visible: !root.compact && root.text.length > 0
            text: root.text
            color: root.hovered || root.checked ? root.activeInk : root.baseInk
            font: root.font
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }
    StyledToolTip {
        objectName:"abyssButtonToolTip"
        enabled:root.toolTipEnabled && (root.compact || root.text.length === 0)
        text:root.description
        delay:700
    }
}
