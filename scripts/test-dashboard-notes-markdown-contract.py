#!/usr/bin/env python3
"""Dashboard Markdown mode uses canonical shared notes without a copy backend."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
dash=(ROOT/"modules/dashboard/DashNotes.qml").read_text()
view=(ROOT/"modules/sidebarRight/notepad/QuickNotesView.qml").read_text()
widget=(ROOT/"modules/sidebarRight/notepad/NotepadWidget.qml").read_text()
planner=(ROOT/"modules/dashboard/DashboardWeeklyPlanner.qml").read_text()
corner=(ROOT/"modules/screenCorners/QuickNotesPopup.qml").read_text()
assert "showMarkdownModeSwitch: true" in dash
assert "quickNotesSharedDashboardView" in dash
assert "QuickNotesView" in dash and "NotepadWidget" not in dash
assert "Component {id:notesPanel;DashNotes {}}" in planner
assert 'readingOnHover: true' in corner
assert "property bool showMarkdownModeSwitch: false" in view
assert 'objectName: "quickNotesMarkdownModeSwitch"' in view
assert "allowManualReading: root.showMarkdownModeSwitch" in view
assert "readingOnHover: root.readingOnHover" in view
assert "notepad.enterMarkdownReading()" in view and "root.focusEditor()" in view
assert "property bool markdownEditing: !root.readingOnHover" in widget
assert "property bool allowManualReading: false" in widget
assert "root.releaseEditorFocus()" in widget and "root.markdownEditing = false" in widget
assert widget.count("visible: root.markdownReading") == 1
assert widget.count("visible: !root.markdownReading") == 1
assert "MarkdownNote.safeReading(textArea.text)" in widget
assert "root.flushPendingSave()" in widget
assert "Notepad.setTabTextById" in widget
assert "MarkdownNote.format(textArea.text" in widget
print("DASHBOARD_NOTES_MARKDOWN_SOURCE_PASS 18 contracts")
