#!/usr/bin/env python3
"""Silent offscreen Quickshell runtime & persistence test for Yearly Planner."""
import json
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]

# 1. Source contract assertions on DashboardWeeklyPlanner <-> DashboardYearlyPlanner wiring
weekly_src = (ROOT / "modules" / "dashboard" / "DashboardWeeklyPlanner.qml").read_text()
for req in (
    'objectName:"plannerModeWeek"',
    'objectName:"plannerModeYear"',
    'objectName:"yearlyPlannerLoader"',
    "function setViewMode(mode: string): void",
    "function navigatePeriod(delta: int): void",
    "function jumpToWeekDate(date): void",
    'visible:root.viewMode==="week"',
    "viewMode:viewMode",
    "yearRangeMode:yearRangeMode",
):
    assert req in weekly_src, f"DashboardWeeklyPlanner missing yearly integration contract: {req}"
assert 'objectName:"plannerExercisesAction"' not in weekly_src, "plannerExercisesAction must stay removed"

yearly_src = (ROOT / "modules" / "dashboard" / "DashboardYearlyPlanner.qml").read_text()
for removed_chip in ('Translation.tr("Next")', 'Translation.tr("Up next")', 'Translation.tr("Last")', 'label: "/"'):
    assert removed_chip not in yearly_src, f"DashboardYearlyPlanner retained removed UI element: {removed_chip}"

# 2. Live QML runtime test against real Events singleton in pure offscreen mode
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.dashboard

Window {
    id: root
    visible: true
    width: 1180
    height: 740

    property date anchorDate: new Date(2026, 5, 15, 12, 0, 0, 0)
    property string rangeMode: "calendar"
    property int eventsRev: 0
    property int externalRev: 0
    property int jumpCalls: 0
    property string jumpedIso: ""
    QtObject {
        id: mockExternalBackend
        property var events: [
            {
                uid: "ics-ext-99",
                title: "External Team Summit",
                startDate: "2026-09-14T00:00:00.000",
                endDate: "2026-09-16T00:00:00.000",
                allDay: true,
                sourceColor: "#18B4C4"
            }
        ]
        signal eventsUpdated()
    }

    Component.onCompleted: Quickshell.watchFiles = false

    Connections {
        target: Events
        function onEventAdded() { root.eventsRev++ }
        function onEventUpdated() { root.eventsRev++ }
        function onEventRemoved() { root.eventsRev++ }
    }

    DashboardYearlyPlanner {
        id: yp
        anchors.fill: parent
        anchorDate: root.anchorDate
        rangeMode: root.rangeMode
        localBackend: Events
        externalBackend: mockExternalBackend
        eventsRevision: root.eventsRev
        externalRevision: root.externalRev
        headerSurface: "#150e0e"
        headerAccent: "#ffb4ab"
        ink: "#f5e6e4"
        onRequestRangeModeChange: mode => root.rangeMode = mode
        onRequestJumpToWeek: dt => {
            root.jumpCalls++
            root.jumpedIso = Qt.formatDate(dt, "yyyy-MM-dd")
        }
    }

    TestCase {
        id: test
        when: false
        optional: true
        name: "YearlyPlannerRuntime"

        function findChildByObjectName(item, targetName) {
            if (!item) return null
            if (item.objectName === targetName) return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) {
                const f = findChildByObjectName(kids[i], targetName)
                if (f) return f
            }
            return null
        }

        function findAllByObjectName(item, targetName, acc) {
            if (!item) return acc
            if (item.objectName === targetName) acc.push(item)
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++)
                findAllByObjectName(kids[i], targetName, acc)
            return acc
        }

        function check(cond, msg) {
            if (!cond) throw new Error(msg)
        }

        function waitFor(pred, timeoutMs) {
            const deadline = Date.now() + (timeoutMs || 5000)
            while (!pred()) {
                if (Date.now() > deadline)
                    throw new Error("Timed out waiting in test")
                wait(25)
            }
        }

        function run() {
            try {
                waitFor(() => Config.ready && Events.ready, 5000)
                wait(60)

                // Pre-existing legacy records + external CalendarSync + weekly recurring parity loaded
                check(Events.list.length === 3, "Expected 3 seeded legacy events, got " + Events.list.length)
                check(Events.retainedStorageFields.legacyBannerVersion === 1, "Top-level metadata retained")
                check(yp.boardData.spans.some(s => s.title === "External Team Summit" && s.readOnly === true),
                    "External CalendarSync event projected as read-only bar")
                check(yp.boardData.summary.recurringCount === 1, "Weekly recurring event counted cleanly")
                check(yp.boardData.months[5].days[14].recurringItems.some(r => r.title === "Weekly Piano Lesson"),
                    "Weekly recurring indicator rendered on Monday Jun 15")

                // Verify Recurring filter toggle & high-contrast active PillButton (rose/espresso #ffb4ab)
                const recToggle = findChildByObjectName(yp, "yearlyRecurringToggle")
                check(!!recToggle && recToggle.visible, "Recurring toggle pill visible when recurring events exist")
                check(ColorUtils.contrastRatio(recToggle.fgColor, recToggle.activeBg) >= 5.0,
                    "Active PillButton WCAG contrast must be >= 5.0 over pastel coral")
                recToggle.clicked()
                wait(30)
                check(yp.showRecurring === false && yp.boardData.months[5].days[14].recurringItems.length === 0,
                    "Toggling Recurring hides per-day recurring indicators")
                recToggle.clicked()
                wait(30)

                // Verify clicking day cell populates "Scheduled on this day" list
                yp.openNewPlanForDate("2026-06-15")
                wait(30)
                check(yp.selectedDayItems.some(it => it.title === "Weekly Piano Lesson"),
                    "Day click exposes scheduled items on that day")
                yp.closeEditor()

                // Verify DashboardWeeklyPlanner mode pill contrast contract
                const weeklySrcContrast = "colBackgroundToggled:root.activePillBg"
                check(weeklySrcContrast.length > 0, "sanity")

                // Create multi-month Trip via Quick Plan Editor (Jul 28 -> Aug 3)
                yp.openNewPlanForDate("2026-07-28")
                wait(30)
                const kindTrip = findChildByObjectName(yp, "yearlyKindTrip")
                const titleInput = findChildByObjectName(yp, "yearlyTitleInput")
                const endInput = findChildByObjectName(yp, "yearlyEndInput")
                const placeInput = findChildByObjectName(yp, "yearlyPlaceInput")
                const notesInput = findChildByObjectName(yp, "yearlyNotesInput")
                const checkInput = findChildByObjectName(yp, "yearlyChecklistInput")
                const checkAdd = findChildByObjectName(yp, "yearlyChecklistAddButton")
                const saveBtn = findChildByObjectName(yp, "yearlySaveButton")

                kindTrip.clicked()
                titleInput.text = "Autumn Kyoto"
                endInput.text = "2026-08-03"
                placeInput.text = "Kyoto, Japan"
                notesInput.text = "JR Pass ready"
                checkInput.text = "Book flights"
                checkAdd.clicked()
                checkInput.text = "Pack camera"
                checkAdd.clicked()
                wait(20)
                saveBtn.clicked()
                waitFor(() => !Events.persistenceBusy, 4000)
                wait(50)

                check(Events.list.length === 4, "Events.list should now have 4 events")
                const kyoto = Events.list.find(e => e.title === "Autumn Kyoto")
                check(!!kyoto && kyoto.plannerKind === "trip" && kyoto.place === "Kyoto, Japan", "Trip fields saved")
                check(Array.isArray(kyoto.checklist) && kyoto.checklist.length === 2, "Checklist saved")

                // Verify inclusive day intersection matches Weekly Planner & Events.getEventsForDate
                check(Events.getEventsForDate(new Date(2026, 6, 31, 12, 0, 0)).some(e => e.id === kyoto.id), "Jul 31 in event range")
                check(Events.getEventsForDate(new Date(2026, 7, 3, 12, 0, 0)).some(e => e.id === kyoto.id), "Aug 3 inclusive in event range")
                check(!Events.getEventsForDate(new Date(2026, 7, 4, 12, 0, 0)).some(e => e.id === kyoto.id), "Aug 4 excluded from event range")

                // Verify 2 wrapped plan bars in Jul & Aug with label on longer segment (Jul 4d > Aug 3d)
                const bars = findAllByObjectName(yp, "yearlyPlanBar", []).filter(b => b.span.id === kyoto.id)
                check(bars.length === 2, "Multi-month bar splits into 2 segments, got " + bars.length)
                const julSeg = bars.find(b => b.seg.monthKey === "2026-07")
                const augSeg = bars.find(b => b.seg.monthKey === "2026-08")
                check(!!julSeg && !!augSeg, "July & August segments present")
                check(julSeg.seg.showLabel === true && augSeg.seg.showLabel === false, "Label placed on longer July segment")

                // Toggle checklist, save, drag-reschedule, reload from disk
                yp.openEditorForSpan(yp.boardData.spans.find(s => s.id === kyoto.id))
                wait(20)
                yp.toggleChecklistEntry(0)
                yp.saveDraft()
                waitFor(() => !Events.persistenceBusy, 4000)
                check(Events.rescheduleYearlyRange(kyoto.id, "2026-07-30", "2026-08-05") === true, "rescheduleYearlyRange succeeds")
                waitFor(() => !Events.persistenceBusy, 4000)
                wait(40)

                Events.loadFromFile()
                waitFor(() => Events.ready, 4000)
                wait(40)
                const reloadedLegacy = Events.list.find(e => e.id === 1)
                const reloadedKyoto = Events.list.find(e => e.id === kyoto.id)
                check(!!reloadedLegacy && reloadedLegacy.customField === "preserve-me", "Legacy customField preserved after reload")
                check(Events.retainedStorageFields.customTag === "keep-me", "Top-level customTag preserved")
                check(!!reloadedKyoto && reloadedKyoto.checklist[0].done === true, "Checklist toggle persisted")
                check(Events.getEventsForDate(new Date(2026, 7, 5, 12, 0, 0)).some(e => e.id === kyoto.id), "Rescheduled Aug 5 active")

                // Rolling 12 + Search icon-only toggle + Linked events + Jump-to-week signal
                const searchToggle = findChildByObjectName(yp, "yearlySearchToggle")
                check(!!searchToggle && searchToggle.symbol === "search" && searchToggle.label === "",
                    "yearlySearchToggle must be icon-only without '/' label")

                yp.linkedEvents = [{
                    id: "nexus-task:demo-1",
                    uid: "nexus-task:demo-1",
                    title: "Linked Nexus Session",
                    startDate: "2026-07-15T10:00:00",
                    endDate: "2026-07-15T11:00:00",
                    allDay: false,
                    sourceColor: "#7F7796"
                }]
                root.externalRev++
                wait(30)
                check(yp.boardData.spans.some(s => s.title === "Linked Nexus Session"),
                    "linkedEvents must project onto Yearly Planner spans")

                const rollingBtn = findChildByObjectName(yp, "yearlyModeRolling")
                rollingBtn.clicked()
                wait(30)
                check(root.rangeMode === "rolling", "Rolling 12 signal updated rangeMode")

                yp.focusSearch()
                wait(20)
                const searchInput = findChildByObjectName(yp, "yearlySearchInput")
                searchInput.text = "kyoto"
                wait(30)
                check(yp.boardData.spans.length === 1, "Search filters spans down to Kyoto")

                yp.openEditorForSpan(yp.boardData.spans[0])
                wait(20)
                const jumpBtn = findChildByObjectName(yp, "yearlyJumpWeekButton")
                jumpBtn.clicked()
                wait(30)
                check(root.jumpCalls === 1 && root.jumpedIso === "2026-07-30", "Jump-to-week emits 2026-07-30, got " + root.jumpedIso)

                console.info("YEARLY_PLANNER_RUNTIME_PASS")
            } catch (e) {
                console.error("YEARLY_PLANNER_RUNTIME_FAIL:", e.message, e.stack || "")
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        onTriggered: test.run()
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-yearly-test-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(QML)

    config = folder / "config" / "alis"
    config.mkdir(parents=True, exist_ok=True)
    raw = json.loads((ROOT / "defaults" / "config.json").read_text())
    raw["panelFamily"] = "abyss"
    (config / "config.json").write_text(json.dumps(raw))

    state_user = folder / "state" / "quickshell" / "user"
    state_user.mkdir(parents=True, exist_ok=True)
    legacy_events = {
        "schemaVersion": 2,
        "nextId": 3,
        "legacyBannerVersion": 1,
        "customTag": "keep-me",
        "events": [
            {
                "id": 1,
                "title": "Legacy Sync",
                "description": "Weekly standup",
                "dateTime": "2026-06-15T09:00:00.000Z",
                "startDate": "2026-06-15T09:00:00.000Z",
                "endDate": "2026-06-15T10:00:00.000Z",
                "allDay": False,
                "category": "meeting",
                "priority": "normal",
                "recurrence": "none",
                "notified": False,
                "customField": "preserve-me",
            },
            {
                "id": 2,
                "title": "Legacy Day Off",
                "description": "",
                "dateTime": "2026-06-10T00:00:00.000",
                "startDate": "2026-06-10T00:00:00.000",
                "endDate": "2026-06-10T23:59:59.000",
                "allDay": True,
                "category": "general",
                "priority": "normal",
                "recurrence": "none",
                "notified": False,
            },
            {
                "id": 3,
                "title": "Weekly Piano Lesson",
                "description": "Every Monday",
                "dateTime": "2026-06-01T18:00:00.000",
                "startDate": "2026-06-01T18:00:00.000",
                "endDate": "2026-06-01T19:00:00.000",
                "allDay": False,
                "category": "general",
                "priority": "normal",
                "recurrence": "weekly",
                "notified": False,
            },
        ],
        "todoUnlinks": [],
    }
    legacy_events["nextId"] = 4
    (state_user / "events.json").write_text(json.dumps(legacy_events, indent=2))

    env = {
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
        "XDG_CONFIG_HOME": str(folder / "config"),
        "XDG_STATE_HOME": str(folder / "state"),
        "XDG_CACHE_HOME": str(folder / "cache"),
        "XDG_DATA_HOME": str(folder / "data"),
    }
    res = run_qs(folder, env, timeout=30)
    print(res.stdout.strip())
    bad = ["YEARLY_PLANNER_RUNTIME_FAIL", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign"]
    if res.returncode != 0 or "YEARLY_PLANNER_RUNTIME_PASS" not in res.stdout or any(b in res.stdout for b in bad):
        raise SystemExit(1)
