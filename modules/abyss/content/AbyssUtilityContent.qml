pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services
import qs.modules.sessionScreen
import qs.modules.cheatsheet
import qs.modules.shellUpdate

Item {
    id: root
    property string kind: "session"
    property string outputName: ""
    property var participant: null
    readonly property var feature: content.item
    readonly property real desiredWidth: feature?.desiredWidth ?? 640
    readonly property real desiredHeight: feature?.desiredHeight ?? 700
    signal closeRequested()
    function focusPrimarySurface(): void {
        if (feature) feature.forceActiveFocus()
        else root.forceActiveFocus()
    }
    Loader {
        id: content
        anchors.fill: parent
        sourceComponent: root.kind === "session" ? session : root.kind === "cheatsheet" ? cheatsheet : update
    }
    Component { id: session; SessionScreen { embeddedHost: root } }
    Component { id: cheatsheet; Cheatsheet { embeddedHost: root } }
    Component { id: update; ShellUpdateOverlay { embeddedHost: root } }
}
