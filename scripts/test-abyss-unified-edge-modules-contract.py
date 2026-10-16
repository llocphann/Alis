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
abyss_corners = read("modules/abyss/AbyssCorners.qml")

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

# Module source exists only in Module Icon mode. "Hide icon" unmounts its
# whole popup/source and switches to the existing legacy corner Edgebar.
assert "showIcon:p.showIcon !== false" in layout
assert 'showIcon: module.unifiedEdgeLauncher ? true : placement?.showIcon !== false' in bar
assert "visible: hit.parent.moduleRoot.showIcon" in module
assert "enabled: moduleRoot.showIcon" in module
assert "hoverEnabled: true" in module
assert "hiddenEdgeLauncher" not in bar
assert "edgeReach:" not in module
assert 'onHiddenEdgeLauncherChanged:' not in bar
assert "module.moduleIconHitOnly" in bar
assert "(!module.unifiedEdgeLauncher || module.showIcon)" in bar

# Editor keeps output placement, singletons per unified kind and undo/history.
assert 'objectName:"abyssUnifiedModuleIconVisibility"' not in editor
assert 'root.batch("showIcon",checked)' not in editor
assert "Placement.isUnifiedKind(kind)" in editor
assert "Placement.saveProfile(" in editor
assert 'if(["remove","locked","enabled","joinCorner"].concat(placementKeys)' in layout

# Existing corner fallback and explicit notification hotkey remain supported.
assert "ModuleLayout.moduleOwnsCornerHover(" in corners
assert "moduleAnchorMode: true" in module
assert 'liquidPresentationKind: "notesTimers"' in module
assert 'liquidPresentationKind: "notificationActivity"' in module
assert 'presentationKind === "notesTimers"' in perimeter
assert 'presentationKind === "notificationActivity"' in perimeter
assert 'tangentEdgeOverride: root.moduleAnchorMode ? "" : "end"' in center
assert "GlobalStates.notificationCenterExplicitOpen" in perimeter
assert "NotificationCenterPopup {" in corners
assert "QuickNotesPopup {" in corners

# Module Icon must disable the actual legacy ScreenCorners popup Loader,
# independent of Bar visibility, auto-hide, or per-output bar eligibility.
assert 'function moduleOwnsCornerHover(options,panelFamily,kind)' in layout
assert 'return ModuleLayout.moduleOwnsCornerHover(' in corners
owner_gate=corners.split('function hasUnifiedEdgeReplacement(kind): bool {',1)[1].split('\n        }',1)[0]
assert 'GlobalStates.barOpen' not in owner_gate
assert 'ModuleLayout.hasEnabledModule' not in owner_gate
assert 'enabledPanels' not in owner_gate
assert 'Config.options?.panelFamily ?? "ii",kind' in owner_gate
assert '&& !cornerPanelWindow.hasUnifiedEdgeReplacement("notesTimers")' in corners
assert '&& !cornerPanelWindow.hasUnifiedEdgeReplacement("notificationActivity")' in corners
assert 'active: cornerPanelWindow.shouldShowQuickNotesCorner' in corners
assert 'active: cornerPanelWindow.notificationCenterHostNeeded' in corners
assert 'hoverAllowed: cornerPanelWindow.shouldShowQuickNotesCorner' in corners
assert 'cornerPanelWindow.shouldShowNotificationCenterCorner' in corners
assert 'property bool hoverAllowed: true' in notes
assert 'hoverActivates: root.hoverAllowed' in notes

# Once Panels Quick Notes controls were retired, their saved enable=false
# remains legal user config. Edgebar mode must revive the old input host
# independent of that flag; likewise for Notification legacy hover and output
# masks. Explicit Module Icon still disables both old popup loaders.
assert 'function edgebarOwnsCornerHover(options,panelFamily,kind)' in layout
assert 'function abyssEdgebarSelected(kind): bool' in corners
assert 'return ModuleLayout.edgebarOwnsCornerHover(' in corners
quick_gate = corners.split('readonly property bool shouldShowQuickNotesCorner:',1)[1].split('function notificationCenterTargetsOutput',1)[0]
assert 'cornerPanelWindow.abyssEdgebarSelected("notesTimers")' in quick_gate
assert 'Config.options?.quickNotes?.enable ?? true' in quick_gate
assert 'cornerPanelWindow.quickNotesMonitorAllowed' in quick_gate
notification_gate = corners.split('readonly property bool shouldShowNotificationCenterCorner:',1)[1].split('function reconcileNotificationCenterFullscreenPolicy',1)[0]
assert notification_gate.count('cornerPanelWindow.abyssEdgebarSelected("notificationActivity")') >= 5
assert 'Config.options?.notificationCenter?.hoverEnable ?? true' in notification_gate
assert 'Config.options?.notificationCenter?.enable ?? true' in notification_gate
assert 'cornerPanelWindow.notificationCenterTargetsOutput()' in notification_gate
assert 'active: cornerPanelWindow.shouldShowQuickNotesCorner' in corners
assert 'active: cornerPanelWindow.notificationCenterHostNeeded' in corners

# The actual Abyss perimeter embeds AbyssCorners, not ii's
# ScreenCorners. Edgebar ownership must be gated at the native
# AbyssCorners anchors and input regions, including legacy-disabled profiles.
assert 'AbyssCorners {' in perimeter
assert 'Region { item:corners.notesAvailable ? corners.notesAnchor : emptyInput }' in perimeter
assert 'Region { item:corners.centerAvailable ? corners.centerAnchor : emptyInput }' in perimeter
assert 'import "looks/AbyssLayout.js" as ModuleLayout' in abyss_corners
assert 'readonly property bool notesEdgebarMode:' in abyss_corners
assert 'readonly property bool centerEdgebarMode:' in abyss_corners
assert 'ModuleLayout.edgebarOwnsCornerHover(' in abyss_corners
notes_policy=abyss_corners.split('readonly property bool notesAvailable:',1)[1].split('readonly property bool centerAvailable:',1)[0]
center_policy=abyss_corners.split('readonly property bool centerAvailable:',1)[1].split('function targets(list)',1)[0]
assert '&& notesEdgebarMode' in notes_policy
assert '&& centerEdgebarMode' in center_policy
for obsolete in (
    'Config.options?.quickNotes?.enable',
    'Config.options?.quickNotes?.monitorMode',
):
    assert obsolete not in notes_policy, obsolete
for obsolete in (
    'Config.options?.notificationCenter?.enable',
    'Config.options?.notificationCenter?.hoverEnable',
    'Config.options?.enabledPanels',
    'Config.options?.notificationCenter?.screenList',
):
    assert obsolete not in center_policy, obsolete
assert 'kind:"quickNotes";allowed:root.notesAvailable' in abyss_corners
assert 'kind:"notificationCenter";allowed:root.centerAvailable' in abyss_corners
assert 'hoverActivates:root.notesAvailable' in abyss_corners
assert 'hoverAllowed:root.centerAvailable' in abyss_corners
assert 'if (!notesAvailable && notesPopup.presentationActive)' in abyss_corners
assert 'if (!centerAvailable && centerPopup.presentationActive)' in abyss_corners

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
assert 'placements,launcherModes,editing' in bar
assert 'iconVisibility: ({' in bar
assert 'notesTimers: Config.options?.abyss?.modules?.iconVisibility?.notesTimers' in bar
assert 'notificationActivity: Config.options?.abyss?.modules?.iconVisibility?.notificationActivity' in bar
assert 'notesTimersMode: Config.options?.abyss?.modules?.notesTimersMode' in bar
assert 'notificationActivityMode: Config.options?.abyss?.modules?.notificationActivityMode' in bar
assert 'return ModuleLayout.moduleOwnsCornerHover(' in corners
assert '"notificationActivity") === "module"' in perimeter
assert 'ModuleLayout.livePlacements(placements,Config.options?.abyss?.modules,false)' in perimeter
assert 'bar.activePlacements,bar.layoutOptions' in perimeter

# Each live Module Icon has exactly one painted hit source; there is no
# invisible fallback in Module mode. Edgebar mode uses separate ScreenCorners.
assert 'x: (parent.width-parent.iconDiameter)/2' in module
assert 'y: (parent.height-parent.iconDiameter)/2' in module
assert 'width: parent.iconDiameter' in module
assert 'height: parent.iconDiameter' in module
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
# Only Modules (not the Behavior & clock tab) owns the per-kind mode
# switches. Never recreate duplicate selectors under Behavior & clock.
assert 'objectName: "abyssNotesTimersAccessMode"' not in settings
assert 'objectName: "abyssNotificationActivityAccessMode"' not in settings
assert 'Choose one opening behavior for Quick Notes' not in settings
assert 'Choose one opening behavior for notifications' not in settings
assert 'objectName: "abyssSettingsQuickNotesTimersIcon"' in settings
assert 'objectName: "abyssSettingsNotificationActivityIcon"' in settings
assert 'Config.setNestedValue("abyss.modules.notesTimersMode",checked ? "module" : "edgebar")' in settings
assert 'Config.setNestedValue("abyss.modules.notificationActivityMode",checked ? "module" : "edgebar")' in settings
assert 'ModuleLayout.unifiedLauncherMode(' in settings
assert 'objectName:"abyssUnifiedLauncherSettingsMode"' not in style
assert '"modules": "modules"' in settings
assert '"module behavior"' in abyss_page
assert 'section: Translation.tr("Modules")' in index
assert 'Quick Notes & Notifications access modes' in index
assert 'launcherMode' not in editor
assert 'draftLauncherMode' not in bar
assert 'draftLauncherMode' not in perimeter
assert 'Placement.saveProfile(' in editor
# Settings icon toggles now change the same per-kind presentation mode as
# Module Behavior. Older show/hide preferences remain readable for safe migration.
assert 'property JsonObject iconVisibility: JsonObject' in config
assert 'property string notesTimers: "inherit"' in config
assert 'property string notificationActivity: "inherit"' in config
assert 'function iconVisibilityPreference(options,kind)' in layout
assert 'iconVisibilityPreference(options,kind)===false' in layout
assert 'return ModuleLayout.unifiedLauncherMode(' in settings
for kind in ("notesTimers","notificationActivity"):
    assert f'Config.setNestedValue("abyss.modules.{kind}Mode",checked ? "module" : "edgebar")' in settings
    assert f'Config.setNestedValue("abyss.modules.iconVisibility.{kind}"' not in settings
assert 'These settings apply across outputs. Hiding an icon keeps' not in settings
assert 'Off: remove this module' in settings

# The containing Bar item often owns a wider mouse target than the icon.
# Strict owner hover must exclude the Bar's ancestor hover state, while
# retaining normal broad-zone hover for every existing non-unified popup.
styled = read("modules/bar/StyledPopup.qml")
assert 'property bool strictSourceHover: false' in styled
assert 'root.strictSourceHover' in styled
assert 'root.hoverTarget?.containsMouse || root.hoverTarget?.hovered' in styled
assert module.count('strictSourceHover: true') == 2

# The prior thick inner rim came from avoiding the local surface of the very
# launcher whose popup was being presented; unrelated obstacles remain.
assert 'function clearanceInsets(insets, localRecords, edge, along, span, popupOwnerKind)' in layout
assert 'if (popupOwnerKind && record.kind===popupOwnerKind) return;' in layout
assert 'var record={kind:p.kind,edge:p.edge' in layout
assert 'function bodyInsets(edge,along,span,ownLauncherKind = "")' in perimeter
assert 'presentationKind === "notesTimers"' in perimeter
assert 'presentationKind === "notificationActivity"' in perimeter
print("ABYSS-R15 unified edge module source contract: ok")
