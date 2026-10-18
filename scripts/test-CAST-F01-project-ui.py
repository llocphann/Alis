#!/usr/bin/env python3
"""CAST-F01 Project & Cast UI contract, no desktop/session access required."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
qml = (root / "modules/abyss/content/AbyssUtilitiesPopup.qml").read_text()
start = qml.index("    Component {\n        id: displayPage")
end = qml.index("    Component {\n        id: audioPage", start)
panel = qml[start:end]

assert '"Monitor arrangement", "Project & Cast", "Sound", "Eye protection"' in qml
assert 'visible: pages.currentIndex === 1' in qml
assert 'text: "present_to_all"' in qml

for mode, label in (
    ("primary-only", "PC screen only"),
    ("mirror", "Duplicate"),
    ("extend", "Extend"),
    ("second-only", "Second screen only"),
):
    assert f'key: "{mode}", title: "{label}"' in panel
    assert f'DisplayMode.apply("{mode}")' in panel

assert "columns: 2" in panel and "GridLayout {" in panel
assert "readonly property bool selected: DisplayMode.currentMode === modelData.key" in panel
assert 'text: "check"' in panel
assert "onClicked: displayContent.activateMode(modeTile.modelData.key)" in panel

assert 'text: "DISPLAY MODE"' in panel
assert 'text: "WIRELESS DISPLAY"' in panel
assert 'text: NetworkDisplays.scanning ? "Scanning…" : "Scan"' in panel
assert "onClicked: NetworkDisplays.scan()" in panel
assert "model: NetworkDisplays.displays" in panel
assert "receiverRow.modelData.name" in panel
assert "receiverRow.modelData.protocol" in panel
assert "receiverRow.receiverState" in panel
assert "NetworkDisplays.select(receiverRow.receiverId)" in panel
assert "NetworkDisplays.connectToSelected()" in panel
assert "NetworkDisplays.disconnect()" in panel
assert "NetworkDisplays.streamReady" in panel

assert "DisplayMode.setMirrorSource(DisplayMode.connectedOutputs[currentIndex])" in panel
assert "DisplayMode.setMirrorTarget(outputIds[currentIndex])" in panel
assert "DisplayMode.selectedSecondary = selected" in panel
assert "visible: displayContent.hasMultipleExternals" in panel
assert "Flickable {" in panel and "contentHeight: displayColumn.implicitHeight" in panel

# Design exactly as requested: embedded in the shared Utilities page,
# no standalone modal, header close action or sample-only footnote.
assert "closeRequested()" not in panel
assert '"Living Room TV"' not in panel and '"Android TV"' not in panel
assert "Minh họa giao diện" not in panel
assert "StyledComboBox" not in panel[panel.index('text: "WIRELESS DISPLAY"'):]
assert "NetworkDisplays.selectedUuid" not in panel
print("CAST_F01_PROJECT_UI_PASS: native Utilities tile grid and dynamic receiver rows")
