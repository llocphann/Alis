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
assert fine_columns, "fine controls must expose adaptive columns"
# A single add-module palette remains. Existing modules are selected by
# clicking/dragging their Screen Edge handles, not by a duplicate dropdown.
# All module actions keep their object names and handlers after regrouping.
fine_start=editor.index("id:editFineControls")
selected_start=editor.index("id:selectedModuleControls")
fine_segment=editor[fine_start:selected_start]
selected_segment=editor[selected_start:]
assert 'id: palette' in fine_segment
assert 'onClicked:root.add(palette.currentValue)' in fine_segment
assert 'id:selection' not in editor
assert 'selectionRegion' not in editor
assert fine_segment.count('objectName:"abyssCompactSelectedModuleActions"') == 1
assert fine_segment.count('id:alignmentChoice') == 1
assert fine_segment.count('objectName:"abyssModulePositionLock"') == 1
assert fine_segment.count('objectName:"abyssSelectionEnabled"') == 1
assert fine_segment.count('objectName:"abyssSelectionRemove"') == 1
assert fine_segment.count('id:scaleModulesRow') == 1
assert fine_segment.count('objectName:"abyssJoinNearbyModules"') == 1
assert selected_segment.count('objectName:"abyssModuleRounding"') == 1
assert selected_segment.count('objectName:"abyssModuleCustomSizeToggle"') == 1
assert selected_segment.count('objectName:"abyssModuleJoinCorner"') == 1
assert 'AbyssCheckBox {' not in selected_segment
assert 'onToggled:root.change("customSize",checked)' in selected_segment
assert 'onToggled:root.change("joinCorner",checked)' in selected_segment
assert 'checkable:true' in selected_segment
assert fine_segment.index('id: palette') < fine_segment.index('objectName:"abyssCompactSelectedModuleActions"') < fine_segment.index('id:alignmentChoice')
assert fine_segment.index('id:edgeChoice') < fine_segment.index('id:scaleModulesRow')
assert selected_segment.index('objectName:"abyssModuleRounding"') < selected_segment.index('objectName:"abyssModuleCustomSizeToggle"') < selected_segment.index('objectName:"abyssModuleJoinCorner"')
assert editor.count('AbyssSlider {') == 6
assert editor.count('Layout.maximumWidth:root.editorActionSize') == 17

selected=editor[editor.index("id:selectedModuleControls"):]
columns=re.search(r"\bcolumns:\s*([\s\S]+?)\n\s*rowSpacing:",selected)
assert columns, "selected module controls need an adaptive grid"
subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true]) {
 for(const fontSizeScale of [.7,1,1.5,2]) {
  let previous=1;
  for(const width of [0,250,400,419,420,600,739,740,900,1099,1100,1400,2200]) {
   const actual=vm.runInNewContext(process.argv[1],{root:{toolbarOnHorizontalEdge},width,Appearance:{fontSizeScale}});
   const expected=!toolbarOnHorizontalEdge || width<440*fontSizeScale
       ? 1 : width>=700*fontSizeScale ? 3 : 2;
   assert([1,2,3].includes(actual));assert.equal(actual,expected);
   assert(actual>=previous);previous=actual;
  }
 }
}
''',columns.group(1)],check=True)

subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true])for(const fontSizeScale of [.7,1,1.5,2]) {
 let previous=1;
 for(const width of [0,250,400,460,600,699,700,900,1400]) {
  const actual=vm.runInNewContext(process.argv[1],{root:{toolbarOnHorizontalEdge},width,Appearance:{fontSizeScale}});
  const expected=!toolbarOnHorizontalEdge||width<460*fontSizeScale ? 1
     : width>=700*fontSizeScale ? 3 : 2;
  assert.equal(actual,expected);assert(actual>=previous);previous=actual;
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
