pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.dock
import "../looks/AbyssWave.js" as Wave

// Keep the existing app model, menus and launch behavior.
// Only the surrounding shell is supplied by the output's field.
Item {
    id: root
    property string outputName: ""
    property string edge: "bottom"
    property var participant: null
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real desiredSpan: (vertical ? content.implicitHeight : content.implicitWidth) + 24
    readonly property bool requestDockShow: apps.requestDockShow
        || (GlobalStates.abyssPopupKind === "dockAppMenu"
            && GlobalStates.abyssPopupTargetOutput === root.outputName)
    readonly property var appContent: apps
    function openAppMenu(model, localX, localY, ownerId): void {
        if (!root.participant)
            return
        const point = apps.mapToItem(root.participant, localX, localY)
        GlobalStates.abyssDockMenuModel = model ?? []
        GlobalStates.abyssDockMenuOwnerId = String(ownerId ?? "")
        GlobalStates.abyssDockMenuTriggerHovered = true
        GlobalStates.abyssPopupTargetOutput = root.outputName
        GlobalStates.abyssPopupEdge = root.edge
        GlobalStates.abyssPopupAlong = root.vertical ? point.y : point.x
        GlobalStates.mediaControlsOpen = false
        GlobalStates.abyssPopupKind = "dockAppMenu"
    }
    function closeAppMenu(): void {
        if (GlobalStates.abyssPopupKind !== "dockAppMenu"
                || GlobalStates.abyssPopupTargetOutput !== root.outputName)
            return
        GlobalStates.abyssDockMenuOwnerId = ""
        GlobalStates.abyssDockMenuTriggerHovered = false
        GlobalStates.abyssPopupKind = ""
    }
    function updateAppMenuHover(ownerId, hovered): void {
        if (String(ownerId ?? "") !== GlobalStates.abyssDockMenuOwnerId)
            return
        GlobalStates.abyssDockMenuTriggerHovered = hovered
    }
    onEdgeChanged: root.closeAppMenu()
    Component.onDestruction: root.closeAppMenu()
    function react(position, strength): void {
        if (!participant?.controller) return
        const point = root.mapToItem(participant, position.x, position.y)
        participant.controller.impulse(edge, vertical ? point.y : point.x, 50,
            strength * Wave.bodyStrength(Config.options?.abyss?.waves), 1, "module")
    }
    HoverHandler {
        onHoveredChanged: root.react(point.position, hovered ? .4 : -.15)
    }
    PointHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onActiveChanged: root.react(point.position, active ? 1 : -.3)
    }
    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        rowSpacing: 2; columnSpacing: 2
        DockApps {
            id: apps
            residentDelegates: true
            vertical: root.vertical
            abyssMenuPresenter: (model, x, y, ownerId) =>
                root.openAppMenu(model, x, y, ownerId)
            abyssMenuHoverPresenter: (ownerId, hovered) =>
                root.updateAppMenuHover(ownerId, hovered)
            abyssMenuClosePresenter: () =>
                root.closeAppMenu()
            dockPosition: root.edge
            parentWindow: root.QsWindow.window
            Layout.preferredHeight: root.vertical ? implicitHeight : 50
            Layout.preferredWidth: root.vertical ? 50 : implicitWidth
        }
        DockButton {
            visible: Config.options?.dock?.showDashboardButton ?? true
            vertical: root.vertical
            onClicked: GlobalStates.toggleOverview(root.outputName)
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "apps"
                iconSize: 25
                color: Appearance.colors.colOnLayer0
            }
        }
    }
}
