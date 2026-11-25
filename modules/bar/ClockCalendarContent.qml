pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sidebarRight.events
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    signal eventEditorRequested(var event)
    signal eventDateSelected(var date)

    property int monthShift: 0
    property bool eventDateSelectionEnabled: false
    property var selectedEventDate: null
    readonly property date today: DateTime.todayDate
    readonly property var locale: Qt.locale()
    readonly property date viewingDate: new Date(
        root.today.getFullYear(),
        root.today.getMonth() + root.monthShift,
        1
    )
    readonly property bool eventEditorActive: eventsPane.inlineEditorMode
    readonly property int maxEventDots: Math.max(0, Math.min(3,
        Number(Config.options?.calendar?.maxEventDots ?? 3)))
    property int _localEventRevision: 0
    property int _externalEventRevision: 0

    Connections {
        target: Events
        function onEventAdded(event) { root._localEventRevision++ }
        function onEventUpdated(event) { root._localEventRevision++ }
        function onEventRemoved(id) { root._localEventRevision++ }
        function onReadyChanged() { root._localEventRevision++ }
    }
    Connections {
        target: CalendarSync
        function onEventsUpdated() { root._externalEventRevision++ }
    }

    function closeEventEditor(): void {
        if (eventsPane.inlineEditorMode)
            eventsPane.closeInlineEditor()
    }

    readonly property var calendarCells: {
        // Invalidate when the shared local/external stores notify changes.
        root._localEventRevision
        root._externalEventRevision
        const year = root.viewingDate.getFullYear()
        const month = root.viewingDate.getMonth()
        const first = new Date(year, month, 1)
        const mondayOffset = (first.getDay() + 6) % 7
        const start = new Date(year, month, 1 - mondayOffset)
        const cells = []

        for (let i = 0; i < 42; ++i) {
            const d = new Date(start)
            d.setDate(start.getDate() + i)
            // Include fired/historic Agenda slots in month indicators.
            const local = Events.getAllEventOccurrencesForDate(d)
            const external = CalendarSync.getEventsForDate(d) || []
            // One color per EVENT, not per distinct event source.
            const colors = local.map(() => Appearance.colors.colPrimary)
                .concat(external.map(evt => evt.sourceColor
                    || Appearance.colors.colPrimary))
            cells.push({
                date: d,
                day: d.getDate(),
                currentMonth: d.getMonth() === month && d.getFullYear() === year,
                today: root.sameDay(d, root.today),
                eventCount: local.length + external.length,
                eventColors: colors,
            })
        }
        return cells
    }

    property bool verticalLayout: false
    // Keep both halves symmetric so the separator is the true visual center.
    // The month view remains the sizing floor; Events receives the same width.
    readonly property real paneWidth:
        Math.max(292, monthView.implicitWidth)
    readonly property real verticalEventsHeight: 236
    implicitWidth: root.verticalLayout ? root.paneWidth : (root.paneWidth * 2 + 25)
    implicitHeight: root.verticalLayout
        ? (monthView.implicitHeight + 13 + root.verticalEventsHeight)
        : monthView.implicitHeight

    function sameDay(a, b): bool {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    Item {
        id: calendarLayoutHost
        anchors.fill: parent

        EventsWidget {
            id: eventsPane
            x: 0
            y: root.verticalLayout ? (monthViewHost.height + 13) : 0
            width: root.verticalLayout ? parent.width : root.paneWidth
            height: root.verticalLayout
                ? Math.max(160, parent.height - y)
                : parent.height
            // Calendar popup-specific FAB treatment: smaller and tucked into
            // the popup's bottom-left corner. Other EventsWidget owners keep
            // the shared bottom-right default.
            fabSize: 36
            fabMargins: 10
            fabLeftAligned: true
            compactCalendarWindow: true
            showAddButton: false
        }

        Rectangle {
            id: calendarPaneDivider
            // A shorter centered hairline keeps the two panes visually related
            // without cutting the popup in half. Use the active theme accent
            // instead of a high-contrast white/outline line.
            x: root.verticalLayout ? 18 : (root.paneWidth + 12)
            y: root.verticalLayout
                ? (monthViewHost.height + 6)
                : Math.round((parent.height - height) / 2)
            width: root.verticalLayout ? Math.max(120, parent.width - 36) : 1
            height: root.verticalLayout
                ? 1
                : Math.max(120, Math.min(parent.height - 40, parent.height - 64))
            color: Appearance.colors.colPrimary
            opacity: 0.28
        }

        Item {
            id: monthViewHost
            x: root.verticalLayout ? 0 : (root.paneWidth + 25)
            y: 0
            width: root.verticalLayout
                ? parent.width
                : Math.max(root.paneWidth, parent.width - x)
            height: root.verticalLayout
                ? monthView.implicitHeight
                : parent.height

            NexusMonthCalendar {
                id: monthView
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                viewingDate: root.viewingDate
                today: root.today
                locale: root.locale
                calendarCells: root.calendarCells
                showEventDots: root.maxEventDots > 0
                countedEventDots: true
                maxEventDots: root.maxEventDots
                selectedDate: eventsPane.inlineEditorMode
                    ? eventsPane.inlineEditorDate
                    : root.selectedEventDate
                interactiveDays: true
                onPreviousMonthRequested: root.monthShift--
                onNextMonthRequested: root.monthShift++
                onTodayRequested: root.monthShift = 0
                onDayActivated: date => {
                    if (eventsPane.inlineEditorMode)
                        eventsPane.setInlineEditorDate(date)
                    else {
                        eventsPane.openInlineEditor(date)
                        root.eventDateSelected(date)
                    }
                }
            }
        }
    }
}
