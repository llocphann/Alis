#!/usr/bin/env python3
"""Core optional Todo interface; behavior is covered by native host fixtures."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
backend=(ROOT/"services/DailyNoteTodoBackend.qml").read_text()
qmldir=(ROOT/"services/qmldir").read_text()
assert 'property bool active: false' in backend
assert 'active: root.active && AlisIntergration.obsidianEnabled' in backend
assert 'return false' in backend and 'integration-unavailable' in backend
for forbidden in ('Process {','Timer {','FileView {','"eval"','["obsidian"'):
    assert forbidden not in backend, "core retained a worker/runtime CLI: "+forbidden
assert 'AlisIntergration.backendSource("daily")' in backend
assert "DailyNoteTodoBackend 1.0 DailyNoteTodoBackend.qml" in qmldir
for field in ['vaultPath', 'folder', 'noteFormat', 'plannerHeading', 'plannerHeadingLevel', 'defaultDurationMinutes']:
    assert "root."+field in backend and "item."+field in backend, "lost live parameter binding: "+field
for method in ('previewInternal','migrateInternal','addTask','toggleTask','deleteTask'):
    assert "function "+method+"(" in backend and "root.implementation."+method+"(" in backend, "lost owned action: "+method
for signal in ('migrationCommitted','migrationFinished'):
    assert "signal "+signal in backend and "root."+signal+"(" in backend, "lost forwarded migration signal: "+signal
print("CORE_OPTIONAL_TODO_INTERFACE_PASS")
