pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600
    property bool hideEmbeddedScrollBar: false
    // The roomy Dashboard Weekly Planner uses the same embedded dialog
    // lifecycle as Calendar, but owns an intentionally expanded form layout.
    property bool plannerPresentation: false
    property date plannerViewMonth: new Date()
    property int plannerCalendarRevision: 0
    readonly property var plannerCalendarCells: {
        if (!root.plannerPresentation) return []
        root.plannerCalendarRevision
        const year=root.plannerViewMonth.getFullYear()
        const month=root.plannerViewMonth.getMonth()
        const first=new Date(year,month,1)
        const offset=(first.getDay()+6)%7
        const start=new Date(year,month,1-offset)
        const cells=[]
        for (let i=0;i<42;i++) {
            const date=new Date(start)
            date.setDate(start.getDate()+i)
            const local=Events.getAllEventsForDate(date)
            const external=CalendarSync.getEventsForDate(date) || []
            cells.push({date:date,day:date.getDate(),
                currentMonth:date.getMonth()===month && date.getFullYear()===year,
                today:date.toDateString()===DateTime.clock.date.toDateString(),
                eventCount:local.length+external.length,
                eventColors:local.map(()=>Appearance.colors.colPrimary)
                    .concat(external.map(e=>e.sourceColor || Appearance.colors.colPrimary))})
        }
        return cells
    }
    onEventDateChanged: if (plannerPresentation && !isNaN(eventDate.getTime()))
        plannerViewMonth=new Date(eventDate.getFullYear(),eventDate.getMonth(),1)
    Connections {
        target: Events
        function onEventAdded(event) {root.plannerCalendarRevision++}
        function onEventUpdated(event) {root.plannerCalendarRevision++}
        function onEventRemoved(id) {root.plannerCalendarRevision++}
    }
    Connections {
        target: CalendarSync
        function onEventsUpdated() {root.plannerCalendarRevision++}
    }
    readonly property bool compactEditor: embeddedPresentation && !plannerPresentation
    contentSpacing: root.plannerPresentation ? 12
        : (root.compactEditor ? 4 : 16)
    embeddedBackgroundColor: Appearance.angelEverywhere
        ? Appearance.angel.colGlassPopup
        : Appearance.inirEverywhere ? Appearance.inir.colLayer1
        : Appearance.auroraEverywhere ? Appearance.aurora.colDialogSurface
        : Appearance.colors.colSurfaceContainerHigh

    component EventSectionHeader: WindowDialogSectionHeader {
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: root.embeddedPresentation
            ? Appearance.font.pixelSize.small
            : Appearance.font.pixelSize.large
        font.weight: Font.Medium
    }

    component EventTextField: MaterialTextField {
        // Material's floating-label padding leaves too little room in the
        // compact editor. Keep a single line and size it for the actual font.
        implicitHeight: Math.max(root.compactEditor ? 40 : 52,
            Math.ceil(contentHeight + topPadding + bottomPadding))
        wrapMode: root.compactEditor ? TextInput.NoWrap : TextInput.Wrap
        Binding on topPadding {
            when: root.embeddedPresentation
            value: 8
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    // Popup-only icon control. Standalone/full EventsDialog keeps its existing
    // labelled controls; this is rendered only by embeddedPresentation.
    component CompactEventOptionButton: Button {
        id: compactButton
        property string symbol: ""
        property string tooltipText: ""
        property bool selectedState: false

        implicitWidth: root.compactEditor ? 30 : 36
        implicitHeight: root.compactEditor ? 30 : 36
        padding: 0
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        opacity: compactButton.enabled ? 1 : 0.35
        Accessible.name: tooltipText

        background: Rectangle {
            radius: Appearance.rounding.small
            color: compactButton.selectedState
                ? Appearance.colors.colPrimaryContainer
                : compactButton.hovered || compactButton.activeFocus
                    ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colLayer2
            border.width: compactButton.activeFocus ? 1 : 0
            border.color: Appearance.colors.colPrimary

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve:
                        Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: compactButton.symbol
                iconSize: root.compactEditor ? 15 : 18
                color: compactButton.selectedState
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnSurfaceVariant
            }
        }

        StyledToolTip {
            visible: compactButton.hovered
                && compactButton.tooltipText.length > 0
            text: compactButton.tooltipText
            delay: 350
            position: "top"
        }
    }

    property var editingEvent: null
    property int editingOccurrenceIndex: 0
    property bool isEditing: editingEvent !== null

    // Form state
    property string eventTitle: ""
    property string eventDescription: ""
    property date eventDate: new Date()
    // eventTime remains the start-time compatibility property.
    property string eventTime: "12:00"
    property string eventEndTime: "13:00"
    property bool allDay: false
    property string eventCategory: "general"
    property string eventPriority: "normal"
    property int reminderMinutes: 15
    property string recurrence: "none"
    property string compactOptionGroup: ""
    // Keep a serialized baseline for the embedded Events draft while its
    // view stays loaded behind the Todo and Quick Notes columns.
    property string editorWarning: ""
    property string _cleanFormSnapshot: ""
    function formSnapshot(): string {
        return JSON.stringify([eventTitle,eventDescription,Number(eventDate),
            eventTime,eventEndTime,allDay,eventCategory,eventPriority,
            reminderMinutes,recurrence])
    }
    function captureFormBaseline(): void {
        _cleanFormSnapshot=formSnapshot()
        editorWarning=""
    }
    function hasUnsavedChanges(): bool {
        return _cleanFormSnapshot.length>0 && formSnapshot()!==_cleanFormSnapshot
    }

    function compactOptionsFor(group) {
        if (group === "repeat") {
            return [
                { displayName: Translation.tr("Event"), icon: "event", value: "none" },
                { displayName: Translation.tr("Daily"), icon: "today", value: "daily" },
                { displayName: Translation.tr("Weekly"), icon: "date_range", value: "weekly" },
                { displayName: Translation.tr("Monthly"), icon: "calendar_month", value: "monthly" },
                { displayName: Translation.tr("Yearly"), icon: "event_repeat", value: "yearly" }
            ]
        }
        if (group === "category") {
            return [
                { displayName: Translation.tr("General"), icon: "event", value: "general" },
                { displayName: Translation.tr("Birthday"), icon: "cake", value: "birthday" },
                { displayName: Translation.tr("Meeting"), icon: "groups", value: "meeting" },
                { displayName: Translation.tr("Deadline"), icon: "flag", value: "deadline" },
                { displayName: Translation.tr("Reminder"), icon: "notifications", value: "reminder" }
            ]
        }
        if (group === "priority") {
            return [
                { displayName: Translation.tr("Low"), icon: "arrow_downward", value: "low" },
                { displayName: Translation.tr("Normal"), icon: "remove", value: "normal" },
                { displayName: Translation.tr("High"), icon: "priority_high", value: "high" }
            ]
        }
        return [
            { displayName: Translation.tr("None"), icon: "notifications_off", value: 0 },
            { displayName: Translation.tr("5 min"), icon: "alarm", value: 5 },
            { displayName: Translation.tr("15 min"), icon: "alarm", value: 15 },
            { displayName: Translation.tr("1 hour"), icon: "alarm", value: 60 },
            { displayName: Translation.tr("1 day"), icon: "alarm", value: 1440 }
        ]
    }

    function compactGroupTitle(group): string {
        if (group === "repeat") return Translation.tr("Repeat")
        if (group === "category") return Translation.tr("Category")
        if (group === "priority") return Translation.tr("Priority")
        return Translation.tr("Reminder")
    }

    function compactGroupValue(group) {
        if (group === "repeat") return root.recurrence
        if (group === "category") return root.eventCategory
        if (group === "priority") return root.eventPriority
        return root.reminderMinutes
    }

    function compactSelectedOption(group) {
        const current = root.compactGroupValue(group)
        const options = root.compactOptionsFor(group)
        for (let i = 0; i < options.length; ++i) {
            if (options[i].value == current)
                return options[i]
        }
        return options[0]
    }

    function compactGroupIcon(group): string {
        return root.compactSelectedOption(group)?.icon ?? "tune"
    }

    function compactGroupTooltip(group): string {
        const selected = root.compactSelectedOption(group)
        return root.compactGroupTitle(group) + " · "
            + (selected?.displayName ?? "")
    }

    function setCompactOption(group, value): void {
        if (group === "repeat") root.recurrence = value
        else if (group === "category") root.eventCategory = value
        else if (group === "priority") root.eventPriority = value
        else root.reminderMinutes = value
        root.compactOptionGroup = ""
    }

    function focusEditor(): void {
        Qt.callLater(() => {
            if (root.show && root.visible && root.enabled)
                titleField.forceActiveFocus()
        })
    }

    function resetForm(): void {
        root.editingEvent = null
        root.editingOccurrenceIndex = 0
        root.eventTitle = ""
        root.eventDescription = ""
        root.eventDate = new Date()
        root.eventTime = "12:00"
        root.eventEndTime = "13:00"
        root.allDay = false
        root.eventCategory = "general"
        root.eventPriority = "normal"
        root.reminderMinutes = 15
        root.recurrence = "none"
        root.compactOptionGroup = ""
        root.captureFormBaseline()
    }

    function loadEvent(event: var): void {
        root.editingEvent = event
        root.editingOccurrenceIndex = event._editOccurrenceIndex ?? 0
        const selectedSlot = Array.isArray(event.occurrences)
            ? (event.occurrences[root.editingOccurrenceIndex] || event) : event
        root.eventTitle = event.title || ""
        root.eventDescription = event.description || ""
        const startSource = selectedSlot.startDate || selectedSlot.dateTime
        const startDt = new Date(startSource)
        const safeStart = isNaN(startDt.getTime()) ? new Date() : startDt
        const endDt = selectedSlot.endDate
            ? new Date(selectedSlot.endDate)
            : new Date(safeStart.getTime() + 60 * 60 * 1000)
        const safeEnd = isNaN(endDt.getTime())
            ? new Date(safeStart.getTime() + 60 * 60 * 1000) : endDt
        root.eventDate = safeStart
        root.eventTime = safeStart.getHours().toString().padStart(2, '0')
            + ":" + safeStart.getMinutes().toString().padStart(2, '0')
        root.eventEndTime = safeEnd.getHours().toString().padStart(2, '0')
            + ":" + safeEnd.getMinutes().toString().padStart(2, '0')
        root.allDay = event.allDay === true
        root.eventCategory = event.category || "general"
        root.eventPriority = event.priority || "normal"
        root.reminderMinutes = event.reminderMinutes ?? 15
        root.recurrence = event.recurrence || "none"
        root.compactOptionGroup = ""
        root.captureFormBaseline()
    }

    function saveEvent(): bool {
        if (!Events.ready || root.eventTitle.trim() === "") return false

        const startParts = root.eventTime.split(":")
        const endParts = root.eventEndTime.split(":")
        const startDateTime = new Date(root.eventDate)
        const endDateTime = new Date(root.eventDate)

        if (root.allDay) {
            startDateTime.setHours(0, 0, 0, 0)
            endDateTime.setHours(0, 0, 0, 0)
            endDateTime.setDate(endDateTime.getDate() + 1)
        } else {
            startDateTime.setHours(
                parseInt(startParts[0]) || 0,
                parseInt(startParts[1]) || 0, 0, 0)
            endDateTime.setHours(
                parseInt(endParts[0]) || 0,
                parseInt(endParts[1]) || 0, 0, 0)
            // Treat an end time at/before the start as crossing midnight.
            if (endDateTime.getTime() <= startDateTime.getTime())
                endDateTime.setDate(endDateTime.getDate() + 1)
        }

        const startIso = startDateTime.toISOString()
        const endIso = endDateTime.toISOString()

        if (root.isEditing && Array.isArray(root.editingEvent.occurrences)) {
            // One write preserves the other days and the canonical Todo link.
            // Recurrence edits need a separate series policy; never mix them.
            if (root.recurrence !== "none") return false
            return Events.rescheduleOccurrence(root.editingEvent.id,
                root.editingOccurrenceIndex,startIso,endIso,{
                    title:root.eventTitle.trim(),
                    description:root.eventDescription.trim(),
                    allDay:root.allDay,
                    category:root.eventCategory,
                    priority:root.eventPriority,
                    reminderMinutes:root.reminderMinutes
                })
        }
        if (root.isEditing) {
            return Events.updateEvent(root.editingEvent.id, {
                title: root.eventTitle.trim(),
                description: root.eventDescription.trim(),
                dateTime: startIso,
                startDate: startIso,
                endDate: endIso,
                allDay: root.allDay,
                category: root.eventCategory,
                priority: root.eventPriority,
                reminderMinutes: root.reminderMinutes,
                recurrence: root.recurrence,
                notified: false,
                reminderNotified: false
            })
        }

        return Events.addEvent(
            root.eventTitle.trim(),
            root.eventDescription.trim(),
            startIso,
            root.eventCategory,
            root.eventPriority,
            root.reminderMinutes,
            root.recurrence,
            endIso,
            root.allDay
        ) !== null
    }

    WindowDialogTitle {
        Layout.leftMargin: root.plannerPresentation ? 12 : (root.compactEditor ? 6 : 0)
        Layout.topMargin: root.plannerPresentation ? 10 : 0
        Layout.rightMargin: root.plannerPresentation ? 12 : (root.compactEditor ? 6 : 0)
        text: root.isEditing
            ? Translation.tr("Edit Event")
            : (root.embeddedPresentation
                ? Translation.tr("Add Event")
                : Translation.tr("New Event"))
        font.pixelSize: root.compactEditor
            ? Appearance.font.pixelSize.normal
            : Appearance.font.pixelSize.large
        font.weight: root.embeddedPresentation ? Font.DemiBold : Font.Medium
    }

    WindowDialogSeparator {
        visible: !root.compactEditor
    }

    StyledText {
        visible:root.embeddedPresentation && root.editorWarning.length>0
        Layout.fillWidth:true;Layout.leftMargin:6;Layout.rightMargin:6
        text:root.editorWarning
        color:Appearance.colors.colError
        wrapMode:Text.WordWrap
        font.pixelSize:Appearance.font.pixelSize.small
    }

    // Scrollable content
    Flickable {
        id: editorFlickable
        Layout.fillWidth: true
        Layout.fillHeight: true

        readonly property real embeddedGap: root.plannerPresentation ? 12 : Math.max(4,
            (height - basicInfoColumn.implicitHeight
                - scheduleColumn.implicitHeight
                - compactOptionDeck.height) / 2)

        contentHeight: root.compactEditor
            ? Math.max(height, formColumn.implicitHeight)
            : formColumn.implicitHeight + 18
        Layout.leftMargin: root.plannerPresentation ? 10 : (root.compactEditor ? 6 : 0)
        Layout.rightMargin: root.plannerPresentation ? 10 : (root.compactEditor ? 6 : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            // Hiding the indicator does not disable wheel, touch or keyboard scroll.
            policy: root.hideEmbeddedScrollBar || root.plannerPresentation
                ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
        }

        Column {
            id: formColumn
            width: parent.width
            spacing: root.embeddedPresentation
                ? editorFlickable.embeddedGap : 8

            // ─── Basic Info Section ───────────────────────────────────
            EventSectionHeader {
                visible: !root.compactEditor
                text: Translation.tr("Basic Info")
            }

            WindowDialogSeparator {
                visible: !root.compactEditor
                Layout.topMargin: -22
            }

            Column {
                id: basicInfoColumn
                width: parent.width
                spacing: root.compactEditor ? 4 : 10
                topPadding: root.compactEditor ? 2 : 8

                EventTextField {
                    id: titleField
                    width: parent.width - (root.compactEditor ? 8 : 16)
                    anchors.horizontalCenter: parent.horizontalCenter
                    placeholderText: root.embeddedPresentation
                        ? Translation.tr("Title") + " *"
                        : Translation.tr("Event title") + " *"
                    placeholderTextColor: Appearance.colors.colOnSurface
                    color: Appearance.colors.colOnSurface
                    renderType: Text.QtRendering
                    font.weight: Font.Medium
                    font.hintingPreference: Font.PreferFullHinting
                    text: root.eventTitle
                    onTextChanged: root.eventTitle = text
                }

                EventTextField {
                    width: parent.width - (root.compactEditor ? 8 : 16)
                    anchors.horizontalCenter: parent.horizontalCenter
                    placeholderText: root.embeddedPresentation
                        ? Translation.tr("Note (opt)")
                        : Translation.tr("Description (optional)")
                    text: root.eventDescription
                    onTextChanged: root.eventDescription = text
                }
            }

            // ─── Date & Time Section ──────────────────────────────────
            EventSectionHeader {
                visible: !root.compactEditor
                text: Translation.tr("Date & Time")
                topPadding: root.embeddedPresentation ? 0 : 16
            }

            WindowDialogSeparator {
                visible: !root.compactEditor
                Layout.topMargin: -22
            }

            Column {
                id: scheduleColumn
                width: parent.width
                spacing: root.compactEditor ? 3 : 10
                topPadding: root.compactEditor ? 3 : 4

                // Embedded Calendar already owns the date grid above this sheet.
                // Modal owners keep the self-contained picker.
                DatePicker {
                    visible: !root.embeddedPresentation
                    width: parent.width
                    compact: false
                    selectedDate: root.eventDate
                    onDateSelected: (date) => { root.eventDate = date }
                }

                // Exact shared visual component from Calendar Popup.
                ObsidianMonthCalendar {
                    id: plannerMonthCalendar
                    visible: root.plannerPresentation
                    width: Math.min(parent.width, Math.max(250, implicitWidth))
                    anchors.horizontalCenter: parent.horizontalCenter
                    viewingDate: root.plannerViewMonth
                    today: DateTime.clock.date
                    calendarCells: root.plannerCalendarCells
                    selectedDate: root.eventDate
                    interactiveDays: true
                    showEventDots: true
                    countedEventDots: true
                    maxEventDots: Math.max(0,Math.min(5,
                        Number(Config.options?.calendar?.maxEventDots ?? 3)))
                    onPreviousMonthRequested: {
                        root.plannerViewMonth=new Date(root.plannerViewMonth.getFullYear(),
                            root.plannerViewMonth.getMonth()-1,1)
                    }
                    onNextMonthRequested: {
                        root.plannerViewMonth=new Date(root.plannerViewMonth.getFullYear(),
                            root.plannerViewMonth.getMonth()+1,1)
                    }
                    onTodayRequested: root.eventDate=new Date(DateTime.clock.date)
                    onDayActivated: date=>root.eventDate=date
                }

                RowLayout {
                    visible: root.compactEditor
                    width: parent.width - 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    MaterialSymbol {
                        text: "calendar_month"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.eventDate, "ddd, dd MMM yyyy")
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    CompactEventOptionButton {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        symbol: root.allDay
                            ? "event_available" : "event_busy"
                        selectedState: root.allDay
                        tooltipText: Translation.tr("All day") + " · "
                            + (root.allDay
                                ? Translation.tr("On")
                                : Translation.tr("Off"))
                        onClicked: root.allDay = !root.allDay
                    }
                }

                RowLayout {
                    visible: root.plannerPresentation
                    width: parent.width
                    spacing: 6

                    StyledText {
                        text: Translation.tr("All day")
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledSwitch {
                        Layout.preferredWidth: 34
                        scale: .58
                        checked: root.allDay
                        onToggled: root.allDay=checked
                    }
                    Item {Layout.preferredWidth: 4}
                    ConfigTimeInput {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 74
                        enabled: !root.allDay
                        compact: true
                        icon: ""
                        text: Translation.tr("Start")
                        value: root.eventTime
                        onTimeChanged: newTime=>root.eventTime=newTime
                    }
                    ConfigTimeInput {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 74
                        enabled: !root.allDay
                        compact: true
                        icon: ""
                        text: Translation.tr("End")
                        value: root.eventEndTime
                        onTimeChanged: newTime=>root.eventEndTime=newTime
                    }
                }

                RowLayout {
                    visible: !root.embeddedPresentation
                    width: parent.width - 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    MaterialSymbol {
                        text:"event_available"
                        iconSize:16
                        color:Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth:true
                        text:Translation.tr("All day")
                        color:Appearance.colors.colOnSurface
                        font.pixelSize:Appearance.font.pixelSize.small
                    }
                    StyledSwitch {
                        scale:.58
                        checked:root.allDay
                        onToggled:root.allDay=checked
                    }
                }
                RowLayout {
                    visible: !root.embeddedPresentation || root.compactEditor
                    width: parent.width-(root.compactEditor ? 8 : 0)
                    anchors.horizontalCenter:parent.horizontalCenter
                    spacing:root.compactEditor ? 6 : 8
                    ConfigTimeInput {
                        Layout.fillWidth:true
                        visible:!root.allDay
                        compact:root.compactEditor
                        icon:"schedule"
                        text:Translation.tr("Start")
                        value:root.eventTime
                        onTimeChanged:newTime=>root.eventTime=newTime
                    }
                    ConfigTimeInput {
                        Layout.fillWidth:true
                        visible:!root.allDay
                        compact:root.compactEditor
                        icon:"schedule"
                        text:Translation.tr("End")
                        value:root.eventEndTime
                        onTimeChanged:newTime=>root.eventEndTime=newTime
                    }
                }
            }

            // Embedded Add Event uses one compact icon deck instead of
            // four labelled option sections. Fixed-size buttons keep spacing
            // predictable and avoid crowding the time controls above.
            Item {
                id: compactOptionDeck
                visible: root.compactEditor
                width: parent.width
                height: 32

                RowLayout {
                    visible: root.compactOptionGroup === ""
                    anchors.centerIn: parent
                    spacing: 8

                    Repeater {
                        model: [
                            { key: "repeat" },
                            { key: "category" },
                            { key: "priority" },
                            { key: "reminder" }
                        ]

                        delegate: CompactEventOptionButton {
                            required property var modelData
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            symbol: root.compactGroupIcon(modelData.key)
                            tooltipText: root.compactGroupTooltip(modelData.key)
                            onClicked: root.compactOptionGroup = modelData.key
                        }
                    }
                }

                RowLayout {
                    visible: root.compactOptionGroup !== ""
                    anchors.centerIn: parent
                    spacing: 6

                    CompactEventOptionButton {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        symbol: "arrow_back"
                        tooltipText: Translation.tr("Back")
                        onClicked: root.compactOptionGroup = ""
                    }

                    Repeater {
                        model: root.compactOptionsFor(
                            root.compactOptionGroup)

                        delegate: CompactEventOptionButton {
                            required property var modelData
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            symbol: modelData.icon
                            selectedState: modelData.value
                                == root.compactGroupValue(
                                    root.compactOptionGroup)
                            tooltipText:
                                root.compactGroupTitle(
                                    root.compactOptionGroup)
                                + " · " + modelData.displayName
                            onClicked: root.setCompactOption(
                                root.compactOptionGroup,
                                modelData.value)
                        }
                    }
                }
            }

            // Repeat is part of scheduling, so keep it next to date/time rather
            // than burying it below category/priority/reminder settings.
            EventSectionHeader {
                visible: !root.compactEditor
                text: Translation.tr("Repeat")
                topPadding: root.embeddedPresentation ? 5 : 16
            }

            WindowDialogSeparator {
                visible: !root.compactEditor
                Layout.topMargin: -22
            }

            ConfigSelectionArray {
                visible: !root.compactEditor
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                }
                enableSettingsSearch: false
                activeLabelOnly: root.plannerPresentation
                options: [
                    // "Event" maps to the existing one-time/non-recurring
                    // storage value instead of inventing an incompatible mode.
                    { displayName: Translation.tr("Event"), icon: "event", value: "none" },
                    { displayName: Translation.tr("Daily"), icon: "today", value: "daily" },
                    { displayName: Translation.tr("Weekly"), icon: "date_range", value: "weekly" },
                    { displayName: Translation.tr("Monthly"), icon: "calendar_month", value: "monthly" },
                    { displayName: Translation.tr("Yearly"), icon: "event_repeat", value: "yearly" }
                ]
                currentValue: root.recurrence
                onSelected: (newValue) => { root.recurrence = newValue }
            }

            // ─── Category Section ─────────────────────────────────────
            EventSectionHeader {
                visible: !root.compactEditor
                text: Translation.tr("Category")
                topPadding: root.embeddedPresentation ? 6 : 16
            }

            WindowDialogSeparator {
                visible: !root.compactEditor
                Layout.topMargin: -22
            }

            ConfigSelectionArray {
                visible: !root.compactEditor
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                }
                enableSettingsSearch: false
                activeLabelOnly: root.plannerPresentation
                options: [
                    { displayName: Translation.tr("General"), icon: "event", value: "general" },
                    { displayName: Translation.tr("Birthday"), icon: "cake", value: "birthday" },
                    { displayName: Translation.tr("Meeting"), icon: "groups", value: "meeting" },
                    { displayName: Translation.tr("Deadline"), icon: "flag", value: "deadline" },
                    { displayName: Translation.tr("Reminder"), icon: "notifications", value: "reminder" }
                ]
                currentValue: root.eventCategory
                onSelected: (newValue) => { root.eventCategory = newValue }
            }

            // ─── Priority Section ─────────────────────────────────────
            EventSectionHeader {
                visible: !root.compactEditor
                text: Translation.tr("Priority")
                topPadding: root.embeddedPresentation ? 6 : 16
            }

            WindowDialogSeparator {
                visible: !root.compactEditor
                Layout.topMargin: -22
            }

            ConfigSelectionArray {
                visible: !root.compactEditor
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                }
                enableSettingsSearch: false
                activeLabelOnly: root.plannerPresentation
                options: [
                    { displayName: Translation.tr("Low"), icon: "arrow_downward", value: "low" },
                    { displayName: Translation.tr("Normal"), icon: "remove", value: "normal" },
                    { displayName: Translation.tr("High"), icon: "priority_high", value: "high" }
                ]
                currentValue: root.eventPriority
                onSelected: (newValue) => { root.eventPriority = newValue }
            }

            // ─── Reminder Section ─────────────────────────────────────
            EventSectionHeader {
                visible: !root.compactEditor
                text: Translation.tr("Reminder")
                topPadding: root.embeddedPresentation ? 6 : 16
            }

            WindowDialogSeparator {
                visible: !root.compactEditor
                Layout.topMargin: -22
            }

            ConfigSelectionArray {
                visible: !root.compactEditor
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                }
                enableSettingsSearch: false
                activeLabelOnly: root.plannerPresentation
                options: [
                    { displayName: Translation.tr("None"), icon: "notifications_off", value: 0 },
                    { displayName: Translation.tr("5 min"), icon: "alarm", value: 5 },
                    { displayName: Translation.tr("15 min"), icon: "alarm", value: 15 },
                    { displayName: Translation.tr("1 hour"), icon: "alarm", value: 60 },
                    { displayName: Translation.tr("1 day"), icon: "alarm", value: 1440 }
                ]
                currentValue: root.reminderMinutes
                onSelected: (newValue) => { root.reminderMinutes = newValue }
            }

            // Bottom padding
            Item {
                visible: !root.compactEditor
                width: 1
                height: 16
            }
        }
    }

    WindowDialogSeparator {
        visible: !root.compactEditor
    }

    WindowDialogButtonRow {
        spacing: root.compactEditor ? 6 : 8
        Layout.leftMargin: root.compactEditor ? 6 : -8
        Layout.rightMargin: root.compactEditor ? 6 : -8
        Layout.bottomMargin: root.compactEditor ? 2 : 0

        DialogButton {
            visible: root.isEditing && !root.compactEditor
            enabled: Events.ready
            padding: 14
            implicitHeight: 36
            buttonText: root.editingEvent?.occurrences?.length > 1
                ? Translation.tr("Delete this date") : Translation.tr("Delete")
            onClicked: {
                if (Events.removeOccurrence(root.editingEvent.id, root.editingOccurrenceIndex)) {
                    root.resetForm()
                    root.dismiss()
                }
            }
        }

        CompactEventOptionButton {
            visible: root.compactEditor && root.isEditing
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            enabled: Events.ready
            symbol: "delete"
            tooltipText: root.editingEvent?.occurrences?.length > 1
                ? Translation.tr("Delete this date") : Translation.tr("Delete")
            onClicked: {
                if (Events.removeOccurrence(root.editingEvent.id, root.editingOccurrenceIndex)) {
                    root.resetForm()
                    root.dismiss()
                }
            }
        }

        Item { Layout.fillWidth: true }

        DialogButton {
            visible: !root.compactEditor
            padding: 14
            implicitHeight: 36
            buttonText: Translation.tr("Cancel")
            onClicked: {
                root.resetForm()
                root.dismiss()
            }
        }

        CompactEventOptionButton {
            visible: root.compactEditor
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            symbol: "close"
            tooltipText: Translation.tr("Cancel")
            onClicked: {
                root.resetForm()
                root.dismiss()
            }
        }

        DialogButton {
            visible: !root.compactEditor
            padding: 14
            implicitHeight: 36
            buttonText: root.isEditing
                ? Translation.tr("Save")
                : Translation.tr("Add Event")
            enabled: Events.ready && root.eventTitle.trim() !== ""
            onClicked: {
                if (root.saveEvent()) {
                    root.resetForm()
                    root.dismiss()
                } else {
                    root.editorWarning=Translation.tr("The event could not be saved. Check that it still exists.")
                }
            }
        }

        CompactEventOptionButton {
            visible: root.compactEditor
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            symbol: root.isEditing ? "check" : "add_task"
            selectedState: true
            tooltipText: root.isEditing
                ? Translation.tr("Save")
                : Translation.tr("Add Event")
            enabled: Events.ready && root.eventTitle.trim() !== ""
            onClicked: {
                if (root.saveEvent()) {
                    root.resetForm()
                    root.dismiss()
                } else {
                    root.editorWarning=Translation.tr("The event could not be saved. Check that it still exists.")
                }
            }
        }
    }
}
