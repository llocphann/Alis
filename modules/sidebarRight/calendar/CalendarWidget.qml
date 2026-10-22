pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    // Emitted when a day with events is clicked (for navigation in legacy mode)
    signal dayWithEventsClicked(var date)
    // Emitted to open the events dialog. An event object means edit it, a Date
    // means a new event prefilled to that day.
    signal openEventsDialog(var editEvent)

    // Two states: "month" (grid + upcoming) and "day" (day detail)
    property string viewState: "month"
    property var selectedDate: null
    property bool dashboardAdaptive: false
    // Keep Dashboard counted indicators aligned with the Edge calendar popup.
    readonly property int maxEventDots: Math.max(0, Math.min(3,
        Number(Config.options?.calendar?.maxEventDots ?? 3)))

    // Trigger to force recomputation when events change
    property int _eventsTrigger: 0
    Connections {
        target: Events
        function onEventAdded(event) { root._eventsTrigger++ }
        function onEventRemoved(id) { root._eventsTrigger++ }
        function onEventUpdated(event) { root._eventsTrigger++ }
        function onReadyChanged() { root._eventsTrigger++ }
    }
    property int _externalTrigger: 0
    Connections {
        target: CalendarSync
        function onEventsUpdated() { root._externalTrigger++ }
    }

    // Shared month presentation is Material-only and owned by
    // ObsidianMonthCalendar. CalendarWidget keeps only event data/state.
    readonly property color colPrimary: Appearance.colors.colPrimary

    property var locale: {
        const envLocale = Quickshell.env("LC_TIME") || Quickshell.env("LC_ALL") || Quickshell.env("LANG") || ""
        const cleaned = (envLocale.split(".")[0] ?? "").split("@")[0] ?? ""
        return cleaned ? Qt.locale(cleaned) : Qt.locale()
    }

    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, 1)
    readonly property var monthCells: {
        root._eventsTrigger
        root._externalTrigger
        const cells = []
        for (let weekRow = 0; weekRow < 6; ++weekRow) {
            for (let dayIndex = 0; dayIndex < 7; ++dayIndex) {
                const cell = root.calendarLayout[weekRow]?.[dayIndex]
                if (!cell)
                    continue
                const date = root._getDateForCell(cell.day, weekRow, dayIndex)
                // Month history includes every persisted occurrence, even if
                // its notification has already fired or its date has passed.
                const local = Events.getAllEventOccurrencesForDate(date)
                const external = CalendarSync.getEventsForDate(date) || []
                const colors = root.dashboardAdaptive
                    ? local.map(() => root.colPrimary).concat(
                        external.map(event => event.sourceColor || root.colPrimary))
                    : root.distinctSourceColors(local, external)
                cells.push({
                    date: date,
                    day: cell.day,
                    currentMonth: cell.today !== -1,
                    today: cell.today === 1,
                    eventCount: local.length + external.length,
                    eventColors: colors,
                })
            }
        }
        return cells
    }
    implicitHeight: contentStack.implicitHeight
    implicitWidth: contentStack.implicitWidth

    // Sidebar retains one dot per distinct calendar source; the Dashboard
    // instead counts every saved event to match the popup.
    function distinctSourceColors(local, external): var {
        const colors = []
        if (local.length > 0)
            colors.push(root.colPrimary)
        for (const event of external) {
            const color = event.sourceColor || root.colPrimary
            if (colors.indexOf(color) === -1)
                colors.push(color)
        }
        return colors
    }

    // Resolve a calendar cell to a real Date object
    function _getDateForCell(day: int, weekRow: int, dayIndex: int): var {
        const cellData = root.calendarLayout[weekRow]?.[dayIndex]
        if (!cellData) return null
        const year = root.viewingDate.getFullYear()
        const month = root.viewingDate.getMonth()
        let targetMonth = month
        let targetYear = year
        if (cellData.today === -1) {
            if (weekRow === 0) {
                if (month === 0) { targetMonth = 11; targetYear = year - 1 }
                else targetMonth = month - 1
            } else {
                if (month === 11) { targetMonth = 0; targetYear = year + 1 }
                else targetMonth = month + 1
            }
        }
        return new Date(targetYear, targetMonth, day)
    }

    function openDayDetail(date: var): void {
        root.selectedDate = date
        root.viewState = "day"
    }

    function closeDayDetail(): void {
        root.viewState = "month"
    }

    Keys.onPressed: (event) => {
        if (root.viewState === "day" && event.key === Qt.Key_Escape) {
            closeDayDetail()
            event.accepted = true
            return
        }
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) monthShift++
            else if (event.key === Qt.Key_PageUp) monthShift--
            event.accepted = true
        }
    }

    // Content stack — month view and day detail with crossfade transition
    Item {
        id: contentStack
        anchors.fill: parent
        implicitHeight: root.viewState === "day" ? dayDetailView.implicitHeight : monthView.implicitHeight
        implicitWidth: parent?.width ?? 280

        Behavior on implicitHeight {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        // Month view (grid + upcoming)
        Item {
            id: monthView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: root.dashboardAdaptive ? undefined : parent.top
            anchors.verticalCenter: root.dashboardAdaptive
                ? parent.verticalCenter : undefined
            implicitHeight: monthColumn.implicitHeight
            opacity: root.viewState === "month" ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            WheelHandler {
                target: monthView
                orientation: Qt.Vertical
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y > 0) root.monthShift--
                    else if (event.angleDelta.y < 0) root.monthShift++
                }
            }

            ColumnLayout {
                id: monthColumn
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                ObsidianMonthCalendar {
                    id: sharedMonthCalendar
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    viewingDate: root.viewingDate
                    today: DateTime.clock.date
                    locale: root.locale
                    calendarCells: root.monthCells
                    responsive: true
                    responsiveMinCellSize: root.dashboardAdaptive ? 24 : 30
                    responsiveMaxCellSize: root.dashboardAdaptive ? 56 : 42
                    responsiveAvailableHeight: root.dashboardAdaptive
                        ? Math.max(0, root.height - 8) : 0
                    autoWeekNumbers: root.dashboardAdaptive
                    interactiveDays: true
                    showEventDots: !root.dashboardAdaptive || root.maxEventDots > 0
                    countedEventDots: root.dashboardAdaptive
                    maxEventDots: root.maxEventDots

                    onPreviousMonthRequested: root.monthShift--
                    onNextMonthRequested: root.monthShift++
                    onTodayRequested: root.monthShift = 0
                    onDayActivated: date => root.openDayDetail(date)
                }

            }
        }

        // Day detail view
        Item {
            id: dayDetailView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: dayDetail.implicitHeight
            opacity: root.viewState === "day" ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            CalendarDayDetail {
                id: dayDetail
                anchors.left: parent.left
                anchors.right: parent.right
                selectedDate: root.selectedDate
                onBackClicked: root.closeDayDetail()
                onEventClicked: (event) => {
                    if ((event?.source ?? "local") === "local") root.openEventsDialog(event)
                }
                // A Date means "new event on this day". Hosts must not treat it
                // as an existing event to edit: a template object would make the
                // dialog call updateEvent() with no id and silently drop the event.
                onAddEventClicked: (date) => root.openEventsDialog(date)
            }
        }
    }


}
