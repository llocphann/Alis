pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * Pick-and-place chip for arrangement editors: a pill showing an icon +
 * label that can be "lifted" (tap once) and then placed on any
 * ArrangeDropSlot. Purely presentational — the page owns the lifted
 * state and the actual move. Pairs with ArrangeDropSlot; pattern
 * documented in the alis-settings-ui skill.
 */
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string accessibleName: root.label
    property bool lifted: false
    property bool dimmed: false // something else is lifted
    signal tapped()

    implicitHeight: 34
    implicitWidth: chipRow.implicitWidth + 22
    radius: height / 2
    scale: lifted ? 1.06 : 1.0
    opacity: dimmed ? 0.55 : 1.0
    color: lifted ? Appearance.colors.colPrimaryContainer
         : chipHover.hovered ? Appearance.colors.colLayer2Hover
         : Appearance.colors.colLayer2
    border.width: lifted || activeFocus ? 2 : 1
    border.color: lifted || activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.checkable: true
    Accessible.checked: root.lifted
    Accessible.onPressAction: root.tapped()

    Keys.onPressed: event => {
        if (event.isAutoRepeat)
            return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.tapped()
            event.accepted = true
        }
    }

    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: 120 } }
    Behavior on scale {
        enabled: Appearance.animationsEnabled
        NumberAnimation { duration: 160; easing.type: Easing.OutBack }
    }
    Behavior on opacity { enabled: Appearance.animationsEnabled; NumberAnimation { duration: 120 } }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            text: root.icon
            iconSize: 17
            color: root.lifted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
        }
        StyledText {
            visible: root.label.length > 0
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.lifted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
        }
    }

    HoverHandler { id: chipHover }
    TapHandler { onTapped: root.tapped() }
}
