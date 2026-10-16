#!/usr/bin/env python3
"""Guard click-to-relocate fade behavior without changing other popup users."""
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

assert "desktopContextMenu.requestOpenAt(mouse.x, mouse.y)" in desktop
assert "desktopItemContextMenu.requestOpenAt(position.x, position.y)" in desktop
assert "function requestOpenAt(x: real, y: real): void" in menu
assert "root.item.retargetAnchor(nextX, nextY)" in menu
assert "function retargetAnchor(x: real, y: real): void" in menu
assert "fadeOnlyOpenAnim.stop();" in menu
assert "fadeOnlyCloseAnim.stop();" in menu
assert "relocationAnim.stop();" in menu
assert "popupWindow.anchor.updateAnchor();" in menu
assert "opacity: popupWindow.relocationOpacity" in menu
assert "root.fadeOnly ? 1" in menu
assert "property bool fadeOnly: false" in menu

print("PASS: desktop context-menu fade relocation contract")
