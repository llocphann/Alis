pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sidebarRight.events
import qs.modules.common.functions
import qs.modules.abyss.looks
import "WeeklyPlannerPolicy.js" as Planner
import "PlannerGesture.js" as Gesture
import "PlannerSelection.js" as Selection
import "PlannerEventPalette.js" as EventPalette
import "../../services/EventFutureSchedule.js" as FutureSchedule

Item {
    id: root
    objectName: "dashboardWeeklyPlanner"
    property bool presentationActive: false
    property var localBackend: Events
    property var externalBackend: CalendarSync
    property date selectedDate: new Date()
    property bool followToday: true
    property string sideView: ""
    property bool _inlineEventsLoaded: false
    property var _pendingInlineEvent: null
    property bool _initialized: false
    readonly property string todayKey: Qt.formatDate(DateTime.clock.date,"yyyy-MM-dd")
    // A tab reactivation should not replace today's date object just because
    // the wall clock advanced by a few seconds. That unnecessarily invalidates
    // Planner.project(), the seven-day grid, and event delegates mid-slide.
    function refreshFollowingToday(): void {
        if (!root._initialized || !root.followToday) return
        const today = DateTime.clock.date
        if (Qt.formatDate(root.selectedDate, "yyyy-MM-dd")
                !== Qt.formatDate(today, "yyyy-MM-dd"))
            root.selectedDate = today
    }
    onTodayKeyChanged: root.refreshFollowingToday()
    onSelectedDateChanged: {clearEventSelection();storeBrowser()}
    onFollowTodayChanged: storeBrowser()
    onSideViewChanged: {
        // Click-created ID selections belong to the inline editor session;
        // manual Ctrl/region selections remain independent of panel changes.
        if (sideView!=="events" && root.followEditorCalendarSelection) {
            root.clearEventSelection()
            root.restoreEditorSelection=true
        } else if (sideView==="events" && root.restoreEditorSelection) {
            root.restoreEditorSelection=false
            const form=inlineEventsPanel.item
            if (form?.isEditing) {
                const rows=root.selectableEventRows.filter(row=>row.source==="local"
                    && row.event.id===form.editingEvent.id)
                root.selectedEventKeys=(form.hasUnsavedChanges()
                    ? rows.filter(row=>form.plannerSelectedDateKeys.includes(
                        Qt.formatDate(new Date(row.startDate),"yyyy-MM-dd"))) : rows
                    ).map(row=>Selection.key(row))
                root.explicitGridSelection=true
                root.followEditorCalendarSelection=true
            }
        }
        storeBrowser()
    }
    onPresentationActiveChanged: if (presentationActive) root.refreshFollowingToday()
    property bool expandAllDay: false
    property int activeDragDay: -1
    property var selectedEventKeys: []
    // Once a grid selection is explicitly made, do not restore the editor's
    // broader visual outline over a Ctrl-deselected individual occurrence.
    property bool explicitGridSelection: false
    // A click opens Edit Event and selects its ID group. Later changes made
    // inside that editor's date picker should update exactly those outlines,
    // unless Ctrl/range/manual selection has explicitly taken ownership.
    property bool followEditorCalendarSelection: false
    property bool restoreEditorSelection: false
    property string selectionAnchorKey: ""
    property bool deleteConfirmation: false
    property var activeGroupGesture: null
    property var selectionRegion: null
    onSelectedEventKeysChanged: deleteConfirmation=false
    readonly property var selectableEventRows: Selection.ordered(root.days)
    readonly property var selectedEventRows: root.selectableEventRows.filter(
        row=>root.selectedEventKeys.includes(Selection.key(row)))
    readonly property bool canDeleteSelection: root.selectedEventRows.length>0
        && root.selectedEventRows.every(row=>Selection.canDelete(row))
    function finishSelectionRegion(): void {
        const region=root.selectionRegion
        if (!region) return
        const hits=[]
        function visit(item) {
            if ((item.objectName==="plannerTimedEvent" || item.objectName==="plannerAllDayEvent")
                    && Selection.canSelect(item.modelData)) {
                const p=item.mapToItem(viewport.contentItem,0,0)
                if (p.x<region.right && p.x+item.width>region.left
                        && p.y<region.bottom && p.y+item.height>region.top)
                    hits.push(Selection.key(item.modelData))
            }
            for (const child of item.children || []) visit(child)
        }
        visit(viewport.contentItem)
        root.selectedEventKeys=Array.from(new Set(region.before.concat(hits)))
        if (hits.length) {
            root.explicitGridSelection=true
            root.followEditorCalendarSelection=false
            root.selectionAnchorKey=hits[0]
        }
        root.selectionRegion=null
        root.forceActiveFocus()
    }
    function isEventSelected(row): bool {
        return root.selectedEventKeys.includes(Selection.key(row))
    }
    // The editor's chosen dates are visual context. Only explicit grid
    // selection authorizes a batch gesture or selected-occurrence deletion.
    readonly property var editorEventSelection: {
        const form=inlineEventsPanel.item
        return root.sideView==="events" && form?.isEditing
            ? {id:form.editingEvent?.id,days:form.plannerSelectedDateKeys} : null
    }
    onEditorEventSelectionChanged: {
        const selection=root.editorEventSelection
        const form=inlineEventsPanel.item
        // Loading a canonical editor record sets date keys before it
        // captures its pristine baseline. That is NOT a user deselection.
        if (!root.followEditorCalendarSelection || !selection
                || root._pendingInlineEvent!==null
                || !form?.hasUnsavedChanges()) return
        // A user explicitly changed selected dates inside the editor.
        // Reconcile actual gesture membership, not only an editor outline.
        root.selectedEventKeys=root.selectableEventRows.filter(row=>
            row.source==="local" && row.event?.id===selection.id
                && selection.days.includes(Qt.formatDate(
                    new Date(row.startDate),"yyyy-MM-dd"))
        ).map(row=>Selection.key(row))
    }
    function isEditorEvent(row): bool {
        if (root.explicitGridSelection) return false
        const selected=root.editorEventSelection
        return !!selected && row?.source==="local" && row.event?.id===selected.id
            && selected.days.includes(Qt.formatDate(new Date(row.startDate),"yyyy-MM-dd"))
    }
    function clearEventSelection(): void {
        root.selectedEventKeys=[]
        root.explicitGridSelection=false
        root.followEditorCalendarSelection=false
        root.restoreEditorSelection=false
        root.selectionAnchorKey=""
        root.deleteConfirmation=false
        root.activeGroupGesture=null
        root.selectionRegion=null
    }
    function selectEventId(row): void {
        const keys=Selection.groupKeys(root.selectableEventRows,row)
        if (!keys.length) return
        root.selectedEventKeys=keys
        root.selectionAnchorKey=Selection.key(row)
        root.explicitGridSelection=true
    }
    function gestureTargets(row) {
        if (!Selection.canReschedule(row) && !Selection.canSelect(row)) return []
        const targets=root.isEventSelected(row) && root.selectedEventRows.length>1
            ? root.selectedEventRows : [row]
        // A direct historical edit is explicit. Never propagate a selected
        // recurring group backwards into its other already-past occurrences.
        return targets.filter(target=>Selection.gestureKey(target)===Selection.gestureKey(row)
            || (target.event?.recurrence || "none")==="none"
            || new Date(target.startDate)>=DateTime.clock.date)
    }
    function clickPlannerEvent(row,modifiers): void {
        const ctrl=!!(modifiers & Qt.ControlModifier)
        const shift=!!(modifiers & Qt.ShiftModifier)
        if (ctrl || shift) {
            const result=Selection.choose(root.selectableEventRows,
                root.selectedEventKeys,root.selectionAnchorKey,row,ctrl,shift)
            if (!result) return
            root.explicitGridSelection=true
            root.followEditorCalendarSelection=false
            root.selectedEventKeys=result.keys
            root.selectionAnchorKey=result.anchor
            root.forceActiveFocus()
        } else {
            const group=Selection.groupKeys(root.selectableEventRows,row)
            // Clicking any member of a partly Ctrl-deselected group restores
            // the full ID group. A complete group stays selected without
            // repeatedly reopening an already-loaded editor.
            const alreadyComplete=group.length>0
                && root.selectedEventKeys.length===group.length
                && group.every(key=>root.selectedEventKeys.includes(key))
            if (!alreadyComplete) {
                root.clearEventSelection()
                root.selectEventId(row)
                root.followEditorCalendarSelection=true
                // Keep normal one-click editing as before.
                root.editOccurrence(row)
            }
        }
    }
    function confirmOrDeleteSelected(): void {
        if (!root.canDeleteSelection) return
        if (!root.deleteConfirmation) {root.deleteConfirmation=true;return}
        if (typeof root.localBackend.applyPlannerOccurrenceBatch!=="function")
            return
        const form=inlineEventsPanel.item
        const editedIsSelected=form && form.isEditing
            && root.selectedEventRows.some(row=>row.event.id===form.editingEvent?.id
                && row.occurrenceIndex===form.editingOccurrenceIndex)
        if (editedIsSelected && form.hasUnsavedChanges()) {
            form.editorWarning=Translation.tr(
                "Save or Cancel the current event before deleting selected events.")
            root.deleteConfirmation=false
            return
        }
        const actions=root.selectedEventRows.map(row=>({
            id:row.event.id,occurrenceIndex:row.occurrenceIndex,remove:true
        }))
        if (root.localBackend.applyPlannerOccurrenceBatch(actions)) {
            root.clearEventSelection()
            if (editedIsSelected) root.closeInlineEventEditor()
        } else root.deleteConfirmation=false
    }
    function handleSelectionKey(event): bool {
        if (event.key===Qt.Key_Escape && root.selectedEventKeys.length>0) {
            root.clearEventSelection()
            return true
        }
        if ((event.key===Qt.Key_Delete || event.key===Qt.Key_Backspace)
                && root.selectedEventRows.length>0) {
            // Recurring group selection is for safe move/resize only.
            if (root.canDeleteSelection) root.confirmOrDeleteSelected()
            return true
        }
        return false
    }
    property real hourHeight: 52 * Appearance.fontSizeScale
    property int _eventsRevision: 0
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property var days: {
        const revision = root._eventsRevision
        return Planner.project(root.localBackend.list, root.externalBackend.events,
            root.selectedDate, root.firstDay, FutureSchedule)
    }
    readonly property int maximumMinutes: Math.max.apply(null, days.map(day => day.minutes))
    readonly property int allDayRows: Math.min(expandAllDay ? 512 : 4, Math.max.apply(null, days.map(day => day.allDay.length)))
    readonly property real allDayHeight: 24 + Math.max(1, allDayRows) * 26
    readonly property real gridTop: 44 + allDayHeight
    readonly property real columnWidth: Math.max(102 * Appearance.fontSizeScale, (viewport.width - 44) / 7)
    readonly property color ink: Appearance.colors.colOnLayer1
    readonly property color mutedInk: Appearance.colors.colSubtext
    // Muted, curated Event swatches independent of wallpaper/theme. An
    // Event ID has one stable signature across its saved/virtual occurrences.
    function eventIdentityColor(row): color {
        const explicit=row?.event?.color || (row?.source==="external"
            ? row?.event?.sourceColor : null)
        if (explicit) {
            const saved=Qt.color(explicit)
            if (saved.valid) return saved
        }
        return Qt.color(EventPalette.eventSwatch(row?.event,row?.source))
    }
    // Match the pinned date and All-day headings to the Weekly Planner
    // background color so initial/scrolled timed events never show through.
    readonly property bool abyssPanel: Config.options?.panelFamily === "abyss"
    readonly property color headerSurface: abyssPanel
        ? AbyssStyle.surfaceDeep : Qt.alpha(Appearance.colors.colLayer0Base, 1)
    readonly property color headerInk: root.ink
    readonly property color headerMutedInk: root.mutedInk
    readonly property color headerAccent: abyssPanel
        ? AbyssStyle.accent : Appearance.colors.colPrimary
    readonly property color headerTodayInk: ColorUtils.ensureReadable(
        headerAccent, abyssPanel ? AbyssStyle.contentLayer : Appearance.colors.colLayer0, 4.5)
    readonly property color headerDivider: Qt.alpha(headerInk, .16)
    signal requestEventsDialog(var event)
    Connections {
        target: root.localBackend
        function onEventAdded(event) {root._eventsRevision++}
        function onEventUpdated(event) {root._eventsRevision++}
        function onEventRemoved(id) {root._eventsRevision++}
    }
    Connections {
        target: root.externalBackend
        function onEventsUpdated() {root._eventsRevision++}
    }
    function storeBrowser(): void {
        if (_initialized) GlobalStates.dashboardPlannerBrowser={
            date:selectedDate.toISOString(),followToday:followToday,
            sideView:sideView==="events"?"":sideView
        }
    }
    function openInlineEventEditor(arg): void {
        // New slot/event requests cannot silently replace an unsaved form.
        // The same form stays loaded behind the Todo/Notes columns.
        const current=inlineEventsPanel.item
        if (current && current.hasUnsavedChanges()) {
            sideView="events"
            current.editorWarning=Translation.tr("Save or Cancel the current event before opening another.")
            current.focusEditor()
            return
        }
        _pendingInlineEvent=arg
        _inlineEventsLoaded=true
        sideView="events"
        applyPendingInlineEvent()
    }
    function applyPendingInlineEvent(): void {
        const form=inlineEventsPanel.item
        if (!form || _pendingInlineEvent===null) return
        const arg=_pendingInlineEvent
        const date=arg?.plannerDate instanceof Date ? arg.plannerDate
            : (arg instanceof Date ? arg : null)
        if (date) {
            form.resetForm()
            form.eventDate=date
            if (arg?.plannerDate instanceof Date) {
                form.eventTime=Qt.formatTime(date,"hh:mm")
                form.eventEndTime=Qt.formatTime(new Date(date.getTime()+3600000),"hh:mm")
            }
        } else if (arg) {
            form.loadEvent(arg)
        } else {
            form.resetForm()
        }
        form.captureFormBaseline()
        _pendingInlineEvent=null
        form.focusEditor()
    }
    function closeInlineEventEditor(): void {
        _pendingInlineEvent=null
        if (root.followEditorCalendarSelection) root.clearEventSelection()
        if (sideView==="events") sideView=""
        _inlineEventsLoaded=false
    }
    function changeWeek(count): void {followToday=false;selectedDate=Planner.addDays(selectedDate,count*7)}
    function showToday(): void {followToday=true;selectedDate=new Date();scrollWorkingHours()}
    function commitTimedGesture(row, mode, dx, dy): void {
        const targets=root.gestureTargets(row)
        if (!targets.length) return
        const changes=[]
        for (const target of targets) {
            // A saved repeat slot is a single-instance override, not a
            // batch edit of the repeating series. Only non-repeating selection
            // uses the group policy (including all-day civil moves).
            const repeating=(target.event?.recurrence || "none")!=="none"
            const range=repeating ? Gesture.rangeForGesture(target,mode,dx,dy,
                    root.columnWidth,root.hourHeight)
                : Gesture.rangeForSelection(target,mode,dx,dy,
                    root.columnWidth,root.hourHeight)
            if (!range) {
                console.warn("[WeeklyPlanner] Unsupported group gesture; selection unchanged")
                return
            }
            changes.push({id:target.event.id,occurrenceIndex:target.occurrenceIndex,
                startIso:range.startIso,endIso:range.endIso,recurring:repeating,
                future:repeating,branchKey:target.plannerBranchKey,
                cycle:target.plannerScheduleCycle,previousStartIso:target.startDate.toISOString(),
                originalStartIso:target.virtual ? target.plannerOriginalStartIso : undefined})
        }
        const candidate=changes[0]
        if (targets.length>1 || changes[0].recurring) {
            if (typeof root.localBackend.applyPlannerOccurrenceBatch!=="function"
                    || !root.localBackend.applyPlannerOccurrenceBatch(changes)) {
                console.warn("[WeeklyPlanner] Group gesture rejected; no events changed")
                return
            }
        } else {
            const repeating=(row.event?.recurrence || "none")!=="none"
            const projected=repeating && row.virtual && !!row.plannerOriginalStartIso
            const method=projected ? "rescheduleProjectedRecurring"
                : repeating ? "rescheduleRecurringOccurrence" : "rescheduleOccurrence"
            if (typeof root.localBackend[method] !== "function") return
            const saved=projected
                ? root.localBackend[method](row.event.id,row.occurrenceIndex,
                    row.plannerOriginalStartIso,candidate.startIso,candidate.endIso)
                : root.localBackend[method](row.event.id,row.occurrenceIndex,
                    candidate.startIso,candidate.endIso)
            if (!saved) {
                console.warn("[WeeklyPlanner] Timed event gesture not saved")
                return
            }
        }
        root.clearEventSelection()
        // Preserve unsaved title/note; reconcile only a matching edited slot.
        const form=inlineEventsPanel.item
        if (form && form.isEditing) {
            for (const target of targets) {
                // An overridden virtual occurrence is not a saved series
                // member; do not rewrite its series editor calendar fields.
                if (target.virtual) continue
                if (form.editingEvent?.id===target.event.id
                        && form.editingOccurrenceIndex===target.occurrenceIndex) {
                    const changed=changes.find(change=>change.id===target.event.id
                        && change.occurrenceIndex===target.occurrenceIndex)
                    form.syncMovedOccurrence(target.event.id,target.startDate,
                        changed.startIso,changed.endIso)
                    break
                }
            }
        }
    }
    function editOccurrence(row): void {
        if (row.source!=="local") return
        root.requestEventsDialog(Object.assign({},row.event,{
            _editOccurrenceIndex:row.occurrenceIndex
        }))
    }
    function scrollWorkingHours(): void {
        viewport.contentY=Math.min(Math.max(0,viewport.contentHeight-viewport.height),hourHeight*8)
    }
    function panHorizontally(delta): bool {
        const before=viewport.contentX
        viewport.contentX=Math.max(0,Math.min(viewport.contentWidth-viewport.width,before-delta))
        return viewport.contentX!==before
    }
    Keys.onPressed: event => {
        // Unhandled editor keys must never navigate the week underneath a form.
        if (root.handleSelectionKey(event)) {event.accepted=true;return}
        if (root.sideView === "events") { event.accepted = false; return }
        if (event.key === Qt.Key_PageUp) {changeWeek(-1);event.accepted=true}
        else if (event.key === Qt.Key_PageDown) {changeWeek(1);event.accepted=true}
        else if (event.key === Qt.Key_Home) {showToday();event.accepted=true}
        else event.accepted=false
    }
    component Action: RippleButton {
        id:action
        property string label: ""
        property string symbol: ""
        property color buttonInk: root.ink
        implicitHeight:34 * Appearance.fontSizeScale
        implicitWidth:label.length
            ? actionRow.implicitWidth + 18 * Appearance.fontSizeScale
            : 34 * Appearance.fontSizeScale
        buttonRadius:12 * Appearance.fontSizeScale
        Accessible.name:label.length ? label : symbol
        colBackground:toggled ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover:Appearance.colors.colLayer1Hover
        // Qt Controls gives contentItem the available button rectangle.
        // Centre the actual glyph/text row within it for equal margins.
        contentItem: Item {
            implicitWidth:actionRow.implicitWidth
            implicitHeight:actionRow.implicitHeight
            Row {
                id:actionRow
                anchors.centerIn:parent
                spacing:5 * Appearance.fontSizeScale
                MaterialSymbol {
                    objectName:"plannerActionGlyph"
                    visible:action.symbol.length>0
                    text:action.symbol
                    iconSize:18 * Appearance.fontSizeScale
                    color:action.buttonInk
                }
                StyledText {
                    visible:action.label.length>0
                    text:action.label
                    color:action.buttonInk
                    font.pixelSize:Appearance.font.pixelSize.small
                }
            }
        }
    }
    ColumnLayout {
        anchors.fill:parent
        spacing:6
        ColumnLayout {
            Layout.fillWidth:true
            spacing:2 * Appearance.fontSizeScale
            Item {
                id:plannerToolbar
                objectName:"plannerToolbar"
                Layout.fillWidth:true
                Layout.preferredHeight:34 * Appearance.fontSizeScale
                // Anchor to the toolbar midpoint, independently of unequal
                // left navigation and right action widths. Stack when tight.
                readonly property bool compact:width < weekNav.width + weekTools.width
                    + Math.max(180 * Appearance.fontSizeScale, weekHeading.implicitWidth)
                    + 20 * Appearance.fontSizeScale
                Row {
                    id:weekNav
                    anchors.left:parent.left
                    anchors.verticalCenter:parent.verticalCenter
                    spacing:4 * Appearance.fontSizeScale
                    Action {
                        objectName:"plannerPreviousWeek"
                        symbol:"chevron_left"
                        Accessible.name:Translation.tr("Previous week")
                        onClicked:root.changeWeek(-1)
                    }
                    Action {label:Translation.tr("Today");onClicked:root.showToday()}
                    Action {
                        objectName:"plannerNextWeek"
                        symbol:"chevron_right"
                        Accessible.name:Translation.tr("Next week")
                        onClicked:root.changeWeek(1)
                    }
                }
                StyledText {
                    id:weekHeading
                    objectName:"plannerWeekHeading"
                    anchors.centerIn:parent
                    width:Math.max(0,parent.width
                        - 2*Math.max(weekNav.width,weekTools.width)
                        - 20*Appearance.fontSizeScale)
                    height:parent.height
                    visible:!plannerToolbar.compact
                    text:Qt.formatDate(root.days[0].date,"d MMM") + " – "
                        + Qt.formatDate(root.days[6].date,"d MMM yyyy")
                    horizontalAlignment:Text.AlignHCenter
                    font.weight:Font.Bold
                    font.pixelSize:Appearance.font.pixelSize.normal
                    color:root.headerTodayInk
                    elide:Text.ElideRight
                }
                Row {
                    id:weekTools
                    anchors.right:parent.right
                    anchors.verticalCenter:parent.verticalCenter
                    spacing:4 * Appearance.fontSizeScale
                    Action {
                        objectName:"plannerDeleteSelected"
                        // Repeating instances cannot be deleted by batch.
                        // No disabled destructive action or extra editor shortcut.
                        visible:root.canDeleteSelection
                        enabled:root.canDeleteSelection
                        label:root.deleteConfirmation
                            ? "Confirm delete ("+root.selectedEventRows.length+")"
                            : "Delete ("+root.selectedEventRows.length+")"
                        symbol:"delete"
                        buttonInk:root.deleteConfirmation
                            ? Appearance.colors.colError : root.headerInk
                        onClicked:root.confirmOrDeleteSelected()
                        StyledToolTip {
                            text:"Ctrl+Click to toggle · Shift+Click for range · Ctrl/Shift+drag background to select · Delete twice to confirm"
                        }
                    }
                    Action {
                        objectName:"plannerTodoAction"
                        symbol:"checklist"
                        Accessible.name:Translation.tr("To Do")
                        toggled:root.sideView==="todo"
                        onClicked:root.sideView=root.sideView==="todo"?"":"todo"
                    }
                    Action {
                        objectName:"plannerNotesAction"
                        symbol:"sticky_note_2"
                        Accessible.name:Translation.tr("Quick Notes")
                        toggled:root.sideView==="notes"
                        onClicked:root.sideView=root.sideView==="notes"?"":"notes"
                    }
                }
            }
            StyledText {
                objectName:"plannerCompactWeekHeading"
                visible:plannerToolbar.compact
                Layout.fillWidth:true
                Layout.preferredHeight:visible ? 24*Appearance.fontSizeScale : 0
                text:weekHeading.text
                horizontalAlignment:Text.AlignHCenter
                font.weight:Font.Bold
                font.pixelSize:Appearance.font.pixelSize.normal
                color:root.headerTodayInk
                elide:Text.ElideRight
            }
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth:0
            Layout.maximumWidth:root.width
            columns: root.width<760 ? 1 : 2
            columnSpacing:8;rowSpacing:8
            Flickable {
                id: viewport
                objectName: "weeklyPlannerViewport"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth:0
                Layout.preferredWidth:1
                Layout.minimumHeight: root.width<760 ? Math.min(110,Math.max(0,root.height-40)*.45) : 0
                clip:true
                contentWidth:44+root.columnWidth*7
                contentHeight:root.gridTop+root.maximumMinutes/60*root.hourHeight
                boundsBehavior:Flickable.StopAtBounds
                flickableDirection:Flickable.HorizontalAndVerticalFlick
                ScrollBar.vertical: ScrollBar {policy:ScrollBar.AlwaysOff}
                ScrollBar.horizontal: ScrollBar {policy:ScrollBar.AlwaysOff}
                Rectangle {
                    objectName:"plannerSelectionRegion"
                    z:100;visible:root.selectionRegion!==null
                    x:root.selectionRegion?.left ?? 0;y:root.selectionRegion?.top ?? 0
                    width:Math.max(0,(root.selectionRegion?.right ?? 0)-x)
                    height:Math.max(0,(root.selectionRegion?.bottom ?? 0)-y)
                    color:Qt.alpha(root.headerAccent,.12)
                    border.color:root.headerAccent;border.width:1
                }
                Repeater {
                    model: Math.ceil(root.maximumMinutes/60)
                    delegate: StyledText {
                        required property int index
                        y:root.gridTop+index*root.hourHeight-7;x:0;width:40
                        text:String(index).padStart(2,"0")+":00"
                        color:root.mutedInk;font.pixelSize:Appearance.font.pixelSize.smallest
                    }
                }
                Rectangle {
                    objectName:"plannerHeaderCorner"
                    x:0;y:viewport.contentY;width:44;height:root.gridTop;z:20
                    color:root.headerSurface
                    Rectangle {
                        x:0;y:43;width:parent.width;height:1
                        color:root.headerDivider
                    }
                }
                Repeater {
                    model:root.days
                    delegate: Item {
                        id:dayColumn
                        z:root.activeDragDay===index ? 50 : 0
                        required property var modelData
                        required property int index
                        x:44+index*root.columnWidth;width:root.columnWidth;height:viewport.contentHeight
                        readonly property bool today:Qt.formatDate(modelData.date,"yyyy-MM-dd")===Qt.formatDate(DateTime.clock.date,"yyyy-MM-dd")
                        Rectangle {anchors.fill:parent;color:dayColumn.today?Qt.alpha(Appearance.colors.colPrimary,.045):"transparent"}
                        Rectangle {
                            id:dayHeader
                            objectName:"plannerDayHeader"
                            x:0;y:viewport.contentY;width:parent.width;height:root.gridTop;z:10
                            color:root.headerSurface
                            HoverHandler {id:dayHeaderHover}
                            Rectangle {
                                width:parent.width;height:44
                                visible:dayColumn.today || dayHeaderHover.hovered
                                color:Qt.alpha(root.headerAccent,dayColumn.today?.12:.07)
                            }
                            Rectangle {
                                y:44;width:parent.width;height:Math.max(0,parent.height-44)
                                visible:dayColumn.today
                                color:Qt.alpha(Appearance.colors.colPrimary,.045)
                            }
                            Rectangle {
                                x:0;y:0;width:1;height:parent.height
                                color:root.headerDivider
                            }
                            Rectangle {
                                x:0;y:43;width:parent.width;height:1
                                color:root.headerDivider
                            }
                            MouseArea {anchors.fill:parent}
                        }
                        StyledText {
                            objectName:"plannerDayTitle"
                            x:6;y:viewport.contentY+3;width:parent.width-12;height:38;z:11
                            text:Qt.formatDate(dayColumn.modelData.date,"ddd d MMM")
                            horizontalAlignment:Text.AlignHCenter
                            font.weight:Font.Bold
                            color:dayColumn.today?root.headerTodayInk:root.headerInk
                            font.pixelSize:Appearance.font.pixelSize.small;elide:Text.ElideRight
                        }
                        Action {
                            x:2;y:viewport.contentY+44;height:24;z:11
                            label:Translation.tr("All day")
                            buttonInk:root.headerInk
                            colBackground:"transparent"
                            colBackgroundHover:Qt.alpha(root.headerAccent,.14)
                            colBackgroundToggled:Qt.alpha(root.headerAccent,.20)
                            toggled:root.expandAllDay
                            onClicked:root.expandAllDay=!root.expandAllDay
                        }
                        Repeater {
                            model: dayColumn.modelData.allDay.slice(0,root.allDayRows)
                            delegate: RippleButton {
                                id:allDayButton
                                required property var modelData
                                required property int index
                                objectName:"plannerAllDayEvent"
                                readonly property color eventAccent:
                                    root.eventIdentityColor(modelData)
                                x:4+(dragMoved?dragX
                                    : root.activeGroupGesture?.mode==="move"
                                        && root.activeGroupGesture?.keys?.includes(
                                            Selection.gestureKey(modelData))
                                        ? root.activeGroupGesture.dx : 0)
                                y:viewport.contentY+68+index*26;width:dayColumn.width-8;height:24;z:11
                                buttonRadius:6
                                colBackground:Qt.alpha(allDayButton.eventAccent,
                                    root.isEventSelected(modelData) || root.isEditorEvent(modelData) ? .44 : .35)
                                Rectangle {
                                    objectName:"plannerAllDaySelection"
                                    anchors.fill:parent;radius:allDayButton.buttonRadius
                                    color:"transparent"
                                    border.width:root.isEventSelected(allDayButton.modelData)
                                        || root.isEditorEvent(allDayButton.modelData) ? 2 : 0
                                    border.color:Appearance.colors.colPrimary
                                    z:1
                                }
                                Accessible.name:modelData.event.title+(modelData.source==="external"?" · Read-only":"")
                                contentItem:StyledText {text:allDayButton.modelData.event.title;color:root.ink;elide:Text.ElideRight;font.pixelSize:Appearance.font.pixelSize.smallest}
                                onClicked:root.editOccurrence(modelData)
                                property bool dragMoved:false
                                property bool dragArmed:false
                                property real dragOriginContentX:0
                                property real dragX:0
                                MouseArea {
                                    id:allDayMouse
                                    anchors.fill:parent;z:12
                                    hoverEnabled:true;preventStealing:true
                                    acceptedButtons:Qt.LeftButton
                                    cursorShape:Selection.canSelect(allDayButton.modelData)
                                        ? Qt.OpenHandCursor : Qt.PointingHandCursor
                                    onPressed:mouse=>{
                                        allDayButton.dragMoved=false;allDayButton.dragX=0
                                        allDayButton.dragArmed=Selection.canSelect(allDayButton.modelData)
                                            && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                                        if (!allDayButton.dragArmed) return
                                        const point=allDayMouse.mapToItem(viewport.contentItem,mouse.x,mouse.y)
                                        allDayButton.dragOriginContentX=point.x
                                    }
                                    onPositionChanged:mouse=>{
                                        if (!pressed || !allDayButton.dragArmed) return
                                        const point=allDayMouse.mapToItem(viewport.contentItem,mouse.x,mouse.y)
                                        const dx=point.x-allDayButton.dragOriginContentX
                                        if (!allDayButton.dragMoved && Math.abs(dx)<6) return
                                        allDayButton.dragMoved=true;allDayButton.dragX=dx
                                        if (!root.isEventSelected(allDayButton.modelData))
                                            root.selectEventId(allDayButton.modelData)
                                        const targets=root.gestureTargets(allDayButton.modelData)
                                        root.activeGroupGesture={keys:targets.map(row=>Selection.gestureKey(row)),
                                            mode:"move",dx:dx,dy:0}
                                        root.activeDragDay=dayColumn.index
                                    }
                                    onReleased:{
                                        const moved=allDayButton.dragMoved
                                        const dx=allDayButton.dragX
                                        allDayButton.dragArmed=false;allDayButton.dragX=0
                                        root.activeGroupGesture=null;root.activeDragDay=-1
                                        if (moved) root.commitTimedGesture(allDayButton.modelData,"move",dx,0)
                                    }
                                    onCanceled:{
                                        allDayButton.dragMoved=false;allDayButton.dragArmed=false
                                        allDayButton.dragX=0;root.activeGroupGesture=null
                                        root.activeDragDay=-1
                                    }
                                    onClicked:mouse=>{
                                        if (!allDayButton.dragMoved)
                                            root.clickPlannerEvent(allDayButton.modelData,mouse.modifiers)
                                    }
                                    onDoubleClicked:{
                                        root.clearEventSelection()
                                        root.editOccurrence(allDayButton.modelData)
                                    }
                                }
                                StyledToolTip {text:parent.Accessible.name}
                            }
                        }
                        StyledText {
                            x:6;y:viewport.contentY+root.gridTop-18;z:11
                            visible:dayColumn.modelData.allDay.length>root.allDayRows || dayColumn.modelData.overflow>0 || !!dayColumn.modelData.projectionLimited
                            text:dayColumn.modelData.projectionLimited ? Translation.tr("More events") : "+"+(Math.max(0,dayColumn.modelData.allDay.length-root.allDayRows)+dayColumn.modelData.overflow)
                            color:root.mutedInk;font.pixelSize:Appearance.font.pixelSize.smallest
                        }
                        Repeater {
                            model:Math.ceil(dayColumn.modelData.minutes/60)+1
                            delegate: Rectangle {
                                required property int index
                                x:0;y:root.gridTop+index*root.hourHeight;width:dayColumn.width;height:1
                                color:Qt.alpha(root.ink,.09)
                                StyledText {
                                    visible:dayColumn.modelData.minutes!==1440
                                    x:3;y:2;text:Qt.formatTime(new Date(dayColumn.modelData.date.getTime()+index*3600000),"hh:mm")
                                    color:root.mutedInk;font.pixelSize:Appearance.font.pixelSize.smallest
                                }
                            }
                        }
                        Rectangle {x:0;y:root.gridTop;width:1;height:dayColumn.modelData.minutes/60*root.hourHeight;color:Qt.alpha(root.ink,.09)}
                        MouseArea {
                            objectName:"plannerCreateSlot"
                            x:0;y:root.gridTop;width:parent.width;height:dayColumn.modelData.minutes/60*root.hourHeight
                            property var regionOrigin: null
                            property bool regionMoved: false
                            preventStealing:regionOrigin!==null
                            onPressed:mouse=>{
                                regionMoved=false
                                regionOrigin=(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                                    ? mapToItem(viewport.contentItem,mouse.x,mouse.y) : null
                            }
                            onPositionChanged:mouse=>{
                                if (!pressed || regionOrigin===null) return
                                const p=mapToItem(viewport.contentItem,mouse.x,mouse.y)
                                if (!regionMoved && Math.hypot(p.x-regionOrigin.x,p.y-regionOrigin.y)<6) return
                                regionMoved=true
                                root.selectionRegion={left:Math.min(regionOrigin.x,p.x),
                                    right:Math.max(regionOrigin.x,p.x),top:Math.min(regionOrigin.y,p.y),
                                    bottom:Math.max(regionOrigin.y,p.y),before:root.selectedEventKeys.slice()}
                            }
                            onReleased:{
                                if (regionMoved) root.finishSelectionRegion()
                                regionOrigin=null
                            }
                            onCanceled:{regionOrigin=null;regionMoved=false;root.selectionRegion=null}
                            onClicked:mouse=>{
                                if (regionMoved || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) return
                                root.clearEventSelection()
                                root.requestEventsDialog({plannerDate:new Date(dayColumn.modelData.date.getTime()+Math.floor(mouse.y/root.hourHeight*4)*15*60000)})
                            }
                        }
                        Repeater {
                            model:dayColumn.modelData.timed
                            delegate:Rectangle {
                                id:timedButton
                                required property var modelData
                                objectName:"plannerTimedEvent"
                                readonly property bool canReschedule: Selection.canReschedule(modelData)
                                readonly property color eventAccent:
                                    root.eventIdentityColor(modelData)
                                // Resize affordances belong to this card alone. Keep
                                // the edge MouseAreas active even while the bars fade out.
                                readonly property bool showResizeHandles: canReschedule
                                    && (eventResizeHover.hovered || gestureMode.length>0)
                                HoverHandler {id:eventResizeHover}
                                property string gestureMode: ""
                                property real dragX: 0
                                property real dragY: 0
                                property real pressX: 0
                                property real pressY: 0
                                property bool gestureMoved: false
                                readonly property var groupPreview:
                                    root.activeGroupGesture?.keys?.includes(Selection.gestureKey(modelData))
                                        ? root.activeGroupGesture : null
                                readonly property string effectiveMode:gestureMode.length>0
                                    ? gestureMode : groupPreview?.mode ?? ""
                                readonly property real effectiveDx:gestureMode.length>0
                                    ? dragX : groupPreview?.dx ?? 0
                                readonly property real effectiveDy:gestureMode.length>0
                                    ? dragY : groupPreview?.dy ?? 0
                                readonly property var previewRange: gestureMode.length>0 && gestureMoved
                                    ? Gesture.rangeForGesture(modelData,gestureMode,dragX,dragY,
                                        root.columnWidth,root.hourHeight)
                                    : groupPreview ? Gesture.rangeForGesture(modelData,
                                        groupPreview.mode,groupPreview.dx,groupPreview.dy,
                                        root.columnWidth,root.hourHeight) : null
                                readonly property real baseHeight: Math.max(18,
                                    (modelData.end-modelData.start)/60*root.hourHeight-2)
                                x:4+modelData.lane*dayColumn.width/modelData.lanes
                                    +(effectiveMode==="move"?effectiveDx:0)
                                y:root.gridTop+modelData.start/60*root.hourHeight
                                    +(effectiveMode==="bottom"?0:effectiveDy)
                                width:Math.max(1,dayColumn.width/modelData.lanes-8)
                                height:Math.max(18,baseHeight
                                    +(effectiveMode==="top"?-effectiveDy
                                        :effectiveMode==="bottom"?effectiveDy:0))
                                radius:7
                                // The two gradient stops share one understated
                                // Event swatch; only alpha changes, never hue.
                                gradient: Gradient {
                                    orientation:Gradient.Horizontal
                                    GradientStop {
                                        position:0
                                        color:Qt.alpha(timedButton.eventAccent,
                                            eventMouse.containsMouse ? .47 : .36)
                                    }
                                    GradientStop {
                                        position:1
                                        color:Qt.alpha(timedButton.eventAccent,
                                            eventMouse.containsMouse ? .34 : .24)
                                    }
                                }
                                border.width:root.isEventSelected(modelData) ? 2
                                    : root.isEditorEvent(modelData) ? 2 : activeFocus ? 1 : 0
                                border.color:Appearance.colors.colPrimary
                                activeFocusOnTab:true
                                Accessible.role:Accessible.Button
                                Accessible.name:modelData.event.title+" · "+
                                    Qt.formatDateTime(modelData.startDate,"ddd hh:mm t")+
                                    (modelData.source==="external"?" · Read-only"
                                     : canReschedule?" · Drag to move, resize edges"
                                     :" · Open to edit")
                                Keys.onReturnPressed:root.editOccurrence(modelData)
                                Keys.onSpacePressed:root.editOccurrence(modelData)
                                Keys.onPressed:event=>{
                                    if (root.handleSelectionKey(event)) event.accepted=true
                                }
                                function startGesture(mode,source,mouse) {
                                    gestureMoved=false
                                    if (!canReschedule
                                            || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) return
                                    const point=source.mapToItem(viewport.contentItem,mouse.x,mouse.y)
                                    gestureMode=mode
                                    gestureMoved=false
                                    dragX=0;dragY=0
                                    pressX=point.x;pressY=point.y
                                    root.activeDragDay=dayColumn.index
                                }
                                function updateGesture(mode,source,mouse) {
                                    if (!canReschedule || gestureMode!==mode) return
                                    const point=source.mapToItem(viewport.contentItem,mouse.x,mouse.y)
                                    const dx=point.x-pressX,dy=point.y-pressY
                                    if (!gestureMoved && Math.hypot(dx,dy)<6) return
                                    gestureMoved=true
                                    dragX=mode==="move" ? dx : 0
                                    dragY=dy
                                    if (!root.isEventSelected(modelData))
                                        root.selectEventId(modelData)
                                    const targets=root.gestureTargets(modelData)
                                    root.activeGroupGesture={keys:targets.map(row=>Selection.gestureKey(row)),
                                        mode:mode,dx:dragX,dy:dragY}
                                }
                                function finishGesture(mode) {
                                    if (gestureMode!==mode) return
                                    const dx=dragX,dy=dragY,shouldCommit=gestureMoved
                                    gestureMode="";dragX=0;dragY=0
                                    root.activeGroupGesture=null
                                    root.activeDragDay=-1
                                    if (shouldCommit) root.commitTimedGesture(modelData,mode,dx,dy)
                                }
                                function cancelGesture() {
                                    gestureMode="";dragX=0;dragY=0;gestureMoved=false
                                    root.activeGroupGesture=null;root.activeDragDay=-1
                                }
                                Column {
                                    anchors.fill:parent;anchors.margins:5;clip:true
                                    StyledText {
                                        width:parent.width
                                        text:timedButton.modelData.event.title
                                        color:root.ink;font.weight:Font.Medium
                                        font.pixelSize:Appearance.font.pixelSize.smallest
                                        elide:Text.ElideRight
                                    }
                                    StyledText {
                                        width:parent.width
                                        text:Qt.formatTime(timedButton.previewRange
                                            ? new Date(timedButton.previewRange.startIso)
                                            : timedButton.modelData.startDate,"hh:mm")
                                            +" – "+Qt.formatTime(timedButton.previewRange
                                            ? new Date(timedButton.previewRange.endIso)
                                            : timedButton.modelData.endDate,"hh:mm")
                                        color:root.mutedInk
                                        font.pixelSize:Appearance.font.pixelSize.smallest
                                        elide:Text.ElideRight
                                    }
                                }
                                // PROTECTED INTERACTION: Local, one-off timed events keep
                                // click-drag move, top-edge resize, and bottom-edge resize.
                                // Preserve these during Dashboard page/gesture refactors;
                                // the pointer regression guard is a maintainer gate.
                                // A saved repeating slot may be moved independently of
                                // its immutable template; virtual and imported rows
                                // remain read-only and may not mutate the original series.
                                // One pointer owner for body movement. In particular, do not
                                // combine RippleButton's internal MouseArea with DragHandler.
                                // Stop Flickable stealing a pressed event; background scrolling
                                // is unaffected when the pointer is outside an event.
                                MouseArea {
                                    id:eventMouse
                                    objectName:"plannerEventMoveArea"
                                    anchors.fill:parent;z:2
                                    acceptedButtons:Qt.LeftButton
                                    preventStealing:true
                                    hoverEnabled:true
                                    cursorShape:timedButton.canReschedule
                                        ? Qt.OpenHandCursor : Qt.PointingHandCursor
                                    onPressed:mouse=>timedButton.startGesture("move",eventMouse,mouse)
                                    onPositionChanged:mouse=>{
                                        if (pressed) timedButton.updateGesture("move",eventMouse,mouse)
                                    }
                                    onReleased:timedButton.finishGesture("move")
                                    onCanceled:timedButton.cancelGesture()
                                    onClicked:mouse=>{
                                        if (!timedButton.gestureMoved)
                                            root.clickPlannerEvent(timedButton.modelData,mouse.modifiers)
                                    }
                                    onDoubleClicked:{
                                        root.clearEventSelection()
                                        root.editOccurrence(timedButton.modelData)
                                    }
                                }
                                Rectangle {
                                    objectName:"plannerResizeStart"
                                    visible:timedButton.canReschedule
                                    x:0;y:0;width:parent.width;height:Math.min(11,parent.height/3);z:3
                                    radius:3;color:"transparent"
                                    Rectangle {
                                        anchors.centerIn:parent
                                        width:Math.min(28,parent.width*.3)
                                        height:2
                                        radius:1
                                        color:Qt.lighter(timedButton.eventAccent,1.20)
                                        // Visible only while hovering this event or
                                        // actively resizing it; never show idle bars.
                                        opacity:timedButton.showResizeHandles
                                            ? (topResizeMouse.containsMouse
                                                || timedButton.gestureMode==="top" ? .9 : .65)
                                            : 0
                                        Behavior on opacity {NumberAnimation {duration:120}}
                                    }
                                    MouseArea {
                                        id:topResizeMouse
                                        anchors.fill:parent
                                        hoverEnabled:true
                                        acceptedButtons:Qt.LeftButton
                                        preventStealing:true
                                        cursorShape:Qt.SizeVerCursor
                                        onPressed:mouse=>timedButton.startGesture("top",topResizeMouse,mouse)
                                        onPositionChanged:mouse=>{
                                            if (pressed)timedButton.updateGesture("top",topResizeMouse,mouse)
                                        }
                                        onReleased:timedButton.finishGesture("top")
                                        onCanceled:timedButton.cancelGesture()
                                        onClicked:mouse=>{
                                            if (!timedButton.gestureMoved)
                                                root.clickPlannerEvent(timedButton.modelData,mouse.modifiers)
                                        }
                                    }
                                }
                                Rectangle {
                                    objectName:"plannerResizeEnd"
                                    visible:timedButton.canReschedule
                                    x:0;y:parent.height-height
                                    width:parent.width;height:Math.min(11,parent.height/3);z:3
                                    radius:3;color:"transparent"
                                    Rectangle {
                                        anchors.centerIn:parent
                                        width:Math.min(28,parent.width*.3)
                                        height:2
                                        radius:1
                                        color:Qt.lighter(timedButton.eventAccent,1.20)
                                        opacity:timedButton.showResizeHandles
                                            ? (bottomResizeMouse.containsMouse
                                                || timedButton.gestureMode==="bottom" ? .9 : .65)
                                            : 0
                                        Behavior on opacity {NumberAnimation {duration:120}}
                                    }
                                    MouseArea {
                                        id:bottomResizeMouse
                                        anchors.fill:parent
                                        hoverEnabled:true
                                        acceptedButtons:Qt.LeftButton
                                        preventStealing:true
                                        cursorShape:Qt.SizeVerCursor
                                        onPressed:mouse=>timedButton.startGesture("bottom",bottomResizeMouse,mouse)
                                        onPositionChanged:mouse=>{
                                            if (pressed)timedButton.updateGesture("bottom",bottomResizeMouse,mouse)
                                        }
                                        onReleased:timedButton.finishGesture("bottom")
                                        onCanceled:timedButton.cancelGesture()
                                        onClicked:mouse=>{
                                            if (!timedButton.gestureMoved)
                                                root.clickPlannerEvent(timedButton.modelData,mouse.modifiers)
                                        }
                                    }
                                }
                                StyledToolTip {
                                    text:parent.Accessible.name+
                                        (parent.modelData.virtual
                                            ?" · Recurring occurrence: open editor" : "")
                                }
                            }
                        }
                        Rectangle {
                            visible:dayColumn.today && root.presentationActive
                            x:0;y:root.gridTop+(DateTime.clock.date-dayColumn.modelData.date)/3600000*root.hourHeight
                            width:parent.width;height:2;color:Appearance.colors.colPrimary
                        }
                    }
                }
            }
            Loader {
                id:sidePanel
                objectName:"plannerSharedSidePanel"
                Layout.fillHeight:root.width>=760
                Layout.fillWidth:root.width<760
                Layout.preferredWidth:root.width<760?root.width:250*Appearance.fontSizeScale
                Layout.minimumWidth:0
                Layout.maximumWidth:root.width
                Layout.preferredHeight:root.width<760?Math.min(230,root.height*.4):-1
                Layout.minimumHeight:0
                Layout.maximumHeight:root.width<760?Math.min(230,root.height*.4):Infinity
                clip:true
                visible:root.sideView==="todo" || root.sideView==="notes"
                active:visible
                sourceComponent:root.sideView==="todo"?todoPanel:notesPanel
            }
            Loader {
                id:inlineEventsPanel
                objectName:"plannerInlineEventsLoader"
                Layout.fillHeight:root.width>=760
                Layout.fillWidth:root.width<760
                Layout.preferredWidth:root.width<760?root.width:310*Appearance.fontSizeScale
                Layout.minimumWidth:0
                Layout.maximumWidth:root.width
                Layout.preferredHeight:root.width<760?Math.min(230,root.height*.4):-1
                Layout.minimumHeight:0
                Layout.maximumHeight:root.width<760?Math.min(230,root.height*.4):Infinity
                clip:true
                visible:root.sideView==="events"
                active:root._inlineEventsLoaded
                sourceComponent:EventsDialog {
                    objectName:"plannerInlineEventsEditor"
                    anchors.fill:parent
                    embeddedPresentation:true
                    plannerPresentation:true
                    hideEmbeddedScrollBar:true
                    embeddedBackgroundColor: {
                        const surface=Config.options?.panelFamily==="abyss"
                            ? AbyssStyle.contentLayer : Appearance.colors.colLayer1
                        const opacity=Math.max(.3,Math.min(1,
                            Config.options?.dashboard?.appearance?.cardOpacity ?? 1))
                        return opacity>=.999 ? surface : ColorUtils.applyAlpha(surface,
                            opacity*surface.a)
                    }
                    show:root.sideView==="events"
                    onDismiss:root.closeInlineEventEditor()
                }
                onLoaded:root.applyPendingInlineEvent()
            }
        }
    }
    Component {id:todoPanel;DashTodo {}}
    Component {id:notesPanel;DashNotes {}}
    Component.onCompleted: {
        const saved=GlobalStates.dashboardPlannerBrowser
        if(saved.date)selectedDate=new Date(saved.date)
        followToday=saved.followToday ?? true
        sideView=["todo","notes"].includes(saved.sideView)?saved.sideView:""
        _initialized=true
        refreshFollowingToday()
        storeBrowser()
        Qt.callLater(root.scrollWorkingHours)
    }
}
