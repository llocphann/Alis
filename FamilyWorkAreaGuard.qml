pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Keep gapless tiled clients distinguishable from fullscreen while family
// reservations are replaced or restored after fullscreen. Fullscreen clients
// ignore this transparent buffer; it never takes input.
Scope {
    id: root
    property bool guarded: false
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            FamilyWorkAreaHold {
                id: hold
                guarded: root.guarded || GameMode.hasFullscreenOnOutput(modelData.name)
            }
            screen: modelData
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // GameMode's Niri size heuristic tolerates two logical pixels.
            // Existing fullscreen clients ignore exclusive zones.
            exclusiveZone: hold.retained ? 3 : 0
            implicitHeight: 3
            anchors { top: true; left: true; right: true }
            WlrLayershell.namespace: "alis:family-workarea-guard"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
        }
    }
}
