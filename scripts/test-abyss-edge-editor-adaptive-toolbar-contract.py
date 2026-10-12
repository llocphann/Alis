#!/usr/bin/env python3
from pathlib import Path
import re, subprocess

root = Path(__file__).resolve().parents[1]
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
positions = (root / "modules/abyss/settings/AbyssPositionSettings.qml").read_text()

for needle in [
    "if (root.editingPopups)",
    "edge === previewBody.edge",
    "previewBody.joinedEdge",
    "onPreviewPositionChanged: root.scheduleToolbarRelocation()",
    "onPreviewKindChanged: root.scheduleToolbarRelocation()",
    "id: toolbarScroll",
    "id:editFineControls",
    "compactVertical:!root.toolbarWideControls",
]:
    assert needle in editor, needle

assert "Math.min(820,root.width*.55" not in editor
assert "property bool compactVertical: false" in positions
assert "columns:root.compactVertical ? 1 : 2" in positions
assert "columns:root.compactVertical ? 1 : 3" in positions
# The editor has one visible IPC kind picker; output scope joins the tabs.
assert 'objectName:"abyssEditorIpcKind"' in editor
assert 'objectName:"abyssEditorIpcOutput"' in editor
assert 'showKindSelector:false' in editor and 'showOutputSelector:false' in editor
assert 'compactIpcEditor:true' in editor
assert 'visible:root.showKindSelector || root.showOutputSelector' in positions
assert 'visible:root.showKindSelector' in positions
assert 'visible:root.showOutputSelector' in positions
assert positions.count('202*Appearance.fontSizeScale') == 4
assert 'ipcOutputRegion' in editor and 'ipcOutputRegion,edgeRegion' in editor
assert 'selectionRegion' not in editor
# First row stays two aligned groups on horizontal Edges:
# left: Modules / IPC tabs; right: output dropdown + This output only.
head=editor.split('id: editorModeHeader',1)[1].split('id:ipcKindChoice',1)[0]
assert 'objectName: "abyssEditorModeHeader"' in editor
assert 'columns: width >= 500*Appearance.fontSizeScale ? 2 : 1' in head
assert 'objectName: "abyssEditorModeTabs"' in head
assert 'objectName: "abyssEditorOutputScope"' in head
assert head.index('objectName:"abyssEditorModulesMode"') < head.index('objectName:"abyssEditorIpcMode"')
assert head.index('objectName: "abyssEditorOutputScope"') < head.index('id:ipcOutputChoice') < head.index('objectName:"abyssEditorOutputOnly"')
assert 'Layout.alignment: Qt.AlignRight | Qt.AlignVCenter' in head
assert 'visible:true' in head.split('id:ipcOutputChoice',1)[1]
assert 'visible:root.editingPopups' in editor.split('id:ipcKindChoice',1)[1].split('AbyssPositionSettings {',1)[0]
assert editor.count('id:ipcOutputChoice') == 1
assert editor.count('id:ipcKindChoice') == 1
assert editor.count('text:"This output only"') == 1
assert 'visible: !root.compactIpcEditor' in positions.split('SettingsNote {')[-1]

assert 'Layout.preferredWidth:116*Appearance.fontSizeScale' in editor

fine=editor[editor.index("id:editFineControls"):]
fine_columns=re.search(r"\bcolumns:\s*([\s\S]+?)\n\s*columnSpacing:",fine)
assert fine_columns, "two-column controls must expose a responsive layout"

# The first row, Modules/IPC with shared output scope, is unchanged.
# Below it: two content columns with a short divider, no leading dropdown icons.
left=editor[editor.index('id:moduleEditorColumn'):editor.index('objectName:"abyssEditorColumnDivider"')]
right=editor[editor.index('id:edgeEditorColumn'):]
selected=left[left.index('id:selectedModuleControls'):]
assert 'objectName:"abyssEditorModuleColumn"' in left
assert 'objectName:"abyssEditorEdgeColumn"' in right
assert 'id: palette' in left and 'objectName:"abyssModuleDropdown"' in left
assert 'id:edgeChoice' in right and 'objectName:"abyssEditingEdgeDropdown"' in right
assert 'onClicked:root.add(palette.currentValue)' in left
assert 'onActivated:root.editingEdge=currentText' in right
assert 'id:selection' not in editor and 'selectionRegion' not in editor
assert left.count('objectName:"abyssCompactSelectedModuleActions"') == 1
assert left.count('id:alignmentChoice') == 1
assert left.count('objectName:"abyssModulePositionLock"') == 1
assert left.count('objectName:"abyssSelectionEnabled"') == 1
assert left.count('objectName:"abyssSelectionRemove"') == 1
assert left.count('objectName:"abyssModuleRounding"') == 1
assert left.count('objectName:"abyssModuleCustomSizeToggle"') == 1
assert left.count('objectName:"abyssModuleJoinCorner"') == 1
assert 'AbyssCheckBox {' not in selected
assert 'onToggled:root.change("customSize",checked)' in selected
assert 'onToggled:root.change("joinCorner",checked)' in selected
assert right.count('id:scaleModulesRow') == 1
assert right.count('objectName:"abyssJoinNearbyModules"') == 1
assert right.count('objectName:"abyssRoundZeroCorners"') == 1
assert right.index('id:edgeChoice') < right.index('id:scaleModulesRow')
assert right.index('id:edgeChoice') < right.index('EditorIconHint {')
assert left.index('id: palette') < left.index('objectName:"abyssCompactSelectedModuleActions"')
assert left.index('objectName:"abyssCompactSelectedModuleActions"') < left.index('id:selectedModuleControls')
assert 'Layout.preferredHeight:64*Appearance.fontSizeScale' in editor
assert 'Layout.preferredWidth:1*Appearance.fontSizeScale' in editor
assert 'color:Qt.alpha(AbyssStyle.textColorMuted,.18)' in editor
assert 'visible:editFineControls.columns===3' in editor
assert editor.count('AbyssSlider {') == 6
assert editor.count('Layout.maximumWidth:root.editorActionSize') == 17

selected_columns=re.search(r"\bcolumns:\s*([^\n]+)",selected)
assert selected_columns and selected_columns.group(1).strip()=="1", "module-only fields stack vertically"
subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true])for(const fontSizeScale of [.7,1,1.5,2]) {
 for(const width of [0,250,400,460,599,649,650,700,900,1400,2200]) {
  const actual=vm.runInNewContext(process.argv[1],
      {root:{toolbarOnHorizontalEdge},width,Appearance:{fontSizeScale}});
  const expected=toolbarOnHorizontalEdge && width>=650*fontSizeScale?3:1;
  assert.equal(actual,expected);
 }
}
''',fine_columns.group(1)],check=True)

# A clamped viewport must scroll regardless of its physical Edge. Evaluate
# the real binding at fit/overflow boundaries, rather than its old spelling.
policy=re.search(r"\binteractive:\s*([^\n]+)",editor)
assert policy, "editor scroll policy is missing"
subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true]) {
 for(const contentHeight of [0,99,100,101,500]) {
  const height=100;
  const actual=vm.runInNewContext(process.argv[1],{
   root:{toolbarOnHorizontalEdge},contentHeight,height
  },{timeout:100});
  assert.equal(actual,contentHeight>height);
 }
}
''',policy.group(1)],check=True)

print("abyss editor adaptive side-toolbar contract: ok")
