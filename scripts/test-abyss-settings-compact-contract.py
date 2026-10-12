#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
q=(r/"modules/common/widgets/QuickActionSettingsEditor.qml").read_text()
s=(r/"modules/abyss/settings/AbyssStyleSettings.qml").read_text()
assert "Drag the dotted handle to reorder" not in q
assert "Layout.minimumWidth: 120" in q
assert "root.actionIcon(slot.actionId)" in q
assert "root.actionLabel(slot.actionId)" in q
assert "id: moduleToggleGrid" in s
assert "columns: width >= 980 ? 3 : (width >= 620 ? 2 : 1)" in s
assert "Module functionality settings" not in s
# SET-R04: the removed batch preset must not return. Independent settings
# remain editable; removing the button must not reset saved appearance state.
assert 'Use opaque Material appearance' not in s
assert 'onClicked:Config.setNestedValues({"abyss.surface.opacity":1' not in s
for config in (
    'configKey:"abyss.surface.opacity"',
    'configKey:"abyss.perimeter.radius"',
    'configKey:"abyss.effects.glow.strength"',
):
    assert config in s, config
for owner in ('objectName:"abyssPanelOpacity"', 'objectName:"abyssPanelBlur"'):
    assert owner in s, owner
assert 'Config.setNestedValue("abyss.effects.blur.enabled",checked)' in s
assert 'Config.setNestedValue("abyss.effects.refraction.enabled",checked)' in s
print("quick action row + Abyss modules grid contract: ok")
