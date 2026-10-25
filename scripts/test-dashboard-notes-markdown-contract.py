#!/usr/bin/env python3
"""Dashboard Markdown mode uses canonical shared notes without a copy backend."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
dash=(ROOT/"modules/dashboard/DashNotes.qml").read_text()
view=(ROOT/"modules/sidebarRight/notepad/QuickNotesView.qml").read_text()
widget=(ROOT/"modules/sidebarRight/notepad/NotepadWidget.qml").read_text()
planner=(ROOT/"modules/dashboard/DashboardWeeklyPlanner.qml").read_text()
corner=(ROOT/"modules/screenCorners/QuickNotesPopup.qml").read_text()
assert "autoMarkdownReading: true" in dash
assert "quickNotesSharedDashboardView" in dash
assert "QuickNotesView" in dash and "NotepadWidget" not in dash
assert "Component {id:notesPanel;DashNotes {}}" in planner
assert "autoMarkdownReading: true" in corner
assert "property bool autoMarkdownReading: false" in view
assert "property bool externalEscapeHandling: false" in view
assert "autoMarkdownReading: root.autoMarkdownReading" in view
assert "externalEscapeHandling: root.externalEscapeHandling" in view
assert "onEditorDeactivated: root.editorDeactivated()" in view
assert "property bool markdownEditing: !root.autoMarkdownReading" in widget
assert "property bool autoMarkdownReading: false" in widget
assert "root.releaseEditorFocus()" in widget and "root.markdownEditing = false" in widget
assert widget.count("visible: root.markdownReading") == 1
assert widget.count("visible: !root.markdownReading") == 1
assert "MarkdownNote.safeReading(textArea.text)" in widget
assert "root.flushPendingSave()" in widget
assert "Notepad.setTabTextById" in widget
assert "MarkdownNote.format(textArea.text" in widget
print("DASHBOARD_NOTES_MARKDOWN_SOURCE_PASS 18 contracts")
