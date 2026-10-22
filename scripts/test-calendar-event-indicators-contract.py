#!/usr/bin/env python3
"""Calendar dots source: counterclockwise per-edge cap and legacy compatibility."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
config=json.loads((root/"defaults/config.json").read_text())
renderer=(root/"modules/common/widgets/ObsidianMonthCalendar.qml").read_text()
policy=(root/"modules/common/widgets/CalendarEventDotLayout.js").read_text()
popup=(root/"modules/bar/ClockCalendarContent.qml").read_text()
editor=(root/"modules/sidebarRight/events/EventsDialog.qml").read_text()
events=(root/"services/Events.qml").read_text()
occurrences=(root/"services/EventOccurrences.js").read_text()
sidebar=(root/"modules/sidebarRight/calendar/CalendarWidget.qml").read_text()
settings=(root/"modules/settings/IntegrationsConfig.qml").read_text()
english=json.loads((root/"translations/en_US.json").read_text())
def require(ok,msg):
    if not ok:raise SystemExit("CALENDAR_EVENT_DOTS_FAIL: "+msg)
require(config["calendar"]["maxEventDots"]==3,"default must be three per edge")
require("property bool countedEventDots: false" in renderer,"opt-in mode changed")
require("Math.max(0, Math.min(3, root.maxEventDots))" in renderer,"per-edge cap must be three")
require('import "CalendarEventDotLayout.js" as DotLayout' in renderer,"pure policy module not loaded")
require("DotLayout.layoutDots(dayCell.eventCount" in renderer,"dot layout is not reactive to count")
for i,name in enumerate(["Bottom","Right","Top","Left"]):
    require(f'objectName: "calendarEventDot{name}"' in renderer,"missing "+name+" perimeter")
    require(f"dayCell.dotLayout?.edges[{i}]" in renderer,"missing "+name+" distribution")
require(renderer.count('objectName: "calendarEventDot"')==4,"dot delegates must retain identity")
require("dayCell.eventColors.slice(0, 3)" in renderer,"legacy source-color dots changed")
require('objectName: "calendarEventOverflow"' not in renderer,
    "counted calendar must not render a + overflow marker")
require("overflow:" not in policy, "indicator layout must not expose unused overflow state")
require("Math.floor(i / limit)" in policy and "limit * 4" in policy,"pure counterclockwise packing missing")
require("spacing: root.countedEventDots ? 3 : 1" in renderer,"legacy dot spacing changed")
require("Math.min(3," in popup and "Math.min(3," in editor,"counted hosts must cap at 3")
require("countedEventDots: true" in popup and "maxEventDots: root.maxEventDots" in popup,"Popup not wired")
require("countedEventDots: true" in editor,"Planner editor not wired")
require("Events.getAllEventOccurrencesForDate(date)" in editor,
    "Planner calendar must count saved slots, not canonical Event IDs")
require("Occurrences.occurrencesForDay(event,date,true)" in events,
    "Calendar occurrence feed must include every saved slot and history")
require("function occurrencesForDay(event,date,includeNotified)" in occurrences,
    "Missing canonical per-day slot filter")
require("return occurrencesForDay(event,date,includeNotified).length > 0" in occurrences,
    "Legacy intersectsDay must share per-day filtering semantics")
require("CalendarSync.getEventsForDate(d)" in popup and "Events.getAllEventOccurrencesForDate(d)" in popup,"missing historical feeds")
require("Events.getEventsForDate(d)" not in popup,"popup must not discard notified Agenda history")
require("eventCount: local.length + external.length" in popup,"event identity/count lost")
require("root._localEventRevision" in popup and "root._externalEventRevision" in popup,"updates no longer reactive")
require("onReadyChanged()" in popup,"popup must update when local Agenda storage loads")
require(all(x in popup for x in ["onEventAdded(event)","onEventRemoved(id)","onEventUpdated(event)","onEventsUpdated()"]),"events signals missing")
require("showEventDots: root.maxEventDots > 0" in popup,"setting zero must hide dots")
require('Config.setNestedValue("calendar.maxEventDots", value)' in settings,"settings storage changed")
require('Translation.tr("Maximum indicators per edge")' in settings,"per-edge label missing")
require("from: 0" in settings and "to: 3" in settings,"settings must cap at three")
require("Maximum indicators per edge" in english,"English translation missing")
require("Events.getAllEventOccurrencesForDate(date)" in sidebar,"Dashboard must count historic Agenda occurrences")
require("Events.getEventsForDate(" not in sidebar,"Dashboard must not omit notified slots")
require("onReadyChanged()" in sidebar,"Dashboard must update when Agenda storage loads")
require("countedEventDots: root.dashboardAdaptive" in sidebar,"Dashboard must use counted dots without changing Sidebar style")
require("maxEventDots: root.maxEventDots" in sidebar,"Dashboard indicator count cap not wired")
require("showEventDots: !root.dashboardAdaptive || root.maxEventDots > 0" in sidebar,"zero indicator setting must disable Dashboard dots only")
require("local.map(() => root.colPrimary)" in sidebar and "external.map(event => event.sourceColor || root.colPrimary)" in sidebar,"Dashboard colors must match event identities")
require("root.distinctSourceColors(local, external)" in sidebar,"Sidebar source-color legacy mode not preserved")
print("CALENDAR_EVENT_DOTS_PASS: Dashboard and Edge historical indicators, per-event colors, count bounds")
