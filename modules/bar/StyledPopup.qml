import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.perimeter
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root
    // QML deferred closures can outlive a Loader's destroyed popup subtree.
    // A disposed wrapper no longer exposes its methods; cancel before invoking
    // any of them, including callbacks queued during ancestor replacement.
    property bool _live: true

    property Item hoverTarget
    // Optional semantic kind used only when a mature popup is rehosted by the
    // Abyss output field. Battery naturally inherits "battery" from its owning
    // module; Launcher uses this override because its visual module is distroIcon.
    property string liquidPresentationKind: ""
    // The same feature/content can be hosted by the output's Abyss field.
    // No second native popup, connector painter or feature implementation.
    property Item embeddedHost: null
    function liquidAnchor(item) {
        for (let ancestor = item; ancestor; ancestor = ancestor.parent)
            if (ancestor.liquidController) return ancestor
        return null
    }
    // A fresh Loader can create the popup before the anchor's ancestor chain
    // is attached to AbyssBarModule. Rescan when ancestor parents/controllers
    // change; bounded cold-mount retries cover out-of-order QML completion.
    property int _anchorTreeRevision: 0
    readonly property Item _liquidAnchor: {
        const revision = root._anchorTreeRevision
        return root.liquidAnchor(root.hoverTarget)
    }
    readonly property var _liquidController: embeddedHost ? null : _liquidAnchor?.liquidController ?? null
    function refreshAnchorOwnership(): void {
        if (!root || !root._live) return
        root._anchorTreeRevision += 1
        Qt.callLater(() => {
            if (!root || !root._live) return
            root.syncCompanionAnchor()
            root.syncLiquidPresentation()
            Qt.callLater(root._syncBarAutoHideLease)
        })
    }
    function startColdAnchorResolution(): void {
        if (!root || !root._live || !root.hoverTarget) return
        anchorResolveRetry.remaining = 18
        root.refreshAnchorOwnership()
        if (!root._liquidController && !root.embeddedHost)
            anchorResolveRetry.restart()
    }
    property QtObject _anchorTargetConnections: Connections {
        target: root.hoverTarget
        ignoreUnknownSignals: true
        function onParentChanged() { root.startColdAnchorResolution() }
        function onLiquidControllerChanged() { root.refreshAnchorOwnership() }
    }
    property QtObject _anchorParentConnections: Connections {
        target: root.hoverTarget?.parent ?? null
        ignoreUnknownSignals: true
        function onParentChanged() { root.startColdAnchorResolution() }
        function onLiquidControllerChanged() { root.refreshAnchorOwnership() }
    }
    property QtObject _anchorGrandparentConnections: Connections {
        target: root.hoverTarget?.parent?.parent ?? null
        ignoreUnknownSignals: true
        function onParentChanged() { root.startColdAnchorResolution() }
        function onLiquidControllerChanged() { root.refreshAnchorOwnership() }
    }
    property QtObject _anchorOwnerConnections: Connections {
        target: root._liquidAnchor
        ignoreUnknownSignals: true
        function onParentChanged() { root.refreshAnchorOwnership() }
        function onLiquidControllerChanged() { root.refreshAnchorOwnership() }
    }
    // Initial QsWindow can become available after the shell's first frame
    // (observed boot log: shellEntryReady at T+1390ms). A one-second retry
    // started at QML construction is not sufficient by itself.
    property QtObject _shellReadinessConnections: Connections {
        target: GlobalStates
        function onShellEntryReadyChanged() {
            if (GlobalStates.shellEntryReady && root.hoverTarget)
                root.startColdAnchorResolution()
        }
        function onDeferredPanelsReadyChanged() {
            if (GlobalStates.deferredPanelsReady && root.hoverTarget)
                root.startColdAnchorResolution()
        }
    }
    property QtObject _anchorResolveTimer: Timer {
        id: anchorResolveRetry
        interval: 60
        repeat: true
        running: false
        property int remaining: 18
        onTriggered: {
            if (!root.hoverTarget || root._liquidController || remaining <= 0) {
                stop()
                return
            }
            remaining--
            root.refreshAnchorOwnership()
        }
    }
    property var _hostedController: null
    property bool _liquidDismissed: false
    // Preserve dismissal while the user-requested slide is still running.
    property bool _gracefulDismissal: false
    property bool _liquidSemanticHold: false
    // Aqua borrows this exact mature popup. Hover/focus takes the same content
    // over, and revokes the lease so its later departure cannot close user UI.
    property var companionLease: null
    property var _companionAnchor: null
    function syncCompanionAnchor(): void {
        if (_companionAnchor === _liquidAnchor) return
        if (_companionAnchor?.unregisterCompanionPopup)
            _companionAnchor.unregisterCompanionPopup(root)
        companionLease = null
        _companionAnchor = _liquidAnchor
        if (_companionAnchor?.registerCompanionPopup)
            _companionAnchor.registerCompanionPopup(root)
    }
    on_LiquidAnchorChanged: syncCompanionAnchor()
    function acquireCompanion(owner): bool {
        if (!owner || !_anchorReady || !_liquidController || humanVisibleRequest
                || companionLease || presentationActive) return false
        _liquidDismissed = false
        companionLease = owner
        return true
    }
    function releaseCompanion(owner): void {
        if (companionLease === owner) companionLease = null
    }
    on_AnchorReadyChanged: {
        if (!_anchorReady) companionLease = null
        // Readiness can change while QsWindow is evaluating _anchorWindow.
        // Rescanning writes its hierarchy revision, so defer that write until
        // the current binding evaluation has completed.
        else if (!root._liquidController) Qt.callLater(root.startColdAnchorResolution)
    }
    readonly property bool presentationActive: embeddedHost ? embeddedHost.visible
        : _liquidController ? _anchorReady && _liquidController.presented
            && (requestedVisible || _lingerVisible) : active
    function syncLiquidPresentation(): void {
        if (_hostedController && (_hostedController !== _liquidController || !presentationActive)) {
            _hostedController.releasePopup(root)
            _hostedController = null
        }
        if (!_liquidController || !presentationActive || !contentItem) return
        _hostedController = _liquidController
        _hostedController.presentPopup(root)
    }
    // User-requested close: keep the resident panel through the normal
    // slide-under retract tail instead of snapping it/fading it out.
    // Forced owner eviction still uses dismissPresentation() below.
    function retractPresentation(): void {
        companionLease = null
        _gracefulDismissal = true
        _liquidDismissed = true
        _liquidSemanticHold = false
        _bodyHovered = false
        _contentHovered = false
        hoverTransferTimer.stop()
        if (_liquidController) _liquidController.releasePopupHover(root)
        if (_lingerVisible)
            _beginRetract()
        else
            offsetScale = 1
        requestClose()
    }

    function dismissPresentation(): void {
        companionLease = null
        _gracefulDismissal = false
        _liquidDismissed = true
        _liquidSemanticHold = false
        _bodyHovered = false; _contentHovered = false
        _lingerVisible = false
        offsetScale = 1
        if (_liquidController) _liquidController.releasePopupHover(root)
        requestClose()
    }
    property QtObject _liquidPresentationConnections: Connections {
        target: root
        function onPresentationActiveChanged() { root.syncLiquidPresentation(); Qt.callLater(root._syncBarAutoHideLease) }
        function onContentItemChanged() { root.syncLiquidPresentation() }
        function on_LiquidControllerChanged() {
            if (root._liquidController) {
                anchorResolveRetry.stop()
                if (root._hoverRequested)
                    root._liquidController.claimPopupHover(root)
            }
            root.syncCompanionAnchor()
            root.syncLiquidPresentation()
        }
    }
    function syncEmbeddedContent(): void {
        if (!embeddedHost || !contentItem) return
        contentItem.parent = embeddedHost
        contentItem.x = 0; contentItem.y = 0
        contentItem.width = Qt.binding(() => embeddedHost.width)
        contentItem.height = Qt.binding(() => embeddedHost.height)
    }
    onEmbeddedHostChanged: syncEmbeddedContent()
    onContentItemChanged: syncEmbeddedContent()
    // Optional rect in hoverTarget-local coordinates. The target itself remains
    // the real visual/source control for output ownership; this rect only narrows
    // tangent placement (for example a right-click point inside a broad Bar zone).
    property var anchorRect: null
    // Some large connected surfaces (notably workspace Overview) should keep
    // their Bar ownership but use the output midpoint for tangent placement.
    // This changes only placement; the real hoverTarget still owns screen,
    // edge, hover-transfer and cross-axis attachment.
    property bool centerOnOutput: false
    // Edge-hosted hot-corner anchors live in tiny layer-shell windows whose
    // local coordinates start at zero even when the window is physically on the
    // output's trailing edge. Let those callers pin tangent placement to the
    // output start/end without weakening hoverTarget screen ownership.
    property string tangentEdgeOverride: ""
    property string attachmentEdgeOverride: ""
    property real attachmentThicknessOverride: -1
    property bool hoverActivates: true
    // Opt-in for launchers whose actual icon is smaller than their owner Bar
    // module. Legacy popups can still use the ancestor hover for broad zones.
    // A strict source accepts only its own MouseArea / HoverHandler.
    property bool strictSourceHover: false
    // Read live module and source pointer state, never an event-copied latch:
    // nested controls can consume hover transitions while still tracking their
    // own MouseArea.containsMouse. All sources release when the pointer leaves.
    readonly property bool moduleHoverActive: root._sourceHoverReady && !!(
        root.strictSourceHover
            ? (root.hoverTarget?.containsMouse || root.hoverTarget?.hovered)
            : (root._liquidAnchor?.hovered
                || root._liquidAnchor?.feature?.containsMouse
                || root._liquidAnchor?.feature?.hovered
                || root.hoverTarget?.containsMouse
                || root.hoverTarget?.hovered))
    property bool barAutoHideHoldEnabled: true
    property int _barPopupHoverLeaseId: 0
    property bool alternativeVisibleCondition: false
    property bool closeOnOutsideClick: false
    // Keep the outside-click catcher below the popup when a surface needs to
    // remain pointer-interactive after the catcher maps (for example a text
    // editor that enters focus mode after its first click).
    property bool outsideClickBackdropBelowPopup: false
    property bool keyboardFocus: false
    // Allow a visible popup to participate in compositor click-to-focus without
    // proactively stealing focus. This mirrors the working sticky-note and
    // background editor contract: WlrKeyboardFocus.OnDemand is armed before the
    // first click, while explicit keyboardFocus remains false until the surface
    // actually owns the editor.
    property bool keyboardFocusOnDemand: false
    // Some click-activated editors become keyboard owners only after the
    // pointer event that requested editing has already reached the popup.
    // OnDemand cannot retroactively focus that first click on Niri, so those
    // surfaces may opt into Exclusive focus once keyboardFocus flips true.
    // The default remains OnDemand for existing focused popups such as Media.
    property bool exclusiveKeyboardFocus: false
    property bool _bodyHovered: false
    property bool _contentHovered: false
    readonly property bool popupHovered: root._bodyHovered || root._contentHovered
    default property Item contentItem
    property real popupBackgroundMargin: 0
    // Compatibility knob retained for old callers. Placement is now authoritative:
    // every popup automatically joins any Screen Edge its body actually reaches.
    property bool connectAdjacentScreenEdge: false

    // Presentation-only handle for the lazily-created connected surface. This is
    // useful to presentation peers such as the tray focus grab; feature/backend
    // state never depends on this window object.
    property var presentationWindow: null

    readonly property bool _barVertical: Config.options?.bar?.vertical ?? false
    readonly property bool _trailingEdge: Config.options?.bar?.bottom ?? false
    readonly property string _defaultAttachmentEdge: root._barVertical
        ? (root._trailingEdge ? "right" : "left")
        : (root._trailingEdge ? "bottom" : "top")
    readonly property string _attachmentEdge:
        root._liquidAnchor?.attachedEdge ?? (["top", "bottom", "left", "right"].includes(root.attachmentEdgeOverride)
            ? root.attachmentEdgeOverride : root._defaultAttachmentEdge)
    readonly property bool _attachmentVertical:
        root._attachmentEdge === "left" || root._attachmentEdge === "right"
    readonly property bool _attachmentTrailing:
        root._attachmentEdge === "right" || root._attachmentEdge === "bottom"
    // Source controls own tangent placement; the attached surface owns the
    // cross-axis edge. Existing Bar callers keep canonical Bar thickness while
    // Screen Edge callers may provide the physical frame thickness.
    readonly property real _barSurfaceThickness:
        root._liquidController?.edgeInsets?.[root._attachmentEdge]
            ?? (root.attachmentThicknessOverride > 0
            ? root.attachmentThicknessOverride
            : (root._attachmentVertical
                ? Appearance.sizes.verticalBarWidth
                : Appearance.sizes.barHeight))
    readonly property real _contentPadding: 14
    readonly property real _screenEdgeThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
    // Placement stops at the real Screen Edge inner boundary. Tangent welding
    // is SDF-only inside ConnectedSurfaceAbyssFrame, so content/input never need
    // to live underneath the physical Screen Edge just to keep the fillet.
    readonly property real _popupScreenMargin: root._screenEdgeThickness
    // Share the public Screen Edge shadow controls and raw Material shadow ink.
    // colShadow can become transparent in transparent-material modes, which made
    // popup depth disappear even while the physical Screen Edge shadow remained.
    readonly property bool _edgeShadowEnabled:
        Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
    readonly property real _edgeShadowExtent: Math.max(0, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
    readonly property real _edgeShadowOpacity: Math.max(0, Math.min(1.0,
        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))
    readonly property color _edgeShadowColor:
        Qt.alpha(Appearance.m3colors.m3shadow, root._edgeShadowOpacity)

    // The visual anchor is the authority for output/window ownership. StyledPopup
    // itself is a LazyLoader and is not a visual child of the bar, so resolving
    // QsWindow from the loader can point at no window at all. Keeping placement,
    // screen selection and geometry attached to the actual source Item mirrors the
    // layer-surface model used by edge shells: a full-output presentation window
    // with a shape-aware input region, driven by a control already on that output.
    readonly property var _anchorWindow: {
        const revision = root._anchorTreeRevision
        return root.hoverTarget ? root.hoverTarget.QsWindow.window : null
    }
    readonly property var _anchorScreen: root._anchorWindow
        ? root._anchorWindow.screen : null
    readonly property bool _anchorReady: root.hoverTarget !== null
        && root.hoverTarget.visible
        && root.hoverTarget.enabled
        && root._anchorWindow !== null
        && root._anchorScreen !== null
        && root.hoverTarget.width > 0
        && root.hoverTarget.height > 0

    // Source input eligibility is narrower than presentation readiness: a
    // disabled module can retain mature-feature hover flags during editing,
    // while an already-open body's hover or explicit pin/keyboard request
    // still has its own lifetime on this output.
    readonly property bool _sourceHoverReady: root._anchorReady
        && (!root._liquidAnchor
            || (root._liquidAnchor.visible && root._liquidAnchor.enabled))

    // Observe the actual source Item, including interactive descendants. Legacy
    // MouseArea flags can stop reporting hover over a child's pointer handler
    // or survive a focus click; neither is the popup's pointer lease.
    property Item _anchorHover: Item {
        parent: root.hoverTarget
        anchors.fill: parent
        enabled: root.hoverActivates && root._sourceHoverReady
        readonly property bool hovered: sourceHover.enabled && sourceHover.hovered
        // Read-only, scene-local coordinates, valid ONLY while hovered.
        // Qt resets HandlerPoint when not tracking a point; never
        // interpret (0,0) after leave as a genuine pointer position.
        readonly property var hoverProbeScenePoint: sourceHover.enabled && sourceHover.hovered
            ? ({ x: sourceHover.point.scenePosition.x,
                 y: sourceHover.point.scenePosition.y }) : null
        HoverHandler {
            id: sourceHover
            enabled: root.hoverActivates && root._sourceHoverReady
            onHoveredChanged: {
                if (hovered && !root._liquidController)
                    root.refreshAnchorOwnership()
            }
        }
    }

    // Keep the loader resident for the reverse morph. `requestedVisible` is the
    // semantic popup state; `active` includes only the short retract tail. While
    // hover-activated, the body itself also counts as the request so the pointer
    // can travel from the bar through the connected shoulder without collapse.
    readonly property bool _hoverRequested: root.hoverActivates
        && (root.moduleHoverActive || root._anchorHover.hovered || root.popupHovered)
    on_HoverRequestedChanged: {
        if (root._hoverRequested) {
            if (root._liquidController)
                root._liquidController.claimPopupHover(root)
        } else if (root._liquidController) {
            root._liquidController.releasePopupHover(root)
        }
    }
    readonly property bool humanVisibleRequest: root.alternativeVisibleCondition
        || (root._hoverRequested
            && (!root._liquidController
                || root._liquidController.hoveredPopup === root))
    onHumanVisibleRequestChanged: if (humanVisibleRequest) companionLease = null
    readonly property bool _rawVisibleRequest: root.companionLease !== null || root.humanVisibleRequest
    readonly property bool requestedVisible: !root._liquidDismissed && root._rawVisibleRequest
    // Abyss semantic ownership includes only the 90 ms compositor hand-off
    // grace, never the visual retract tail.
    readonly property bool liquidSemanticVisible:
        root.requestedVisible || root._liquidSemanticHold
    function _cancelSemanticHold(): void {
        if (!root._liquidSemanticHold)
            return
        root._liquidSemanticHold = false
        hoverTransferTimer.stop()
        if (!root.requestedVisible)
            root._beginRetract()
    }
    on_RawVisibleRequestChanged: {
        if (!root._rawVisibleRequest && !root._gracefulDismissal)
            root._liquidDismissed = false
    }
    function _finishGracefulDismissal(): void {
        if (!root._gracefulDismissal)
            return
        root._gracefulDismissal = false
        if (!root._rawVisibleRequest)
            root._liquidDismissed = false
    }
    property bool _lingerVisible: false
    // Match Caelestia's panel wrappers: one normalized offsetScale drives the
    // whole slide and reverses naturally from its current value. Geometry keeps
    // consuming revealProgress as the inverse for compatibility.
    property real offsetScale: 1
    readonly property real revealProgress: 1 - root.offsetScale

    // Material is the sole supported Global Theme for v1.0. Keep the connected
    // popup surface on the canonical Material palette and radius instead of
    // retaining unreachable alternate-theme branches in the shared popup path.
    readonly property color _surfaceColor: Appearance.colors.colLayer0
    readonly property color _borderColor: Appearance.colors.colLayer0Border
    readonly property real _borderWidth: 0
    // Caelestia PanelBg uses Tokens.rounding.extraLarge (28px at scale 1).
    readonly property real _surfaceRadius: PerimeterTokens.popupRadius

    signal requestClose()

    active: !root.embeddedHost && !root._liquidController && root._anchorReady && (root.requestedVisible || root._lingerVisible)

    function _syncBarAutoHideLease(): void {
        if (!root || !root._live || root._barPopupHoverLeaseId <= 0)
            return
        GlobalStates.setBarPopupHoverLease(root._barPopupHoverLeaseId,
            String(root._anchorScreen?.name ?? ""),
            root.barAutoHideHoldEnabled && root.presentationActive && root._anchorReady)
    }

    // The lease makes an auto-hide anchor visible, which in turn contributes
    // to presentationActive. Publish after that binding turn to avoid re-entry.
    // Qt.callLater coalesces calls to this same function.
    on_AnchorScreenChanged: Qt.callLater(root._syncBarAutoHideLease)
    onBarAutoHideHoldEnabledChanged: Qt.callLater(root._syncBarAutoHideLease)

    // Hover handlers belong to the lazily-created presentation window. Their
    // last true state must not survive eviction, anchor replacement or a
    // hidden bar: otherwise requestedVisible can resurrect a stale popup.
    onActiveChanged: {
        if (root._liquidController) return
        Qt.callLater(root._syncBarAutoHideLease)
        if (active) {
            // A hidden anchor can become ready while requestedVisible was
            // already true; resume the reveal without waiting for a new hover.
            if (root.requestedVisible && !root._lingerVisible)
                root._syncRequestedVisibility()
            return
        }
        root._bodyHovered = false
        root._contentHovered = false
        root._liquidSemanticHold = false
        root._lingerVisible = false
        root.offsetScale = 1
    }
    onHoverTargetChanged: {
        anchorResolveRetry.stop()
        if (root._liquidController) root._liquidController.releasePopupHover(root)
        if (root.hoverTarget) Qt.callLater(root.startColdAnchorResolution)
        root._gracefulDismissal = false
        root._liquidDismissed = false
        root._liquidSemanticHold = false
        root._bodyHovered = false
        root._contentHovered = false
        Qt.callLater(root._syncBarAutoHideLease)
    }

    function _beginRetract(): void {
        if (!root._lingerVisible)
            return
        root.offsetScale = 1
        if (Appearance.animationsEnabled)
            retractTimer.restart()
        else {
            root._lingerVisible = false
            root._finishGracefulDismissal()
        }
    }

    function _syncRequestedVisibility(): void {
        if (root.requestedVisible) {
            const alreadyResident = root._lingerVisible
            root._liquidSemanticHold = false
            hoverTransferTimer.stop()
            retractTimer.stop()
            root._lingerVisible = true
            if (!Appearance.animationsEnabled) {
                root.offsetScale = 0
                return
            }
            if (alreadyResident) {
                // Reverse an in-flight close from its current geometry rather than
                // snapping to zero and replaying the opening animation.
                root.offsetScale = 0
                return
            }
            root.offsetScale = 1
            Qt.callLater(() => {
                if (root && root._live && root.requestedVisible)
                    root.offsetScale = 0
            })
            return
        }

        if (!root._lingerVisible)
            return

        // Bar and popup are separate layer-shell surfaces. Compositors can emit
        // one leave before the matching enter when the pointer crosses their
        // shared seam. Give that hand-off a short grace period so a transient
        // all-false hover state cannot start a retract/reopen oscillation.
        if (root.hoverActivates
                && !(root._liquidController?._claimingPopupHover ?? false)
                && ((root._liquidController?.hoveredPopup ?? null) === null
                    || root._liquidController?.hoveredPopup === root)) {
            root._liquidSemanticHold = true
            hoverTransferTimer.restart()
            return
        }

        root._beginRetract()
    }

    onRequestedVisibleChanged: root._syncRequestedVisibility()
    Component.onCompleted: {
        Qt.callLater(root.startColdAnchorResolution)
        root.syncCompanionAnchor()
        root.syncEmbeddedContent()
        root._barPopupHoverLeaseId = GlobalStates.allocateBarPopupHoverLease()
        Qt.callLater(root._syncBarAutoHideLease)
        if (root._hoverRequested && root._liquidController)
            root._liquidController.claimPopupHover(root)
        root._syncRequestedVisibility()
        root.syncLiquidPresentation()
    }
    Component.onDestruction: {
        root._live = false
        anchorResolveRetry.stop()
        if (root._companionAnchor?.unregisterCompanionPopup)
            root._companionAnchor.unregisterCompanionPopup(root)
        if (root._liquidController) root._liquidController.releasePopupHover(root)
        if (root._hostedController) {
            root._hostedController.releasePopupHover(root)
            root._hostedController.releasePopup(root, false)
        }
        GlobalStates.setBarPopupHoverLease(root._barPopupHoverLeaseId, "", false)
    }

    // Immutable ii surface-motion contract: slide only, monotonic, no
    // spring/back/overshoot and no theme/config curve override.
    Behavior on offsetScale {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: SurfaceMotion.duration
            easing.type: SurfaceMotion.easingType
        }
    }

    // `contentItem` is the default property and accepts only QQuickItem. Keep
    // internal QObject/QWindow helpers on explicit object properties so they are
    // never routed through the popup content contract during type construction.
    property QtObject _hoverTransferTimerObject: Timer {
        id: hoverTransferTimer
        interval: 90
        repeat: false
        onTriggered: {
            root._liquidSemanticHold = false
            if (!root.requestedVisible)
                root._beginRetract()
        }
    }

    property QtObject _retractTimerObject: Timer {
        id: retractTimer
        interval: Math.max(1, SurfaceMotion.duration + 16)
        repeat: false
        onTriggered: {
            if (!root.requestedVisible && root.offsetScale >= 0.999) {
                root._lingerVisible = false
                root._finishGracefulDismissal()
            }
        }
    }

    function _anchorRect(outputWidth, outputHeight) {
        const target = root.hoverTarget
        const host = target ? target.QsWindow : null
        const hostWindow = root._anchorWindow
        if (!target || !host || !hostWindow || !root._anchorScreen
                || target.width <= 0 || target.height <= 0
                || outputWidth <= 0 || outputHeight <= 0)
            return Qt.rect(0, 0, 0, 0)

        // Mapping is non-reactive. Ancestor rotations/scales also change a
        // source's scene rectangle without changing its own local dimensions.
        for (let item = target; item; item = item.parent) {
            item.x; item.y; item.width; item.height
            item.rotation; item.scale; item.transformOrigin
        }
        hostWindow.windowTransform

        const localX = Number(root.anchorRect?.x ?? 0)
        const localY = Number(root.anchorRect?.y ?? 0)
        const localWidth = Math.max(1,
            Number(root.anchorRect?.width ?? target.width))
        const localHeight = Math.max(1,
            Number(root.anchorRect?.height ?? target.height))
        // A rotated module's local width becomes its scene height. Mapping
        // just the first corner shifts long vertical sources away from their
        // popup, leaving the pointer outside the actual painted connection.
        const corners = [
            host.mapFromItem(target, localX, localY),
            host.mapFromItem(target, localX + localWidth, localY),
            host.mapFromItem(target, localX, localY + localHeight),
            host.mapFromItem(target, localX + localWidth, localY + localHeight)
        ]
        const left = Math.min(...corners.map(point => point.x))
        const top = Math.min(...corners.map(point => point.y))
        const sceneWidth = Math.max(...corners.map(point => point.x)) - left
        const sceneHeight = Math.max(...corners.map(point => point.y)) - top
        const thickness = Math.max(1, Number(root._barSurfaceThickness ?? 1))

        // Preserve the source/sub-rect tangent center/extent, but normalize the
        // cross-axis boundary to the real Bar surface. Large surfaces may opt
        // into the output midpoint without replacing the real Bar ownership
        // anchor — important for workspace Overview, which should be visually
        // centered even when the hovered workspace button sits near an edge.
        if (root._attachmentVertical) {
            const barX = root._attachmentTrailing
                ? Math.max(0, outputWidth - thickness) : 0
            const tangentY = root.centerOnOutput
                ? Math.max(0, (outputHeight - sceneHeight) / 2)
                : root.tangentEdgeOverride === "start" ? 0
                : root.tangentEdgeOverride === "end"
                    ? Math.max(0, outputHeight - sceneHeight) // rotated equivalent of outputHeight - localHeight
                : top
            return Qt.rect(barX, tangentY, thickness, sceneHeight)
        }

        const barY = root._attachmentTrailing
            ? Math.max(0, outputHeight - thickness) : 0
        const tangentX = root.centerOnOutput
            ? Math.max(0, (outputWidth - sceneWidth) / 2)
            : root.tangentEdgeOverride === "start" ? 0
            : root.tangentEdgeOverride === "end"
                ? Math.max(0, outputWidth - sceneWidth) // rotated equivalent of outputWidth - localWidth
            : left
        return Qt.rect(tangentX, barY, sceneWidth, thickness)
    }

    // Fullscreen transparent backdrop for Niri to detect clicks outside
    // (same pattern as ContextMenu / SysTrayMenu). It disappears as soon as the
    // semantic popup closes while the visual surface is allowed to retract.
    property QtObject _clickOutsideBackdropObject: PanelWindow {
        id: clickOutsideBackdrop
        visible: root._anchorReady && root.requestedVisible && root.closeOnOutsideClick
        screen: root._anchorScreen
        color: Qt.rgba(0, 0, 0, 1/255)
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        // The output field is already Overlay while hosting this content. A
        // separately mapped Overlay catcher could cover its valid input and
        // dismiss an inside click before a tab or button ever receives it.
        WlrLayershell.layer: root._liquidController !== null || root.outsideClickBackdropBelowPopup
            ? WlrLayer.Top : WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:popup-catcher"
        anchors { top: true; bottom: true; left: true; right: true }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.requestClose()
        }
    }

    component: PanelWindow {
        id: popupWindow

        screen: root._anchorScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        visible: root.active
        focusable: root.requestedVisible
            && (root.keyboardFocus || root.keyboardFocusOnDemand)

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: !root.requestedVisible
            ? WlrKeyboardFocus.None
            : root.keyboardFocus && root.exclusiveKeyboardFocus
                ? WlrKeyboardFocus.Exclusive
                : (root.keyboardFocus || root.keyboardFocusOnDemand)
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None

        Component.onCompleted: root.presentationWindow = popupWindow
        Component.onDestruction: {
            if (root.presentationWindow === popupWindow)
                root.presentationWindow = null
        }

        // Hyprland still needs an explicit grab for keyboard-driven popouts;
        // Niri uses the layer-shell focus mode above. Keep the behavior inside
        // the shared popup so focused surfaces (notably Media) do not fall back
        // to a detached-window implementation just to own keyboard focus.
        CompositorFocusGrab {
            // Layer-shell keyboard interactivity is authoritative on Niri.
            // CompositorFocusGrab is the Hyprland compatibility path only; if
            // activated on Niri it can immediately clear and undo a legitimate
            // TextArea focus transition.
            active: CompositorService.isHyprland
                && root.keyboardFocus && root.requestedVisible
            windows: [popupWindow]
            onCleared: root.requestClose()
        }

        ConnectedSurfaceGeometry {
            id: geometry
            edge: root._attachmentEdge
            alignment: "center"
            outputRect: Qt.rect(0, 0, popupWindow.width, popupWindow.height)
            anchorRect: root._anchorRect(popupWindow.width, popupWindow.height)
            bodySize: Qt.size(
                Math.max(1, (root.contentItem?.implicitWidth ?? 0)
                    + root._contentPadding * 2 + Math.max(0, root.popupBackgroundMargin)),
                Math.max(1, (root.contentItem?.implicitHeight ?? 0)
                    + root._contentPadding * 2 + Math.max(0, root.popupBackgroundMargin)))
            outerRadius: root._surfaceRadius
            screenMargin: root._popupScreenMargin
            // Caelestia composes popouts directly into the edge surface. Keep
            // the shared geometry, but remove the detached neck/gap entirely.
            connectorLength: 0
            // Match the accepted G2 morphology: the SDF body overlaps its
            // primary owner by the locked weld depth, while reveal/paint/input
            // clipping still starts at the real Bar/Screen Edge boundary.
            seamOverlap: PerimeterTokens.abyssWeldDepth
            progress: root.revealProgress
            devicePixelRatio: popupWindow.devicePixelRatio
        }

        QtObject {
            id: directEdgeAttachment

            readonly property rect body: geometry.bodyRect
            readonly property real epsilon:
                1 / Math.max(1, popupWindow.devicePixelRatio)
            readonly property real margin: geometry.effectiveScreenMargin
            // Detect all output edges from the resting body geometry. A popup
            // moved away from a corner therefore loses that edge join naturally;
            // a wide/tall popup may join multiple Screen Edges if it reaches them.
            readonly property bool atLeft:
                Math.abs(body.x - margin) <= epsilon
            readonly property bool atRight:
                Math.abs((popupWindow.width - margin)
                    - (body.x + body.width)) <= epsilon
            readonly property bool atTop:
                Math.abs(body.y - margin) <= epsilon
            readonly property bool atBottom:
                Math.abs((popupWindow.height - margin)
                    - (body.y + body.height)) <= epsilon
        }

        // Fixed resting-edge viewport: the full popup translates behind this
        // clip, so closing/opening reads as sliding underneath the Bar/Screen Edge.
        ConnectedSurfaceRevealClip {
            id: popupRevealClip
            geometry: geometry

            ConnectedSurfaceAbyssFrame {
                id: frame
                anchors.fill: parent
                geometry: geometry
                fillColor: root._surfaceColor
                borderColor: root._borderColor
                borderWidth: root._borderWidth
                fuseDepth: PerimeterTokens.abyssFuseDepth
                externalFrameThickness: root._screenEdgeThickness
                // Own hover on the complete popup body, including its visual
                // padding, but not on the reveal viewport's empty screen area.
                // This closes the Bar→popup dead zone without turning the whole
                // inward half of the output into a hover bridge.
                hoverEnabled: root.active
                onBodyHoveredChanged: root._bodyHovered = bodyHovered
                shadowEnabled: root._edgeShadowEnabled
                    && root._edgeShadowExtent > 0
                    && root._edgeShadowOpacity > 0
                shadowExtent: root._edgeShadowExtent
                shadowColor: root._edgeShadowColor
                joinTop: root._attachmentEdge === "top"
                    || directEdgeAttachment.atTop
                joinBottom: root._attachmentEdge === "bottom"
                    || directEdgeAttachment.atBottom
                joinLeft: root._attachmentEdge === "left"
                    || directEdgeAttachment.atLeft
                joinRight: root._attachmentEdge === "right"
                    || directEdgeAttachment.atRight
            }

            ConnectedSurfaceContentHost {
                id: popupContentHost
                geometry: geometry
                padding: root._contentPadding
                // Pure slide-under motion: no scale/shrink and no staged fade.
                opacity: 1
                children: [root.contentItem]

                // Track the actual content plane as well as the decorative body.
                // Interactive children (notably StyledSwitch/MouseArea controls)
                // sit above ConnectedSurfaceFrame and can otherwise make the
                // Abyss body's HoverHandler report a transient leave while the pointer
                // is still visibly inside the popup, causing retract/reopen jitter.
                HoverHandler {
                    enabled: root.active
                    onHoveredChanged: root._contentHovered = hovered
                }
            }
        }

        ConnectedSurfaceBodyMask {
            id: connectedMask
            geometry: geometry
            bodyItem: frame.bodyItem
            visibleBodyRect: frame.visibleBodyRect
            inputEnabled: root.requestedVisible
                || (root.hoverActivates && root._lingerVisible)
        }

        mask: connectedMask
    }
}
