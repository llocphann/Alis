import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.services.deferred
import qs
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    property bool panelMapped: false
    readonly property bool allowMultiplePanels: Config.options?.waffles?.behavior?.allowMultiplePanels ?? false

    function enforceExclusivity(): void {
        if (!root.allowMultiplePanels && GlobalStates.searchOpen) {
            GlobalStates.waffleActionCenterOpen = false
            GlobalStates.waffleNotificationCenterOpen = false
            GlobalStates.waffleWidgetsOpen = false
        }
    }

    Timer {
        id: unmapWatchdogTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!GlobalStates.searchOpen)
                root.panelMapped = false
        }
    }

    Component.onCompleted: {
        root.panelMapped = GlobalStates.searchOpen
        root.enforceExclusivity()
    }

    Connections {
        target: GlobalStates
        function onSearchOpenChanged() {
            if (GlobalStates.searchOpen) {
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
            && GlobalStates.searchOpen
            && !content.closing
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "quickshell:wStartMenuBg"
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
            onClicked: GlobalStates.searchOpen = false
        }
    }

    PanelWindow {
        id: panelWindow
        visible: root.panelMapped
        exclusiveZone: 0
        readonly property bool acceptsInput:
            GlobalStates.searchOpen
            && !content.closing
            && content.panelOpacity > 0.01
        WlrLayershell.namespace: "quickshell:wStartMenu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: panelWindow.acceptsInput
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {
            item: panelWindow.acceptsInput ? content : emptyPanelInput
        }

        // Adaptive minimum size based on preset
        property string preset: Config.options.waffles?.startMenu?.sizePreset ?? "normal"
        property int minW: preset === "mini" ? 200 : preset === "compact" ? 280 : 360
        property int minH: preset === "mini" ? 200 : preset === "compact" ? 280 : 300

        anchors {
            bottom: Config.options?.waffles?.bar?.bottom ?? true
            top: !(Config.options?.waffles?.bar?.bottom ?? true)
            left: Config.options?.waffles?.bar?.leftAlignApps ?? false
        }

        implicitWidth: Math.max(minW, content.implicitWidth)
        implicitHeight: Math.max(minH, content.implicitHeight)

        Item {
            id: emptyPanelInput
            width: 0
            height: 0
        }

        StartMenuContent {
            id: content
            anchors.fill: parent
            presented: GlobalStates.searchOpen
            focus: true
            onClosed: {
                unmapWatchdogTimer.stop()
                GlobalStates.searchOpen = false
                root.panelMapped = false
                LauncherSearch.query = ""
            }
        }
    }

}
