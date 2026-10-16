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
assert 'liquidPresentationKind: "notesTimers"' in module
assert 'liquidPresentationKind: "notificationActivity"' in module
assert 'presentationKind === "notesTimers"' in perimeter
assert 'presentationKind === "notificationActivity"' in perimeter
assert 'tangentEdgeOverride: root.moduleAnchorMode ? "" : "end"' in center
assert "GlobalStates.notificationCenterExplicitOpen" in perimeter
assert "NotificationCenterPopup {" in corners
assert "QuickNotesPopup {" in corners

# Editor focus/popup contents are retained, not rewritten as new services.
assert "onNotesEditorFocusChanged:" in perimeter
assert "onEditorFocusedChanged:" in module
assert "selectedMainTab" in notes and "popupPinned" in notes
assert "selectedTab" in center and "Notifications" in center

# Two independent saved modes, falling back to old combined setting.
config = read("modules/common/Config.qml")
assert 'property string launcherMode: "module"' in config
assert 'property string notesTimersMode: ""' in config
assert 'property string notificationActivityMode: ""' in config
assert 'function unifiedLauncherMode(options,kind)' in layout
assert 'function livePlacements(placements, options, editing)' in layout
assert 'readonly property var activePlacements: Layout.livePlacements(' in bar
assert 'Layout.geometry(activePlacements,width,height' in bar
assert 'const next=activePlacements.filter(p=>p.enabled)' in bar
assert 'onActivePlacementsChanged: syncModuleIds()' in bar
assert 'root.launcherModes,module.kind' in bar
assert 'notesTimersMode: Config.options?.abyss?.modules?.notesTimersMode' in bar
assert 'notificationActivityMode: Config.options?.abyss?.modules?.notificationActivityMode' in bar
assert 'ModuleLayout.unifiedLauncherMode(' in corners and ',kind) === "module"' in corners
assert '"notificationActivity") === "module"' in perimeter
assert 'ModuleLayout.livePlacements(placements,Config.options?.abyss?.modules,false)' in perimeter
assert 'bar.activePlacements,bar.layoutOptions' in perimeter

# Each Module Icon is its own hover source. The iconless compatibility path
# may reach the physical edge, but no icon-mode source does. No name tooltip.
assert 'moduleRoot.showIcon ? parent.iconDiameter : parent.width' in module
assert 'moduleRoot.showIcon ? parent.iconDiameter' in module
assert 'StyledToolTip { text: hit.parent.description' not in module
assert 'module.moduleIconHitOnly' in bar
assert 'onModuleIconHitOnlyChanged: invalidateInputRegion()' in bar
assert 'onModuleIconHitSizeChanged: invalidateInputRegion()' in bar

# Window/work-area padding is not affected by isolated mini launchers;
# the associated painting remains a local Surface on any of the 4 edges.
assert '!isUnifiedKind(p.kind)' in layout
assert 'stripDepth(enabled,edge,options,fontScale)' in layout
assert 'return isUnifiedKind(p.kind) || edgeThickness' in layout
assert 'root.outputInsets(modelData?.name ?? "",true)[edge]' in perimeter

# Live editor owns position/icon/size, not the source presentation modes.
settings = read("modules/settings/BarConfig.qml")
style = read("modules/abyss/settings/AbyssStyleSettings.qml")
index = read("modules/settings/SettingsPageRegistryData.qml")
abyss_page = read("modules/settings/AbyssConfig.qml")
assert 'objectName: "abyssNotesTimersAccessMode"' in settings
assert 'objectName: "abyssNotificationActivityAccessMode"' in settings
assert 'Config.setNestedValue("abyss.modules.notesTimersMode",value)' in settings
assert 'Config.setNestedValue("abyss.modules.notificationActivityMode",value)' in settings
assert 'ModuleLayout.unifiedLauncherMode(' in settings
assert '{displayName: "Module Icon",value: "module"}' in settings
assert '{displayName: "Edgebar Hover",value: "edgebar"}' in settings
assert 'objectName:"abyssUnifiedLauncherSettingsMode"' not in style
assert '"module behavior"' in abyss_page
assert 'section: Translation.tr("Module behavior")' in index
assert 'Quick Notes & Notifications access modes' in index
assert 'launcherMode' not in editor
assert 'draftLauncherMode' not in bar
assert 'draftLauncherMode' not in perimeter
assert 'Placement.saveProfile(' in editor
assert 'root.batch("showIcon",checked)' in editor
print("ABYSS-R15 unified edge module source contract: ok")
