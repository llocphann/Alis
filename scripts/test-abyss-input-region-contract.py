#!/usr/bin/env python3
"""Guard Screen Edge hitboxes in the non-edit host against stale Region items.

This static contract supplements the native Abyss runtime test and must not be
misrepresented as proof of Niri compositor hover acceptance.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
bar = (root / "modules/abyss/bar/AbyssBar.qml").read_text()
perimeter = (root / "modules/abyss/AbyssPerimeter.qml").read_text()
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
runtime = (root / "scripts/test-abyss-runtime-contract.sh").read_text()
assert 'readonly property Region inputRegion: Region {' in bar
for token in (
    'x: Math.floor(module.x)', 'y: Math.floor(module.y)',
    'Math.ceil(module.x + module.width) - Math.floor(module.x)',
    'Math.ceil(module.y + module.height) - Math.floor(module.y)',
    'module.visible && module.enabled',
    'inputRegion.changed()',
    'onXChanged: invalidateInputRegion()',
    'onYChanged: invalidateInputRegion()',
    'onEnabledChanged: invalidateInputRegion()',
    'root.inputRegions = root.inputRegions.concat([item.inputRegion])',
    'enabled: !root.editing',
):
    assert token in bar, f"missing explicit module pointer mask contract: {token}"
import re
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
print('ABYSS_MODULE_POINTER_REGION_SOURCE_PASS dynamic geometry/edit mask boundaries')
