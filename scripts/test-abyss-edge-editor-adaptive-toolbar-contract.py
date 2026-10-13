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
assert 'id: ipcPositionSelectorRow' in positions
assert 'objectName: "abyssIpcSelectorsRow"' in positions
assert 'columns:root.compactIpcEditor' in positions
assert '? (root.compactVertical ? 1 : 4)' in positions
assert 'id:compactKindChoice' in positions
assert 'property alias compactKindCombo: compactKindChoice' in positions
assert positions.count('Layout.preferredWidth:root.compactIpcEditor') == 3
assert 'property bool compactSideToolbar: false' in positions
assert 'property Item compactCornerHost: null' in positions
assert 'root.compactCornerHost : ipcPositionSelectorRow' in positions
assert 'compactCornerHost:root.toolbarOnHorizontalEdge ? null : editorModeTabs' in editor
assert 'font.pixelSize:root.toolbarOnHorizontalEdge' in editor
assert 'root.headerActionSize' in editor
assert 'columns: root.toolbarOnHorizontalEdge' in editor
assert 'objectName: "abyssEditorHeader"' in editor
header=editor.split('objectName: "abyssEditorHeader"',1)[1].split('objectName:"abyssEditorHeaderActions"',1)[0]
assert 'Layout.fillWidth:true;Layout.minimumWidth:0' in header
assert 'Layout.alignment:Qt.AlignVCenter' in header
assert 'elide:Text.ElideRight' in header
assert '10*Appearance.fontSizeScale' in header
assert 'toolbarScroll.width>=205*Appearance.fontSizeScale ? 2 : 1' not in editor
assert 'compactSideSelectorWidth:root.sideIpcSelectorWidth' in editor
assert 'readonly property real sideIpcSelectorWidth: sideIpcDropdownWidth' in editor
assert '+ 6 * Appearance.fontSizeScale + headerActionSize' in editor
assert 'Layout.fillWidth: root.toolbarOnHorizontalEdge' in editor
assert 'Layout.preferredWidth: root.toolbarOnHorizontalEdge' in editor
assert 'Layout.maximumWidth: root.toolbarOnHorizontalEdge' in editor
assert 'Qt.AlignLeft | Qt.AlignVCenter' in editor
assert positions.count('root.compactSideSelectorWidth') == 6
assert 'property real compactSideSelectorWidth: 136*Appearance.fontSizeScale' in positions
assert 'Layout.preferredWidth:root.toolbarOnHorizontalEdge' in editor
assert 'Math.max(116*Appearance.fontSizeScale,' in editor
assert positions.count('popupMinimumWidth:root.compactSideToolbar') == 3
combo = (root / "modules/common/widgets/StyledComboBox.qml").read_text()
assert 'property real popupMinimumWidth: 0' in combo
assert 'width: Math.max(root.width,root.popupMinimumWidth)' in combo
assert 'width: root.popup.width - 8' in combo
# The editor has one visible IPC kind picker; output scope joins the tabs.
assert 'objectName:"abyssEditorIpcKind"' in positions
assert 'objectName:"abyssIpcEdgeDropdown"' in positions
assert 'objectName:"abyssIpcAlignmentDropdown"' in positions
assert 'objectName:"abyssEditorIpcOutput"' in editor
assert 'showKindSelector:false' in editor and 'showOutputSelector:false' in editor
assert 'compactIpcEditor:true' in editor
assert 'visible:root.showKindSelector || root.showOutputSelector' in positions
assert 'visible:root.showKindSelector' in positions
assert 'visible:root.showOutputSelector' in positions
assert '202*Appearance.fontSizeScale' not in positions
assert 'root.compactSelectorWidth' not in positions
assert 'FontMetrics {' in positions
assert 'compactSelectorMetrics.advanceWidth(option.label)' in positions
for dimension in ['compactKindWidth', 'compactEdgeWidth', 'compactAlignmentWidth']:
    assert f'readonly property real {dimension}:' in positions
    # The full model width is now only used by the wider popup. The trigger
    # instead follows the active label on side toolbars.
    assert positions.count('root.' + dimension) == 1
for dimension in ['compactKindTriggerWidth', 'compactEdgeTriggerWidth', 'compactAlignmentTriggerWidth']:
    assert f'readonly property real {dimension}:' in positions
    assert positions.count('root.' + dimension) == 2
assert 'Math.min(root.width-48,root.editingPopups' in editor
assert 'root.ipcToolbarSpan : root.moduleToolbarSpan' in editor
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
assert 'ipcOutputRegion' in editor and 'ipcOutputRegion,edgeRegion' in editor
assert 'selectionRegion' not in editor
# Horizontal Modes and scope remain paired; side scope is a uniform
# output dropdown plus the adjacent icon-only checked control.
head=editor.split('id: editorModeHeader',1)[1].split('AbyssPositionSettings {',1)[0]
assert 'objectName: "abyssEditorModeHeader"' in editor
assert 'columns: root.toolbarOnHorizontalEdge' in head
assert 'toolbarScroll.width >= 450*Appearance.fontSizeScale ? 2 : 1' in head
assert 'objectName: "abyssEditorModeTabs"' in head
assert 'objectName: "abyssEditorOutputScope"' in head
assert head.index('objectName:"abyssEditorModulesMode"') < head.index('objectName:"abyssEditorIpcMode"')
assert head.index('objectName: "abyssEditorOutputScope"') < head.index('id:ipcOutputChoice') < head.index('objectName:"abyssEditorOutputOnly"')
assert 'Layout.alignment: root.toolbarOnHorizontalEdge' in head
assert '(Qt.AlignRight | Qt.AlignVCenter)' in head
assert '(Qt.AlignLeft | Qt.AlignVCenter)' in head
assert 'columns:2' in head
assert 'Layout.alignment:root.toolbarOnHorizontalEdge' in head
assert 'visible:true' in head.split('id:ipcOutputChoice',1)[1]
assert 'id:ipcKindChoice' not in editor
assert 'previewPositions.compactKindCombo.popup.contentItem' in editor
assert editor.count('id:ipcOutputChoice') == 1
assert positions.count('id:compactKindChoice') == 1
assert 'function resetIpcPosition(): void' in editor
assert 'previewPositions.apply(null)' in editor
assert 'root.editingPopups ? root.resetIpcPosition() : root.reset()' in editor
assert editor.count('text:"This output only"') == 1
scope=editor.split('objectName:"abyssEditorOutputOnly"',1)[1].split('AbyssPositionSettings {',1)[0]
for needle in ['glyph:checked ? "check_box" : "check_box_outline_blank"',
               'compact:true;editorSquare:true;checkable:true',
               'checked:root.outputOnly','onToggled:root.outputOnly=checked']:
    assert needle in scope, needle
assert 'AbyssCheckBox {' not in editor.split('objectName: "abyssEditorOutputScope"',1)[1].split('AbyssPositionSettings {',1)[0]
assert 'visible: !root.compactIpcEditor' in positions.split('SettingsNote {')[-1]

assert 'Layout.preferredWidth:root.toolbarOnHorizontalEdge' in editor
assert 'Math.max(116*Appearance.fontSizeScale,' in editor

fine=editor[editor.index("id:editFineControls"):]
fine_two_column=re.search(r"readonly property bool useTwoColumns:\s*([\s\S]+?)\n\s*columns:useTwoColumns",fine)
assert fine_two_column, "the column decision must come from the outer toolbar viewport"
assert 'columns:useTwoColumns ? 3 : 1' in fine
assert fine.count('Layout.preferredWidth:editFineControls.useTwoColumns') == 2
assert fine.count('Math.max(0,(toolbarScroll.width-24*Appearance.fontSizeScale)/2)') == 0
assert 'Layout.fillWidth:!editFineControls.useTwoColumns' in fine
assert '? moduleHeaderActions.implicitWidth' in fine
assert '? 270*Appearance.fontSizeScale' in fine
assert 'editFineControls.width-24' not in fine
assert '&& width>=570*Appearance.fontSizeScale ? 3 : 1' not in fine

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
assert left.count('objectName:"abyssModuleHeaderActions"') == 1
assert left.count('objectName:"abyssModuleRoundingAction"') == 1
assert left.count('id:moduleRoundingRow') == 1
assert left.count('id:moduleCustomSizeRow') == 1
assert left.index('id: palette') < left.index('objectName:"abyssModulePositionLock"') < left.index('objectName:"abyssModuleJoinCorner"')
assert left.index('objectName:"abyssModuleJoinCorner"') < left.index('id:alignmentChoice')
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
assert left.index('objectName:"abyssModuleHeaderActions"') < left.index('id:alignmentChoice') < left.index('id:selectedModuleControls')
assert 'Layout.preferredHeight:64*Appearance.fontSizeScale' in editor
assert 'Layout.preferredWidth:1*Appearance.fontSizeScale' in editor
assert 'color:Qt.alpha(AbyssStyle.textColorMuted,.18)' in editor
assert 'visible:editFineControls.useTwoColumns' in editor
assert editor.count('AbyssSlider {') == 6
assert editor.count('Layout.maximumWidth:root.editorActionSize') == 18
assert editor.count('EditorIconHint {') == 3
assert 'id:edgeGapAndSizeRow' in right and 'id:edgeWidthRow' in right
assert right.index('objectName:"abyssJoinNearbyModules"') < right.index('id:edgeGapAndSizeRow')
assert right.index('objectName:"abyssRoundZeroCorners"') < right.index('id:scaleModulesRow')
assert 'AbyssCheckBox {' not in right
assert 'checkable:true' in right and 'onToggled:root.edgeRoundZeroCorners' in right
assert 'root.ipcToolbarSpan : root.moduleToolbarSpan' in editor
assert right.count('Layout.preferredWidth:110*Appearance.fontSizeScale') == 2
assert right.count('Layout.preferredWidth:190*Appearance.fontSizeScale') == 2
assert 'columns:root.toolbarOnHorizontalEdge' in right
assert 'edgeEditorColumn.width>=260*Appearance.fontSizeScale ? 2 : 1' in right
assert 'Math.min(width,moduleHeaderActions.implicitWidth)' in left
assert 'Layout.preferredWidth:moduleEditorColumn.controlsSpan' in left
assert 'Layout.maximumWidth:moduleEditorColumn.controlsSpan' in left
assert left.count('id:moduleRoundingRow') + left.count('id:moduleCustomSizeRow') == 2
assert right.count('id:edgeGapAndSizeRow') + right.count('id:edgeWidthRow') + right.count('id:scaleModulesRow') == 3

selected_columns=re.search(r"\bcolumns:\s*([^\n]+)",selected)
assert 'columns:1;rowSpacing:' in selected, "module appearance rows stack vertically"
subprocess.run(["node","-e",r'''
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
''',fine_two_column.group(1)],check=True)

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

# Both side positions start at the same origin. The three IPC selectors
# terminate at the same right-hand coordinate as output selector + scope icon.
subprocess.run(["node","-e",r'''
const assert=require("node:assert/strict");
for(const scale of [.75,1,1.25,1.75,2]) {
 for(const viewport of [175,200,220,260,400]) {
  const action=24*scale;
  const output=Math.min(136*scale,Math.max(86*scale,
    viewport-(action+10*scale)));
  const ipc=output+6*scale+action;
  const left=12*scale;
  assert.ok(ipc>output);
  assert.equal(left+ipc,left+output+6*scale+action);
 }
}
'''],check=True)

print("abyss editor adaptive side-toolbar contract: ok")
