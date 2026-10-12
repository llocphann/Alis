#!/usr/bin/env python3
from pathlib import Path
import re, subprocess

root = Path(__file__).resolve().parents[1]
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
positions = (root / "modules/abyss/settings/AbyssPositionSettings.qml").read_text()

for needle in [
    'text: "Reset"; glyph: "restart_alt"; compact: true',
    'text: "Cancel"; glyph: "close"; compact: true',
    'text: "Done"; glyph: "check"',
    'buttonIcon:"widgets";buttonText:"Modules"',
    'buttonIcon:"open_in_new";buttonText:"IPC"',
    'compactActions:root.toolbarOnHorizontalEdge',
    'text:"Add module";glyph:"add"',
    'text:"Snap to guides";glyph:"grid_4x4"',
    'text:"Inherit surface";glyph:"layers"',
    'text:"Expand whole Edge";glyph:"fit_screen"',
    '? "visibility" : "visibility_off"',
    'text:"Remove";glyph:"delete"',
]:
    assert needle in editor, needle

# Immediate edit actions use compact icons on every Edge; tooltip/accessible
# names remain textual. Fine tuning is always available in the editor; there is no Options toggle.
for name in ["abyssLayoutUndo", "abyssLayoutDone", "abyssLayoutCancel", "abyssModulePositionLock", "abyssSelectionEnabled", "abyssSelectionRemove"]:
    block = editor[editor.index('objectName:"'+name+'"'):]
    block = block[:block.index("onClicked:")]
    assert re.search(r"compact:\s*true", block), name
assert 'readonly property bool expandedControls: true' in editor
assert 'objectName:"abyssEditorOptions"' not in editor
assert 'expandedControls=false' not in editor
assert 'objectName:"abyssEditorAdd"' not in editor
assert 'objectName:"abyssEditorConfirmAdd"' in editor
assert 'property bool compactActions: false' in positions
assert 'text:"Reset position";glyph:"restart_alt"' in positions
assert 'compact:root.compactActions' in positions
assert 'description:root.ipcOnly ? "Reset IPC position"' in positions
# Popup placement choices must not be exposed by this screen-edge editor.
match = re.search(r'allowedKinds:\s*\[([^]]+)\]', editor)
assert match, "Editor must constrain independently positioned indicators"
choices = re.findall(r'"([^"]+)"', match.group(1))
assert set(choices) == {"osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"}, choices
assert '"clock"' not in choices and '"notificationCenter"' not in choices

# Ambiguous scope/placement semantics intentionally stay textual.
for needle in [
    'text:"This output only"',
    'text:"Custom size"',
]:
    assert needle in editor, needle

# Exercise the real binding for both the unjoined and nearby-Edge states;
# whitespace or a multiline conditional must not change this contract.
label=re.search(r'text:\s*(root\.nearbyCorner\s*\?[\s\S]*?)\n\s*checked:',editor)
assert label, "join action must expose a contextual text binding"
subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const nearbyCorner of ['', 'top', 'right', 'bottom', 'left']) {
 const actual=vm.runInNewContext(process.argv[1],{root:{nearbyCorner}},{timeout:100});
 assert.equal(actual,nearbyCorner ? 'Connect to '+nearbyCorner+' corner' : 'Join nearby corner');
}
''',label.group(1)],check=True)

print("abyss editor compact action density contract: ok")

# Compact follow-up: centred icon-only buttons; density and semantic captions.
button = (root / "modules/abyss/looks/AbyssButton.qml").read_text()
assert 'anchors.centerIn: parent' in button
assert 'property bool editorSquare: false' in button
assert 'root.editorSquare && root.iconOnly' in button
assert 'component EditorIconHint: Item' in editor
assert len(re.findall(r'EditorIconHint\s*\{', editor)) == 5
assert editor.count('AbyssSlider {') == 6
assert editor.count('Layout.preferredWidth:root.editorSliderWidth') == 6
# Qt rejects two assignments to the same attached property in one QML item.
# All six compact sliders must keep exactly one minimum-width binding.
for line_number, line in enumerate(editor.splitlines(), 1):
    attached = re.findall(r'Layout[.][A-Za-z]+[ ]*:', line)
    assert len(attached) == len(set(attached)), (
        f"duplicate Layout property on line {line_number}"
    )
slider_rows = [
    line for line in editor.splitlines()
    if 'Layout.preferredWidth:root.editorSliderWidth' in line
]
assert len(slider_rows) == 6
assert all(
    row.count('Layout.minimumWidth:') == 1
    and 'Layout.minimumWidth:75*Appearance.fontSizeScale' in row
    for row in slider_rows
), "each compact slider needs one minimum width"
assert editor.count('editorSquare:true') >= 10
assert 'id:scaleModulesCaption' not in editor
assert 'id:scaleText' not in editor
assert 'description:"Scale modules:' in editor
assert 'root.edgeWidthAffectsModules[root.editingEdge]!==false' in editor
assert 'description:"Choose a module to add"' not in editor
assert 'Layout.preferredWidth:92*Appearance.fontSizeScale' in editor
assert 'Layout.preferredWidth:58*Appearance.fontSizeScale' in editor
assert 'readonly property real editorActionSize: 30 * Appearance.fontSizeScale' in editor
assert 'readonly property real editorSliderWidth: 158 * Appearance.fontSizeScale' in editor
assert editor.count('editorCompact:true') == 6
assert editor.count('Layout.preferredWidth:20*Appearance.fontSizeScale') == 5
assert editor.count('spacing:2') >= 10
assert 'root.editorSquare ? 17 * Appearance.fontSizeScale' in button
assert 'objectName:"abyssButtonCenteredGlyph"' in button
assert 'rightPadding:editorCompact ? 46*Appearance.fontSizeScale : 52' in (root / "modules/abyss/looks/AbyssSlider.qml").read_text()
assert 'objectName:"abyssEditorFineControls"' in editor
assert 'objectName:"abyssEditorSelectedFields"' in editor
assert 'columns:!root.toolbarOnHorizontalEdge || width<460*Appearance.fontSizeScale' in editor
assert 'columns:!root.toolbarOnHorizontalEdge || width<440*Appearance.fontSizeScale' in editor
assert editor.count('text:"This output only"') == 1
assert '750*Appearance.fontSizeScale' in editor
assert 'Ctrl/Shift-click select · Drag' not in editor

# Every Editor button has a bounded square hit rectangle, even in fill rows.
assert editor.count('Layout.maximumWidth:root.editorActionSize') == 15
assert editor.count('Layout.maximumHeight:root.editorActionSize') == 15


# The editor's fine-controls grid keeps nine stable slots in all states.
# Scale modules and Join nearby modules are icon-only with hover help;
# the controls do not disappear or reflow on the per-Edge scaling toggle.
for name in ["abyssScaleModulesToggle","abyssScaleModulesSlider","abyssJoinNearbyModules","abyssModuleRounding"]:
    assert editor.count('objectName:"'+name+'"') == 1, name
assert 'glyph:"join_inner"' in editor
assert 'id:scaleModulesRow' in editor
assert 'visible:root.edgeWidthAffectsModules[root.editingEdge]===false' not in editor
assert 'enabled:root.edgeWidthAffectsModules[root.editingEdge]===false' in editor
assert 'root.expandedControls ? 860 : 720' not in editor
assert editor.count('Layout.preferredWidth:root.editorSliderWidth') == 6
assert editor.count('editorSquare:true') >= 14
assert 'columnSpacing:4;rowSpacing:3' in editor
assert 'rowSpacing:3;columnSpacing:4' in editor
