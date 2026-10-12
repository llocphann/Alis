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
assert 'if (!root.localBackend.rescheduleOccurrence(' in qml
assert "function rescheduleOccurrence(id, index, startIso, endIso, metadata)" in backend
assert "function rangeForGesture(row, mode, dx, dy, dayWidth, hourHeight)" in policy
assert 'row.source !== "local" || row.virtual' in policy, "read-only and recurrence limits"
print("WEEKLY_PLANNER_POINTER_SOURCE_PASS: pointer ownership + move/resize contracts")
