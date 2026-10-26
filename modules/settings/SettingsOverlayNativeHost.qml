import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// Native ownership only. SettingsOverlay retains the single mature content tree.
PanelWindow {
    property var controller: null
    visible: controller?.settingsOpen || controller?._closeAnimRunning || false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:settingsOverlay"
    // Both external pkexec agents and the shell's own Polkit window must
    // overlay Settings. Never promote Settings to Top during authentication.
    WlrLayershell.layer: (GlobalStates.settingsNativeDialogOpen
        || AlisIntergration.authorizationPending || PolkitService.active)
        ? WlrLayer.Bottom : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: controller?.settingsOpen
        && !GlobalStates.regionSelectorOpen && !GlobalStates.settingsNativeDialogOpen
        && !PolkitService.active && !AlisIntergration.authorizationPending
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
}
