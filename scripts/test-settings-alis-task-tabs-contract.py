#!/usr/bin/env python3
"""Compatibility entry point: shared sculpted Settings task navigation."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

nav = read("modules/common/widgets/SettingsTaskNavigator.qml")
array = read("modules/common/widgets/ConfigSelectionArray.qml")
button = read("modules/common/widgets/SelectionGroupButton.qml")
page = read("modules/common/widgets/ContentPage.qml")
overlay = read("modules/settings/SettingsOverlay.qml")
embedded = read("modules/abyss/content/AbyssSettingsContent.qml")

assert 'SettingsMaterialPreset.cardColor' in nav
assert 'taskNavigation: true' in nav
assert 'settingsTaskRail' in nav
assert 'SettingsMaterialPreset.taskRailColor' in nav
assert 'property var searchAliases: ({})' in nav
assert 'page.settingsTaskNavigator = root' in nav
assert 'property bool useAbyssPillShape: true' in array
assert 'useAbyssPillShape: root.useAbyssPillShape' in array
assert 'waveFace: !root.abyssTaskNavigation && root.useAbyssPillShape' in button
assert 'root.taskNavigation && Config.options?.panelFamily === "abyss"' in array
assert 'property var settingsTaskNavigator: null' in page

# Presentation ownership is intentionally unchanged: Abyss still embeds the
# mature Settings card in its connected liquid body rather than spawning a
# detached replacement window.
assert 'parent: root.embeddedHost ?? nativeHost.item?.contentItem ?? null' in overlay
assert 'embeddedHost:' in embedded or 'embeddedHost' in embedded

print("PASS: shared sculpted task rail stays in the existing Settings host; Waffle and ordinary controls retain their style")
