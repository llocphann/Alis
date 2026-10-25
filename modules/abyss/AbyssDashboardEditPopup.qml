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
    property var tabController: null
    parent: body?.parent ?? null
    objectName: "abyssDashboardEditPopup"
    z: 90
    readonly property real desiredHeight: toolbar.implicitHeight
    readonly property bool editing: canvasController?.editMode ?? false
    readonly property bool naming: tabController?.tabNamingActive ?? false
    readonly property bool controlsVisible: root.editing || root.naming
    readonly property var contentRect: body?.targetRecord?.content
    readonly property bool revealRequested: controlsVisible
        && (body?.presented ?? false) && (body?.progress ?? 0)>.99
    property real revealProgress: revealRequested ? 1 : 0
    readonly property real targetWidth: Math.min(toolbar.implicitWidth,
        (contentRect?.width ?? 0) > 0 ? contentRect.width : toolbar.implicitWidth,
        (parent?.width ?? 0) > 24 ? parent.width - 24 : toolbar.implicitWidth)
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
    function rememberRequestedRect(): void {
        // The body can release its clearance before controlsVisible and
        // revealRequested reevaluate. Read the editor's semantic state now,
        // so that binding order cannot overwrite the closing snapshot.
        const requested = (root.canvasController?.editMode ?? false)
            || (root.tabController?.tabNamingActive ?? false)
        if (requested && root.revealRequested)
            root.retainedRect = root.targetRect
    }
    onTargetRectChanged: root.rememberRequestedRect()
    onRevealRequestedChanged: if (revealRequested) root.rememberRequestedRect()
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
    // Escape belongs to the Perimeter PanelWindow, never this reparented
    // editor (delegates onActivated: root.canvasController.cancelEditMode()).
    // Having both WindowShortcuts for Overview makes them ambiguous.
    DashboardEditToolbar {
        id: toolbar
        width: root.width
        height: root.height
        y: root.slideOffset
        visible: root.visible
        canvasController: root.canvasController
        tabController: root.tabController
        embeddedSurface: true
    }
}
