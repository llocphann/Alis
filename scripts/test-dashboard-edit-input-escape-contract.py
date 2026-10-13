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
overview = read("modules/overview/OverviewDashboard.qml")
overview_host = read("modules/abyss/content/AbyssOverviewContent.qml")

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
# The owning window, not its reparented toolbar, owns Escape.
assert 'sequences: ["Escape"]' not in editor
assert 'sequences: ["Escape"]' in perimeter
assert 'context: Qt.WindowShortcut' in perimeter
assert 'autoRepeat: false' in perimeter
assert 'function cancelDashboardEditFromEscape(): bool' in perimeter
assert 'perimeterEscapeFallback.forceActiveFocus()' in perimeter
assert 'onActivated: window.cancelDashboardEditFromEscape()' in perimeter
assert 'onActivatedAmbiguously:' in perimeter
assert 'dashboardEscapeCancelPending' in perimeter
assert 'target: "dashboardEscProbe"' in perimeter
assert 'function dashboardEscapeProbe(): var' in perimeter
assert 'dashboardEscapeCancelCount++' in perimeter
assert 'dashboardEscapeFallbackCount++' in perimeter
assert 'id: dashboardEditEscapeShortcut' in perimeter
assert 'ownerShortcutEnabled: dashboardEditEscapeShortcut.enabled' in perimeter
assert 'escapeKeyCount++' in read("modules/abyss/AbyssBodyHost.qml")
assert "function handleEscape(): bool {" in embedded
assert "return content.handleEscape()" in embedded
assert 'const dashboard = dashboardBody.presented ? dashboardBody.contentItem?.item : null' in perimeter
assert 'target.handleEscape()' in perimeter
assert perimeter.index('if (window.cancelDashboardEditFromEscape())') < perimeter.index(
    'GlobalStates.dashboardOpen = false', perimeter.index('Keys.onEscapePressed:'))
assert "contentLoader.item?.handleEscape()" in standalone
assert "panelRoot.hide()" in standalone
assert "function cancelEditMode()" in canvas
assert "root._draftEntries = null" in canvas
assert 'enabled: root.editing && root.popupPresented && !root.externalEditToolbar' in overview
assert 'function handleEscape(): bool' in overview_host
assert 'overview.item?.handleEscape?.()' in overview_host

# The QML focus path inside the body previously closed immediately, before
# the outer Perimeter's cancellation handler could see the event.
body_host = read("modules/abyss/AbyssBodyHost.qml")
assert 'Keys.onEscapePressed: root.closeRequested()' not in body_host
host_escape = body_host[body_host.index("Keys.onEscapePressed: event => {"):
                        body_host.index("Behavior on visualPlacementAlong")]
assert 'root.identity === "dashboard" ? content.item : null' in host_escape
assert '(dashboard?.editMode ?? false)' in host_escape
assert 'dashboard.handleEscape()' in host_escape
assert host_escape.index("dashboard.handleEscape()") < host_escape.index("root.closeRequested()")
assert "event.accepted = true" in host_escape

# Both the output-field fallback and standalone window should preserve focus
# after Cancel so the next Escape can reach the normal close path.
assert "perimeterEscapeFallback.forceActiveFocus()" in perimeter
assert "contentLoader.forceActiveFocus()" in standalone
assert "onActivatedAmbiguously:" in standalone
assert standalone.index('        Shortcut {') < standalone.index('        // Backdrop click to close')
assert "dashboard?.handleEscape?.()" not in editor

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
