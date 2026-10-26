#!/usr/bin/env python3
"""Regression contract for public Material-only Themes settings."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "modules" / "settings" / "SettingsPageRegistry.qml"
REGISTRY_DATA = ROOT / "modules" / "settings" / "SettingsPageRegistryData.qml"
THEMES = ROOT / "modules" / "settings" / "ThemesConfig.qml"
QMLDIR = ROOT / "modules" / "settings" / "qmldir"
WAFFLE_THEMES = ROOT / "modules" / "waffle" / "settings" / "pages" / "WThemesPage.qml"
WELCOME = ROOT / "welcome.qml"
GLOBAL_ACTIONS = ROOT / "services" / "GlobalActions.qml"
MONITOR_VISIBILITY = ROOT / "modules" / "settings" / "MonitorVisibilityConfig.qml"


def require(text: str, token: str, source: str) -> None:
    if token not in text:
        raise AssertionError(
            f"{source} is missing required Material-only settings token: {token!r}"
        )


def forbid(text: str, token: str, source: str) -> None:
    if token in text:
        raise AssertionError(
            f"{source} still contains retired Global Style UI/routing: {token!r}"
        )


def main() -> None:
    registry = REGISTRY.read_text(encoding="utf-8")
    registry_data = REGISTRY_DATA.read_text(encoding="utf-8")
    themes = THEMES.read_text(encoding="utf-8")
    qmldir = QMLDIR.read_text(encoding="utf-8")
    waffle_themes = WAFFLE_THEMES.read_text(encoding="utf-8")
    welcome = WELCOME.read_text(encoding="utf-8")
    global_actions = GLOBAL_ACTIONS.read_text(encoding="utf-8")
    monitor_visibility = MONITOR_VISIBILITY.read_text(encoding="utf-8")

    for token in (
        "themesPageIndex",
        "ThemesConfigMaterial",
    ):
        forbid(registry, token, "SettingsPageRegistry.qml")
    for token in (
        'component: "modules/settings/ThemesConfig.qml"',
        'desc: Translation.tr("Material colors, typography and motion")',
    ):
        require(registry_data, token, "SettingsPageRegistryData.qml")

    for token in (
        "retiredGlobalStyleKeywords",
        "isRetiredGlobalStyleEntry",
        ".filter(entry => !root.isRetiredGlobalStyleEntry(entry))",
    ):
        forbid(registry, token, "SettingsPageRegistry.qml")

    for token in (
        'summary: Translation.tr("Colors · typography · motion · advanced")',
        '{ displayName: Translation.tr("Colors"), icon: "palette", value: "colors" }',
        '{ displayName: Translation.tr("Type"), icon: "text_format", value: "type" }',
        '{ displayName: Translation.tr("Motion"), icon: "animation", value: "motion" }',
        '{ displayName: Translation.tr("Advanced"), icon: "construction", value: "advanced" }',
    ):
        require(themes, token, "ThemesConfig.qml")

    for token in (
        'value: "style"',
        'settingsTaskSection: "style"',
        'Translation.tr("Global Style")',
        "ThemeService.setGlobalStyle(",
        "AuroraStyleEditor.qml",
        "AngelStyleEditor.qml",
        "RegaliaStyleEditor.qml",
        "ZzzStyleEditor.qml",
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.inirEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
    ):
        forbid(themes, token, "ThemesConfig.qml")

    forbid(
        registry_data,
        'section: Translation.tr("Global Style")',
        "SettingsPageRegistryData.qml",
    )

    for token in (
        "ThemeService.normalizeGlobalStyle()",
        'if (activeSection === "style")',
        'activeSection = "colors"',
    ):
        require(themes, token, "ThemesConfig.qml")

    require(qmldir, "ThemesConfig 1.0 ThemesConfig.qml", "qmldir")
    forbid(qmldir, "ThemesConfigMaterial", "qmldir")
    if (ROOT / "modules" / "settings" / "ThemesConfigMaterial.qml").exists():
        raise AssertionError("retired ThemesConfigMaterial facade must stay absent")

    for token in (
        "id: globalStyleCard",
        'title: Translation.tr("Global Style")',
        'description: Translation.tr("Choose the visual language used across the shell")',
        "ThemeService.setGlobalStyle(",
    ):
        forbid(waffle_themes, token, "WThemesPage.qml")

    for token in (
        "Config.options?.appearance?.globalStyle",
        'Config.setNestedValue("appearance.globalStyle"',
        'Translation.tr("More experimental styles remain available in Settings.")',
    ):
        forbid(welcome, token, "welcome.qml")

    for token in (
        "function applyGlobalStyle(",
        'id: "style-',
        "ThemeService.setGlobalStyle(",
    ):
        forbid(global_actions, token, "GlobalActions.qml")

    for token in (
        "Appearance.inirEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.zzzEverywhere",
        "Appearance.cookieEverywhere",
    ):
        forbid(monitor_visibility, token, "MonitorVisibilityConfig.qml")
    for token in (
        "color: Appearance.colors.colLayer1",
        "border.width: 1",
        "border.color: SettingsMaterialPreset.groupBorderColor",
    ):
        require(monitor_visibility, token, "MonitorVisibilityConfig.qml")

    print("Material-only public Themes settings contract: PASS")


if __name__ == "__main__":
    main()
