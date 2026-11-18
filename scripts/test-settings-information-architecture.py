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
        first_label = "Abyss & Bar" if family == "abyss" else "Bar & Shell"
        assert labels == [
            first_label, "Appearance", "Panels & Dock", "Display & Windows", "System & Power", "Integrations", "Applications", "Tools & Shortcuts"
        ], labels
        page_indices = [index for group in groups for index in group["pages"]]
        assert len(page_indices) == len(set(page_indices)), "duplicate default page"
        if family == "abyss":
            excluded = {0, 5, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36}
            expected = set(range(40)) - excluded
        else:
            excluded = {0, 5, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21, 27, 28, 29}
            expected = (set(range(30)) - excluded) | {37, 38, 39}
        assert set(page_indices) == expected
        if family == "abyss":
            assert next(group for group in groups if group["label"] == "Abyss & Bar")["pages"] == [2, 33, 37, 24]
        assert next(group for group in groups if group["label"] == "Panels & Dock")["pages"] == [22, 23, 10, 11]
        assert next(group for group in groups if group["label"] == "Display & Windows")["pages"] == [12]

    nav_js = read("modules/settings/SettingsNavigation.js")
    nav_driver = nav_js + r"""
const assert = require("assert");
assert.strictEqual(SCHEMA_VERSION, 14);
const defaults = [
    { label: "Abyss & Bar", pages: [2, 33, 37, 24] },
    { label: "Appearance", pages: [4, 3, 25] },
    { label: "Panels & Dock", pages: [22, 23, 10, 11] },
    { label: "Display & Windows", pages: [12] },
    { label: "System & Power", pages: [1, 7] },
    { label: "Integrations", pages: [38] },
    { label: "Applications", pages: [39] },
    { label: "Tools & Shortcuts", pages: [6, 9] }
];
const retired = [0, 5, 8, 13, 14, 15, 16, 17, 18, 19, 20, 21, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36];

// Pre-v14 saved state with "Abyss" label, retired 14/15/16, 33 & 10/11 in Display & Windows
const rawV13 = JSON.stringify({
    version: 13,
    groups: [
        { label: "Abyss", pages: [2, 37, 24] },
        { label: "Appearance", pages: [4, 3, 25] },
        { label: "Panels & Dock", pages: [22, 23, 16] },
        { label: "Display & Windows", pages: [15, 33, 12, 14, 10, 11] },
        { label: "System & Power", pages: [1, 7] },
        { label: "Integrations", pages: [38] },
        { label: "Applications", pages: [39] },
        { label: "Tools & Shortcuts", pages: [6, 9] }
    ],
    hidden: [7, 14, 15, 16],
    names: { "12": "My Displays" }
});
const resV13 = arrange(rawV13, defaults, 40, [0, 5, 8, 13, 17, 18, 19, 20, 21, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36]);
assert.strictEqual(resV13.version, 14);
const groupByLabel = (res, lbl) => res.groups.find(g => g.label === lbl);
assert.deepStrictEqual(groupByLabel(resV13, "Display & Windows").pages, [12]);
assert.deepStrictEqual(groupByLabel(resV13, "Abyss").pages, [2, 33, 37, 24]);
assert.deepStrictEqual(groupByLabel(resV13, "Panels & Dock").pages, [22, 23, 10, 11]);
const allV13Pages = resV13.groups.flatMap(g => g.pages);
for (const r of [14, 15, 16]) {
    assert(!allV13Pages.includes(r), "Retired page " + r + " leaked into groups");
    assert(!resV13.hidden.includes(r), "Retired page " + r + " leaked into hidden");
}
assert.deepStrictEqual(resV13.hidden, [7]);
assert.deepStrictEqual(resV13.names, { "12": "My Displays" });

// Already migrated v14 custom arrangement stays intact
const rawV14Custom = JSON.stringify({
    version: 14,
    groups: [
        { label: "Abyss & Bar", pages: [2, 33, 37, 24] },
        { label: "Appearance", pages: [4, 3, 25] },
        { label: "Panels & Dock", pages: [22, 23, 11] },
        { label: "Display & Windows", pages: [12] },
        { label: "Custom Shell", pages: [10] },
        { label: "System & Power", pages: [1, 7] },
        { label: "Integrations", pages: [38] },
        { label: "Applications", pages: [39] },
        { label: "Tools & Shortcuts", pages: [6, 9] }
    ],
    hidden: []
});
const resV14 = arrange(rawV14Custom, defaults, 40, retired);
assert.strictEqual(resV14.version, 14);
assert.deepStrictEqual(groupByLabel(resV14, "Custom Shell").pages, [10]);
console.log("NAV_V14_OK");
"""
    nav_out = subprocess.check_output(["node", "-e", nav_driver], text=True)
    assert "NAV_V14_OK" in nav_out, nav_out

    require(arrangement, "layoutSchemaVersion: 13", "navigation migration")
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
    legacy_waffle_keys = ["quick","system","bar","wallpaper","themes","gowall","panels","modules","waffle-style","shortcuts","monitors","autostart","workspace-strip","ai","effects","shell-layout","power"]
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
    niri = read("modules/settings/NiriConfig.qml")
    tools = read("modules/settings/ToolsConfig.qml")
    for token in ('settingsTaskSection: "screen"',
                  'Config.setNestedValue("bar.bottom"',
                  'Config.setNestedValue("bar.vertical"'):
        forbid(quick, token, "Quick ownership")
    forbid(registry, "QuickConfigHugOnly", "retired Quick compatibility")
    forbid(tools, 'Config.setNestedValue("osd.', "moved OSD ownership to Popups")
    forbid(tools, "On-screen display (OSD)", "moved OSD card to Popups")
    require(data, "legacyHiddenIndexes: [0, 5, 8, 13, 14, 15, 16,", "retired Overview/Monitors/Dashboard indices 14, 15, 16")
    require(niri, 'Translation.tr("Displays & Monitors")', "merged Displays & Monitors tab")
    require(niri, 'Translation.tr("Windows & Tiling")', "Niri Windows & Tiling tab")
    require(niri, "embeddedArrangementOnly: true", "embedded Monitor Arrangement in NiriConfig")
    require(niri, 'Config.setNestedValue("display.primaryMonitor"', "primary monitor selector in NiriConfig")
    for retired_key in ("_retired-18", "_retired-19", "_retired-21",
                        "_retired-27", "_retired-28", "_retired-30",
                        "_retired-31", "_retired-35", "_retired-36"):
        forbid(data, retired_key, "retired registry page")
    forbid(data, 'key: "automation"', "retired Automation route")
    forbid(data, 'key: "arrange"', "duplicate Arrange route")
    forbid(data, "ArrangeConfig.qml", "duplicate Arrange component")
    forbid(data, "DesktopWidgetsConfig.qml", "retired Desktop Widgets component")
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
                         ("Sidebars", sidebars)):
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
