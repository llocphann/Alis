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
    onTodayKeyChanged: if (_initialized && followToday) selectedDate=DateTime.clock.date
    onSelectedDateChanged: storeBrowser()
    onFollowTodayChanged: storeBrowser()
    onSideViewChanged: storeBrowser()
    onPresentationActiveChanged: if (_initialized && presentationActive && followToday) selectedDate=DateTime.clock.date
    property bool expandAllDay: false
    property int activeDragDay: -1
    property real hourHeight: 52 * Appearance.fontSizeScale
    property int _eventsRevision: 0
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property var days: {
        const revision = root._eventsRevision
        return Planner.project(root.localBackend.list, root.externalBackend.events,
            root.selectedDate, root.firstDay)
    }
    readonly property int maximumMinutes: Math.max.apply(null, days.map(day => day.minutes))
    readonly property int allDayRows: Math.min(expandAllDay ? 512 : 4, Math.max.apply(null, days.map(day => day.allDay.length)))
    readonly property real allDayHeight: 24 + Math.max(1, allDayRows) * 26
    readonly property real gridTop: 44 + allDayHeight
    readonly property real columnWidth: Math.max(102 * Appearance.fontSizeScale, (viewport.width - 44) / 7)
    readonly property color ink: Appearance.colors.colOnLayer1
    readonly property color mutedInk: Appearance.colors.colSubtext
    // Match the date and All-day headings to the actual timeline: its day
    // cells have no opaque backing, so the pinned headings must not paint a
    // contrasting solid Weather/Material card over the transparent grid.
    // The Today tint on the day column stays visible through this surface.
    readonly property bool abyssPanel: Config.options?.panelFamily === "abyss"
    readonly property color headerSurface: "transparent"
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
        if (sideView==="events") sideView=""
        _inlineEventsLoaded=false
    }
    function changeWeek(count): void {followToday=false;selectedDate=Planner.addDays(selectedDate,count*7)}
    function showToday(): void {followToday=true;selectedDate=new Date();scrollWorkingHours()}
    function commitTimedGesture(row, mode, dx, dy): void {
        if (typeof root.localBackend.rescheduleOccurrence !== "function") return
        const candidate=Gesture.rangeForGesture(row,mode,dx,dy,
            root.columnWidth,root.hourHeight)
        if (!candidate) return
        if (!root.localBackend.rescheduleOccurrence(row.event.id,
                row.occurrenceIndex,candidate.startIso,candidate.endIso)) {
            console.warn("[WeeklyPlanner] Timed event gesture not saved")
            return
        }
        // The calendar dots already react to Events.eventUpdated, but the
        // open Edit Event form owns its own selected-day highlight. Reconcile
        // that focus only after the canonical occurrence was actually saved.
        // Do not reload the form: doing so would erase an unsaved title/note.
        const form=inlineEventsPanel.item
        if (form && form.isEditing
                && form.editingEvent?.id===row.event.id
                && form.editingOccurrenceIndex===row.occurrenceIndex)
            form.syncMovedOccurrence(row.event.id,row.startDate,
                candidate.startIso,candidate.endIso)
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
                ScrollBar.vertical: ScrollBar {policy:ScrollBar.AsNeeded}
                ScrollBar.horizontal: ScrollBar {policy:ScrollBar.AsNeeded}
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
                                x:4;y:viewport.contentY+68+index*26;width:dayColumn.width-8;height:24;z:11
                                buttonRadius:6
                                colBackground:Qt.alpha(modelData.event.color || Appearance.colors.colPrimary,.18)
                                Accessible.name:modelData.event.title+(modelData.source==="external"?" · Read-only":"")
                                contentItem:StyledText {text:allDayButton.modelData.event.title;color:root.ink;elide:Text.ElideRight;font.pixelSize:Appearance.font.pixelSize.smallest}
                                onClicked:root.editOccurrence(modelData)
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
                            onClicked:mouse=>root.requestEventsDialog({plannerDate:new Date(dayColumn.modelData.date.getTime()+Math.floor(mouse.y/root.hourHeight*4)*15*60000)})
                        }
                        Repeater {
                            model:dayColumn.modelData.timed
                            delegate:Rectangle {
                                id:timedButton
                                required property var modelData
                                objectName:"plannerTimedEvent"
                                readonly property bool canReschedule: modelData.source==="local"
                                    && !modelData.virtual && !modelData.event.allDay
                                    && (modelData.event.recurrence || "none")==="none"
                                property string gestureMode: ""
                                property real dragX: 0
                                property real dragY: 0
                                property real pressX: 0
                                property real pressY: 0
                                property bool gestureMoved: false
                                readonly property var previewRange: gestureMode.length>0 && gestureMoved
                                    ? Gesture.rangeForGesture(modelData,gestureMode,dragX,dragY,
                                        root.columnWidth,root.hourHeight) : null
                                readonly property real baseHeight: Math.max(18,
                                    (modelData.end-modelData.start)/60*root.hourHeight-2)
                                x:4+modelData.lane*dayColumn.width/modelData.lanes
                                    +(gestureMode==="move"?dragX:0)
                                y:root.gridTop+modelData.start/60*root.hourHeight
                                    +(gestureMode==="bottom"?0:dragY)
                                width:Math.max(1,dayColumn.width/modelData.lanes-8)
                                height:Math.max(18,baseHeight
                                    +(gestureMode==="top"?-dragY:gestureMode==="bottom"?dragY:0))
                                radius:7
                                color:Qt.alpha(modelData.event.color || Appearance.colors.colPrimary,
                                    eventMouse.containsMouse ? .32 : .2)
                                border.width:activeFocus ? 1 : 0
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
                                function startGesture(mode,source,mouse) {
                                    if (!canReschedule) return
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
                                }
                                function finishGesture(mode) {
                                    if (gestureMode!==mode) return
                                    const dx=dragX,dy=dragY,shouldCommit=gestureMoved
                                    gestureMode="";dragX=0;dragY=0
                                    root.activeDragDay=-1
                                    if (shouldCommit) root.commitTimedGesture(modelData,mode,dx,dy)
                                }
                                function cancelGesture() {
                                    gestureMode="";dragX=0;dragY=0;gestureMoved=false
                                    root.activeDragDay=-1
                                }
                                Column {
                                    anchors.fill:parent;anchors.margins:4;clip:true
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
                                    onClicked:if (!timedButton.gestureMoved)
                                        root.editOccurrence(timedButton.modelData)
                                }
                                Rectangle {
                                    objectName:"plannerResizeStart"
                                    visible:timedButton.canReschedule
                                    x:0;y:0;width:parent.width;height:Math.min(9,parent.height/3);z:3
                                    radius:3;color:"transparent"
                                    Rectangle {
                                        anchors.centerIn:parent
                                        width:Math.min(28,parent.width*.3)
                                        height:2
                                        radius:1
                                        color:root.headerAccent
                                        opacity:topResizeMouse.containsMouse
                                            || timedButton.gestureMode==="top" ? .82 : 0
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
                                    }
                                }
                                Rectangle {
                                    objectName:"plannerResizeEnd"
                                    visible:timedButton.canReschedule
                                    x:0;y:parent.height-height
                                    width:parent.width;height:Math.min(9,parent.height/3);z:3
                                    radius:3;color:"transparent"
                                    Rectangle {
                                        anchors.centerIn:parent
                                        width:Math.min(28,parent.width*.3)
                                        height:2
                                        radius:1
                                        color:root.headerAccent
                                        opacity:bottomResizeMouse.containsMouse
                                            || timedButton.gestureMode==="bottom" ? .82 : 0
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
        if(followToday)selectedDate=DateTime.clock.date
        storeBrowser()
        Qt.callLater(root.scrollWorkingHours)
    }
}
