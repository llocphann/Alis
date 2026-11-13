#!/usr/bin/env python3
"""Guard Todo UI routing across internal and Nexus backends."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
widget = (ROOT / "modules" / "sidebarRight" / "todo" / "TodoWidget.qml").read_text(encoding="utf-8")
task_list = (ROOT / "modules" / "sidebarRight" / "todo" / "TaskList.qml").read_text(encoding="utf-8")

assert 'onClicked: Todo.openSource("")' in widget
assert '["xdg-open", Directories.todoTxtPath]' not in widget

assert 'if (Todo.backend === "nexus")' in task_list
assert "actionTimer.start()" in task_list
assert "enabled: !Todo.busy" in task_list
assert task_list.count("enabled: !Todo.busy") >= 2

print("Todo UI backend routing contract: PASS")
