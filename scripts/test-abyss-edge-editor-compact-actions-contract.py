#!/usr/bin/env python3
from pathlib import Path
import re, subprocess

root = Path(__file__).resolve().parents[1]
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
positions = (root / "modules/abyss/settings/AbyssPositionSettings.qml").read_text()

dock = editor[editor.index("AbyssCustomizationDock {"):editor.index("id: toolbarColumn")]
fallback = editor[editor.index("id: toolbarColumn"):]

# 2-tier iNiR-adapted Abyss Layout Dock contract (horizontal Abyss Panel Mode)
for needle in [
    'id: horizontalDock',
    'AbyssCustomizationDock {',
    'objectName: root.useHorizontalDock ? "abyssEdgeEditorDock" : ""',
    'embeddedSurface: true',
    'key: "modules"',
    'label: Translation.tr("Modules")',
    'key: "edge"',
    'Translation.tr("Screen Edge")',
    'key: "popups"',
    'Translation.tr("Popups & Panels")',
    'undoObjectName: root.useHorizontalDock ? "abyssLayoutUndo" : ""',
    'searchObjectName: root.useHorizontalDock ? "abyssModuleSearchInput" : ""',
    'cancelObjectName: root.useHorizontalDock ? "abyssLayoutCancel" : ""',
    'doneObjectName: root.useHorizontalDock ? "abyssLayoutDone" : ""',
    'objectName: root.useHorizontalDock ? "abyssLayoutReset" : ""',
    'objectName: root.useHorizontalDock ? "abyssDockSnapToggle" : ""',
    'objectName: root.useHorizontalDock ? "abyssEditorOutputOnly" : ""',
    'objectName: root.useHorizontalDock ? "abyssModuleGallery" : ""',
    'delegate: AbyssCustomizationTile {',
    'objectName: "abyssModuleGalleryTile"',
    'separateBadgeClick: true',
    'objectName: root.useHorizontalDock ? "abyssDockModuleInspector" : ""',
    'objectName: root.useHorizontalDock ? "abyssEditingEdgeSelector" : ""',
    'id: dockPopupsHost',
]:
    assert needle in dock, needle

assert "palette.currentIndex = idx" in editor and "dockPalette.currentIndex = idx" in editor

# Compact fallback contract (!useHorizontalDock: vertical side edges & cramped viewports)
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
    assert needle in fallback, needle

# Immediate edit actions use compact icons on every fallback Edge; tooltip/accessible
# names remain textual. Fine tuning is always available in the editor; there is no Options toggle.
for name in ["abyssLayoutUndo", "abyssLayoutDone", "abyssLayoutCancel", "abyssModulePositionLock", "abyssSelectionEnabled", "abyssSelectionRemove"]:
    marker = 'objectName:!root.useHorizontalDock ? "' + name + '" : ""'
    assert marker in fallback, name
    block = fallback[fallback.index(marker):]
    block = block[:block.index("onClicked:")]
    assert re.search(r"compact:\s*true", block), name

# Every shared control objectName must be mutually gated between dock and compact fallback.
for shared in [
    "abyssLayoutUndo",
    "abyssLayoutReset",
    "abyssLayoutCancel",
    "abyssLayoutDone",
    "abyssEditorModulesMode",
    "abyssEditorIpcMode",
    "abyssEditorOutputOnly",
    "abyssEditorIpcOutput",
    "abyssModuleDropdown",
    "abyssEditorConfirmAdd",
    "abyssModulePositionDropdown",
    "abyssModuleRotate",
    "abyssModulePositionLock",
    "abyssSelectionEnabled",
    "abyssModuleJoinCorner",
    "abyssSelectionRemove",
    "abyssModuleCustomSizeToggle",
    "abyssModuleCustomSizeSlider",
    "abyssRoundZeroCorners",
    "abyssEdgeWidthSlider",
    "abyssScaleModulesToggle",
    "abyssEdgeGapSlider",
    "abyssEdgeSizeSlider",
    "abyssScaleModulesSlider",
    "abyssJoinNearbyModules",
    "abyssModuleRoundingAction",
    "abyssModuleRounding",
]:
    assert f'root.useHorizontalDock ? "{shared}" : ""' in dock, f"missing dock {shared}"
    assert f'!root.useHorizontalDock ? "{shared}" : ""' in fallback, f"missing fallback {shared}"

assert 'readonly property bool expandedControls: true' in editor
assert 'objectName:"abyssEditorOptions"' not in editor
assert 'expandedControls=false' not in editor
assert 'objectName:"abyssEditorAdd"' not in editor
assert 'property bool compactActions: false' in positions
assert 'text:"Reset position";glyph:"restart_alt"' in positions
assert 'visible:!root.compactIpcEditor' in positions
assert 'description: root.editingPopups ? "Reset selected IPC position" : "Reset layout draft"' in fallback
assert 'onClicked: root.editingPopups ? root.resetIpcPosition() : root.reset()' in editor
assert 'compact:root.compactActions' in positions
assert 'editorSquare:root.compactIpcEditor' in positions
assert 'objectName:"abyssEditorIpcPlacement"' in fallback
assert 'currentIndex:model.findIndex(option => option.value === (root.outputOnly ? root.outputName : ""))' in fallback
assert 'onActivated:root.outputOnly=currentValue!==""' in fallback
assert 'outputName:root.outputOnly ? root.outputName : ""' in fallback
assert 'description:root.ipcOnly ? "Reset IPC position"' in positions
assert 'objectName:"abyssIpcJoinCornerToggle"' in positions
assert 'compact:true;editorSquare:true;checkable:true' in positions
assert 'onToggled:root.change("joinCorner",checked)' in positions

# Popup placement choices must not be exposed by this screen-edge editor.
match = re.search(r'allowedKinds:\s*\[([^]]+)\]', editor)
assert match, "Editor must constrain independently positioned indicators"
choices = re.findall(r'"([^"]+)"', match.group(1))
assert set(choices) == {"osd", "volume", "brightness", "mic", "mediaOsd", "keyboardLayout", "voiceSearch"}, choices
assert '"clock"' not in choices and '"notificationCenter"' not in choices

# Ambiguous scope/placement semantics intentionally stay textual.
for needle in [
    'text:"This output only"',
    'text:"Custom size"',
]:
    assert needle in fallback, needle

# Exercise the real binding for both the unjoined and nearby-Edge states;
# whitespace or a multiline conditional must not change this contract.
label = re.search(r'text:\s*(root\.nearbyCorner\s*\?[\s\S]*?:\s*"Join nearby corner")', fallback)
assert label, "join action must expose a contextual text binding"
subprocess.run(["node", "-e", r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const nearbyCorner of ['', 'top', 'right', 'bottom', 'left']) {
 const actual=vm.runInNewContext(process.argv[1],{root:{nearbyCorner}},{timeout:100});
 assert.equal(actual,nearbyCorner ? 'Connect to '+nearbyCorner+' corner' : 'Join nearby corner');
}
''', label.group(1)], check=True)

print("abyss editor compact action density contract: ok")

# Compact follow-up: centred icon-only buttons; density and semantic captions.
button = (root / "modules/abyss/looks/AbyssButton.qml").read_text()
assert 'anchors.centerIn: parent' in button
assert 'property bool editorSquare: false' in button
assert 'root.editorSquare && root.iconOnly' in button
assert 'component EditorIconHint: Item' in editor
assert len(re.findall(r'EditorIconHint\s*\{', fallback)) == 3
assert 'objectName:!root.useHorizontalDock ? "abyssEditingEdgeDropdown" : ""' in fallback
# Dropdowns are their column headers and must not have a leading glyph.
edge_column = fallback[fallback.index('id:edgeEditorColumn'):]
assert edge_column.index('id:edgeChoice') < edge_column.index('EditorIconHint {')
assert fallback.count('AbyssSlider {') == 6
assert dock.count('AbyssSlider {') == 6
assert editor.count('Layout.preferredWidth:root.editorSliderWidth') == 0

# Qt rejects two assignments to the same attached property in one QML item.
for line_number, line in enumerate(editor.splitlines(), 1):
    attached = re.findall(r'Layout[.][A-Za-z]+[ ]*:', line)
    assert len(attached) == len(set(attached)), (
        f"duplicate Layout property on line {line_number}"
    )

# Six sliders in each mode keep a single minimum binding each; the fallback Module pair
# derives its maximum from the module action row rather than a 158px cap.
assert fallback.count('Layout.minimumWidth:75*Appearance.fontSizeScale') == 6
assert dock.count('Layout.minimumWidth: 75 * Appearance.fontSizeScale') == 6
assert fallback.count('Layout.preferredWidth:Math.max(75*Appearance.fontSizeScale,') == 2
assert fallback.count('moduleEditorColumn.controlsSpan-root.editorActionSize-2*Appearance.fontSizeScale)') == 4
assert editor.count('Layout.maximumWidth:root.editorSliderWidth') == 0
assert fallback.count('editorSquare:true') >= 10
assert 'id:scaleModulesCaption' not in editor
assert 'id:scaleText' not in editor
assert 'description:"Scale modules:' in fallback
assert 'root.edgeWidthAffectsModules[root.editingEdge]!==false' in fallback
assert 'description:"Choose a module to add"' not in editor
assert 'Layout.preferredWidth:92*Appearance.fontSizeScale' in fallback
assert 'readonly property real headerActionSize:' in editor
assert fallback.count('Layout.preferredWidth:root.headerActionSize;Layout.preferredHeight:root.headerActionSize') == 4
assert 'objectName:"abyssEditorHeaderActions"' in fallback
assert 'objectName:"abyssEditorTitle"' in fallback
assert 'Layout.preferredWidth:58*Appearance.fontSizeScale' in fallback
assert 'readonly property real editorActionSize: 30 * Appearance.fontSizeScale' in editor
assert 'readonly property real controlsSpan:Math.max(0,' in fallback
assert 'Math.min(width,Math.max(moduleHeaderActions.implicitWidth,' in fallback
assert '107*Appearance.fontSizeScale' in fallback
assert fallback.count('editorCompact:true') == 6
assert dock.count('editorCompact: true') == 6
assert fallback.count('Layout.preferredWidth:20*Appearance.fontSizeScale') == 3
module_actions = fallback.split('id:moduleHeaderActions', 1)[1].split('id:moduleAlignmentRow', 1)[0]
assert module_actions.count('columnSpacing:2') == 3
assert 'objectName:"abyssModuleSelectionActions"' in module_actions
assert 'root.editorSquare ? 17 * Appearance.fontSizeScale' in button
assert 'objectName:"abyssButtonCenteredGlyph"' in button
assert 'rightPadding:editorCompact ? 46*Appearance.fontSizeScale : 52' in (root / "modules/abyss/looks/AbyssSlider.qml").read_text()
assert 'objectName:"abyssEditorFineControls"' in fallback
assert 'objectName:"abyssEditorSelectedFields"' in fallback
assert 'columns:root.toolbarOnHorizontalEdge' in fallback
assert 'toolbarScroll.width>=520*Appearance.fontSizeScale' in fallback
assert 'columns:useTwoColumns ? 3 : 1' in fallback
assert 'Layout.preferredWidth:editFineControls.useTwoColumns' in fallback
assert 'editFineControls.width-24' not in editor
assert 'id:moduleEditorColumn' in fallback and 'id:edgeEditorColumn' in fallback
assert 'objectName:"abyssEditorColumnDivider"' in fallback
assert 'columns:1' in fallback[fallback.index('id:selectedModuleControls'):]
assert fallback.count('text:"This output only"') == 1
assert 'readonly property real dockToolbarSpan:' in editor
assert 'readonly property real moduleToolbarSpan:' in editor
assert 'readonly property real ipcToolbarSpan:' in editor
assert 'root.ipcToolbarSpan : root.moduleToolbarSpan' in editor
assert 'Ctrl/Shift-click select · Drag' not in editor

# Every fallback Editor button has a bounded square hit rectangle, even in fill rows.
assert fallback.count('Layout.maximumWidth:root.editorActionSize') == 18
assert fallback.count('Layout.maximumHeight:root.editorActionSize') == 18
for name, action in [('abyssModuleCustomSizeToggle', 'customSize'), ('abyssModuleJoinCorner', 'joinCorner')]:
    marker = 'objectName:!root.useHorizontalDock ? "' + name + '" : ""'
    part = fallback[fallback.index(marker):]
    part = part[:part.index('onToggled:') + len('onToggled:root.change("' + action + '",checked)')]
    assert 'compact:true;editorSquare:true;checkable:true' in part, name
    assert 'checked:' in part and 'enabled:' in part, name
    assert 'onToggled:root.change("' + action + '",checked)' in part, name
assert 'id:selection' not in editor and 'selectionRegion' not in editor

# Both fallback editor columns preserve their control IDs and reactive state.
for name in ["abyssScaleModulesToggle", "abyssScaleModulesSlider", "abyssJoinNearbyModules", "abyssModuleRounding"]:
    assert fallback.count('objectName:!root.useHorizontalDock ? "' + name + '" : ""') == 1, name
assert 'glyph:"join_inner"' in fallback
assert 'id:scaleModulesRow' in fallback
assert fallback.count('Layout.preferredWidth:110*Appearance.fontSizeScale') == 2
assert fallback.count('Layout.preferredWidth:190*Appearance.fontSizeScale') == 2
assert 'Layout.maximumWidth:135*Appearance.fontSizeScale' not in editor
assert 'objectName:"abyssEdgeGapAndSizeRow"' in fallback
assert 'edgeEditorColumn.width>=260*Appearance.fontSizeScale ? 2 : 1' in fallback
for name in ('abyssEdgeGapSlider', 'abyssEdgeSizeSlider', 'abyssEdgeWidthSlider'):
    assert fallback.count('objectName:!root.useHorizontalDock ? "' + name + '" : ""') == 1
assert 'Layout.preferredWidth:104*Appearance.fontSizeScale' in fallback
assert 'objectName:"abyssModuleHeaderActions"' in fallback
assert 'id:edgeGapAndSizeRow' in fallback
assert 'id:edgeWidthRow' in fallback
assert 'columns:1;rowSpacing:4*Appearance.fontSizeScale' in fallback
assert 'visible:root.edgeWidthAffectsModules[root.editingEdge]===false' not in editor
assert 'enabled:root.edgeWidthAffectsModules[root.editingEdge]===false' in fallback
assert 'root.expandedControls ? 860 : 720' not in editor
assert fallback.count('editorSquare:true') >= 14
assert 'columnSpacing:10*Appearance.fontSizeScale' in fallback
assert 'rowSpacing:6*Appearance.fontSizeScale' in fallback
assert 'spacing:4*Appearance.fontSizeScale' in fallback
assert fallback.count('objectName:!root.useHorizontalDock ? "abyssModuleDropdown" : ""') == 1
assert fallback.count('objectName:!root.useHorizontalDock ? "abyssEditingEdgeDropdown" : ""') == 1
