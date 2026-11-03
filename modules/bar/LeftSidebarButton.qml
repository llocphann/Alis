import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root
    cookieMorphing: true

    property bool showPing: false

    Accessible.name: Translation.tr("Toggle left sidebar")

    property real buttonPadding: 5 * Appearance.sizes.barModuleScale
    implicitWidth: sidebarIcon.width + buttonPadding * 2
    implicitHeight: sidebarIcon.height + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    // Spatial control: addresses whatever sidebar role occupies the left slot.
    toggled: ShellLayoutController.sidebarOpenAtSlot("left",
        root.QsWindow.window?.screen?.name ?? "")

    onClicked: {
        ShellLayoutController.toggleSidebarAtSlot("left",
            root.QsWindow.window?.screen?.name ?? "");
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    MaterialSymbol {
        id: sidebarIcon
        anchors.centerIn: parent
        text: "left_panel_open"
        iconSize: Math.round(20 * Appearance.sizes.barModuleScale)
        color: root.toggled
            ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnLayer0

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2 * Appearance.sizes.barModuleScale
                rightMargin: -2 * Appearance.sizes.barModuleScale
            }
            implicitWidth: 8 * Appearance.sizes.barModuleScale
            implicitHeight: 8 * Appearance.sizes.barModuleScale
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary
            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
        }
    }
}
