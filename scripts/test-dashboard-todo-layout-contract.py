#!/usr/bin/env python3
"""Static contract for the adaptive Dashboard Todo presentation."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
todo = (ROOT / "modules" / "dashboard" / "DashTodo.qml").read_text(encoding="utf-8")

for token in (
    "import QtQuick.Shapes",
    "readonly property bool narrowLayout:",
    "readonly property bool shallowLayout:",
    "readonly property bool veryShallowLayout:",
    "id: tabShell",
    "Layout.alignment: Qt.AlignHCenter",
    "Layout.preferredWidth: Math.max(1, Math.min(",
    "320, root.width - 24",
    "readonly property real innerHeight:",
    "readonly property real cornerRadius: innerHeight / 2",
    "readonly property real arcKappa: 0.5522847498",
    "readonly property real inset: 2",
    "readonly property int tabIconSize:",
    "readonly property int badgeSize:",
    "readonly property real labelSpacing: 4",
    "id: inactiveTabShape",
    "PathCubic {",
    "xScale: root.currentTab === 0 ? -1 : 1",
    "width: tabShell.halfWidth + tabShell.cornerRadius",
    "id: activeTabPill",
    "? tabShell.inset",
    ": tabShell.halfWidth",
    "width: tabShell.halfWidth - tabShell.inset",
    "radius: tabShell.cornerRadius",
    "id: leftTabHover",
    "id: rightTabHover",
    'Translation.tr("Unfinished")',
    'Translation.tr("Done")',
    "id: leftTabLabel",
    "id: rightTabLabel",
    "anchors.centerIn: parent",
    "anchors.verticalCenter: parent.verticalCenter",
    "font.weight: Font.Medium",
    "anchors.rightMargin: 6",
    "width: tabShell.badgeSize",
    "height: tabShell.badgeSize",
    "root.unfinishedTasks.length",
    "root.doneTasks.length",
    "readonly property int safeEdgeInset: 2",
    "readonly property int actionButtonSize:",
    "Layout.leftMargin: root.safeEdgeInset",
    "Layout.rightMargin: root.safeEdgeInset",
    'Translation.tr("Prepare Nexus")',
    'Translation.tr("Edit task source")',
    'Translation.tr("Add task")',
):
    assert token in todo, f"Dashboard Todo adaptive UI contract lost: {token}"

# Only one inactive path is maintained; right-side presentation is a mirror of
# the same canonical geometry. Both convex and concave ends use the same R and
# cubic-circle constant, so the two tab states cannot drift apart.
assert todo.count("id: inactiveTabShape") == 1
assert "id: inactiveLeftShape" not in todo
assert "id: inactiveRightShape" not in todo
assert todo.count("PathCubic {") == 4
assert todo.count("tabShell.arcKappa * tabShell.cornerRadius") >= 8
assert todo.count("id: activeTabPill") == 1
assert "PathArc.Counterclockwise" not in todo
assert "PathArc.Clockwise" not in todo

# Icon + text are centered as one visual unit. Count badges are independently
# right-anchored so their width never displaces the label center.
assert todo.count("id: leftTabLabel") == 1
assert todo.count("id: rightTabLabel") == 1
assert todo.count("anchors.centerIn: parent") >= 2
assert todo.count("anchors.rightMargin: 6") >= 2
assert todo.count("width: tabShell.badgeSize") == 2
assert todo.count("font.weight: Font.Medium") >= 2
assert "iconSlotSize" not in todo
assert "contentPadding" not in todo
assert "contentSpacing" not in todo
assert 'text: "more_horiz"' not in todo

assert "seamOverlap" not in todo
assert "tabSurfaceWidth" not in todo
assert "implicitHeight: root.tabControlHeight" in todo
assert "root.veryShallowLayout ? 28 : (root.narrowLayout ? 30 : 32)" in todo
assert "Layout.minimumHeight: root.veryShallowLayout" in todo
assert todo.count("Layout.preferredWidth: root.actionButtonSize") == 3
assert "id: setupRow" not in todo
assert "id: editRow" not in todo
assert "id: addRow" not in todo
assert "tabShell.notch" not in todo

print("Dashboard Todo adaptive layout contract: PASS")
