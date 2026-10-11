pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WeeklyPlannerPolicy.js" as Planner

Item {
    id: root
    objectName: "dashboardWeeklyPlanner"
    property bool presentationActive: false
    property var localBackend: Events
    property var externalBackend: CalendarSync
    property date selectedDate: new Date()
    property bool followToday: true
    property string sideView: ""
    property bool _initialized: false
    readonly property string todayKey: Qt.formatDate(DateTime.clock.date,"yyyy-MM-dd")
    onTodayKeyChanged: if (_initialized && followToday) selectedDate=DateTime.clock.date
    onSelectedDateChanged: storeBrowser()
    onFollowTodayChanged: storeBrowser()
    onSideViewChanged: storeBrowser()
    onPresentationActiveChanged: if (_initialized && presentationActive && followToday) selectedDate=DateTime.clock.date
    property bool expandAllDay: false
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
        if (_initialized) GlobalStates.dashboardPlannerBrowser={date:selectedDate.toISOString(),followToday:followToday,sideView:sideView}
    }
    function changeWeek(count): void {followToday=false;selectedDate=Planner.addDays(selectedDate,count*7)}
    function showToday(): void {followToday=true;selectedDate=new Date();scrollWorkingHours()}
    function scrollWorkingHours(): void {
        viewport.contentY=Math.min(Math.max(0,viewport.contentHeight-viewport.height),hourHeight*8)
    }
    function panHorizontally(delta): bool {
        const before=viewport.contentX
        viewport.contentX=Math.max(0,Math.min(viewport.contentWidth-viewport.width,before-delta))
        return viewport.contentX!==before
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) {changeWeek(-1);event.accepted=true}
        else if (event.key === Qt.Key_PageDown) {changeWeek(1);event.accepted=true}
        else if (event.key === Qt.Key_Home) {showToday();event.accepted=true}
        else event.accepted=false
    }
    component Action: RippleButton {
        id:action
        property string label: ""
        property string symbol: ""
        implicitHeight: 34
        implicitWidth: label.length ? row.implicitWidth + 18 : 34
        buttonRadius: 12
        Accessible.name: label.length ? label : symbol
        colBackground: toggled ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        contentItem: RowLayout {
            id: row;anchors.centerIn: parent;spacing: 5
            MaterialSymbol {visible:action.symbol.length>0;text:action.symbol;iconSize:18;color:root.ink}
            StyledText {visible:action.label.length>0;text:action.label;color:root.ink;font.pixelSize:Appearance.font.pixelSize.small}
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Action {symbol:"chevron_left";Accessible.name:Translation.tr("Previous week");onClicked:root.changeWeek(-1)}
            Action {label:Translation.tr("Today");onClicked:root.showToday()}
            Action {symbol:"chevron_right";Accessible.name:Translation.tr("Next week");onClicked:root.changeWeek(1)}
            StyledText {
                Layout.fillWidth: true
                text: Qt.formatDate(root.days[0].date,"d MMM") + " – " + Qt.formatDate(root.days[6].date,"d MMM yyyy")
                color:root.ink;elide:Text.ElideRight;font.weight:Font.DemiBold
            }
            Action {symbol:"checklist";Accessible.name:Translation.tr("To Do");toggled:root.sideView==="todo";onClicked:root.sideView=root.sideView==="todo"?"":"todo"}
            Action {symbol:"sticky_note_2";Accessible.name:Translation.tr("Quick Notes");toggled:root.sideView==="notes";onClicked:root.sideView=root.sideView==="notes"?"":"notes"}
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
                Rectangle {x:0;y:viewport.contentY;width:44;height:root.gridTop;z:20;color:Appearance.colors.colLayer1}
                Repeater {
                    model:root.days
                    delegate: Item {
                        id:dayColumn
                        required property var modelData
                        required property int index
                        x:44+index*root.columnWidth;width:root.columnWidth;height:viewport.contentHeight
                        readonly property bool today:Qt.formatDate(modelData.date,"yyyy-MM-dd")===Qt.formatDate(DateTime.clock.date,"yyyy-MM-dd")
                        Rectangle {anchors.fill:parent;color:dayColumn.today?Qt.alpha(Appearance.colors.colPrimary,.045):"transparent"}
                        Rectangle {
                            x:0;y:viewport.contentY;width:parent.width;height:root.gridTop;z:10
                            color:Appearance.colors.colLayer1
                            MouseArea {anchors.fill:parent}
                        }
                        StyledText {
                            x:6;y:viewport.contentY+3;width:parent.width-12;height:38;z:11
                            text:Qt.formatDate(dayColumn.modelData.date,"ddd d MMM")
                            font.weight:Font.DemiBold;color:dayColumn.today?Appearance.colors.colPrimary:root.ink
                            font.pixelSize:Appearance.font.pixelSize.small;elide:Text.ElideRight
                        }
                        Action {
                            x:2;y:viewport.contentY+40;height:24;z:11
                            label:Translation.tr("All day")
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
                                x:4;y:viewport.contentY+66+index*26;width:dayColumn.width-8;height:24;z:11
                                buttonRadius:6
                                colBackground:Qt.alpha(modelData.event.color || Appearance.colors.colPrimary,.18)
                                Accessible.name:modelData.event.title+(modelData.source==="external"?" · Read-only":"")
                                contentItem:StyledText {text:allDayButton.modelData.event.title;color:root.ink;elide:Text.ElideRight;font.pixelSize:Appearance.font.pixelSize.smallest}
                                onClicked:if(modelData.source==="local")root.requestEventsDialog(modelData.event)
                                StyledToolTip {text:parent.Accessible.name+(parent.modelData.source==="local" && !parent.modelData.virtual && Todo.agendaStatus(parent.modelData.event)?" · "+Todo.agendaStatus(parent.modelData.event):"")}
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
                            delegate:RippleButton {
                                id:timedButton
                                required property var modelData
                                objectName:"plannerTimedEvent"
                                x:4+modelData.lane*dayColumn.width/modelData.lanes
                                y:root.gridTop+modelData.start/60*root.hourHeight
                                width:Math.max(1,dayColumn.width/modelData.lanes-8)
                                height:Math.max(18,(modelData.end-modelData.start)/60*root.hourHeight-2)
                                buttonRadius:7
                                colBackground:Qt.alpha(modelData.event.color || Appearance.colors.colPrimary,.2)
                                colBackgroundHover:Qt.alpha(modelData.event.color || Appearance.colors.colPrimary,.32)
                                Accessible.name:modelData.event.title+" · "+Qt.formatDateTime(modelData.startDate,"ddd hh:mm t")+(modelData.source==="external"?" · Read-only":"")
                                contentItem:Column {
                                    clip:true
                                    StyledText {width:parent.width;text:timedButton.modelData.event.title;color:root.ink;font.weight:Font.Medium;font.pixelSize:Appearance.font.pixelSize.smallest;elide:Text.ElideRight}
                                    StyledText {width:parent.width;visible:text.length>0;text:timedButton.modelData.source==="local" && !timedButton.modelData.virtual ? Translation.tr(Todo.agendaStatus(timedButton.modelData.event)) : "";color:root.mutedInk;font.pixelSize:Appearance.font.pixelSize.smallest;elide:Text.ElideRight}
                                    StyledText {width:parent.width;text:Qt.formatTime(timedButton.modelData.startDate,"hh:mm")+" – "+Qt.formatTime(timedButton.modelData.endDate,"hh:mm");color:root.mutedInk;font.pixelSize:Appearance.font.pixelSize.smallest;elide:Text.ElideRight}
                                }
                                onClicked:if(modelData.source==="local")root.requestEventsDialog(modelData.event)
                                StyledToolTip {text:parent.Accessible.name+(parent.modelData.virtual?" · Recurring: edits apply to the saved event":parent.modelData.source==="local" && Todo.agendaStatus(parent.modelData.event)?" · "+Todo.agendaStatus(parent.modelData.event):"")}
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
                visible:root.sideView.length>0
                active:visible
                sourceComponent:root.sideView==="todo"?todoPanel:notesPanel
            }
        }
    }
    Component {id:todoPanel;DashTodo {}}
    Component {id:notesPanel;DashNotes {}}
    Component.onCompleted: {
        const saved=GlobalStates.dashboardPlannerBrowser
        if(saved.date)selectedDate=new Date(saved.date)
        followToday=saved.followToday ?? true
        sideView=saved.sideView ?? ""
        _initialized=true
        if(followToday)selectedDate=DateTime.clock.date
        storeBrowser()
        Qt.callLater(root.scrollWorkingHours)
    }
}
