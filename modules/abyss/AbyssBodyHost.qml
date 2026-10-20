import QtQuick
import QtQml.Models
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss.looks
import "looks/AbyssGeometry.js" as Geometry
import "looks/AbyssPyramidMotion.js" as PyramidMotion
import "looks/AbyssWave.js" as Wave
import "looks/AbyssPlacementMemo.js" as PlacementMemo

// This host never paints a panel. Its geometry record is consumed by the one
// output field. Hover popups may include their drawn connection to the Edge;
// other bodies retain only the clipped content rectangle as their input region.
Item {
    id: root
    required property string edge
    property string joinedEdge: ""
    readonly property string attachedEdge: edge
    property string outputName: ""
    property string identity: ""
    property var controller: null
    readonly property var liquidController: controller
    // Presentation-only semantic metadata for vacancy borrowing.
    property string vacancyRole: ""
    property bool vacancyHovered: root.vacancyRole.length > 0
        && vacancyBodyHover.hovered
    property int vacancyHoverOrder: 0
    property Item embeddedItem: null
    property bool includeEdgeConnection: false
    property rect connectionSourceRect: Qt.rect(0,0,0,0)
    property bool animatePresentation: true
    // Notification Center already supplies a monotonic revealProgress from
    // StyledPopup. Suppress this host's second availability tween for that
    // explicitly opted-in surface, without changing loading/readiness gates.
    property bool singleExternalReveal: false
    // Transient notifications do not need the generic spring/settle tail:
    // one monotonic pass has fewer animation frames and avoids the visible
    // change of direction at the end of a small notification banner.
    property bool monotonicNotificationReveal: false
    property bool stableContentSize: false
    // Some owners need content-owned hold-open state even while visually closed.
    // Keep those contents resident so open never depends on a Loader whose
    // activation itself depends on open.
    property bool residentContent: false
    // Large canvases get a short reuse window, never a permanent residency.
    // Warm content is hidden and has no input after the final closing pixel.
    property bool warmContent: false
    property bool warmHeld: false
    onWarmContentChanged: if (!warmContent) { warmExpiry.stop(); warmHeld=false }
    onVisualResidentChanged: {
        if (visualResident) warmExpiry.stop()
        else if (warmHeld) warmExpiry.restart()
    }
    Timer {
        id: warmExpiry
        interval: 1200
        onTriggered: root.warmHeld=false
    }
    // Allocator changes (another popup/body entering, leaving, or reflowing)
    // should travel to their new tier instead of snapping the shared field to a
    // larger silhouette in one frame. Editor/Dock geometry stays immediate.
    property bool animatePlacementChanges:
        identity !== "dock" && identity !== "edgeEditor" && identity !== "editorPreview"
    property bool largeSurface: false
    // Content may place a compact control surface above itself. Top-attached
    // bodies move inward; side-attached bodies move along their physical Edge.
    // Both leave the widget canvas dimensions unchanged during editing.
    readonly property real minimumInward: edge === "top"
        && (contentItem.item?.editMode ?? false)
        ? Math.max(0, Number(contentItem.item?.topControlReserve ?? 0)) : 0
    readonly property real requestedAlong: !Geometry.horizontal(edge)
        && (contentItem.item?.editMode ?? false)
        ? Math.max(along, Number(contentItem.item?.topControlReserve ?? 0)) : along
    // Keep Dock/icon geometry fixed, but let panel content reflow before any
    // lower-priority body is evicted. These are panel dimensions including
    // padding; hosts may raise them for feature-specific readability.
    // Dock is a physical-edge affordance. If another higher-priority surface
    // makes that edge slot unavailable, retract it instead of turning it into
    // a floating inner-tier panel.
    property bool placementCanStackInward: identity !== "dock"
    property bool placementCanResize: identity !== "dock"
    property real minimumSpan: Math.min(span, placementCanResize
        ? (largeSurface ? 520 : 220) : span)
    property real minimumDepth: Math.min(depth, placementCanResize
        ? (largeSurface ? 360 : 120) : depth)
    readonly property real waveInfluence: Wave.bodyStrength(Config.options?.abyss?.waves)
    readonly property real mass: Math.max(1,span*depth/90000)
    property bool initialized: false
    property bool open: false
    // Pyramid v2 keeps semantic/input ownership separate from visual residency.
    // Non-popup bodies leave this undefined and retain the original open contract.
    property var semanticOpenOverride: undefined
    readonly property bool semanticOpen:
        semanticOpenOverride === undefined
            ? root.open : Boolean(semanticOpenOverride)
    readonly property bool visualResident:
        root.open || root.progress > 0.001
    readonly property bool acceptsInput:
        root.semanticOpen && root.placementVisible
    // Presentation policy only. The allocator remains a deterministic resting
    // layout producer; animation state is owned outside AbyssBodyPlacement.
    property string stackPolicy: ""
    // A visual origin for nearby Pyramid popups, without entering their
    // area-sorted allocator group. Recording controls keep their Edge slot.
    property bool pyramidAnchor: false
    // Pyramid grouping follows the allocator's normal content-clearance scale.
    // Same-Edge popup intervals that overlap or come within this many logical
    // pixels participate in one visual neighborhood.
    property real stackProximity: 24
    property int activationOrder: 0
    property int placementPriority: identity === "dialog" ? 2 : ["utility","edgeEditor"].includes(identity) ? 1 : identity === "dock" ? -1 : 0
    readonly property var placementMemo: ({})
    readonly property var placement: PlacementMemo.stable(placementMemo,
        controller?.bodyPlacements?.[identity] ?? null)
    readonly property bool placementVisible: placement?.visible !== false
    // A temporarily evicted body retracts using its last valid geometry, keeps
    // its loaded feature/draft, and can reopen in place when space returns.
    property var retainedPlacement: null
    readonly property var layoutPlacement: placementVisible
        ? placement : (retainedPlacement ?? placement)
    readonly property var effectivePlacement: placementVisible
        ? placement : (progress > 0.001 ? retainedPlacement : placement)
    readonly property var pyramidCoordinator:
        root.controller?.pyramidCoordinator ?? null
    readonly property bool pyramidMotionEnabled:
        root.stackPolicy === "pyramid"
        && root.externalProgress >= 0
        && root.pyramidCoordinator !== null
    property bool pyramidClosing: false
    property bool pyramidReopening: false
    property var pyramidOriginRecord: null
    property var pyramidLatchedFullRecord: null
    // Last semantic-open resting state is the close snapshot authority. A QML
    // binding turn may remove the live allocator entry before the semantic
    // change handler runs, so close animation must never depend on that race.
    property var pyramidLastPlacement: null
    property var pyramidLastFullRecord: null
    readonly property var coordinatedPlacement:
        root.pyramidMotionEnabled
            ? root.pyramidCoordinator.targetFor(
                root.identity,root.effectivePlacement)
            : root.effectivePlacement
    // Keep allocator truth discrete, but interpolate its visible geometry. The
    // first placement snaps into place; later peer-induced tier/size changes
    // slide/reflow from the current frame and naturally reverse mid-flight.
    readonly property bool placementMotionReady: retainedPlacement !== null
    property real visualPlacementAlong: Number.isFinite(Number(coordinatedPlacement?.along))
        ? Number(coordinatedPlacement.along) : requestedAlong
    property real visualPlacementSpan: Number.isFinite(Number(coordinatedPlacement?.span))
        ? Number(coordinatedPlacement.span) : span
    property real visualPlacementDepth: Number.isFinite(Number(coordinatedPlacement?.depth))
        ? Number(coordinatedPlacement.depth) : depth
    property real visualPlacementInward: Number.isFinite(Number(coordinatedPlacement?.inward))
        ? Number(coordinatedPlacement.inward) : 0
    readonly property var visualPlacement: coordinatedPlacement
        ? Object.assign({},coordinatedPlacement,{
            along:visualPlacementAlong,
            span:visualPlacementSpan,
            depth:visualPlacementDepth,
            inward:visualPlacementInward
        }) : null
    readonly property bool presented: open && placementVisible
    property real along: 0
    property real span: 380
    property real depth: 320
    property real padding: AbyssStyle.contentPadding
    property var edgeInsets: ({left:8,top:8,right:8,bottom:8})
    property var obstacles: []
    property string source: ""
    property string contentKind: ""
    // External presenters such as StyledPopup own their own reveal fraction.
    // Keep that motion independent from allocator availability: otherwise the
    // host's Behavior would re-animate every incoming reveal frame.
    property real externalProgress: -1
    // Loading is driven by semantic open below. Wait for its content before
    // starting reveal so a cold load cannot consume the animation behind an
    // empty panel; warm content and embedded items remain ready immediately.
    property real availabilityProgress: presented && ready ? 1 : 0
    property real progress: (externalProgress >= 0
        ? Math.max(0,Math.min(1,externalProgress)) : 1) * availabilityProgress
    readonly property var requestedRecord: Geometry.panel(width,height,edgeInsets,edge,requestedAlong,span,depth,1,padding,[],largeSurface)
    // Resting geometry is still produced by AbyssGeometry from allocator output.
    // Pyramid motion only snapshots/interpolates this already-resolved record.
    readonly property var pyramidRestingRecord: Geometry.placedPanel(
        width,height,edgeInsets,edge,requestedAlong,span,depth,1,padding,
        obstacles,largeSurface,visualPlacement)
    readonly property bool pyramidPresentationActive:
        root.pyramidMotionEnabled
        && (root.semanticOpen || root.pyramidClosing
            || root.pyramidReopening || root.progress > 0.001)
    // Entry animation is armed from the allocator's final target, not from
    // visualPlacement while its peer-reflow Behavior may still be in flight.
    // This closes the one-event-loop race where reveal could start from the
    // physical Edge before the lower popup origin had been resolved.
    readonly property var pyramidAllocatorPlacement:
        root.semanticOpen && root.placement?.visible !== false
            ? root.placement : null
    readonly property var pyramidAllocatorRecord:
        root.pyramidAllocatorPlacement
            ? Geometry.placedPanel(width,height,edgeInsets,edge,requestedAlong,span,
                depth,1,padding,obstacles,largeSurface,
                root.pyramidAllocatorPlacement)
            : null
    readonly property var pyramidFullRecord:
        (root.pyramidClosing || root.pyramidReopening)
                && root.pyramidLatchedFullRecord
            ? root.pyramidLatchedFullRecord
            : (!root.semanticOpen && root.pyramidLastFullRecord
                ? root.pyramidLastFullRecord : root.pyramidRestingRecord)
    readonly property var rawPresentationRecord:
        root.pyramidPresentationActive && root.pyramidFullRecord
            ? PyramidMotion.interpolateRecord(
                root.pyramidOriginRecord
                    ?? PyramidMotion.collapsedRecord(
                        root.pyramidFullRecord,null),
                root.pyramidFullRecord,root.progress)
            : Geometry.placedPanel(width,height,edgeInsets,edge,requestedAlong,span,
                depth,progress,padding,obstacles,largeSurface,
                visualPlacement)
    readonly property var record: Geometry.joinCorner(
        rawPresentationRecord,joinedEdge,width,height,edgeInsets)
    readonly property var targetRecord: Geometry.placedPanel(width,height,edgeInsets,edge,requestedAlong,span,depth,1,padding,obstacles,largeSurface,layoutPlacement)
    readonly property Item contentItem: content
    readonly property bool ready: embeddedItem !== null || content.status === Loader.Ready
    readonly property Item contentParent: contentCanvas
    readonly property Item hoverParent: root.includeEdgeConnection ? inputFrame : contentCanvas
    // Placement clearance includes module depth; the painted field's actual
    // seam stays at the physical Edge. Keep the bridge between both interactive.
    readonly property var connectionInsets: root.controller?.edgeInsets ?? root.edgeInsets
    readonly property rect inputBounds: {
        if (!root.acceptsInput || !root.ready) return Qt.rect(0,0,0,0)
        const c=root.record.content
        const contentRect=Qt.rect(c.x,c.y,c.width,c.height)
        if (!root.includeEdgeConnection) return contentRect
        const region=Geometry.popupInput(contentRect,root.width,root.height,
            root.connectionInsets,root.edge,root.rawPresentationRecord.surface)
        return Qt.rect(region.x,region.y,region.width,region.height)
    }
    readonly property rect sourceBridge: {
        if (!root.includeEdgeConnection || !root.acceptsInput || !root.ready)
            return Qt.rect(0,0,0,0)
        const r=Geometry.popupSourceBridge(root.connectionSourceRect,root.inputBounds,
            root.width,root.height,root.connectionInsets,root.edge)
        return Qt.rect(r.x,r.y,r.width,r.height)
    }
    readonly property rect hoverBounds: {
        const body=root.inputBounds,bridge=root.sourceBridge
        if (bridge.width<=0 || bridge.height<=0) return body
        const x=Math.min(body.x,bridge.x),y=Math.min(body.y,bridge.y)
        return Qt.rect(x,y,Math.max(body.x+body.width,bridge.x+bridge.width)-x,
            Math.max(body.y+body.height,bridge.y+bridge.height)-y)
    }
    readonly property var connectionRects: root.includeEdgeConnection
            && root.inputBounds.width > 0 && root.inputBounds.height > 0
        ? Geometry.popupShouldersSnapshot(root.width,root.height,root.connectionInsets,root.edge,
            root.rawPresentationRecord,AbyssStyle.perimeterRadius,
            AbyssStyle.connectionDepth,AbyssStyle.neckRadius,
            root.controller?.roundZeroCorners,root.controller?.cornerWidthInsets) : []
    property var connectionRegions: []
    // Instantiator creates/removes a synchronous cohort. Publish its complete
    // native region list once, before returning to input dispatch, rather than
    // rebuilding the composite mask after each individual shoulder strip.
    readonly property var connectionRegionState: ({objects: []})
    function publishConnectionRegions(): void {
        const objects=root.connectionRegionState.objects
        if(objects.length!==root.connectionRects.length)return
        for(let i=0;i<objects.length;i++)if(!objects[i])return
        root.connectionRegions=objects.slice()
    }
    readonly property Region nativeInputRegion: Region {
        Region {
            x: Math.floor(root.inputBounds.x); y: Math.floor(root.inputBounds.y)
            width: root.inputBounds.width > 0
                ? Math.ceil(root.inputBounds.x+root.inputBounds.width)-x : 0
            height: root.inputBounds.height > 0
                ? Math.ceil(root.inputBounds.y+root.inputBounds.height)-y : 0
        }
        Region { regions: root.connectionRegions }
        Region {
            x: Math.floor(root.sourceBridge.x); y: Math.floor(root.sourceBridge.y)
            width: root.sourceBridge.width>0 ? Math.ceil(root.sourceBridge.x+root.sourceBridge.width)-x : 0
            height: root.sourceBridge.height>0 ? Math.ceil(root.sourceBridge.y+root.sourceBridge.height)-y : 0
        }
    }
    Instantiator {
        // Reuse Region identities while the strip count is stable; unload on close.
        model: root.connectionRects.length
        delegate: Region {
            required property int index
            readonly property var rect: root.connectionRects[index] ?? null
            x: rect?.x ?? 0; y: rect?.y ?? 0
            width: rect?.width ?? 0; height: rect?.height ?? 0
        }
        onObjectAdded: (index,object) => {
            root.connectionRegionState.objects[index]=object
            root.publishConnectionRegions()
        }
        onObjectRemoved: (index,object) => {
            const objects=root.connectionRegionState.objects
            const at=objects.indexOf(object)
            if(at>=0)objects.splice(at,1)
            root.publishConnectionRegions()
        }
    }
    signal closeRequested()
    AbyssParticipant {
        id: participant
        identity: root.identity
        controller: root.controller
        geometry: root.record
        restingRecord: root.pyramidRestingRecord
        visualPlacement: root.visualPlacement
        surfaceSettled: root.presented && root.ready && Math.abs(root.progress-1) < .001
            && !root.pyramidClosing && !root.pyramidReopening
            && Math.abs(root.visualPlacementAlong-(root.coordinatedPlacement?.along ?? root.requestedAlong))<.1
            && Math.abs(root.visualPlacementSpan-(root.coordinatedPlacement?.span ?? root.span))<.1
            && Math.abs(root.visualPlacementDepth-(root.coordinatedPlacement?.depth ?? root.depth))<.1
            && Math.abs(root.visualPlacementInward-(root.coordinatedPlacement?.inward ?? 0))<.1
        vacancyRole: root.vacancyRole
        vacancyHovered: root.vacancyHovered
        vacancyHoverOrder: root.vacancyHoverOrder
        placementRequest: ({id:root.identity,open:root.semanticOpen,order:root.activationOrder,
            priority:root.placementPriority,padding:root.padding,
            minSpan:root.minimumSpan,minDepth:root.minimumDepth,
            allowInward:root.placementCanStackInward,
            minimumInward:root.minimumInward,
            stackPolicy:root.stackPolicy,
            pyramidAnchor:root.pyramidAnchor,
            stackProximity:root.stackProximity,
            record:root.requestedRecord})
        inputBounds: root.inputBounds
        nativeInputRegion: root.includeEdgeConnection ? root.nativeInputRegion : null
        mass: root.mass
    }
    function react(opening): void {
        if (controller) controller.impulse(edge,along+span/2,span,(opening ? 0.85 : -0.65)*waveInfluence,mass,opening ? "open" : "close")
    }
    function markOpened(): void { if (open && controller?.nextPresentationOrder) activationOrder=controller.nextPresentationOrder() }
    function refreshVacancyInteraction(): void {
        if (!root.vacancyHovered || root.vacancyRole.length === 0) {
            root.vacancyHoverOrder = 0
            return
        }
        if (root.controller?.nextVacancyInteractionOrder)
            root.vacancyHoverOrder = root.controller.nextVacancyInteractionOrder()
    }
    function resetPyramidMotion(): void {
        root.pyramidCoordinator?.resetIdentity(root.identity)
        root.pyramidClosing=false
        root.pyramidReopening=false
        root.pyramidOriginRecord=null
        root.pyramidLatchedFullRecord=null
        root.pyramidLastPlacement=null
        root.pyramidLastFullRecord=null
    }
    function capturePyramidRestingState(): void {
        if (!root.pyramidMotionEnabled || !root.semanticOpen
                || root.pyramidClosing || root.pyramidReopening
                || !root.visualPlacement || !root.pyramidRestingRecord)
            return
        root.pyramidLastPlacement=
            PyramidMotion.clonePlacement(root.visualPlacement)
        root.pyramidLastFullRecord=
            PyramidMotion.cloneRecord(root.pyramidRestingRecord)
    }
    function resetPresentationOwner(): void {
        // Stable hosts may be reused by a different semantic popup owner.
        // Clear the previous allocator snapshot while the old owner is hidden so
        // the next owner snaps to its own tangent anchor before reveal starts.
        root.retainedPlacement=null
        root.resetPyramidMotion()
    }
    function syncPyramidEntryOrigin(): void {
        if (!root.pyramidMotionEnabled || !root.semanticOpen
                || root.pyramidClosing || root.pyramidReopening
                || !root.pyramidAllocatorPlacement
                || !root.pyramidAllocatorRecord)
            return
        // Once reveal has actually started, the origin is part of that visual
        // transaction. Peer reflow may change the final resting placement, but
        // rewriting the origin mid-flight would create a visible discontinuity.
        if (root.pyramidOriginRecord && root.progress > 0.001)
            return
        const origin=root.pyramidCoordinator?.entryOrigin(
            root.identity,participant.placementRequest,
            root.pyramidAllocatorPlacement,root.pyramidAllocatorRecord)
        if (origin)
            root.pyramidOriginRecord=origin
    }
    function syncPyramidSemanticState(): void {
        if (!root.pyramidMotionEnabled)
            return
        if (root.semanticOpen) {
            if (root.pyramidClosing) {
                // Reopen is a phase reversal of this exact visual transaction.
                // Keep this popup's O/F snapshots until progress returns to 1.
                // Surviving peers independently follow live allocator targets.
                root.pyramidCoordinator?.beginReopen(root.identity)
                root.pyramidClosing=false
                root.pyramidReopening=true
                root.finishPyramidReopenIfDone()
                return
            }
            root.syncPyramidEntryOrigin()
            return
        }
        if (root.pyramidReopening) {
            // A second close during reversal flips phase only. The same O/F
            // snapshots remain authoritative, so no visible path can jump.
            root.pyramidCoordinator?.resumeClose(root.identity)
            root.pyramidReopening=false
            root.pyramidClosing=true
            root.finishPyramidCloseIfDone()
            return
        }
        const closingPlacement=root.pyramidLastPlacement
            ?? root.visualPlacement
        const closingRecord=root.pyramidLastFullRecord
            ?? root.pyramidRestingRecord
        if (!closingPlacement || !closingRecord)
            return
        root.pyramidLatchedFullRecord=
            PyramidMotion.cloneRecord(closingRecord)
        root.pyramidOriginRecord=root.pyramidCoordinator?.beginClose(
            root.identity,participant.placementRequest,
            closingPlacement,root.pyramidLatchedFullRecord)
            ?? PyramidMotion.collapsedRecord(
                root.pyramidLatchedFullRecord,null)
        root.pyramidClosing=true
        // With reduced/disabled motion the owner may already have driven
        // externalProgress to zero before this semantic handler runs. Finish
        // synchronously so the group freeze cannot survive without another
        // progress change to wake it.
        root.finishPyramidCloseIfDone()
    }
    function finishPyramidCloseIfDone(): void {
        if (!root.initialized || !root.pyramidClosing
                || root.semanticOpen || root.progress > 0.001)
            return
        root.pyramidCoordinator?.finishClose(root.identity)
        root.pyramidClosing=false
        root.pyramidLatchedFullRecord=null
        root.pyramidOriginRecord=null
    }
    function finishPyramidReopenIfDone(): void {
        if (!root.initialized || !root.pyramidReopening
                || !root.semanticOpen || root.progress < 0.999)
            return
        root.pyramidCoordinator?.finishReopen(root.identity)
        root.pyramidReopening=false
        root.pyramidLatchedFullRecord=null
        root.pyramidOriginRecord=null
        root.capturePyramidRestingState()
    }
    onPlacementChanged: {
        if (placement?.visible !== false)
            retainedPlacement = placement
        if (initialized && semanticOpen && pyramidMotionEnabled
                && !pyramidClosing && !pyramidReopening) {
            root.capturePyramidRestingState()
            root.syncPyramidEntryOrigin()
        }
    }
    onPyramidAllocatorRecordChanged: if (initialized
            && semanticOpen && !pyramidClosing && !pyramidReopening)
        root.syncPyramidEntryOrigin()
    onPyramidRestingRecordChanged: if (initialized)
        root.capturePyramidRestingState()
    onVisualPlacementChanged: if (initialized)
        root.capturePyramidRestingState()
    onSemanticOpenChanged: if (initialized)
        root.syncPyramidSemanticState()
    onVacancyHoveredChanged: root.refreshVacancyInteraction()
    onVacancyRoleChanged: root.refreshVacancyInteraction()
    onProgressChanged: {
        root.finishPyramidCloseIfDone()
        root.finishPyramidReopenIfDone()
    }
    onOpenChanged: if (initialized) { markOpened();react(open) }
    onEmbeddedItemChanged: if (initialized) markOpened()
    onContentKindChanged: if (initialized) markOpened()
    onControllerChanged: if (initialized) {
        root.resetPyramidMotion()
        markOpened()
        root.refreshVacancyInteraction()
    }
    Component.onCompleted: {
        initialized = true
        markOpened()
        root.refreshVacancyInteraction()
        if (semanticOpen) {
            root.capturePyramidRestingState()
            root.syncPyramidEntryOrigin()
        }
        if (open) Qt.callLater(() => { if (root.open) root.react(true) })
    }
    property int escapeKeyCount: 0
    Keys.onEscapePressed: event => {
        root.escapeKeyCount++
        // Escape bubbling out of a Dashboard widget must cancel its editable
        // draft before the generic body host requests a window close. A child
        // can own activeFocus, bypassing the perimeter's outer key handler.
        const dashboard = root.identity === "dashboard" ? content.item : null
        if ((dashboard?.editMode ?? false)
                && typeof dashboard.handleEscape === "function"
                && dashboard.handleEscape()) {
            event.accepted = true
            return
        }
        root.closeRequested()
        event.accepted = true
    }
    Behavior on visualPlacementAlong {
        enabled: root.animatePlacementChanges && root.placementMotionReady
            && AbyssStyle.motionEnabled
        NumberAnimation {
            duration: AbyssStyle.motionNormal
            easing.type: root.pyramidMotionEnabled
                ? Easing.InOutCubic : Easing.OutCubic
        }
    }
    Behavior on visualPlacementSpan {
        enabled: root.animatePlacementChanges && root.placementMotionReady
            && AbyssStyle.motionEnabled
        NumberAnimation {
            duration: AbyssStyle.motionNormal
            easing.type: root.pyramidMotionEnabled
                ? Easing.InOutCubic : Easing.OutCubic
        }
    }
    Behavior on visualPlacementDepth {
        enabled: root.animatePlacementChanges && root.placementMotionReady
            && AbyssStyle.motionEnabled
        NumberAnimation {
            duration: AbyssStyle.motionNormal
            easing.type: root.pyramidMotionEnabled
                ? Easing.InOutCubic : Easing.OutCubic
        }
    }
    Behavior on visualPlacementInward {
        enabled: root.animatePlacementChanges && root.placementMotionReady
            && AbyssStyle.motionEnabled
        NumberAnimation {
            duration: AbyssStyle.motionNormal
            easing.type: root.pyramidMotionEnabled
                ? Easing.InOutCubic : Easing.OutCubic
        }
    }
    Behavior on availabilityProgress {
        id: availabilityMotion
        enabled: root.animatePresentation && AbyssStyle.motionEnabled
            && !root.singleExternalReveal
        SequentialAnimation {
            NumberAnimation {
                to: availabilityMotion.targetValue > 0
                    ? availabilityMotion.targetValue
                        + (root.monotonicNotificationReveal ? 0 : AbyssStyle.motionOvershoot)
                    : 0
                duration: root.monotonicNotificationReveal
                    ? AbyssStyle.motionNormal
                    : Math.round(AbyssStyle.motionNormal
                        *(1+Math.min(0.5,Math.sqrt(root.mass)*0.1)))
                // An accelerating InCubic retract has maximum velocity at its
                // last pixel and then stops abruptly. Only short notification
                // banners get a zero-velocity exit; every other body keeps
                // its existing easing and duration.
                easing.type: root.monotonicNotificationReveal && !root.presented
                    ? Easing.InOutSine
                    : (root.presented ? Easing.OutCubic : Easing.InCubic)
            }
            NumberAnimation {
                to: availabilityMotion.targetValue
                duration: !root.monotonicNotificationReveal
                    && root.presented && AbyssStyle.motionOvershoot > 0
                    ? Math.round(AbyssStyle.motionSettle
                        *(1+Math.min(0.5,Math.sqrt(root.mass)*0.1))) : 0
                easing.type: Easing.OutCubic
            }
        }
    }
    Item {
        id: inputFrame
        readonly property real shoulderReach: root.connectionRects.length > 0
            ? Math.ceil(Math.max(AbyssStyle.connectionDepth,
                root.rawPresentationRecord.radius ?? AbyssStyle.neckRadius))+1 : 0
        x: root.hoverBounds.x-(Geometry.horizontal(root.edge) ? shoulderReach : 0)
        y: root.hoverBounds.y-(Geometry.horizontal(root.edge) ? 0 : shoulderReach)
        width: root.hoverBounds.width+(Geometry.horizontal(root.edge) ? 2*shoulderReach : 0)
        height: root.hoverBounds.height+(Geometry.horizontal(root.edge) ? 0 : 2*shoulderReach)
        enabled: root.acceptsInput && root.ready
        containmentMask: QtObject {
            function contains(point: point): bool {
                const x=point.x+inputFrame.x,y=point.y+inputFrame.y
                if ((root.controller?.sourceInputRegions ?? []).some(
                        rect=>Geometry.rectContains(rect,x,y))) return false
                return Geometry.rectContains(root.inputBounds,x,y)
                    || Geometry.rectContains(root.sourceBridge,x,y)
                    || root.connectionRects.some(rect=>Geometry.rectContains(rect,x,y))
            }
        }
    }
    Item {
        id: contentFrame
        // The body/bridge hover plane must be an ancestor of interactive
        // contents. A sibling behind MouseAreas loses hover when they consume
        // it, incorrectly starting the popup's dismissal timer.
        parent: root.includeEdgeConnection ? inputFrame : root
        x: root.record.content.x-(root.includeEdgeConnection ? inputFrame.x : 0)
        y: root.record.content.y-(root.includeEdgeConnection ? inputFrame.y : 0)
        width: root.pyramidPresentationActive
            ? root.record.content.width
            : (root.placementVisible
                ? root.record.content.width : root.targetRecord.content.width)
        height: root.pyramidPresentationActive
            ? root.record.content.height
            : (root.placementVisible
                ? root.record.content.height : root.targetRecord.content.height)
        clip: true
        visible: (!root.warmContent || root.visualResident) && (root.pyramidPresentationActive
            ? (root.semanticOpen || root.progress > 0.001)
            : (root.placementVisible || root.progress > 0.001))
        // Pyramid uses the same pure slide-under principle as StyledPopup:
        // content remains full-size behind a moving clip; it never fades/shrinks.
        // Transient notifications slide under the Edge clip without the
        // separate end-loaded fade (previously ~70ms at default settings).
        opacity: root.pyramidPresentationActive || root.monotonicNotificationReveal
            ? 1 : Math.min(1,root.progress*1.5)
        enabled: root.acceptsInput

        // Actual rendered-body hover; source anchors/physical edges never grant
        // vacancy ownership.
        HoverHandler {
            id: vacancyBodyHover
            parent: contentFrame
            enabled: root.vacancyRole.length > 0
                && contentFrame.visible && contentFrame.enabled
        }

        Item {
            id: contentCanvas
            readonly property var fullRect:
                root.pyramidFullRecord?.content ?? root.targetRecord.content
            x: root.pyramidPresentationActive
                ? fullRect.x-root.record.content.x : 0
            y: root.pyramidPresentationActive
                ? fullRect.y-root.record.content.y : 0
            // Reparented dialogs use this canvas directly instead of the
            // Loader. Both paths must keep their final dimensions behind the
            // reveal clip; otherwise the dialog form reflows on every frame.
            width: root.pyramidPresentationActive
                ? fullRect.width : (root.stableContentSize
                    ? root.targetRecord.content.width : contentFrame.width)
            height: root.pyramidPresentationActive
                ? fullRect.height : (root.stableContentSize
                    ? root.targetRecord.content.height : contentFrame.height)
        }
    }
    Loader {
        id: content
        parent: contentCanvas
        x: 0; y: 0
        // Reveal clips/slides a fixed-size content canvas. Icons, labels and
        // controls retain their dimensions throughout opening/closing/reversal.
        width: root.pyramidPresentationActive
            ? contentCanvas.width
            : (root.stableContentSize
                ? root.targetRecord.content.width : contentFrame.width)
        height: root.pyramidPresentationActive
            ? contentCanvas.height
            : (root.stableContentSize
                ? root.targetRecord.content.height : contentFrame.height)
        // A space-constrained body retains drafts/focus state while hidden. It
        // unloads only after a semantic close and completion of the reveal.
        active: !root.embeddedItem
            && (root.residentContent || root.visualResident || root.warmHeld)
            && GlobalStates.deferredPanelsReady
        source: root.source
        clip: true
        opacity: 1
        enabled: root.acceptsInput
        onLoaded: {
            root.warmHeld = root.warmContent && root.visualResident
            if (item.participant !== undefined) item.participant = root
            if (item.outputName !== undefined) item.outputName = Qt.binding(() => root.outputName)
            if (item.kind !== undefined) item.kind = Qt.binding(() => root.contentKind)
            if (item.edge !== undefined) item.edge = Qt.binding(() => root.edge)
            if (item.closeRequested !== undefined) item.closeRequested.connect(root.closeRequested)
        }
    }
}
