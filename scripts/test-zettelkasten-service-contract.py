#!/usr/bin/env python3
"""Contract guard for Dashboard/Notepad Zettelkasten quick-note capture."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
widget = (ROOT / "modules/sidebarRight/notepad/NotepadWidget.qml").read_text(encoding="utf-8")
service = (ROOT / "services/Zettelkasten.qml").read_text(encoding="utf-8")
todo_service = (ROOT / "services/Todo.qml").read_text(encoding="utf-8")
dash = (ROOT / "modules/dashboard/DashNotes.qml").read_text(encoding="utf-8")
quick_notes = (ROOT / "modules/sidebarRight/notepad/QuickNotesView.qml").read_text(encoding="utf-8")
settings = (ROOT / "modules" / "settings" / "IntegrationsConfig.qml").read_text(encoding="utf-8")
obsidian_settings = (ROOT / "modules" / "settings" / "ObsidianThemeSettings.qml").read_text(encoding="utf-8")
shared_settings = settings + obsidian_settings
system_services = (ROOT / "modules" / "settings" / "ServicesConfig.qml").read_text(encoding="utf-8")
assert 'title: Translation.tr("To-do & Quick Notes")' not in system_services
qmldir = (ROOT / "services/qmldir").read_text(encoding="utf-8")
config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
defaults = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))

for token in (
    'icon: "note_add"',
    'Translation.tr("Save as Zettelkasten quick note")',
    "Zettelkasten.capture(title, draftText)",
    "function saveAsZettel(): bool",
    "function captureQuickNote(): bool",
    "readonly property bool canSaveZettel:",
    'Translation.tr("Saved to Zettelkasten")',
    '/^Note \\d+$/.test(tabTitle)',
    "Notepad.setTabTextById(root._loadedTabId, textArea.text)",
    "draft cleanup remains an explicit user action",
    "property bool compactPresentation: false",
    "visible: !root.compactPresentation",
    "visible: root.compactPresentation",
):
    assert token in widget, f"Notepad Zettelkasten UI contract lost: {token}"

for token in ("pragma Singleton", "AlisIntergration.session?.zettelkasten", "function capture(title, body): bool", "signal captured(var payload)"):
    assert token in service, "Zettelkasten facade lost contract: "+token
assert "Process {" not in service and "Timer {" not in service


for token in (
    'Translation.tr("Quick Notes")',
    'Translation.tr("Zettelkasten capture")',
    'Translation.tr("%1 note · draft stays in Notepad")',
    ".arg(Zettelkasten.defaultType)",
    "Zettelkasten.errorMessage.length > 0",
    "enabled: notepad.canSaveZettel",
    "onClicked: notepad.captureQuickNote()",
    "compactPresentation: true",
    "margin: 0",
    "readonly property bool constrainedHeight:",
    "Layout.minimumHeight: root.constrainedHeight ? 76 : 130",
):
    assert token in quick_notes, f"Shared Quick Notes Zettelkasten contract lost: {token}"

for token in (
    "QuickNotesView {",
    "surfaceLocalTabSelection: true",
    "showZettelkastenActions: true",
    "margin: 0",
):
    assert token in dash, f"Dashboard Notes shared-view host contract lost: {token}"


assert "singleton Zettelkasten 1.0 Zettelkasten.qml" in qmldir
assert "property JsonObject notes: JsonObject {" in config
assert 'property string folder: "00_Capture/03_Zettelkasten"' in config
assert defaults["notes"]["zettelkasten"] == {
    "vaultPath": "",
    "folder": "00_Capture/03_Zettelkasten",
    "defaultType": "Fleeting",
}

print("Zettelkasten quick-note service/UI contract: PASS")

assert 'Translation.tr("Create a Fleeting Zettelkasten note.' not in dash
assert "font.pixelSize: Appearance.font.pixelSize.smallest" not in dash
assert "_clearCapturedDraft" not in widget
assert "_pendingZettelCapture" not in widget
assert "function removeTabSafely(index): void" in widget
assert "root.flushPendingSave()" in widget
assert "if (!Notepad.removeTab(index))" in widget
assert "draft clears after verified save" not in dash
assert 'text: Translation.tr("Capture")' not in dash

# Generic shared-vault resolution and optional routing remain host-owned.
assert "readonly property string sharedVaultPath:" in todo_service
assert 'Config.options?.todo?.obsidian?.vaultPath ?? ""' in todo_service
assert 'Config.options?.notes?.zettelkasten?.vaultPath ?? ""' in todo_service
assert todo_service.count("vaultPath: root.sharedVaultPath") == 2
assert "notes.zettelkasten.vaultPath" not in service
assert 'GlobalStates.openSettingsSection(7, "To-do & Quick Notes")' in quick_notes

# The optional package owns the shared Obsidian path editor. Core owns only
# navigation metadata and a selected/disposable settings loader.
assert 'active: AlisIntergration.obsidianEnabled' in obsidian_settings
assert 'source: AlisIntergration.settingsSource("obsidian")' in obsidian_settings
assert 'property string settingsTaskSection:' in obsidian_settings
assert 'id: todoObsidianVaultPath' not in settings
