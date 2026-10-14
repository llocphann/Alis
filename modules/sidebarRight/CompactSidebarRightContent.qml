// CompactSidebarRightContent.qml
//
// Two-column compact sidebar:
//   Left rail  (54 px) — icon navigation + system actions
//   Right area          — active section fills the rest
//
// Sections:
//   0 = Controls  (sliders + quick toggles)
//   1+ = Widgets  (calendar / events / todo / notepad / calc / sysmon / timer)
//
// Notification history is intentionally owned by the standalone bottom-right
// Notification Center; the compact sidebar keeps only notification policy
// controls such as Do Not Disturb.
//
// Global Theme chrome is Material-only; the explicit Ricelin island skin remains supported.

import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.perimeter
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.mediaControls
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects as GE

import qs.modules.sidebarRight.quickToggles
import qs.modules.sidebarRight.quickToggles.classicStyle
import qs.modules.sidebarRight.bluetoothDevices
import qs.modules.sidebarRight.nightLight
import qs.modules.sidebarRight.hotspot
import qs.modules.sidebarRight.volumeMixer
import qs.modules.sidebarRight.wifiNetworks
import qs.modules.sidebarLeft.widgets

import qs.modules.sidebarRight.calendar
import qs.modules.sidebarRight.todo
import qs.modules.sidebarRight.pomodoro
import qs.modules.sidebarRight.notepad
import qs.modules.sidebarRight.calculator
import qs.modules.sidebarRight.sysmon
import qs.modules.sidebarRight.events
import qs.modules.sidebarRight.weather

Item {
    id: root

    // ── Public API (same as SidebarRightContent) ──────────────────
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property int screenWidth: 1920
    property int screenHeight: 1080
    property var panelScreen: null
    property real panelScreenY: Appearance.sizes.hyprlandGapsOut
    property bool externalConnectedSurface: false
    readonly property color connectedSurfaceColor:
        bg.cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0
    readonly property real connectedSurfaceRadius: bg.radius
    property bool panelVisible: false
    property bool geometryPreviewActive: false
    property string attachedEdge: "right"

    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showEventsDialog: false
    property bool showHotspotDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property bool layoutEditMode: false // Edit mode for reordering Controls sections
    property var eventsDialogEditEvent: null
    property bool reloadButtonEnabled: true
    property bool settingsButtonEnabled: true
    readonly property real preferredContentHeight: Math.max(520,
        root.screenHeight * SidebarGeometry.rightFitExpandedPreferredRatio)
    readonly property real minimumUsefulHeight: Math.max(420,
        root.screenHeight * SidebarGeometry.rightFitExpandedMinRatio)
    readonly property real minimumUsefulWidth: 360
    readonly property real maximumUsefulWidth: 900
    readonly property bool compactTightHeight: height > 0 && height < 760
    readonly property bool compactNarrowWidth: width > 0 && width < 420
    readonly property int compactPanelPadding: Math.max(6, Math.min(sidebarPadding, Math.round(Math.min(width || sidebarWidth, height || screenHeight) * 0.018)))
    readonly property int compactContentPadding: Math.max(6, Math.min(10, compactPanelPadding))
    readonly property int compactRailWidth: Math.max(50, Math.min(58, Math.round((width || sidebarWidth) * 0.13)))
    readonly property int compactRailMargin: Math.max(6, Math.min(9, Math.round(compactRailWidth * 0.15)))
    readonly property int compactNavItemHeight: compactTightHeight ? 40 : 46
    readonly property int compactNavBgHeight: compactTightHeight ? 34 : 38
    readonly property int compactNavSpacing: compactTightHeight ? 2 : 4
    readonly property int compactActionItemHeight: compactTightHeight ? 36 : 40
    readonly property int compactActionBgHeight: compactTightHeight ? 30 : 34
    readonly property int compactSectionSpacing: compactTightHeight ? Appearance.sizes.spacingSmall : Appearance.sizes.spacingMedium
    readonly property int compactGridSpacing: compactNarrowWidth ? 4 : 5

    // Controls section order from config
    readonly property var defaultSectionOrder: ["sliders", "toggles", "devices", "media", "quickActions"]
    property var controlsSectionOrder: Config.options?.sidebar?.right?.controlsSectionOrder ?? defaultSectionOrder

    function moveSectionUp(index: int): void {
        if (index <= 0) return
        let order = [...root.controlsSectionOrder]
        const temp = order[index - 1]
        order[index - 1] = order[index]
        order[index] = temp
        root.controlsSectionOrder = order
        Config.setNestedValue("sidebar.right.controlsSectionOrder", order)
    }

    function moveSectionDown(index: int): void {
        if (index >= root.controlsSectionOrder.length - 1) return
        let order = [...root.controlsSectionOrder]
        const temp = order[index + 1]
        order[index + 1] = order[index]
        order[index] = temp
        root.controlsSectionOrder = order
        Config.setNestedValue("sidebar.right.controlsSectionOrder", order)
    }

    // Persist a stable section id. Older builds stored a numeric tab index;
    // migration below maps the retired Notifications slot away once.
    property int activeSection: 0
    property bool compactSectionRestored: false

    function persistActiveSection(): void {
        if (!root.compactSectionRestored)
            return
        const state = Persistent.states?.sidebar?.compactGroup
        const section = root.sections[root.activeSection]
        if (!state || !section)
            return
        state.sectionId = section.id
        // Keep the legacy field coherent for downgrade compatibility, but it is
        // no longer authoritative.
        state.tab = root.activeSection
    }

    function restoreActiveSection(): void {
        const state = Persistent.states?.sidebar?.compactGroup
        let idx = -1
        const savedId = String(state?.sectionId ?? "")
        if (savedId.length > 0)
            idx = root.sections.findIndex(section => section.id === savedId)

        if (idx < 0 && savedId.length === 0) {
            const legacy = Math.max(0, Number(state?.tab ?? 0))
            // Old order: controls=0, notifications=1, widgets started at 2.
            // New order: controls=0, widgets start at 1.
            idx = legacy <= 1 ? 0 : legacy - 1
        }

        root.activeSection = Math.max(0,
            Math.min(idx < 0 ? 0 : idx, Math.max(0, root.sections.length - 1)))
        root.compactSectionRestored = true
        root.persistActiveSection()
    }

    onActiveSectionChanged: {
        root.persistActiveSection()
        Qt.callLater(() => {
            // Focus the newly active section's content
            const idx = activeSection
            if (idx >= 0 && idx < sectionRepeater.count) {
                const item = sectionRepeater.itemAt(idx)
                if (item && item.sectionLoader && item.sectionLoader.item) {
                    item.sectionLoader.item.forceActiveFocus()
                }
            }
        })
    }

    onSectionsChanged: {
        if (!root.compactSectionRestored)
            return
        const savedId = String(
            Persistent.states?.sidebar?.compactGroup?.sectionId ?? "")
        const idx = root.sections.findIndex(section => section.id === savedId)
        root.activeSection = idx >= 0 ? idx : 0
    }

    function handleRequestedWidget(): void {
        const w = GlobalStates.sidebarRightRequestedWidget
        if (!w) return
        const idx = root.sections.findIndex(s => s.id === w)
        if (idx !== -1) root.activeSection = idx
        GlobalStates.sidebarRightRequestedWidget = ""
    }

    Component.onCompleted: {
        Notifications.ensureInitialized()
        restoreActiveSection()
        handleRequestedWidget()
    }

    Connections {
        target: GlobalStates
        function onSidebarRightRequestedWidgetChanged() {
            root.handleRequestedWidget()
        }
    }

    property int configVersion: 0
    Connections {
        target: Config
        function onConfigChanged() { root.configVersion++ }
    }

    // ── Section definitions ───────────────────────────────────────
    readonly property var baseSections: [
        { id: "controls", icon: "tune", label: Translation.tr("Controls") },
    ]

    component CompactContentSurface: Rectangle {
        id: surface

        default property alias content: contentHolder.data

        anchors.margins: root.compactContentPadding
        radius: 0
        color: "transparent"
        border.width: 0
        border.color: "transparent"
        clip: false

        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }

    Component {
        id: calendarComponent
        Item {
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.compactContentPadding
                spacing: root.compactNavSpacing

                // Calendar grid card
                Item {
                    Layout.fillWidth: true
                    implicitHeight: calendarSurface.implicitHeight

                    StyledRectangularShadow {
                        target: calendarSurface
                        visible: false
                        blur: 0.35 * Appearance.sizes.elevationMargin
                    }

                    Rectangle {
                        id: calendarSurface
                        anchors.fill: parent
                        implicitHeight: calWidget.implicitHeight + 12
                        radius: 0
                        color: "transparent"
                        border.width: 0
                        Behavior on border.width {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        border.color: "transparent"
                        clip: false

                        CalendarWidget {
                            id: calWidget
                            anchors.fill: parent
                            anchors.margins: root.compactGridSpacing
                            onDayWithEventsClicked: (date) => {
                                const eventsIdx = root.sections.findIndex(s => s.id === "events")
                                if (eventsIdx !== -1) root.activeSection = eventsIdx
                            }
                            onOpenEventsDialog: (editEvent) => {
                                const eventsIdx = root.sections.findIndex(s => s.id === "events")
                                if (eventsIdx !== -1) root.activeSection = eventsIdx
                            }
                        }
                    }
                }

                // Upcoming events below the calendar
                Item {
                    id: upcomingArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property color _colText: Appearance.colors.colOnLayer1
                    readonly property color _colSub: Appearance.colors.colSubtext
                    readonly property color _colPrimary: Appearance.colors.colPrimary

                    // Merged upcoming events (next 14 days)
                    property int _eventsTrigger: 0
                    Connections {
                        target: Events
                        function onEventAdded(event) { upcomingArea._eventsTrigger++ }
                        function onEventRemoved(id) { upcomingArea._eventsTrigger++ }
                        function onEventUpdated(event) { upcomingArea._eventsTrigger++ }
                    }
                    property int _externalTrigger: 0
                    Connections {
                        target: CalendarSync
                        function onEventsUpdated() { upcomingArea._externalTrigger++ }
                    }
                    readonly property var upcomingEvents: {
                        const _t = _eventsTrigger
                        const _t2 = _externalTrigger
                        const now = new Date()
                        const all = []
                        const local = Events.getUpcomingEvents(14)
                        for (const e of local)
                            all.push(Object.assign({}, e, { _source: "local" }))

                        const startDay = new Date(now); startDay.setHours(0,0,0,0)
                        const dates = []
                        for (let i = 0; i < 14; i++) {
                            const d = new Date(startDay); d.setDate(d.getDate() + i)
                            dates.push(d)
                        }
                        const externalBuckets = CalendarSync._getEventBucketsForDates(dates)
                        for (let i = 0; i < externalBuckets.length; i++) {
                            const dayEvts = externalBuckets[i] || []
                            for (const e of dayEvts) {
                                const evtTime = new Date(e.startDate || e.dateTime)
                                if (evtTime >= now || (e.allDay && evtTime >= startDay))
                                    all.push(Object.assign({}, e, { _source: "external", dateTime: e.startDate || e.dateTime, category: "general", priority: "normal" }))
                            }
                        }
                        all.sort((a,b) => new Date(a.dateTime || a.startDate) - new Date(b.dateTime || b.startDate))
                        return all
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // "Upcoming" header
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Appearance.sizes.spacingSmall
                            spacing: root.compactGridSpacing

                            MaterialSymbol {
                                text: "event_upcoming"
                                iconSize: 16
                                fill: 1
                                color: upcomingArea._colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Upcoming")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: upcomingArea._colText
                            }
                        }

                        // Event list or empty hint
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: upcomingCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                            ColumnLayout {
                                id: upcomingCol
                                width: parent.width
                                spacing: root.compactNavSpacing

                                Repeater {
                                    model: upcomingArea.upcomingEvents.slice(0, 8)
                                    delegate: EventCard {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        event: modelData
                                        isExternal: (modelData?._source ?? "local") === "external"
                                        onEditClicked: (evt) => {
                                            if (!isExternal) {
                                                root.eventsDialogEditEvent = evt
                                                root.showEventsDialog = true
                                            }
                                        }
                                        onRemoveClicked: {
                                            if (!isExternal) Events.removeEvent(modelData.id)
                                        }
                                    }
                                }

                                // Empty state
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 60
                                    visible: upcomingArea.upcomingEvents.length === 0

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: Translation.tr("No upcoming events")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: upcomingArea._colSub
                                        opacity: 0.7
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: eventsComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: eventsSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: eventsSurface
                anchors.fill: parent

                EventsWidget {
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                    onOpenEventsDialog: (editEvent) => {
                        root.eventsDialogEditEvent = editEvent
                        root.showEventsDialog = true
                    }
                }
            }
        }
    }
    Component {
        id: todoComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: todoSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: todoSurface
                anchors.fill: parent

                TodoWidget {
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                }
            }
        }
    }
    Component {
        id: notepadComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: notepadSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: notepadSurface
                anchors.fill: parent

                NotepadWidget {
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                }
            }
        }
    }
    Component {
        id: calculatorComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: calculatorSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: calculatorSurface
                anchors.fill: parent

                CalculatorWidget {
                    compactMode: true
                    centerContentVertically: true
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                }
            }
        }
    }
    Component {
        id: sysmonComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: sysmonSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: sysmonSurface
                anchors.fill: parent

                SysMonWidget {
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                }
            }
        }
    }
    Component {
        id: timerComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: timerSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: timerSurface
                anchors.fill: parent

                PomodoroWidget {
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                    compactMode: true
                }
            }
        }
    }
    Component {
        id: weatherDetailComponent
        Item {
            anchors.fill: parent

            StyledRectangularShadow {
                target: weatherSurface
                visible: false
                blur: 0.35 * Appearance.sizes.elevationMargin
            }

            CompactContentSurface {
                id: weatherSurface
                anchors.fill: parent

                StyledFlickable {
                    anchors.fill: parent
                    anchors.margins: root.compactGridSpacing
                    contentHeight: weatherDetailItem.implicitHeight
                    clip: true

                    WeatherDetailWidget {
                        id: weatherDetailItem
                        width: parent.width
                        margin: root.compactGridSpacing
                    }
                }
            }
        }
    }

    component ControlChipButton: Item {
        id: chip
        required property string chipIcon
        required property string chipLabel
        property string value: ""

        signal clicked()

        implicitHeight: 48

        // Style helpers
        readonly property color _colPrimary: Appearance.colors.colPrimary
        readonly property color _colText: Appearance.colors.colOnLayer1
        readonly property color _colSub: Appearance.colors.colSubtext

        Rectangle {
            id: chipBg
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: {
                if (chipMA.containsPress)
                    return bg.colDarkSurfaceActive
                if (chipMA.containsMouse)
                    return bg.colDarkSurfaceHover
                return "transparent"
            }
            border.width: 0

            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 9

                // Icon in accent-tinted circle
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: ColorUtils.transparentize(chip._colPrimary, 0.84)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 17
                        text: chip.chipIcon
                        color: chip._colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: chip.chipLabel
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: chip._colText
                        elide: Text.ElideRight
                    }

                    Revealer {
                        vertical: true
                        reveal: chip.value !== ""
                        Layout.fillWidth: true
                        StyledText {
                            text: chip.value
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: chip._colSub
                            elide: Text.ElideRight
                        }
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    iconSize: 14
                    text: "chevron_right"
                    color: chip._colSub
                    opacity: chipMA.containsMouse ? 0.9 : 0.5
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                }
            }

            MouseArea {
                id: chipMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.clicked()
            }
        }

        BubbleToolTip {
            visible: chipMA.containsMouse
            position: "left"
            text: chip.chipLabel
        }
    }

    readonly property var widgetSections: {
        root.configVersion // Force dependency
        const enabled = Config.options?.sidebar?.right?.enabledWidgets ?? ["calculator", "sysmon"]
        const all = [
            {id: "calculator", icon: "calculate",     label: Translation.tr("Calc"),       component: calculatorComponent},
            {id: "sysmon",     icon: "monitor_heart", label: Translation.tr("System"),     component: sysmonComponent},
        ]
        return all.filter(w => enabled.includes(w.id))
    }

    readonly property var sections: baseSections.concat(widgetSections)

    // ── Close dialogs when sidebar is hidden ─────────────────────
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog        = false
                root.showBluetoothDialog   = false
                root.showEventsDialog      = false
                root.showAudioOutputDialog = false
                root.showAudioInputDialog  = false
                root.showNightLightDialog  = false
                root.showHotspotDialog     = false
                root.eventsDialogEditEvent = null
            }
        }
        function onRequestWifiDialogChanged() {
            if (GlobalStates.requestWifiDialog) {
                GlobalStates.requestWifiDialog = false
                if (!GlobalStates.sidebarRightOpen)
                    GlobalStates.openSidebarRight(GlobalStates.sidebarLeftTargetOutput)
                root.showWifiDialog = true
            }
        }
        function onRequestBluetoothDialogChanged() {
            if (GlobalStates.requestBluetoothDialog) {
                GlobalStates.requestBluetoothDialog = false
                if (!GlobalStates.sidebarRightOpen)
                    GlobalStates.openSidebarRight(GlobalStates.sidebarLeftTargetOutput)
                root.showBluetoothDialog = true
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Background (identical pattern to SidebarRightContent)
    // ─────────────────────────────────────────────────────────────
    StyledRectangularShadow {
        target: bg
        radius: bg.radius
        blur: Math.max(0, Math.min(32,
            Math.round(Config.options?.appearance?.screenEdge?.shadow?.size ?? 15)))
        spread: 0
        offset: Qt.vector2d(0, 0)
        color: ColorUtils.applyAlpha(Appearance.colors.colShadow,
            Math.max(0, Math.min(1.0,
                Number(Config.options?.appearance?.screenEdge?.shadow?.opacity ?? 0.70))))
        visible: root.panelVisible && !root.externalConnectedSurface
            && (Config.options?.appearance?.screenEdge?.shadow?.enabled ?? true)
            && !Appearance.gameModeMinimal
        joinLeft: root.attachedEdge === "left"
        joinRight: root.attachedEdge === "right"
    }

    RicelinSurface {
        anchors.fill: bg
        visible: !root.externalConnectedSurface && bg.islandStyle
        radius: bg.radius
        glassEnabled: true
        screen: root.panelScreen ?? root.QsWindow?.window?.screen ?? null
        glassScreenX: root.screenWidth - bg.width - Appearance.sizes.hyprlandGapsOut
        glassScreenY: root.panelScreenY
        glassScreenWidth: root.screenWidth
        glassScreenHeight: root.screenHeight
    }

    Rectangle {
        id: bg
        anchors.fill: parent

        property bool cardStyle: Config.options?.sidebar?.cardStyle ?? false
        // Ricelin island mode remains an explicit supported sidebar skin;
        // otherwise compact right uses the canonical Material surface.
        readonly property string surfaceDialect: Appearance.surfaceDialectFor(
            (Config.options?.sidebar?.style ?? "panel") === "island" ? "island" : "")
        readonly property bool islandStyle: surfaceDialect === "island"
        readonly property bool gameModeMinimal: Appearance.gameModeMinimal

        readonly property color colDarkSurface:
            ColorUtils.transparentize(Appearance.colors.colLayer1, 0.22)
        readonly property color colDarkSurfaceHover:
            ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 0.20)
        readonly property color colDarkSurfaceActive:
            ColorUtils.transparentize(Appearance.colors.colLayer1Active, 0.18)

        color: root.externalConnectedSurface
            ? "transparent"
            : (gameModeMinimal || islandStyle) ? "transparent"
            : (cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0)

        // Compact and default sidebars share one borderless Screen Edge seam.
        border.width: 0 // Screen Edge seam owns the outer boundary
        border.color: "transparent"

        radius: cardStyle
            ? Appearance.rounding.normal
            : (Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1)
        topLeftRadius: root.attachedEdge === "left" ? 0 : radius
        bottomLeftRadius: root.attachedEdge === "left" ? 0 : radius
        topRightRadius: root.attachedEdge === "right" ? 0 : radius
        bottomRightRadius: root.attachedEdge === "right" ? 0 : radius
        Behavior on radius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        clip: true

        layer.enabled: root.panelVisible && !gameModeMinimal
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: bg.width
                height: bg.height
                radius: bg.radius
                topLeftRadius: bg.topLeftRadius
                topRightRadius: bg.topRightRadius
                bottomLeftRadius: bg.bottomLeftRadius
                bottomRightRadius: bg.bottomRightRadius
            }
        }

        // ─────────────────────────────────────────────────────────
        // Two-column layout
        // ─────────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.compactPanelPadding
            anchors.topMargin: root.compactPanelPadding
            spacing: root.compactPanelPadding

            Rectangle {
                id: compactSurface
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                Behavior on radius {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                // Compact mode sits directly on the panel background (no wrapper card),
                // matching the normal SidebarRightContent layout.
                color: "transparent"
                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                border.width: 0
                Behavior on border.width {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                border.color: "transparent"
                Behavior on border.color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                clip: true

                layer.enabled: root.panelVisible && !bg.gameModeMinimal
                layer.effect: GE.OpacityMask {
                    maskSource: Rectangle {
                        width: compactSurface.width
                        height: compactSurface.height
                        radius: compactSurface.radius
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

            // ── LEFT RAIL ─────────────────────────────────────────
            Rectangle {
                id: leftRail
                Layout.fillHeight: true
                Layout.preferredWidth: root.compactRailWidth
                color: "transparent"

                // Thin separator on right edge
                Rectangle {
                    anchors {
                        top: parent.top; bottom: parent.bottom; right: parent.right
                        topMargin: bg.radius; bottomMargin: bg.radius
                    }
                    width: 0
                    visible: false
                    color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.72)
                }

                // ── Sliding selection highlight (declared before ColumnLayout = behind it) ──
                Rectangle {
                    id: navIndicator
                    // Layout constants — must match ColumnLayout margins and nav item dimensions
                    readonly property int colTop: root.compactContentPadding
                    readonly property int colLeft: root.compactRailMargin
                    readonly property int colRight: root.compactRailMargin
                    readonly property int navBgLeft: 0
                    readonly property int navItemH: root.compactNavItemHeight
                    readonly property int navBgH: root.compactNavBgHeight
                    readonly property int navSpacing: root.compactNavSpacing
                    readonly property int clampedIdx: Math.max(0, Math.min(root.activeSection, root.sections.length - 1))

                    x: colLeft + navBgLeft
                    y: colTop + clampedIdx * (navItemH + navSpacing) + (navItemH - navBgH) / 2
                    width: leftRail.width - colLeft - colRight - navBgLeft
                    height: navBgH
                    radius: Appearance.rounding.small
                    // Bgless doctrine: the selected category is signalled by the colored
                    // material symbol + left accent pill (navPill), not a tenuous plate.
                    color: "transparent"
                    border.width: 0
                    visible: root.activeSection >= 0 && root.activeSection < root.sections.length

                    Behavior on y {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration * 1.5
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                }

                // ── Sliding active pill on left edge ──
                Rectangle {
                    id: navPill
                    x: navIndicator.colLeft + 1
                    y: navIndicator.colTop + navIndicator.clampedIdx * (navIndicator.navItemH + navIndicator.navSpacing) + (navIndicator.navItemH - height) / 2
                    width: 3
                    height: 26
                    color: Appearance.colors.colPrimary
                    radius: 2
                    visible: root.activeSection >= 0 && root.activeSection < root.sections.length
                    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                    Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }

                    Behavior on y {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration * 1.5
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Section scroll navigation on rail
                WheelHandler {
                    orientation: Qt.Vertical
                    onWheel: (event) => {
                        if (event.angleDelta.y < 0)
                            root.activeSection = Math.min(root.activeSection + 1, root.sections.length - 1)
                        else if (event.angleDelta.y > 0)
                            root.activeSection = Math.max(root.activeSection - 1, 0)
                    }
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        topMargin: root.compactContentPadding; bottomMargin: root.compactContentPadding
                        leftMargin: root.compactRailMargin; rightMargin: root.compactRailMargin
                    }
                    spacing: root.compactNavSpacing

                    // ── Section navigation buttons ──────────────
                    Repeater {
                        model: root.sections
                        delegate: Item {
                            id: navItem
                            required property int index
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: root.compactNavItemHeight

                            readonly property bool isActive: root.activeSection === navItem.index

                            // Button background (active highlight provided by navIndicator behind)
                            Rectangle {
                                id: navBg
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                height: root.compactNavBgHeight
                                radius: Appearance.rounding.small

                                // Bgless doctrine: no plate at rest, hover or press.
                                // Feedback lives in the icon colour/weight + accent pill.
                                color: "transparent"
                                border.width: 0

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 24
                                    fill: navItem.isActive ? 1 : 0
                                    animateFill: true
                                    font.weight: (navItem.isActive || navMA.containsMouse) ? Font.DemiBold : Font.Normal
                                    text: navItem.modelData.icon
                                    // Bgless: active icon carries the accent itself (no plate behind)
                                    color: navItem.isActive
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colOnLayer1
                                    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                }

                                MouseArea {
                                    id: navMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activeSection = navItem.index
                                }
                                BubbleToolTip {
                                    visible: navMA.containsMouse
                                    position: "left"
                                    text: navItem.modelData.label
                                }
                            }
                        }
                    }

                    // ── Vertical spacer ──────────────────────────
                    Item { Layout.fillHeight: true }

                    // Subtle separator between nav and system buttons
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 4
                        height: 1
                        visible: false
                        color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.76)
                    }

                    // ── System action buttons ────────────────────
                    Repeater {
                        model: {
                            const actions = [
                                { icon: root.layoutEditMode ? "check" : "reorder",
                                  label: root.layoutEditMode ? Translation.tr("Done editing") : Translation.tr("Reorder sections"),
                                  action: function() { root.layoutEditMode = !root.layoutEditMode } },
                            ]
                            if ((Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android") {
                                actions.push({
                                    icon: root.editMode ? "check" : "edit",
                                    label: Translation.tr("Edit quick toggles"),
                                    action: function() { root.editMode = !root.editMode }
                                })
                            }
                            actions.push(
                                { icon: "restart_alt", label: Translation.tr("Reload Quickshell"),
                                  action: function() { doReload() } },
                                { icon: "settings", label: Translation.tr("Settings"),
                                  action: function() { doSettings() } },
                                { icon: "power_settings_new", label: Translation.tr("Session"),
                                  action: function() { GlobalStates.sessionOpen = true } }
                            )
                            return actions
                        }
                        delegate: Item {
                            id: sysItem
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: root.compactActionItemHeight

                            Rectangle {
                                id: sysActBg
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                height: root.compactActionBgHeight
                                radius: Appearance.rounding.small
                                color: {
                                    if (sysMA.containsPress)
                                        return bg.colDarkSurfaceActive
                                    if (sysMA.containsMouse)
                                        return bg.colDarkSurfaceHover
                                    return "transparent"
                                }
                                border.width: 0
                                border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.70)
                                Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    text: sysItem.modelData.icon
                                    color: Appearance.colors.colOnLayer1
                                }
                                MouseArea {
                                    id: sysMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sysItem.modelData.action()
                                }
                                BubbleToolTip {
                                    visible: sysMA.containsMouse
                                    position: "left"
                                    text: sysItem.modelData.label
                                }
                            }
                        }
                    }

                    // ── Layout toggle ────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: root.compactActionItemHeight
                        Rectangle {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            height: root.compactActionBgHeight
                            radius: Appearance.rounding.small
                            color: {
                                if (layoutMA.containsPress)
                                    return bg.colDarkSurfaceActive
                                if (layoutMA.containsMouse)
                                    return bg.colDarkSurfaceHover
                                return "transparent"
                            }
                            border.width: 0
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.70)
                            Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "view_agenda"
                                color: Appearance.colors.colPrimary
                            }
                            MouseArea {
                                id: layoutMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.setNestedValue("sidebar.layout", "default")
                            }
                            BubbleToolTip {
                                visible: layoutMA.containsMouse
                                position: "left"
                                text: Translation.tr("Switch to default layout")
                            }
                        }
                    }
                } // ColumnLayout (rail)
            } // leftRail

            // ── RIGHT CONTENT AREA ────────────────────────────────
            Item {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Crossfade container — all sections stacked, only active one visible
                Repeater {
                    id: sectionRepeater
                    model: root.sections

                    delegate: Item {
                        id: sectionItem
                        required property int index
                        required property var modelData
                        anchors.fill: parent

                        readonly property bool isCurrent: root.activeSection === sectionItem.index
                        readonly property bool isBase: sectionItem.modelData.id === "controls"
                        property alias sectionLoader: sectionContentLoader

                        // Crossfade opacity
                        opacity: isCurrent ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Subtle slide-in from direction of navigation
                        transform: Translate {
                            y: sectionItem.isCurrent ? 0 : (root.activeSection > sectionItem.index ? -6 : 6)
                            Behavior on y {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // ── Section content ──────────────────────
                        Loader {
                            id: sectionContentLoader
                            anchors.fill: parent
                            // Lazy loading: base sections always loaded, widgets only when adjacent or current
                            active: sectionItem.isBase
                                || sectionItem.isCurrent
                                || Math.abs(root.activeSection - sectionItem.index) <= 1

                            sourceComponent: {
                                if (sectionItem.modelData.id === "controls")
                                    return controlsSectionComponent
                                // Widget sections — use component from data
                                return sectionItem.modelData.component ?? null
                            }
                        }
                    }
                }
            } // contentArea
                } // RowLayout (two columns)
            }
        }
    } // bg Rectangle

    // ── Section content components ────────────────────────────────

    Component {
        id: controlsSectionComponent
        Item {
            id: controlsRoot
            readonly property int controlsAreaPadding: Math.max(root.compactGridSpacing, Math.min(root.compactContentPadding, Math.round(Math.min(width || root.width, height || root.height) * 0.018)))
            readonly property int controlsGap: Math.max(root.compactNavSpacing, Math.min(root.compactSectionSpacing, Math.round((height || root.height) * (root.compactTightHeight ? 0.006 : 0.009))))
            readonly property int controlsInnerPadding: Math.max(3, Math.round(controlsAreaPadding / 2))
            readonly property int controlsInlineGap: Math.max(root.compactGridSpacing, Math.round(controlsGap * 0.8))

            // Scrollable content for Controls section
            Flickable {
                id: controlsFlickable
                anchors.fill: parent
                anchors.topMargin: controlsRoot.controlsAreaPadding
                anchors.bottomMargin: controlsRoot.controlsAreaPadding
                anchors.leftMargin: controlsRoot.controlsAreaPadding
                anchors.rightMargin: controlsRoot.controlsAreaPadding
                contentWidth: controlsColumn.width
                contentHeight: controlsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Preserve wheel/touch scrolling without painting a competing
                // scrollbar beside the compact Sidebar Right content.
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: controlsColumn
                    width: controlsFlickable.width
                    spacing: controlsRoot.controlsGap

                    // Controls identity is already represented by the selected
                    // icon in the left rail; do not duplicate a content heading.

                    // ═══════════════════════════════════════════════════════
                    // REORDERABLE CONTROLS SECTIONS
                    // ═══════════════════════════════════════════════════════
                    Repeater {
                        model: root.controlsSectionOrder

                        delegate: ColumnLayout {
                            id: sectionDelegate
                            required property string modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.topMargin: sectionDelegate.index > 0 ? controlsRoot.controlsInlineGap : 0
                            spacing: controlsRoot.controlsInlineGap

                            // Move buttons (visible in edit mode)
                            Revealer {
                                vertical: true
                                reveal: root.layoutEditMode
                                Layout.fillWidth: true
                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                spacing: controlsRoot.controlsInlineGap

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        switch (sectionDelegate.modelData) {
                                            case "sliders": return Translation.tr("Sliders")
                                            case "toggles": return Translation.tr("Quick Toggles")
                                            case "devices": return Translation.tr("Devices")
                                            case "media": return Translation.tr("Media Player")
                                            case "quickActions": return Translation.tr("Quick Actions")
                                            default: return sectionDelegate.modelData
                                        }
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colPrimary
                                }

                                RippleButton {
                                    implicitWidth: 28; implicitHeight: 28
                                    buttonRadius: 14
                                    enabled: sectionDelegate.index > 0
                                    opacity: enabled ? 1 : 0.3
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    onClicked: root.moveSectionUp(sectionDelegate.index)
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_upward"; iconSize: 16; color: Appearance.colors.colOnLayer1 }
                                    StyledToolTip { text: Translation.tr("Move up") }
                                }

                                RippleButton {
                                    implicitWidth: 28; implicitHeight: 28
                                    buttonRadius: 14
                                    enabled: sectionDelegate.index < root.controlsSectionOrder.length - 1
                                    opacity: enabled ? 1 : 0.3
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    onClicked: root.moveSectionDown(sectionDelegate.index)
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_downward"; iconSize: 16; color: Appearance.colors.colOnLayer1 }
                                    StyledToolTip { text: Translation.tr("Move down") }
                                }
                            }
                            }

                            // Section content based on modelData
                            Loader {
                                Layout.fillWidth: true
                                active: sectionDelegate.modelData === "sliders"
                                visible: active && (Config.options?.sidebar?.quickSliders?.enable && (Config.options?.sidebar?.quickSliders?.showMic || Config.options?.sidebar?.quickSliders?.showVolume || Config.options?.sidebar?.quickSliders?.showBrightness))
                                sourceComponent: QuickSliders {
                                    verticalPadding: controlsRoot.controlsInnerPadding
                                    horizontalPadding: controlsRoot.controlsAreaPadding
                                    sliderSpacing: controlsRoot.controlsGap
                                    compactSurface: true
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                active: sectionDelegate.modelData === "toggles"
                                visible: active
                                sourceComponent: ColumnLayout {
                                    spacing: controlsRoot.controlsInlineGap

                                    // Classic compact controls: one intentional row only.
                                    // Wi-Fi/Bluetooth already have full device rows below; Settings/Lock
                                    // live in the rail/system actions. Use the scarce header slots for
                                    // stateful controls that are otherwise harder to reach.
                                    Loader {
                                        Layout.fillWidth: true
                                        active: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "classic"
                                        visible: active
                                        sourceComponent: RowLayout {
                                            spacing: 0

                                            // Ambient / focus / session controls.
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40
                                                    visible: Config.options?.sidebar?.widgets?.controlsCard?.showDarkMode ?? true

                                                    QuickToggleButton {
                                                        anchors.centerIn: parent
                                                        accessibleName: (Appearance.m3colors?.darkmode ?? false)
                                                            ? Translation.tr("Switch to light mode")
                                                            : Translation.tr("Switch to dark mode")
                                                        buttonIcon: (Appearance.m3colors?.darkmode ?? false)
                                                            ? "light_mode" : "dark_mode"
                                                        toggled: Appearance.m3colors?.darkmode ?? false
                                                        onClicked: Appearance.toggleDarkMode()
                                                        StyledToolTip {
                                                            text: (Appearance.m3colors?.darkmode ?? false)
                                                                ? Translation.tr("Switch to light mode")
                                                                : Translation.tr("Switch to dark mode")
                                                        }
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40
                                                    visible: Config.options?.sidebar?.widgets?.controlsCard?.showDnd ?? true

                                                    QuickToggleButton {
                                                        anchors.centerIn: parent
                                                        accessibleName: Translation.tr("Do not disturb")
                                                        buttonIcon: "do_not_disturb_on"
                                                        toggled: Notifications.silent ?? false
                                                        onClicked: Notifications.toggleSilent()
                                                        StyledToolTip { text: Translation.tr("Do not disturb") }
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40
                                                    visible: Config.options?.sidebar?.widgets?.controlsCard?.showNightLight ?? true

                                                    QuickToggleButton {
                                                        anchors.centerIn: parent
                                                        accessibleName: Translation.tr("Night Light")
                                                        buttonIcon: (Config.options?.light?.night?.automatic ?? false)
                                                            ? "night_sight_auto" : "bedtime"
                                                        toggled: Hyprsunset.active ?? false
                                                        onClicked: Hyprsunset.toggle()
                                                        altAction: () => { root.showNightLightDialog = true }

                                                        Component.onCompleted: Hyprsunset.fetchState()

                                                        StyledToolTip {
                                                            text: Translation.tr("Night Light | Right-click for settings")
                                                        }
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40
                                                    visible: Config.options?.sidebar?.widgets?.controlsCard?.showGameMode ?? true

                                                    GameMode {
                                                        anchors.centerIn: parent
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 1
                                                Layout.preferredHeight: 24
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.leftMargin: 3
                                                Layout.rightMargin: 3
                                                radius: 0.5
                                                color: Appearance.colors.colOutlineVariant
                                                opacity: 0.5
                                            }

                                            // Performance / audio / connectivity utilities.
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40

                                                    IdleInhibitor {
                                                        anchors.centerIn: parent
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40
                                                    visible: EasyEffects.available

                                                    EasyEffectsToggle {
                                                        anchors.centerIn: parent
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40

                                                    HotspotToggle {
                                                        anchors.centerIn: parent
                                                        altAction: () => { root.showHotspotDialog = true }
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 40

                                                    CloudflareWarp {
                                                        anchors.centerIn: parent
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Android style keeps its editable panel and the legacy ControlsCard.
                                    Loader {
                                        id: compactAndroidControlsCardLoader
                                        Layout.fillWidth: true
                                        active: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android"
                                        visible: active
                                        sourceComponent: Item {
                                            implicitHeight: androidCcSurface.implicitHeight

                                            Rectangle {
                                                id: androidCcSurface
                                                anchors.fill: parent
                                                implicitHeight: androidCcCard.implicitHeight + controlsRoot.controlsAreaPadding
                                                radius: 0
                                                color: "transparent"
                                                border.width: 0
                                                border.color: "transparent"

                                                ControlsCard {
                                                    id: androidCcCard
                                                    anchors.fill: parent
                                                    anchors.margins: controlsRoot.controlsInnerPadding
                                                }
                                            }
                                        }
                                    }

                                    Loader {
                                        id: compactAndroidQuickPanelLoader
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 0; Layout.rightMargin: 0
                                        active: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android"
                                        sourceComponent: AndroidQuickPanel { editMode: root.editMode }
                                        Connections {
                                            target: compactAndroidQuickPanelLoader.item
                                            ignoreUnknownSignals: true
                                            function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true }
                                            function onOpenAudioInputDialog()  { root.showAudioInputDialog  = true }
                                            function onOpenBluetoothDialog()   { root.showBluetoothDialog   = true }
                                            function onOpenNightLightDialog()  { root.showNightLightDialog  = true }
                                            function onOpenHotspotDialog()     { root.showHotspotDialog     = true }
                                            function onOpenWifiDialog()        { root.showWifiDialog        = true }
                                        }
                                    }
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                active: sectionDelegate.modelData === "devices"
                                visible: active
                                sourceComponent: ColumnLayout {
                                    spacing: controlsRoot.controlsInlineGap
                                    SectionDivider { text: Translation.tr("Devices"); visible: false }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: controlsRoot.controlsInlineGap
                                        rowSpacing: controlsRoot.controlsInlineGap

                                        ControlChipButton { Layout.fillWidth: true; chipIcon: "media_output"; chipLabel: Translation.tr("Output"); value: Audio.sink?.description ?? ""; onClicked: root.showAudioOutputDialog = true }
                                        ControlChipButton { Layout.fillWidth: true; chipIcon: "mic_external_on"; chipLabel: Translation.tr("Input"); value: Audio.source?.description ?? ""; onClicked: root.showAudioInputDialog = true }
                                        ControlChipButton { Layout.fillWidth: true; chipIcon: "bluetooth"; chipLabel: Translation.tr("Bluetooth"); value: Bluetooth.defaultAdapter?.enabled ? Translation.tr("On") : Translation.tr("Off"); onClicked: root.showBluetoothDialog = true }
                                        ControlChipButton { Layout.fillWidth: true; chipIcon: Network.materialSymbol; chipLabel: Translation.tr("Wi-Fi"); value: Network.networkName ?? ""; onClicked: root.showWifiDialog = true }
                                    }
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                active: sectionDelegate.modelData === "media"
                                visible: active
                                sourceComponent: ColumnLayout {
                                    spacing: controlsRoot.controlsInlineGap
                                    SectionDivider { text: Translation.tr("Media"); visible: false }

                                    CompactMediaPlayer {
                                        Layout.fillWidth: true
                                    }

                                    EqualizerPanel {
                                        Layout.fillWidth: true
                                        // The base controls tree stays warm,
                                        // but its analyzer/DSP lease ends after
                                        // the last crossfade pixels disappear.
                                        active: root.panelVisible && visible
                                    }
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                active: sectionDelegate.modelData === "quickActions"
                                visible: active
                                sourceComponent: QuickActionsSection {}
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Dialogs (identical to SidebarRightContent) ────────────────
    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog { isSink: true }
    }
    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog { isSink: false }
    }
    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!Bluetooth.defaultAdapter) return
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false
            } else {
                Bluetooth.defaultAdapter.enabled = true
                Bluetooth.defaultAdapter.discovering = true
            }
        }
    }
    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }
    ToggleDialog {
        shownPropertyString: "showHotspotDialog"
        dialog: HotspotDialog {}
    }
    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return
            Network.enableWifi()
            Network.rescanWifi()
        }
    }

    ToggleDialog {
        id: compactEventsToggle
        shownPropertyString: "showEventsDialog"
        dialog: EventsDialog {}
        onShownChanged: {
            if (shown && compactEventsToggle.item) {
                if (root.eventsDialogEditEvent) {
                    compactEventsToggle.item.loadEvent(root.eventsDialogEditEvent)
                } else {
                    compactEventsToggle.item.resetForm()
                }
            }
        }
        onActiveChanged: {
            if (!active) {
                root.eventsDialogEditEvent = null
            }
        }
    }

    // ── Cooldown timers ───────────────────────────────────────────
    Timer { id: reloadCooldown;   interval: 500; onTriggered: root.reloadButtonEnabled  = true }
    Timer { id: settingsCooldown; interval: 500; onTriggered: root.settingsButtonEnabled = true }

    // ── System action implementations ────────────────────────────
    function doReload() {
        if (!root.reloadButtonEnabled) return
        root.reloadButtonEnabled = false
        reloadCooldown.restart()
        if (CompositorService.isHyprland)
            Hyprland.dispatch("reload")
        else if (CompositorService.isNiri)
            Quickshell.execDetached(["/usr/bin/niri", "msg", "action", "load-config-file"])
        Quickshell.execDetached(["/usr/bin/bash", Quickshell.shellPath("scripts/restart-shell.sh")])
    }

    function doSettings() {
        if (!root.settingsButtonEnabled) return
        root.settingsButtonEnabled = false
        settingsCooldown.restart()
        if (CompositorService.isNiri) {
            const wins = NiriService.windows || []
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i]
                if (w.title === "Alis Settings" && w.app_id === "org.quickshell") {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => NiriService.focusWindow(w.id))
                    return
                }
            }
        }
        GlobalStates.sidebarRightOpen = false
        Qt.callLater(() => Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"]))
    }

    // ═════════════════════════════════════════════════════════════
    // INLINE COMPONENTS
    // ═════════════════════════════════════════════════════════════

    component ToggleDialog: Loader {
        id: tdLoader
        required property string shownPropertyString
        property alias dialog: tdLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent
        active: shown
        onItemChanged: {
            if (item) { item.show = true; item.forceActiveFocus() }
        }
        Connections {
            target: tdLoader.item
            ignoreUnknownSignals: true
            function onDismiss() { root[tdLoader.shownPropertyString] = false }
        }
    }

    // ── Section Header ───────────────────────────────────────────
    component SectionHeader: Item {
        id: sectionHeader
        required property string headerText
        property string headerIcon: ""
        property string badgeText: ""
        property bool showAction: false
        property string actionIcon: ""
        property string actionTooltip: ""
        property bool actionToggled: false
        property bool showSecondaryAction: false
        property string secondaryActionIcon: ""
        property string secondaryActionTooltip: ""

        signal actionClicked()
        signal secondaryActionClicked()

        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight

        RowLayout {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            MaterialSymbol {
                visible: sectionHeader.headerIcon !== ""
                text: sectionHeader.headerIcon
                iconSize: 18
                fill: 1
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: sectionHeader.headerText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }

            // Badge (notification count)
            Revealer {
                reveal: sectionHeader.badgeText !== ""
                Rectangle {
                    implicitWidth: Math.max(18, badgeLabelInHeader.implicitWidth + 8)
                    implicitHeight: 18
                    radius: 9
                    color: Appearance.colors.colSecondaryContainer

                    StyledText {
                        id: badgeLabelInHeader
                        anchors.centerIn: parent
                        text: sectionHeader.badgeText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            // Secondary action button
            Revealer {
                reveal: sectionHeader.showSecondaryAction
            RippleButton {
                implicitWidth: 28; implicitHeight: 28
                buttonRadius: 14
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.68)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: sectionHeader.secondaryActionClicked()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent; text: sectionHeader.secondaryActionIcon; iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip {
                    position: "left"
                    text: sectionHeader.secondaryActionTooltip
                }
            }
            }

            // Primary action button
            Revealer {
                reveal: sectionHeader.showAction
            RippleButton {
                implicitWidth: 28; implicitHeight: 28
                buttonRadius: 14
                colBackground: sectionHeader.actionToggled
                    ? Appearance.colors.colSecondaryContainer
                    : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.68)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: sectionHeader.actionClicked()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent; text: sectionHeader.actionIcon; iconSize: 16
                    fill: sectionHeader.actionToggled ? 1 : 0; animateFill: true
                    color: sectionHeader.actionToggled
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    position: "left"
                    text: sectionHeader.actionTooltip
                }
            }
            }
        }
    }

    // ── Quick Actions Section ─────────────────────────────────────
    component QuickActionsSection: ColumnLayout {
        id: quickActions
        spacing: root.compactNavSpacing

        SectionDivider {
            text: Translation.tr("Quick Actions")
            visible: false
        }

        // Action buttons — compact 3-column grid
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: root.compactGridSpacing
            rowSpacing: root.compactGridSpacing

            QuickActionButton {
                Layout.fillWidth: true
                icon: "screenshot_monitor"
                label: Translation.tr("Screenshot")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "screenshot"]))
                }
            }

            QuickActionButton {
                Layout.fillWidth: true
                icon: "videocam"
                label: Translation.tr("Record")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "record"]))
                }
            }

            QuickActionButton {
                Layout.fillWidth: true
                icon: "document_scanner"
                label: Translation.tr("OCR")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "ocr"]))
                }
            }

            QuickActionButton {
                Layout.fillWidth: true
                icon: "travel_explore"
                label: Translation.tr("Search")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "search"]))
                }
            }

            QuickActionButton {
                Layout.fillWidth: true
                icon: "palette"
                label: Translation.tr("Color Picker")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => ShellExec.execDetachedArgs(["/usr/bin/hyprpicker", "-a"], "Pick color"))
                }
            }

            QuickActionButton {
                Layout.fillWidth: true
                icon: "folder_open"
                label: Translation.tr("Files")
                onClicked: ShellExec.execDetachedArgs(["xdg-open", Quickshell.env("HOME")], "Open home folder")
            }
        }
    }

    component BubbleToolTip: PopupToolTip {
        id: bubble
        property string position: "left" // top | right | left
        delay: 0
        horizontalPadding: 12
        verticalPadding: 5
        anchorEdges: position === "left" ? Edges.Left
            : position === "right" ? Edges.Right
            : Edges.Top
        anchorGravity: anchorEdges
        contentItem: Item {
            id: bubbleContent
            property bool shown: false
            implicitWidth: bubbleBackground.implicitWidth
            implicitHeight: bubbleBackground.implicitHeight
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.9

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: bubbleBackground
                anchors.centerIn: parent
                color: Appearance.colors.colPrimary
                radius: Appearance.rounding.full
                implicitWidth: bubbleLabel.implicitWidth + 24
                implicitHeight: bubbleLabel.implicitHeight + 10

                StyledText {
                    id: bubbleLabel
                    anchors.centerIn: parent
                    text: bubble.text
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // ── Quick Action Button ───────────────────────────────────────
    component QuickActionButton: Item {
        id: qaBtn
        required property string icon
        required property string label
        property bool toggled: false

        signal clicked()

        implicitHeight: 52

        // Style helpers
        readonly property color _colPrimary: Appearance.colors.colPrimary
        readonly property color _colText: Appearance.colors.colOnLayer1
        readonly property color _colOnToggle: Appearance.colors.colOnSecondaryContainer
        readonly property color _colToggleBg: Appearance.colors.colSecondaryContainer

        Rectangle {
            id: qaBtnBg
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: {
                if (qaBtnMA.containsPress)
                    return bg.colDarkSurfaceActive
                if (qaBtnMA.containsMouse)
                    return bg.colDarkSurfaceHover
                if (qaBtn.toggled)
                    return qaBtn._colToggleBg
                return "transparent"
            }
            border.width: 0

            scale: qaBtnMA.containsPress ? 0.94 : 1.0
            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                // Icon in accent circle
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: qaBtn.toggled
                        ? ColorUtils.transparentize(qaBtn._colOnToggle, 0.82)
                        : ColorUtils.transparentize(qaBtn._colPrimary, 0.86)

                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: qaBtn.icon
                        iconSize: 17
                        fill: qaBtn.toggled ? 1 : 0
                        animateFill: true
                        color: qaBtn.toggled ? qaBtn._colOnToggle : qaBtn._colPrimary
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: qaBtnBg.width - 6
                    text: qaBtn.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    color: qaBtn.toggled ? qaBtn._colOnToggle : qaBtn._colText
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                id: qaBtnMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: qaBtn.clicked()
            }

            BubbleToolTip {
                visible: qaBtnMA.containsMouse
                position: "left"
                text: qaBtn.label
            }
        }
    }
}
