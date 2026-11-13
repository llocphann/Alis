#!/usr/bin/env python3
"""Dashboard Todo concept and backend-routing contract."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
dash = (ROOT / "modules" / "dashboard" / "DashTodo.qml").read_text(encoding="utf-8")

for token in (
    'title: ""',
    "readonly property var unfinishedTasks:",
    "readonly property var doneTasks:",
    'Translation.tr("Unfinished")',
    'Translation.tr("Done")',
    "colPrimaryContainer",
    "Todo.markDone(item.originalIndex)",
    "Todo.markUnfinished(item.originalIndex)",
    "Todo.deleteItem(item.originalIndex)",
    'Translation.tr("Add task")',
    'Translation.tr("Prepare Nexus")',
    'GlobalStates.openSettingsSection(7, "To-do & Quick Notes")',
    'Todo.openSource("")',
    'Todo.backend === "nexus"',
    "Todo.sourceLabel",
    "Todo.useMarkdownNote",
    "Todo.addTaskWithTime(text, start, end)",
    'Translation.tr("Start time")',
    'Translation.tr("End time")',
    "taskRow.modelData.startTime",
    "taskRow.modelData.endTime",
):
    assert token in dash, f"Dashboard Todo lost concept contract: {token}"

assert "TodoWidget {" not in dash, "Dashboard Todo must not be coupled to Sidebar presentation"
assert 'text: "more_horiz"' not in dash, "Dashboard Todo must not restore the overflow settings button"
assert "enabled: Todo.ready && !Todo.busy" in dash
assert "font.strikeout: taskRow.modelData.done === true" in dash

print("Dashboard Todo concept contract: PASS")
