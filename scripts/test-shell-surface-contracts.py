#!/usr/bin/env python3
"""Regression checks for shell surface, dock, Waffle, and English-only contracts."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
failures = []


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def main() -> None:
    readme = read("README.md")
    check("### 2.1 Locked ownership contract — single Caelestia-style inverted frame" in readme
          and "Normal Bar mode owns only the Bar body" in readme
          and "`scripts/test-shell-surface-contracts.py` is the regression gate" in readme,
          "README must retain the maintainer-approved single-owner perimeter contract")

    styled_popup = read("modules/bar/StyledPopup.qml")
    abyss_frame = read("modules/common/perimeter/ConnectedSurfaceAbyssFrame.qml")
    abyss_edge_surface = read("modules/common/perimeter/ConnectedSurfaceAbyssEdgeSurface.qml")
    for token in (
        "qs.modules.common.perimeter",
        "ConnectedSurfaceGeometry",
        "ConnectedSurfaceAbyssFrame",
        "ConnectedSurfaceRevealClip",
        "ConnectedSurfaceContentHost",
        "ConnectedSurfaceBodyMask",
        "mask: connectedMask",
        "ExclusionMode.Ignore",
        "Appearance.colors.colLayer0",
        "PerimeterTokens.popupRadius",
        "CompositorFocusGrab",
        "WlrKeyboardFocus.OnDemand",
        "requestedVisible",
        "_lingerVisible",
        "retractTimer",
        "progress: root.revealProgress",
        "property real offsetScale: 1",
        "readonly property real revealProgress: 1 - root.offsetScale",
        "Behavior on offsetScale",
        "|| root.popupHovered",
        "enabled: root.active",
    ):
        check(token in styled_popup, f"StyledPopup must preserve connected-perimeter contract: {token}")
    for edge in ("top", "bottom", "left", "right"):
        check(f'"{edge}"' in styled_popup,
              f"StyledPopup must preserve {edge} attachment handling")
    check("Appearance.colors.colSurfaceContainer" not in styled_popup,
          "Connected bar popups must use the owning bar surface family, not the detached popup-card material")
    check("root._anchorReady" in styled_popup
          and "root.requestedVisible || root._lingerVisible" in styled_popup,
          "Connected popout loader must require a real anchor and stay resident long enough to retract into it")
    check("cornerStyle" not in styled_popup,
          "Connected bar popouts must not branch on retired Classic Bar corner styles")
    check("Appearance.zzz.chromeAlt" not in styled_popup
          and "Appearance.regalia.barSurfaceFloating" not in styled_popup,
          "Connected bar popouts must use the Hug surface family only")

    for token in (
        "property real ownerPaintOverlap: 0",
        "root.clipExternalOwners(root.rawPaintBounds, root.ownerPaintOverlap)",
        "root.clipExternalOwners(root.body, 0)",
        "root.clipExternalOwners(root.rawShadowBounds, 0)",
    ):
        check(token in abyss_frame,
              f"Abyss paint-only owner overlap contract missing: {token}")
    check("property real paintOverlap: 0" in abyss_edge_surface
          and "ownerPaintOverlap: root.paintOverlap" in abyss_edge_surface,
          "Direct Abyss edge adapter must expose opt-in paint-only seam overlap")
    check("property real tangentFrameThickness: ownerThickness" in abyss_edge_surface
          and "externalFrameThickness: root.tangentFrameThickness" in abyss_edge_surface,
          "Direct Abyss edge adapter must separate primary-owner and tangent-frame thickness")

    perimeter_tokens = read("modules/common/perimeter/PerimeterTokens.qml")
    for token in (
        "const revision = Config.revision",
        "Config.options?.appearance?.screenEdge?.radius ?? 25",
        "Math.max(0, Math.min(96",
        "readonly property real abyssFuseDepth: 30",
        "readonly property real abyssWeldDepth: 3",
        "readonly property real popupRadius: 28",
    ):
        check(token in perimeter_tokens,
              f"Perimeter geometry token missing: {token}")
    check("attachedCornerRadius" not in perimeter_tokens,
          "Connected surfaces must not reintroduce inward attached-body corner rounding")

    geometry = read("modules/common/perimeter/ConnectedSurfaceGeometry.qml")
    for edge in ("top", "bottom", "left"):
        check(f'edge === "{edge}"' in geometry,
              f"ConnectedSurfaceGeometry missing {edge} edge handling")
    check("PerimeterTopology.edges.includes(edge)" in geometry,
          "ConnectedSurfaceGeometry must validate the implicit right-edge fallback through shared topology")
    for token in (
        "seamOverlap",
        "effectiveSeamOverlap",
        "devicePixelRatio",
        "function pixelScale()",
        "function snap(",
        "connectorSourceExtent",
        "connectorBodyExtent",
        "animatedTangentExtent",
        "animatedCrossExtent",
        "revealProgress",
        "motionProgress",
        "connectorRectForBody",
        "animatedBodyRect",
    ):
        check(token in geometry,
              f"ConnectedSurfaceGeometry missing seam/morph geometry contract: {token}")
    check("property real connectorWidth: PerimeterTokens.connectorWidth" in geometry,
          "ConnectedSurfaceGeometry must source popup connector width from the shared perimeter token")
    check("Math.max(Math.max(0, connectorWidth), anchorTangentExtent)" not in geometry,
          "Connected popup neck width must not expand or shrink with the source control width")
    check("(1 - motionProgress) * crossBodyExtent" in geometry,
          "Connected popup motion must translate the complete body with its spatial scalar")
    check("readonly property real revealProgress: clamp(progress, 0, 1)" in geometry
          and "readonly property real motionProgress:" in geometry,
          "Connected popup must clamp semantic reveal while preserving continuous translation state")
    check("readonly property rect revealClipRect:" in geometry,
          "Connected popup reveal must expose a fixed resting-edge clip")
    check("readonly property rect visibleBodyRect:" in geometry,
          "Connected popup input must follow only the revealed body segment")
    check("crossBodyExtent * revealProgress" not in geometry,
          "Connected popup reveal must not shrink the body cross-axis")
    check("(bodyTangentExtent - connectorSourceExtent) * revealProgress" not in geometry,
          "Connected popup reveal must not expand from a narrow neck")
    check("bodyRect.width, bodyRect.height" in geometry,
          "Connected popup slide must preserve the full body size")
    check("tangentAnimationOffset" not in geometry
          and "tangentRevealDirection" not in geometry,
          "Connected popup slide must remain on the attachment axis like Caelestia wrappers")
    check("seamOverlap: PerimeterTokens.abyssWeldDepth" in styled_popup,
          "Bar popup SDF must preserve the primary-owner weld while the reveal clip keeps owner pixels hidden")
    check("readonly property real _popupScreenMargin: root._screenEdgeThickness" in styled_popup
          and "readonly property rect sdfBodyRect:" in abyss_frame,
          "Tangent-clamped Bar popups must stop at the real Screen Edge boundary and weld only their SDF record")
    check("ConnectedSurfaceRevealClip {" in styled_popup
          and "opacity: 1" in styled_popup,
          "Connected popup must use pure slide-under clipping instead of staged fade/scale")

    # Bottom-left Quick Notes is interaction/popup ownership only. It must
    # consume the shared StyledPopup/Abyss presentation path and never become a
    # second physical Screen Edge painter.
    quick_notes_popup = read("modules/screenCorners/QuickNotesPopup.qml")
    screen_corners = read("modules/screenCorners/ScreenCorners.qml")
    screen_edges = read("modules/screenCorners/ScreenEdges.qml")
    check("Bar.StyledPopup {" in quick_notes_popup
          and "attachmentEdgeOverride: root.cornerAttachmentEdge" in quick_notes_popup
          and "attachmentThicknessOverride: root.cornerAttachmentThickness" in quick_notes_popup,
          "Quick Notes must remain a shared connected popup attached to the real corner owner")
    check('property string quickNotesEditorOutput: ""' in screen_corners
          and "screenCorners.quickNotesEditorOutput === outputName" in screen_corners,
          "Quick Notes keyboard focus ownership must remain exclusive across outputs")
    check("QuickNotes" not in screen_edges and "quickNotes" not in screen_edges,
          "Quick Notes must never paint or modify the locked physical Screen Edge")

    content_host = read("modules/common/perimeter/ConnectedSurfaceContentHost.qml")
    for token in ("geometry.animatedBodyRect", "effectivePadding", "clip: true"):
        check(token in content_host,
              f"ConnectedSurfaceContentHost must centralize live padded body placement: {token}")

    connector = read("modules/common/perimeter/ConnectedSurfaceConnector.qml")
    check("Canvas {" in connector,
          "ConnectedSurfaceConnector must render a shaped shoulder rather than a rectangular stem")
    check("bezierCurveTo" in connector,
          "ConnectedSurfaceConnector must retain curved shoulder transitions")
    check("connectorSourceExtent" in connector,
          "ConnectedSurfaceConnector must narrow toward the real bar anchor")

    for retired_path in (
        "modules/common/perimeter/ConnectedSurfaceJoinFlares.qml",
        "modules/common/perimeter/PerimeterCornerShadow.qml",
        "modules/common/widgets/RoundCorner.qml",
    ):
        check(not (ROOT / retired_path).exists(),
              f"Retired round-wedge geometry must be absent: {retired_path}")
    abyss_edge = read("modules/common/perimeter/ConnectedSurfaceAbyssEdgeSurface.qml")
    for token in (
        "readonly property rect weldedBodyRect:",
        "property real ownerThickness: 10",
        "ConnectedSurfaceAbyssFrame {",
        "externalFrameThickness: root.tangentFrameThickness",
    ):
        check(token in abyss_edge, f"Abyss edge adapter contract missing: {token}")

    check("hoverEnabled: root.active" in styled_popup
          and "onBodyHoveredChanged: root._bodyHovered = bodyHovered" in styled_popup
          and "readonly property bool popupHovered: root._bodyHovered || root._contentHovered" in styled_popup,
          "StyledPopup hover bridge must track body and content without a seam-triggered retract")
    check("property QtObject _hoverTransferTimerObject: Timer {" in styled_popup
          and "interval: 90" in styled_popup
          and "hoverTransferTimer.restart()" in styled_popup,
          "StyledPopup must debounce the compositor leave/enter hand-off across Bar and popup windows")

    check("root.hoverTarget.visible" in styled_popup
          and "onActiveChanged: {" in styled_popup
          and "root._bodyHovered = false" in styled_popup
          and "root._contentHovered = false" in styled_popup
          and "onHoverTargetChanged: {" in styled_popup,
          "Connected popup must drop stale hover when anchor or presentation is evicted")
    for indicator in (
        "modules/bar/weather/WeatherBar.qml",
        "modules/bar/ShellUpdateIndicator.qml",
        "modules/bar/TimerIndicator.qml",
    ):
        source = read(indicator)
        check("property bool _pointerFocused: false" in source
              and "onPressed: root._pointerFocused = true" in source
              and "onActiveFocusChanged:" in source
              and "alternativeVisibleCondition: root.activeFocus && !root._pointerFocused" in source,
              f"{indicator} must distinguish keyboard focus from sticky pointer focus")
    tooltip = read("modules/common/widgets/PopupToolTip.qml")
    check("property bool useParentHover: true" in tooltip
          and "if (parent.containsMouse !== undefined)" in tooltip
          and "return false" in tooltip,
          "Shared tooltip must fail closed for unknown parent hover state")
    waffle_tile = read("modules/waffle/altSwitcher/WaffleAltSwitcherTile.qml")
    check("useParentHover: false" in waffle_tile
          and "externalHoverState: compactMouse.containsMouse" in waffle_tile
          and "externalPressedState: compactMouse.pressed" in waffle_tile,
          "Waffle compact tile must explicitly route hover/press from its child MouseArea")

    # Auxiliary edge-attached surfaces refined after the Abyss migration must
    # keep using the same production connected-surface vocabulary. These guards
    # intentionally check presentation ownership only; feature/IPC lifecycle
    # remains owned by each subsystem.
    region_selection = read("modules/regionSelector/RegionSelection.qml")
    for token in (
        "ConnectedSurfaceAbyssEdgeSurface {",
        'edge: "bottom"',
        "ownerThickness: root.screenEdgeThickness",
        "physicalShadow?.enabled ?? true",
        "progress: 1",
        "enableShadow: false",
        "transparent: true",
        "readonly property bool screenshotIiBarActive:",
        "readonly property string screenshotIiBarEdge:",
        "id: selectionVisualViewport",
        "x: root.screenshotLeftOwnerInset",
        "y: root.screenshotTopOwnerInset",
        "clip: true",
        "layer.effect: GE.OpacityMask {",
        "PerimeterTokens.frameRadius",
        "paintOverlap: Math.min(",
        "PerimeterTokens.seamOverlap",
    ):
        check(token in region_selection,
              f"Region selector connected Screen Edge controls missing: {token}")
    check("opacity: regionSelectionControls.opacity" not in region_selection,
          "Region selector outer Abyss shell must not fade with toolbar content")

    osd = read("modules/onScreenDisplay/OnScreenDisplay.qml")
    for token in (
        "ConnectedSurfaceAbyssFrame {",
        "ConnectedSurfaceBodyMask {",
        "seamOverlap: PerimeterTokens.abyssWeldDepth",
        "fuseDepth: PerimeterTokens.abyssFuseDepth",
        "visibleBodyRect: statusFrame.visibleBodyRect",
        "physicalShadow?.enabled ?? true",
        "Appearance.m3colors.m3shadow",
    ):
        check(token in osd,
              f"Compact IPC/OSD popup Abyss contract missing: {token}")
    check("ConnectedSurfaceFrame {" not in osd
          and "ConnectedSurfaceMask {" not in osd,
          "Compact IPC/OSD popups must not restore the legacy connected frame/mask")

    clipboard_panel = read("modules/clipboard/ClipboardPanel.qml")
    for token in (
        "qs.modules.common.perimeter",
        "ConnectedSurfaceGeometry {",
        'edge: "bottom"',
        "ConnectedSurfaceRevealClip {",
        "ConnectedSurfaceAbyssFrame {",
        "ConnectedSurfaceContentHost {",
        "PerimeterTokens.popupRadius",
        "screenMargin: root._screenEdgeThickness",
        "connectorLength: 0",
        "seamOverlap: PerimeterTokens.abyssWeldDepth",
        "externalFrameThickness: root._screenEdgeThickness",
        "physicalShadow?.enabled ?? true",
        "Appearance.m3colors.m3shadow",
        "duration: SurfaceMotion.duration",
        "easing.type: SurfaceMotion.easingType",
        "root._bottomOwnerThickness(outputName)",
    ):
        check(token in clipboard_panel,
              f"Clipboard connected bottom-surface contract missing: {token}")
    check("GlassBackground {" not in clipboard_panel,
          "Clipboard history must not keep the detached legacy GlassBackground shell")

    toast_manager = read("modules/common/ToastManager.qml")
    toast_notification = read("modules/common/widgets/ToastNotification.qml")
    check("\nimport qs\n" in toast_manager
          and "GlobalStates.barOpen" in toast_manager,
          "ToastManager must import root qs before consuming GlobalStates")
    for token in (
        "property real surfaceOffsetScale: 1",
        "readonly property real surfaceRevealProgress: 1 - root.surfaceOffsetScale",
        "Behavior on surfaceOffsetScale",
        "duration: SurfaceMotion.duration",
        "easing.type: SurfaceMotion.easingType",
        "progress: root.surfaceRevealProgress",
        "onDismissed: root.dismissToast(modelData.id)",
    ):
        check(token in toast_manager,
              f"Reload toast slide-motion contract missing: {token}")
    check('property: "opacity"' not in toast_manager
          and 'property: "scale"' not in toast_manager
          and "ParallelAnimation {" not in toast_manager
          and "entryAnim" not in toast_manager
          and "exitAnim" not in toast_manager,
          "Reload toast must stay slide-only with no fade/scale delegate animation")
    for token in (
        '"Quickshell reloaded"',
        "ConnectedSurfaceGeometry {",
        "id: toastGeometry",
        'edge: "top"',
        'alignment: "end"',
        "root.topOwnerThickness",
        "screenMargin: root.screenEdgeThickness",
        "connectorLength: 0",
        "seamOverlap: PerimeterTokens.abyssWeldDepth",
        "ConnectedSurfaceRevealClip {",
        "ConnectedSurfaceAbyssFrame {",
        "externalFrameThickness: root.screenEdgeThickness",
        "joinTop: true",
        "joinRight: !root.topBarOwnsEdge",
        "readonly property real topBarFreeRightInset: Math.max(",
        "PerimeterTokens.abyssFuseDepth + 2",
        "root.edgeShadowEnabled ? root.edgeShadowSize + 2 : 0",
        "root.topBarOwnsEdge ? root.topBarFreeRightInset : 0",
        "ConnectedSurfaceContentHost {",
        "ConnectedSurfaceBodyMask {",
        "visibleBodyRect: toastFrame.visibleBodyRect",
        "exclusionMode: ExclusionMode.Ignore",
        "connectedSurface: true",
        "physicalShadow?.enabled ?? true",
        "Appearance.m3colors.m3shadow",
    ):
        check(token in toast_manager,
              f"Top-right connected reload toast contract missing: {token}")
    check('"Niri config reloaded"' not in toast_manager
          and '"Niri Reloaded"' not in toast_manager
          and '_pendingReloadSource = "niri"' not in toast_manager,
          "Successful Niri config reloads must remain silent")
    check("joinRight: true" not in toast_manager
          and "joinRight: !root.topBarOwnsEdge" in toast_manager,
          "Reload toast must prefer a real top Bar; right Screen Edge welding is fallback-only")
    check("ConnectedSurfaceAbyssEdgeSurface {" not in toast_manager
          and "popup.width - width - root.edgeDecorationMargin" not in toast_manager
          and "x: Math.max(root.edgeDecorationMargin," not in toast_manager,
          "Reload toast must reuse StyledPopup geometry instead of the detached direct-edge host")
    toast_popup_start = toast_manager.index("PanelWindow {\n            id: popup")
    toast_geometry_start = toast_manager.index("ConnectedSurfaceGeometry {", toast_popup_start)
    check(toast_popup_start >= 0 and toast_geometry_start > toast_popup_start,
          "Reload toast visual PanelWindow must exist before its connected geometry")
    toast_popup_contract = toast_manager[toast_popup_start:toast_geometry_start]
    check("exclusiveZone:" not in toast_popup_contract
          and "exclusionMode: ExclusionMode.Ignore" in toast_popup_contract
          and "WlrLayershell.layer: WlrLayer.Overlay" in toast_popup_contract,
          "Reload toast visual window must stay full-output Overlay/Ignore with no exclusive-zone setter")
    check("\n    property bool connectedSurface: false\n" in toast_notification
          and "\n    property bool copied: false\n" in toast_notification
          and "layer.enabled: Appearance.effectsEnabled && !root.connectedSurface" in toast_notification
          and "wallpaperBackdropEnabled: !root.connectedSurface" in toast_notification,
          "Toast content must expose real host-owned connected-surface properties")
    check("\\\\n    property bool connectedSurface: false" not in toast_notification
          and "\\\\n    property bool copied: false" not in toast_notification,
          "Toast connected-surface properties must not be escaped into a line comment")

    screen_edge = read("modules/screenCorners/ScreenEdges.qml")
    screen_edge_fallback = read("modules/screenCorners/ScreenEdgeLegacyFallback.qml")
    check("Config.options?.appearance?.screenEdge?.width ?? 10" in screen_edge,
          "Screen Edge must default to 10px while remaining user-adjustable")
    check("Config.options?.appearance?.screenEdge?.radius" not in screen_edge
          and "RoundCorner {" not in screen_edge
          and "readonly property real rounding: PerimeterTokens.frameRadius" in screen_edge,
          "Screen Edge must consume the shared configurable radius")
    check("screenEdge?.enable" not in screen_edge,
          "Screen Edge must not be disabled by stale persisted enable flags")

    frame_window_start = screen_edge.index("component FrameWindow: PanelWindow")
    reservation_window_start = screen_edge.index("component ReservationWindow: PanelWindow")
    check(frame_window_start >= 0 and reservation_window_start > frame_window_start,
          "Screen Edge must retain separate painted FrameWindow and transparent ReservationWindow roles")
    frame_window_block = screen_edge[frame_window_start:reservation_window_start]
    reservation_window_block = screen_edge[reservation_window_start:]

    frame_mapped_start = frame_window_block.index("readonly property bool mapped:")
    frame_mapped_end = frame_window_block.index("// LOCKED BAR/SCREEN-EDGE INSETS:")
    frame_mapped_block = frame_window_block[frame_mapped_start:frame_mapped_end]
    check("FULLSCREEN-SCREEN-EDGE-LIFECYCLE-LOCK (maintainer approved 2026-09-19)" in frame_window_block
          and "!GlobalStates.screenLocked" in frame_mapped_block
          and "fullscreen" not in frame_mapped_block.lower()
          and "gameModeMinimal" not in frame_mapped_block,
          "Painted Screen Edge FrameWindow must stay mapped across fullscreen")

    check("readonly property bool fullscreenCovered: outputName.length > 0" in frame_window_block
          and "GameMode.hasFullscreenOnOutput(outputName)" in frame_window_block
          and "updatesEnabled: mapped && !fullscreenCovered" in frame_window_block,
          "FrameWindow must stay mapped but suspend render updates while fullscreen covers it")
    check("readonly property bool physicalShadowActive:" in frame_window_block
          and "&& !frameWindow.fullscreenCovered" in frame_window_block
          and "&& !Appearance.gameModeMinimal" in frame_window_block,
          "Expensive Screen Edge elevation must suspend under fullscreen/minimal mode")
    check("GameMode.hasFullscreenOnOutput(outputName)" in reservation_window_block
          and "!fullscreenCovered" in reservation_window_block
          and "updatesEnabled: mapped && workspaceOverviewEdgeSupportEnabled" in reservation_window_block,
          "Transparent Screen Edge reservations must keep mapping/exclusion live while render updates sleep unless hover support needs them")
    check("mask: Region { item: emptyFrameInput }" in screen_edge,
          "Painted Screen Edge frame must remain completely click-through")

    check("workspaceOverviewEdgeSupportEnabled" in screen_edge
          and "workspaceOverviewEdgeTriggerEnabled" in screen_edge
          and "active: reservationWindow.workspaceOverviewEdgeSupportEnabled" in screen_edge
          and "workspaceOverviewSupport.item?.hitArea" in screen_edge
          and ": emptyReservationInput" in screen_edge,
          "Reservation surfaces may allocate/accept Overview input only for the supported vertical-Bar Top-edge path")

    for retired_shadow_geometry in (
        "id: edgeShadow",
        "shadowExtent",
        "GradientStop",
        "RadialGradient",
        "shadowCanvas",
    ):
        check(retired_shadow_geometry not in screen_edge,
              f"Physical Screen Edge must not restore separate shadow geometry: {retired_shadow_geometry}")
    check("Config.options?.appearance?.screenEdge?.shadow" not in screen_edge,
          "Physical Screen Edge must not consume the connected-surface shadow config")

    # Primary painter: one texture-free analytic field fed by the exact same
    # FrameWindow inset/radius ownership as the locked Shape geometry.
    for token in (
        "ScreenEdgeField {",
        "id: frameField",
        "visible: !frameWindow.fullscreenCovered",
        "leftInset: frameWindow.frameLeftInset",
        "topInset: frameWindow.frameTopInset",
        "rightInset: frameWindow.frameRightInset",
        "bottomInset: frameWindow.frameBottomInset",
        "radius: root.rounding",
        "edgeColor: root.edgeColor",
        "elevationColor: Qt.alpha(",
        "Appearance.m3colors.m3shadow",
        "elevationSize: root.physicalShadowSize",
        "elevationEnabled: frameWindow.physicalShadowActive",
    ):
        check(token in frame_window_block,
              f"Analytic Screen Edge primary painter contract missing: {token}")

    analytic_start = frame_window_block.index("ScreenEdgeField {")
    fallback_start = frame_window_block.index("id: legacyFramePainter")
    check(analytic_start >= 0 and fallback_start > analytic_start,
          "Analytic Screen Edge must be primary and the legacy painter secondary")

    # The prior Shape/MultiEffect visual stays available only as a URL-loaded
    # error fallback. Healthy ScreenEdges.qml must not import its type graph.
    fallback_block = frame_window_block[fallback_start:]
    for token in (
        "readonly property var edgeRoot: root",
        "readonly property var frameHost: frameWindow",
        "active: frameField.shaderError",
        'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")',
    ):
        check(token in fallback_block,
              f"Legacy Screen Edge loader contract missing: {token}")
    check("import QtQuick.Shapes" not in screen_edge
          and "import QtQuick.Effects" not in screen_edge
          and "Shape {" not in frame_window_block
          and "MultiEffect {" not in frame_window_block,
          "Healthy Screen Edge path must not import or embed the legacy renderer")
    for token in (
        "import qs.modules.common",
        "import QtQuick.Shapes",
        "import QtQuick.Effects",
        "readonly property var edgeRoot: parent.edgeRoot",
        "readonly property var frameHost: parent.frameHost",
        "preferredRendererType: Shape.CurveRenderer",
        "fillRule: ShapePath.OddEvenFill",
        "readonly property real shadowRasterScale:",
        "root.edgeRoot.physicalShadowSize >= 12 ? 0.5 : 0.625",
        "layer.enabled: root.frameHost.physicalShadowActive",
        "layer.effect: MultiEffect {",
        "shadowEnabled: root.frameHost.physicalShadowActive",
        "blurMax: Math.max(1, root.edgeRoot.physicalShadowSize)",
        "shadowBlur: 1.0",
        "autoPaddingEnabled: false",
        "shadowHorizontalOffset: 0",
        "shadowVerticalOffset: 0",
    ):
        check(token in screen_edge_fallback,
              f"Legacy Screen Edge external fallback contract missing: {token}")

    check("component FrameWindow: PanelWindow" in screen_edge
          and "component ReservationWindow: PanelWindow" in screen_edge
          and "implicitHeight: horizontal ? root.thickness : 1" in screen_edge
          and "implicitWidth: horizontal ? 1 : root.thickness" in screen_edge,
          "One full-screen frame must own paint while transparent thin windows reserve work-area space")
    check("exclusiveZone: 0" not in screen_edge
          and screen_edge.count("exclusionMode: ExclusionMode.Ignore") == 1,
          "Full-screen Screen Edge frame must ignore reservations without resetting itself to normal exclusion mode")
    check("exclusiveZone: mapped ? root.thickness : 0" in screen_edge,
          "Transparent Screen Edge reservation windows must reserve the configured physical edge thickness")

    check("function iiBarOwnsEdge(outputName, edge)" in screen_edge
          and "!(Config.options?.bar?.autoHide?.enable ?? false)" in screen_edge,
          "Auto-hide ii Bar must hand physical edge ownership to ScreenEdges.qml")
    for bar_frame_token in (
        'root.iiBarOwnsEdge(outputName, "left")',
        'root.iiBarOwnsEdge(outputName, "right")',
        'root.iiBarOwnsEdge(outputName, "top")',
        'root.iiBarOwnsEdge(outputName, "bottom")',
        "Appearance.sizes.verticalBarWidth : root.thickness",
        "Appearance.sizes.barHeight : root.thickness",
        "leftInset: frameWindow.frameLeftInset",
        "topInset: frameWindow.frameTopInset",
        "rightInset: frameWindow.frameRightInset",
        "bottomInset: frameWindow.frameBottomInset",
    ):
        check(bar_frame_token in screen_edge,
              f"ii Bar must remain the thicker side of the single Screen Edge field: {bar_frame_token}")
    check(screen_edge.count("Appearance.sizes.verticalBarWidth : root.thickness") == 2
          and screen_edge.count("Appearance.sizes.barHeight : root.thickness") == 2,
          "Left/right and top/bottom Bar frame insets must remain orientation-symmetric")

    for retired_geometry in (
        "PERIMETER-CORNER-LOCK",
        "id: leadingCorner",
        "id: trailingCorner",
        "RoundCorner.CornerEnum",
        "PathCubic",
        "RadialGradient",
    ):
        check(retired_geometry not in screen_edge,
              f"Screen Edge must not restore retired corner implementations: {retired_geometry}")

    check("SCREEN-EDGE-GEOMETRY-LOCK (maintainer approved 2026-09-19)" in screen_edge
          and "BAR-SCREEN-EDGE-CORNER-LOCK (maintainer approved 2026-09-19)" in screen_edge,
          "Approved Screen Edge + Bar corner geometry lock markers must remain present")
    check("BAR-SCREEN-EDGE-CORNER-LOCK" in perimeter_tokens,
          "Shared perimeter radius owner must retain the Bar/Screen Edge corner lock marker")

    # Legacy geometry exists only in the URL-loaded fallback file.
    check(screen_edge_fallback.count("Shape {") == 1
          and screen_edge_fallback.count("ShapePath {") == 1
          and screen_edge_fallback.count("PathMove {") == 1
          and screen_edge_fallback.count("direction: PathArc.Clockwise") == 4,
          "External Screen Edge fallback must retain exactly one inverted frame")
    check("readonly property int outerPadding: 50" in screen_edge,
          "Screen Edge must retain the locked outer padding token")
    for fallback_geometry in (
        "readonly property real innerLeft: root.frameHost.frameLeftInset",
        "readonly property real innerTop: root.frameHost.frameTopInset",
        "frameShape.width - root.frameHost.frameRightInset",
        "frameShape.height - root.frameHost.frameBottomInset",
        "startX: -root.edgeRoot.outerPadding",
        "startY: -root.edgeRoot.outerPadding",
        "x: frameShape.width + root.edgeRoot.outerPadding",
        "y: frameShape.height + root.edgeRoot.outerPadding",
        "x: framePath.innerLeft + framePath.r",
        "x: framePath.innerRight - framePath.r",
        "radiusX: framePath.r",
        "radiusY: framePath.r",
    ):
        check(fallback_geometry in screen_edge_fallback,
              f"Legacy Screen Edge fallback geometry changed: {fallback_geometry}")

    check("component CornerWindow: PanelWindow" not in screen_edge
          and "CornerWindow {" not in screen_edge
          and "component EdgeWindow: PanelWindow" not in screen_edge
          and "Rectangle {" not in screen_edge,
          "Screen Edge must not reconstruct the frame from painted edge/corner overlays")
    check('FrameWindow {}' in screen_edge,
          "Each output must have exactly one painted Screen Edge frame")
    for edge in ("top", "bottom", "left", "right"):
        check(f'ReservationWindow {{ edge: "{edge}" }}' in screen_edge,
              f"Screen Edge must retain transparent {edge} work-area reservation")

    sidebar_host = read("modules/sidebar/SidebarHost.qml")
    for token in (
        "GlobalStates.sidebarLeftPresentationOutput",
        "GlobalStates.sidebarRightPresentationOutput",
        "PanelWindow {",
        "width: Math.max(0, root.effectiveSidebarWidth",
        "- Appearance.sizes.elevationMargin",
        "- root.screenEdgeHoverWidth)",
        "rightMargin: root.isLeftEdge",
        "? Appearance.sizes.elevationMargin",
        ": root.screenEdgeHoverWidth",
        "leftMargin: root.isLeftEdge",
        "? root.screenEdgeHoverWidth",
        ": Appearance.sizes.elevationMargin",
        "readonly property real screenEdgePaintOverlap: Math.min(",
        "PerimeterTokens.seamOverlap",
        "paintOverlap: root.screenEdgePaintOverlap",
    ):
        check(token in sidebar_host,
              f"Sidebar Screen Edge boundary contract missing: {token}")
    for retired in (
        "ConnectedSurfaceConnector",
        "sidebarBridgeGeometry",
        "directEdgeInset",
        "screenEdgeThickness",
    ):
        check(retired not in sidebar_host,
              f"Sidebar must not stop at an inner-edge inset or restore a connector: {retired}")
    check(sidebar_host.count('property: "animTranslateX"') == 2
          and "SurfaceMotion.duration" in sidebar_host
          and "SurfaceMotion.easingType" in sidebar_host
          and 'readonly property string animationType: SurfaceMotion.mode' in sidebar_host,
          "Sidebar presentation must use the immutable slide-only SurfaceMotion contract")

    dock = read("modules/dock/Dock.qml")
    dock_apps = read("modules/dock/DockApps.qml")
    for dead_dock_apps_api in (
        "maxWindowPreviewHeight",
        "maxWindowPreviewWidth",
        "windowControlsHeight",
        "buttonPadding",
        "previewAnchorItem",
    ):
        check(dead_dock_apps_api not in dock_apps
              and dead_dock_apps_api not in dock,
              f"Dock must not retain unused app-list API: {dead_dock_apps_api}")
    for token in (
        "import qs.modules.common.perimeter",
        "duration: SurfaceMotion.duration",
        "easing.type: SurfaceMotion.easingType",
        "ConnectedSurfaceAbyssEdgeSurface {",
        "id: dockAbyssSurface",
        "edge: root.position",
        "ownerThickness: dockRoot.screenEdgeThickness",
        "exclusionMode: ExclusionMode.Ignore",
        'WlrLayershell.layer: WlrLayer.Overlay',
        'WlrLayershell.namespace: "quickshell:dock-reservation"',
        "exclusiveZone: mapped ? reservationThickness : 0",
        "id: dockConnectedBody",
        "anchors.fill: dockConnectedBody",
        "paintOverlap: Math.min(",
        "PerimeterTokens.seamOverlap",
        "dockMouseArea.x + dockBackground.x + dockConnectedBody.x",
        "dockRoot.edgeDecorationMargin * 2",
        "? dockRoot.screenEdgeThickness",
        "screenEdge?.physicalShadow?.enabled ?? true",
        "screenEdge?.physicalShadow?.size ?? 15",
        "screenEdge?.physicalShadow?.opacity ?? 0.70",
        "Qt.alpha(Appearance.m3colors.m3shadow, dockRoot.screenEdgeShadowOpacity)",
        "fillColor: dockVisualBackground.abyssFillColor",
        "borderColor: dockVisualBackground.abyssBorderColor",
        "borderWidth: dockVisualBackground.abyssBorderWidth",
        "readonly property color abyssFillColor:",
        "readonly property bool matchDarkPhysicalEdge:",
        "Appearance.m3colors.darkmode",
        "? Appearance.colors.colLayer0",
        ": Appearance.alis.colLayer1",
    ):
        check(token in dock,
              f"Dock Abyss Screen Edge / shadow contract missing: {token}")
    check("nativeBlurGeometryExact" not in dock,
          "Dock must not retain an unused blur-proof compatibility alias")
    for stale_corner_override in (
        'topLeftRadius: (root.isTop || root.isLeft) ? 0 : radius',
        'topRightRadius: (root.isTop || root.position === "right") ? 0 : radius',
        'bottomLeftRadius: (root.position === "bottom" || root.isLeft) ? 0 : radius',
        'bottomRightRadius: (root.position === "bottom" || root.position === "right") ? 0 : radius',
    ):
        check(stale_corner_override not in dock,
              f"Dock body must not overpaint Abyss weld fillets: {stale_corner_override}")
    check("StyledRectangularShadow {" not in dock,
          "Dock must not retain its detached local shadow after Abyss cutover")
    dock_visual_start = dock.index("sourceComponent: PanelWindow {")
    dock_reservation_start = dock.index("PanelWindow {\n            id: dockReservationWindow")
    check(dock_visual_start >= 0 and dock_reservation_start > dock_visual_start,
          "Dock must keep visual and reservation layer-shell roles separate")
    dock_visual_block = dock[dock_visual_start:dock_reservation_start]
    check("exclusiveZone:" not in dock_visual_block
          and 'WlrLayershell.layer: WlrLayer.Overlay' in dock_visual_block
          and "exclusionMode: ExclusionMode.Ignore" in dock_visual_block,
          "Dock visual window must remain Overlay/Ignore with no exclusive-zone setter")
    check("screenEdgePaintOverlap" not in dock
          and "paintOverlap: dockRoot." not in dock,
          "Dock seam overlap must stay local to the shared connected body, not a second offset state")
    check(dock.count("duration: SurfaceMotion.duration") >= 4
          and "Appearance.animation.elementMoveEnter.duration" not in dock,
          "Dock reveal/retract must use the same immutable slide motion as connected popups")

    osk = read("modules/onScreenKeyboard/OnScreenKeyboard.qml")
    for token in (
        "targetY = 0",
        "targetY = ph - kh",
        "y: parent ? parent.height - height : 0",
        'joinTop: oskRoot.snappedEdge === "top"',
        'joinBottom: oskRoot.snappedEdge === "bottom"',
    ):
        check(token in osk,
              f"OSK physical Screen Edge attachment contract missing: {token}")
    check("screenAttachInset" not in osk,
          "OSK must not stop at the inner Screen Edge boundary")
    check('topLeftRadius: oskRoot.snappedEdge === "top" ? 0 : radius' in osk
          and 'topRightRadius: oskRoot.snappedEdge === "top" ? 0 : radius' in osk
          and 'bottomLeftRadius: oskRoot.snappedEdge === "bottom" ? 0 : radius' in osk
          and 'bottomRightRadius: oskRoot.snappedEdge === "bottom" ? 0 : radius' in osk
          and "PerimeterTokens.attachedCornerRadius" not in osk,
          "OSK attached body edge must stay square without a legacy endpoint wedge")
    check("SurfaceMotion.duration" in osk
          and "SurfaceMotion.easingType" in osk,
          "OSK attached-edge slide must use the immutable connected-surface motion token")
    check("property real initScale:" not in osk
          and "Behavior on scale" not in osk,
          "OSK enter/exit must stay slide-only without a second scale animation")
    for token in (
        "property bool _oskResident:",
        "property real _oskRevealProgress:",
        "readonly property real revealOffsetY:",
        "transform: Translate { y: oskRoot.revealOffsetY }",
    ):
        check(token in osk,
              f"OSK must stay resident and slide through its attached edge: {token}")

    for token in (
        "tangentRevealDirection",
        "tangentAnimationOffset",
        "bodyRect.x + tangentAnimationOffset",
        "bodyRect.y + tangentAnimationOffset",
    ):
        check(token not in geometry,
              f"Connected popup slide must stay on the attachment axis like Caelestia: {token}")

    check("PerimeterCornerShadow" not in screen_edge
          and "adjacentShadowInset" not in screen_edge
          and "shadowSeamOverlap" not in screen_edge,
          "Rejected curved perimeter-shadow stitching must stay removed from Screen Edge")

    for token in (
        "readonly property real hiddenTranslateDistance:",
        "Math.ceil(root.effectiveSidebarWidth) + Math.max(",
        "PerimeterTokens.abyssFuseDepth",
        "? -root.hiddenTranslateDistance",
        ": root.hiddenTranslateDistance",
        "ConnectedSurfaceAbyssEdgeSurface {",
        "id: sidebarAbyssSurface",
        "ownerThickness: root.screenEdgeHoverWidth",
        "paintOverlap: root.screenEdgePaintOverlap",
        "exclusionMode: ExclusionMode.Ignore",
    ):
        check(token in sidebar_host, f"Sidebar Abyss/full-hide contract missing: {token}")
    for retired in ("ConnectedSurfaceJoinFlares", "joinFlareRadius", "sidebarEdgeFlares"):
        check(retired not in sidebar_host,
              f"Sidebar must not retain retired wedge geometry: {retired}")

    media_popup = read("modules/mediaControls/BarMediaPopup.qml")
    check("EqualizerPanel {" in media_popup,
          "Bar media popup must retain the Equalizer panel")
    check("No active player" not in media_popup
          and "Make sure your player has MPRIS support" not in media_popup,
          "Bar media popup must not append an inactive-player text card below Equalizer")

    for rounded_sidebar_path in (
        "modules/sidebarLeft/SidebarLeftContent.qml",
        "modules/sidebarRight/SidebarRightContent.qml",
        "modules/sidebarRight/CompactSidebarRightContent.qml",
    ):
        rounded_sidebar = read(rounded_sidebar_path)
        check("PerimeterTokens.attachedCornerRadius" not in rounded_sidebar,
              f"{rounded_sidebar_path} must not round attached body corners inward")
        check('root.attachedEdge === "left" ? 0 : radius' in rounded_sidebar
              or 'root.attachedEdge === "right" ? 0 : radius' in rounded_sidebar,
              f"{rounded_sidebar_path} attached body edge must stay square at the owner seam")

    compact_sidebar = read("modules/sidebarRight/CompactSidebarRightContent.qml")
    check("import qs.modules.mediaControls" in compact_sidebar
          and "EqualizerPanel {" in compact_sidebar
          and "active: root.panelVisible" in compact_sidebar,
          "Compact right Sidebar Media section must render the shared Equalizer below the player")

    resources_popup = read("modules/bar/ResourcesPopup.qml")
    check('Translation.tr("RPM:")' in resources_popup
          and 'Translation.tr("Speed:")' not in resources_popup,
          "ThinkFan inline metric must use the compact RPM label")
    check('String(ThinkFanService.fanRpm)' in resources_popup,
          "ThinkFan RPM value must not repeat the RPM unit after the RPM label")

    for settings_path in (
        "modules/settings/SettingsOverlay.qml",
        "modules/settings/SettingsFocus.qml",
    ):
        settings_surface = read(settings_path)
        if settings_path.endswith("SettingsOverlay.qml"):
            settings_surface += read("modules/settings/SettingsOverlayNativeHost.qml")
        # Authentication must cover Settings. The native flag matrix in
        # test-alis-intergration-polkit-visibility.py exercises yielding and restoration.
        for token in (
            "? WlrLayer.Bottom : WlrLayer.Overlay",
            "ConnectedSurfaceAbyssEdgeSurface {",
            'edge: "bottom"',
            "ownerThickness: root._screenEdgeThickness",
            "bottomLeftRadius: 0",
            "bottomRightRadius: 0",
            'color: "transparent"',
        ):
            check(token in settings_surface,
                  f"{settings_path} Abyss bottom-attachment contract missing: {token}")
        check("ConnectedSurfaceJoinFlares" not in settings_surface,
              f"{settings_path} must not restore legacy endpoint wedge geometry")

    settings_overlay = read("modules/settings/SettingsOverlay.qml")
    settings_focus = read("modules/settings/SettingsFocus.qml")
    check("1600" in settings_overlay
          and "settingsPanel.width * 0.90" in settings_overlay
          and "settingsPanel.height * 0.92" in settings_overlay,
          "Rail Settings overlay must use the enlarged bottom-connected footprint")
    check("1560" in settings_focus
          and "settingsPanel.width * 0.88" in settings_focus
          and "settingsPanel.height * 0.92" in settings_focus,
          "Focus Settings overlay must use the enlarged bottom-connected footprint")
    check("Appearance.colors.colLayer0" in settings_overlay
          and "Appearance.colors.colLayer0" in settings_focus,
          "Connected Settings body fill must share the Material Screen Edge/Bar colLayer0 family")
    check("Appearance.colors.colLayer0Base" not in settings_overlay,
          "Rail Settings overlay must not use the detached base tone for its connected body")

    for settings_surface in (settings_overlay, settings_focus):
        check("SurfaceMotion.duration" in settings_surface
              and "SurfaceMotion.easingType" in settings_surface,
              "Connected Settings overlays must use the immutable slide-only SurfaceMotion contract")
        check("Appearance.m3colors.m3shadow" in settings_surface
              and "screenEdge?.physicalShadow?.enabled" in settings_surface
              and "screenEdge?.physicalShadow?.size" in settings_surface
              and "screenEdge?.physicalShadow?.opacity" in settings_surface
              and "shadowExtent:" in settings_surface,
              "Connected Settings Abyss surfaces must share the physical Screen Edge shadow controls")
        check("ConnectedSurfaceJoinFlares" not in settings_surface,
              "Settings must not reintroduce floating endpoint wedge geometry")

    search_widget = read("modules/overview/SearchWidget.qml")
    check("property bool directBottomAttachment: false" in search_widget
          and "readonly property rect connectedSurfaceRect:" in search_widget
          and "bottomLeftRadius: root.directBottomAttachment && root.showResults ? 0 : radius" in search_widget
          and "bottomRightRadius: root.directBottomAttachment && root.showResults ? 0 : radius" in search_widget
          and "ConnectedSurfaceJoinFlares" not in search_widget
          and "joinFlareRadius" not in search_widget,
          "Applications search must keep a square direct seam without legacy endpoint wedges")

    dashboard = read("modules/overview/OverviewDashboard.qml")
    check("import qs.modules.dashboard" in dashboard
          and "DashboardContent {" in dashboard
          and "SearchWidget {" in dashboard
          and "embeddedSurface: true" in dashboard,
          "Launcher Dashboard must be one shared three-column/search surface")
    check("Config.options?.dashboard?.widthRatio" in dashboard
          and "Config.options?.dashboard?.heightRatio" in dashboard
          and "root.presentingSearch" in dashboard
          and "root.searchOnlyHeight : root.configuredHeight" in dashboard,
          "Launcher Dashboard must consume Dashboard width/height settings")
    check("property real dashboardProgress: 1" in dashboard
          and "opacity: root.dashboardOpacity" in dashboard
          and "resultsOpacity: root.searchResultsOpacity" in dashboard,
          "Dashboard-to-search transition must use the shared crossfade/height-resize progress")
    check("SurfaceMotion.duration" in dashboard
          and "SurfaceMotion.easingType" in dashboard,
          "Dashboard connected motion must use immutable SurfaceMotion")
    check("ConnectedSurfaceAbyssEdgeSurface {" in dashboard
          and "id: dashboardAbyssSurface" in dashboard
          and "ownerThickness: root.attachmentThickness" in dashboard
          and "PerimeterTokens.abyssFuseDepth" in dashboard
          and "id: dashboardSurfaceLayer" in dashboard
          and "z: 2" in dashboard
          and "ConnectedSurfaceJoinFlares" not in dashboard,
          "Dashboard bottom attachment must keep content above the Abyss plate without legacy wedge geometry")
    dashboard_content = read("modules/dashboard/DashboardContent.qml")
    dashboard_canvas = read("modules/dashboard/DashboardCanvas.qml")
    dashboard_grid = read("modules/dashboard/DashboardEditGrid.qml")
    dashboard_card = read("modules/dashboard/DashCard.qml")
    check("DashboardCanvas {" in dashboard_content
          and "DashboardHeader {" in dashboard_content
          and "WidgetColumn" not in dashboard_content,
          "Dashboard must use the freeform canvas instead of fixed columns")
    check('color: root.embeddedSurface ? "transparent" : Appearance.colors.colLayer0' in dashboard_content
          and 'radius: root.embeddedSurface ? 0 : Appearance.rounding.large' in dashboard_content
          and "border.width: 0" in dashboard_content,
          "Dashboard outer surface must reuse the canonical Material popup/sidebar background")
    check('Config.options?.panelFamily === "abyss" ? AbyssStyle.contentLayer : Appearance.colors.colLayer1' in dashboard_card
          and "Appearance.colors.colSurfaceContainerHigh" not in dashboard_card,
          "Dashboard cards must use the adjustable Abyss content layer and retain Sidebar layer-1 for Waffle")
    for retired_dashboard_surface in (
        "ColorQuantizer {",
        "AdaptedMaterialScheme {",
        "ZzzPanelBackdrop {",
        "ZzzPlate {",
        "id: blurredWallpaper",
        "useWallpaperBackdrop",
        "wallpaperDominantColor",
        "Appearance.auroraEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.zzzEverywhere",
    ):
        check(retired_dashboard_surface not in dashboard_content,
              f"Dashboard must not introduce a separate background style: {retired_dashboard_surface}")
    check('Config.options?.dashboard?.canvas?.widgets' in dashboard_canvas
          and "function beginMove(" in dashboard_canvas
          and "function beginResize(" in dashboard_canvas
          and "function finishInteraction(" in dashboard_canvas,
          "Dashboard canvas must persist free move/resize geometry")
    for edge in ('"n"', '"s"', '"e"', '"w"', '"nw"', '"ne"', '"sw"', '"se"'):
        check(f"edge: {edge}" in dashboard_canvas,
              f"Dashboard canvas missing resize handle {edge}")
    check("DashboardEditGrid {" in dashboard_canvas
          and 'Config.options?.dashboard?.canvas?.gridStyle' in dashboard_canvas
          and 'Config.options?.dashboard?.canvas?.gridSize' in dashboard_canvas
          and 'Config.options?.dashboard?.canvas?.snap' in dashboard_canvas,
          "Dashboard Edit mode must expose configurable grid and snapping")
    check('property string gridStyle: "dots"' in dashboard_grid
          and 'gridStyle === "lines"' in dashboard_grid
          and 'gridStyle === "cross"' in dashboard_grid,
          "Dashboard edit grid must keep dots/lines/cross rendering modes")
    check("enabled: !root.editMode" in dashboard_canvas
          and "visible: root.editMode" in dashboard_canvas,
          "Dashboard modules must only be movable/resizable in explicit Edit mode")
    check("Flickable {" not in dashboard_content
          and "Flickable {" not in dashboard_canvas
          and '=== "abyss"' in dashboard_canvas,
          "Dashboard stays bounded without a scrolling or expanded workspace")
    dashboard_toolbar = read("modules/dashboard/DashboardEditToolbar.qml")
    check("id: editToolbar" not in dashboard_canvas
          and "DashboardEditToolbar {" in dashboard
          and "x: Math.round(dashContainer.x" in dashboard
          and "y: root.embeddedSurface ? 0 : Math.round(dashContainer.y - height + 1)" in dashboard,
          "Dashboard edit toolbar must stay centered and attached above the Dashboard canvas")
    check("bottomLeftRadius: root.abyssMode ? radius : 0" in dashboard_toolbar
          and "bottomRightRadius: root.abyssMode ? radius : 0" in dashboard_toolbar,
          "Dashboard edit toolbar must visually join the Dashboard top edge")
    overview_runtime = read("modules/overview/Overview.qml")
    check("readonly property bool applicationsPresentationMode:" in overview_runtime
          and "dashboardPanel.item.connectedSurfaceRect" in overview_runtime
          and "searchingText: root.searchingText" in overview_runtime,
          "Search and Dashboard must share one bottom-connected launcher surface")
    check("SearchWidget {\n                    id: searchWidget" not in overview_runtime,
          "Overview must not keep a second floating SearchWidget above Dashboard")
    check("opacity: root.taskViewMode" in overview_runtime,
          "Launcher search must not use the old Overview fade path")

    critical_panels = read("modules/ii/critical/ShellIiCriticalPanels.qml")
    check('../../screenCorners/ScreenEdges.qml' in critical_panels,
          "ii critical shell must load persistent Screen Edge chrome")
    check('../../sidebar/SidebarEdgeConnectors.qml' not in critical_panels,
          "ii critical shell must not recreate the retired standalone sidebar bridge window")
    check("PerimeterRuntime.qml" not in critical_panels,
          "Full iiPerimeter runtime must not be booted by the critical shell")

    abyss_frame = read("modules/common/perimeter/ConnectedSurfaceAbyssFrame.qml")
    abyss_field = read("modules/common/perimeter/ConnectedSurfaceAbyssField.qml")
    abyss_frag = read("modules/common/perimeter/AbyssField.frag")
    abyss_mask = read("modules/common/perimeter/ConnectedSurfaceBodyMask.qml")
    for token in (
        "function clipExternalOwners(raw, primaryOverlap)",
        "readonly property rect visibleBodyRect:",
        "readonly property rect sdfBodyRect:",
        "x: root.sdfBodyRect.x",
        "y: root.sdfBodyRect.y",
        "readonly property var ownerShape:",
        "readonly property var frameStartShape: !root.tangentStartJoined",
        "readonly property var frameEndShape: !root.tangentEndJoined",
        "readonly property var popupShape:",
        "readonly property bool needsEndJoinAux:",
        "ShaderEffectSource {",
        "id: shadowMaskField",
        "shapes: field.shapes",
        "sourceItem: shadowMaskField",
        "sourceRect: root.rawShadowBounds",
        "id: blurredShadow",
        "source: shadowTextureSource",
        "blurEnabled: true",
        "autoPaddingEnabled: false",
        "sourceItem: blurredShadow",
        "hideSource: true",
        "smooth: true",
        "ConnectedSurfaceAbyssField {",
        "readonly property bool bodyHovered: bodyHover.hovered",
    ):
        check(token in abyss_frame,
              f"Production Abyss frame contract missing: {token}")
    check("ConnectedSurfaceJoinFlares" not in abyss_frame
          and "ConnectedSurfaceConnector" not in abyss_frame
          and "RectangularShadow {" not in abyss_frame,
          "Connected shadow must use the same smooth-union SDF instead of patch or box shadow geometry")
    check('fragmentShader: Qt.resolvedUrl("AbyssField.frag.qsb")' in abyss_field
          and "readonly property vector4d viewport:" in abyss_field
          and "pass.x, pass.y" in abyss_field,
          "Production Abyss field must use the locked local QSB with output-local viewport coordinates")
    for token in (
        "float roundedBoxCorners(",
        "float tangentAwareBody(",
        "primaryRelation > 0.5 && tangentRelation > 0.5",
        "also < -0.5 || also > 0.5",
    ):
        check(token in abyss_frag,
              f"Production tangent-contact shader contract missing: {token}")
    check("tangentQuarterFillet" not in abyss_frag
          and "tangentContribution" not in abyss_frag
          and "tangentShoulder" not in abyss_frag
          and "outsideEllipse" not in abyss_frag,
          "Experimental tangent-corner shader paths must stay out of production")
    check("_sourceStrip" not in abyss_mask
          and "_middleStrip" not in abyss_mask
          and "_bodyStrip" not in abyss_mask
          and "visibleBodyRect" in abyss_mask,
          "StyledPopup Abyss input must be body-only rather than the retired connector-strip approximation")
    check("ConnectedSurfaceFrame {" not in styled_popup
          and "ConnectedSurfaceMask {" not in styled_popup,
          "ii StyledPopup must not silently retain the legacy flare/mask renderer after Abyss cutover")

    frame = read("modules/common/perimeter/ConnectedSurfaceFrame.qml")
    check("property real connectorBorderWidth: 0" in frame,
          "ConnectedSurfaceFrame must default the connector outline off at the seam")
    check("strokeWidth: root.connectorBorderWidth" in frame,
          "ConnectedSurfaceFrame must route connector outline width through its seam policy")
    check("ConnectedSurfaceJoinFlares" not in frame
          and "joinFlareRadius" not in frame,
          "ConnectedSurfaceFrame must not retain the retired round-wedge painter")
    check("opacity: root.geometry.progress" not in frame,
          "ConnectedSurfaceFrame must morph geometry instead of fading the whole surface")
    check("attachedCornerRadius" not in frame
          and "topLeftRadius: (root.joinTop || root.joinLeft) ? 0 : surfaceRadius" in frame
          and "topRightRadius: (root.joinTop || root.joinRight) ? 0 : surfaceRadius" in frame
          and "bottomLeftRadius: (root.joinBottom || root.joinLeft) ? 0 : surfaceRadius" in frame
          and "bottomRightRadius: (root.joinBottom || root.joinRight) ? 0 : surfaceRadius" in frame,
          "Shared connected popup body must stay square on attached edges without a wedge painter")
    check("property bool hoverEnabled: false" in frame
          and "readonly property bool bodyHovered: bodyHover.hovered" in frame
          and "HoverHandler {" in frame,
          "ConnectedSurfaceFrame must expose body-scoped hover ownership for popup hand-off")
    generic_shadow = read("modules/common/widgets/StyledRectangularShadow.qml")
    check("property color color: Appearance.colors.colShadow" in generic_shadow,
          "Shared rectangular shadow must use the proven themed shell shadow source")
    check("cached: !(root.joinTop || root.joinBottom" in generic_shadow,
          "Connected moving shadows must remain live; stationary cards may cache")

    mask = read("modules/common/perimeter/ConnectedSurfaceMask.qml")
    for token in ("_sourceStrip", "_middleStrip", "_bodyStrip", "connectorSourceExtent"):
        check(token in mask,
              f"ConnectedSurfaceMask must track the flared connector rather than its full bounding box: {token}")
    check("item: root.active ? root.connectorItem" not in mask,
          "ConnectedSurfaceMask must not make the transparent connector bounding box fully interactive")

    bar_runtime = read("modules/bar/Bar.qml")
    vertical_bar_runtime = read("modules/verticalBar/VerticalBar.qml")
    bar_content = read("modules/bar/BarContent.qml")
    vertical_bar_content = read("modules/verticalBar/VerticalBarContent.qml")
    for runtime in (bar_runtime, vertical_bar_runtime):
        check("PerimeterCornerShadow" not in runtime
              and "shadowTangentInset" not in runtime
              and "shadowSeamOverlap" not in runtime,
              "Rejected curved Bar shadow stitching must stay reverted")
    for runtime in (bar_runtime, vertical_bar_runtime):
        for retired_geometry in (
            "id: roundDecorators",
            "ScreenEdgeContact",
            "id: barEdgeShadow",
            "id: autoHideScreenEdge",
            "autoHideEdgeBand",
            "edgeShadowEnabled",
            "edgeShadowExtent",
            "edgeShadowOpacity",
            "edgeShadowColor",
            "screenEdgeThickness",
            "inwardDecoratorAllowance",
            "screenEdge?.shadow",
            "screenEdge?.radius",
            "PerimeterTokens.frameRadius",
            "RoundCorner {",
            "surfacePresented",
        ):
            check(retired_geometry not in runtime,
                  f"Bar runtime must not retain physical Screen Edge geometry/shadow: {retired_geometry}")
        check("showBarBackground" not in runtime,
              "Supported Hug Bar chrome must not depend on a dead visibility alias")
        for dead_root_probe in ("brightnessMonitor", "useShortenedForm", "centerSideModuleWidth"):
            check(dead_root_probe not in runtime,
                  f"Bar root must not retain unused sizing/state probe: {dead_root_probe}")
        check("Appearance.animation.elementMove.duration" in runtime
              and "Appearance.animation.elementMove.bezierCurve" in runtime,
              "Bar auto-hide slide must use the default-spatial motion token")
    check("id: barBackground" in bar_content
          and "visible: true" in bar_content
          and "visible: !gameModeMinimal" not in bar_content,
          "Horizontal Hug body must remain structural across fullscreen/GameMode")
    check("id: barBackground" in vertical_bar_content
          and "visible: true" in vertical_bar_content
          and "isIslands" not in vertical_bar_content
          and "appearanceStyle" not in vertical_bar_content,
          "Vertical Hug body must remain structural without retired Islands routing")
    module_shown_start = bar_content.index("function _moduleShown")
    module_shown_end = bar_content.index("\n    }", module_shown_start)
    module_shown_block = bar_content[module_shown_start:module_shown_end]
    check(module_shown_start >= 0
          and "GameMode" not in module_shown_block
          and "gameModeMinimal" not in module_shown_block
          and "fullscreen" not in module_shown_block.lower(),
          "Horizontal Bar module visibility must not be gated by fullscreen/GameMode")
    check("Config.options?.bar?.cornerStyle" not in bar_content,
          "Horizontal Hug body must ignore persisted retired cornerStyle at runtime")
    check("Config.options?.bar?.cornerStyle" not in vertical_bar_content,
          "Vertical Hug body must ignore persisted retired cornerStyle at runtime")
    check("(Config.options?.bar?.cornerStyle ?? 0) === 0" not in vertical_bar_runtime,
          "Vertical Hug shoulders must not depend on legacy cornerStyle state")
    check("readonly property bool fullscreenCovered:" in bar_runtime
          and "GameMode.hasFullscreenOnOutput(barRoot.outputName)" in bar_runtime
          and "item: barRoot.fullscreenCovered ? emptyMask : hoverMaskRegion" in bar_runtime
          and "enabled: !barRoot.fullscreenCovered" in bar_runtime
          and "opacity: barRoot.fullscreenCovered ? 0 : 1" in bar_runtime,
          "Horizontal Bar fullscreen lifecycle must keep the window mapped while sleeping input/paint")
    check("visible: !fullscreenCovered" not in bar_runtime
          and "updatesEnabled: !fullscreenCovered" not in bar_runtime,
          "Horizontal Bar must not unmap or disable window updates across fullscreen")
    check("fullscreenCovered" not in vertical_bar_runtime
          and "visible: !fullscreenCovered" not in vertical_bar_runtime
          and "updatesEnabled: !fullscreenCovered" not in vertical_bar_runtime
          and "GameMode.hasFullscreenOnOutput" not in vertical_bar_runtime,
          "Vertical Bar must not gain a fullscreen mapping gate")
    for bar_surface in (bar_runtime, vertical_bar_runtime, bar_content, vertical_bar_content):
        for forbidden_corner_owner in (
            "PerimeterTokens.frameRadius",
            "screenEdge?.radius",
            "BAR-SCREEN-EDGE-CORNER-LOCK",
            "RoundCorner {",
            "PathArc {",
        ):
            check(forbidden_corner_owner not in bar_surface,
                  f"Bar surfaces must not create a second physical corner owner: {forbidden_corner_owner}")

    media = read("modules/bar/Media.qml")
    check("PopupWindow" not in media,
          "Bar Media must not restore detached PopupWindow surfaces")
    check(media.count("StyledPopup {") >= 1,
          "Bar Media expanded controls must use the connected StyledPopup")
    check("BarMediaPopup {" in media,
          "Bar Media must preserve its expanded control content inside the connected surface")
    check("hoverActivates: true" in media
          and "keyboardFocus: root.barMediaPopupVisible" in media,
          "Media hover popup must not steal keyboard focus unless explicitly pinned")
    for token in (
        "readonly property real restingX: overflowing",
        "Math.max(0, (width - titleText.implicitWidth) / 2)",
        "x: titleScroller.restingX",
        "horizontalAlignment: titleScroller.overflowing",
        "? Text.AlignLeft : Text.AlignHCenter",
        "marqueeRow.x = titleScroller.restingX",
    ):
        check(token in media,
              f"Bar Media short-title centering contract missing: {token}")
    check("width: titleScroller.overflowing ? implicitWidth : titleScroller.width" not in media,
          "Short Bar Media titles must not stretch back to the old left-aligned label width")

    taskbar_preview = read("modules/bar/BarTaskbarPreview.qml")
    check("StyledPopup {" in taskbar_preview,
          "Taskbar window previews must use the connected bar popout shell")
    check("PopupWindow {" not in taskbar_preview,
          "Taskbar window previews must not restore the detached PopupWindow shell")
    check("GlassBackground {" not in taskbar_preview,
          "Taskbar window previews must not draw a second floating card inside the connected shell")
    check("anchorItem" in taskbar_preview and "previewOpen" in taskbar_preview,
          "Taskbar preview must preserve real button anchoring and hover lifecycle")

    tray = read("modules/bar/SysTray.qml")
    check("alternativeVisibleCondition: root.trayOverflowOpen" in tray,
          "Tray overflow must use the shared connected visibility lifecycle")
    check("active: root.trayOverflowOpen" not in tray,
          "Tray overflow must not bypass the retract lifecycle by overriding LazyLoader.active")

    check(not (ROOT / "modules/bar/ClockWidgetTooltip.qml").exists(),
          "Retired ClockWidgetTooltip must not return as a standalone hover surface")

    connected_bar_popouts = {
        "modules/bar/TimerIndicatorTooltip.qml": "StyledPopup {",
        "modules/bar/ShellUpdateIndicator.qml": "StyledPopup {",
        "modules/bar/BatteryPopup.qml": "StyledPopup {",
        "modules/bar/ResourcesPopup.qml": "StyledPopup {",
    }
    for path, connected_shell in connected_bar_popouts.items():
        source = read(path)
        check(connected_shell in source,
              f"{path} must use the shared connected bar popout shell")
        check("PopupWindow" not in source,
              f"{path} must not restore a detached PopupWindow surface")

    bar_runtime = read("modules/bar/Bar.qml")
    check("cornerStyle" not in bar_runtime
          and "appearance?.globalStyle" not in bar_runtime
          and "rebuildKey" not in bar_runtime,
          "Live Classic Bar must leave legacy normalization to SettingsPageRegistry")
    config_qml = read("modules/common/Config.qml")
    defaults_json = read("defaults/config.json")
    appearance_qml = read("modules/common/Appearance.qml")
    shell_layout = read("services/ShellLayoutController.qml")
    check("property int cornerStyle: 0" in config_qml,
          "Classic Bar schema default must be Hug")
    check('"cornerStyle": 0' in defaults_json,
          "Classic Bar persisted default must be Hug")
    check("property JsonObject screenEdge: JsonObject {" in config_qml
          and "property int radius: 25" in config_qml,
          "Screen Edge schema must retain the shared 25px corner-radius default")
    check('"screenEdge": {' in defaults_json
          and '"radius": 25' in defaults_json,
          "Persisted Screen Edge radius default must remain 25px")
    check("property JsonObject physicalShadow: JsonObject {" in config_qml
          and "property bool enabled: true" in config_qml
          and "property int size: 15" in config_qml
          and "property real opacity: 0.70" in config_qml,
          "Physical Screen Edge shadow schema must default to Caelestia 15px/70%")
    check('"physicalShadow": {' in defaults_json
          and '"enabled": true' in defaults_json
          and '"size": 15' in defaults_json
          and '"opacity": 0.7' in defaults_json,
          "Persisted physical Screen Edge shadow defaults must match Caelestia")
    check("property int material: 0" in config_qml
          and '"material": 0' in defaults_json,
          "Material global-style compatibility corner must resolve to Hug")
    check("Config.options?.bar?.cornerStyle" not in appearance_qml,
          "Shared Bar sizing must not branch on retired cornerStyle")
    check("Config.options?.bar?.cornerStyle" not in shell_layout,
          "Shell layout reservation must not branch on retired cornerStyle")
    check("appearanceStyle" not in shell_layout
          and "bar?.pill" not in shell_layout
          and "bar.pill" not in shell_layout,
          "Shell layout reservation must use canonical Hug geometry only")
    # The active Hug renderer still shares internal geometry/color paths with
    # historical styles. Keep bridge inputs frozen to canonical Hug values until
    # those renderer paths are split; never reconnect them to persisted config.
    for canonical_bar_bridge in (
        "readonly property int cornerStyle: 0",
        "readonly property bool floatingStyle: false",
        "readonly property bool cardStyleEverywhere: false",
        "readonly property bool zzzDetachedRounded: false",
        "readonly property real barMargin: 0",
        "readonly property bool nativeBlurGeometryExact",
    ):
        check(canonical_bar_bridge in bar_content,
              f"Horizontal Hug bridge lost its canonical frozen input: {canonical_bar_bridge}")
    for retired_runtime_token in ("effectiveCornerStyle", "floatStyleShadow", "barFillInner"):
        check(retired_runtime_token not in bar_runtime,
              f"Classic Bar runtime must not retain retired corner-style branch: {retired_runtime_token}")
    for retired_surface_key in ("floatStyleShadow", "blurBackground"):
        check(retired_surface_key not in config_qml
              and retired_surface_key not in defaults_json,
              f"Retired Bar surface config must not remain in schema/defaults: {retired_surface_key}")
    bar_surface_cleanup = read("sdata/migrations/045-retired-bar-surface-state.sh")
    check("del(.bar.floatStyleShadow, .bar.blurBackground)" in bar_surface_cleanup,
          "Migration 045 must remove persisted retired Bar surface state")

    bar_settings = read("modules/settings/BarConfig.qml")
    bar_settings_compact = " ".join(bar_settings.split())
    bar_settings_dense = "".join(bar_settings.split())
    quick_settings = read("modules/settings/QuickConfig.qml")
    for retired_bar_control in (
        'Translation.tr("Corner style")',
        'Translation.tr("Float shadow")',
        'Translation.tr("Show background")',
        "Config.options?.bar?.blurBackground",
        'Config.setNestedValue("bar.blurBackground',
    ):
        check(retired_bar_control not in bar_settings,
              f"Canonical Bar settings must not instantiate retired UI: {retired_bar_control}")
    check('Translation.tr("Bar style")' not in quick_settings
          and 'settingsTaskSection: "screen"' not in quick_settings
          and 'Config.setNestedValue("bar.vertical"' not in quick_settings,
          "Canonical Quick settings must not recreate Bar/backdrop ownership")
    check('Config.options?.appearance?.screenEdge?.width ?? 10' in bar_settings
          and 'Config.setNestedValue("appearance.screenEdge.width",value)' in bar_settings_dense,
          "Bar settings must expose persistent Screen Edge width with a 10px default")
    check('Config.options?.appearance?.screenEdge?.radius ?? 25' in bar_settings
          and 'Config.setNestedValue("appearance.screenEdge.radius",value)' in bar_settings_dense
          and 'Translation.tr("Corner radius (px)")' in bar_settings
          and 'from: 0' in bar_settings
          and 'to: 96' in bar_settings,
          "Bar settings must expose the shared Screen Edge/Bar radius with a 25px default")
    check('appearance.screenEdge.shadow' not in bar_settings
          and 'Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true' in bar_settings
          and 'Config.setNestedValue("appearance.screenEdge.physicalShadow.enabled",checked)' in bar_settings_dense
          and 'Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15' in bar_settings
          and 'Config.setNestedValue("appearance.screenEdge.physicalShadow.size",value)' in bar_settings_dense
          and 'Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70' in bar_settings
          and 'Config.setNestedValue("appearance.screenEdge.physicalShadow.opacity",value/100)' in bar_settings_dense,
          "Screen Edge settings must control only the dedicated physical shadow owner")

    dock_config = read("modules/settings/DockConfig.qml")
    dock_config_lower = dock_config.lower()
    for legacy_style in ('value: "pill"', 'value: "macos"', 'value: "island"', 'value: "m3"'):
        check(legacy_style not in dock_config_lower,
              f"Dock settings must not expose legacy style option {legacy_style}")
    check('panelFamily !== "waffle"' in dock_config,
          "Waffle must remain a separate panel family rather than a Dock style")
    check("Dock uses the Panel surface style." in dock_config,
          "Dock settings must describe Panel as the canonical surface style")
    for retired_dock_component in (
        "DockPillItem.qml",
        "DockMacItem.qml",
        "DockMacBackground.qml",
    ):
        check(not (ROOT / "modules/dock" / retired_dock_component).exists(),
              f"Retired Dock style component must stay absent: {retired_dock_component}")
    dock_app_button = read("modules/dock/DockAppButton.qml")
    dock_button = read("modules/dock/DockButton.qml")
    check(not (ROOT / "modules/dock/DockWindowPreview.qml").exists(),
          "Dock hover uses app actions; retired window preview must stay absent")
    dock_qmldir = read("modules/dock/qmldir")
    check(not (ROOT / "modules/dock/DockSeparator.qml").exists()
          and "DockSeparator" not in dock_qmldir,
          "Unused DockSeparator component must stay removed")
    check("property string dockPosition:" not in dock_button
          and dock.count("dockPosition: root.position") == 2,
          "Dock buttons must not retain the unused position API while DockApps keeps preview placement")
    check("property alias hoverTimer:" not in dock_app_button,
          "Dock app buttons must not export an unused hover timer alias")
    for retired_dock_token in (
        "pillStyle",
        "macosStyle",
        "DockPillItem",
        "DockMacItem",
        "macHoveredIndex",
    ):
        check(retired_dock_token not in dock_app_button,
              f"Canonical Dock app button must not branch on retired style: {retired_dock_token}")
    for dead_dock_button_api in (
        "property int listIndex:",
        "property bool smartIndicator:",
        "property bool showAllDots:",
        "property int maxDots:",
    ):
        check(dead_dock_button_api not in dock_app_button,
              f"Dock app button must not retain unused delegate API: {dead_dock_button_api}")

    check(not (ROOT / "modules/pill").exists(),
          "Retired Pill compatibility module must stay absent")
    check("qs.modules.pill" not in dock_app_button
          and "PillTheme" not in dock_app_button
          and "Appearance.colors.colPrimary" in dock_app_button,
          "Dock Ricelin interactions must consume active Appearance tokens directly")
    for ricelin_consumer in (
        "modules/overview/SearchWidget.qml",
        "modules/sidebarLeft/SidebarLeftContent.qml",
        "modules/sidebarRight/SidebarRightContent.qml",
        "modules/sidebarRight/CompactSidebarRightContent.qml",
    ):
        source = read(ricelin_consumer)
        check("qs.modules.pill" not in source
              and "IslandPanel" not in source
              and "RicelinSurface {" in source,
              f"{ricelin_consumer} must use the canonical active Ricelin surface directly")

    check(not (ROOT / "services/MascotChaos.qml").exists(),
          "Retired MascotChaos service must stay absent")
    services_qmldir = read("services/qmldir")
    check("MascotChaos" not in services_qmldir,
          "Retired MascotChaos service must not be exported")
    for mascot_consumer in (
        "modules/waffle/bar/WaffleBar.qml",
        "modules/background/widgets/AbstractBackgroundWidget.qml",
    ):
        source = read(mascot_consumer)
        check("MascotChaos" not in source
              and "_chaos" not in source
              and "_quake" not in source,
              f"{mascot_consumer} must not retain dead mascot response machinery")

    settings_registry = read("modules/settings/SettingsPageRegistry.qml")
    check('Config.setNestedValue("dock.style", "panel")' in settings_registry,
          "Legacy Dock styles must normalize to Panel")
    check('Config.setNestedValue("language.ui", "en_US")' in settings_registry,
          "Legacy UI locales must normalize to canonical en_US")
    check('Config.setNestedValue("bar.cornerStyle", 0)' in settings_registry,
          "Legacy Classic Bar corner styles must normalize to Hug")
    check('Config.setNestedValue("bar.showBackground", true)' in settings_registry,
          "Legacy transparent Classic Bar state must normalize to the structural Hug surface")
    check("_migrateLegacyScreenEdgeShadow" in settings_registry
          and 'Config.setNestedValue("appearance.screenEdge.shadow.size", 15)' in settings_registry
          and 'Config.setNestedValue("appearance.screenEdge.shadow.opacity", 0.70)' in settings_registry,
          "Legacy 12px/24% Screen Edge shadow must migrate to the Caelestia 15px/70% baseline")
    check('Config.setNestedValue("sidebar.style", "panel")' in settings_registry
          and 'Config.setNestedValue("sidebar.cardStyle", false)' in settings_registry,
          "Legacy Sidebar Island/Card values must normalize to Panel/non-card")
    check("BarConfigHugOnly" not in settings_registry
          and "QuickConfigHugOnly" not in settings_registry,
          "Settings registry must route canonical Quick/Bar pages without compatibility facades")
    settings_registry_data = read("modules/settings/SettingsPageRegistryData.qml")
    check('label: Translation.tr("Bar background")' not in settings_registry_data,
          "Settings search source must not retain the retired Bar background toggle")
    check('label: Translation.tr("Sidebar style")' not in settings_registry_data,
          "Settings search source must not retain the retired Sidebar surface selector")
    check('label: Translation.tr("Corner radius (px)")' in settings_registry_data
          and 'description: Translation.tr("Set Screen Edge, Bar and outward popup contact radius")' in settings_registry_data,
          "Settings search must expose the shared Screen Edge/Bar/popup contact radius")
    check('label: Translation.tr("Screen edge shadow")' in settings_registry_data
          and 'description: Translation.tr("Configure Screen Edge and connected surface shadows")' in settings_registry_data,
          "Settings search must expose the shared Screen Edge/connected-surface shadow controls")

    for connected_shadow_path in (
        "modules/sidebarLeft/SidebarLeftContent.qml",
        "modules/sidebarRight/SidebarRightContent.qml",
        "modules/sidebarRight/CompactSidebarRightContent.qml",
        "modules/onScreenKeyboard/OnScreenKeyboard.qml",
    ):
        connected_shadow_source = read(connected_shadow_path)
        check("ColorUtils.applyAlpha(Appearance.colors.colShadow" in connected_shadow_source
              and "Appearance.m3colors.m3shadow" not in connected_shadow_source,
              f"{connected_shadow_path} must retain the connected-surface themed shadow ink")
        check("physicalShadow" not in connected_shadow_source,
              f"{connected_shadow_path} must not consume the physical Screen Edge shadow owner")

    for shared_settings_shadow_path in (
        "modules/settings/SettingsOverlay.qml",
        "modules/settings/SettingsFocus.qml",
    ):
        shared_settings_shadow_source = read(shared_settings_shadow_path)
        check("screenEdge?.physicalShadow?.enabled ?? true" in shared_settings_shadow_source
              and "screenEdge?.physicalShadow?.size ?? 15" in shared_settings_shadow_source
              and "screenEdge?.physicalShadow?.opacity ?? 0.70" in shared_settings_shadow_source
              and "Appearance.m3colors.m3shadow" in shared_settings_shadow_source,
              f"{shared_settings_shadow_path} must use the same physical elevation tokens")

    check("screenEdge?.physicalShadow?.enabled ?? true" in styled_popup
          and "screenEdge?.physicalShadow?.size ?? 15" in styled_popup
          and "screenEdge?.physicalShadow?.opacity ?? 0.70" in styled_popup
          and "Qt.alpha(Appearance.m3colors.m3shadow, root._edgeShadowOpacity)" in styled_popup
          and "screenEdge?.shadow?.enabled" not in styled_popup,
          "All ii Bar StyledPopup surfaces must share the visible Screen Edge shadow controls and ink")

    for shared_edge_shadow_source, label in (
        (sidebar_host, "SidebarHost"),
        (dashboard, "OverviewDashboard"),
        (dock, "Dock"),
    ):
        check("screenEdge?.physicalShadow?.enabled ?? true" in shared_edge_shadow_source
              and "screenEdge?.physicalShadow?.size ?? 15" in shared_edge_shadow_source
              and "screenEdge?.physicalShadow?.opacity ?? 0.70" in shared_edge_shadow_source
              and "Appearance.m3colors.m3shadow" in shared_edge_shadow_source,
              f"{label} must share the visible Screen Edge shadow controls and Material shadow ink")


    osk_shadow = read("modules/onScreenKeyboard/OnScreenKeyboard.qml")
    check("visible: root._oskResident" in osk_shadow
          and "root.screenEdgeShadowEnabled" in osk_shadow
          and "root.screenEdgeShadowSize > 0" in osk_shadow
          and "root.screenEdgeShadowOpacity > 0" in osk_shadow,
          "OSK connected shadow must remain resident through the whole enter/exit slide")

    sidebars_config = read("modules/settings/SidebarsConfig.qml")
    check('Translation.tr("Use Card style")' not in sidebars_config
          and 'Translation.tr("Island")' not in sidebars_config
          and 'Config.setNestedValue("sidebar.style"' not in sidebars_config,
          "Sidebar General settings must not expose Island or Card surface choices")

    shell = read("shell.qml")
    check("DevNavigation.registerSettingsPages(SettingsPageRegistry.pages)" in shell,
          "Shell startup must materialize SettingsPageRegistry so legacy config normalization runs without opening Settings")

    settings_sources = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "modules/settings").glob("*.qml")
    )
    check("connectedPerimeter" not in settings_sources,
          "Connected Perimeter must not gain a user-facing settings key")

    translation = read("services/Translation.qml")
    check('availableLanguages: ["en_US"]' in translation,
          "Translation runtime must expose only en_US")
    check('languageCode: "en_US"' in translation,
          "Translation runtime languageCode must stay canonical en_US")
    check('Quickshell.shellPath("translations")' in translation and '/en_US.json' in translation,
          "Translation runtime must load the canonical en_US catalog")
    locale_files = sorted(path.name for path in (ROOT / "translations").glob("*.json"))
    check(locale_files == ["en_US.json"],
          f"Only translations/en_US.json is allowed; found {locale_files}")

    general_config = read("modules/settings/GeneralConfigCore.qml")
    check("Interface Language" not in general_config,
          "English-only settings must not reintroduce an Interface Language selector")
    check("Generate translations" not in general_config,
          "English-only settings must not reintroduce translation generation UI")

    if failures:
        print("Shell surface contract regression(s):")
        for failure in failures:
            print(f"  - {failure}")
        raise SystemExit(1)

    print("Shell surface contracts: OK")


if __name__ == "__main__":
    main()
