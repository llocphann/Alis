import QtQuick
import QtQuick.Controls
import qs.modules.common

Slider {
    id: root
    from: 0; to: 1
    property string unit:"%"
    // Editor-only value gutter; other slider consumers keep original metrics.
    property bool editorCompact:false
    property real displayScale:unit === "%" ? 100 : 1
    readonly property string valueText:Math.round(value*displayScale)+" "+unit
    readonly property color sliderInk: Appearance.m3colors.darkmode
        ? AbyssStyle.textColor : "#000000"
    readonly property color sliderMutedInk: Appearance.m3colors.darkmode
        ? AbyssStyle.textColorMuted : "#1a1a1a"
    rightPadding:editorCompact ? 46*Appearance.fontSizeScale : 52
    implicitHeight: editorCompact ? 30*Appearance.fontSizeScale : 32
    background: Rectangle {
        x: root.leftPadding; y: (root.height-height)/2
        width: root.availableWidth; height: 2
        color: Qt.alpha(root.sliderInk,0.16)
        Rectangle { width: root.visualPosition*parent.width; height: 2; color: AbyssStyle.accent }
    }
    handle: Rectangle {
        x: root.leftPadding+root.visualPosition*(root.availableWidth-width)
        y: (root.height-height)/2
        width: root.pressed ? 12 : 10; height: width; radius: width/2
        color: AbyssStyle.specular
    }
    AbyssLabel { anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;text:root.valueText;color:root.sliderMutedInk }
}
