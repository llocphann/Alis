import QtQuick
import QtQuick.Window
import Quickshell
import qs.modules.common
import qs.modules.dashboard
import qs.modules.abyss.looks

// Reparent only the customization dock into the output field connected to the
// physical bottom Screen Edge; the Dashboard canvas retains its object identity.
Item {
    id: root
    required property var body
    required property var canvasController
    property var tabController: null
    readonly property Item stageDockParent: body?.hostWindow?.stageDashboardDockHost ?? null
    readonly property Item stageLeftHost: stageHosted ? (body?.hostWindow?.stageLeftDashboardDockHost ?? null) : null
    readonly property Item stageRightHost: stageHosted ? (body?.hostWindow?.stageRightDashboardDockHost ?? null) : null
    readonly property bool stageHosted: stageDockParent !== null
    parent: stageHosted ? stageDockParent : (body?.parent ?? null)
    objectName: "abyssDashboardEditPopup"
    z: 90

    readonly property real desiredWidth: Math.min(
        2400,
        Math.max(680, Math.ceil(toolbar.implicitWidth)))
    readonly property real desiredHeight: toolbar.implicitHeight
    readonly property real desiredLeftDockWidth: toolbar.desiredLeftDockWidth
    readonly property real desiredLeftDockHeight: toolbar.desiredLeftDockHeight
    readonly property real desiredRightDockWidth: toolbar.desiredRightDockWidth
    readonly property real desiredRightDockHeight: toolbar.desiredRightDockHeight
    readonly property bool editing: canvasController?.editMode ?? false
    readonly property bool naming: tabController?.tabNamingActive ?? false
    readonly property bool controlsVisible: root.editing || root.naming
    readonly property var contentRect: body?.targetRecord?.content
    readonly property bool revealRequested: controlsVisible
        && (stageHosted ? (body?.open ?? false)
            : ((body?.presented ?? false) && (body?.progress ?? 0) > .99))
    property real revealProgress: revealRequested ? 1 : 0

    readonly property real maxParentWidth: (parent?.width ?? 0) > 24
        ? parent.width - 24 : toolbar.implicitWidth
    readonly property real preferredMaxWidth: (contentRect?.width ?? 0) > 0
        ? Math.max(Math.min(maxParentWidth, 880), contentRect.width)
        : maxParentWidth
    readonly property real targetWidth: Math.min(
        toolbar.implicitWidth, preferredMaxWidth, maxParentWidth)
    readonly property real targetX: Math.max(12, Math.min(
        (parent?.width ?? 0) - targetWidth - 12,
        (contentRect?.width ?? 0) > 0
            ? (contentRect.x + (contentRect.width - targetWidth) / 2)
            : (((parent?.width ?? 0) - targetWidth) / 2)))
    readonly property real bottomInset: {
        const win = root.QsWindow?.window
        if (win && typeof win.bodyInsets === "function") {
            const ins = win.bodyInsets("bottom", root.targetX, root.targetWidth)
            if (Number.isFinite(Number(ins?.bottom)))
                return Math.max(0, Number(ins.bottom))
        }
        return Math.max(0, Number(root.body?.controller?.edgeInsets?.bottom
            ?? root.body?.edgeInsets?.bottom ?? 0))
    }
    readonly property real targetY: Math.max(8,
        (parent?.height ?? 0) - bottomInset - desiredHeight)
    readonly property rect targetRect: Qt.rect(
        targetX, targetY, targetWidth, desiredHeight)

    // Exiting edit mode releases the body's bottom clearance. Keep the last
    // dock footprint while retracting downward instead of snapping early.
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

    x: stageHosted ? 0 : presentationRect.x
    y: stageHosted ? 0 : presentationRect.y
    width: stageHosted ? (stageDockParent?.width ?? toolbar.implicitWidth) : presentationRect.width
    height: stageHosted ? (stageDockParent?.height ?? desiredHeight) : presentationRect.height
    readonly property real slideOffset: stageHosted ? 0 : height * (1 - revealProgress)
    readonly property real revealedHeight: stageHosted ? height : height * revealProgress
    visible: stageHosted
        ? (revealRequested || (stageDockParent?.visible ?? false))
        : (revealProgress > 0)
    enabled: revealRequested && visible && (body?.acceptsInput ?? false)

    // The dock sits at the bottom Screen Edge outside the Dashboard body's mask.
    // Publish its own native Region to the Abyss field when not stage-hosted.
    readonly property rect toolbarInputBounds: root.enabled && !root.stageHosted
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
        identity: (root.body?.identity ?? "dashboard") + "Editor"
        controller: root.body?.controller ?? null
        geometry: (!root.stageHosted && root.visible) ? ({
            edge: "bottom",
            surface: {
                x: root.x - 8,
                y: root.y + root.slideOffset - 8,
                width: root.width + 16,
                height: root.revealedHeight + root.bottomInset + 58
            },
            content: {
                x: root.x,
                y: root.y + root.slideOffset,
                width: root.width,
                height: root.revealedHeight
            },
            along: root.x,
            span: root.width,
            depth: root.revealedHeight,
            progress: root.revealProgress
        }) : null
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
        splitSideDocks: root.stageLeftHost !== null && root.stageRightHost !== null
        leftDockParent: root.stageLeftHost
        rightDockParent: root.stageRightHost
        embeddedSurface: true
        compactHeight: (root.body?.height ?? root.QsWindow?.window?.height ?? 1080) < 720
    }
}
