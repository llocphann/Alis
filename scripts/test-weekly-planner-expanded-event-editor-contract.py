#!/usr/bin/env python3
"""Dashboard planner has a full form; Calendar Popup retains compact controls."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
planner=(r/"modules/dashboard/DashboardWeeklyPlanner.qml").read_text()
editor=(r/"modules/sidebarRight/events/EventsDialog.qml").read_text()
calendar=(r/"modules/sidebarRight/events/EventsWidget.qml").read_text()
todo=(r/"modules/dashboard/DashCard.qml").read_text()
assert 'plannerPresentation:true' in planner
assert 'embeddedPresentation:true' in planner
assert 'hideEmbeddedScrollBar:true' in planner
assert 'policy: root.hideEmbeddedScrollBar || root.plannerPresentation' in editor
assert 'embeddedBackgroundColor: {' in planner
assert 'AbyssStyle.contentLayer : Appearance.colors.colLayer1' in planner
assert 'AbyssStyle.contentLayer : Appearance.colors.colLayer1' in todo
assert 'property bool plannerPresentation: false' in editor
assert 'readonly property bool compactEditor: embeddedPresentation && !plannerPresentation' in editor
assert 'root.plannerPresentation ? 12 : Math.max(4,' in editor, "compact gaps remain"
assert 'readonly property real visibleItemHeight:' in editor
assert 'readonly property int visibleItemCount:' in editor
assert '(editorFlickable.height-visibleItemHeight)' in editor
assert 'Math.max(editorFlickable.height,root.plannerPage===0' in editor
assert 'responsive: root.plannerPresentation' in editor
assert 'width: root.plannerPresentation ? parent.width' in editor
assert 'root.plannerPresentation\n            ? Math.max(height, formColumn.implicitHeight)' in editor
assert 'contentHeight: root.plannerPresentation' in editor, "Planner fits the page and preserves genuine overflow"
assert 'visible: root.compactEditor' in editor, "Calendar deck remains compact"
assert 'visible: !root.compactEditor' in editor, "Planner shows full labelled form controls"
assert editor.count('activeLabelOnly: false') == 4, "All Planner choices display icon + text"
assert editor.count('wrapFullLabels: root.plannerPresentation') == 4, "Planner chips wrap at narrow widths"
choices=(r/"modules/common/widgets/ConfigSelectionArray.qml").read_text()
assert 'property bool activeLabelOnly: false' in choices, "opt-in only"
assert 'property bool wrapFullLabels: false' in choices, "Planner-only opt-in"
assert 'property bool centerWrappedRows: false' in choices
assert 'onPositioningComplete: if (root.centerWrappedRows)' in choices
assert editor.count('centerWrappedRows: root.plannerPresentation') == 4
assert 'spacing: root.wrapFullLabels ? 5 : 2' in choices
assert 'horizontalPadding: root.wrapFullLabels' in choices
assert 'enableImplicitWidthAnimation: !root.taskNavigation && !root.wrapFullLabels' in choices
assert 'buttonText: modelData.displayName' in choices
assert 'revealActiveLabelOnly: root.activeLabelOnly' in choices
assert 'property var revealedSelection: null' in choices
assert 'revealNextSelection.restart()' in choices
assert 'onTriggered: root.revealedSelection=root.currentValue' in choices
assert 'interval: 190' in choices
assert 'selectedLabelExpanded: root.activeLabelOnly' in choices
assert 'horizontalPadding: root.activeLabelOnly' in choices
assert 'maxTextWidth: root.taskNavigation' in choices
assert 'clip: root.activeLabelOnly' in choices
assert 'root.activeLabelOnly && !paletteButton.toggled' not in choices
reveal=(r/"modules/common/widgets/SelectionGroupButton.qml").read_text()
assert 'property bool selectedLabelExpanded: root.toggled' in reveal
assert 'readonly property bool labelExpanded: !root.revealActiveLabelOnly' in reveal
assert '|| root.selectedLabelExpanded' in reveal
assert 'clip: root.revealActiveLabelOnly' in reveal
assert 'clip: root.revealActiveLabelOnly' in reveal.split('contentItem: RowLayout {',1)[1]
assert 'NumberAnimation { duration: 190; easing.type: Easing.InOutCubic }' in reveal
assert 'root.labelExpanded' in reveal
assert 'visible: root.buttonText?.length > 0' in reveal
assert 'visible: opacity > 0' not in reveal.split('id: textItem',1)[0].split('implicitWidth: root.buttonText?.length > 0 && root.labelExpanded',1)[1]
assert 'Text.ElideNone : Text.ElideRight' in reveal
assert 'Math.min(textItem.implicitWidth, root.maxTextWidth) : 0' in reveal
assert 'Accessible.name: modelData.displayName' in choices
assert 'property date plannerViewMonth: new Date()' in editor
assert 'ObsidianMonthCalendar {' in editor
assert 'calendarCells: root.plannerCalendarCells' in editor
assert 'onDayActivated: (date,modifiers)=>root.choosePlannerDay(date,modifiers)' in editor
assert 'Layout.topMargin: root.plannerPresentation ? 10 : 0' in editor
assert 'visible: root.plannerPresentation' in editor
assert 'visible: root.isEditing && !root.embeddedPresentation' in editor
assert 'visible: root.embeddedPresentation && root.isEditing' in editor
assert 'visible: root.embeddedPresentation' in editor
assert 'visible: !root.embeddedPresentation' in editor
assert 'symbol: root.allDay ? "event_available" : "event_busy"' in editor
assert 'Layout.preferredWidth: root.compactEditor ? 30 : 36' in editor
assert 'Layout.preferredHeight: root.compactEditor ? 30 : 36' in editor
assert 'root.allDay = !root.allDay' in editor
assert 'symbol: "delete"' in editor
assert 'symbol: "close"' in editor
assert 'symbol: root.isEditing ? "check" : "add_task"' in editor
# Planner pages are in one clipped, animated viewport: form controls remain
# mounted so switching between details and options cannot destroy draft fields.
assert 'property int plannerPage: 0' in editor
assert 'function changePlannerPage(nextPage): void' in editor
assert 'editorFlickable.contentY=0' in editor
assert 'id: plannerPageHost' in editor
assert 'clip: root.plannerPresentation' in editor
assert 'id: plannerBasics' in editor
assert 'id: plannerOptions' in editor
assert editor.index('id: plannerBasics') < editor.index('id: basicInfoColumn')
assert editor.index('id: plannerOptions') < editor.index('text: Translation.tr("Repeat")')
assert 'id: plannerOptions' in editor and 'id: compactOptionDeck' in editor
assert 'x: root.plannerPresentation && root.plannerPage===1' in editor
assert 'x: root.plannerPresentation && root.plannerPage===0' in editor
assert 'objectName: "plannerEventPageNavigation"' in editor
assert 'visible: root.plannerPresentation' in editor
assert 'symbol: root.plannerPage===0 ? "arrow_forward" : "arrow_back"' in editor
assert 'onClicked: root.changePlannerPage(root.plannerPage===0 ? 1 : 0)' in editor
assert 'root.plannerPage = 0' in editor
assert editor.count('objectName: "plannerEventPageNavigation"')==1

# Page-two spacing is composed as four equal, subtle cards instead of one
# short top-aligned stack and a large empty area. Under reduced height the
# intrinsic content wins, so the page is still scrollable.
page_two=editor.split('id: plannerOptions',1)[1].split('} // plannerOptions',1)[0]
assert 'optionCardHeight: root.plannerPresentation' in page_two
assert 'Math.max(0,(editorFlickable.height-spacing*3-4)/4)' in page_two
assert 'spacing: root.plannerPresentation ? 7' in page_two
for kind in ('repeat','category','priority','reminder'):
    assert 'id: '+kind+'Card' in page_two
    assert 'id: '+kind+'Content' in page_two
    assert 'Math.max('+kind+'Content.implicitHeight + 12,' in page_two
assert page_two.count('visible: root.plannerPresentation') >= 8
assert page_two.count('radius: Appearance.rounding.large')==4
assert page_two.count('color: Appearance.colors.colLayer2')==4
assert page_two.count('activeLabelOnly: false')==4
assert page_two.count('wrapFullLabels: root.plannerPresentation')==4
assert page_two.count('ConfigSelectionArray {')==4, "Do not duplicate editable options"
assert 'currentValue: root.recurrence' in page_two
assert 'currentValue: root.eventCategory' in page_two
assert 'currentValue: root.eventPriority' in page_two
assert 'currentValue: root.reminderMinutes' in page_two
assert 'visible: !root.compactEditor && !root.plannerPresentation' in page_two, "Modal separators stay available"

# Narrow Planner footer: both corner action groups must sit inside equal
# 12 px gutters, not inherit WindowDialogButtonRow's -8 px modal overhang.
footer=editor.split('    WindowDialogButtonRow {',1)[1].split('        DialogButton {',1)[0]
assert 'Layout.fillWidth: true' in footer
assert 'Layout.leftMargin: root.plannerPresentation ? 12 : (root.compactEditor ? 6 : -8)' in footer
assert 'Layout.rightMargin: root.plannerPresentation ? 12 : (root.compactEditor ? 6 : -8)' in footer
assert 'Layout.topMargin: root.plannerPresentation ? 6 : 0' in footer
assert 'Layout.bottomMargin: root.plannerPresentation ? 12 : (root.compactEditor ? 2 : 0)' in footer
assert editor.count('Layout.preferredWidth: root.compactEditor ? 30 : 36') >= 3
assert editor.count('Layout.preferredHeight: root.compactEditor ? 30 : 36') >= 3
assert 'enabled: !root.allDay' in editor, "All-day and aligned Start/End share a planner row"
assert 'embeddedPresentation: true' in calendar and 'plannerPresentation:true' not in calendar, "Calendar untouched"
for kind,mouse in [('Start','topResizeMouse'),('End','bottomResizeMouse')]:
    marker='objectName:"plannerResize'+kind+'"'
    segment=planner.split(marker,1)[1].split('onCanceled:timedButton.cancelGesture()',1)[0]
    assert 'radius:3;color:"transparent"' in segment
    assert 'height:2' in segment and 'width:Math.min(28,parent.width*.3)' in segment
    assert 'opacity:'+mouse+'.containsMouse' in segment
    assert 'hoverEnabled:true' in segment
assert 'Qt.alpha(root.ink,.32)' not in planner.split('objectName:"plannerResizeStart"',1)[1].split('objectName:"plannerResizeEnd"',1)[0]

# Evaluate the actual QML centering algorithm using two independently
# wrapped rows. Other selectors must remain unchanged with opt-in disabled.
fn = choices.split("function centerWrappedOptionRows(): void {",1)[1].split(
    "onPositioningComplete:",1)[0]
assert "const delta=(root.width-(maxX-minX))/2-minX" in fn
subprocess.run(["node","-e",r'''
const assert=require("node:assert/strict"),vm=require("node:vm");
const raw=process.argv[1];
const source="function centerWrappedOptionRows() {"+raw;
for(const enabled of [false,true]) {
 const items=[
 {x:0,y:0,width:68,visible:true},{x:73,y:0,width:78,visible:true},
 {x:156,y:0,width:86,visible:true},{x:0,y:34,width:92,visible:true},
 {x:97,y:34,width:83,visible:true}
 ];
 const root={centerWrappedRows:enabled,width:280};
 const optionRepeater={count:items.length,itemAt:i=>items[i]};
 vm.runInNewContext(source+"; centerWrappedOptionRows()",{root,optionRepeater});
 if(enabled){
  for(const group of [items.slice(0,3),items.slice(3,5)]){
   const left=group[0].x,right=group[group.length-1].x+group[group.length-1].width;
   assert(Math.abs((left+right)/2-140)<0.0001);
  }
 }else{
  assert.equal(items[0].x,0);assert.equal(items[3].x,0);
 }
}
''',fn],check=True)
print("WEEKLY_PLANNER_EXPANDED_EDITOR_AND_RESIZE_HOVER_PASS")

# Multi-date is opt-in only for Planner Add Event; Recurrence is exclusive.
assert 'multiSelectedDates: root.plannerSelectedDateKeys' in editor
assert 'selectedDays.length>1 && root.recurrence!=="none"' in editor
assert 'root.resetPlannerDateSelection()' in editor
assert 'root.plannerSelectedCount>1' in editor
assert 'root._plannerPickingDate' in editor
