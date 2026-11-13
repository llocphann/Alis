#!/usr/bin/env python3
from pathlib import Path
import re, subprocess

root = Path(__file__).resolve().parents[1]
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
positions = (root / "modules/abyss/settings/AbyssPositionSettings.qml").read_text()

dock = editor[editor.index("id: horizontalDock"):editor.index("id: toolbarColumn")]
fallback = editor[editor.index("id: toolbarColumn"):]

for needle in [
    "if (root.editingPopups)",
    "previewBody.targetRecord?.content",
    "Placement.toolbarEdgeForRects",
    "onPreviewPositionChanged: root.scheduleToolbarRelocation()",
    "onPreviewKindChanged: root.scheduleToolbarRelocation()",
    "id: toolbarScroll",
    "id: horizontalDock",
    "id: toolbarColumn",
    "id:editFineControls",
    "compactVertical:!root.toolbarWideControls",
    "parent:root.useHorizontalDock ? dockPopupsHost : toolbarColumn",
]:
    assert needle in editor, needle

assert "Math.min(820,root.width*.55" not in editor
assert "property bool compactVertical: false" in positions
assert "columns:root.compactVertical ? 1 : 2" in positions
assert 'id: ipcPositionSelectorRow' in positions
assert 'objectName: "abyssIpcSelectorsRow"' in positions
assert 'columns:root.compactIpcEditor' in positions
assert '? (root.compactVertical ? 1 : 4)' in positions
assert 'id:compactKindChoice' in positions
assert 'property alias compactKindCombo: compactKindChoice' in positions
for selector in ['compactKindChoice', 'edgeChoice', 'alignmentChoice']:
    block = positions.split('id:' + selector, 1)[1].split('onActivated:', 1)[0]
    assert 'Layout.preferredWidth:root.compactIpcEditor' in block, selector
    assert 'root.compactSideSelectorWidth' in block, selector
assert 'property bool compactSideToolbar: false' in positions
assert 'property Item compactCornerHost: null' in positions
assert 'root.compactCornerHost : ipcPositionSelectorRow' in positions
assert 'compactCornerHost:root.toolbarOnHorizontalEdge ? null : editorModeTabs' in fallback
assert 'font.pixelSize:root.compactHeaderActions' in fallback
assert 'root.headerActionSize' in editor
assert 'columns: root.toolbarOnHorizontalEdge' in fallback
assert 'objectName: "abyssEditorHeader"' in fallback
header = fallback.split('objectName: "abyssEditorHeader"', 1)[1].split('objectName:"abyssEditorHeaderActions"', 1)[0]
assert 'Layout.fillWidth:true;Layout.minimumWidth:0' in header
assert 'Layout.alignment:Qt.AlignVCenter' in header
assert 'elide:Text.ElideRight' in header
assert '10*Appearance.fontSizeScale' in header
assert 'toolbarScroll.width>=205*Appearance.fontSizeScale ? 2 : 1' not in editor
assert 'compactSideSelectorWidth:root.sideIpcSelectorWidth' in fallback
assert 'readonly property real sideIpcSelectorWidth: sideIpcDropdownWidth' in editor
assert '+ 6 * Appearance.fontSizeScale + headerActionSize' in editor
assert 'Layout.fillWidth: root.toolbarOnHorizontalEdge' in fallback
assert 'Layout.preferredWidth: root.toolbarOnHorizontalEdge' in fallback
assert 'Layout.maximumWidth: root.toolbarOnHorizontalEdge' in fallback
assert 'Qt.AlignLeft | Qt.AlignVCenter' in fallback
assert positions.count('root.compactSideSelectorWidth') == 6
assert 'property real compactSideSelectorWidth: 136*Appearance.fontSizeScale' in positions
assert 'Layout.preferredWidth:root.toolbarOnHorizontalEdge' in fallback
assert 'Math.max(116*Appearance.fontSizeScale,' in fallback
assert positions.count('popupMinimumWidth:root.compactSideToolbar') == 3
combo = (root / "modules/common/widgets/StyledComboBox.qml").read_text()
assert 'property real popupMinimumWidth: 0' in combo
assert 'width: Math.max(root.width,root.popupMinimumWidth)' in combo
assert 'root.popup.width - 8' in combo
# The editor has one visible IPC kind picker; output scope joins the tabs / dock Popups card.
assert 'objectName:"abyssEditorIpcKind"' in positions
assert 'objectName:"abyssIpcEdgeDropdown"' in positions
assert 'objectName:"abyssIpcAlignmentDropdown"' in positions
assert 'objectName: root.useHorizontalDock ? "abyssEditorIpcOutput" : ""' in dock
assert 'objectName:!root.useHorizontalDock ? "abyssEditorIpcOutput" : ""' in fallback
assert 'showKindSelector:false' in fallback and 'showOutputSelector:false' in fallback
assert 'compactIpcEditor:true' in fallback
assert 'visible:root.showKindSelector || root.showOutputSelector' in positions
assert 'visible:root.showKindSelector' in positions
assert 'visible:root.showOutputSelector' in positions
assert '202*Appearance.fontSizeScale' not in positions
assert 'root.compactSelectorWidth' not in positions
assert 'FontMetrics {' in positions
assert 'compactSelectorMetrics.advanceWidth(option.label)' in positions
for dimension in ['compactKindWidth', 'compactEdgeWidth', 'compactAlignmentWidth']:
    assert f'readonly property real {dimension}:' in positions
    assert positions.count('root.' + dimension) == 1
for dimension in ['compactKindTriggerWidth', 'compactEdgeTriggerWidth', 'compactAlignmentTriggerWidth']:
    assert f'readonly property real {dimension}:' in positions
    assert positions.count('root.' + dimension) == 2
assert 'Math.min(root.width-48,root.dockToolbarSpan)' in editor
assert 'Math.min(root.width-48,root.editingPopups' in editor
assert 'root.ipcToolbarSpan : root.moduleToolbarSpan' in editor
assert 'readonly property real dockToolbarSpan:' in editor
assert 'readonly property real moduleToolbarSpan:' in editor
assert 'moduleHeaderActions.implicitWidth + (270 + 2*10 + 1)*Appearance.fontSizeScale' in editor
assert 'readonly property real ipcSelectorSpan:' in editor
assert 'Math.max(450*Appearance.fontSizeScale,ipcSelectorSpan)' in editor
assert 'toolbarScroll.width >= (editingPopups' in editor
assert '? ipcSelectorSpan : 520*Appearance.fontSizeScale)' in editor
assert 'root.compactIpcEditor ? "Source edge" : "Follow source edge"' in positions
assert 'root.compactIpcEditor ? "Source position" : "Follow source position"' in positions
assert 'value:"source"' in positions
assert 'objectName:"abyssIpcJoinCornerToggle"' in positions
assert 'visible:!root.compactIpcEditor && Presentation.canJoin(root.kind)' in positions
assert 'onToggled:root.change("joinCorner",checked)' in positions
assert 'ipcOutputRegion' in editor and 'dockIpcOutputRegion' in editor
assert 'selectionRegion' not in editor

# Fallback Modes and scope remain paired; side scope is a uniform
# output dropdown plus the adjacent icon-only checked control.
head = fallback.split('id: editorModeHeader', 1)[1].split('AbyssPositionSettings {', 1)[0]
assert 'objectName: "abyssEditorModeHeader"' in fallback
assert 'columns: root.toolbarOnHorizontalEdge' in head
assert 'toolbarScroll.width >= 450*Appearance.fontSizeScale ? 2 : 1' in head
assert 'objectName: "abyssEditorModeTabs"' in head
assert 'objectName: "abyssEditorOutputScope"' in head
assert head.index('"abyssEditorModulesMode"') < head.index('"abyssEditorIpcMode"')
assert head.index('objectName: "abyssEditorOutputScope"') < head.index('id:ipcOutputChoice') < head.index('"abyssEditorOutputOnly"')
assert 'Layout.alignment: root.toolbarOnHorizontalEdge' in head
assert '(Qt.AlignRight | Qt.AlignVCenter)' in head
assert '(Qt.AlignLeft | Qt.AlignVCenter)' in head
assert 'columns:2' in head
assert 'Layout.alignment:root.toolbarOnHorizontalEdge' in head
assert 'visible:true' in head.split('id:ipcOutputChoice', 1)[1]
assert 'id:ipcKindChoice' not in editor
assert 'previewPositions.compactKindCombo.popup.contentItem' in editor
assert editor.count('id:ipcOutputChoice') == 1
assert editor.count('id: dockIpcOutputChoice') == 1
assert positions.count('id:compactKindChoice') == 1
assert 'function resetIpcPosition(): void' in editor
assert 'previewPositions.apply(null)' in editor
assert 'root.editingPopups ? root.resetIpcPosition() : root.reset()' in editor
assert fallback.count('text:"This output only"') == 1
scope = fallback.split('"abyssEditorOutputOnly"', 1)[1].split('AbyssPositionSettings {', 1)[0]
for needle in ['glyph:checked ? "check_box" : "check_box_outline_blank"',
               'compact:true;editorSquare:true;checkable:true',
               'checked:root.outputOnly', 'onToggled:root.outputOnly=checked']:
    assert needle in scope, needle
assert 'AbyssCheckBox {' not in fallback.split('objectName: "abyssEditorOutputScope"', 1)[1].split('AbyssPositionSettings {', 1)[0]
assert 'visible: !root.compactIpcEditor' in positions.split('SettingsNote {')[-1]

fine = fallback[fallback.index("id:editFineControls"):]
fine_two_column = re.search(r"readonly property bool useTwoColumns:\s*([\s\S]+?)\n\s*columns:useTwoColumns", fine)
assert fine_two_column, "the column decision must come from the outer toolbar viewport"
assert 'columns:useTwoColumns ? 3 : 1' in fine
assert fine.count('Layout.preferredWidth:editFineControls.useTwoColumns') == 2
assert fine.count('Math.max(0,(toolbarScroll.width-24*Appearance.fontSizeScale)/2)') == 0
assert 'Layout.fillWidth:!editFineControls.useTwoColumns' in fine
assert '? moduleHeaderActions.implicitWidth' in fine
assert '? 270*Appearance.fontSizeScale' in fine
assert 'editFineControls.width-24' not in fine
assert '&& width>=570*Appearance.fontSizeScale ? 3 : 1' not in fine

left = fallback[fallback.index('id:moduleEditorColumn'):fallback.index('objectName:"abyssEditorColumnDivider"')]
right = fallback[fallback.index('id:edgeEditorColumn'):]
selected = left[left.index('id:selectedModuleControls'):]
assert 'objectName:"abyssEditorModuleColumn"' in left
assert 'objectName:"abyssEditorEdgeColumn"' in right
assert 'id: palette' in left and '"abyssModuleDropdown"' in left
assert 'id:edgeChoice' in right and '"abyssEditingEdgeDropdown"' in right
assert 'onClicked:root.add(palette.currentValue)' in left
assert 'onActivated:root.editingEdge=currentText' in right
assert 'id:selection' not in editor and 'selectionRegion' not in editor
assert left.count('objectName:"abyssModuleHeaderActions"') == 1
assert left.count('"abyssModuleRoundingAction"') == 1
assert left.count('id:moduleRoundingRow') == 1
assert left.count('id:moduleCustomSizeRow') == 1
assert left.index('id: palette') < left.index('"abyssModulePositionLock"') < left.index('"abyssModuleJoinCorner"')
assert left.index('"abyssModuleJoinCorner"') < left.index('id:alignmentChoice')
assert left.count('id:alignmentChoice') == 1
assert left.count('"abyssModulePositionLock"') == 1
assert left.count('"abyssSelectionEnabled"') == 1
assert left.count('"abyssSelectionRemove"') == 1
assert left.count('"abyssModuleRounding"') == 1
assert left.count('"abyssModuleCustomSizeToggle"') == 1
assert left.count('"abyssModuleJoinCorner"') == 1
assert 'AbyssCheckBox {' not in selected
assert 'onToggled:root.change("customSize",checked)' in selected
join = left.split('"abyssModuleJoinCorner"', 1)[1].split('id:moduleAlignmentRow', 1)[0]
assert 'checked:root.targets.length>0 && root.targets.every(p=>p.joinCorner)' in join
assert 'onToggled:root.change("joinCorner",checked)' in join
assert right.count('id:scaleModulesRow') == 1
assert right.count('"abyssJoinNearbyModules"') == 1
assert right.count('"abyssRoundZeroCorners"') == 1
assert right.index('id:edgeChoice') < right.index('id:scaleModulesRow')
assert right.index('id:edgeChoice') < right.index('EditorIconHint {')
assert left.index('objectName:"abyssModuleHeaderActions"') < left.index('id:alignmentChoice') < left.index('id:selectedModuleControls')
assert 'Layout.preferredHeight:64*Appearance.fontSizeScale' in fallback
assert 'Layout.preferredWidth:1*Appearance.fontSizeScale' in fallback
assert 'color:Qt.alpha(AbyssStyle.textColorMuted,.18)' in fallback
assert 'visible:editFineControls.useTwoColumns' in fallback
assert fallback.count('AbyssSlider {') == 6
assert dock.count('AbyssSlider {') == 6
assert fallback.count('Layout.maximumWidth:root.editorActionSize') == 18
assert fallback.count('EditorIconHint {') == 3
assert 'id:edgeGapAndSizeRow' in right and 'id:edgeWidthRow' in right
assert right.index('"abyssJoinNearbyModules"') < right.index('id:edgeGapAndSizeRow')
assert right.index('"abyssRoundZeroCorners"') < right.index('id:scaleModulesRow')
assert 'AbyssCheckBox {' not in right
assert 'checkable:true' in right and 'onToggled:root.edgeRoundZeroCorners' in right
assert right.count('Layout.preferredWidth:110*Appearance.fontSizeScale') == 2
assert right.count('Layout.preferredWidth:190*Appearance.fontSizeScale') == 2
assert 'columns:root.toolbarOnHorizontalEdge' in right
assert 'edgeEditorColumn.width>=260*Appearance.fontSizeScale ? 2 : 1' in right
assert 'Math.min(width,Math.max(moduleHeaderActions.implicitWidth,' in left
assert '107*Appearance.fontSizeScale' in left
assert 'Layout.preferredWidth:moduleEditorColumn.controlsSpan' in left
assert 'Layout.maximumWidth:moduleEditorColumn.controlsSpan' in left
assert left.count('id:moduleRoundingRow') + left.count('id:moduleCustomSizeRow') == 2
assert right.count('id:edgeGapAndSizeRow') + right.count('id:edgeWidthRow') + right.count('id:scaleModulesRow') == 3

assert 'columns:1;rowSpacing:' in selected, "module appearance rows stack vertically"
subprocess.run(["node", "-e", r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true])for(const fontSizeScale of [.7,1,1.5,2]) {
 for(const width of [0,250,400,519,520,570,599,650,700,900,1400,2200]) {
  const two=vm.runInNewContext(process.argv[1],
      {root:{toolbarOnHorizontalEdge},toolbarScroll:{width},Appearance:{fontSizeScale}});
  const expected=toolbarOnHorizontalEdge && width>=520*fontSizeScale;
  assert.equal(two,expected);
  assert.equal(two?3:1,expected?3:1);
 }
}
''', fine_two_column.group(1)], check=True)

# A clamped viewport must scroll regardless of its physical Edge.
scroll_block = editor[editor.index("id: toolbarScroll"):editor.index("id: horizontalDock")]
policy = re.search(r"\binteractive:\s*([^\n]+)", scroll_block)
assert policy, "editor scroll policy is missing"
subprocess.run(["node", "-e", r'''
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
''', policy.group(1)], check=True)

# Evaluate horizontal dock mode boundary: horizontal Edge + wide (>= 748px) + sufficient height (>= 420px).
dock_cond = re.search(r"readonly property bool useHorizontalDock:\s*([\s\S]+?)\n\s*property string editorSection:", editor)
assert dock_cond, "useHorizontalDock binding missing"
subprocess.run(["node", "-e", r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const toolbarOnHorizontalEdge of [false,true]) {
 for(const scale of [1,1.25]) {
  for(const [width,height] of [[800,800],[850,480],[1000,360],[600,800],[420,440]]) {
   const actual=vm.runInNewContext(process.argv[1],{
    toolbarOnHorizontalEdge,width,height,Appearance:{fontSizeScale:scale}
   },{timeout:100});
   const expected=toolbarOnHorizontalEdge && (width-48)>=700*scale && height>=420*scale;
   assert.equal(actual,expected);
  }
 }
}
''', dock_cond.group(1)], check=True)

# Both side positions start at the same origin. The three IPC selectors
# terminate at the same right-hand coordinate as output selector + scope icon.
output_width = re.search(r'readonly property real sideIpcDropdownWidth:\s*([\s\S]+?)\n\s*readonly property real sideIpcSelectorWidth:', editor).group(1)
selector_width = re.search(r'readonly property real sideIpcSelectorWidth:\s*([\s\S]+?)\n\s*required property string outputName', editor).group(1)
subprocess.run(["node", "-e", r'''
const assert=require("node:assert/strict"),vm=require("node:vm");
for(const scale of [.75,1,1.25,1.5,1.75,2])for(const actionScale of [24,30]) {
 for(const viewport of [150,168,175,200,220,260,400]) {
  const action=actionScale*scale;
  const context={Appearance:{fontSizeScale:scale},toolbarScroll:{width:viewport},headerActionSize:action};
  const output=vm.runInNewContext(process.argv[1],context,{timeout:100});
  const ipc=vm.runInNewContext(process.argv[2],{...context,sideIpcDropdownWidth:output},{timeout:100});
  const left=12*scale;
  assert.ok(output>=0 && output<=136*scale);
  assert.ok(ipc<=viewport+1e-9,'scope exceeds its viewport');
  assert.ok(ipc>output);
  assert.equal(left+ipc,left+output+6*scale+action);
 }
}
''', output_width, selector_width], check=True)

print("abyss editor adaptive side-toolbar contract: ok")
