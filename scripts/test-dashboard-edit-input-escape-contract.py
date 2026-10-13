#!/usr/bin/env python3
"""Contract checks for the Dashboard Edit Layout toolbar's native input and Esc."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
read = lambda path: (root / path).read_text(encoding="utf-8")

editor = read("modules/abyss/AbyssDashboardEditPopup.qml")
surface = read("modules/abyss/AbyssSurfaceController.qml")
perimeter = read("modules/abyss/AbyssPerimeter.qml")
embedded = read("modules/abyss/content/AbyssDashboardContent.qml")
content = read("modules/dashboard/DashboardContent.qml")
toolbar = read("modules/dashboard/DashboardEditToolbar.qml")
canvas = read("modules/dashboard/DashboardCanvas.qml")
standalone = read("modules/dashboard/Dashboard.qml")

# A field-owned editor above the body requires its own shaped Wayland input.
# A fullscreen mask would steal clicks from underlying windows.
for token in (
    "readonly property rect toolbarInputBounds:",
    "readonly property Region toolbarInputRegion: Region",
    "inputBounds: root.toolbarInputBounds",
    "nativeInputRegion: root.toolbarInputRegion",
    "enabled: revealRequested && visible && (body?.acceptsInput ?? false)",
):
    assert token in editor, token
assert "nativeInputRegions: Object.keys(participants)" in surface
assert "liquid.nativeInputRegions" in perimeter

# The first Escape goes through Cancel (draft discarded), not Done/Save/Close.
body = content[content.index("function handleEscape(): bool {"):
               content.index("function openPlannerEventEditor(")]
assert body.index("dashboardCanvas.cancelEditMode()") < body.index("if (_agendaDialogShown)")
assert "dashboardHeader.cancelPageDrag()" in body
assert 'sequences: ["Escape"]' in editor
assert "root.canvasController.cancelEditMode()" in editor
assert "function handleEscape(): bool {" in embedded
assert "return content.handleEscape()" in embedded
assert "dashboardBody.contentItem.item.handleEscape()" in perimeter
assert perimeter.index("dashboardBody.contentItem.item.handleEscape()") < perimeter.index(
    "GlobalStates.dashboardOpen = false", perimeter.index("Keys.onEscapePressed:"))
assert "contentLoader.item?.handleEscape()" in standalone
assert "panelRoot.hide()" in standalone
assert "function cancelEditMode()" in canvas
assert "root._draftEntries = null" in canvas

# Action buttons must remain centered, keyboard-reachable and functional.
for token in (
    "Layout.alignment: Qt.AlignHCenter",
    "Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter",
    "anchors.centerIn: parent",
    "horizontalAlignment: Text.AlignHCenter",
    "verticalAlignment: Text.AlignVCenter",
    "focusPolicy: Qt.StrongFocus",
):
    assert token in toolbar, token
for operation in (
    "commitEditMode()", "cancelEditMode()", "undoLastEdit()",
    "toggleSnap()", "toggleAutoAdjustSize()", "_cycleGridStyle()",
    "_cycleGridSize()", "resetLayout()", "fitAllWidgets()",
):
    assert operation in toolbar, operation

print("ok - Dashboard Edit Layout input mask, icon alignment and two-stage Escape")
