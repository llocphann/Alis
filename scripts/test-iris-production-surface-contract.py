#!/usr/bin/env python3
"""Static regression gate for the production iRiS split-composition popup path."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        raise SystemExit(f"iRiS production surface contract failed: {label}: {token}")


def forbid(text: str, token: str, label: str) -> None:
    if token in text:
        raise SystemExit(f"iRiS production surface contract failed: {label}: {token}")


styled = read("modules/bar/StyledPopup.qml")
frame = read("modules/common/perimeter/ConnectedSurfaceIrisFrame.qml")
field = read("modules/common/perimeter/ConnectedSurfaceIrisField.qml")
mask = read("modules/common/perimeter/ConnectedSurfaceBodyMask.qml")
edge_surface = read("modules/common/perimeter/ConnectedSurfaceIrisEdgeSurface.qml")
sidebar = read("modules/sidebar/SidebarHost.qml")
settings_overlay = read("modules/settings/SettingsOverlay.qml")
settings_focus = read("modules/settings/SettingsFocus.qml")
dashboard = read("modules/overview/OverviewDashboard.qml")
dock = read("modules/dock/Dock.qml")
search_widget = read("modules/overview/SearchWidget.qml")
search_bar = read("modules/overview/SearchBar.qml")
tokens = read("modules/common/perimeter/PerimeterTokens.qml")
qmldir = read("modules/common/perimeter/qmldir")
motion = read("modules/common/SurfaceMotion.qml")
waffle = read("modules/waffle/bar/BarPopup.qml")

production_qsb = ROOT / "modules/common/perimeter/IrisField.frag.qsb"
production_frag = ROOT / "modules/common/perimeter/IrisField.frag"

# The historical corner POC is evidence, not the production shader authority.
# Lock the shipped binary/source pair to the current tangent-aware production
# generation without requiring it to remain byte-identical to that old POC.
if production_qsb.stat().st_size != 18582:
    raise SystemExit("iRiS production surface contract failed: unexpected QSB byte size")
production_frag_text = production_frag.read_text(encoding="utf-8")
for token in (
    "float roundedBoxCorners(",
    "float tangentAwareBody(",
    "primaryRelation > 0.5 && tangentRelation > 0.5",
    "also < -0.5 || also > 0.5",
):
    require(production_frag_text, token, "tangent-aware production shader")

for token in (
    "ConnectedSurfaceGeometry {",
    "ConnectedSurfaceRevealClip {",
    "ConnectedSurfaceIrisFrame {",
    "ConnectedSurfaceContentHost {",
    "ConnectedSurfaceBodyMask {",
    "fuseDepth: PerimeterTokens.irisFuseDepth",
    "externalFrameThickness: root._screenEdgeThickness",
    "readonly property real _popupScreenMargin: root._screenEdgeThickness",
    "seamOverlap: PerimeterTokens.irisWeldDepth",
    "visibleBodyRect: frame.visibleBodyRect",
    "progress: root.revealProgress",
    "mask: connectedMask",
    "screenEdge?.physicalShadow?.enabled ?? true",
    "screenEdge?.physicalShadow?.size ?? 15",
    "screenEdge?.physicalShadow?.opacity ?? 0.70",
    "Qt.alpha(Appearance.m3colors.m3shadow, root._edgeShadowOpacity)",
):
    require(styled, token, "StyledPopup cutover")

for token in ("ConnectedSurfaceFrame {", "ConnectedSurfaceMask {"):
    forbid(styled, token, "StyledPopup legacy renderer")
forbid(styled, "screenEdge?.shadow?.enabled", "StyledPopup obsolete private shadow owner")

for token in (
    "function clipExternalOwners(raw, primaryOverlap)",
    "readonly property rect rawPaintBounds:",
    "readonly property rect paintBounds:",
    "readonly property rect visibleBodyRect:",
    "readonly property rect sdfBodyRect:",
    "x: root.sdfBodyRect.x",
    "y: root.sdfBodyRect.y",
    "readonly property var ownerShape:",
    "readonly property var frameStartShape: !root.tangentStartJoined",
    "readonly property var frameEndShape: !root.tangentEndJoined",
    "readonly property var popupShape:",
    "readonly property bool needsEndJoinAux:",
    'joins: ["owner", "frame-end"]',
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
    "sourceRect: Qt.rect(",
    "hideSource: true",
    "smooth: true",
    "ConnectedSurfaceIrisField {",
    "readonly property bool bodyHovered: bodyHover.hovered",
):
    require(frame, token, "ConnectedSurfaceIrisFrame")

for token in ("ConnectedSurfaceJoinFlares", "ConnectedSurfaceConnector", "Canvas {", "RectangularShadow {"):
    forbid(frame, token, "production renderer patch geometry")
assert frame.count("ConnectedSurfaceIrisField {") == 2, (
    "Visible surface and shadow mask must use the same iRiS field implementation"
)
assert frame.index("id: shadowMaskField") < frame.index("id: isolatedShadow") < frame.index("id: field"), (
    "The shadow mask and clipped blur must render below the visible field"
)

for token in (
    'fragmentShader: Qt.resolvedUrl("IrisField.frag.qsb")',
    "readonly property vector4d viewport:",
    "pass.x, pass.y",
    "readonly property vector2d screen:",
    "readonly property vector4d shape19:",
    "readonly property vector4d joinE:",
    "readonly property vector4d alsoE:",
    "shaderCompiled: pass.status === ShaderEffect.Compiled",
):
    require(field, token, "ConnectedSurfaceIrisField")

for token in ("_sourceStrip", "_middleStrip", "_bodyStrip", "connectorItem"):
    forbid(mask, token, "body-only compositor mask")
require(mask, "visibleBodyRect", "body-only compositor mask")
require(tokens, "readonly property real irisFuseDepth: 30", "validated G2 fuse token")
require(tokens, "readonly property real irisWeldDepth: 3", "validated G2 weld token")
for token in ("joinFlareRadius", "joinFlareCrossScale"):
    forbid(tokens, token, "retired flare token")
for path in (
    "modules/common/perimeter/ConnectedSurfaceJoinFlares.qml",
    "modules/common/perimeter/PerimeterCornerShadow.qml",
    "modules/common/widgets/RoundCorner.qml",
):
    if (ROOT / path).exists():
        raise SystemExit(f"iRiS production surface contract failed: retired wedge source still exists: {path}")

for export in (
    "ConnectedSurfaceIrisField 1.0 ConnectedSurfaceIrisField.qml",
    "ConnectedSurfaceIrisFrame 1.0 ConnectedSurfaceIrisFrame.qml",
    "ConnectedSurfaceIrisEdgeSurface 1.0 ConnectedSurfaceIrisEdgeSurface.qml",
    "ConnectedSurfaceBodyMask 1.0 ConnectedSurfaceBodyMask.qml",
):
    require(qmldir, export, "perimeter module export")

for token in (
    "required property rect bodyRect",
    "required property string edge",
    "property real weldDepth: PerimeterTokens.irisWeldDepth",
    "readonly property rect weldedBodyRect:",
    "ConnectedSurfaceIrisFrame {",
):
    require(edge_surface, token, "ConnectedSurfaceIrisEdgeSurface")

for token in (
    "ConnectedSurfaceIrisEdgeSurface {",
    "ownerThickness: root.screenEdgeHoverWidth",
    "sidebarContentLoader.x + sidebarContentLoader.animTranslateX",
    "progress: root.presentationOpen || sidebarContentLoader.animating ? 1 : 0",
    "readonly property real hiddenTranslateDistance:",
    "exclusionMode: ExclusionMode.Ignore",
    "? -root.hiddenTranslateDistance",
    ": root.hiddenTranslateDistance",
):
    require(sidebar, token, "Sidebar iRiS edge cutover")
for token in ("ConnectedSurfaceJoinFlares {", "ConnectedSurfaceConnector {"):
    forbid(sidebar, token, "Sidebar legacy edge renderer")

for settings in (settings_overlay, settings_focus):
    for token in (
        "ConnectedSurfaceIrisEdgeSurface {",
        'edge: "bottom"',
        "ownerThickness: root._screenEdgeThickness",
        "settingsPanel.height - root._screenEdgeThickness - height",
        "screenEdge?.physicalShadow?.enabled ?? true",
        "screenEdge?.physicalShadow?.size ?? 15",
        "screenEdge?.physicalShadow?.opacity ?? 0.70",
        "Appearance.m3colors.m3shadow",
    ):
        require(settings, token, "Settings iRiS edge cutover")

for token in (
    "ConnectedSurfaceIrisEdgeSurface {",
    'edge: "bottom"',
    "ownerThickness: root.attachmentThickness",
    "root.height + root.attachmentThickness",
    "SearchWidget {",
    "embeddedSurface: true",
    "directBottomAttachment: false",
    "id: dashboardSurfaceLayer",
    "z: 2",
    "id: dashboardIrisSurface",
    "z: 1",
):
    require(dashboard, token, "Dashboard/Search iRiS edge cutover")
forbid(dashboard, "ConnectedSurfaceJoinFlares {", "Dashboard legacy edge renderer")

for token in (
    "ConnectedSurfaceIrisEdgeSurface {",
    "id: dockIrisSurface",
    "edge: root.position",
    "ownerThickness: dockRoot.screenEdgeThickness",
    "dockMouseArea.x + dockBackground.x + dockConnectedBody.x",
    "screenEdge?.physicalShadow?.enabled ?? true",
    "screenEdge?.physicalShadow?.size ?? 15",
    "screenEdge?.physicalShadow?.opacity ?? 0.70",
    "Qt.alpha(Appearance.m3colors.m3shadow, dockRoot.screenEdgeShadowOpacity)",
):
    require(dock, token, "Dock iRiS edge cutover")
forbid(dock, "StyledRectangularShadow {", "Dock detached legacy shadow")

for source, label in (
    (sidebar, "Sidebar"),
    (dashboard, "Dashboard"),
    (dock, "Dock"),
):
    for token in (
        "screenEdge?.physicalShadow?.enabled ?? true",
        "screenEdge?.physicalShadow?.size ?? 15",
        "screenEdge?.physicalShadow?.opacity ?? 0.70",
        "Appearance.m3colors.m3shadow",
    ):
        require(source, token, f"{label} shared Screen Edge shadow")
for token in ("ConnectedSurfaceIrisEdgeSurface", "ConnectedSurfaceJoinFlares", "joinFlareRadius"):
    forbid(search_widget, token, "Embedded SearchWidget must not double-paint Dashboard edge ownership")
for source_path in (
    "modules/overview/SearchWidget.qml",
    "modules/onScreenKeyboard/OnScreenKeyboard.qml",
    "modules/common/perimeter/ConnectedSurfaceFrame.qml",
):
    source = read(source_path)
    forbid(source, "ConnectedSurfaceJoinFlares", f"{source_path} legacy wedge renderer")
    forbid(source, "joinFlareRadius", f"{source_path} legacy flare token")

for token in (
    'colBackground: "transparent"',
    'colBackgroundHover: "transparent"',
    'colRipple: "transparent"',
    "rippleEnabled: false",
    "pressScaleEnabled: false",
):
    require(search_bar, token, "SongRec geometry cleanup")

require(motion, 'readonly property string mode: "slide"', "immutable motion")
require(waffle, "ConnectedSurfaceFrame {", "Waffle compatibility")
require(waffle, "ConnectedSurfaceMask {", "Waffle compatibility")
for token in ("ConnectedSurfaceIrisFrame {", "ConnectedSurfaceBodyMask {"):
    forbid(waffle, token, "Waffle must remain unchanged by ii cutover")

print("iRiS production surface contract: PASS")
