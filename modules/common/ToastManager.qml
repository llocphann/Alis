import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.perimeter
import qs.services

Scope {
    id: root
    
    // Toast queue
    property var toasts: []
    property int maxToasts: 5
    property int toastSpacing: 8
    readonly property bool suppressOnScreenToasts: (GameMode?.active ?? false) || (GameMode?.hasAnyFullscreenWindow ?? false)
    readonly property real screenEdgeThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
    readonly property bool topBarOwnsEdge:
        (Config.options?.panelFamily ?? "ii") === "ii"
        && !(Config.options?.bar?.vertical ?? false)
        && !(Config.options?.bar?.bottom ?? false)
        && GlobalStates.barOpen
        && !(Config.options?.bar?.autoHide?.enable ?? false)
        && (Config.options?.enabledPanels ?? []).includes("iiBar")
    readonly property real topOwnerThickness: topBarOwnsEdge
        ? Appearance.sizes.barHeight : screenEdgeThickness
    readonly property bool edgeShadowEnabled:
        Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
    readonly property real edgeShadowSize: Math.max(0, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
    readonly property real edgeShadowOpacity: Math.max(0, Math.min(1.0,
        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))
    readonly property color edgeShadowColor:
        Qt.alpha(Appearance.m3colors.m3shadow, root.edgeShadowOpacity)
    // When a real top Bar owns the attachment edge, keep the toast's right
    // side free instead of welding it into the physical right Screen Edge.
    // Leave enough room for the Abyss fuse/AA reach so it cannot visually touch
    // that tangent owner. If the Bar is elsewhere, the toast falls back to the
    // top-right Screen Edge corner and intentionally joins the right frame.
    readonly property real topBarFreeRightInset: Math.max(
        PerimeterTokens.abyssFuseDepth + 2,
        root.edgeShadowEnabled ? root.edgeShadowSize + 2 : 0)
    readonly property real edgeDecorationMargin: Math.max(
        8,
        PerimeterTokens.abyssFuseDepth,
        root.edgeShadowEnabled ? root.edgeShadowSize + 2 : 0)
    readonly property real toastBodyPadding: 8
    readonly property bool useAbyssPresentation:
        (Config.options?.panelFamily ?? "ii") === "abyss"
        && (Config.options?.enabledPanels ?? []).includes("abyssPerimeter")
    property string presentationOutputName: ""

    Component.onCompleted: GlobalStates.toastManager = root
    Component.onDestruction: {
        if (GlobalStates.toastManager === root)
            GlobalStates.toastManager = null
    }
    onUseAbyssPresentationChanged: {
        if (root.useAbyssPresentation) {
            popupLoader.active = false
            if (root.toasts.length > 0 && !root.presentationOutputName)
                root.presentationOutputName = GlobalStates.resolveOutputName("", [])
        } else if (root.toasts.length > 0) {
            popupLoader.loading = true
        }
    }

    // Match StyledPopup's immutable ii motion contract: the whole connected
    // surface slides under its owner. Individual toast content never fades,
    // scales or morphs independently.
    property real surfaceOffsetScale: 1
    readonly property real surfaceRevealProgress: 1 - root.surfaceOffsetScale
    property var _pendingSurfaceRemovalId: null

    Behavior on surfaceOffsetScale {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: SurfaceMotion.duration
            easing.type: SurfaceMotion.easingType
        }
    }

    Timer {
        id: surfaceRetractTimer
        interval: Math.max(1, SurfaceMotion.duration + 16)
        repeat: false
        onTriggered: {
            const pendingId = root._pendingSurfaceRemovalId
            root._pendingSurfaceRemovalId = null
            if (pendingId !== null && root.surfaceOffsetScale >= 0.999)
                root.removeToast(pendingId)
        }
    }
    
    // Unified reload tracking - only show ONE toast per reload event
    property real _lastReloadToastTime: 0
    property string _pendingReloadSource: ""  // "quickshell" or ""
    readonly property int _reloadDebounceMs: 800   // Wait this long to coalesce events
    readonly property int _reloadCooldownMs: 2500  // Minimum time between reload toasts
    
    // Check if reload toasts should be shown
    function shouldShowReloadToast(): bool {
        if (Config.isSettingsProcess) return false
        if (!(Config.options?.reloadToasts?.enable ?? true)) return false
        
        if (GameMode.disableReloadToasts && (GameMode.active || GameMode.hasAnyFullscreenWindow || GameMode.suppressNiriToast)) {
            return false
        }
        
        return true
    }
    
    function _revealSurface(wasEmpty) {
        const reversingRetract = root._pendingSurfaceRemovalId !== null
        surfaceRetractTimer.stop()
        root._pendingSurfaceRemovalId = null

        if (!Appearance.animationsEnabled) {
            root.surfaceOffsetScale = 0
            return
        }

        if (!wasEmpty || reversingRetract) {
            // Reverse naturally from the current slide position if a new toast
            // arrives during retract; do not replay or snap the animation.
            root.surfaceOffsetScale = 0
            return
        }

        root.surfaceOffsetScale = 1
        Qt.callLater(() => {
            if (root.toasts.length > 0)
                root.surfaceOffsetScale = 0
        })
    }

    function addToast(title, message, icon, isError, duration, source, accentColor) {
        // Prevent duplicates: if same source and title already visible, ignore
        if (toasts.some(t => t.source === source && t.title === title)) {
            return
        }

        const wasEmpty = toasts.length === 0
        if (wasEmpty)
            root.presentationOutputName = GlobalStates.resolveOutputName("", [])
        const toast = {
            id: Date.now(),
            title: title,
            message: message || "",
            icon: icon || (isError ? "error" : "check_circle"),
            isError: isError || false,
            duration: duration || (isError ? 6000 : 2000),
            source: source || "system",
            accentColor: accentColor || Appearance.colors.colPrimary
        }

        toasts = [...toasts, toast]

        if (toasts.length > maxToasts) {
            toasts = toasts.slice(-maxToasts)
        }

        if (!root.useAbyssPresentation)
            popupLoader.loading = true
        root._revealSurface(wasEmpty)
    }

    function removeToast(id) {
        toasts = toasts.filter(t => t.id !== id)
        if (toasts.length === 0) {
            root.surfaceOffsetScale = 1
            root.presentationOutputName = ""
            popupLoader.active = false
        }
    }

    function dismissToast(id) {
        if (!toasts.some(t => t.id === id))
            return

        if (toasts.length > 1 || !Appearance.animationsEnabled) {
            root.removeToast(id)
            return
        }

        root._pendingSurfaceRemovalId = id
        root.surfaceOffsetScale = 1
        surfaceRetractTimer.restart()
    }
    
    // Reload success is a transient notification, sharing its placement,
    // output selection, DND, timeout and hover lifetime with ordinary popups.
    // Error toasts retain their copy/dismiss actions in this manager.
    function sendReloadNotification(title, appName, icon): void {
        Quickshell.execDetached([
            "notify-send", "-a", appName, "-i", icon, "-t", "2000",
            "-h", "boolean:transient:true",
            "-h", "boolean:suppress-sound:true", title
        ])
    }

    // Show the single pending reload notification.
    function _showReloadToast() {
        if (!root._pendingReloadSource) return
        if (!root.shouldShowReloadToast()) {
            root._pendingReloadSource = ""
            return
        }
        
        const now = Date.now()
        // Check cooldown
        if (now - root._lastReloadToastTime < root._reloadCooldownMs) {
            root._pendingReloadSource = ""
            return
        }
        
        root._lastReloadToastTime = now
        const source = root._pendingReloadSource
        root._pendingReloadSource = ""

        if (source === "quickshell") {
            root.sendReloadNotification(
                "Quickshell reloaded", "Quickshell", "view-refresh")
        }
    }
    
    // Single debounce timer for all reload events
    Timer {
        id: reloadDebounce
        interval: root._reloadDebounceMs
        onTriggered: root._showReloadToast()
    }
    
    // Quickshell reload signals
    Connections {
        target: Quickshell
        
        function onReloadCompleted() {
            root._pendingReloadSource = "quickshell"
            reloadDebounce.restart()
        }
        
        function onReloadFailed(error) {
            root.addToast(
                "Quickshell reload failed",
                error,
                "error",
                true,
                8000,
                "error",
                Appearance.colors.colError
            )
        }
    }
    
    // Niri config reload signals
    Connections {
        target: NiriService
        
        function onConfigLoadFinished(ok, error) {
            // Successful Niri config reloads are intentionally silent. The
            // maintainer does not want a popup/notification for this routine
            // event; only failures remain actionable.
            if (!ok) {
                root.addToast(
                    "Niri config reload failed",
                    error || "Run 'niri validate' for details",
                    "error",
                    true,
                    8000,
                    "error",
                    Appearance.colors.colError
                )
            }
        }
    }
    
    LazyLoader {
        id: popupLoader
        
        PanelWindow {
            id: popup
            visible: root.toasts.length > 0 && !root.suppressOnScreenToasts
            // Visual-only Overlay: never set exclusiveZone here. Quickshell's
            // exclusiveZone setter switches exclusionMode back to Normal,
            // which made Niri configure this window to the remaining work area
            // instead of the physical output.
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:toast-manager"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            // Mirror BatteryPopup/StyledPopup production geometry. A one-pixel
            // logical anchor at the Bar's top-right edge is enough to make the
            // shared geometry clamp the body to the right Screen Edge while the
            // top owner remains the full Bar (or Screen Edge fallback).
            ConnectedSurfaceGeometry {
                id: toastGeometry
                edge: "top"
                alignment: "end"
                outputRect: Qt.rect(0, 0, popup.width, popup.height)
                anchorRect: Qt.rect(
                    Math.max(0,
                        popup.width
                        - root.screenEdgeThickness
                        - (root.topBarOwnsEdge ? root.topBarFreeRightInset : 0)
                        - 1),
                    0,
                    1,
                    root.topOwnerThickness)
                bodySize: Qt.size(
                    Math.max(1, toastColumn.implicitWidth
                        + root.toastBodyPadding * 2),
                    Math.max(1, toastColumn.implicitHeight
                        + root.toastBodyPadding * 2))
                outerRadius: PerimeterTokens.popupRadius
                screenMargin: root.screenEdgeThickness
                connectorLength: 0
                seamOverlap: PerimeterTokens.abyssWeldDepth
                progress: root.surfaceRevealProgress
                devicePixelRatio: popup.devicePixelRatio
            }

            ConnectedSurfaceRevealClip {
                id: toastRevealClip
                geometry: toastGeometry

                ConnectedSurfaceAbyssFrame {
                    id: toastFrame
                    anchors.fill: parent
                    geometry: toastGeometry
                    fillColor: Appearance.colors.colLayer0
                    borderColor: Appearance.colors.colLayer0Border
                    borderWidth: 0
                    fuseDepth: PerimeterTokens.abyssFuseDepth
                    externalFrameThickness: root.screenEdgeThickness
                    shadowEnabled: root.edgeShadowEnabled
                        && root.edgeShadowSize > 0
                        && root.edgeShadowOpacity > 0
                    shadowExtent: root.edgeShadowSize
                    shadowColor: root.edgeShadowColor
                    // Primary top owner is Bar when it is actually
                    // present at the top; otherwise it is the top Screen Edge.
                    // Only the Screen-Edge fallback is allowed to weld into the
                    // tangent right frame.
                    joinTop: true
                    joinRight: !root.topBarOwnsEdge
                }

                ConnectedSurfaceContentHost {
                    id: toastContentHost
                    geometry: toastGeometry
                    padding: root.toastBodyPadding

                    ColumnLayout {
                        id: toastColumn
                        anchors.fill: parent
                        spacing: root.toastSpacing

                        Repeater {
                            model: root.toasts

                            delegate: ToastNotification {
                                required property var modelData
                                required property int index

                                connectedSurface: true
                                title: modelData.title
                                message: modelData.message
                                icon: modelData.icon
                                isError: modelData.isError
                                duration: modelData.duration
                                source: modelData.source
                                accentColor: modelData.accentColor

                                opacity: 1
                                scale: 1

                                onDismissed: root.dismissToast(modelData.id)
                            }
                        }
                    }
                }
            }

            ConnectedSurfaceBodyMask {
                id: toastMask
                geometry: toastGeometry
                bodyItem: toastFrame.bodyItem
                visibleBodyRect: toastFrame.visibleBodyRect
                inputEnabled: popup.visible
            }

            mask: toastMask
        }
    }
}
