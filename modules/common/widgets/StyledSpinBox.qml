import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Refined Material 3 tonal stepper / SpinBox component with centered +/- icons
 * and centered tabular numeric input.
 */
SpinBox {
    id: root

    property real baseHeight: 32
    property real radius: 9
    property real innerButtonRadius: 7
    topPadding: 0
    bottomPadding: 0
    leftPadding: (down.indicator ? down.indicator.width : (root.baseHeight - 4)) + 6
    rightPadding: (up.indicator ? up.indicator.width : (root.baseHeight - 4)) + 6
    implicitHeight: root.baseHeight
    implicitWidth: Math.max(
        implicitBackgroundWidth + leftInset + rightInset,
        Math.max(42, labelText.implicitWidth + 10) + leftPadding + rightPadding
    )
    hoverEnabled: true
    editable: true
    textFromValue: function(value, locale) {
        return String(value)
    }
    valueFromText: function(text, locale) {
        const parsed = Number.parseInt(String(text).trim(), 10)
        return Number.isFinite(parsed) ? parsed : root.value
    }

    opacity: root.enabled ? 1 : 0.4

    background: Rectangle {
        color: SettingsMaterialPreset.controlSurface
        radius: root.radius
        border.width: root.activeFocus || labelText.activeFocus ? 1.5 : 1
        border.color: root.activeFocus || labelText.activeFocus
            ? Appearance.colors.colPrimary
            : SettingsMaterialPreset.controlBorderColor

        Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
    }

    // Direct TextInput contentItem so QQuickSpinBox natively commits typed edits
    // and keeps displayText synchronized on +/- stepping.
    contentItem: StyledTextInput {
        id: labelText
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        text: root.displayText
        color: SettingsMaterialPreset.textColor
        font.family: Appearance.font.family.numbers
        font.variableAxes: Appearance.font.variableAxes.numbers
        font.features: ({ "tnum": 1 })
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        readOnly: !root.editable
        validator: root.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        selectByMouse: true
        clip: true
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: 2
        }
        width: root.baseHeight - 4
        height: root.baseHeight - 4
        implicitHeight: root.baseHeight - 4
        implicitWidth: root.baseHeight - 4
        radius: root.innerButtonRadius

        color: root.down.pressed ? SettingsMaterialPreset.controlSurfaceActive
            : root.down.hovered ? SettingsMaterialPreset.controlSurfaceHover
            : "transparent"

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "remove"
            iconSize: 16
            color: SettingsMaterialPreset.textColor
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
            rightMargin: 2
        }
        width: root.baseHeight - 4
        height: root.baseHeight - 4
        implicitHeight: root.baseHeight - 4
        implicitWidth: root.baseHeight - 4
        radius: root.innerButtonRadius

        color: root.up.pressed ? SettingsMaterialPreset.controlSurfaceActive
            : root.up.hovered ? SettingsMaterialPreset.controlSurfaceHover
            : "transparent"

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "add"
            iconSize: 16
            color: SettingsMaterialPreset.textColor
        }
    }
}
