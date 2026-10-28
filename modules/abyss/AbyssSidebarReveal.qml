import QtQuick

// Output-local hover lease. Only a hover-opened sidebar closes on pointer exit;
// explicit IPC/shortcut opens retain their original lifetime.
Item {
    id: root
    property bool available: true
    property bool openingAllowed: true
    property bool closeBlocked: false
    property bool open: false
    property Item bodyItem: null
    property int revealDelay: 80
    property int closeDelay: 240
    property bool edgeHovered: edgeHover.hovered
    property bool bodyHovered: bodyHover.hovered
    property bool peerHovered: false
    readonly property bool hovered: edgeHovered || bodyHovered || (open && peerHovered)
    property bool ownedOpen: false
    property bool transientOpen: false
    signal revealRequested()
    signal hideRequested()
    visible: available
    function release(): void {
        reveal.stop();hide.stop()
        if (ownedOpen || transientOpen) {
            ownedOpen=false
            root.hideRequested()
        }
    }
    function updateHover(): void {
        if (!available) { release();return }
        if (hovered) {
            hide.stop()
            if (!open && openingAllowed) reveal.restart()
        } else {
            reveal.stop()
            if ((ownedOpen || transientOpen) && open) hide.restart()
        }
    }
    onHoveredChanged: updateHover()
    onAvailableChanged: updateHover()
    onOpeningAllowedChanged: updateHover()
    onCloseBlockedChanged: if (!closeBlocked) updateHover()
    onTransientOpenChanged: updateHover()
    onOpenChanged: {
        if (!open) {
            if (!available) release()
            else { ownedOpen=false;reveal.stop();hide.stop() }
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
            root.ownedOpen=true;root.revealRequested()
        }
    }
    Timer {
        id: hide;interval: root.closeDelay
        onTriggered: {
            if (root.closeBlocked) { restart();return }
            if ((root.ownedOpen || root.transientOpen) && !root.hovered) root.release()
        }
    }
}
