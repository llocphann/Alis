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
assert "root.activeGroupGesture={keys:targets.map(row=>Selection.key(row))" in ui
assert "root.isEventSelected(modelData) ? 2" in ui
assert "root.clickPlannerEvent(timedButton.modelData,mouse.modifiers)" in ui
assert "root.clickPlannerEvent(allDayButton.modelData,mouse.modifiers)" in ui
assert 'objectName:"plannerDeleteSelected"' in ui
assert "root.confirmOrDeleteSelected()" in ui
assert "event.key===Qt.Key_Delete || event.key===Qt.Key_Backspace" in ui
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
print("WEEKLY_PLANNER_MULTISELECT_CONTRACT_PASS: scroll preserved, select + handles + atomic delete/move")
