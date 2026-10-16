#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORNERS = ROOT / "modules" / "screenCorners" / "ScreenCorners.qml"
POPUP = ROOT / "modules" / "screenCorners" / "QuickNotesPopup.qml"
STYLED_POPUP = ROOT / "modules" / "bar" / "StyledPopup.qml"
SCREEN_EDGES = ROOT / "modules" / "screenCorners" / "ScreenEdges.qml"
NOTEPAD = ROOT / "modules" / "sidebarRight" / "notepad" / "NotepadWidget.qml"
QUICK_NOTES_VIEW = ROOT / "modules" / "sidebarRight" / "notepad" / "QuickNotesView.qml"
DASH_NOTES = ROOT / "modules" / "dashboard" / "DashNotes.qml"
SIDEBAR_QUICK_NOTE = ROOT / "modules" / "sidebarLeft" / "widgets" / "QuickNote.qml"
NOTEPAD_SERVICE = ROOT / "services" / "Notepad.qml"
CONFIG = ROOT / "modules" / "common" / "Config.qml"
DEFAULTS = ROOT / "defaults" / "config.json"
SETTINGS = ROOT / "modules" / "settings" / "InterfaceConfig.qml"
REGISTRY = ROOT / "modules" / "settings" / "SettingsPageRegistryData.qml"
QMLDIR = ROOT / "modules" / "screenCorners" / "qmldir"


def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)


def require(source: str, token: str, message: str) -> None:
    if token not in source:
        fail(message + " (" + token + ")")


def forbid(source: str, token: str, message: str) -> None:
    if token in source:
        fail(message + " (" + token + ")")


corners = CORNERS.read_text(encoding="utf-8")
popup = POPUP.read_text(encoding="utf-8")
styled_popup = STYLED_POPUP.read_text(encoding="utf-8")
screen_edges = SCREEN_EDGES.read_text(encoding="utf-8")
notepad = NOTEPAD.read_text(encoding="utf-8")
quick_notes_view = QUICK_NOTES_VIEW.read_text(encoding="utf-8")
dash_notes = DASH_NOTES.read_text(encoding="utf-8")
sidebar_quick_note = SIDEBAR_QUICK_NOTE.read_text(encoding="utf-8")
notepad_service = NOTEPAD_SERVICE.read_text(encoding="utf-8")
config = CONFIG.read_text(encoding="utf-8")
defaults = json.loads(DEFAULTS.read_text(encoding="utf-8"))
settings = SETTINGS.read_text(encoding="utf-8")
registry = REGISTRY.read_text(encoding="utf-8")
qmldir = QMLDIR.read_text(encoding="utf-8")

# The physical Screen Edge is a maintainer-locked paint geometry. Quick Notes is
# interaction/popup behavior only and must never add a second painted corner.
if "QuickNotes" in screen_edges or "quickNotes" in screen_edges:
    fail("Quick Notes must not modify the locked physical ScreenEdges renderer")

for token in (
    "QuickNotesPopup 1.0 QuickNotesPopup.qml",
):
    require(qmldir, token, "screenCorners module must export the Quick Notes popup")

if popup.count("QuickNotesView {") != 1:
    fail("Quick Notes corner must own exactly one shared QuickNotesView")
if "NotepadWidget {" in popup or "quickCapturePresentation" in popup:
    fail("Quick Notes corner must not bypass the shared Dashboard presentation")
loader_pos = popup.find("id: notesViewLoader")
component_pos = popup.find("sourceComponent: QuickNotesView {")
if loader_pos < 0 or component_pos < 0 or loader_pos > component_pos:
    fail("Quick Notes view must be instantiated lazily through its Loader")

timer_loader_pos = popup.find("id: timerViewLoader")
timer_component_pos = popup.find("sourceComponent: PomodoroWidget {", timer_loader_pos)
if timer_loader_pos < 0 or timer_component_pos < 0 or timer_loader_pos > timer_component_pos:
    fail("Timers must be instantiated through the Quick Notes timer Loader")
timer_loader = popup[timer_loader_pos:timer_component_pos]
require(
    timer_loader,
    "active: root.presentationActive\n                        && root.selectedMainTab === 1",
    "Quick Notes hover must not materialize the timer subtree before Timers is selected",
)

for token in (
    "import QtQuick.Controls",
    "Bar.StyledPopup {",
    'property string cornerAttachmentEdge: "bottom"',
    "property real cornerAttachmentThickness:",
    "attachmentEdgeOverride: root.cornerAttachmentEdge",
    "attachmentThicknessOverride: root.cornerAttachmentThickness",
    "hoverActivates: true",
    "property bool entryBridgeHeld: false",
    "alternativeVisibleCondition: root.editorFocused || root.todoDialogOpen",
    "id: entryBridgeTimer",
    "Math.round(root.cornerAttachmentThickness * 6)",
    "keyboardFocusOnDemand: true",
    "keyboardFocus: root.editorFocused || root.todoDialogOpen",
    "exclusiveKeyboardFocus: true",
    "outsideClickBackdropBelowPopup: true",
    "closeOnOutsideClick: root.editorFocused || root.todoDialogOpen",
    "if (!root.presentationActive || !Notepad.ready || !notesViewLoader.item)",
    "readonly property real requestedPopupWidth:",
    "readonly property real requestedPopupHeight: Math.max(300,",
    "Math.min(640, Config.options?.quickNotes?.popupHeight ?? 300)",
    "root.requestedPopupWidth - root._contentPadding * 2",
    "root.requestedPopupHeight - root._contentPadding * 2",
    "width: parent ? parent.width : implicitWidth",
    "height: parent ? parent.height : implicitHeight",
    "id: notesViewLoader",
    "id: todoViewLoader",
    "id: timerViewLoader",
    'Translation.tr("Notes & To-do")',
    'Translation.tr("Timers")',
    'Translation.tr("Quick Notes")',
    'Translation.tr("To-do")',
    "sourceComponent: DashTodo {",
    "sourceComponent: PomodoroWidget {",
    "active: root.presentationActive",
    "sourceComponent: QuickNotesView {",
    "surfaceLocalTabSelection: true",
    "showHeader: false",
    "showZettelkastenActions: false",
    "verticalDotNavigation: true",
    "pillHeight: 30",
    "pillHeight: 28",
    "property bool notesTrayOpen: false",
    "property real notesTrayReveal:",
    "Behavior on notesTrayReveal",
    "Appearance.animation.elementResize.duration",
    "function holdNotesTray(): void",
    "function releaseNotesTray(): void",
    "id: notesTrayHideTimer",
    "interval: 220",
    "id: tabDock",
    "implicitHeight: mainTabs.height",
    "+ 32 * root.notesTrayReveal",
    "id: tabDockHover",
    "PointerDevice.Mouse | PointerDevice.TouchPad",
    "id: mainTabs",
    "id: notesTraySlot",
    "anchors.top: mainTabs.bottom",
    "height: 32 * root.notesTrayReveal",
    "id: notesTray",
    "opacity: root.notesTrayReveal",
    "onEditorActivated: root.enterEditorMode()",
    "root.editorFocused = true",
    "notesViewLoader.item.releaseEditorFocus()",
    "notesViewLoader.item.flushPendingSave()",
    "Component.onDestruction:",
    "sequences: [StandardKey.Cancel]",
    "context: Qt.WindowShortcut",
):
    require(popup, token, "Quick Notes popup interaction/focus contract missing")

for retired in (
    "TapHandler {",
    'text: Translation.tr("Click to type")',
    'text: Translation.tr("Esc to release")',
    "sourceComponent: NotepadWidget {",
    "quickCapturePresentation: true",
    "root.selectedMainTab === 0 && root.selectedNotesTab === 0 ? 300 : 380",
    "id: mainTabsHover",
    "id: notesTrayHover",
    "Behavior on y",
    "Behavior on height",
    "Behavior on opacity",
    "anchors.topMargin: height > 0 ? 4 : 0",
    "&& root.notesTrayOpen ? 28 : 0",
    "opacity: root.notesTrayOpen ? 1 : 0",
    "z: 21",
    "visible: opacity > 0",
    "Layout.preferredWidth: Math.min(\n                    248",
):
    forbid(popup, retired,
           "Quick Notes corner must not restore its private capture presentation")

for token in (
    "property bool outsideClickBackdropBelowPopup: false",
    "property bool keyboardFocusOnDemand: false",
    "property bool exclusiveKeyboardFocus: false",
    "focusable: root.requestedVisible",
    "&& (root.keyboardFocus || root.keyboardFocusOnDemand)",
    "? WlrKeyboardFocus.Exclusive",
    "(root.keyboardFocus || root.keyboardFocusOnDemand)",
    "? WlrKeyboardFocus.OnDemand",
    "CompositorService.isHyprland",
    "&& root.keyboardFocus && root.requestedVisible",
    "? WlrLayer.Top : WlrLayer.Overlay",
):
    require(styled_popup, token,
            "StyledPopup must support click-activated exclusive keyboard ownership")

shortcut_pos = popup.find("sequences: [StandardKey.Cancel]")
content_pos = popup.find("id: contentRoot")
if shortcut_pos < 0 or content_pos < 0 or shortcut_pos < content_pos:
    fail("Quick Notes Escape shortcut must live inside popup content")

for token in (
    "property bool quickCapturePresentation: false",
    "readonly property bool zettelkastenIntegrationEnabled:",
    "!root.quickCapturePresentation",
    "target: root.zettelkastenIntegrationEnabled ? Zettelkasten : null",
    "visible: !root.quickCapturePresentation",
    "signal editorActivated()",
    "function focusEditor(): void",
    "textArea.forceActiveFocus()",
    "function releaseEditorFocus(): void",
    "textArea.focus = false",
    "function flushPendingSave(): void",
    "saveTimer.stop()",
    'property string _loadedTabId: ""',
    "readonly property string displayedTabId:",
    "readonly property int displayedTabIndex:",
    "readonly property string displayedTabTitle:",
    "property bool surfaceLocalTabSelection: false",
    "readonly property bool veryNarrowCompact:",
    "function _activeTabId(): string",
    "function _loadTabById(tabId): bool",
    "Notepad.setTabTextById(root._loadedTabId, textArea.text)",
    "if (root.focus)",
    "function switchToTab(index): void",
    "function addTabSafely(): void",
    "function removeTabSafely(index): void",
    "if (root.surfaceLocalTabSelection) {",
    "root._loadTabById(targetId)",
    "Notepad.indexForTabId(root._loadedTabId) < 0",
    "String(modelData?.id ?? \"\") === root._loadedTabId",
    "id: tabFlick",
    "implicitHeight: root.compactPresentation ? 24 : 28",
    "x: Math.max(0, (tabFlick.width - implicitWidth) / 2)",
    "height: root.compactPresentation ? 22 : 26",
    "id: editorStage",
    "id: noteRail",
    "id: editorCard",
    "id: compactActionRail",
    "id: primaryNoteActions",
    "id: secondaryNoteActions",
    "anchors.top: parent.top",
    "anchors.bottom: parent.bottom",
    "opacity: editorStageHover.hovered || textArea.activeFocus ? 1 : 0",
    "onClicked: root.switchToTab(tabPill.index)",
    "onClicked: root.addTabSafely()",
    "onClicked: root.removeTabSafely(tabPill.index)",
    "onActiveFocusChanged:",
    "if (activeFocus)",
    "root.editorActivated()",
    "MouseArea {",
    "acceptedButtons: Qt.NoButton",
    "hoverEnabled: true",
    "cursorShape: Qt.IBeamCursor",
    "id: editorFocusCatcher",
    "visible: Notepad.ready && !textArea.activeFocus",
    "acceptedButtons: Qt.LeftButton",
    "textArea.forceActiveFocus()",
    "textArea.cursorPosition = textArea.positionAt(",
    "mouse.accepted = true",
    "Component.onDestruction: root.flushPendingSave()",
):
    require(notepad, token, "shared Notepad must expose safe Quick Notes hooks")

forbid(notepad, "TapHandler {",
       "shared Notepad editor must not intercept TextArea presses to obtain focus")

rail_pos = notepad.find("id: noteRail")
editor_pos = notepad.find("id: editorCard")
action_rail_pos = notepad.find("id: compactActionRail")
if min(rail_pos, editor_pos, action_rail_pos) < 0 or not (
        rail_pos < editor_pos < action_rail_pos):
    fail("Quick Notes note indicators and hover actions must stay outside the editor card")

inline_start = notepad.find("// Full Sidebar presentation keeps Add beside the tabs.")
inline_end = notepad.find("// Full toolbar remains unchanged for Sidebar;", inline_start)
if inline_start < 0 or inline_end < 0:
    fail("Quick Notes tab-row lifecycle block is missing")
inline_block = notepad[inline_start:inline_end]
require(inline_block, "visible: !root.compactPresentation",
        "Sidebar-only Add action must not consume compact Quick Notes height")
for compact_action in ('icon: "close"', "root.displayedTabIndex"):
    forbid(inline_block, compact_action,
           "Compact Add/Remove actions must not duplicate the full tab toolbar")

primary_start = notepad.find("id: primaryNoteActions", action_rail_pos)
secondary_start = notepad.find("id: secondaryNoteActions", action_rail_pos)
if primary_start < 0 or secondary_start < 0 or primary_start > secondary_start:
    fail("Quick Notes primary and secondary right-side action groups are missing")
primary_block = notepad[primary_start:secondary_start]
for token in (
    'icon: "add"',
    'icon: "close"',
    "root.addTabSafely()",
    "root.removeTabSafely(root.displayedTabIndex)",
):
    require(primary_block, token,
            "Compact presentations without note dots keep their lifecycle controls")

require(primary_block, "visible: !root.verticalDotNavigation",
        "note-dot presentation must not duplicate Add/Remove on the opposite side")

for token in (
    'icon: "content_copy"',
    'icon: "content_paste"',
    'icon: "select_all"',
    'icon: "delete"',
):
    require(notepad[secondary_start:], token,
            "Quick Notes hover rail is missing a secondary editor action")

for token in (
    "QuickNotesView {",
    "preferredHeight: 210",
    "surfaceLocalTabSelection: true",
    "showZettelkastenActions: true",
    "root.flushPendingSave()",
    "root.releaseEditorFocus()",
):
    require(sidebar_quick_note, token,
            "Sidebar Quick Note must delegate to the shared presentation")

for retired in (
    "property string draftTabId:",
    "function beginEditing()",
    "function saveDraft()",
    "function cancelEditing()",
    "TextArea {",
    "RippleButton {",
):
    forbid(sidebar_quick_note, retired,
           "Sidebar Quick Note must not restore its legacy private editor")

for token in (
    "signal editorActivated()",
    "NotepadWidget {",
    "compactPresentation: true",
    "surfaceLocalTabSelection: root.surfaceLocalTabSelection",
    'text: Translation.tr("Quick Notes")',
    "readonly property bool narrowHeader:",
    "readonly property bool veryNarrowHeader:",
    "spacing: root.veryNarrowHeader ? 4 : 6",
    "&& !root.narrowHeader",
    "function focusEditor(): void",
    "function flushPendingSave(): void",
    "function releaseEditorFocus(): void",
    "notepad.releaseEditorFocus()",
    "onEditorActivated: root.editorActivated()",
    "showZettelkastenActions",
):
    require(quick_notes_view, token,
            "shared Quick Notes presentation contract missing")

if dash_notes.count("QuickNotesView {") != 1:
    fail("Dashboard Quick Notes must own exactly one shared QuickNotesView")
for token in (
    "surfaceLocalTabSelection: true",
    "showZettelkastenActions: true",
):
    require(dash_notes, token,
            "Dashboard Quick Notes must configure the shared presentation")
forbid(dash_notes, "NotepadWidget {",
       "Dashboard must not bypass the shared Quick Notes presentation")

tabs_loaded_start = notepad_service.index("        onLoaded: {")
tabs_saved_start = notepad_service.index("        onSaved:", tabs_loaded_start)
tabs_loaded_block = notepad_service[tabs_loaded_start:tabs_saved_start]
if "legacyFileView.path" in tabs_loaded_block:
    fail("Existing invalid multi-tab storage must never fall back to stale legacy data")
if "root._saving" in tabs_loaded_block:
    fail("Notepad writes must complete from FileView saved(), never loaded()")
require(tabs_loaded_block, "Tabs file contains no valid tabs; preserving it",
        "Notepad must fail closed when an existing tabs file has no valid tabs")
require(tabs_loaded_block, "Invalid tabs file; preserving it:",
        "Notepad must preserve malformed existing tabs storage for recovery")

for token in (
    "function _finishSave(): void",
    "onSaved: root._finishSave()",
    "onSaveFailed: (error) =>",
    "tabsFileView.loaded && tabsFileView.text() === serialized",
    "function _allocateTabId()",
    "function _makeTab(title, text)",
    "while (seenIds.includes(id))",
    "function indexForTabId(tabId)",
    "function setTabTextById(tabId, newText)",
    "property bool _normalizedTabsNeedSave: false",
    "if (root._normalizedTabsNeedSave)",
    "Qt.callLater(() => root._save())",
    "if (index < previousCurrent)",
    "currentTab = previousCurrent - 1",
):
    require(notepad_service, token,
            "shared Notepad must preserve stable tab identity across surfaces")

for token in (
    'property string quickNotesEditorOutput: ""',
    "function setQuickNotesEditorOutput(outputName, focused): void",
    "(!screenCorners.quickNotesEditorOutput",
    "|| screenCorners.quickNotesEditorOutput === name)",
    "Component.onDestruction:",
    "cornerPanelWindow.outputName, false",
    "readonly property bool shouldShowQuickNotesCorner:",
    "cornerPanelWindow.quickNotesMonitorAllowed",
    "screenCorners.quickNotesEditorOutput === outputName",
    "function quickNotesBarTargetsOutput(): bool",
    'readonly property string quickNotesAttachmentEdge: "bottom"',
    "Appearance.sizes.barHeight",
    "Config.options?.bar?.autoHide?.enable ?? false",
    "cornerAttachmentEdge: cornerPanelWindow.quickNotesAttachmentEdge",
    "cornerAttachmentThickness: cornerPanelWindow.quickNotesAttachmentThickness",
    "cornerPanelWindow.isBottomLeft",
    'Config.options?.quickNotes?.monitorMode ?? "all"',
    'outputName === (GlobalStates.primaryScreen?.name ?? "")',
    "&& !cornerPanelWindow.niriOverviewOwnsCorner",
    "&& !cornerPanelWindow.quickNotesInteractionBlocked",
    "GlobalStates.controlPanelOpen",
    "GlobalStates.dashboardOpen",
    "GlobalStates.searchOpen",
    "GlobalStates.settingsNativeDialogOpen",
    "GlobalStates.tilingOverlayOsdOpen",
    "&& !shouldShowQuickNotesCorner",
    "id: quickNotesCornerLoader",
    "onActiveChanged:",
    "onEditorFocusedChanged:",
    "screenCorners.setQuickNotesEditorOutput(",
    "property bool dwellReady: false",
    "id: quickNotesDwellTimer",
    "Config.options?.quickNotes?.hoverDelayMs ?? 220",
    "Config.options?.quickNotes?.cornerSize ?? 14",
    "QuickNotesPopup {",
    "anchorItem: quickNotesAnchor",
):
    require(corners, token, "bottom-left Quick Notes corner contract missing")

# Orbit is retired. The compositor's real Niri overview hot corner still owns
# its physical corner before Quick Notes or the legacy Sidebar trigger.
quick_start = corners.index("readonly property bool shouldShowQuickNotesCorner:")
sidebar_start = corners.index("readonly property bool shouldShowSidebarCornerOpen:")
if not quick_start < sidebar_start:
    fail("Quick Notes priority must be resolved before legacy sidebar corner-open")
quick_block = corners[quick_start:sidebar_start]
require(quick_block, "!cornerPanelWindow.niriOverviewOwnsCorner",
        "native Niri overview hot corners must retain priority over Quick Notes")
for retired in ("shouldShowOrbitHotCorner", "GlobalStates.openOrbit(",
                "Config.options?.orbit", 'overviewMode !== "orbit"'):
    forbid(corners, retired, "retired Orbit hot-corner runtime must stay absent")

schema_match = re.search(
    r"property JsonObject quickNotes: JsonObject \{([\s\S]*?)\n\s*\}",
    config,
)
if not schema_match:
    fail("Config schema does not expose quickNotes")
schema = schema_match.group(1)
for token in (
    "property bool enable: true",
    'property string monitorMode: "all"',
    "property int hoverDelayMs: 220",
    "property int cornerSize: 14",
    "property int popupWidth: 420",
    "property int popupHeight: 300",
):
    require(schema, token, "Quick Notes Config default missing")

expected_defaults = {
    "enable": True,
    "monitorMode": "all",
    "hoverDelayMs": 220,
    "cornerSize": 14,
    "popupWidth": 420,
    "popupHeight": 300,
}
default_quick_notes = defaults.get("quickNotes")
if not isinstance(default_quick_notes, dict):
    fail("defaults/config.json must expose a Quick Notes object")
for key, value in expected_defaults.items():
    if default_quick_notes.get(key) != value:
        fail(f"defaults/config.json Quick Notes {key} does not match Config.qml schema")

for token in (
    'title: Translation.tr("Bottom-left Quick Notes")',
    'text: Translation.tr("Hover to reveal; click to type.")',
    'Config.options?.quickNotes?.enable ?? true',
    'Config.setNestedValue("quickNotes.enable", checked)',
    'Config.options?.quickNotes?.monitorMode ?? "all"',
    'Config.setNestedValue("quickNotes.monitorMode", newValue)',
    'Translation.tr("Primary only")',
    'Translation.tr("All monitors")',
    'Config.setNestedValue("quickNotes.hoverDelayMs", value)',
    'Config.setNestedValue("quickNotes.cornerSize", value)',
    'Config.setNestedValue("quickNotes.popupWidth", value)',
    'Config.setNestedValue("quickNotes.popupHeight", value)',
):
    require(settings, token, "Quick Notes Settings controls missing")

for token in (
    'section: Translation.tr("Bottom-left Quick Notes")',
    'label: Translation.tr("Quick Notes corner")',
    '"quick notes"',
    '"bottom left"',
    '"hover"',
    '"monitor"',
    '"primary"',
    '"all monitors"',
):
    require(registry, token, "Quick Notes Settings search metadata missing")

# Quick Notes Reading/Source is focus-driven on Dashboard and the popup;
# Sidebar Left and the full Notepad retain their existing Source-first entry.
for token in (
    "property bool autoMarkdownReading: false",
    "property bool externalEscapeHandling: false",
    "property bool markdownEditing: !root.autoMarkdownReading",
    "readonly property bool markdownReading: root.autoMarkdownReading && !root.markdownEditing",
    "signal editorDeactivated()",
    "onActiveFocusChanged:",
    "Qt.callLater(() => {",
    "root.releaseEditorFocus()",
    "root.editorDeactivated()",
    "root.autoMarkdownReading && !root.externalEscapeHandling",
    "event.key === Qt.Key_Escape",
    "event.accepted = true",
    "root.flushPendingSave()",
    "textArea.forceActiveFocus()",
):
    require(notepad, token, "Quick Notes focus-driven Markdown contract missing")

for token in (
    "property bool autoMarkdownReading: false",
    "property bool externalEscapeHandling: false",
    "autoMarkdownReading: root.autoMarkdownReading",
    "externalEscapeHandling: root.externalEscapeHandling",
    "onEditorDeactivated: root.editorDeactivated()",
):
    require(quick_notes_view, token, "QuickNotesView mode forwarding missing")

for token in (
    "autoMarkdownReading: true",
    "externalEscapeHandling: true",
    "onEditorActivated: root.enterEditorMode()",
    "onEditorDeactivated: root.editorFocused = false",
    "property bool escapeArmed: false",
    "root.escapeArmed = true",
    "root.leaveEditorMode()",
    "keyboardFocus: root.editorFocused || root.todoDialogOpen || root.escapeArmed",
):
    require(popup, token, "Quick Notes popup two-stage Escape missing")

require(dash_notes, "autoMarkdownReading: true",
        "Dashboard Quick Notes must open in Reading")

for source in (quick_notes_view, dash_notes):
    for retired in ("showMarkdownModeSwitch", "markdownModeSwitch",
                    "toggleMarkdownMode", "Source-first Markdown Reading switch"):
        forbid(source, retired, "Quick Notes must not expose a manual mode switch")

for retired in ("readingOnHover", "allowManualReading", "enterMarkdownReading"):
    forbid(notepad, retired, "Retired manual/hover Markdown mode still used")

# Do not inadvertently turn the Sidebar Left editor into a forced Reading host.
forbid(sidebar_quick_note, "autoMarkdownReading: true",
       "Sidebar Left should retain Source-first entry")

# Retraction is intentionally different from forced owner eviction.
# Scope assertions to each method: QML often uses unqualified property names
# inside its own root object, so requiring a literal "root." is incorrect.
def _scoped(source: str, opening: str, closing: str, label: str) -> str:
    before, found, tail = source.partition(opening)
    if not found:
        fail(f"Graceful slide-under popup close contract missing ({label}: opening)")
    body, found, after = tail.partition(closing)
    if not found:
        fail(f"Graceful slide-under popup close contract missing ({label}: closing)")
    return body


require(styled_popup, "property bool _gracefulDismissal: false",
        "Graceful slide-under state flag missing")
retract = _scoped(styled_popup, "function retractPresentation(): void {",
                  "function dismissPresentation(): void {", "retractPresentation")
for token in (
    "_gracefulDismissal = true",
    "_liquidDismissed = true",
    "if (_lingerVisible)",
    "_beginRetract()",
    "requestClose()",
):
    require(retract, token, "Graceful slide-under retract path missing")

forced_dismiss = _scoped(styled_popup, "function dismissPresentation(): void {",
                         "property QtObject _liquidPresentationConnections",
                         "dismissPresentation")
for token in ("_gracefulDismissal = false", "_lingerVisible = false",
              "offsetScale = 1", "requestClose()"):
    require(forced_dismiss, token, "Forced owner eviction contract missing")

finish_retract = _scoped(styled_popup,
                         "function _finishGracefulDismissal(): void {",
                         "property bool _lingerVisible", "finishGracefulDismissal")
for token in ("root._gracefulDismissal = false", "root._liquidDismissed = false"):
    require(finish_retract, token, "Graceful close completion contract missing")

begin_retract = _scoped(styled_popup, "function _beginRetract(): void {",
                        "function _syncRequestedVisibility(): void {", "beginRetract")
for token in ("if (!root._lingerVisible)", "root.offsetScale = 1",
              "retractTimer.restart()", "root._finishGracefulDismissal()"):
    require(begin_retract, token, "Slide-under retract animation contract missing")

retract_timer = _scoped(styled_popup,
                        "property QtObject _retractTimerObject: Timer {",
                        "function _anchorRect(", "retractTimer")
for token in ("interval: Math.max(1, SurfaceMotion.duration + 16)",
              "root._lingerVisible = false", "root._finishGracefulDismissal()"):
    require(retract_timer, token, "Slide-under retract completion timer missing")

visible_sync = _scoped(styled_popup,
                       "function _syncRequestedVisibility(): void {",
                       "onRequestedVisibleChanged:", "syncRequestedVisibility")
for token in ("root._lingerVisible = true", "root._beginRetract()"):
    require(visible_sync, token, "Popup visible/retract lifecycle missing")
require(styled_popup,
        "onRequestedVisibleChanged: root._syncRequestedVisibility()",
        "Popup visibility synchronization missing")
require(styled_popup,
        "(root.requestedVisible || root._lingerVisible)",
        "Popup must stay resident for the animation tail")

# Assert the actual Escape state machine, not just a stray call elsewhere.
# First Escape releases editing and arms the lease; second Escape retracts
# with StyledPopup's graceful slide tail. Forced eviction may still dismiss.
escape_shortcut = re.search(
    r"Shortcut\s*\{\s*sequences:\s*\[StandardKey\.Cancel\]"
    r"[\s\S]*?onActivated:\s*\{\s*if\s*\(root\.editorFocused\)\s*\{"
    r"\s*root\.escapeArmed\s*=\s*true"
    r"\s*root\.leaveEditorMode\(\)\s*\}\s*else\s*\{"
    r"\s*root\.escapeArmed\s*=\s*false"
    r"\s*root\.retractPresentation\(\)\s*\}\s*\}",
    popup,
)
if escape_shortcut is None:
    fail("Quick Notes Escape must leave editing first and gracefully retract on second press")

for token in (
    "event.key === Qt.Key_U",
    'event.key === Qt.Key_L ? "align-left"',
    'event.key === Qt.Key_E ? "align-center"',
    'event.key === Qt.Key_R ? "align-right"',
    'event.key === Qt.Key_J ? "align-justify"',
    "Qt.ControlModifier | Qt.ShiftModifier",
):
    require(notepad, token, "Quick Notes editor keyboard formatting missing")

for token in (
    "function _renumberDefaultTitles(value)",
    "if (renamed.changed)",
    "_normalizedTabsNeedSave = true",
    "tabs = root._renumberDefaultTitles(t).tabs",
):
    require(notepad_service, token,
            "Default note titles must renumber on load and mutations")

print("ok - bottom-left Quick Notes corner contract")
