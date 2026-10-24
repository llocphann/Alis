#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
canvas = (root / "modules/dashboard/DashboardCanvas.qml").read_text()
content = (root / "modules/dashboard/DashboardContent.qml").read_text()
toolbar = (root / "modules/dashboard/DashboardEditToolbar.qml").read_text()

required_canvas = [
    "property var _draftEntries: null",
    "function _captureEditDraft()",
    "function beginEditMode()",
    "function commitEditMode()",
    "function cancelEditMode()",
    "if (root.editMode && root._draftEntries !== null)",
    "root._draftEntries = root._cloneEntries(entries)",
    "Config.options?.dashboard?.canvas?.widgets ?? []",
    "property var _draftGridSize: null",
    "property var _draftSnap: null",
    "property var _draftAutoAdjustSize: null",
    "property var _draftGridStyle: null",
    "function toggleSnap()",
    "function toggleAutoAdjustSize()",
    "function fitAllWidgets()",
    "Added and fitted all Dashboard modules",
    "onPresentationActiveChanged:",
    "if (!presentationActive) root.cancelEditMode()",
]
for needle in required_canvas:
    assert needle in canvas, needle

assert "root.canvasController.commitEditMode()" in content
assert "root.canvasController?.beginEditMode()" in content
assert "root.canvasController?.editMode" in content
assert "dashboardCanvas.editMode = !dashboardCanvas.editMode" not in content

assert "Add all modules and fit them automatically" in toolbar
assert "root.canvasController.fitAllWidgets()" in toolbar
assert "root.canvasController.toggleSnap()" in toolbar
assert "root.canvasController.toggleAutoAdjustSize()" in toolbar
assert 'Config.setNestedValue(\n                        "dashboard.canvas.snap"' not in toolbar
assert 'Config.setNestedValue(\n                        "dashboard.canvas.autoAdjustSize"' not in toolbar

# Layout writes during edit must terminate at the draft before reaching Config.
write_start = canvas.index("function _writeEntries(entries)")
write_end = canvas.index("function _persistPatch", write_start)
write_body = canvas[write_start:write_end]
assert "if (root.editMode)" in write_body
assert "root._draftEntries" in write_body
assert "return" in write_body

print("dashboard edit transaction contract: ok")
