#!/usr/bin/env python3
"""Desktop context popup: slide-only motion, precise pointer anchor, safe remap."""
from pathlib import Path
import re

repo = Path(__file__).resolve().parents[1]
desktop = (repo / "modules/background/Background.qml").read_text()
menu = (repo / "modules/common/widgets/ContextMenu.qml").read_text()

bare = desktop.split("id: desktopContextMenu", 1)[1].split("model:", 1)[0]
managed = desktop.split("id: desktopItemContextMenu", 1)[1].split("WidgetCanvas {", 1)[0]

# Catch the exact duplicate-property bug that previously prevented loading.
for label, block in (("desktop", bare), ("desktop item", managed)):
    assert block.count("popupAbove:") == 1, (label, "duplicate popupAbove")
    assert block.count("popupAdjustment:") == 1, (label, "duplicate popupAdjustment")
    assert "cursorSlide: true" in block, label
    assert "scaleContent: false" in block, label
    assert "fadeOnly: true" not in block, label
    assert "closeOnHoverLost: false" in block, label
    assert "closeOnFocusLost: false" in block, label
    for token in ("PopupAdjustment.FlipX", "PopupAdjustment.FlipY",
                  "PopupAdjustment.SlideX", "PopupAdjustment.SlideY"):
        assert token in block, (label, token)
    assert "PopupAdjustment.Resize" not in block, label
    assert "popupAbove: desktopMenuAnchor.y > bgRoot.height - 230" in block, label

# Map desktop and desktop-item click coordinates to the anchor's parent.
assert "id: desktopContextHitArea" in desktop
assert "desktopContextHitArea.mapToItem(" in desktop
assert "desktopMenuAnchor.parent, mouse.x, mouse.y" in desktop
assert "desktopContextMenu.requestOpenAt(point.x, point.y)" in desktop
assert "desktopItemDelegate.mapToItem(" in desktop
assert "desktopItemContextMenu.requestOpenAt(position.x, position.y, menuModel)" in desktop

# With only a vertical Edges.Top/Bottom flag, the popup is CENTERED around
# the cursor horizontally. Pair Edges.Left of the anchor with Edges.Right
# expansion of the popup to place its left edge at the clicked X position.
assert "property bool cursorSlide: false" in menu
assert re.search(r"gravity:\s*root\.cursorSlide\s*\?\s*\(\(root\.popupAbove\s*\?\s*Edges\.Top\s*:\s*Edges\.Bottom\)\s*\|\s*Edges\.Right\)", menu)
assert re.search(r"edges:\s*root\.cursorSlide\s*\?\s*\(\(root\.popupAbove\s*\?\s*Edges\.Top\s*:\s*Edges\.Bottom\)\s*\|\s*Edges\.Left\)", menu)

# Remap xdg-popup only after the old surface exits; newest click wins.
assert "function requestOpenAt(x: real, y: real, newModel: var): void" in menu
assert "if (root.relocationQueued)" in menu
assert "root.relocationX = nextX" in menu
assert "root.relocationY = nextY" in menu
assert "root.item.slideForRelocation()" in menu
assert "function slideForRelocation(): void" in menu
assert "function commitRelocation(): void" in menu
assert "root.relocationCommitting = true" in menu
assert "root.active = false" in menu
assert "Qt.callLater(() => {" in menu
assert "root.anchorItem.x = root.relocationX" in menu
assert "root.anchorItem.y = root.relocationY" in menu
assert "root.relocationModelProvided" in menu
assert "ScriptAction { script: root.commitRelocation() }" in menu
assert "GlobalStates.activeContextMenu && GlobalStates.activeContextMenu !== root" in menu

# Slide animation, no fading or scaling for either desktop menu.
assert "target: popupWindow" in menu
assert 'property: "sourceEdgeMargin"' in menu
assert "id: openAnim" in menu
assert "id: closeAnim" in menu
assert "id: relocationAnim" in menu
assert "opacity: root.cursorSlide ? 1" in menu
assert "enabled: Appearance.animationsEnabled && !root.cursorSlide" in menu
assert "property real relocationOpacity" not in menu
assert "fadeOnlyOpenAnim" not in menu
assert "fadeOnlyCloseAnim" not in menu

print("PASS: desktop context menu slide, cursor anchor, corner flip and remap contracts")
