#!/usr/bin/env python3
"""Weekly Planner hidden scrollbars, multi-select UI and atomic persistence contract."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
ui=(root/"modules/dashboard/DashboardWeeklyPlanner.qml").read_text()
policy=(root/"modules/dashboard/PlannerSelection.js").read_text()
gesture=(root/"modules/dashboard/PlannerGesture.js").read_text()
backend=(root/"services/Events.qml").read_text()
batch=(root/"services/EventBatchPolicy.js").read_text()
assert "flickableDirection:Flickable.HorizontalAndVerticalFlick" in ui
assert "ScrollBar.vertical: ScrollBar {policy:ScrollBar.AlwaysOff}" in ui
assert "ScrollBar.horizontal: ScrollBar {policy:ScrollBar.AlwaysOff}" in ui
assert "ScrollBar.AsNeeded" not in ui
assert 'import "PlannerSelection.js" as Selection' in ui
assert "Selection.choose(root.selectableEventRows" in ui
assert "root.selectedEventKeys=result.keys" in ui
assert ui.count("root.activeGroupGesture={keys:targets.map(row=>Selection.gestureKey(row))") == 2
assert 'includes(Selection.gestureKey(modelData))' in ui
assert 'function gestureKey(row)' in policy
assert "root.isEventSelected(modelData) ? 2" in ui
assert "root.clickPlannerEvent(timedButton.modelData,mouse.modifiers)" in ui
assert "root.clickPlannerEvent(allDayButton.modelData,mouse.modifiers)" in ui
# RippleButton derives from QtQuick.Controls.Button; pressX/pressY are FINAL.
# Redeclaring them makes the entire DashboardWeeklyPlanner type unavailable.
all_day=ui.split('delegate: RippleButton {',1)[1].split('StyledToolTip {text:parent.Accessible.name}',1)[0]
assert 'property real pressX:' not in all_day, "cannot override Button FINAL pressX"
assert 'property real pressY:' not in all_day, "cannot override Button FINAL pressY"
assert 'property real dragOriginContentX:0' in all_day
assert 'allDayButton.dragOriginContentX=point.x' in all_day
assert 'point.x-allDayButton.dragOriginContentX' in all_day
assert 'objectName:"plannerDeleteSelected"' in ui
assert "root.confirmOrDeleteSelected()" in ui
assert "event.key===Qt.Key_Delete || event.key===Qt.Key_Backspace" in ui
# A recurring Event is selectable for its own drag/resize, but is not
# authorized for destructive series batch deletion. The former disabled
# "Delete (1)" was misleading: make an explicit, clickable editor route.
assert 'enabled:root.selectedEventRows.length>0' in ui
assert 'label:!root.canDeleteSelection' in ui
assert '"Edit to delete ("+root.selectedEventRows.length+")"' in ui
assert 'function openSelectedRecurringEditor(): void {' in ui
assert 'root.selectedEventRows.find(row=>!Selection.canDelete(row))' in ui
assert 'root.editOccurrence(selected)' in ui
assert 'if (root.canDeleteSelection) root.confirmOrDeleteSelected()' in ui
assert 'else root.openSelectedRecurringEditor()' in ui
assert 'Deleting there may affect the full series; this button does not delete anything.' in ui
assert 'enabled:root.canDeleteSelection' not in ui
assert '&& root.selectedEventRows.every(row=>Selection.canDelete(row))' in ui
assert 'if (!root.canDeleteSelection) return' in ui
# Keep two-step confirmation and non-recurring-only atomic batch behavior.
assert 'root.localBackend.applyPlannerOccurrenceBatch(actions)' in ui
assert 'id:row.event.id,occurrenceIndex:row.occurrenceIndex,remove:true' in ui
assert "if (!root.deleteConfirmation) {root.deleteConfirmation=true;return}" in ui
assert "root.localBackend.applyPlannerOccurrenceBatch(actions)" in ui
assert "root.localBackend.applyPlannerOccurrenceBatch(changes)" in ui
assert 'function rangeForSelection(row,mode,dx,dy,dayWidth,hourHeight)' in gesture
assert "function ordered(days)" in policy and "function choose(rows,selected,anchor,target,ctrl,shift)" in policy
assert "function applyPlannerOccurrenceBatch(operations)" in backend
assert "const result=EventBatch.apply(root.list,operations,Occurrences)" in backend
batch_method=backend.split("function applyPlannerOccurrenceBatch(operations)",1)[1].split("function removeOccurrence",1)[0]
assert batch_method.count("root.saveToFile()")==1
assert "root.list=result.list" in batch_method
assert "function apply(events,operations,occurrences)" in batch
assert "const distinct=new Set" in batch
assert "if (distinct.size!==next.length) return null" in batch
# Qt's embedded QML JavaScript parser rejects object-rest/spread in
# imported service scripts. Node/V8 tests alone will not catch this.
assert "..." not in batch, "QML script parser rejects spread in EventBatchPolicy.js"
assert "..." not in policy, "QML script parser rejects spread in PlannerSelection.js"
assert "Object.assign({},slots[i]," in batch, "preserve slot metadata without object spread"
assert "(day.allDay || []).concat(day.timed || [])" in policy
assert "Array.from(new Set(merged))" in policy
print("WEEKLY_PLANNER_MULTISELECT_CONTRACT_PASS: scroll preserved, select + handles + atomic delete/move")
