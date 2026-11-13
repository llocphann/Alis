import QtQuick
import qs.modules.dashboard
import qs.modules.abyss

Item {
    id: root
    property var participant: null
    readonly property bool editMode: content.editMode
    readonly property bool tabNamingActive: content.tabNamingActive
    readonly property bool contentReady: content.contentReady
    function handleEscape(): bool {
        return content.handleEscape()
    }
    function focusPrimarySurface(): void {
        content.focusPrimarySurface()
    }
    readonly property real topControlReserve: 0
    readonly property real bottomControlReserve: editor.stageHosted ? 0 : (editor.desiredHeight + 16)
    readonly property real editDockWidth: editor.desiredWidth
    readonly property real editDockHeight: editor.desiredHeight
    readonly property real editLeftDockWidth: editor.desiredLeftDockWidth
    readonly property real editLeftDockHeight: editor.desiredLeftDockHeight
    readonly property real editRightDockWidth: editor.desiredRightDockWidth
    readonly property real editRightDockHeight: editor.desiredRightDockHeight
    DashboardContent {
        id: content
        anchors.fill: parent
        embeddedSurface: true
        warmContent: root.participant?.warmContent ?? false
        presentationActive: root.participant ? Boolean(root.participant.open || root.participant.visualResident) : true
        screenWidth: root.participant?.width ?? 1920
        screenHeight: root.participant?.height ?? 1080
    }
    AbyssDashboardEditPopup {
        id: editor
        body: root.participant
        canvasController: content.canvasController
        tabController: content
    }
}
