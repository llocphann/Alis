#!/usr/bin/env python3
"""Regression contract for Clock Calendar / Weather ownership."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEATHER_CONTENT = ROOT / "modules/bar/weather/WeatherPopupContent.qml"
ORBITAL_WEATHER = ROOT / "modules/bar/weather/OrbitalWeather.qml"
DASH_WEATHER = ROOT / "modules/dashboard/DashWeather.qml"
DASH_CALENDAR = ROOT / "modules/dashboard/DashCalendar.qml"
WEATHER_POPUP = ROOT / "modules/bar/weather/WeatherPopup.qml"
CLOCK = ROOT / "modules/bar/ClockWidget.qml"
CALENDAR_POPUP = ROOT / "modules/bar/ClockCalendarPopup.qml"
CALENDAR_CONTENT = ROOT / "modules/bar/ClockCalendarContent.qml"
EVENTS_WIDGET = ROOT / "modules/sidebarRight/events/EventsWidget.qml"
EVENTS_DIALOG = ROOT / "modules/sidebarRight/events/EventsDialog.qml"
EVENTS_SERVICE = ROOT / "services/Events.qml"
WINDOW_DIALOG = ROOT / "modules/common/widgets/WindowDialog.qml"
DATE_PICKER = ROOT / "modules/common/widgets/DatePicker.qml"
CONFIG_TIME_INPUT = ROOT / "modules/common/widgets/ConfigTimeInput.qml"
SHARED_MONTH = ROOT / "modules/common/widgets/ObsidianMonthCalendar.qml"
SIDEBAR_CALENDAR = ROOT / "modules/sidebarRight/calendar/CalendarWidget.qml"
CLOCK_TOOLTIP = ROOT / "modules/bar/ClockWidgetTooltip.qml"
VERTICAL = ROOT / "modules/verticalBar/VerticalBarContent.qml"

def require(text: str, token: str, source: str) -> None:
    if token not in text:
        raise AssertionError(f"{source} is missing Clock Calendar / Weather contract token: {token!r}")

def forbid(text: str, token: str, source: str) -> None:
    if token in text:
        raise AssertionError(f"{source} contains retired Clock Calendar / Weather token: {token!r}")

def main() -> None:
    weather = WEATHER_CONTENT.read_text(encoding="utf-8")
    orbital_weather = ORBITAL_WEATHER.read_text(encoding="utf-8")
    dash_weather = DASH_WEATHER.read_text(encoding="utf-8")
    dash_calendar = DASH_CALENDAR.read_text(encoding="utf-8")
    weather_popup = WEATHER_POPUP.read_text(encoding="utf-8")
    clock = CLOCK.read_text(encoding="utf-8")
    calendar_popup = CALENDAR_POPUP.read_text(encoding="utf-8")
    calendar = CALENDAR_CONTENT.read_text(encoding="utf-8")
    events_widget = EVENTS_WIDGET.read_text(encoding="utf-8")
    events_dialog = EVENTS_DIALOG.read_text(encoding="utf-8")
    events_service = EVENTS_SERVICE.read_text(encoding="utf-8")
    window_dialog = WINDOW_DIALOG.read_text(encoding="utf-8")
    date_picker = DATE_PICKER.read_text(encoding="utf-8")
    config_time_input = CONFIG_TIME_INPUT.read_text(encoding="utf-8")
    shared_month = SHARED_MONTH.read_text(encoding="utf-8")
    sidebar_calendar = SIDEBAR_CALENDAR.read_text(encoding="utf-8")
    vertical = VERTICAL.read_text(encoding="utf-8")

    if CLOCK_TOOLTIP.exists():
        raise AssertionError("retired ClockWidgetTooltip.qml must not return")

    for token in ("id: clockHoverArea", "ClockCalendarPopup {", "hoverTarget: clockHoverArea"):
        require(clock, token, "ClockWidget.qml")
    require(calendar_popup, "StyledPopup {", "ClockCalendarPopup.qml")
    require(calendar_popup, "ClockCalendarContent {", "ClockCalendarPopup.qml")
    forbid(calendar_popup, "PopupWindow", "ClockCalendarPopup.qml")

    for token in (
        "id: popupContent",
        "implicitWidth: calendarContent.implicitWidth",
        "implicitHeight: calendarContent.implicitHeight",
        "ClockCalendarContent {",
        "anchors.fill: parent",
        "alternativeVisibleCondition: calendarContent.eventEditorActive",
        "keyboardFocus: calendarContent.eventEditorActive",
        "onRequestClose: calendarContent.closeEventEditor()",
    ):
        require(calendar_popup, token, "ClockCalendarPopup.qml")
    for retired in (
        "showEventsDialog",
        "editorPaneHeight",
        "id: editorPane",
        "EventsDialog {",
        "Behavior on implicitHeight",
    ):
        forbid(calendar_popup, retired,
               "ClockCalendarPopup must stay fixed-size while Events edits inline")

    for token in (
        "property bool embeddedPresentation: false",
        "property real contentSpacing: 16",
        'property color embeddedBackgroundColor: "transparent"',
        "? root.embeddedBackgroundColor",
        "spacing: root.contentSpacing",
        "visible: !root.effectiveEmbedded",
        "x: root.effectiveEmbedded",
        "width: root.effectiveEmbedded",
        "height: root.effectiveEmbedded",
    ):
        require(window_dialog, token, "WindowDialog.qml")

    for token in (
        "function focusEditor(): void",
        "id: titleField",
        "id: editorFlickable",
        "readonly property bool compactEditor: embeddedPresentation && !plannerPresentation",
        "readonly property real embeddedGap: root.plannerPresentation ? 12 : Math.max(4,",
        "? Math.max(height, formColumn.implicitHeight)",
        "? editorFlickable.embeddedGap : 8",
        "id: basicInfoColumn",
        "id: scheduleColumn",
        "contentSpacing: root.plannerPresentation ? 12\n        : (root.compactEditor ? 4 : 16)",
        "embeddedBackgroundColor:",
        "component EventSectionHeader: WindowDialogSectionHeader",
        "Appearance.colors.colSurfaceContainerHigh",
        "visible: !root.compactEditor",
        'Translation.tr("Title") + " *"',
        'Translation.tr("Note (opt)")',
        "compact:root.compactEditor",
        "property string eventEndTime:",
        "property bool allDay: false",
        'property string compactOptionGroup: ""',
        "component CompactEventOptionButton: Button",
        "renderType: Text.QtRendering",
        "font.weight: Font.Medium",
        '? Translation.tr("Add Event")',
        ': Translation.tr("New Event"))',
        "placeholderTextColor: Appearance.colors.colOnSurface",
        "DatePicker {",
        "compact: false",
        'text:Translation.tr("All day")',
        'text: Translation.tr("Start")',
        'text: Translation.tr("End")',
        'text: Translation.tr("Repeat")',
        '{ displayName: Translation.tr("Event"), icon: "event", value: "none" }',
        '{ displayName: Translation.tr("Daily"), icon: "today", value: "daily"',
        '{ displayName: Translation.tr("Weekly"), icon: "date_range", value: "weekly"',
        '{ displayName: Translation.tr("Monthly"), icon: "calendar_month", value: "monthly"',
        '{ displayName: Translation.tr("Yearly"), icon: "event_repeat", value: "yearly"',
        "startDate: startIso",
        "endDate: endIso",
        "allDay: root.allDay",
    ):
        require(events_dialog, token, "EventsDialog.qml")
    forbid(events_dialog,
           "component EventSectionHeader: EventSectionHeader",
           "EventsDialog.qml")

    compact_deck_start = events_dialog.find(
        "// Embedded Add Event uses one compact icon deck")
    compact_deck_end = events_dialog.find(
        "// Repeat: stable, evenly sized option card", compact_deck_start)
    if compact_deck_start < 0 or compact_deck_end < 0:
        raise AssertionError("EventsDialog compact embedded option deck missing")
    compact_deck = events_dialog[compact_deck_start:compact_deck_end]
    for token in (
        "id: compactOptionDeck",
        "visible: root.compactEditor",
        "height: 32",
        "anchors.centerIn: parent",
        "spacing: 8",
        "spacing: 6",
        "Layout.preferredWidth: 30",
        "Layout.preferredHeight: 30",
        'root.compactOptionGroup === ""',
        "root.compactGroupIcon(modelData.key)",
        "root.compactGroupTooltip(modelData.key)",
        'symbol: "arrow_back"',
        "root.compactOptionsFor(",
        "modelData.value",
        "root.setCompactOption(",
    ):
        require(compact_deck, token, "EventsDialog compact embedded option deck")
    for retired in (
        "Layout.fillWidth: true",
        "Layout.fillHeight: true",
        "spacing: 0",
        "parent.modelData.key",
        "parent.modelData.value",
    ):
        forbid(compact_deck, retired,
               "EventsDialog compact option controls must stay tightly grouped")

    require(events_dialog, "delay: 350", "EventsDialog compact option tooltip")
    require(events_dialog,
            'tooltipText: Translation.tr("All day") + " · "',
            "EventsDialog compact all-day icon")
    require(events_dialog,
            "visible: !root.embeddedPresentation\n                    width: parent.width - 8",
            "EventsDialog standalone all-day row")


    for token in (
        'symbol: "close"',
        'symbol: root.isEditing ? "check" : "event_available"',
        'tooltipText: Translation.tr("Cancel")',
        "selectedState: true",
        "visible: !root.embeddedPresentation",
    ):
        require(events_dialog, token, "EventsDialog compact action row")

    legacy_options = events_dialog[compact_deck_end:]
    if legacy_options.count("ConfigSelectionArray {") < 4:
        raise AssertionError(
            "EventsDialog standalone option arrays were removed by compact popup refactor")
    if legacy_options.count("visible: !root.compactEditor") < 8:
        raise AssertionError(
            "EventsDialog legacy option sections must stay standalone/planner-only")

    date_picker_pos = events_dialog.find("DatePicker {")
    category_pos = events_dialog.find("// Category: stable, evenly sized option card")
    if date_picker_pos < 0 or category_pos < 0 or date_picker_pos > category_pos:
        raise AssertionError("EventsDialog scheduling controls must stay before category metadata")
    date_picker_block = events_dialog[date_picker_pos:category_pos]
    require(date_picker_block, "visible: !root.embeddedPresentation", "EventsDialog embedded date reuse")
    require(date_picker_block, "Qt.formatDate(root.eventDate", "EventsDialog embedded selected-date summary")
    require(date_picker_block, "StyledSwitch {", "EventsDialog all-day control")
    date_picker_component = date_picker_block[
        :date_picker_block.find("RowLayout {")]
    forbid(date_picker_component,
           "compact: root.embeddedPresentation",
           "EventsDialog duplicate embedded calendar")

    for token in (
        "function addEvent(title, description, dateTime, category, priority, reminderMinutes, recurrence, endDate, allDay",
        "startDate: startIso",
        'const firstEnd=bulk ? explicitSlots[0].endDate : (endDate || "")',
        "endDate: firstEnd",
        "allDay: allDay === true",
        "event.allDay === true",
        "durationMs",
        "nextEnd",
    ):
        require(events_service, token, "services/Events.qml")

    for token in (
        "property bool compact: false",
        "root.compact ? 4 : 16",
        "spacing: root.compact ? 3 : 8",
        "implicitHeight: root.compact ? 22 : 28",
        "Layout.preferredWidth: root.compact ? 24 : 32",
        "implicitWidth: root.compact ? 24 : 32",
        "weekCells.some(cell => cell?.isCurrentMonth === true)",
        "visible: !root.compact || containsCurrentMonth",
    ):
        require(date_picker, token, "DatePicker.qml")


    for token in (
        "property bool compact: false",
        "spacing: root.compact ? 4 : 10",
        "Layout.leftMargin: root.compact ? 4 : 8",
        "iconSize: root.compact ? 16",
        "Layout.preferredHeight: root.compact ? 30 : 35",
    ):
        require(config_time_input, token, "ConfigTimeInput.qml")

    for token in (
        "property int monthShift: 0",
        "for (let i = 0; i < 42; ++i)",
        "ObsidianMonthCalendar {",
        "property bool eventDateSelectionEnabled: false",
        "property var selectedEventDate: null",
        "id: eventsPane",
        "readonly property bool eventEditorActive: eventsPane.inlineEditorMode",
        "function closeEventEditor(): void",
        "selectedDate: eventsPane.inlineEditorMode",
        "? eventsPane.inlineEditorDate",
        "interactiveDays: true",
        "eventsPane.setInlineEditorDate(date)",
        "eventsPane.openInlineEditor(date)",
        "anchors.horizontalCenter: parent.horizontalCenter",
        "fabSize: 36",
        "fabMargins: 10",
        "fabLeftAligned: true",
        "readonly property real paneWidth:",
        "implicitWidth: root.paneWidth * 2 + 25",
        "Layout.preferredWidth: root.paneWidth",
        "Layout.preferredHeight: Math.max(120, root.height - 64)",
        "Layout.alignment: Qt.AlignVCenter",
        "color: Appearance.colors.colPrimary",
        "opacity: 0.28",
    ):
        require(calendar, token, "ClockCalendarContent.qml")

    require(events_widget, 'text: Translation.tr("Events")', "EventsWidget.qml")
    forbid(events_widget, 'text: Translation.tr("Events & Reminders")', "EventsWidget.qml")

    for token in (
        "property bool inlineEditorMode: false",
        "readonly property var inlineEditorDate:",
        "function openInlineEditor(editEvent): void",
        "function closeInlineEditor(): void",
        "function setInlineEditorDate(date): void",
        "visible: !root.inlineEditorMode",
        "root.openInlineEditor(\n                                    modelData._canonicalEvent ?? evt)",
        "EventsDialog {",
        "id: inlineEditor",
        "show: root.inlineEditorMode",
        "embeddedPresentation: true",
        'embeddedBackgroundColor: "transparent"',
        "backgroundHeight: -1",
        "onDismiss: root.closeInlineEditor()",
        "onClicked: root.openInlineEditor(null)",
        "property int fabSize: 48",
        "property int fabMargins: 14",
        "property bool fabLeftAligned: false",
        "anchors.left: root.fabLeftAligned ? parent.left : undefined",
        "anchors.right: root.fabLeftAligned ? undefined : parent.right",
    ):
        require(events_widget, token, "EventsWidget.qml")

    for token in (
        "import qs.services",
        "id: calendarHeader",
        "Layout.preferredWidth: calendarBody.implicitWidth",
        "id: mondayMeasure",
        "property var selectedDate: null",
        "function sameDay(a, b): bool",
        "readonly property bool selected: root.multiSelectedDates.length>0",
        ": root.sameDay(dayCell.modelData?.date, root.selectedDate)",
        "Appearance.colors.colPrimaryContainer",
        "Appearance.colors.colOnPrimaryContainer",
        "property bool responsive: false",
        "property real responsiveMinCellSize: 30",
        "property real responsiveMaxCellSize: 42",
        "property real responsiveAvailableHeight: 0",
        "property bool autoWeekNumbers: false",
        "readonly property bool effectiveWeekNumbers:",
        "function isoWeekNumber(value): int",
        'text: Translation.tr("WK")',
        'root.locale.toString(root.viewingDate, "MMM")',
        'root.locale.toString(root.viewingDate, "yyyy")',
        'Translation.tr("Today").toUpperCase()',
        "readonly property bool currentMonth:",
        "opacity: 1",
        "color: todayButton.currentMonth ? root.colMuted : root.colAccent",
        'iconName: "chevron_left"',
        'iconName: "chevron_right"',
        "opacity: dayCell.modelData?.currentMonth === false\n                            && !dayCell.selected ? 0.25 : 1",
    ):
        require(shared_month, token, "ObsidianMonthCalendar.qml")

    for token in (
        "ObsidianMonthCalendar {",
        "calendarCells: root.monthCells",
        "Layout.fillWidth: true",
        "responsive: true",
        "property bool dashboardAdaptive: false",
        "responsiveMinCellSize: root.dashboardAdaptive ? 24 : 30",
        "responsiveMaxCellSize: root.dashboardAdaptive ? 56 : 42",
        "autoWeekNumbers: root.dashboardAdaptive",
        "interactiveDays: true",
        "showEventDots: !root.dashboardAdaptive || root.maxEventDots > 0",
        "CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, 1)",
    ):
        require(sidebar_calendar, token, "Sidebar CalendarWidget.qml")

    forbid(shared_month,
           "todayButton.opacity < 1 ? root.colMuted : root.colAccent",
           "ObsidianMonthCalendar.qml")

    for token in (
        "CalendarDayButton {",
        "id: todayCol",
        'locale.toString(viewingDate, "MMMM")',
    ):
        forbid(sidebar_calendar, token, "Sidebar CalendarWidget.qml")

    for token in ("StyledPopup {", "id: weatherContent", "root.presentationWindow?.width"):
        require(weather_popup, token, "WeatherPopup.qml")
    for token in (
        "readonly property real compactBreakpoint: 900",
        "readonly property int tabCount: 2",
        "property int currentTab: 0",
        "id: tabIndicator",
        "anchors.right: parent.right",
        "Behavior on tabPosition",
        "WheelHandler {",
        "id: timeWeatherPanel",
        "OrbitalWeather {",
        "id: orbitalTimeline",
        "readonly property real panelWidth: root.compact ? 360 : 390",
        "readonly property real orbitalInset: root.compact ? 6 : 8",
        "readonly property real orbitalRightInset: root.orbitalInset",
        "leftMargin: root.orbitalInset",
        "rightMargin: root.orbitalRightInset",
        "topMargin: root.orbitalInset",
        "bottomMargin: root.orbitalInset",
        "id: detailPanel",
        "id: detailSummary",
        "id: primaryMetrics",
        "id: sunTimeline",
    ):
        require(weather, token, "WeatherPopupContent.qml")
    for token in (
        "(Weather.data?.hourly ?? []).slice(0, 8)",
        "function hourFromLabel(label): real",
        "function arcAngle(startAngle, endAngle, fraction, tables): real",
        "function orbitAngleForHour(label, tables): real",
        "readonly property real pointWidth:",
        "readonly property real pointHeight:",
    ):
        require(orbital_weather, token, "OrbitalWeather.qml")
    require(dash_weather, "OrbitalWeather {", "DashWeather.qml")
    require(dash_calendar, "dashboardAdaptive: true", "DashCalendar.qml")
    for token in ("id: calendarPanel", "function calendarDay(index)", "columns: root.compact ? 1 : 2", "columns: root.compact ? 1 : 3"):
        forbid(weather, token, "WeatherPopupContent.qml")
    forbid(weather, "anchors.topMargin: -12", "WeatherPopupContent.qml")

    for token in ("component VerticalClockModule: Item", "Bar.ClockCalendarPopup {", "hoverTarget: clockHoverArea"):
        require(vertical, token, "VerticalBarContent.qml")

    print("Clock Calendar / Weather ownership contract: PASS")

if __name__ == "__main__":
    main()
