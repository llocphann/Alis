pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.perimeter
import qs.modules.bar as Bar
import qs.services
import qs.modules.waffle.looks as WaffleLooks
import QtQuick
import Quickshell
import Quickshell.Wayland

// Physical Screen Edge renderer.
//
// SCREEN-EDGE-GEOMETRY-LOCK (maintainer approved 2026-09-19):
// BAR-SCREEN-EDGE-CORNER-LOCK (maintainer approved 2026-09-19):
// The current Screen Edge + normal ii Bar silhouette is the canonical Alis
// physical perimeter. Screen Edge and Bar endpoint corners are one geometry:
// the single inverted rounded workspace hole below. Future refactors must keep
// this exact ownership/placement/path model. The only approved visual degree of
// freedom is PerimeterTokens.frameRadius (user setting). If any later change
// distorts top/bottom/left/right corners, restore this model rather than adding
// Bar-local radii, RoundCorner wedges, edge patches or a second renderer.
// Change either lock only with explicit maintainer approval.
//
// Caelestia does not build its border from four strips plus corner patches.
// Its idle border is one inverted rounded rectangle: the window bounds are the
// outer rect and the workspace is one rounded inner hole. Alis preserves
// that exact geometry in the texture-free ScreenEdgeField analytic SDF. The
// historical ShapePath / OddEvenFill + MultiEffect renderer remains only as a
// lazy ShaderEffect.Error fallback. The four thin ReservationWindow surfaces
// below are transparent and exist only to reserve compositor work-area space;
// they do not paint any Screen Edge pixels.
Scope {
    id: root

    // Caelestia BorderConfig defaults: thickness=10, rounding=25. The
    // maintainer-approved geometry model stays locked, while the radius itself
    // is now the shared user-adjustable perimeter token.
    readonly property int thickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
    readonly property real rounding: PerimeterTokens.frameRadius

    // Public Screen Edge shadow controls also drive ii Bar StyledPopup depth.
    // Do not reuse appearance.screenEdge.shadow here: that older key remains
    // for Sidebar/Dashboard/Settings/OSK connected-body shadows.
    readonly property bool physicalShadowEnabled:
        Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
    readonly property int physicalShadowSize: Math.max(0, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
    readonly property real physicalShadowOpacity: Math.max(0, Math.min(1.0,
        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))

    // Caelestia's BlobInvertedRect extends 50px beyond the ContentWindow so the
    // visible outer screen boundary is clipped by the window rather than by an
    // antialiased shape edge. Keep the same construction.
    readonly property int outerPadding: 50

    readonly property bool waffleFamily:
        (Config.options?.panelFamily ?? "ii") === "waffle"
    readonly property bool barVertical: Config.options?.bar?.vertical ?? false
    readonly property string iiBarEdge: barVertical
        ? ((Config.options?.bar?.bottom ?? false) ? "right" : "left")
        : ((Config.options?.bar?.bottom ?? false) ? "bottom" : "top")
    readonly property string iiBarPanelId:
        barVertical ? "iiVerticalBar" : "iiBar"
    readonly property bool iiBarPanelEnabled:
        (Config.options?.enabledPanels ?? []).includes(iiBarPanelId)
    readonly property string waffleBarEdge:
        (Config.options?.waffles?.bar?.bottom ?? false) ? "bottom" : "top"
    readonly property bool waffleBarPanelEnabled: root.waffleFamily
        && (Config.options?.enabledPanels ?? []).includes("wBar")

    readonly property color edgeColor: root.waffleBarPanelEnabled
        ? WaffleLooks.Looks.colors.bg0
        : Appearance.colors.colLayer0

    function targetsOutput(outputName, configuredList) {
        if (outputName.length === 0)
            return false
        const list = configuredList ?? []
        if (!list || list.length === 0)
            return true
        let hasConfiguredOutput = false
        // Preserve the old filter callback's complete screen/name read order so
        // QML dependency capture stays identical, but avoid allocating a result
        // array that was used only for its length.
        for (const screen of Quickshell.screens) {
            const screenName = String(screen?.name ?? "")
            if (screenName.length > 0 && list.includes(screenName))
                hasConfiguredOutput = true
        }
        if (!hasConfiguredOutput)
            return true
        return list.includes(outputName)
    }

    function iiBarTargetsOutput(outputName) {
        return root.targetsOutput(outputName,
            Config.options?.bar?.screenList ?? [])
    }

    function waffleBarTargetsOutput(outputName) {
        return root.targetsOutput(outputName,
            Config.options?.waffles?.bar?.screenList ?? [])
    }

    function iiBarOwnsEdge(outputName, edge) {
        if (!GlobalStates.barOpen || GlobalStates.widgetEditMode)
            return false

        // Auto-hide deliberately hands the physical edge back to ScreenEdges so
        // the persistent frame remains the visible baseline while the Bar moves.
        return !root.waffleFamily
            && root.iiBarPanelEnabled
            && !(Config.options?.bar?.autoHide?.enable ?? false)
            && edge === root.iiBarEdge
            && root.iiBarTargetsOutput(outputName)
    }

    function barOwnsEdge(outputName, edge) {
        if (!GlobalStates.barOpen || GlobalStates.widgetEditMode)
            return false

        const iiOwned = root.iiBarOwnsEdge(outputName, edge)
        const waffleOwned = root.waffleBarPanelEnabled
            && edge === root.waffleBarEdge
            && root.waffleBarTargetsOutput(outputName)
        return iiOwned || waffleOwned
    }

    component FrameWindow: PanelWindow {
        id: frameWindow

        required property ShellScreen modelData

        readonly property string outputName: String(modelData?.name ?? "")
        readonly property bool fullscreenCovered: outputName.length > 0
            && GameMode.hasFullscreenOnOutput(outputName)
        // FULLSCREEN-SCREEN-EDGE-LIFECYCLE-LOCK (maintainer approved 2026-09-19):
        // This painted FrameWindow must stay mapped across fullscreen just like
        // the ii Bar. Quickshell destroys layer-shell windows when visible=false;
        // recreating this Top-layer frame after fullscreen changes same-layer
        // stacking and can place the Bar-thick physical frame above BarContent.
        // Niri already renders a focused fullscreen client above Top layer.
        // Transparent ReservationWindows below may still release their work area.
        readonly property bool mapped: Config.ready
            && !GlobalStates.screenLocked

        // LOCKED BAR/SCREEN-EDGE INSETS:
        // Caelestia treats the Bar as a thicker side of the same inverted
        // border. When a normal ii Bar owns an edge, only that one inset changes
        // from Screen Edge thickness to the real Bar body thickness. These four
        // formulas are part of BAR-SCREEN-EDGE-CORNER-LOCK and must remain
        // orientation-symmetric. No Bar-local corner paint may replace them.
        readonly property real frameLeftInset:
            root.iiBarOwnsEdge(outputName, "left")
                ? Appearance.sizes.verticalBarWidth : root.thickness
        readonly property real frameRightInset:
            root.iiBarOwnsEdge(outputName, "right")
                ? Appearance.sizes.verticalBarWidth : root.thickness
        readonly property real frameTopInset:
            root.iiBarOwnsEdge(outputName, "top")
                ? Appearance.sizes.barHeight : root.thickness
        readonly property real frameBottomInset:
            root.iiBarOwnsEdge(outputName, "bottom")
                ? Appearance.sizes.barHeight : root.thickness

        screen: modelData
        visible: mapped
        // Preserve the mapped layer-shell surface across fullscreen for stable
        // stacking, but suspend its scenegraph while the fullscreen client
        // completely covers the physical frame.
        updatesEnabled: mapped && !fullscreenCovered
        color: "transparent"
        // Visual host must ignore all exclusive zones and remain pinned to the
        // physical output bounds, matching Caelestia ContentWindow.
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "alis:screen-edge-frame"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Item {
            id: emptyFrameInput
            width: 0
            height: 0
            visible: false
        }
        mask: Region { item: emptyFrameInput }

        readonly property bool physicalShadowActive:
            root.physicalShadowEnabled
            && root.physicalShadowSize > 0
            && root.physicalShadowOpacity > 0
            && !frameWindow.fullscreenCovered
            && !Appearance.gameModeMinimal

        // Primary physical Screen Edge painter: one output-local analytic SDF
        // pass. It draws the exact rounded workspace hole plus inward elevation
        // without any source capture, blur pyramid or texture sampling.
        ScreenEdgeField {
            id: frameField
            anchors.fill: parent
            visible: !frameWindow.fullscreenCovered
            leftInset: frameWindow.frameLeftInset
            topInset: frameWindow.frameTopInset
            rightInset: frameWindow.frameRightInset
            bottomInset: frameWindow.frameBottomInset
            radius: root.rounding
            edgeColor: root.edgeColor
            elevationColor: Qt.alpha(
                Appearance.m3colors.m3shadow,
                root.physicalShadowOpacity)
            elevationSize: root.physicalShadowSize
            elevationEnabled: frameWindow.physicalShadowActive
        }

        // Fail-safe only. Keep the legacy Shapes/Effects implementation in a
        // separately loaded file so the healthy analytic path does not import
        // or parse that renderer/type graph at startup.
        Loader {
            id: legacyFramePainter
            anchors.fill: parent

            // Keep only object references resident on the healthy path. All
            // legacy value bindings are created inside the fallback file only
            // after an actual ShaderEffect error.
            readonly property var edgeRoot: root
            readonly property var frameHost: frameWindow

            active: frameField.shaderError
                && !frameWindow.fullscreenCovered
            source: active
                ? Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml") : ""
        }
    }

    // Transparent compositor reservation only. ScreenEdge pixels are never
    // painted here, so these windows cannot alter the frame/corner silhouette.
    component ReservationWindow: PanelWindow {
        id: reservationWindow

        required property ShellScreen modelData
        required property string edge

        readonly property string outputName: String(modelData?.name ?? "")
        readonly property bool horizontal: edge === "top" || edge === "bottom"
        readonly property bool fullscreenCovered: outputName.length > 0
            && GameMode.hasFullscreenOnOutput(outputName)
        readonly property bool workspaceOverviewEdgeSupportEnabled:
            edge === "top"
            && root.barVertical
            && !root.waffleFamily
            && root.iiBarPanelEnabled
            && root.iiBarTargetsOutput(outputName)
            && (Config.options?.overview?.workspaceHover?.enable ?? true)
        readonly property bool workspaceOverviewEdgeTriggerEnabled:
            workspaceOverviewEdgeSupportEnabled
            && GlobalStates.barOpen
            && !GlobalStates.widgetEditMode
        readonly property bool mapped: Config.ready
            && !GlobalStates.screenLocked
            && !fullscreenCovered
            && !root.barOwnsEdge(outputName, edge)

        screen: modelData
        visible: mapped
        // Reservation surfaces paint nothing. Only the optional top-edge
        // workspace-hover support needs render updates; exclusive-zone,
        // mapping and input-mask state remain live independently.
        updatesEnabled: mapped && workspaceOverviewEdgeSupportEnabled
        color: "transparent"
        // Reservation surfaces intentionally participate in normal layer-shell
        // exclusion. Do not set Ignore here: their only job is to reserve the
        // configured Screen Edge thickness for client windows.
        exclusiveZone: mapped ? root.thickness : 0

        implicitWidth: horizontal ? 1 : root.thickness
        implicitHeight: horizontal ? root.thickness : 1

        WlrLayershell.namespace: "alis:screen-edge-reservation-" + edge
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: edge === "top" || edge === "left" || edge === "right"
            bottom: edge === "bottom" || edge === "left" || edge === "right"
            left: edge === "left" || edge === "top" || edge === "bottom"
            right: edge === "right" || edge === "top" || edge === "bottom"
        }

        Item {
            id: emptyReservationInput
            width: 0
            height: 0
            visible: false
        }

        Loader {
            id: workspaceOverviewSupport
            anchors.fill: parent
            // In the common horizontal-Bar configuration this remains
            // completely unloaded. Bottom/left/right reservations can never
            // satisfy the support gate either, so they retain no hover timer,
            // hit area or StyledPopup/Overview object graph.
            active: reservationWindow.workspaceOverviewEdgeSupportEnabled
            sourceComponent: Component {
                Item {
                    id: overviewSupport
                    property alias hitArea: workspaceOverviewHitArea

                    function closeOverview(): void {
                        workspaceEdgeOverview.close()
                    }

                    MouseArea {
                        id: workspaceOverviewHitArea
                        anchors.fill: parent
                        enabled:
                            reservationWindow.workspaceOverviewEdgeTriggerEnabled
                        hoverEnabled: enabled
                        acceptedButtons: Qt.NoButton
                        onContainsMouseChanged: {
                            if (containsMouse && enabled)
                                workspaceOverviewHoverDelay.restart()
                            else
                                workspaceOverviewHoverDelay.stop()
                        }
                    }

                    Timer {
                        id: workspaceOverviewHoverDelay
                        interval:
                            Config.options?.overview?.workspaceHover?.delayMs
                            ?? 280
                        repeat: false
                        onTriggered: {
                            if (reservationWindow.workspaceOverviewEdgeTriggerEnabled
                                    && workspaceOverviewHitArea.containsMouse)
                                workspaceEdgeOverview.showWorkspace(
                                    null, workspaceOverviewHitArea)
                        }
                    }

                    Bar.BarWorkspaceOverview {
                        id: workspaceEdgeOverview
                        dockHovered:
                            reservationWindow.workspaceOverviewEdgeTriggerEnabled
                            && workspaceOverviewHitArea.containsMouse
                        barPosition: "top"
                        attachmentThickness: root.thickness
                    }
                }
            }
        }

        onWorkspaceOverviewEdgeTriggerEnabledChanged: {
            if (!workspaceOverviewEdgeTriggerEnabled)
                workspaceOverviewSupport.item?.closeOverview()
        }

        mask: Region {
            item: reservationWindow.workspaceOverviewEdgeTriggerEnabled
                ? (workspaceOverviewSupport.item?.hitArea
                    ?? emptyReservationInput)
                : emptyReservationInput
        }
    }

    Variants {
        model: Quickshell.screens
        FrameWindow {}
    }

    Variants {
        model: Quickshell.screens
        ReservationWindow { edge: "top" }
    }
    Variants {
        model: Quickshell.screens
        ReservationWindow { edge: "bottom" }
    }
    Variants {
        model: Quickshell.screens
        ReservationWindow { edge: "left" }
    }
    Variants {
        model: Quickshell.screens
        ReservationWindow { edge: "right" }
    }
}
