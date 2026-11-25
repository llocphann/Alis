pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.screenCorners
import qs.modules.notificationCenter
import "looks/AbyssLayout.js" as ModuleLayout

// Mature corner content joins the existing StyledPopup/field path.
Item {
    id: root
    required property var controller
    required property string outputName
    property bool presentationEnabled: true
    property bool blocked: false
    property real attachmentThickness: 16
    property var edgeInsets: ({top: 16, right: 16, bottom: 16, left: 16})
    property string quickNotesEditorOutput: ""
    signal quickNotesEditorLeaseChanged(string outputName, bool focused)
    property alias notesAnchor: notesAnchor
    property alias centerAnchor: centerAnchor
    property alias notesPopup: notesPopup
    property alias centerPopup: centerPopup
    property alias leftSidebarCorner: leftSidebarCorner
    property alias rightSidebarCorner: rightSidebarCorner
    readonly property var sidebarRegions: [leftSidebarCorner.inputRegion,rightSidebarCorner.inputRegion]
    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(Quickshell.screens.find(screen=>screen.name===outputName))

    // Match the mature ScreenCorners ownership rule: Niri's configured built-in
    // Overview hot corner gets the physical corner first. Leaving our input
    // region empty is important because a layer-shell MouseArea there can keep
    // the compositor from ever seeing the pointer reach its hot corner.
    function niriOverviewOwnsCorner(cornerName: string): bool {
        return CompositorService.isNiri
            && NiriService.isOverviewHotCornerActive(root.outputName, cornerName)
    }

    // This is the ACTUAL Abyss corner owner. ScreenCorners.qml belongs to
    // ii/Waffle and never owns the Abyss perimeter's hit masks. A saved
    // Module Icon mode must revoke this corner's MouseArea and popup; selecting
    // Edgebar Hover must restore it even if the retired Panels Quick Notes
    // toggle left quickNotes.enable=false or monitorMode=primary.
    readonly property bool notesEdgebarMode:
        ModuleLayout.edgebarOwnsCornerHover(
            Config.options?.abyss?.modules,
            Config.options?.panelFamily ?? "ii","notesTimers")
    readonly property bool centerEdgebarMode:
        ModuleLayout.edgebarOwnsCornerHover(
            Config.options?.abyss?.modules,
            Config.options?.panelFamily ?? "ii","notificationActivity")
    readonly property var notesPlacement: ModuleLayout.edgebarAnchorPlacement(
        Config.options?.abyss?.modules, root.outputName, "notesTimers",
        root.width, root.height, Config.options?.quickNotes?.cornerSize ?? 14)
    readonly property var centerPlacement: ModuleLayout.edgebarAnchorPlacement(
        Config.options?.abyss?.modules, root.outputName, "notificationActivity",
        root.width, root.height, Config.options?.notificationCenter?.cornerSize ?? 14)
    readonly property bool notesAvailable: presentationEnabled && !blocked
        && notesEdgebarMode
        && (quickNotesEditorOutput.length === 0
            || quickNotesEditorOutput === outputName)
        && (notesPlacement.niriCorner === "" || !root.niriOverviewOwnsCorner(notesPlacement.niriCorner))
    readonly property bool centerAvailable: presentationEnabled && !blocked
        && centerEdgebarMode
        // Quick Notes may own the keyboard while Notification Center remains a
        // pointer-only surface. Do not hide the whole popup just because the
        // notes editor has focus; keyboard arbitration is handled below.
        && (centerPlacement.niriCorner === "" || !root.niriOverviewOwnsCorner(centerPlacement.niriCorner))
    function targets(list): bool {
        return !list.length || list.includes(outputName)
            || !Quickshell.screens.some(screen=>list.includes(screen.name))
    }
    component Anchor: Item {
        id: hit
        required property string kind
        required property var placementInfo
        property bool allowed: true
        property int dwell: 220
        property bool dwellReady: false
        readonly property bool pointerHovered: allowed && mouse.containsMouse
        property bool containsMouse: allowed && dwellReady && mouse.containsMouse
        readonly property var liquidController: root.controller
        readonly property bool edgebarCornerAnchor: true
        readonly property string popupAttachmentEdge: String(placementInfo?.edge ?? "bottom")
        readonly property string popupTangentEdge: String(placementInfo?.tangentEdge ?? "")
        readonly property string moduleKind: kind === "quickNotes" ? "notesTimers" : "notificationActivity"
        readonly property string popupJoinedEdge: String(placementInfo?.joinEdge ?? "")
        x: Math.round(placementInfo?.x ?? 0)
        y: Math.round(placementInfo?.y ?? 0)
        width: Math.max(8, Math.round(placementInfo?.width ?? 14))
        height: Math.max(8, Math.round(placementInfo?.height ?? 14))
        visible: allowed
        onAllowedChanged: if (!allowed) { gate.stop();dwellReady=false }
        MouseArea {
            id: mouse;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton
            onEntered:gate.restart()
            onExited: { gate.stop();hit.dwellReady=false }
            onClicked:hit.dwellReady=true
        }
        Timer { id:gate;interval:hit.dwell;onTriggered:if(mouse.containsMouse) hit.dwellReady=true }
    }
    readonly property bool sameCornerOverlap: root.notesAvailable
        && root.centerAvailable
        && String(root.notesPlacement?.corner ?? "") !== ""
        && root.notesPlacement?.corner === root.centerPlacement?.corner
    readonly property var effectiveCenterPlacement: {
        var base = root.centerPlacement
        if (!root.sameCornerOverlap || !base) return base
        var step = Math.round((root.notesPlacement?.width ?? 14) + 4)
        var onRight = String(base.edge ?? "") === "right"
            || String(base.corner ?? "").endsWith("Right")
        var xPos = onRight
            ? Math.max(0, Math.round(base.x) - step)
            : Math.min(Math.max(0, root.width - Math.round(base.width ?? 14)), Math.round(base.x) + step)
        return Object.assign({}, base, { x: xPos })
    }
    Anchor {
        id: notesAnchor
        kind:"quickNotes";allowed:root.notesAvailable;placementInfo:root.notesPlacement
        dwell:Config.options?.quickNotes?.hoverDelayMs ?? 220
    }
    QuickNotesPopup {
        id: notesPopup
        anchorItem:notesAnchor
        cornerAttachmentEdge:notesAnchor.popupAttachmentEdge
        cornerTangentEdge:notesAnchor.popupTangentEdge
        cornerAttachmentThickness:Math.max(1, Number(root.edgeInsets?.[notesAnchor.popupAttachmentEdge] ?? root.attachmentThickness))
        hoverAllowed:root.notesAvailable
        hoverActivates:root.notesAvailable
        externallyBlocked:root.blocked
        onEditorFocusedChanged:
            root.quickNotesEditorLeaseChanged(root.outputName,editorFocused)
    }
    Anchor {
        id: centerAnchor
        kind:"notificationCenter";allowed:root.centerAvailable;placementInfo:root.effectiveCenterPlacement
        dwell:Config.options?.notificationCenter?.hoverDelayMs ?? 220
    }
    NotificationCenterPopup {
        id: centerPopup
        anchorItem:centerAnchor;outputName:root.outputName
        cornerAttachmentEdge:centerAnchor.popupAttachmentEdge
        cornerTangentEdge:centerAnchor.popupTangentEdge
        cornerAttachmentThickness:Math.max(1, Number(root.edgeInsets?.[centerAnchor.popupAttachmentEdge] ?? root.attachmentThickness))
        hoverAllowed:root.centerAvailable
        keyboardAllowed:root.quickNotesEditorOutput.length === 0
    }
    readonly property bool notesOpen: Boolean(notesPopup.presentationActive)
    readonly property bool centerOpen: Boolean(centerPopup.presentationActive)
    readonly property bool notesDirectInteracting: Boolean(notesAnchor.pointerHovered
        || notesPopup._anchorHover?.hovered
        || notesPopup._bodyHovered
        || notesPopup.entryBridgeHeld
        || notesPopup.popupPinned
        || notesPopup.editorFocused)
    readonly property bool centerDirectInteracting: Boolean(centerAnchor.pointerHovered
        || centerPopup._anchorHovered
        || centerPopup._bodyHovered
        || centerPopup.entryBridgeHeld
        || centerPopup.exitGraceHeld)
    readonly property bool notesOwnerRevoked: !presentationEnabled
        || !notesEdgebarMode
        || (quickNotesEditorOutput.length > 0
            && quickNotesEditorOutput !== outputName)
        || (notesPlacement.niriCorner !== "" && root.niriOverviewOwnsCorner(notesPlacement.niriCorner))
    onNotesOwnerRevokedChanged: {
        if (notesOwnerRevoked) {
            notesPopup.clearSuspendedSession()
            notesPopup.popupPinned = false
            if (notesPopup.presentationActive)
                notesPopup.dismissPresentation()
        }
    }
    onNotesAvailableChanged: {
        if (!notesAvailable && notesPopup.presentationActive) {
            if (root.blocked && !root.notesOwnerRevoked
                    && (notesPopup.popupPinned || notesPopup.editorFocused || notesPopup.todoDialogOpen)) {
                // Temporarily blocked by a heavy overlay/modal: suspend active
                // editing, To-do input, or pinned QuickNotes so they auto-restore cleanly.
                notesPopup.suspendForBlock()
            } else {
                // Hover-only close or ownership loss: drop any local pin and dismiss cleanly.
                notesPopup.clearSuspendedSession()
                notesPopup.popupPinned = false
                notesPopup.dismissPresentation()
            }
        }
    }
    onCenterAvailableChanged: {
        if (!centerAvailable && centerPopup.presentationActive) {
            if (!centerPopup.explicitForThisOutput && !centerPopup.keyboardInteraction)
                centerPopup.dismissPresentation()
        }
    }
    // The same public cornerOpen controls as the mature shell. Notes and the
    // notification center retain priority at the bottom corners.
    component SidebarCorner: Item {
        id: corner
        required property bool leftSide
        readonly property var options: Config.options?.sidebar?.cornerOpen ?? ({})
        readonly property bool atBottom: options.bottom ?? false
        readonly property string cornerName: atBottom
            ? (leftSide ? "bottomLeft" : "bottomRight")
            : (leftSide ? "topLeft" : "topRight")
        readonly property bool available: root.presentationEnabled && !root.blocked
            && (options.enable ?? false)
            && (Config.options?.enabledPanels ?? []).includes(leftSide ? "abyssSidebarLeft" : "abyssSidebarRight")
            && root.targets(Config.options?.sidebar?.screenList ?? [])
            && !root.niriOverviewOwnsCorner(corner.cornerName)
            && !(root.notesAvailable && root.notesPlacement.niriCorner === corner.cornerName)
            && !(root.centerAvailable && root.centerPlacement.niriCorner === corner.cornerName)
        readonly property Region inputRegion: Region { x:corner.x;y:corner.y;width:corner.available ? corner.width : 0;height:corner.height }
        width: Math.max(2,Math.min(root.width/2,options.cornerRegionWidth ?? 250))
        height: Math.max(1,Math.min(100,options.cornerRegionHeight ?? 5))
        x: leftSide ? 0 : root.width-width
        y: atBottom ? root.height-height : 0
        visible: available
        function activate(transient = false): void {
            if (!available) return
            if (transient) {
                if (leftSide) GlobalStates.openSidebarLeft(root.outputName, true)
                else GlobalStates.openSidebarRight(root.outputName, true)
                return
            }
            if (leftSide) GlobalStates.toggleSidebarLeft(root.outputName)
            else GlobalStates.toggleSidebarRight(root.outputName)
        }
        FocusedScrollMouseArea {
            anchors.fill:parent;hoverEnabled:true
            // Right corner is click-only; hover and pointer movement must not open the system sidebar.
            onEntered: if((corner.leftSide || corner.atBottom) && (corner.options.clickless ?? false)) corner.activate(true)
            onPressed: if((!corner.leftSide && !corner.atBottom) || !(corner.options.clickless ?? false)) corner.activate(false)
            onPositionChanged: {
                if((!corner.leftSide && !corner.atBottom) || (corner.options.clickless ?? false) || !(corner.options.clicklessCornerEnd ?? false)) return
                const offset=corner.options.clicklessCornerVerticalOffset ?? 1
                const end=corner.leftSide ? mouseX<=2 : mouseX>=width-2
                if(end && (corner.atBottom ? mouseY<height-offset : mouseY>offset)) corner.activate()
            }
            onScrollDown: {
                if(!(corner.options.valueScroll ?? false)) return
                if(corner.leftSide && root.brightnessMonitor) root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness-.05)
                else if(!corner.leftSide) Audio.decrementVolume()
            }
            onScrollUp: {
                if(!(corner.options.valueScroll ?? false)) return
                if(corner.leftSide && root.brightnessMonitor) root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness+.05)
                else if(!corner.leftSide) Audio.incrementVolume()
            }
            onMovedAway: {
                if(!(corner.options.valueScroll ?? false)) return
                if(corner.leftSide) GlobalStates.osdBrightnessOpen=false
                else GlobalStates.osdVolumeOpen=false
            }
        }
        Rectangle { anchors.fill:parent;color:Appearance.colors.colPrimary;visible:corner.options.visualize ?? false }
    }
    SidebarCorner { id:leftSidebarCorner;leftSide:true }
    SidebarCorner { id:rightSidebarCorner;leftSide:false }
}
