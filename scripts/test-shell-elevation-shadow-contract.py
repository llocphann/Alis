#!/usr/bin/env python3
"""Guard rounded shell elevation without restoring retired perimeter painters."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(text: str, *tokens: str) -> None:
    for token in tokens:
        assert token in text, f"Missing shadow contract: {token}"


edge = source("modules/screenCorners/ScreenEdges.qml")
edge_fallback = source("modules/screenCorners/ScreenEdgeLegacyFallback.qml")
theme = source("modules/common/Appearance.qml")
popup = source("modules/bar/StyledPopup.qml")
abyss = source("modules/common/perimeter/ConnectedSurfaceAbyssFrame.qml")
shared = source("modules/common/widgets/StyledRectangularShadow.qml")
sidebar = source("modules/sidebar/SidebarHost.qml")
overview = source("modules/overview/OverviewDashboard.qml")
dashboard = source("modules/dashboard/DashboardContent.qml")
canvas = source("modules/dashboard/DashboardCanvas.qml")
settings = (
    source("modules/settings/SettingsOverlay.qml"),
    source("modules/settings/SettingsFocus.qml"),
)
bars = (
    source("modules/bar/BarContent.qml"),
    source("modules/verticalBar/VerticalBarContent.qml"),
)

# The physical frame is now a single analytic SDF pass. The old
# Shape/MultiEffect path is retained only as a fail-safe for packaged-QSB
# failure, and must not be constructed during the normal path.
require(edge,
    "readonly property bool physicalShadowActive:",
    "readonly property bool fullscreenCovered: outputName.length > 0",
    "GameMode.hasFullscreenOnOutput(outputName)",
    "updatesEnabled: mapped && !fullscreenCovered",
    "&& !frameWindow.fullscreenCovered",
    "&& !Appearance.gameModeMinimal",
    "ScreenEdgeField {",
    "id: frameField",
    "leftInset: frameWindow.frameLeftInset",
    "topInset: frameWindow.frameTopInset",
    "rightInset: frameWindow.frameRightInset",
    "bottomInset: frameWindow.frameBottomInset",
    "radius: root.rounding",
    "edgeColor: root.edgeColor",
    "elevationSize: root.physicalShadowSize",
    "elevationEnabled: frameWindow.physicalShadowActive",
    "id: legacyFramePainter",
    "readonly property var edgeRoot: root",
    "readonly property var frameHost: frameWindow",
    "active: frameField.shaderError",
    'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")',
)
require(edge_fallback,
    "import qs.modules.common",
    "import QtQuick.Shapes",
    "import QtQuick.Effects",
    "readonly property var edgeRoot: parent.edgeRoot",
    "readonly property var frameHost: parent.frameHost",
    "preferredRendererType: Shape.CurveRenderer",
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
    "shadowColor: Qt.alpha(",
    "Appearance.m3colors.m3shadow",
    "root.edgeRoot.physicalShadowOpacity",
)

# Fullscreen/minimal-mode optimization must never weaken the lifecycle lock:
# the FrameWindow remains mapped; only its painter/elevation work may gate.
frame_component = edge[
    edge.index("component FrameWindow:"):
    edge.index("component ReservationWindow:")
]
mapped_block = frame_component[
    frame_component.index("readonly property bool mapped:"):
    frame_component.index("// LOCKED BAR/SCREEN-EDGE INSETS:")
]
assert "fullscreen" not in mapped_block.lower()
assert "gameModeMinimal" not in mapped_block
shadow_block = frame_component[
    frame_component.index("readonly property bool physicalShadowActive:"):
    frame_component.index("// Primary physical Screen Edge painter:")
]
assert "!frameWindow.fullscreenCovered" in shadow_block
assert "!Appearance.gameModeMinimal" in shadow_block

primary_start = frame_component.index("ScreenEdgeField {")
fallback_start = frame_component.index("id: legacyFramePainter")
assert primary_start < fallback_start
fallback_block = frame_component[fallback_start:]
assert "active: frameField.shaderError" in fallback_block
assert 'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")' in fallback_block
assert "import QtQuick.Shapes" not in edge
assert "import QtQuick.Effects" not in edge
assert "Shape {" not in frame_component
assert "MultiEffect {" not in frame_component
assert edge_fallback.count("Shape {") == 1
assert "MultiEffect {" in edge_fallback
assert "PerimeterCornerShadow" not in edge
assert "RoundCorner {" not in edge

# Transparent materials are not transparent elevation ink.
require(theme, "property color colShadow: Qt.alpha(m3colors.m3shadow, 0.45)")
assert 'property color colShadow: m3colors.transparent' not in theme

# Connected corners must cast shadow from their actual SDF union, not a
# rectangular approximation of the body. Capture is bounded to the body/fuse
# reach, and both mask and final output respect the owning Screen Edge.
require(abyss,
    "readonly property real shadowTextureExtent:",
    "Math.max(0, root.shadowExtent) + root.fuse + root.aaReach + 2",
    "readonly property rect shadowMaskBounds:",
    "readonly property rect shadowPaintBounds:",
    "root.clipExternalOwners(root.rawShadowBounds, 0)",
    "id: shadowMaskField",
    "shapes: field.shapes",
    "paintBounds: root.shadowMaskBounds",
    "id: shadowTextureSource",
    "sourceItem: shadowMaskField",
    "sourceRect: root.rawShadowBounds",
    "id: blurredShadow",
    "source: shadowTextureSource",
    "blurEnabled: true",
    "blur: 1.0",
    "autoPaddingEnabled: false",
    "id: isolatedShadow",
    "sourceItem: blurredShadow",
    "sourceRect: Qt.rect(",
    "hideSource: true",
    "live: true",
    "id: field",
)
assert abyss.index("id: shadowMaskField") < abyss.index("id: blurredShadow") < abyss.index("id: isolatedShadow") < abyss.index("id: field")
assert "RectangularShadow {" not in abyss, "The connected shadow may not diverge from the Abyss silhouette"

for surface in (popup, sidebar, overview):
    require(surface, "Appearance.m3colors.m3shadow", "shadowEnabled:")
for surface in settings:
    require(surface,
        "ConnectedSurfaceAbyssEdgeSurface {",
        "Appearance.m3colors.m3shadow",
        "screenEdge?.physicalShadow?.enabled ?? true",
        "screenEdge?.physicalShadow?.size ?? 15",
        "screenEdge?.physicalShadow?.opacity ?? 0.70",
    )
    assert "sourceComponent: StyledRectangularShadow" not in surface

require(dashboard,
    "screenEdge?.physicalShadow?.enabled ?? true",
    "screenEdge?.physicalShadow?.size ?? 15",
    "screenEdge?.physicalShadow?.opacity ?? 0.70",
)
# The normal Bar is part of the physical perimeter, not a second local shadow.
for bar in bars:
    assert "sourceComponent: StyledRectangularShadow" not in bar

# Floating Dashboard and individual cards need distinct shadow owners.
require(dashboard,
    "StyledRectangularShadow {",
    "target: background",
    "Appearance.m3colors.m3shadow",
)
require(canvas,
    "clip: false",
    "id: canvas",
    "id: cardViewport",
    "clip: true",
    "StyledRectangularShadow {",
    "target: cardWrap",
    "z: -1",
    "Appearance.m3colors.m3shadow",
)
assert canvas.index("target: cardWrap") < canvas.index("id: cardViewport")
require(shared,
    "property color color: Appearance.colors.colShadow",
    "cached: !(root.joinTop || root.joinBottom",
)

print("Shell rounded elevation shadow contract: PASS")
