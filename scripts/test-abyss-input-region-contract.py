#!/usr/bin/env python3
"""Guard Screen Edge hitboxes in the non-edit host against stale Region items.

This static contract supplements the native Abyss runtime test and must not be
misrepresented as proof of Niri compositor hover acceptance.
"""
from pathlib import Path
import json
import re
import subprocess
root = Path(__file__).resolve().parents[1]
bar = (root / "modules/abyss/bar/AbyssBar.qml").read_text()
perimeter = (root / "modules/abyss/AbyssPerimeter.qml").read_text()
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
runtime = (root / "scripts/test-abyss-runtime-contract.sh").read_text()
assert 'readonly property Region inputRegion: Region {' in bar
for token in (
    'module.visible && module.enabled',
    'inputRegion.changed()',
    'onXChanged: invalidateInputRegion()',
    'onYChanged: invalidateInputRegion()',
    'onEnabledChanged: invalidateInputRegion()',
    'root.inputRegions = root.inputRegions.concat([item.inputRegion])',
    'enabled: !root.editing',
):
    assert token in bar, f"missing explicit module pointer mask contract: {token}"
for signal in ('onWidthChanged', 'onHeightChanged'):
    assert re.search(signal+r':\s*(?:\{)?\s*invalidateInputRegion\(\)',bar), 'dimension changes must invalidate the actual mask'
assert 'Region { item: module }' not in bar
assert 'Region { regions: window.presented && field.ready && bar.visible ? bar.inputRegions : [] }' in perimeter
assert 'Region { regions: window.presented && field.ready && editor.visible ? editor.regions : [] }' in perimeter
assert 'Region { item:handle;' not in editor
for token in ('x:Math.floor(handle.x)', 'y:Math.floor(handle.y)',
              'Math.ceil(handle.x+handle.width)-Math.floor(handle.x)',
              'Math.ceil(handle.y+handle.height)-Math.floor(handle.y)',
              'root.editingPopups || !handle.visible ? 0', 'inputRegion.changed()',
              'onXChanged:invalidateRegion()', 'onYChanged:invalidateRegion()',
              'onWidthChanged:invalidateRegion()', 'onHeightChanged:invalidateRegion()'):
    assert token in editor, f'missing explicit animated editor hit-region contract: {token}'
assert 'normal-mode pointer region must track real rendered module geometry' in runtime
assert 'normal-mode input region must recover without recreating modules' in runtime
assert 'moving a module must refresh the already-bound input Region' in runtime

# Execute the real QML bindings. Unified launchers intentionally use the
# painted icon, while ordinary modules retain their full outward-rounded box.
# Literal checks for the old full-box spelling miss this distinction.
region = re.search(r'readonly property Region inputRegion: Region \{(.*?)\n\s*\}',
                   bar, re.S).group(1)
expressions = {}
for key, following in (('x', 'y'), ('y', 'width'), ('width', 'height')):
    expressions[key] = re.search(r'\b' + key + r':\s*(.*?)\n\s*' + following + r':',
                                 region, re.S).group(1)
expressions['height'] = re.search(r'\bheight:\s*(.*)', region, re.S).group(1)
for name, kind, following in (
    ('unifiedEdgeLauncher', 'bool', 'readonly property bool moduleIconHitOnly'),
    ('moduleIconHitOnly', 'bool', 'readonly property real moduleIconHitSize'),
    ('moduleIconHitSize', 'real', '// Unified launchers'),
):
    expressions[name] = re.search(r'readonly property ' + kind + ' ' + name
        + r':\s*(.*?)\n\s*' + re.escape(following), bar, re.S).group(1)
node = r'''
const assert = require('node:assert/strict');
const expressions = JSON.parse(process.argv[1]);
const bindings = Object.fromEntries(Object.entries(expressions).map(([key, expr]) =>
    [key, new Function('module', 'Appearance', 'x', 'y', 'return (' + expr + ');')]));
let checks = 0;
for (const kind of ['clock', 'resources', 'notesTimers', 'notificationActivity'])
for (const [width, height] of [[80, 32], [32, 80], [18.5, 27.25]])
for (const [x, y] of [[0, 0], [16.35, 72.65], [-4.2, .8]])
for (const font of [.75, 1, 1.5, 2])
for (const contentScale of [.6, 1, 1.8])
for (const visible of [false, true])
for (const enabled of [false, true])
for (const showIcon of [false, true]) {
    const module = {kind, x, y, width, height, visible, enabled, showIcon, contentScale};
    const appearance = {fontSizeScale: font};
    for (const key of ['unifiedEdgeLauncher', 'moduleIconHitOnly', 'moduleIconHitSize'])
        module[key] = bindings[key](module, appearance);
    const actual = {};
    actual.x = bindings.x(module, appearance);
    actual.y = bindings.y(module, appearance);
    actual.width = bindings.width(module, appearance, actual.x, actual.y);
    actual.height = bindings.height(module, appearance, actual.x, actual.y);
    const unified = ['notesTimers', 'notificationActivity'].includes(kind);
    // The rendered face is a centered 30px glyph scaled by the feature loader.
    const diameter = Math.max(1, Math.min(30 * font * contentScale, width, height));
    const painted = unified
        ? [x + (width-diameter)/2, y + (height-diameter)/2, diameter, diameter]
        : [x, y, width, height];
    const accepts = visible && enabled && (!unified || showIcon);
    assert.ok(Object.values(actual).every(Number.isInteger));
    if (accepts) {
        assert.deepEqual(actual, {
            x: Math.floor(painted[0]), y: Math.floor(painted[1]),
            width: Math.ceil(painted[0]+painted[2])-Math.floor(painted[0]),
            height: Math.ceil(painted[1]+painted[3])-Math.floor(painted[1])
        }, JSON.stringify(module));
        assert.ok(actual.x <= painted[0] && actual.x + actual.width >= painted[0]+painted[2]);
        assert.ok(actual.y <= painted[1] && actual.y + actual.height >= painted[1]+painted[3]);
        assert.ok(painted[0] - actual.x < 1 && painted[1] - actual.y < 1);
    } else assert.deepEqual([actual.width, actual.height], [0, 0], JSON.stringify(module));
    checks++;
}
console.log('ABYSS_MODULE_POINTER_REGION_BINDINGS_PASS', checks,
    'ordinary/icon-only, fractional, visibility and disabled cases');
'''
subprocess.run(['node', '-e', node, json.dumps(expressions)], check=True, timeout=15)
print('ABYSS_MODULE_POINTER_REGION_SOURCE_PASS dynamic geometry/edit mask boundaries')
