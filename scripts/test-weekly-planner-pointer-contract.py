#!/usr/bin/env python3
"""Source contract for exclusive Weekly Planner pointer handling.

Only native Niri input tests can confirm actual pointer delivery. This test
guards against the previous competing RippleButton.MouseArea/DragHandler path.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
qml = (root / "modules/dashboard/DashboardWeeklyPlanner.qml").read_text()
policy = (root / "modules/dashboard/PlannerGesture.js").read_text()
backend = (root / "services/Events.qml").read_text()
assert "model:dayColumn.modelData.timed" in qml
event = qml.split("model:dayColumn.modelData.timed", 1)[1].split(
    "visible:dayColumn.today && root.presentationActive", 1
)[0]
assert "delegate:Rectangle {" in event, "do not nest a second event MouseArea inside RippleButton"
assert "delegate:RippleButton {" not in event
assert "DragHandler {" not in event
assert event.count("preventStealing:true") == 3, "one body + two edge pointer owners"
assert 'onPressed:mouse=>timedButton.startGesture("move",eventMouse,mouse)' in event
assert 'onPressed:mouse=>timedButton.startGesture("top",topResizeMouse,mouse)' in event
assert 'onPressed:mouse=>timedButton.startGesture("bottom",bottomResizeMouse,mouse)' in event
assert event.count("onCanceled:timedButton.cancelGesture()") == 3
assert 'if (!timedButton.gestureMoved)' in event, "a drag must not open the edit dialog"
assert "mapToItem(viewport.contentItem,mouse.x,mouse.y)" in event
assert "root.activeDragDay=dayColumn.index" in event
assert "root.activeDragDay=-1" in event
assert "onReleased:timedButton.finishGesture(" in event
assert "root.commitTimedGesture(modelData,mode,dx,dy)" in event
assert 'Gesture.rangeForGesture(modelData,gestureMode,dragX,dragY,' in event
assert 'const saved=projected' in qml
assert 'root.localBackend[method](row.event.id,row.occurrenceIndex,' in qml
assert "function rescheduleOccurrence(id, index, startIso, endIso, metadata)" in backend
assert "function rescheduleRecurringOccurrence(id, index, startIso, endIso)" in backend
assert 'const method=projected ? "rescheduleProjectedRecurring"' in qml
assert 'function rescheduleProjectedRecurring(id, index, originalIso, startIso, endIso)' in backend
assert 'const range=repeating ? Gesture.rangeForGesture(target,mode,dx,dy,' in qml
assert 'if (!Selection.canReschedule(row)) return []' in qml

assert "function rangeForGesture(row, mode, dx, dy, dayWidth, hourHeight)" in policy
assert 'row.source !== "local" || row.event?.allDay === true' in policy
assert '(row.virtual && !row.plannerOriginalStartIso)' in policy, "unknown projections stay read-only"

# Hard regression gate: these three native hit targets, release handlers,
# viewport anti-steal and discoverable start/end grips are product behavior.
# CI must fail rather than silently shipping a Dashboard page refactor that
# removes event drag or makes both resize affordances fully invisible.
assert 'objectName:"plannerEventMoveArea"' in event
assert 'objectName:"plannerResizeStart"' in event
assert 'objectName:"plannerResizeEnd"' in event
assert event.count("acceptedButtons:Qt.LeftButton") == 3
assert event.count("cursorShape:Qt.SizeVerCursor") == 2
assert 'cursorShape:timedButton.canReschedule' in event
assert 'readonly property bool canReschedule: Selection.canReschedule(modelData)' in event
assert 'visible:timedButton.canReschedule' in event
assert event.count('height:Math.min(11,parent.height/3)') == 2
assert 'timedButton.gestureMode==="top" ? .9 : .38' in event
assert 'timedButton.gestureMode==="bottom" ? .9 : .38' in event
assert 'root.commitTimedGesture(modelData,mode,dx,dy)' in event
selection=(root / "modules/dashboard/PlannerSelection.js").read_text()
assert 'row.source==="local" && !row.virtual' in selection
assert '(row.event?.recurrence || "none")==="none"' in selection
assert "function canReschedule(row)" in selection
assert '["daily","weekly","monthly","yearly"].includes(event?.recurrence)' in selection
assert 'function rescheduleOccurrence(id, index, startIso, endIso, metadata)' in backend
assert 'function reschedule(event,index,start,end)' in (root / "services/EventOccurrences.js").read_text()
assert 'function rescheduleSavedRecurring(event,index,start,end)' in (root / "services/EventOccurrences.js").read_text()
assert 'function rescheduleProjectedRecurring(event,index,originalIso,start,end)' in (root / "services/EventOccurrences.js").read_text()
assert 'row.plannerOriginalStartIso' in qml
print("WEEKLY_PLANNER_POINTER_SOURCE_PASS: guarded event move + visible top/bottom resize + safe persistence")
