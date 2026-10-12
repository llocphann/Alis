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
assert 'hideEmbeddedScrollBar:false' in planner
assert 'embeddedBackgroundColor: {' in planner
assert 'AbyssStyle.contentLayer : Appearance.colors.colLayer1' in planner
assert 'AbyssStyle.contentLayer : Appearance.colors.colLayer1' in todo
assert 'property bool plannerPresentation: false' in editor
assert 'readonly property bool compactEditor: embeddedPresentation && !plannerPresentation' in editor
assert 'root.plannerPresentation ? 12 : Math.max(4,' in editor, "no stretched empty gap"
assert 'contentHeight: root.compactEditor' in editor, "expanded content scrolls naturally"
assert 'visible: root.compactEditor' in editor, "Calendar deck remains compact"
assert 'visible: !root.compactEditor' in editor, "Planner shows full labelled form controls"
assert 'embeddedPresentation: true' in calendar and 'plannerPresentation:true' not in calendar, "Calendar untouched"
for kind,mouse in [('Start','topResizeMouse'),('End','bottomResizeMouse')]:
    marker='objectName:"plannerResize'+kind+'"'
    segment=planner.split(marker,1)[1].split('onCanceled:timedButton.cancelGesture()',1)[0]
    assert 'radius:3;color:"transparent"' in segment
    assert 'height:2' in segment and 'width:Math.min(28,parent.width*.3)' in segment
    assert 'opacity:'+mouse+'.containsMouse' in segment
    assert 'hoverEnabled:true' in segment
assert 'Qt.alpha(root.ink,.32)' not in planner.split('objectName:"plannerResizeStart"',1)[1].split('objectName:"plannerResizeEnd"',1)[0]
print("WEEKLY_PLANNER_EXPANDED_EDITOR_AND_RESIZE_HOVER_PASS")
