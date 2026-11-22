pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: filterField

    property alias colBackground: background.color
    readonly property string liveText: preeditText
        ? (text.slice(0, cursorPosition) + preeditText + text.slice(cursorPosition))
        : text

    Layout.fillHeight: true
    implicitWidth: 200
    implicitHeight: Math.max(Appearance.sizes.baseBarHeight, contentHeight + Math.round(12 * Appearance.fontSizeScale))
    leftPadding: 10
    rightPadding: leftPadding
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter

    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer

    background: Rectangle {
        id: background
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.full
        border.width: 0
        border.color: "transparent"
        Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
        Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
    }

    TextInputContextMenu {
        target: filterField
    }
}
