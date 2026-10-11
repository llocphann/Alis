#!/usr/bin/env python3
"""Canonical ownership for Settings controls: one user-facing owner per option."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding="utf-8")
quick=read("modules/settings/QuickConfig.qml")
themes=read("modules/settings/ThemesConfig.qml")
wallpaper=read("modules/settings/BackgroundConfig.qml")
advanced=read("modules/settings/AdvancedConfig.qml")
interface=read("modules/settings/InterfaceConfig.qml")
modules=read("modules/settings/ModulesConfig.qml")
system=read("modules/settings/GeneralConfigCore.qml")
data=read("modules/settings/SettingsPageRegistryData.qml")

for token in (
    'Config.setNestedValue("appearance.palette.type"',
    'Config.setNestedValue("background.multiMonitor.enable"',
    'Config.setNestedValue("appearance.wallpaperTheming.useBackdropForColors"',
    'Config.setNestedValue("closeConfirm.enabled"',
):
    assert token not in quick, token

assert 'Config.setNestedValue("appearance.palette.type"' in themes
assert 'Config.setNestedValue("background.multiMonitor.enable"' in wallpaper
assert 'Config.setNestedValue("appearance.wallpaperTheming.useBackdropForColors"' in wallpaper
assert 'Config.setNestedValue("closeConfirm.enabled"' in system

for token in (
    'Config.setNestedValue("appearance.wallpaperTheming.enableTerminal"',
    'Config.setNestedValue("appearance.wallpaperTheming.terminalColorAdjustments.harmony"',
):
    assert token not in advanced, token
    assert token in themes, token

assert 'Config.setNestedValue("enabledPanels"' not in interface
assert 'Config.setNestedValue("enabledPanels"' in modules
assert "SettingsPageRegistry.navigateToKey(" not in interface

palette_search='''pageIndex: 4, pageName: root.pages[4].name,
            section: Translation.tr("Color Themes"),
            label: Translation.tr("Palette type")'''
assert palette_search in data
print("PASS: duplicate Settings controls have one canonical owner")
