import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs
import qs.modules.common

Scope {
    id: root

    property bool panelMapped: false
    readonly property bool allowMultiplePanels:
        Config.options?.waffles?.behavior?.allowMultiplePanels ?? false

    function enforceExclusivity(): void {
        if (!root.allowMultiplePanels && GlobalStates.waffleActionCenterOpen) {
            GlobalStates.searchOpen = false
            GlobalStates.waffleNotificationCenterOpen = false
            GlobalStates.waffleWidgetsOpen = false
        }
    }

    Timer {
        id: unmapWatchdogTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!GlobalStates.waffleActionCenterOpen)
                root.panelMapped = false
        }
    }

    Component.onCompleted: {
        root.panelMapped = GlobalStates.waffleActionCenterOpen
        root.enforceExclusivity()
    }

    Connections {
        target: GlobalStates
        function onWaffleActionCenterOpenChanged() {
            if (GlobalStates.waffleActionCenterOpen) {
                unmapWatchdogTimer.stop()
                root.panelMapped = true
            } else {
                unmapWatchdogTimer.restart()
            }
            root.enforceExclusivity()
        }
    }

    PanelWindow {
        id: backdropWindow
        visible: root.panelMapped
            && GlobalStates.waffleActionCenterOpen
            && !content.closing
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "quickshell:wActionCenterBg"
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
            onClicked: GlobalStates.waffleActionCenterOpen = false
        }
    }

    PanelWindow {
        id: panelWindow
        visible: root.panelMapped
        exclusiveZone: 0
        readonly property bool acceptsInput:
            GlobalStates.waffleActionCenterOpen
            && !content.closing
            && content.panelOpacity > 0.01
        WlrLayershell.namespace: "quickshell:wactionCenter"
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
            right: true
        }

        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Item {
            id: emptyPanelInput
            width: 0
            height: 0
        }

        ActionCenterContent {
            id: content
            anchors.fill: parent
            presented: GlobalStates.waffleActionCenterOpen
            panelRightAligned: true
            onClosed: {
                unmapWatchdogTimer.stop()
                GlobalStates.waffleActionCenterOpen = false
                root.panelMapped = false
            }
        }
    }
}
