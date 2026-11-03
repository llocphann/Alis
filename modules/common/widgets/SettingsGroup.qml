import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    default property alias contentData: content.data

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + SettingsMaterialPreset.groupPadding * 2

    radius: SettingsMaterialPreset.groupRadius
    color: SettingsMaterialPreset.groupColor
    border.width: 0
    border.color: SettingsMaterialPreset.groupBorderColor

    Behavior on color {
        enabled: Appearance.animationsEnabled
        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }
    Behavior on border.color {
        enabled: Appearance.animationsEnabled
        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }
    Behavior on border.width {
        enabled: Appearance.animationsEnabled
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    function ensureControlOnActiveSubTab(control) {
        // Pagination is handled at ContentPage level.
    }

    ColumnLayout {
        id: content
        objectName: "settingsGroupContent"
        anchors {
            fill: parent
            margins: SettingsMaterialPreset.groupPadding
        }
        spacing: SettingsMaterialPreset.groupSpacing
    }
}
