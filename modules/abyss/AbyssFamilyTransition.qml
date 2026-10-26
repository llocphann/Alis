pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common

// A finite inward flood. Never receives pointer or keyboard input, including
// during config reload and cancellation. No wallpaper capture or blur pass.
Scope {
    id: root
    signal exitComplete()
    signal enterComplete()
    property real pull: 0
    function finish(): void {
        GlobalStates.familyTransitionActive = false
        root.enterComplete()
    }
    Component.onCompleted: choreography.start()
    SequentialAnimation {
        id: choreography
        NumberAnimation { target: root; property: "pull"; to: 1; duration: Appearance.animationsEnabled ? 180 : 1; easing.type: Easing.OutCubic }
        ScriptAction { script: root.exitComplete() }
        PauseAnimation { duration: 80 }
        NumberAnimation { target: root; property: "pull"; to: 0; duration: Appearance.animationsEnabled ? 260 : 1; easing.type: Easing.OutCubic }
        ScriptAction { script: root.finish() }
    }
    Timer { interval: 1400; running: true; repeat: false; onTriggered: root.finish() }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            visible: GlobalStates.familyTransitionActive
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "alis:abyss-transition"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillRule: ShapePath.OddEvenFill
                    fillColor: Qt.alpha(Appearance.m3colors.m3surface, root.pull * 0.92)
                    strokeColor: Qt.alpha(Appearance.colors.colPrimary, root.pull * 0.55)
                    strokeWidth: 1
                    PathSvg {
                        path: {
                            const d = root.pull * Math.min(window.width, window.height) * 0.18
                            return "M-50,-50 H" + (window.width+50) + " V" + (window.height+50)
                                + " H-50 Z M" + d + "," + d + " H" + (window.width-d)
                                + " V" + (window.height-d) + " H" + d + " Z"
                        }
                    }
                }
            }
        }
    }
}
