#!/usr/bin/env python3
"""Verify Niri Screen Edge hover layer does not flip as its popup opens.

This is a policy/ownership regression, NOT native Wayland pointer acceptance.
The expression under test is extracted from the actual Abyss PanelWindow and
evaluated by Node, so a refactor of its QML condition changes the test result.
"""
from pathlib import Path
import subprocess
import runpy

ROOT = Path(__file__).resolve().parents[1]
perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text()
classic = (ROOT / "modules/bar/Bar.qml").read_text()
bar = (ROOT / "modules/abyss/bar/AbyssBar.qml").read_text()
popup = (ROOT / "modules/bar/StyledPopup.qml").read_text()

layer_lines = [
    line.split("WlrLayershell.layer:", 1)[1].strip()
    for line in perimeter.splitlines()
    if "WlrLayershell.layer:" in line
    and "GlobalStates.settingsNativeDialogOpen" in line
]
assert len(layer_lines) == 1, "cannot uniquely locate Abyss output layer expression"
expression = layer_lines[0]
assert "CompositorService.isNiri" in expression, "Niri is still on the idle Top layer"
assert "liquid.popupsOpen" in expression, "popup layer policy changed unexpectedly"
assert "GlobalStates.settingsNativeDialogOpen ? WlrLayer.Bottom" in expression
assert "PolkitService.active ? WlrLayer.Top" in expression
assert "(CompositorService.isNiri && window.presented) || window.editorOpen" in expression
assert 'Region { regions: window.presented && field.ready && bar.visible ? bar.inputRegions : [] }' in perimeter
# The diagnostic same-shape mask identity toggle was introduced for cold Niri
# hover isolation; both branches must remain shaped and the ordinary case
# must still use nativeInputMask. This is not a full-window input mask.
assert ('mask: window.overviewDragging ? dragPassThrough : liquid.activeDialog ? dialogInputMask'
        ' : utility.open ? utilityInputMask : (window._probeMaskProxy ? probeProxyInputMask'
        ' : nativeInputMask)') in perimeter
assert 'readonly property Region probeProxyInputMask: Region {' in perimeter
assert 'regions: [nativeInputMask]' in perimeter
assert 'readonly property Region inputRegion: Region {' in bar
runpy.run_path(str(ROOT / 'scripts/test-abyss-input-region-contract.py'))
assert 'module.visible && module.enabled' in bar
assert 'Region { item: module }' not in bar
assert 'enabled: !root.editing' in bar
assert "CompositorService.isNiri" in classic and "WlrLayer.Overlay" in classic
assert 'root.moduleHoverActive || root._anchorHover.hovered || root.popupHovered' in popup

node = r"""
const assert = require('node:assert/strict');
const expr = process.argv[1];
const layer = new Function(
  'CompositorService','GlobalStates','PolkitService','window',
  'wallpaperBody','keyboardBody','Config','utility','liquid','toastBody',
  'dialogBody','companionExtension','settings','dashboardBody','controls',
  'WlrLayer', 'return ('+expr+');'
);
const options = {abyss:{},osk:{keepOnTop:false}};
function policy({
  niri=false, presented=true, editing=false, popup=false, polkit=false, dialog=false,
  wallpaper=false, utility=false
}={}) {
  return layer({isNiri:niri},{settingsNativeDialogOpen:dialog},
    {active:polkit},{editorOpen:editing,fullscreenCovered:false,presented},
    {open:wallpaper},{open:false},{options},
    {open:utility},{popupsOpen:popup},{open:false},
    {open:false},{editing:false},{open:false},{open:false},{open:false},
    {Bottom:'bottom',Top:'top',Overlay:'overlay'});
}
assert.equal(policy({niri:true}), 'overlay','normal Niri edge must accept hover before any popup');
assert.equal(policy({niri:true,presented:false}), 'top',
  'non-presented fullscreen/covered output must keep its old Top fallback');
assert.equal(policy({niri:true,popup:true}), 'overlay','popup opening must not remap the Niri edge');
assert.equal(policy({niri:true,editing:true}), 'overlay','editing and normal Niri share a steady layer');
assert.equal(policy({niri:true,wallpaper:true}), 'overlay');
assert.equal(policy({niri:true,utility:true}), 'overlay');
assert.equal(policy({niri:true,polkit:true}), 'top','Polkit override must remain higher priority');
assert.equal(policy({niri:true,dialog:true}), 'bottom','native settings override must remain higher priority');
assert.equal(policy({niri:true,polkit:true,dialog:true}), 'bottom','native settings wins as before');
assert.equal(policy(), 'top','non-Niri idle layer is unchanged');
assert.equal(policy({popup:true}), 'overlay','non-Niri popup can still promote to overlay');
assert.equal(policy({editing:true}), 'overlay','non-Niri editor still promotes to overlay');
assert.equal(policy({polkit:true}), 'top');
assert.equal(policy({dialog:true}), 'bottom');
console.log('PASS: 14 Niri/non-Niri exact-QML layer policy cases');
"""
result = subprocess.run(
    ["node", "-e", node, expression],
    capture_output=True, text=True, check=False, timeout=10,
)
if result.returncode:
    raise SystemExit(result.stdout + result.stderr or f"node exit={result.returncode}")
print(result.stdout.strip())
print("PASS: Abyss popup mask/anchor ownership preserved")
