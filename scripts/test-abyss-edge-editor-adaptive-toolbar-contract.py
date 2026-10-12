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

fine=editor[editor.index("id:editFineControls"):]
fine_columns=re.search(r"\bcolumns:\s*([\s\S]+?)\n\s*columnSpacing:",fine)
assert fine_columns, "fine controls must expose adaptive columns"
# Dense horizontal layout: the fine controls occupy a complete 3-by-3
# grid, while the per-module selected fields consume one complete 3-cell row.
# Moving the selector and action strip does not alter any QML IDs or signals.
fine_start=editor.index("id:editFineControls")
selected_start=editor.index("id:selectedModuleControls")
fine_segment=editor[fine_start:selected_start]
selected_segment=editor[selected_start:]
assert fine_segment.count('id:scaleModulesRow') == 1
assert fine_segment.count('objectName:"abyssJoinNearbyModules"') == 1
assert fine_segment.index('id:scaleModulesRow') < fine_segment.index('objectName:"abyssJoinNearbyModules"') < fine_segment.index('objectName:"abyssModuleRounding"')
assert fine_segment.count('objectName:"abyssCompactSelectedModuleActions"') == 1
assert fine_segment.count('id:selection') == 1
assert fine_segment.count('objectName:"abyssModulePositionLock"') == 1
assert fine_segment.count('objectName:"abyssSelectionEnabled"') == 1
assert fine_segment.count('objectName:"abyssSelectionRemove"') == 1
assert selected_segment.count('id:selection') == 0
assert selected_segment.count('id:alignmentChoice') == 1
assert selected_segment.count('text:"Custom size"') == 1
assert selected_segment.count('objectName:"abyssModuleJoinCorner"') == 1
assert 'Layout.preferredWidth:120*Appearance.fontSizeScale' in fine_segment
assert 'Layout.preferredWidth:190*Appearance.fontSizeScale' in selected_segment
assert editor.count('AbyssSlider {') == 6
assert editor.count('Layout.maximumWidth:root.editorActionSize') == 15

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
