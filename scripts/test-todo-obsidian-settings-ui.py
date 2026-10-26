#!/usr/bin/env python3
"""Host ownership of optional Todo settings, fallback and preserved internal store."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
page=(ROOT/'modules/settings/IntegrationsConfig.qml').read_text()
wrapper=(ROOT/'modules/settings/ObsidianTodoSettings.qml').read_text()
facade=(ROOT/'services/Todo.qml').read_text()
internal=(ROOT/'services/InternalTodoBackend.qml').read_text()
assert 'objectName: "integrationPluginSettings"' in page
assert 'AlisIntergration.settingsSource(' in page and 'selectedCapability.settings' in page
assert 'AlisIntergration.pluginEnabled(root.activePlugin)' in page
assert 'id: todoMarkdownNotePattern' not in page
assert 'objectName: "integrationRestoreInternalTodos"' in page
assert 'Todo.backend === "obsidian" && !AlisIntergration.obsidianEnabled' in page
assert 'onClicked: Todo.reactivateInternal()' in page
assert 'source: AlisIntergration.settingsSource("obsidianTodo")' in wrapper
assert 'active: AlisIntergration.obsidianEnabled && root.visible' in wrapper
assert 'property string settingsTaskSection: "obsidian"' in wrapper
assert 'onClicked: Todo.reactivateInternal()' in wrapper
assert 'Config.setNestedValue("todo.backend", "obsidian")' in facade
assert "readonly property bool useLegacyManagedNote:" in facade
assert "readonly property bool persistenceBusy:" in internal
print('Optional Todo settings host/store contract: PASS')
