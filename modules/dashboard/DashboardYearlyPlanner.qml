pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks
import "YearlyPlannerPolicy.js" as YearlyPolicy

Item {
    id: root

    property date anchorDate: new Date()
    property string rangeMode: "calendar" // "calendar" | "rolling"
    property var localBackend: Events
    property int eventsRevision: 0

    property bool abyssPanel: (Config.options?.panelFamily ?? "ii") === "abyss"
    property color ink: ColorUtils.ensureReadable(
        abyssPanel ? AbyssStyle.text : Appearance.colors.colOnLayer1,
        abyssPanel ? AbyssStyle.contentLayer : Appearance.colors.colLayer1, 7)
    property color mutedInk: ColorUtils.ensureReadable(
        abyssPanel ? AbyssStyle.textSecondary : Appearance.colors.colSubtext,
        abyssPanel ? AbyssStyle.contentLayer : Appearance.colors.colLayer1, 4.5)
    property color headerAccent: abyssPanel ? AbyssStyle.accent : Appearance.colors.colPrimary
    property color headerTodayInk: ColorUtils.ensureReadable(
        headerAccent, abyssPanel ? AbyssStyle.contentLayer : Appearance.colors.colLayer0, 4.5)
    property color headerDivider: Qt.alpha(ink, 0.16)
    property color headerSurface: abyssPanel
        ? AbyssStyle.surfaceDeep : Qt.alpha(Appearance.colors.colLayer0Base, 1)

    property string searchQuery: ""
    property bool searchOpen: false

    // Quick Plan Editor state
    property bool editorOpen: false
    property int editingEventId: -1
    property string draftKind: "plan"
    property string draftTitle: ""
    property string draftStartIso: ""
    property string draftEndIso: ""
    property string draftPlace: ""
    property string draftNotes: ""
    property string draftColor: ""
    property var draftChecklist: []
    property string draftError: ""
    property bool deleteConfirmPending: false

    // Drag move/resize preview state
    property int dragEventId: -1
    property string dragPreviewStartIso: ""
    property string dragPreviewEndIso: ""

    readonly property var swatches: [
        "",
        "#4E8EF7",
        "#2EB872",
        "#F2994A",
        "#E05A5A",
        "#9B6BFF",
        "#18B4C4"
    ]

    readonly property string todayIso: YearlyPolicy.toIsoDate(new Date())
    readonly property var boardData: {
        const _rev = root.eventsRevision
        const eventsList = root.localBackend?.list ?? []
        return YearlyPolicy.projectYearBoard(
            eventsList,
            root.anchorDate,
            root.rangeMode,
            root.todayIso,
            root.searchQuery
        )
    }

    readonly property real monthColWidth: Math.round(58 * Appearance.fontSizeScale)
    readonly property real minDayColWidth: 18
    readonly property real boardGridWidth: Math.max(31 * minDayColWidth, boardViewport.width - monthColWidth)
    readonly property real dayColWidth: boardGridWidth / 31.0

    signal requestRangeModeChange(string mode)
    signal requestJumpToWeek(date date)

    function focusSearch(): void {
        root.searchOpen = true
        Qt.callLater(() => searchInput.forceActiveFocus())
    }

    function clearOrCloseSearch(): void {
        if (root.searchQuery.length > 0) {
            root.searchQuery = ""
            searchInput.text = ""
            return
        }
        root.searchOpen = false
    }

    function _syncEditorInputs(): void {
        titleInput.text = root.draftTitle
        startDateInput.text = root.draftStartIso
        endDateInput.text = root.draftEndIso
        placeInput.text = root.draftPlace
        notesInput.text = root.draftNotes
        checklistInput.text = ""
    }

    function openNewPlanForDate(isoDate): void {
        const cleanIso = YearlyPolicy.parseIsoDate(isoDate) ? isoDate : root.todayIso
        root.editingEventId = -1
        root.draftKind = "plan"
        root.draftTitle = ""
        root.draftStartIso = cleanIso
        root.draftEndIso = cleanIso
        root.draftPlace = ""
        root.draftNotes = ""
        root.draftColor = root.swatches[1]
        root.draftChecklist = []
        root.draftError = ""
        root.deleteConfirmPending = false
        root._syncEditorInputs()
        root.editorOpen = true
        Qt.callLater(() => titleInput.forceActiveFocus())
    }

    function openEditorForSpan(span): void {
        if (!span)
            return
        root.editingEventId = Number(span.id ?? -1)
        root.draftKind = span.kind || "plan"
        root.draftTitle = span.title || ""
        root.draftStartIso = span.startIso || root.todayIso
        root.draftEndIso = span.endIso || root.draftStartIso
        root.draftPlace = span.place || ""
        root.draftNotes = span.notes || ""
        root.draftColor = span.color || ""
        root.draftChecklist = (span.checklist || []).map(item => ({
            text: String(item.text || ""),
            done: item.done === true
        }))
        root.draftError = ""
        root.deleteConfirmPending = false
        root._syncEditorInputs()
        root.editorOpen = true
        Qt.callLater(() => titleInput.forceActiveFocus())
    }

    function closeEditor(): void {
        root.editorOpen = false
        root.draftError = ""
        root.deleteConfirmPending = false
    }

    function stepDraftDate(which, deltaDays): void {
        if (which === "start") {
            const base = YearlyPolicy.parseIsoDate(root.draftStartIso) ? root.draftStartIso : root.todayIso
            const nextStart = YearlyPolicy.addDaysIso(base, deltaDays)
            if (!nextStart) return
            root.draftStartIso = nextStart
            startDateInput.text = nextStart
            if (!YearlyPolicy.parseIsoDate(root.draftEndIso) || root.draftEndIso < nextStart) {
                root.draftEndIso = nextStart
                endDateInput.text = nextStart
            }
        } else {
            const fallback = YearlyPolicy.parseIsoDate(root.draftStartIso) ? root.draftStartIso : root.todayIso
            const base = YearlyPolicy.parseIsoDate(root.draftEndIso) ? root.draftEndIso : fallback
            const nextEnd = YearlyPolicy.addDaysIso(base, deltaDays)
            if (!nextEnd) return
            root.draftEndIso = nextEnd < fallback ? fallback : nextEnd
            endDateInput.text = root.draftEndIso
        }
    }

    function addChecklistEntry(): void {
        const clean = String(checklistInput.text || "").trim()
        if (!clean.length) return
        const next = root.draftChecklist.slice()
        next.push({ text: clean, done: false })
        root.draftChecklist = next
        checklistInput.text = ""
    }

    function toggleChecklistEntry(index): void {
        if (index < 0 || index >= root.draftChecklist.length) return
        const next = root.draftChecklist.map((item, idx) => idx === index
            ? ({ text: item.text, done: !item.done })
            : item)
        root.draftChecklist = next
    }

    function removeChecklistEntry(index): void {
        if (index < 0 || index >= root.draftChecklist.length) return
        root.draftChecklist = root.draftChecklist.filter((_, idx) => idx !== index)
    }

    function saveDraft(): bool {
        const cleanTitle = String(titleInput.text || "").trim()
        const sIso = String(startDateInput.text || root.draftStartIso).trim()
        const eIso = String(endDateInput.text || root.draftEndIso).trim()
        if (!cleanTitle.length) {
            root.draftError = Translation.tr("Title is required")
            titleInput.forceActiveFocus()
            return false
        }
        const sDt = YearlyPolicy.parseIsoDate(sIso)
        const eDt = YearlyPolicy.parseIsoDate(eIso)
        if (!sDt || !eDt) {
            root.draftError = Translation.tr("Use YYYY-MM-DD dates")
            return false
        }
        if (eDt < sDt) {
            root.draftError = Translation.tr("End date must be on or after start date")
            return false
        }
        if (!root.localBackend)
            return false

        const payload = {
            title: cleanTitle,
            startIso: sIso,
            endIso: eIso,
            plannerKind: root.draftKind,
            place: String(placeInput.text || "").trim(),
            description: String(notesInput.text || ""),
            color: root.draftColor,
            checklist: root.draftChecklist
        }

        let ok = false
        if (root.editingEventId >= 0 && typeof root.localBackend.updateYearlyPlan === "function") {
            ok = root.localBackend.updateYearlyPlan(root.editingEventId, payload) === true
        } else if (typeof root.localBackend.addYearlyPlan === "function") {
            const newId = root.localBackend.addYearlyPlan(payload)
            ok = Number(newId) >= 0
        }
        if (!ok) {
            root.draftError = Translation.tr("Could not save plan")
            return false
        }
        root.closeEditor()
        return true
    }

    function deleteEditingPlan(): void {
        if (root.editingEventId < 0 || !root.localBackend)
            return
        if (!root.deleteConfirmPending) {
            root.deleteConfirmPending = true
            return
        }
        if (typeof root.localBackend.removeEvent === "function") {
            root.localBackend.removeEvent(root.editingEventId)
        }
        root.closeEditor()
    }

    function resolveBarColor(colorHex): color {
        const clean = String(colorHex || "").trim()
        if (!clean.length)
            return root.headerAccent
        const parsed = Qt.color(clean)
        return parsed.valid ? parsed : root.headerAccent
    }

    function contrastOnBar(barCol): color {
        return barCol.hslLightness > 0.62 ? "#11161d" : "#f7f9fc"
    }

    function formatShortDate(iso): string {
        const dt = YearlyPolicy.parseIsoDate(iso)
        return dt ? Qt.formatDate(dt, "MMM d") : iso
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.editorOpen) {
                root.closeEditor()
                event.accepted = true
                return
            }
            if (root.searchOpen || root.searchQuery.length > 0) {
                root.clearOrCloseSearch()
                event.accepted = true
                return
            }
        } else if (event.key === Qt.Key_Slash && event.modifiers === Qt.NoModifier) {
            if (!root.editorOpen) {
                root.focusSearch()
                event.accepted = true
                return
            }
        }
        event.accepted = false
    }

    component PillButton: RippleButton {
        id: pillBtn
        property string label: ""
        property string symbol: ""
        property bool activeTint: false
        property color fgColor: activeTint ? Appearance.colors.colOnPrimary : root.ink
        implicitHeight: Math.round(26 * Appearance.fontSizeScale)
        implicitWidth: pillRow.implicitWidth + 16
        buttonRadius: height / 2
        colBackground: activeTint ? root.headerAccent : Qt.alpha(root.ink, 0.08)
        colBackgroundHover: activeTint ? Qt.lighter(root.headerAccent, 1.08) : Qt.alpha(root.ink, 0.14)

        contentItem: Item {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    visible: pillBtn.symbol.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: pillBtn.symbol
                    iconSize: Math.round(14 * Appearance.fontSizeScale)
                    color: pillBtn.fgColor
                }
                StyledText {
                    visible: pillBtn.label.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: pillBtn.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: pillBtn.activeTint ? Font.DemiBold : Font.Medium
                    color: pillBtn.fgColor
                }
            }
        }
    }

    component CompactField: Rectangle {
        id: fieldRoot
        property alias text: fieldInput.text
        property string placeholderText: ""
        signal accepted()

        implicitHeight: Math.round(32 * Appearance.fontSizeScale)
        radius: Appearance.rounding.small
        color: Qt.alpha(root.ink, 0.07)
        border.width: fieldInput.activeFocus ? 1.5 : 1
        border.color: fieldInput.activeFocus ? root.headerAccent : Qt.alpha(root.ink, 0.14)

        TextInput {
            id: fieldInput
            anchors {
                fill: parent
                leftMargin: 9
                rightMargin: 9
            }
            verticalAlignment: TextInput.AlignVCenter
            color: root.ink
            selectionColor: Qt.alpha(root.headerAccent, 0.35)
            selectedTextColor: root.ink
            font.pixelSize: Appearance.font.pixelSize.small
            selectByMouse: true
            clip: true
            onAccepted: fieldRoot.accepted()

            StyledText {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !fieldInput.text.length && !fieldInput.activeFocus
                elide: Text.ElideRight
                text: fieldRoot.placeholderText
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.mutedInk
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // 1. Summary metrics + mode & search controls strip
        Item {
            id: summaryStrip
            objectName: "yearlySummaryStrip"
            Layout.fillWidth: true
            Layout.preferredHeight: stripFlow.implicitHeight + 6

            Flow {
                id: stripFlow
                width: parent.width
                spacing: 6

                // Core macro metrics
                Rectangle {
                    height: Math.round(26 * Appearance.fontSizeScale)
                    width: statsRow.implicitWidth + 14
                    radius: height / 2
                    color: Qt.alpha(root.ink, 0.05)

                    Row {
                        id: statsRow
                        anchors.centerIn: parent
                        spacing: 10

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("%1 plans").arg(root.boardData.summary.planCount)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.ink
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "·"
                            color: root.mutedInk
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("%1 trips").arg(root.boardData.summary.tripCount)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.mutedInk
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "·"
                            color: root.mutedInk
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("%1d away").arg(root.boardData.summary.daysAway)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            color: root.mutedInk
                        }
                    }
                }

                // Next plan quick chip
                PillButton {
                    visible: root.boardData.summary.nextPlan !== null
                    symbol: "event_upcoming"
                    label: root.boardData.summary.nextPlan
                        ? (Translation.tr("Next") + ": " + root.boardData.summary.nextPlan.title + " (" + root.formatShortDate(root.boardData.summary.nextPlan.startIso) + ")")
                        : ""
                    onClicked: root.openEditorForSpan(root.boardData.summary.nextPlan)
                }

                // Up next quick chip
                PillButton {
                    visible: root.width >= 900 && root.boardData.summary.upNextPlan !== null
                    label: root.boardData.summary.upNextPlan
                        ? (Translation.tr("Up next") + ": " + root.boardData.summary.upNextPlan.title + " (" + root.formatShortDate(root.boardData.summary.upNextPlan.startIso) + ")")
                        : ""
                    onClicked: root.openEditorForSpan(root.boardData.summary.upNextPlan)
                }

                // Last plan quick chip
                PillButton {
                    visible: root.width >= 1040 && root.boardData.summary.lastPlan !== null
                    fgColor: root.mutedInk
                    label: root.boardData.summary.lastPlan
                        ? (Translation.tr("Last") + ": " + root.boardData.summary.lastPlan.title)
                        : ""
                    onClicked: root.openEditorForSpan(root.boardData.summary.lastPlan)
                }

                // Calendar | Rolling 12 toggle
                Row {
                    spacing: 3
                    PillButton {
                        objectName: "yearlyModeCalendar"
                        label: Translation.tr("Calendar")
                        activeTint: root.rangeMode === "calendar"
                        onClicked: root.requestRangeModeChange("calendar")
                    }
                    PillButton {
                        objectName: "yearlyModeRolling"
                        label: Translation.tr("Rolling 12")
                        activeTint: root.rangeMode === "rolling"
                        onClicked: root.requestRangeModeChange("rolling")
                    }
                }

                // Search toggle / inline input
                Rectangle {
                    id: searchBox
                    visible: root.searchOpen || root.searchQuery.length > 0
                    height: Math.round(26 * Appearance.fontSizeScale)
                    width: Math.min(200, Math.max(140, root.width * 0.22))
                    radius: height / 2
                    color: Qt.alpha(root.ink, 0.08)
                    border.width: searchInput.activeFocus ? 1 : 0
                    border.color: root.headerAccent

                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                        spacing: 4
                        MaterialSymbol {
                            text: "search"
                            iconSize: 14
                            color: root.mutedInk
                        }
                        TextInput {
                            id: searchInput
                            objectName: "yearlySearchInput"
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            color: root.ink
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            clip: true
                            selectByMouse: true
                            onTextChanged: root.searchQuery = text
                            onAccepted: root.focusSearch()
                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !searchInput.text.length && !searchInput.activeFocus
                                text: Translation.tr("Search...")
                                color: root.mutedInk
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        RippleButton {
                            implicitWidth: 18
                            implicitHeight: 18
                            buttonRadius: 9
                            colBackground: "transparent"
                            colBackgroundHover: Qt.alpha(root.ink, 0.14)
                            onClicked: root.clearOrCloseSearch()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 12
                                color: root.mutedInk
                            }
                        }
                    }
                }

                PillButton {
                    objectName: "yearlySearchToggle"
                    visible: !root.searchOpen && !root.searchQuery.length
                    symbol: "search"
                    label: "/"
                    onClicked: root.focusSearch()
                }

                // Add Plan button
                PillButton {
                    objectName: "yearlyAddButton"
                    symbol: "add"
                    label: Translation.tr("Plan")
                    activeTint: true
                    onClicked: root.openNewPlanForDate(root.todayIso)
                }
            }
        }

        // Floating drag feedback badge
        Rectangle {
            visible: root.dragEventId >= 0 && root.dragPreviewStartIso.length > 0
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: dragFeedbackText.implicitWidth + 16
            implicitHeight: 22
            radius: 11
            color: root.headerAccent
            StyledText {
                id: dragFeedbackText
                anchors.centerIn: parent
                text: root.formatShortDate(root.dragPreviewStartIso) + " → " + root.formatShortDate(root.dragPreviewEndIso)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimary
            }
        }

        // 2. Main workspace row: [1..31 Board] + [Quick Plan Editor]
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            columns: root.width < 760 ? 1 : 2
            columnSpacing: 8
            rowSpacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                spacing: 0

                // Pinned 1..31 header aligned with boardViewport horizontal scroll
                Item {
                    id: dayHeaderBar
                    objectName: "yearlyDayHeader"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(24 * Appearance.fontSizeScale)
                    clip: true

                    Row {
                        x: -boardViewport.contentX
                        width: root.monthColWidth + root.boardGridWidth
                        height: parent.height

                        Item {
                            width: root.monthColWidth
                            height: parent.height
                            StyledText {
                                anchors.centerIn: parent
                                text: root.rangeMode === "rolling"
                                    ? String(root.boardData.months[0].year)
                                    : String(root.anchorDate.getFullYear())
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.numbers
                                color: root.headerTodayInk
                            }
                        }

                        Repeater {
                            model: 31
                            delegate: Item {
                                required property int index
                                width: root.dayColWidth
                                height: dayHeaderBar.height
                                StyledText {
                                    anchors.centerIn: parent
                                    text: String(index + 1)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    font.family: Appearance.font.family.numbers
                                    color: root.mutedInk
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 1
                        color: root.headerDivider
                    }
                }

                // 12-Month scrollable board
                Flickable {
                    id: boardViewport
                    objectName: "yearlyMonthBoard"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: root.monthColWidth + root.boardGridWidth
                    contentHeight: monthRowsColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    readonly property real baseMonthHeight: Math.max(42, Math.floor((height - 2) / 12))

                    Column {
                        id: monthRowsColumn
                        width: root.monthColWidth + root.boardGridWidth
                        spacing: 0

                        Repeater {
                            model: root.boardData.months
                            delegate: Item {
                                id: monthRow
                                required property var modelData
                                required property int index

                                readonly property int lanes: Math.max(1, modelData.laneCount || 1)
                                readonly property real laneStep: 19
                                readonly property real minRequiredHeight: 16 + lanes * laneStep + 4
                                width: monthRowsColumn.width
                                height: Math.max(boardViewport.baseMonthHeight, minRequiredHeight)

                                // Month separator
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 1
                                    color: Qt.alpha(root.ink, 0.08)
                                }

                                // Left Month label cell
                                Rectangle {
                                    width: root.monthColWidth
                                    height: parent.height - 1
                                    color: {
                                        const now = new Date()
                                        return (monthRow.modelData.year === now.getFullYear() && monthRow.modelData.monthIndex === now.getMonth())
                                            ? Qt.alpha(root.headerAccent, 0.12)
                                            : Qt.alpha(root.ink, 0.03)
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: monthRow.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: {
                                            const now = new Date()
                                            return (monthRow.modelData.year === now.getFullYear() && monthRow.modelData.monthIndex === now.getMonth())
                                                ? Font.Bold : Font.Medium
                                        }
                                        color: {
                                            const now = new Date()
                                            return (monthRow.modelData.year === now.getFullYear() && monthRow.modelData.monthIndex === now.getMonth())
                                                ? root.headerTodayInk : root.ink
                                        }
                                    }

                                    Rectangle {
                                        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                                        width: 1
                                        color: root.headerDivider
                                    }
                                }

                                // 31 Day columns
                                Row {
                                    x: root.monthColWidth
                                    width: root.boardGridWidth
                                    height: parent.height - 1

                                    Repeater {
                                        model: 31
                                        delegate: Rectangle {
                                            id: dayCell
                                            required property int index
                                            readonly property bool validDay: index < monthRow.modelData.daysInMonth
                                            readonly property var dayObj: validDay ? monthRow.modelData.days[index] : null
                                            width: root.dayColWidth
                                            height: monthRow.height - 1
                                            color: {
                                                if (!validDay)
                                                    return Qt.alpha(root.ink, 0.04)
                                                if (dayObj.isToday)
                                                    return Qt.alpha(root.headerAccent, 0.20)
                                                if (cellHover.containsMouse)
                                                    return Qt.alpha(root.headerAccent, 0.10)
                                                if (dayObj.isPast)
                                                    return Qt.alpha(root.ink, dayObj.isWeekend ? 0.045 : 0.025)
                                                return dayObj.isWeekend ? Qt.alpha(root.ink, 0.03) : "transparent"
                                            }
                                            border.width: dayObj?.isToday ? 1 : 0
                                            border.color: root.headerAccent

                                            // Right hairline
                                            Rectangle {
                                                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                                                width: 1
                                                color: Qt.alpha(root.ink, 0.05)
                                            }

                                            MouseArea {
                                                id: cellHover
                                                anchors.fill: parent
                                                enabled: dayCell.validDay
                                                hoverEnabled: true
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (dayCell.dayObj)
                                                        root.openNewPlanForDate(dayCell.dayObj.iso)
                                                }
                                                onDoubleClicked: {
                                                    if (dayCell.dayObj) {
                                                        const dt = YearlyPolicy.parseIsoDate(dayCell.dayObj.iso)
                                                        if (dt)
                                                            root.requestJumpToWeek(dt)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Month-wrap horizontal span bars layer
                                Item {
                                    x: root.monthColWidth
                                    width: root.boardGridWidth
                                    height: parent.height - 1
                                    z: 4

                                    Repeater {
                                        model: monthRow.modelData.segments
                                        delegate: Rectangle {
                                            id: planBar
                                            required property var modelData
                                            objectName: "yearlyPlanBar"

                                            readonly property var seg: modelData
                                            readonly property var span: modelData.span
                                            readonly property color baseCol: root.resolveBarColor(span.color)
                                            readonly property color fgCol: root.contrastOnBar(baseCol)
                                            readonly property real baseX: (seg.startDay - 1) * root.dayColWidth + (seg.wrapLeft ? 0 : 1.5)
                                            readonly property real baseWidth: Math.max(8, seg.dayLength * root.dayColWidth - (seg.wrapLeft ? 0 : 1.5) - (seg.wrapRight ? 0 : 1.5))

                                            property bool draggingBody: false
                                            property real dragDeltaX: 0
                                            property string activeEdge: ""
                                            property real resizeDeltaX: 0

                                            x: baseX + (draggingBody ? dragDeltaX : (activeEdge === "start" ? resizeDeltaX : 0))
                                            y: 5 + seg.lane * monthRow.laneStep
                                            width: {
                                                if (activeEdge === "start")
                                                    return Math.max(root.dayColWidth * 0.85, baseWidth - resizeDeltaX)
                                                if (activeEdge === "end")
                                                    return Math.max(root.dayColWidth * 0.85, baseWidth + resizeDeltaX)
                                                return baseWidth
                                            }
                                            height: 16
                                            radius: 5
                                            color: baseCol
                                            opacity: span.isPast ? 0.65 : (barMouse.containsMouse || root.editingEventId === span.id ? 1.0 : 0.92)
                                            border.width: root.editingEventId === span.id ? 1.5 : 0
                                            border.color: root.ink

                                            // Flatten rounded corners cleanly when wrapped across month boundaries
                                            Rectangle {
                                                visible: planBar.seg.wrapLeft
                                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                                width: parent.radius
                                                color: parent.color
                                            }
                                            Rectangle {
                                                visible: planBar.seg.wrapRight
                                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                                width: parent.radius
                                                color: parent.color
                                            }

                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                                spacing: 3
                                                visible: planBar.seg.showLabel

                                                StyledText {
                                                    visible: planBar.seg.wrapLeft
                                                    text: "‹"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    color: planBar.fgCol
                                                }

                                                MaterialSymbol {
                                                    visible: planBar.span.kind !== "plan" && planBar.width >= 34
                                                    text: planBar.span.kind === "trip" ? "flight" : "flag"
                                                    iconSize: 11
                                                    color: planBar.fgCol
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: {
                                                        const base = planBar.span.title + " · " + planBar.span.dayCount + "d"
                                                        return planBar.span.checklistTotal > 0
                                                            ? base + " · " + planBar.span.checklistDone + "/" + planBar.span.checklistTotal
                                                            : base
                                                    }
                                                    font.pixelSize: Math.max(10, Math.round(10.5 * Appearance.fontSizeScale))
                                                    font.weight: Font.DemiBold
                                                    color: planBar.fgCol
                                                }

                                                StyledText {
                                                    visible: planBar.seg.wrapRight
                                                    text: "›"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    color: planBar.fgCol
                                                }
                                            }

                                            // Body click + horizontal drag-move
                                            MouseArea {
                                                id: barMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                preventStealing: true
                                                cursorShape: planBar.draggingBody ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                                property real pressGlobalX: 0
                                                property bool moved: false

                                                onPressed: mouse => {
                                                    pressGlobalX = mapToItem(monthRow, mouse.x, mouse.y).x
                                                    moved = false
                                                    planBar.dragDeltaX = 0
                                                    planBar.draggingBody = false
                                                }
                                                onPositionChanged: mouse => {
                                                    if (!pressed) return
                                                    const curX = mapToItem(monthRow, mouse.x, mouse.y).x
                                                    const dx = curX - pressGlobalX
                                                    if (!moved && Math.abs(dx) < 5) return
                                                    moved = true
                                                    planBar.draggingBody = true
                                                    planBar.dragDeltaX = dx
                                                    const deltaDays = Math.round(dx / root.dayColWidth)
                                                    const shifted = YearlyPolicy.shiftSpanRange(planBar.span.startIso, planBar.span.endIso, deltaDays)
                                                    if (shifted) {
                                                        root.dragEventId = planBar.span.id
                                                        root.dragPreviewStartIso = shifted.startIso
                                                        root.dragPreviewEndIso = shifted.endIso
                                                    }
                                                }
                                                onReleased: {
                                                    const wasMoved = moved
                                                    const deltaDays = Math.round(planBar.dragDeltaX / root.dayColWidth)
                                                    moved = false
                                                    planBar.draggingBody = false
                                                    planBar.dragDeltaX = 0
                                                    root.dragEventId = -1
                                                    root.dragPreviewStartIso = ""
                                                    root.dragPreviewEndIso = ""
                                                    if (wasMoved && deltaDays !== 0) {
                                                        const shifted = YearlyPolicy.shiftSpanRange(planBar.span.startIso, planBar.span.endIso, deltaDays)
                                                        if (shifted && root.localBackend && typeof root.localBackend.rescheduleYearlyRange === "function")
                                                            root.localBackend.rescheduleYearlyRange(planBar.span.id, shifted.startIso, shifted.endIso)
                                                    } else if (!wasMoved) {
                                                        root.openEditorForSpan(planBar.span)
                                                    }
                                                }
                                                onCanceled: {
                                                    moved = false
                                                    planBar.draggingBody = false
                                                    planBar.dragDeltaX = 0
                                                    root.dragEventId = -1
                                                }
                                                onDoubleClicked: {
                                                    const dt = YearlyPolicy.parseIsoDate(planBar.span.startIso)
                                                    if (dt)
                                                        root.requestJumpToWeek(dt)
                                                }
                                            }

                                            // Left edge resize handle
                                            MouseArea {
                                                visible: !planBar.seg.wrapLeft && planBar.width >= 20
                                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                                width: 6
                                                z: 2
                                                preventStealing: true
                                                cursorShape: Qt.SizeHorCursor
                                                property real pressGlobalX: 0
                                                onPressed: mouse => {
                                                    pressGlobalX = mapToItem(monthRow, mouse.x, mouse.y).x
                                                    planBar.activeEdge = "start"
                                                    planBar.resizeDeltaX = 0
                                                }
                                                onPositionChanged: mouse => {
                                                    if (!pressed) return
                                                    const dx = mapToItem(monthRow, mouse.x, mouse.y).x - pressGlobalX
                                                    planBar.resizeDeltaX = dx
                                                    const deltaDays = Math.round(dx / root.dayColWidth)
                                                    const candidate = YearlyPolicy.addDaysIso(planBar.span.startIso, deltaDays)
                                                    const next = YearlyPolicy.resizeSpanRange(planBar.span.startIso, planBar.span.endIso, "start", candidate)
                                                    if (next) {
                                                        root.dragEventId = planBar.span.id
                                                        root.dragPreviewStartIso = next.startIso
                                                        root.dragPreviewEndIso = next.endIso
                                                    }
                                                }
                                                onReleased: {
                                                    const deltaDays = Math.round(planBar.resizeDeltaX / root.dayColWidth)
                                                    planBar.activeEdge = ""
                                                    planBar.resizeDeltaX = 0
                                                    root.dragEventId = -1
                                                    root.dragPreviewStartIso = ""
                                                    root.dragPreviewEndIso = ""
                                                    if (deltaDays !== 0) {
                                                        const candidate = YearlyPolicy.addDaysIso(planBar.span.startIso, deltaDays)
                                                        const next = YearlyPolicy.resizeSpanRange(planBar.span.startIso, planBar.span.endIso, "start", candidate)
                                                        if (next && root.localBackend && typeof root.localBackend.rescheduleYearlyRange === "function")
                                                            root.localBackend.rescheduleYearlyRange(planBar.span.id, next.startIso, next.endIso)
                                                    }
                                                }
                                            }

                                            // Right edge resize handle
                                            MouseArea {
                                                visible: !planBar.seg.wrapRight && planBar.width >= 20
                                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                                width: 6
                                                z: 2
                                                preventStealing: true
                                                cursorShape: Qt.SizeHorCursor
                                                property real pressGlobalX: 0
                                                onPressed: mouse => {
                                                    pressGlobalX = mapToItem(monthRow, mouse.x, mouse.y).x
                                                    planBar.activeEdge = "end"
                                                    planBar.resizeDeltaX = 0
                                                }
                                                onPositionChanged: mouse => {
                                                    if (!pressed) return
                                                    const dx = mapToItem(monthRow, mouse.x, mouse.y).x - pressGlobalX
                                                    planBar.resizeDeltaX = dx
                                                    const deltaDays = Math.round(dx / root.dayColWidth)
                                                    const candidate = YearlyPolicy.addDaysIso(planBar.span.endIso, deltaDays)
                                                    const next = YearlyPolicy.resizeSpanRange(planBar.span.startIso, planBar.span.endIso, "end", candidate)
                                                    if (next) {
                                                        root.dragEventId = planBar.span.id
                                                        root.dragPreviewStartIso = next.startIso
                                                        root.dragPreviewEndIso = next.endIso
                                                    }
                                                }
                                                onReleased: {
                                                    const deltaDays = Math.round(planBar.resizeDeltaX / root.dayColWidth)
                                                    planBar.activeEdge = ""
                                                    planBar.resizeDeltaX = 0
                                                    root.dragEventId = -1
                                                    root.dragPreviewStartIso = ""
                                                    root.dragPreviewEndIso = ""
                                                    if (deltaDays !== 0) {
                                                        const candidate = YearlyPolicy.addDaysIso(planBar.span.endIso, deltaDays)
                                                        const next = YearlyPolicy.resizeSpanRange(planBar.span.startIso, planBar.span.endIso, "end", candidate)
                                                        if (next && root.localBackend && typeof root.localBackend.rescheduleYearlyRange === "function")
                                                            root.localBackend.rescheduleYearlyRange(planBar.span.id, next.startIso, next.endIso)
                                                    }
                                                }
                                            }

                                            StyledToolTip {
                                                text: {
                                                    let tip = planBar.span.title + " (" + planBar.span.startIso + " → " + planBar.span.endIso + ", " + planBar.span.dayCount + "d)"
                                                    if (planBar.span.place.length) tip += "\n" + planBar.span.place
                                                    if (planBar.span.checklistTotal > 0) tip += "\n" + planBar.span.checklistDone + "/" + planBar.span.checklistTotal + " checklist"
                                                    return tip
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. Inline Quick Plan Editor Drawer
            Rectangle {
                id: editorDrawer
                objectName: "yearlyPlanEditor"
                visible: root.editorOpen
                Layout.fillHeight: root.width >= 760
                Layout.fillWidth: root.width < 760
                Layout.preferredWidth: root.width < 760 ? root.width : Math.round(308 * Appearance.fontSizeScale)
                Layout.minimumWidth: 0
                Layout.maximumWidth: root.width
                Layout.preferredHeight: root.width < 760 ? Math.min(340, Math.round(root.height * 0.56)) : -1
                radius: Appearance.rounding.normal
                color: Qt.alpha(root.ink, 0.04)
                border.width: 1
                border.color: root.headerDivider
                clip: true

                Flickable {
                    id: editorFlick
                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: width
                    contentHeight: editorCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ColumnLayout {
                        id: editorCol
                        width: editorFlick.width
                        spacing: 8

                        // Header
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: root.editingEventId >= 0 ? Translation.tr("Edit plan") : Translation.tr("New plan")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: root.ink
                            }
                            RippleButton {
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: 13
                                colBackground: "transparent"
                                colBackgroundHover: Qt.alpha(root.ink, 0.1)
                                onClicked: root.closeEditor()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 16
                                    color: root.mutedInk
                                }
                            }
                        }

                        // Plan | Trip | Milestone selector
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            PillButton {
                                objectName: "yearlyKindPlan"
                                Layout.fillWidth: true
                                label: Translation.tr("Plan")
                                symbol: "event"
                                activeTint: root.draftKind === "plan"
                                onClicked: root.draftKind = "plan"
                            }
                            PillButton {
                                objectName: "yearlyKindTrip"
                                Layout.fillWidth: true
                                label: Translation.tr("Trip")
                                symbol: "flight"
                                activeTint: root.draftKind === "trip"
                                onClicked: root.draftKind = "trip"
                            }
                            PillButton {
                                objectName: "yearlyKindMilestone"
                                Layout.fillWidth: true
                                label: Translation.tr("Milestone")
                                symbol: "flag"
                                activeTint: root.draftKind === "milestone"
                                onClicked: root.draftKind = "milestone"
                            }
                        }

                        // Title input
                        CompactField {
                            id: titleInput
                            objectName: "yearlyTitleInput"
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Plan title")
                            onTextChanged: root.draftTitle = text
                            onAccepted: root.saveDraft()
                        }

                        // Start & End ISO dates with steppers
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    text: Translation.tr("Start")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.mutedInk
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 28
                                        buttonRadius: 6
                                        colBackground: Qt.alpha(root.ink, 0.07)
                                        onClicked: root.stepDraftDate("start", -1)
                                        contentItem: StyledText { anchors.centerIn: parent; text: "−"; color: root.ink }
                                    }
                                    CompactField {
                                        id: startDateInput
                                        objectName: "yearlyStartInput"
                                        Layout.fillWidth: true
                                        placeholderText: "YYYY-MM-DD"
                                        onTextChanged: root.draftStartIso = text
                                    }
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 28
                                        buttonRadius: 6
                                        colBackground: Qt.alpha(root.ink, 0.07)
                                        onClicked: root.stepDraftDate("start", 1)
                                        contentItem: StyledText { anchors.centerIn: parent; text: "+"; color: root.ink }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    text: Translation.tr("End")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.mutedInk
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 28
                                        buttonRadius: 6
                                        colBackground: Qt.alpha(root.ink, 0.07)
                                        onClicked: root.stepDraftDate("end", -1)
                                        contentItem: StyledText { anchors.centerIn: parent; text: "−"; color: root.ink }
                                    }
                                    CompactField {
                                        id: endDateInput
                                        objectName: "yearlyEndInput"
                                        Layout.fillWidth: true
                                        placeholderText: "YYYY-MM-DD"
                                        onTextChanged: root.draftEndIso = text
                                    }
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 28
                                        buttonRadius: 6
                                        colBackground: Qt.alpha(root.ink, 0.07)
                                        onClicked: root.stepDraftDate("end", 1)
                                        contentItem: StyledText { anchors.centerIn: parent; text: "+"; color: root.ink }
                                    }
                                }
                            }
                        }

                        // Place & Notes
                        CompactField {
                            id: placeInput
                            objectName: "yearlyPlaceInput"
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Place (optional)")
                            onTextChanged: root.draftPlace = text
                        }

                        CompactField {
                            id: notesInput
                            objectName: "yearlyNotesInput"
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Notes (optional)")
                            onTextChanged: root.draftNotes = text
                        }

                        // Color swatches
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                text: Translation.tr("Color")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.mutedInk
                            }
                            Repeater {
                                model: root.swatches
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: modelData.length ? modelData : root.headerAccent
                                    border.width: root.draftColor === modelData ? 2 : 0
                                    border.color: root.ink
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.draftColor = modelData
                                    }
                                }
                            }
                        }

                        // Interactive Checklist
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Checklist")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: root.ink
                            }
                            StyledText {
                                readonly property int doneCount: root.draftChecklist.filter(i => i.done).length
                                text: doneCount + "/" + root.draftChecklist.length
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.numbers
                                color: root.mutedInk
                            }
                        }

                        Repeater {
                            model: root.draftChecklist
                            delegate: RowLayout {
                                id: checkRow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 6

                                RippleButton {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: 5
                                    colBackground: checkRow.modelData.done ? root.headerAccent : Qt.alpha(root.ink, 0.08)
                                    onClicked: root.toggleChecklistEntry(checkRow.index)
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: checkRow.modelData.done
                                        text: "check"
                                        iconSize: 14
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: checkRow.modelData.text
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.strikeout: checkRow.modelData.done
                                    color: checkRow.modelData.done ? root.mutedInk : root.ink
                                }

                                RippleButton {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    buttonRadius: 10
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(root.ink, 0.1)
                                    onClicked: root.removeChecklistEntry(checkRow.index)
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 12
                                        color: root.mutedInk
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            CompactField {
                                id: checklistInput
                                objectName: "yearlyChecklistInput"
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Add item")
                                onAccepted: root.addChecklistEntry()
                            }
                            PillButton {
                                objectName: "yearlyChecklistAddButton"
                                symbol: "add"
                                onClicked: root.addChecklistEntry()
                            }
                        }

                        StyledText {
                            visible: root.draftError.length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.draftError
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colError
                        }

                        // Action bar
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6

                            PillButton {
                                objectName: "yearlySaveButton"
                                symbol: "check"
                                label: Translation.tr("Save")
                                activeTint: true
                                onClicked: root.saveDraft()
                            }

                            PillButton {
                                objectName: "yearlyCancelButton"
                                label: Translation.tr("Cancel")
                                onClicked: root.closeEditor()
                            }

                            PillButton {
                                objectName: "yearlyJumpWeekButton"
                                symbol: "calendar_view_week"
                                label: Translation.tr("Week")
                                onClicked: {
                                    const dt = YearlyPolicy.parseIsoDate(root.draftStartIso) || root.anchorDate
                                    root.requestJumpToWeek(dt)
                                }
                            }

                            Item { Layout.fillWidth: true }

                            PillButton {
                                objectName: "yearlyDeleteButton"
                                visible: root.editingEventId >= 0
                                symbol: "delete"
                                label: root.deleteConfirmPending ? Translation.tr("Confirm") : ""
                                fgColor: root.deleteConfirmPending ? Appearance.colors.colError : root.mutedInk
                                onClicked: root.deleteEditingPlan()
                            }
                        }
                    }
                }
            }
        }
    }
}
