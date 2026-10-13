import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.dashboard
import qs.modules.abyss.looks

// Reparent only the controls into the existing output field; the Dashboard
// canvas retains its full dimensions and object identity throughout editing.
Item {
    id: root
    required property var body
    required property var canvasController
    parent: body?.parent ?? null
    objectName: "abyssDashboardEditPopup"
    z: 90
    readonly property real desiredHeight: toolbar.implicitHeight
    readonly property bool editing: canvasController?.editMode ?? false
    readonly property var contentRect: body?.targetRecord?.content
    readonly property bool revealRequested: editing
        && (body?.presented ?? false) && (body?.progress ?? 0)>.99
    property real revealProgress: revealRequested ? 1 : 0
    readonly property real targetWidth: Math.min(toolbar.implicitWidth,
        Math.max(1, contentRect?.width ?? 1), Math.max(1, (parent?.width ?? 1)-24))
    readonly property rect targetRect: Qt.rect(
        Math.max(12, Math.min((parent?.width ?? 0)-targetWidth-12,
            (contentRect?.x ?? 0)+((contentRect?.width ?? 0)-targetWidth)/2)),
        Math.max(8, (contentRect?.y ?? 0)-desiredHeight-(body?.padding ?? 14)+6),
        targetWidth, desiredHeight)
    // Exiting edit mode releases the body's extra top clearance. Keep the last
    // toolbar footprint while retracting instead of snapping to that new layout.
    property var retainedRect: null
    readonly property rect presentationRect: revealRequested
        ? targetRect : (retainedRect ?? targetRect)
    onTargetRectChanged: if (canvasController?.editMode && revealRequested)
        retainedRect = targetRect
    onRevealRequestedChanged: if (revealRequested) retainedRect = targetRect
    x: presentationRect.x
    y: presentationRect.y
    width: presentationRect.width
    height: presentationRect.height
    readonly property real slideOffset: height*(1-revealProgress)
    readonly property real revealedHeight: height*revealProgress
    visible: revealProgress > 0
    enabled: revealRequested && visible && (body?.acceptsInput ?? false)
    // The toolbar sits above the Dashboard body; the body's pointer mask
    // never covers it. Publish its own native Region to the Abyss field.
    readonly property rect toolbarInputBounds: root.enabled
        ? Qt.rect(root.x, root.y + root.slideOffset,
            root.width, root.revealedHeight)
        : Qt.rect(0, 0, 0, 0)
    readonly property Region toolbarInputRegion: Region {
        x: Math.floor(root.toolbarInputBounds.x)
        y: Math.floor(root.toolbarInputBounds.y)
        width: root.toolbarInputBounds.width > 0
            ? Math.ceil(root.toolbarInputBounds.x + root.toolbarInputBounds.width) - x : 0
        height: root.toolbarInputBounds.height > 0
            ? Math.ceil(root.toolbarInputBounds.y + root.toolbarInputBounds.height) - y : 0
    }
    clip: true
    Behavior on revealProgress {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: SurfaceMotion.duration
            easing.type: SurfaceMotion.easingType
        }
    }
    AbyssParticipant {
        identity: (root.body?.identity ?? "dashboard")+"Editor"
        controller: root.body?.controller ?? null
        geometry: root.visible ? ({edge:root.body.edge,
            surface:{x:root.x-8,y:root.y+root.slideOffset-8,
                width:root.width+16,height:root.revealedHeight+22},
            content:{x:root.x,y:root.y+root.slideOffset,
                width:root.width,height:root.revealedHeight},
            along:root.x,span:root.width,depth:root.revealedHeight,
            progress:root.revealProgress}) : null
        surfaceSettled: root.revealRequested && root.revealProgress === 1
        inputBounds: root.toolbarInputBounds
        nativeInputRegion: root.toolbarInputRegion
    }
    // Editing consumes the first Escape just like clicking Cancel. Leave the
    // second Escape to the owning Dashboard surface's normal close shortcut.
    Shortcut {
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        // The toolbar is a sibling of the body after reparenting. Its focused
        // buttons do not bubble Escape through AbyssBodyHost, so this shortcut
        // covers that separate focus tree from the start of Edit Mode (not just
        // after the opening animation has reached 99%).
        enabled: root.editing && (root.body?.open ?? false)
        onActivated: {
            if (!(root.canvasController?.editMode ?? false))
                return
            const dashboard = root.body?.contentItem?.item
            if (dashboard?.handleEscape?.()) {
                // Once the toolbar hides, give focus back to the Dashboard
                // body so a second Escape follows its normal close path.
                root.body?.forceActiveFocus()
            }
        }
    }
    DashboardEditToolbar {
        id: toolbar
        width: root.width
        height: root.height
        y: root.slideOffset
        visible: root.visible
        canvasController: root.canvasController
        embeddedSurface: true
    }
}
