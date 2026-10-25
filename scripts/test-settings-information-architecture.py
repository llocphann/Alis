#!/usr/bin/env python3
"""Regression contract for v11 intent-based Settings navigation and ownership."""

import re, json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(source: str, token: str, name: str) -> None:
    if token not in source:
        raise SystemExit(f"{name}: missing {token!r}")


def forbid(source: str, token: str, name: str) -> None:
    if token in source:
        raise SystemExit(f"{name}: duplicate/retired {token!r}")


def main() -> None:
    data = read("modules/settings/SettingsPageRegistryData.qml")
    registry = read("modules/settings/SettingsPageRegistry.qml")
    arrangement = read("modules/settings/SettingsArrangement.qml")
    group_block = data.split("readonly property var defaultCategories: [", 1)[1].split(
        "readonly property var _arrangement:", 1
    )[0]
    expression = "[" + group_block.strip()
    for family in ("abyss", "ii"):
        program = "const Config={options:{panelFamily:" + json.dumps(family) + "}};const Translation={tr:v=>v};console.log(JSON.stringify(" + expression + "))"
        groups = json.loads(subprocess.check_output(["node", "-e", program], text=True))
        groups = [group for group in groups if group["pages"]]
        labels = [group["label"] for group in groups]
        assert labels == (["Home", "Abyss"] if family == "abyss" else ["Home"]) + [
            "Appearance", "Desktop & Layout", "System", "Features & Services", "Advanced & Help"
        ], labels
        page_indices = [index for group in groups for index in group["pages"]]
        assert len(page_indices) == len(set(page_indices)), "duplicate default page"
        if family == "abyss":
            excluded = {18, 19, 20, 21, 26, 27, 28, 30, 31, 35, 36}
            expected = set(range(40)) - excluded
        else:
            excluded = {18, 19, 20, 21, 27, 28}
            expected = (set(range(30)) - excluded) | {38, 39}
        assert set(page_indices) == expected
        if family == "abyss":
            assert next(group for group in groups if group["label"] == "Abyss")["pages"] == [2,32,34,33,37,22,23,16]

    require(arrangement, "layoutSchemaVersion: 11", "navigation migration")
    require(arrangement, "const untouchedStock =", "navigation migration")
    require(arrangement, "const defaults = SettingsPageRegistry.defaultCategories", "navigation migration")
    require(arrangement, "sourceVersion < 8 && untouchedStock", "legacy customized navigation migration")
    require(arrangement, "grouped[owner.get(page)].pages.push(page)", "legacy relative order")
    require(arrangement, "root.save({ groups: migratedGroups, hidden: migratedHidden })",
            "custom navigation preservation")
    for token in ("function pageIndexForKey(", "function navigateToKey(",
                  "signal navigateRequested("):
        require(registry, token, "stable navigation")
    for path, slot in (
        ("settings.qml", "root.openSearchResult("),
        ("modules/settings/SettingsOverlay.qml", "root.openOverlaySearchResult("),
        ("modules/settings/SettingsFocus.qml", "root.openSearchResult("),
    ):
        source = read(path)
        require(source, "function onNavigateRequested(pageIndex, section)",
                path)
        require(source, slot, path)
        if path != "modules/settings/SettingsFocus.qml":
            require(source, "SettingsPageRegistry.navigationPageIndexes(", path)
            forbid(source, 'type: "header"', path)
            forbid(source, "toggleNavGroup(", path)
        else:
            require(source, "readonly property var visibleGroups:", path)
            require(source, "readonly property var currentGroup:", path)

    waffle = read("waffleSettings.qml")
    wcontent = read("modules/waffle/settings/WSettingsContent.qml")
    wkeys = re.findall(r'key: "([^"]+)"', waffle.split("property var pages: [", 1)[1].split(
        "property int currentPage:", 1
    )[0])
    legacy_waffle_keys = ["quick","system","bar","wallpaper","themes","gowall","panels","modules","waffle-style","shortcuts","about","monitors","autostart","workspace-strip","mascot","ai","effects","shell-layout","power"]
    assert wkeys == legacy_waffle_keys+["integrations","default-apps"], "Waffle historical page indices must not shift"
    assert len(wkeys) == len(set(wkeys)), "Waffle page keys must be unique"
    wgroups = wcontent.split("readonly property var navigationGroups: [", 1)[1].split(
        "readonly property var navigationItems:", 1
    )[0]
    grouped = re.findall(r'keys: \[([^\]]+)\]', wgroups)
    grouped_keys = [item for group in grouped for item in re.findall(r'"([^"]+)"', group)]
    assert set(grouped_keys) == set(wkeys) and len(grouped_keys) == len(wkeys), (
        "Waffle groups must include every page exactly once", grouped_keys
    )
    for token in ("model: root.navigationItems",
                  "root.currentPage = navEntry.modelData.pageIndex",
                  "function revealCurrentNavGroup()"):
        require(wcontent, token, "Waffle navigation")

    quick = read("modules/settings/QuickConfig.qml")
    modules = read("modules/settings/ModulesConfig.qml")
    system = read("modules/settings/GeneralConfigCore.qml")
    sidebars = read("modules/settings/SidebarsConfig.qml")
    services = read("modules/settings/ServicesConfig.qml")
    for token in ('settingsTaskSection: "screen"',
                  'Config.setNestedValue("bar.bottom"',
                  'Config.setNestedValue("bar.vertical"'):
        forbid(quick, token, "Quick ownership")
    forbid(registry, "QuickConfigHugOnly", "retired Quick compatibility")
    for retired_key in ("_retired-18", "_retired-19", "_retired-21",
                        "_retired-27", "_retired-28", "_retired-30",
                        "_retired-31", "_retired-35", "_retired-36"):
        forbid(data, retired_key, "retired registry page")
    forbid(data, 'key: "automation"', "retired Automation route")
    forbid(data, 'key: "arrange"', "duplicate Arrange route")
    forbid(data, "ArrangeConfig.qml", "duplicate Arrange component")
    for path, source, token in (
        ("Modules", modules, 'Config.setNestedValue("appearance.typography.sizeScale"'),
        ("System", system, 'Config.setNestedValue("policies.ai"'),
        ("Sidebars", sidebars, 'Config.setNestedValue("policies.ai"'),
        ("Sidebars", sidebars, 'Config.setNestedValue("policies.weeb"'),
        ("Services", services, 'Config.setNestedValue("bar.modules.weather"'),
    ):
        forbid(source, token, path)
    # SET-R01 retires visible pure redirects; canonical route/search APIs stay.
    for path, source in (("Quick", quick), ("Modules", modules),
                         ("System", system), ("Sidebars", sidebars)):
        forbid(source, "SettingsPageRegistry.navigateToKey(", path)
    require(services, 'SettingsPageRegistry.navigateToKey("integrations",section)',
            "legacy Services search delegation")
    require(data, "pageIndex: 4, pageName: root.pages[4].name,\n"
                  '            section: Translation.tr("Typography"),',
            "scale search destination")
    require(data, "pageIndex: 2, pageName: root.pages[2].name,\n"
                  '            section: Translation.tr("Appearance & Layout"),',
            "Bar search destination")
    print("Settings v11 information architecture, routing and ownership: OK")


if __name__ == "__main__":
    main()
