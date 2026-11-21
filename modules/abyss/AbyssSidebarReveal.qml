import QtQuick

// Output-local hover lease. Only a hover-opened sidebar closes on pointer exit;
// explicit IPC/shortcut opens retain their original lifetime.
Item {
    id: root
    property var controller: null
    property string surfaceId: ""
    property bool available: true
    property bool openingAllowed: true
    property bool closeBlocked: false
    property bool open: false
    property Item bodyItem: null
    property int revealDelay: 80
    property int closeDelay: 240
    property bool edgeHovered: Boolean(edgeHover?.hovered)
    property bool bodyHovered: Boolean(bodyHover?.hovered)
    property bool peerHovered: false
    readonly property bool directHovered: edgeHovered || bodyHovered
    readonly property bool hovered: edgeHovered || bodyHovered || (open && peerHovered)
    property bool ownedOpen: false
    property bool transientOpen: false
    signal revealRequested()
    signal hideRequested()
    visible: available
    function release(): void {
        reveal.stop();hide.stop()
        if (root.controller && root.surfaceId.length > 0)
            root.controller.cancelHoverSurfaceClose(root.surfaceId)
        if (ownedOpen || transientOpen) {
            ownedOpen=false
            root.hideRequested()
        }
    }
    function _notifyFifoHover(): void {
        if (!root.controller || root.surfaceId.length === 0) return
        const autoClosable = root.ownedOpen || root.transientOpen || !root.open
        if (root.directHovered || (root.open && root.hovered)) {
            root.controller.noteHoverSurfaceActive(root.surfaceId, autoClosable)
        } else if (!root.hovered) {
            root.controller.noteHoverSurfaceLeave(root.surfaceId, root.ownedOpen || root.transientOpen)
        }
    }
    function updateHover(): void {
        if (!available) { release();return }
        if (hovered) {
            hide.stop()
            if (root.controller && root.surfaceId.length > 0)
                root.controller.cancelHoverSurfaceClose(root.surfaceId)
            if (!open && openingAllowed) reveal.restart()
        } else {
            reveal.stop()
            if ((ownedOpen || transientOpen) && open) hide.restart()
        }
        root._notifyFifoHover()
    }
    onDirectHoveredChanged: root._notifyFifoHover()
    onHoveredChanged: updateHover()
    onAvailableChanged: updateHover()
    onOpeningAllowedChanged: updateHover()
    onCloseBlockedChanged: if (!closeBlocked) updateHover()
    onTransientOpenChanged: updateHover()
    onOpenChanged: {
        if (!open) {
            if (root.controller && root.surfaceId.length > 0)
                root.controller.clearHoverSurface(root.surfaceId)
            if (!available) release()
            else { ownedOpen=false;reveal.stop();hide.stop() }
        } else if (root.directHovered) {
            root._notifyFifoHover()
        }
    }
    HoverHandler { id: edgeHover; enabled: root.available }
    HoverHandler {
        id: bodyHover
        parent: root.bodyItem
        enabled: root.available && root.open && root.bodyItem !== null
    }
    Timer {
        id: reveal;interval: root.revealDelay
        onTriggered: if (root.available && root.openingAllowed && root.edgeHovered && !root.open) {
            root.ownedOpen=true
            root._notifyFifoHover()
            root.revealRequested()
        }
    }
    Timer {
        id: hide;interval: root.closeDelay
        onTriggered: {
            if (root.closeBlocked) { restart();return }
            if ((root.ownedOpen || root.transientOpen) && !root.hovered) {
                if (root.controller && root.surfaceId.length > 0) {
                    root.controller.requestHoverSurfaceClose(root.surfaceId, () => {
                        if (root.closeBlocked) {
                            root.controller.cancelHoverSurfaceClose(root.surfaceId)
                            hide.restart()
                            return
                        }
                        if ((root.ownedOpen || root.transientOpen) && !root.hovered)
                            root.release()
                    })
                } else {
                    root.release()
                }
            }
        }
    }
}
