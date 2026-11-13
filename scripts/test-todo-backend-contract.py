#!/usr/bin/env python3
"""Contract guard for the Todo facade/backend split."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
facade = (ROOT / "services" / "Todo.qml").read_text(encoding="utf-8")
internal = (ROOT / "services" / "InternalTodoBackend.qml").read_text(encoding="utf-8")
nexus = (ROOT / "services" / "NexusTodoBackend.qml").read_text(encoding="utf-8")
qmldir = (ROOT / "services" / "qmldir").read_text(encoding="utf-8")

required_facade = [
    "InternalTodoBackend {",
    "NexusTodoBackend {",
    "DailyNoteTodoBackend {",
    'Config.options?.todo?.nexus?.sourceMode ?? "markdown-note"',
    'root.nexusSourceMode === "managed-note"',
    "readonly property bool useMarkdownNote:",
    "readonly property var nexusBackend:",
    'Config.options?.todo?.backend ?? "internal"',
    'root.requestedBackend === "nexus"',
    "active: (root.useNexus || root._nexusSetupActive) && root.useLegacyManagedNote",
    "property bool _migrationInFlight: false",
    "readonly property var list: root.useNexus ? root.nexusBackend.list : internal.list",
    "readonly property bool ready:",
    "readonly property bool busy: root.useNexus ? root.nexusBackend.busy : root._migrationInFlight",
    "readonly property string errorMessage:",
    "readonly property var capabilities:",
    "readonly property string sourceLabel:",
    "property alias filePath: internal.filePath",
    "property alias txtFilePath: internal.txtFilePath",
    "return internal.addItem(item)",
    "return internal.addTask(desc)",
    "return internal.markDone(index)",
    "return internal.markUnfinished(index)",
    "return internal.deleteItem(index)",
    "return root.nexusBackend.toggleTask(String(item.id ?? \"\"))",
    "return root.nexusBackend.deleteTask(String(item.id ?? \"\"))",
    "function addTaskWithTime(desc, startTime, endTime)",
    "readonly property bool nexusSetupActive: root._nexusSetupActive",
    "readonly property bool nexusReady: root.nexusBackend.ready",
    "readonly property var nexusMigrationPreview: root.nexusBackend.migrationPreview",
    "function beginNexusSetup(): bool",
    "function cancelNexusSetup(): void",
    "function initializeSection()",
    "function previewInternalToNexus(): bool",
    "readonly property int internalItemCount: internal.list.length",
    "function migrateInternalToNexus(expectedInternalSha)",
    "root._activateAfterMigration = staging",
    "root._migrationInFlight = staging",
    "function onMigrationFinished(success, payload): void",
    "root.nexusBackend.migrateInternal(",
    "function activateNexus(): bool",
    "function reactivateInternal(): bool",
    'Config.setNestedValue("todo.backend", "nexus")',
    'Config.setNestedValue("todo.backend", "internal")',
    "function openNexusSource(): bool",
    "function toggleTask(taskId)",
    "function deleteTask(taskId)",
    "function openSource(taskId)",
    '"nexus://open?path=" + encodeURIComponent(root.nexusBackend.noteFullPath)',
]
for snippet in required_facade:
    assert snippet in facade, f"Todo facade lost contract: {snippet}"

assert "FileView {" not in facade, "persistence leaked into Todo facade"
assert "Process {" not in facade, "process implementation leaked into Todo facade"
assert '"internal"' in facade, "internal backend default/fallback disappeared"
assert "readonly property var list: root.useNexus ? root.nexusBackend.list : internal.list" in facade
assert "root._nexusSetupActive ? nexus.list" not in facade, "staging backend leaked into public canonical list"

required_internal = [
    "Scope {",
    "property string filePath: Directories.todoPath",
    "property string txtFilePath: Directories.todoTxtPath",
    "property var list: []",
    "property bool ready: false",
    "function addTask(desc)",
    "function markDone(index)",
    "function markUnfinished(index)",
    "function deleteItem(index)",
    "function refresh()",
    "function _parseTxt(text)",
    "FileView {",
    "Process {",
]
for snippet in required_internal:
    assert snippet in internal, f"internal Todo backend lost behavior: {snippet}"

assert "pragma Singleton" not in internal, "internal backend must not become a second singleton"
assert facade.count("if (root._migrationInFlight)") >= 7, "internal mutations must freeze during migration"
assert "signal migrationFinished(bool success, var payload)" in nexus
assert 'function onMigrationFinished(success, payload): void' in nexus
assert 'root.migrationFinished(success, payload)' in nexus

assert "InternalTodoBackend 1.0 InternalTodoBackend.qml" in qmldir
assert "NexusTodoBackend 1.0 NexusTodoBackend.qml" in qmldir
assert "DailyNoteTodoBackend 1.0 DailyNoteTodoBackend.qml" in qmldir
assert "singleton Todo 1.0 Todo.qml" in qmldir

print("Todo facade/backend contract: PASS")
