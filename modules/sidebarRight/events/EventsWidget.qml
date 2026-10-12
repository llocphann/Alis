pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../dashboard/WeeklyPlannerPolicy.js" as Planner
import "EventsWindow.js" as UpcomingWindow

Item {
    id: root
    
    // Kept for API compatibility with older owners. Events creation/editing
    // now stays inside this widget instead of asking the owner for a dialog.
    signal openEventsDialog(var editEvent)

    property bool inlineEditorMode: false
    property var inlineEditorTarget: null
    readonly property var inlineEditorDate:
        inlineEditor.eventDate
    property int fabSize: 48
    property int fabMargins: 14
    // Shared EventsWidget keeps its historical bottom-right FAB by default.
    // Compact owners such as the Bar Calendar popup can opt into bottom-left
    // placement without changing Sidebar/other Events surfaces.
    property bool fabLeftAligned: false
    // Only ClockCalendarContent opts into a local-civil 3-day horizon.
    // Sidebar/other Events consumers retain the original upcoming view.
    property bool compactCalendarWindow: false

    // Style tokens
    readonly property color colPrimary: Appearance.angelEverywhere ? Appearance.angel.colPrimary
        : Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary
    readonly property color colText: Appearance.angelEverywhere ? Appearance.angel.colText
        : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
    readonly property color colSubtext: Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
        : Appearance.inirEverywhere ? Appearance.inir.colTextSecondary : Appearance.colors.colSubtext
    readonly property color colBadgeBg: Appearance.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimary, 0.70)
        : Appearance.inirEverywhere ? Appearance.inir.colSecondaryContainer
        : Appearance.colors.colSecondaryContainer
    readonly property color colBadgeText: Appearance.angelEverywhere ? Appearance.angel.colOnPrimary
        : Appearance.inirEverywhere ? Appearance.inir.colOnSecondaryContainer
        : Appearance.colors.colOnSecondaryContainer
    readonly property color colEmptyBg: Appearance.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimary, 0.85)
        : Appearance.inirEverywhere ? Appearance.inir.colLayer1
        : Appearance.auroraEverywhere ? (Appearance.aurora?.colSubSurface ?? Appearance.colors.colSecondaryContainer)
        : Appearance.colors.colSecondaryContainer
    
    // Trigger to force recomputation when events change
    property int _eventsTrigger: 0
    Connections {
        target: Events
        function onEventAdded(event) { root._eventsTrigger++ }
        function onEventRemoved(id) { root._eventsTrigger++ }
        function onEventUpdated(event) { root._eventsTrigger++ }
    }
    property int _externalTrigger: 0
    Connections {
        target: CalendarSync
        function onEventsUpdated() { root._externalTrigger++ }
    }
    
    readonly property string _todayKey: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")

    // Merged events: local + external, sorted by date
    readonly property var mergedEvents: {
        const _t = root._eventsTrigger
        const _t2 = root._externalTrigger
        const _d = root._todayKey
        return _buildMergedEvents()
    }

    function _buildMergedEvents(): var {
        const now = new Date()
        if (root.compactCalendarWindow)
            return UpcomingWindow.threeDayEvents(Events.list, CalendarSync.events,
                DateTime.clock.date, Planner.project)
        const all = []
        const localEvents = Events.getUpcomingEvents(30)
        for (const e of localEvents) {
            all.push(Object.assign({}, e, {
                _source: "local"
            }))
        }

        // Get external events for the next 30 days, skip past ones
        const startDay = new Date(now)
        startDay.setHours(0, 0, 0, 0)
        const dates = []
        for (let i = 0; i < 30; i++) {
            const d = new Date(startDay)
            d.setDate(d.getDate() + i)
            dates.push(d)
        }
        const externalBuckets = CalendarSync._getEventBucketsForDates(dates)
        for (let i = 0; i < externalBuckets.length; i++) {
            const dayEvents = externalBuckets[i] || []
            for (const e of dayEvents) {
                const evtTime = new Date(e.startDate || e.dateTime)
                if (evtTime < now && !(e.allDay && evtTime >= startDay)) continue
                all.push(Object.assign({}, e, {
                    _source: "external",
                    dateTime: e.startDate || e.dateTime,
                    category: "general",
                    priority: "normal"
                }))
            }
        }

        all.sort((a, b) => {
            const da = new Date(a.dateTime || a.startDate)
            const db = new Date(b.dateTime || b.startDate)
            return da - db
        })
        return all
    }

    readonly property int upcomingCount: {
        const _t = root._eventsTrigger
        const _t2 = root._externalTrigger
        return root.mergedEvents.length
    }

    function openInlineEditor(editEvent): void {
        root.inlineEditorTarget = editEvent
        if (editEvent instanceof Date) {
            inlineEditor.resetForm()
            inlineEditor.eventDate = new Date(editEvent)
        } else if (editEvent) {
            inlineEditor.loadEvent(editEvent)
        } else {
            inlineEditor.resetForm()
        }
        root.inlineEditorMode = true
        inlineEditor.focusEditor()
    }

    function closeInlineEditor(): void {
        root.inlineEditorMode = false
        root.inlineEditorTarget = null
    }

    function setInlineEditorDate(date): void {
        const parsed = new Date(date)
        if (!isNaN(parsed.getTime()))
            inlineEditor.eventDate = parsed
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: !root.inlineEditorMode
        
        // Header with upcoming count
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 8
            
            MaterialSymbol {
                text: "event_upcoming"
                iconSize: 20
                fill: 1
                color: root.colPrimary
            }
            
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Events")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.colText
            }
            
            Rectangle {
                visible: root.upcomingCount > 0
                implicitWidth: Math.max(20, countText.implicitWidth + 10)
                implicitHeight: 20
                radius: 10
                color: root.colBadgeBg
                
                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: root.upcomingCount
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.numbers
                    color: root.colBadgeText
                }
            }
        }
        
        // Events list
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: eventsColumn.implicitHeight
            clip: true
            
            ScrollBar.vertical: ScrollBar {
                // Calendar's narrow Events pane has no visible scroll chrome;
                // the Flickable keeps wheel/touchpad/touch/keyboard scrolling.
                policy: root.compactCalendarWindow
                    ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
            }
            
            ColumnLayout {
                id: eventsColumn
                width: parent.width
                spacing: 8
                
                // Merged events
                Repeater {
                    model: root.mergedEvents

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth:true
                        spacing:4

                        StyledText {
                            visible:root.compactCalendarWindow && modelData._showDayHeader
                            Layout.fillWidth:true
                            Layout.leftMargin:12
                            Layout.topMargin:6
                            text:modelData._groupDate
                                ? Qt.formatDate(modelData._groupDate,"ddd, dd MMM") : ""
                            font.pixelSize:Appearance.font.pixelSize.small
                            font.weight:Font.DemiBold
                            color:root.colSubtext
                        }
                        EventCard {
                            Layout.fillWidth:true
                            Layout.margins:root.compactCalendarWindow ? 6 : 8
                            compactPresentation:root.compactCalendarWindow
                            event:modelData
                            isExternal:(modelData?._source ?? "local")==="external"
                            onRemoveClicked: {
                                if (!isExternal) Events.removeEvent(modelData.id)
                            }
                            onEditClicked: evt => {
                                if (!isExternal) root.openInlineEditor(
                                    modelData._canonicalEvent ?? evt)
                            }
                        }
                    }
                }
                
                // Empty state
                Item {
                    id: emptyState
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    visible: root.mergedEvents.length === 0
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        width: parent.width - 32

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48

                            MaterialSymbol {
                                // Bgless empty state: just the colored, breathing glyph — no grey blob.
                                anchors.centerIn: parent
                                text: "event_available"
                                iconSize: 32
                                fill: 0
                                color: root.colPrimary

                                SequentialAnimation on opacity {
                                    running: emptyState.visible && GlobalStates.sidebarRightOpen && Appearance.animationsEnabled
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.5; duration: 2000; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 2000; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                        
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.compactCalendarWindow
                                ? Translation.tr("No events in the next three days")
                                : Translation.tr("No upcoming events")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: root.colText
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Tap + to add your first event")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
    
    // The editor occupies exactly the same item as the Events list. Switching
    // modes never changes the parent/tab geometry.
    EventsDialog {
        id: inlineEditor
        anchors.fill: parent
        show: root.inlineEditorMode
        embeddedPresentation: true
        hideEmbeddedScrollBar: root.compactCalendarWindow
        embeddedBackgroundColor: "transparent"
        backgroundHeight: -1
        visible: root.inlineEditorMode
        onDismiss: root.closeInlineEditor()
    }

    // FAB to add event
    StyledRectangularShadow {
        target: fabButton
        visible: !root.inlineEditorMode
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    
    FloatingActionButton {
        id: fabButton
        visible: !root.inlineEditorMode
        anchors.left: root.fabLeftAligned ? parent.left : undefined
        anchors.right: root.fabLeftAligned ? undefined : parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.fabLeftAligned ? root.fabMargins : 0
        anchors.rightMargin: root.fabLeftAligned ? 0 : root.fabMargins
        anchors.bottomMargin: root.fabMargins
        iconText: "add"
        buttonText: Translation.tr("Add event")
        baseSize: root.fabSize
        onClicked: root.openInlineEditor(null)
    }
    
    // Listen for triggered events and show notifications
    Connections {
        target: Events
        
        function onEventTriggered(event) {
            const urgency = event.priority === "high" ? 2 : (event.priority === "low" ? 0 : 1)
            Notifications.notify(
                event.title,
                event.description || Translation.tr("Event is now!"),
                Events.getCategoryIcon(event.category),
                "event-" + event.id,
                event.priority === "high" ? 0 : 10000,
                []
            )
        }
        
        function onReminderTriggered(event, minutesBefore) {
            const reminderText = minutesBefore >= 1440 
                ? Translation.tr("Tomorrow")
                : minutesBefore >= 60 
                    ? Translation.tr("In %1 hour(s)").arg(Math.floor(minutesBefore / 60))
                    : Translation.tr("In %1 minutes").arg(minutesBefore)
            
            Notifications.notify(
                Translation.tr("Upcoming: %1").arg(event.title),
                reminderText + (event.description ? " — " + event.description : ""),
                "alarm",
                "event-reminder-" + event.id,
                8000,
                []
            )
        }
    }
}
