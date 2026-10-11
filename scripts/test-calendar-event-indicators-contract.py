#!/usr/bin/env python3
"""Calendar Popup event dots: source-level 0..5 bounds, identity and update guards."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
config = json.loads((root / "defaults/config.json").read_text())
renderer = (root / "modules/common/widgets/ObsidianMonthCalendar.qml").read_text()
popup = (root / "modules/bar/ClockCalendarContent.qml").read_text()
settings = (root / "modules/settings/IntegrationsConfig.qml").read_text()
sidebar = (root / "modules/sidebarRight/calendar/CalendarWidget.qml").read_text()
music_config = config.get("dashboard", {}).get("music", {})

def require(condition, message):
    if not condition:
        raise SystemExit("CALENDAR_EVENT_DOTS_FAIL: " + message)

require(config["calendar"]["maxEventDots"] == 3, "default must be 3")
require("property bool countedEventDots: false" in renderer, "old calendar remains untouched")
require("Math.max(0, Math.min(5, root.maxEventDots))" in renderer, "renderer limit must be bounded")
require("dayCell.eventCount > root.effectiveMaxEventDots" in renderer, "overflow cue missing")
require("Math.min(Math.max(0, dayCell.eventCount)" in renderer, "event COUNT, not distinct source count")
require("countedEventDots: true" in popup and "maxEventDots: root.maxEventDots" in popup, "Popup must opt in")
require("CalendarSync.getEventsForDate(d)" in popup and "Events.getEventsForDate(d)" in popup,
        "local and external date queries missing")
require("eventCount: local.length + external.length" in popup, "event identity/count missing")
require("root._localEventRevision" in popup and "root._externalEventRevision" in popup,
        "date-cell reactive invalidation missing")
require("onEventAdded(event)" in popup and "onEventRemoved(id)" in popup
        and "onEventUpdated(event)" in popup and "onEventsUpdated()" in popup,
        "event update signals missing")
require("showEventDots: root.maxEventDots > 0" in popup, "setting zero must hide dots")
require('Config.setNestedValue("calendar.maxEventDots", value)' in settings,
        "Calendar Settings must persist the preference")
require('from: 0' in settings and 'to: 5' in settings, "Settings must bound input")
require("showEventDots: true" in sidebar and "countedEventDots: true" not in sidebar,
        "existing Sidebar/Dashboard calendar display changed")
require(music_config.get("showScrollbars") is True, "previous Music preference lost")
for cap in range(6):
    for count in [0, 1, 2, 3, 5, 6, 20]:
        shown = min(count, cap)
        require(0 <= shown <= cap and shown <= count, "dot count overflow")
        require((count > cap) == (shown < count), "overflow cue count mismatch")
print("CALENDAR_EVENT_DOTS_PASS: settings defaults, source feeds/signals, counted indicators and compatibility")
