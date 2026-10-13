#!/usr/bin/env python3
"""Calendar Popup compact event cards and readable agenda dots: source contract."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
events = (ROOT / "modules/sidebarRight/events/EventsWidget.qml").read_text()
card = (ROOT / "modules/sidebarRight/events/EventCard.qml").read_text()
month = (ROOT / "modules/common/widgets/ObsidianMonthCalendar.qml").read_text()
popup = (ROOT / "modules/bar/ClockCalendarContent.qml").read_text()

def require(ok, reason):
    if not ok:
        raise SystemExit("CALENDAR_COMPACT_FAIL: " + reason)

require("compactCalendarWindow: true" in popup, "popup must opt in to compact Events")
require("countedEventDots: true" in popup, "popup must opt in to counted dots")
require("property bool compactCalendarWindow: false" in events,
        "other EventsWidget owners must retain their defaults")
for label in ('Translation.tr("Today")', 'Translation.tr("Tomorrow")',
              'Translation.tr("Day after")'):
    require(label in events, "missing civil day label " + label)
require('modelData._dayOffset === 0' in events
        and 'modelData._dayOffset === 1' in events,
        "headers must use local three-day offsets rather than formatted dates")
require("root.compactCalendarWindow ? 4 : 8" in events,
        "calendar card spacing must be scoped")
require("root.compactPresentation ? 24 : 40" in card
        and "root.compactPresentation ? 14 : 20" in card,
        "calendar icon dimensions not compacted")
require("if (root.compactPresentation) return range" in card,
        "compact time must exclude redundant Today/Tomorrow/date")
require("cardHover.hovered || root.activeFocus" in card,
        "non-time metadata needs hover/keyboard-focus reveal")
require("HoverHandler { id: removeHover }" in card
        and "removeHover.hovered" in card,
        "close button must only reveal in its own hover target")
require("root.compactPresentation ? 26 : 32" in card,
        "compact close touch area not scoped")
require("Appearance.colors.colLayer1" in card
        and "visible: !root.compactPresentation" in card,
        "compact card background and shadow must be theme-aware")
require("spacing: root.countedEventDots ? 3 : 1" in month,
        "counted agenda dots must be spaced slightly farther apart")
require('objectName: "calendarEventDot"' in month,
        "calendar dot identity must be preserved")
print("CALENDAR_COMPACT_PASS: scoped groups/cards/hover/time/theme and counted-dot spacing")
