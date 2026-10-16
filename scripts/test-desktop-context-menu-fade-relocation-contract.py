#!/usr/bin/env python3
"""Desktop context popup: anchor to the output window on every remap (Niri)."""
from pathlib import Path
import re

repo = Path(__file__).resolve().parents[1]
desktop = (repo / "modules/background/Background.qml").read_text()
menu = (repo / "modules/common/widgets/ContextMenu.qml").read_text()

bare = desktop.split("id: desktopContextMenu", 1)[1].split("model:", 1)[0]
managed = desktop.split("id: desktopItemContextMenu", 1)[1].split("WidgetCanvas {", 1)[0]

for label, block in (("desktop", bare), ("desktop item", managed)):
    assert block.count("popupAbove:") == 1, (label, "duplicate popupAbove")
    assert block.count("popupAdjustment:") == 1, (label, "duplicate popupAdjustment")
    assert block.count("cursorAnchorWindow:") == 1, (label, "missing window anchor")
    assert "cursorAnchorWindow: bgRoot" in block, label
    assert "cursorSlide: true" in block, label
    assert "scaleContent: false" in block, label
    assert "closeOnHoverLost: false" in block, label
    assert "closeOnFocusLost: false" in block, label
    for token in ("PopupAdjustment.FlipX", "PopupAdjustment.FlipY",
                  "PopupAdjustment.SlideX", "PopupAdjustment.SlideY"):
        assert token in block, (label, token)
    assert "PopupAdjustment.Resize" not in block, label

# Scene-local coordinates are exactly the parent PanelWindow's coordinates.
# mapToItem(anchor.parent) can carry stale item geometry after popup recreation.
assert "id: desktopContextHitArea" in desktop
assert re.search(r"desktopContextHitArea\.mapToItem\(\s*null, mouse\.x, mouse\.y\)", desktop)
assert re.search(r"desktopItemDelegate\.mapToItem\(\s*null, anchorX, anchorY\)", desktop)
assert "desktopContextMenu.requestOpenAt(point.x, point.y)" in desktop
assert "desktopItemContextMenu.requestOpenAt(position.x, position.y, menuModel)" in desktop

# Crucial Niri regression: when Loader remaps a popup, use the desktop
# PanelWindow and an explicit 1x1 cursor rect. Do not map before the anchor
# window has been installed or the compositor can place it at (0,0).
assert "property var cursorAnchorWindow: null" in menu
assert "property real cursorAnchorX: 0" in menu
assert "property real cursorAnchorY: 0" in menu
assert "root.cursorAnchorX = nextX" in menu
assert "root.cursorAnchorY = nextY" in menu
assert "root.cursorAnchorX = root.relocationX" in menu
assert "root.cursorAnchorY = root.relocationY" in menu
assert "property bool cursorAnchorReady: false" in menu
assert "visible: !root.cursorSlide || popupWindow.cursorAnchorReady" in menu
assert "popupWindow.anchor.window = root.cursorAnchorWindow;" in menu
assert "popupWindow.cursorAnchorReady = popupWindow.anchor.window !== null;" in menu
assert "item: root.cursorSlide ? null : root.anchorItem" in menu
assert "rect.x: root.cursorSlide ? Math.round(root.cursorAnchorX)" in menu
assert "rect.y: root.cursorSlide ? Math.round(root.cursorAnchorY)" in menu
assert "rect.width: root.cursorSlide ? 1" in menu
assert "rect.height: root.cursorSlide ? 1" in menu
assert 'Quickshell.env("ALIS_CONTEXT_MENU_DEBUG")' in menu
assert "onAnchoring:" in menu

# Correct left-edge horizontal gravity; flip/slide near four output corners.
assert re.search(r"gravity:\s*root\.cursorSlide\s*\?\s*\(\(root\.popupAbove\s*\?\s*Edges\.Top\s*:\s*Edges\.Bottom\)\s*\|\s*Edges\.Right\)", menu)
assert re.search(r"edges:\s*root\.cursorSlide\s*\?\s*\(\(root\.popupAbove\s*\?\s*Edges\.Top\s*:\s*Edges\.Bottom\)\s*\|\s*Edges\.Left\)", menu)

# Existing slide-only motion and newest-click-wins relocation remain intact.
for snippet in (
    "function requestOpenAt(x: real, y: real, newModel: var): void",
    "if (root.relocationQueued)", "root.relocationX = nextX",
    "root.relocationY = nextY", "root.item.slideForRelocation()",
    "function slideForRelocation(): void", "function commitRelocation(): void",
    "root.active = false", "Qt.callLater(() => {",
    "ScriptAction { script: root.commitRelocation() }",
    "GlobalStates.activeContextMenu && GlobalStates.activeContextMenu !== root",
    "id: openAnim", "id: closeAnim", "id: relocationAnim",
    'property: "sourceEdgeMargin"', "opacity: root.cursorSlide ? 1",
    "enabled: Appearance.animationsEnabled && !root.cursorSlide",
):
    assert snippet in menu, snippet

assert "property real relocationOpacity" not in menu
assert "fadeOnlyOpenAnim" not in menu
assert "fadeOnlyCloseAnim" not in menu
print("PASS: desktop cursor popup window anchor, remap, and slide-only contracts")
