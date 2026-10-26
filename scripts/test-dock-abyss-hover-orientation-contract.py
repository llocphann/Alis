#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
apps=(r/"modules/dock/DockApps.qml").read_text()
btn=(r/"modules/dock/DockAppButton.qml").read_text()
ctx=(r/"modules/common/widgets/ContextMenu.qml").read_text()
menu=(r/"modules/dock/DockContextMenu.qml").read_text()
abyss=(r/"modules/abyss/content/AbyssDockContent.qml").read_text()
dock=(r/"modules/dock/Dock.qml").read_text()
settings=(r/"modules/settings/DockConfig.qml").read_text()
ripple=(r/"modules/common/widgets/RippleButton.qml").read_text()
qmldir=(r/"modules/dock/qmldir").read_text()
assert "signal closeAllContextMenus(var exceptOwner)" in apps
assert "function refreshAxisLayout(): void" in apps
assert "listView.forceLayout()" in apps
assert "root.appListRoot.closeAllContextMenus(root)" in btn
assert "if (exceptOwner !== root)" in btn
assert "property color panelFallbackColor" in ctx
assert "AbyssStyle.surfaceDeep" in menu and "AbyssStyle.accent" in menu
assert "showDashboardButton" in abyss
assert dock.count("showDashboardButton") >= 2
assert "Show Dashboard icon" in settings

# Dock icon ordering is configured in Settings. Runtime pointer-drag state was
# retired so there is one ordering source of truth instead of competing paths.
for token in (
    "dragActive",
    "startDrag(",
    "updateDrag(",
    "endDrag(",
    "cancelDrag()",
    "dropTargetIndex",
    "reorderDragProxy",
    "_dockDragStarted",
    "insertionLine",
    "abyssMenuDismissPresenter",
    "_suppressNextClick",
):
    assert token not in apps
assert "pointerDragAxis" not in ripple
assert "drag.axis: Drag.XAndYAxis" in ripple
# Settings owns drag ordering; the runtime Dock must not own a second drag path.
assert "enableDragReorder" not in apps
assert "enableDragReorder" not in settings
assert "function commitPinnedDrop(): void" in settings
assert 'Config.setNestedValue("dock.pinnedApps", values)' in settings
assert 'title: Translation.tr("Pinned apps")' in settings
assert 'text: "drag_indicator"' in settings
assert 'Drag.keys: ["alis-dock-pinned-app"]' in settings or 'Drag.keys: ["inir-dock-pinned-app"]' in settings
assert "root.togglePinnedVisibility(pinnedSlot.appId)" in settings
assert "root.removePinnedApp(pinnedSlot.appId)" in settings
assert "function filteredAddApps(): var" in settings
assert 'placeholderText: Translation.tr("Search applications...")' in settings
assert "property bool addApplicationsOpen: false" in settings
assert "id: dockPrimaryToggles" in settings
assert "id: revealModeToggles" in settings
assert "id: dockSecondaryToggles" in settings
assert 'text: Translation.tr("Drag to reorder · eye hides · minus removes.")' in settings
assert "id: addApplicationsToggle" in settings
assert "Layout.topMargin: 8" in settings
assert "Layout.leftMargin: 8" in settings
assert "Layout.rightMargin: 6" in settings
assert "id: addApplicationsPanel" in settings
assert "implicitHeight: root.addApplicationsOpen" in settings
assert 'text: root.addApplicationsOpen ? "close" : "add"' in settings
assert "model: root.addApplicationsOpen ? root.filteredAddApps() : []" in settings
assert "Behavior on implicitHeight" in settings
assert "Behavior on opacity" in settings
assert "root.addPinnedApp(" in settings
assert "hiddenPinnedApps" in settings
assert "hiddenPinnedIds" in apps
assert "visiblePinnedApps" in apps
assert "function onHiddenPinnedAppsChanged()" in apps
position = [
    '{ displayName: Translation.tr("Left"), icon: "arrow_back", value: "left" }',
    '{ displayName: Translation.tr("Top"), icon: "arrow_upward", value: "top" }',
    '{ displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: "bottom" }',
    '{ displayName: Translation.tr("Right"), icon: "arrow_forward", value: "right" }',
]
assert all(token in settings for token in position)
assert settings.index(position[0]) < settings.index(position[1]) < settings.index(position[2]) < settings.index(position[3])
assert "const pinnedOrder = new Map()" in apps
assert "if (aPinned && bPinned)" in apps
assert "return aPinned ? -1 : 1" in apps

# Dock hover is now one app-popup interaction. Legacy Dock window-preview
# surfaces and their Settings controls must stay retired.
assert "root.showContextMenu(true)" in btn
assert "hoverPreviewRequested" not in btn
assert "hoverPreviewDismissed" not in btn
assert "Config.options?.dock?.hoverPreview" not in btn
assert "DockPreview {" not in apps
assert "showPreviewPopup" not in apps
assert "dockPreviewPopup" not in apps
assert 'Translation.tr("Window preview")' not in settings
assert 'Translation.tr("Show preview on hover")' not in settings
assert 'Config.setNestedValue("dock.hoverPreview"' not in settings
assert 'Config.setNestedValue("dock.hoverPreviewDelay"' not in settings
assert "DockPreview 1.0" not in qmldir
assert "DockWindowPreview 1.0" not in qmldir
assert 'Accessible.name: Translation.tr("Move earlier")' not in settings
assert 'Accessible.name: Translation.tr("Move later")' not in settings
print("dock popup/orientation/dashboard-toggle/settings-order contract: ok")
