#!/usr/bin/env python3
"""Exercise the actual family policy, including disabled-panel persistence."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
policy = (root / "modules/common/PanelFamilyPolicy.js").read_text()
program = policy + r"""
const assert = require('node:assert/strict');
assert.equal(normalize('garbage'), 'abyss');
assert.equal(normalize('abyss'), 'abyss');
assert.equal(normalize('ii'), 'abyss');
let family = 'abyss';
for (let i = 0; i < 60; i++) {
    family = next(family);
    assert.equal(family, ['waffle', 'abyss'][i % 2]);
}
assert.equal(new Set(abyssPanels).size, abyssPanels.length);
for (const index of [16,17,22,23,29]) {
    assert.deepEqual(settingsRoute('abyss',index,''),{pageIndex:index,section:''},'mature stable page indices keep their meaning');
}
for (const [section,pageIndex] of [['waves',32],['spectrum',32],['popups',33],['bar',34],['dock',22],['sidebars',23]]) {
    assert.deepEqual(settingsRoute('abyss',2,section),{pageIndex,section});
    assert.deepEqual(settingsRoute('waffle',2,section),{pageIndex:2,section});
}
assert.deepEqual(settingsRoute('abyss',10,'panels'),{pageIndex:10,section:'panels'});
assert.deepEqual(settingsRoute('abyss',10,'abyss'),{pageIndex:2,section:'surface'});
for (const section of ['modules','Modules','bar modules',' Bar modules ']) {
    assert.deepEqual(settingsRoute('abyss',10,section),{pageIndex:34,section:'modules'});
    assert.deepEqual(settingsRoute('waffle',10,section),{pageIndex:10,section});
}
for (const section of ['panels','terminal','interface','Shell Modules','unknown'])
    assert.deepEqual(settingsRoute('abyss',10,section),{pageIndex:10,section});
let result = ensure('abyss', abyssPanels, ['iiLock'], ['iiCheatsheet'], ['ii']);
assert(result.enabled.includes('abyssPerimeter'));
assert(!result.enabled.includes('iiCheatsheet')); // shared disabled preference
result.enabled = result.enabled.filter(id => id !== 'abyssDock');
result = ensure('abyss', abyssPanels, result.enabled, result.known, result.visited);
assert(!result.enabled.includes('abyssDock')); // survives repeat family visit
result = ensure('abyss', abyssPanels.concat(['abyssNew']), result.enabled, result.known, result.visited);
assert(result.enabled.includes('abyssNew')); // update migration
"""
subprocess.run(["node", "-e", program], check=True)

screen_time = (root / "services/ScreenTime.qml").read_text()
tracking = screen_time.split("readonly property bool enabled:", 1)[1].split("\n    property", 1)[0].strip()
subprocess.run(["node", "-e", """
const assert = require('node:assert/strict');
const Config = {options:{sidebar:{screenTime:{enable:false}},enabledPanels:['iiScreenCorners','abyssNotificationCenter']}};
function tracks() { return """ + tracking + """; }
for (const family of ['ii','waffle','abyss']) {
    Config.options.panelFamily = family;
    assert.equal(tracks(), family !== 'waffle');
    Config.options.sidebar.screenTime.enable = true; assert(tracks());
    Config.options.sidebar.screenTime.enable = false;
}
Config.options.panelFamily = 'ii'; Config.options.enabledPanels = []; assert(!tracks());
"""], check=True)

# Execute the real settings applicability function rather than mirroring it.
registry = (root / "modules/settings/SettingsPageRegistry.qml").read_text()
applicability = registry.split("function isPageApplicable(index: int): bool {", 1)[1].split("\n    }", 1)[0]
subprocess.run(["node", "-e", """
const assert = require('node:assert/strict');
const pages = Array(38).fill({});
for (const i of [18,19,20,21,27,28,30,31,35,36]) pages[i] = null;
const root = {pages, barPageIndex: 2, abyssFamily: false, waffleFamily: false,
    isHiddenLegacyIndex: i => [18,19,21,27,28,30,31,36].includes(i)};
function applicable(index) {""" + applicability + """}
for (const family of ['ii','waffle','abyss']) {
    root.abyssFamily = family === 'abyss'; root.waffleFamily = family === 'waffle';
    assert(applicable(1)); assert(applicable(10)); // shared System/Modules routes
    assert(!applicable(-1)); assert(!applicable(20)); assert(!applicable(35)); assert(!applicable(36)); assert(!applicable(18));
    assert.equal(applicable(2), family !== 'waffle');
    assert.equal(applicable(11), family === 'waffle');
    assert.equal(applicable(16), family !== 'waffle');
    assert.equal(applicable(29), family !== 'waffle');
    assert.equal(applicable(32), family === 'abyss');
}
"""], check=True)

# Exercise the production output-selection expression with hotplug/stale names.
selector = (root / "modules/abyss/settings/AbyssOutputSelector.qml").read_text()
effective = selector.split("readonly property var effective: ", 1)[1].split("\n", 1)[0]
subprocess.run(["node", "-e", """
const assert = require('node:assert/strict');
function resolve(selected, connected) { return """ + effective + """; }
assert.deepEqual(resolve([], ['A','B']), ['A','B']);
assert.deepEqual(resolve(['gone'], ['A','B']), ['A','B']);
assert.deepEqual(resolve(['B','gone'], ['A','B']), ['B']);
assert.deepEqual(resolve(['B'], ['A']), ['A']);
assert.deepEqual(resolve([], []), []);
"""], check=True)
shell = (root / "shell.qml").read_text()
for name in ("ii", "waffle", "abyss"):
    assert f'{name}CriticalHostLoader' in shell
    assert f'{name}DeferredHostLoader' in shell
assert 'root.activePanelFamily === "ii"' in shell
assert 'root.activePanelFamily === "abyss"' in shell
assert json.loads((root / "defaults/config.json").read_text())["panelFamily"] == "abyss"
for file in (root / "modules/abyss").rglob("*.qml"):
    assert 'target: "panelFamily"' not in file.read_text()
for target in ("osd", "osdVolume", "osdInput"):
    assert shell.count(f'target: "{target}"') == 1
    for family_dir in ("abyss", "waffle", "onScreenDisplay"):
        for file in (root / "modules" / family_dir).rglob("*.qml"):
            assert f'target: "{target}"' not in file.read_text(), file
transition = (root / "modules/abyss/AbyssFamilyTransition.qml").read_text()
assert 'mask: Region {}' in transition
assert 'WlrKeyboardFocus.None' in transition
assert 'repeat: false' in transition
print("ok - family cycle/migration/isolation, shared IPC, settings routes and output selection")
