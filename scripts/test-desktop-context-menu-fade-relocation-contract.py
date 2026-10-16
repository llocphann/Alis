#!/usr/bin/env python3
"""Desktop context menus must re-map to the newest click, not move an active xdg-popup."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
desktop = (root / "modules/background/Background.qml").read_text()
menu = (root / "modules/common/widgets/ContextMenu.qml").read_text()

bare = desktop.split("id: desktopContextMenu", 1)[1].split("model:", 1)[0]
managed = desktop.split("id: desktopItemContextMenu", 1)[1].split("WidgetCanvas {", 1)[0]
for label, block in (("desktop", bare), ("desktop item", managed)):
    assert "fadeOnly: true" in block, label
    assert "scaleContent: false" in block, label
    assert "fadeOutDuration: 90" in block, label
    assert "fadeInDuration: 130" in block, label
    assert "closeOnHoverLost: false" in block, label
    assert "popupAdjustment: PopupAdjustment.SlideX | PopupAdjustment.SlideY" in block, label
    assert "popupAbove: desktopMenuAnchor.y > bgRoot.height - 230" in block, label
    # Duplicate QML property assignments make both ContextMenu instances invalid.
    assert block.count("popupAbove:") == 1, f"{label}: duplicate popupAbove assignment"

# The click source and the anchor are siblings; never assume event-local coords
# are the anchor's coordinate space.
assert "id: desktopContextHitArea" in desktop
assert "desktopContextHitArea.mapToItem(" in desktop
assert "desktopMenuAnchor.parent, mouse.x, mouse.y" in desktop
assert "desktopContextMenu.requestOpenAt(point.x, point.y)" in desktop
assert "desktopItemDelegate.mapToItem(" in desktop
assert "desktopItemContextMenu.requestOpenAt(position.x, position.y, menuModel)" in desktop

# A Wayland PopupWindow that is already mapped must be destroyed BEFORE the
# requested anchor is moved: anchor.updateAnchor() alone doesn't move it on Niri.
assert "property bool relocationQueued: false" in menu
assert "property bool relocationCommitting: false" in menu
assert "function requestOpenAt(x: real, y: real, newModel: var): void" in menu
assert "root.relocationQueued = true" in menu
assert "root.relocationX = nextX" in menu
assert "root.relocationY = nextY" in menu
assert "root.item.fadeForRelocation()" in menu
assert "function commitRelocation(): void" in menu
assert "root.relocationCommitting = true" in menu
assert "root.active = false" in menu
assert "Qt.callLater(() => {" in menu
assert "root.anchorItem.x = root.relocationX" in menu
assert "root.anchorItem.y = root.relocationY" in menu
assert "root.relocationModelProvided" in menu
assert "function fadeForRelocation(): void" in menu
assert "ScriptAction { script: root.commitRelocation() }" in menu
assert "root.relocationQueued = false" in menu
assert "GlobalStates.activeContextMenu && GlobalStates.activeContextMenu !== root" in menu

# Fade body and shadow as one layer. Other ContextMenu consumers retain the
# older reveal profile, and animation-disabled mode does an immediate swap.
assert "opacity: popupWindow.relocationOpacity" in menu
assert "root.fadeOnly ? 1" in menu
assert "property bool fadeOnly: false" in menu
assert "if (Appearance.animationsEnabled)" in menu
assert "else\n                root.commitRelocation()" in menu
assert "popupWindow.anchor.updateAnchor()" not in menu
assert "pendingAnchorX" not in menu

print("PASS: desktop context menu remap, pointer mapping and corner-clamp contracts")
