import QtQuick
import qs.modules.dashboard
import qs.modules.abyss

Item {
    id: root
    property var participant: null
    readonly property bool editMode: content.editMode
    readonly property bool tabNamingActive: content.tabNamingActive
    function handleEscape(): bool {
        return content.handleEscape()
    }
    readonly property real topControlReserve: editor.desiredHeight+16
    DashboardContent {
        id: content
        anchors.fill: parent
        embeddedSurface: true
        warmContent: root.participant?.warmContent ?? false
        presentationActive: root.participant?.open ?? true
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
