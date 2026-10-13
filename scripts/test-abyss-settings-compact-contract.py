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
# SET-R03: one brief Module hint replaces the original two paragraphs.
assert 'Arrange modules in Live Editor; use Custom size to override individual modules.' in s
assert 'Their media, resource, clock, tray and workspace settings remain shared.' not in s
assert 'Per-output sizes, snapping guides and start/center/end groups' not in s
assert 'Glass uses wallpaper, not window capture.' in s
# Surface-specific compact rows: one line = icon toggle + title + slider + value.
# Screen Edge depth is already owned by Edit Abyss Layout.
surface = s.split('title:"Surface";icon:"opacity";settingsTaskSection:"surface"', 1)[1] \
    .split('title:"Waves";icon:"waves";settingsTaskSection:"waves"', 1)[0]
assert 'text:"Screen Edge depth"' not in surface
assert 'configKey:"abyss.perimeter.thickness"' not in surface
assert "component CompactSurfaceRow: RowLayout" in s
assert "component CompactSurfacePercent: CompactSurfaceRow" in s
assert "StyledSlider {" in s
assert "onMoved: row.moved(value)" in s
assert 'Layout.preferredWidth: 202 * Appearance.fontSizeScale' in s
assert "Layout.preferredWidth: 58 * Appearance.fontSizeScale" in s
assert surface.count("CompactSurfacePercent {") == 7
assert surface.count("CompactSurfaceRow {") == 2
assert surface.count("ConfigSwitch {") == 0
assert surface.count("toggleIcon:") == 5
assert surface.count("onToggledByUser:") == 5
assert 'toggleObjectName:"abyssPanelOpacityFollow"' in surface
assert 'toggleObjectName:"abyssPanelBlurFollow"' in surface
for key in (
    "abyss.surface.opacity", "abyss.perimeter.radius",
    "abyss.surface.softness", "abyss.effects.blur.radius",
    "abyss.effects.blur.enabled", "abyss.content.opacity",
    "abyss.content.blurRadius", "abyss.effects.refraction.strength",
    "abyss.effects.refraction.enabled", "abyss.effects.surfaceHighlight",
    "abyss.effects.glow.strength",
):
    assert key in surface, key
print("quick action row + Abyss modules grid contract: ok")
