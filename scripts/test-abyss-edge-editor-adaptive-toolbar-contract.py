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
    "Math.max(340,Math.min(460,root.width*.32))",
    "id: toolbarScroll",
    "columns:root.toolbarOnHorizontalEdge ? 5 : 1",
    "compactVertical:!root.toolbarOnHorizontalEdge",
]:
    assert needle in editor, needle

assert "Math.min(820,root.width*.55" not in editor
assert "property bool compactVertical: false" in positions
assert "columns:root.compactVertical ? 1 : 2" in positions
assert "columns:root.compactVertical ? 1 : 3" in positions

selected=editor[editor.index("id:selectedModuleControls"):]
columns=re.search(r"\bcolumns:\s*([^\n]+)",selected)
assert columns, "selected module controls need an adaptive grid"
subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true]) {
 for(const fontSizeScale of [.7,1,1.5,2]) {
  let previous=1;
  for(const width of [0,250,400,419,420,600,739,740,900,1099,1100,1400,2200]) {
   const actual=vm.runInNewContext(process.argv[1],{root:{toolbarOnHorizontalEdge},width,Appearance:{fontSizeScale}});
   assert([1,2,4,8].includes(actual));assert(actual>=previous);previous=actual;
   if(!toolbarOnHorizontalEdge)assert.equal(actual,1);
   if(width<420*fontSizeScale)assert.equal(actual,1);
  }
 }
}
''',columns.group(1)],check=True)

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
