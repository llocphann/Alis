pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property var targetScreen: null

    Connections {
        target: PolkitService
        function onActiveChanged(): void {
            if (PolkitService.active)
                root.targetScreen = GlobalStates.focusedScreen
            else
                root.targetScreen = null
        }
    }

    Loader {
        // Only activate if Polkit agent is registered AND there's an active auth request.
        // Mount a single Exclusive keyboard window on the focused screen instead of
        // competing Exclusive windows on every screen.
        active: PolkitService.available && PolkitService.active
        sourceComponent: PanelWindow {
            id: panelWindow
            screen: root.targetScreen ?? GlobalStates.focusedScreen

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            color: "transparent"
            WlrLayershell.namespace: "quickshell:polkit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            Loader {
                anchors.fill: parent
                focus: true
                source: "PolkitContent.qml"
            }
        }
    }
}
