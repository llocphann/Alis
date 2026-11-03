import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    property bool panelMapped: false
    readonly property bool allowMultiplePanels:
        Config.options?.waffles?.behavior?.allowMultiplePanels ?? false

    function enforceExclusivity(): void {
        if (!root.allowMultiplePanels && GlobalStates.waffleWidgetsOpen) {
            GlobalStates.searchOpen = false
            GlobalStates.waffleActionCenterOpen = false
            GlobalStates.waffleNotificationCenterOpen = false
        }
    }

    Timer {
        id: unmapWatchdogTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!GlobalStates.waffleWidgetsOpen)
                root.panelMapped = false
        }
    }

    Component.onCompleted: {
        root.panelMapped = GlobalStates.waffleWidgetsOpen
        root.enforceExclusivity()
    }

    Connections {
        target: GlobalStates
        function onWaffleWidgetsOpenChanged() {
            if (GlobalStates.waffleWidgetsOpen) {
                unmapWatchdogTimer.stop()
                root.panelMapped = true
            } else {
                unmapWatchdogTimer.restart()
            }
            root.enforceExclusivity()
        }
    }

    // Click-outside-to-close overlay
    PanelWindow {
        id: backdropWindow
        visible: root.panelMapped
            && GlobalStates.waffleWidgetsOpen
            && !content.closing
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "quickshell:wWidgetsBg"
        WlrLayershell.layer: WlrLayer.Top
        color: "transparent"
        mask: Region {
            item: backdropWindow.visible ? backdropMouse : emptyBackdropInput
        }

        Item {
            id: emptyBackdropInput
            width: 0
            height: 0
        }

        MouseArea {
            id: backdropMouse
            anchors.fill: parent
            enabled: backdropWindow.visible
            onClicked: GlobalStates.waffleWidgetsOpen = false
        }
    }

    PanelWindow {
        id: panelWindow
        visible: root.panelMapped
        exclusiveZone: 0
        readonly property bool acceptsInput:
            GlobalStates.waffleWidgetsOpen
            && !content.closing
            && content.panelOpacity > 0.01
        WlrLayershell.namespace: "quickshell:wWidgets"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: panelWindow.acceptsInput
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {
            item: panelWindow.acceptsInput ? content : emptyPanelInput
        }

        anchors {
            bottom: Config.options?.waffles?.bar?.bottom ?? false
            top: !(Config.options?.waffles?.bar?.bottom ?? false)
            left: true
        }

        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Item {
            id: emptyPanelInput
            width: 0
            height: 0
        }

        WidgetsContent {
            id: content
            anchors.fill: parent
            presented: GlobalStates.waffleWidgetsOpen

            onClosed: {
                unmapWatchdogTimer.stop()
                GlobalStates.waffleWidgetsOpen = false
                root.panelMapped = false
            }
        }
    }

}
