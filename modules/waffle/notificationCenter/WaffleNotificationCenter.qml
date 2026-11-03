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
        if (!root.allowMultiplePanels && GlobalStates.waffleNotificationCenterOpen) {
            GlobalStates.searchOpen = false
            GlobalStates.waffleActionCenterOpen = false
            GlobalStates.waffleWidgetsOpen = false
        }
    }

    Timer {
        id: unmapWatchdogTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!GlobalStates.waffleNotificationCenterOpen)
                root.panelMapped = false
        }
    }

    Component.onCompleted: {
        root.panelMapped = GlobalStates.waffleNotificationCenterOpen
        Notifications.ensureInitialized()
        root.enforceExclusivity()
    }

    Connections {
        target: GlobalStates
        function onWaffleNotificationCenterOpenChanged() {
            if (GlobalStates.waffleNotificationCenterOpen) {
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
            && GlobalStates.waffleNotificationCenterOpen
            && !content.closing
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "quickshell:wNotificationCenterBg"
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
            onClicked: GlobalStates.waffleNotificationCenterOpen = false
        }
    }

    PanelWindow {
        id: panelWindow
        visible: root.panelMapped
        exclusiveZone: 0
        readonly property bool acceptsInput:
            GlobalStates.waffleNotificationCenterOpen
            && !content.closing
            && content.panelOpacity > 0.01
        WlrLayershell.namespace: "quickshell:wNotificationCenter"
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

        NotificationCenterContent {
            id: content
            anchors.fill: parent
            presented: GlobalStates.waffleNotificationCenterOpen
            panelRightAligned: true
            onClosed: {
                unmapWatchdogTimer.stop()
                GlobalStates.waffleNotificationCenterOpen = false
                root.panelMapped = false
            }
        }
    }
}
