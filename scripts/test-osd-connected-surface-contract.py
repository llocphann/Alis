#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
osd = (ROOT / "modules/onScreenDisplay/OnScreenDisplay.qml").read_text()
value = (ROOT / "modules/onScreenDisplay/OsdValueIndicator.qml").read_text()
keyboard = (ROOT / "modules/onScreenDisplay/indicators/KeyboardLayoutIndicator.qml").read_text()

for token in (
    "import qs.modules.common.perimeter",
    '["volume", "brightness", "mic", "keyboardLayout"]',
    "function _iiBarOwnsOutput(outputName): bool",
    "function _attachmentThicknessFor(outputName): real",
    "ConnectedSurfaceGeometry {",
    "connectorLength: 0",
    "seamOverlap: PerimeterTokens.abyssWeldDepth",
    "ConnectedSurfaceRevealClip {",
    "ConnectedSurfaceAbyssFrame {",
    "ConnectedSurfaceContentHost {",
    "ConnectedSurfaceBodyMask {",
    'joinTop: connectedGeometry.edge === "top"',
    "bodyItem: statusFrame.bodyItem",
    "visibleBodyRect: statusFrame.visibleBodyRect",
    "item.connectedSurface = true",
):
    assert token in osd, token

for source in (value, keyboard):
    assert "property bool connectedSurface: false" in source
    assert "visible: !root.connectedSurface" in source
    assert 'root.connectedSurface ? "transparent"' in source

assert "wallpaperBackdropEnabled: !root.connectedSurface" in value
print("Connected compact OSD surface contract: OK")
