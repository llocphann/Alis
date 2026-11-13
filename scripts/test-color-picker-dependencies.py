#!/usr/bin/env python3
"""The owned picker needs only the existing Qt/Quickshell runtime."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
checked = 0
for tree in ("distro", "nix", "sdata"):
    for path in (ROOT / tree).rglob("*"):
        if path.is_file() and (path.name in {"PKGBUILD", ".SRCINFO"}
                               or path.suffix in {".sh", ".nix"}):
            checked += 1
            assert not re.search(r"\bhyprpicker\b", path.read_text()), path

for name in (
    "modules/bar/UtilButtons.qml",
    "modules/common/models/quickToggles/ColorPickerToggle.qml",
    "modules/sidebarRight/quickToggles/androidStyle/AndroidColorPickerToggle.qml",
    "modules/sidebarRight/CompactSidebarRightContent.qml",
    "modules/sidebarLeft/ToolsView.qml",
    "modules/regionSelector/RegionSelection.qml",
    "services/GlobalActions.qml",
):
    text = (ROOT / name).read_text()
    assert "ColorPickerService.start()" in text, name
    assert not re.search(r"\bhyprpicker\b|\bpick-color\b", text), name

cli = (ROOT / "scripts/alis").read_text()
wallpaper = (ROOT / "scripts/colors/switchwall.sh").read_text()
assert "ipc call colorpicker start" in cli
assert "colorpicker --config" in wallpaper
assert "hyprpicker" not in cli + wallpaper
assert 'captureSource: root.screen' in (ROOT / "services/ColorPickerOverlay.qml").read_text()
service = (ROOT / "services/ColorPickerService.qml").read_text()
worker = (ROOT / "color-picker-worker.qml").read_text()
assert 'Quickshell.clipboardText = value' in service
assert 'ColorPickerOverlay' not in service and 'PanelWindow' not in service
assert '"/color-picker-worker.qml"' in service
assert 'onExited:' in service and 'worker.signal(9)' in service
assert 'ColorPickerOverlay {' in worker and 'model: Quickshell.screens' in worker
assert 'Quickshell.clipboardText' not in worker
print("COLOR_PICKER_DEPENDENCIES_PASS", checked, "package/installer files; all public callers owned")
