#!/usr/bin/env python3
"""ABYSS-R15 source-level guard; real Wayland owner acceptance is separate."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]

def read(path):
    return (root / path).read_text(encoding="utf-8")

layout = read("modules/abyss/looks/AbyssLayout.js")
bar = read("modules/abyss/bar/AbyssBar.qml")
module = read("modules/abyss/bar/AbyssBarModule.qml")
editor = read("modules/abyss/AbyssEdgeEditor.qml")
corners = read("modules/screenCorners/ScreenCorners.qml")
notes = read("modules/screenCorners/QuickNotesPopup.qml")
center = read("modules/notificationCenter/NotificationCenterPopup.qml")
perimeter = read("modules/abyss/AbyssPerimeter.qml")

for kind, label in (
    ("notesTimers", "QuickNotes & Timers"),
    ("notificationActivity", "Notifications & Activities"),
):
    assert f'{kind}:"{label}"' in layout, kind
    assert f'root.kind === "{kind}"' in module, kind
    assert f'hasUnifiedEdgeReplacement("{kind}")' in corners, kind

# One existing backend/popup per launcher, no copies of notes or notifications.
assert "QuickNotesPopup {" in module
assert "NotificationCenterPopup {" in module
assert "import qs.modules.screenCorners" in module
assert "import qs.modules.notificationCenter" in module
assert "modules.screenCorners.QuickNotesPopup" not in module
assert "NotificationCenterContent {" not in module
assert "TimerService {" not in module
assert "Notifications {" not in module

# Hiding the glyph must not disable its MouseArea, detach the mature popup,
# or turn the entire screen into an invisible input receiver.
assert "showIcon:p.showIcon !== false" in layout
assert '"showIcon"' in layout
assert "visible: hit.parent.moduleRoot.showIcon" in module
assert "hoverEnabled: true" in module
assert "hiddenEdgeLauncher" in bar
assert 'module.attachedEdge === "top"' in bar
assert 'module.attachedEdge === "bottom"' in bar
assert 'module.attachedEdge === "left"' in bar
assert 'module.attachedEdge === "right"' in bar
assert "onHiddenEdgeLauncherChanged: invalidateInputRegion()" in bar
assert "edgeReach: 36" in module

# Editor keeps output placement, singletons per unified kind and undo/history.
assert 'objectName:"abyssUnifiedModuleIconVisibility"' in editor
assert 'root.batch("showIcon",checked)' in editor
assert "Placement.isUnifiedKind(kind)" in editor
assert "Placement.saveProfile(" in editor
assert "if(action===\"showIcon\"" in layout

# Existing corner fallback and explicit notification hotkey remain supported.
assert "ModuleLayout.hasEnabledModule(" in corners
assert "moduleAnchorMode: true" in module
assert 'tangentEdgeOverride: root.moduleAnchorMode ? "" : "end"' in center
assert "GlobalStates.notificationCenterExplicitOpen" in perimeter
assert "NotificationCenterPopup {" in corners
assert "QuickNotesPopup {" in corners

# Editor focus/popup contents are retained, not rewritten as new services.
assert "onNotesEditorFocusChanged:" in perimeter
assert "onEditorFocusedChanged:" in module
assert "selectedMainTab" in notes and "popupPinned" in notes
assert "selectedTab" in center and "Notifications" in center

print("ABYSS-R15 unified edge module source contract: ok")
