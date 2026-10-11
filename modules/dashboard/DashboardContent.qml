pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.sidebarRight.events
import "DashboardPagePolicy.js" as PagePolicy

Item {
    id: root

    property int screenWidth: 1920
    property int screenHeight: 1080
    property bool embeddedSurface: false
    property bool warmContent: false
    property bool presentationActive: GlobalStates.dashboardOpen || GlobalStates.overviewOpen

    property alias editMode: dashboardCanvas.editMode
    readonly property bool musicEnabled: Config.options?.dashboard?.music?.enable ?? true
    readonly property var pageIds: PagePolicy.ordered(dashboardCanvas.effectivePageOrder,
        musicEnabled ? ["dashboard", "music", "weeklyPlanner"] : ["dashboard", "weeklyPlanner"])
    readonly property string currentPageId: pageIds.includes(GlobalStates.dashboardPageId)
        ? GlobalStates.dashboardPageId : pageIds[0]
    readonly property int currentPage: pageIds.indexOf(currentPageId)
    property var musicBackend: null
    property bool musicVisited: currentPageId === "music"
    property bool plannerVisited: currentPageId === "weeklyPlanner"
    onCurrentPageIdChanged: {
        if (currentPageId === "music") musicVisited = true
        if (currentPageId === "weeklyPlanner") plannerVisited = true
    }
    onEditModeChanged: if (editMode)
        selectPage("dashboard")
    readonly property var canvasController: dashboardCanvas

    readonly property bool navigationAllowed: root.presentationActive && pageIds.length > 1
        && !root.editMode && !root._agendaDialogShown && !(musicPage.item?.playlistDialogVisible ?? false)
    property var _pageWheelState: PagePolicy.idle()
    function resetPageWheel(): void {
        pageWheelIdle.stop()
        _pageWheelState = PagePolicy.idle()
    }
    function selectPage(id): void {
        if (!pageIds.includes(id)) return
        GlobalStates.dashboardPageId = id
        GlobalStates.dashboardPage = PagePolicy.defaultOrder.indexOf(id)
    }
    function handlePageWheel(event, panContent): void {
        event.accepted = false
        if (!navigationAllowed) return
        const movement = PagePolicy.delta(event)
        const phase = Number(event.phase ?? 0)
        const contentConsumed = movement.x && Math.abs(movement.x) > Math.abs(movement.y)
            && panContent && (currentPageId === "music" ? musicPage.item?.panHorizontally(movement.x)
                : currentPageId === "weeklyPlanner" ? plannerPage.item?.panHorizontally(movement.x) : false)
        const result = PagePolicy.advance(_pageWheelState, movement, phase, Date.now(), pageIds, currentPageId, contentConsumed)
        _pageWheelState = result.state
        event.accepted = result.accepted
        if (!_pageWheelState.phased && _pageWheelState.direction) pageWheelIdle.restart()
        else pageWheelIdle.stop()
        if (result.target) selectPage(result.target)
    }
    onNavigationAllowedChanged: if (!navigationAllowed) resetPageWheel()
    Timer {id:pageWheelIdle;interval:180;repeat:false;onTriggered:root._pageWheelState=PagePolicy.idle()}
    Connections {
        target: GlobalStates
        function onDashboardPageChanged(): void {
            const id = PagePolicy.defaultOrder[GlobalStates.dashboardPage] ?? "dashboard"
            GlobalStates.dashboardPageId = root.pageIds.includes(id) ? id : root.pageIds[0]
        }
    }
    Component.onCompleted: {
        const legacy = PagePolicy.defaultOrder[GlobalStates.dashboardPage]
        if (legacy && pageIds.includes(legacy)) GlobalStates.dashboardPageId = legacy
    }

    readonly property bool showHeader: Config.options?.dashboard?.showHeader ?? true

    property var _agendaEditEvent: null
    property var _agendaPrefillDate: null
    property bool _agendaPrefillTime: false
    property bool _agendaDialogShown: false
    property bool _agendaDialogLoaded: false

    function handleEscape(): bool {
        if (dashboardHeader.cancelPageDrag()) return true
        if (_agendaDialogShown) {
            _agendaDialogShown = false
            return true
        }
        if (dashboardCanvas.editMode) {
            dashboardCanvas.cancelEditMode()
            return true
        }
        return currentPageId === "music" && (musicPage.item?.restoreBrowserColumns() ?? false)
    }

    function openAgendaDialog(arg) {
        const plannerDate = arg?.plannerDate;
        const isDate = arg instanceof Date || plannerDate instanceof Date;
        root._agendaEditEvent = (arg && !isDate) ? arg : null;
        root._agendaPrefillDate = isDate ? (plannerDate ?? arg) : null;
        root._agendaPrefillTime = plannerDate instanceof Date;
        root._agendaDialogLoaded = true;
        if (agendaDialogLoader.item) {
            if (root._agendaEditEvent) {
                agendaDialogLoader.item.loadEvent(root._agendaEditEvent);
            } else {
                agendaDialogLoader.item.resetForm();
                if (root._agendaPrefillDate)
                    agendaDialogLoader.item.eventDate = root._agendaPrefillDate;
                root.prefillAgendaTime();
            }
        }
        root._agendaDialogShown = true;
    }
    function prefillAgendaTime(): void {
        if (!root._agendaPrefillTime || !root._agendaPrefillDate || !agendaDialogLoader.item) return;
        agendaDialogLoader.item.eventTime = Qt.formatTime(root._agendaPrefillDate,"hh:mm");
        agendaDialogLoader.item.eventEndTime = Qt.formatTime(new Date(root._agendaPrefillDate.getTime()+3600000),"hh:mm");
    }

    // Dashboard does not own a separate background renderer. Detached Dashboard
    // uses the same canonical Material layer-0 surface and shadow vocabulary as
    // existing ii popups/sidebars; the launcher-embedded form stays transparent
    // because OverviewDashboard already owns that same layer-0 surface.
    StyledRectangularShadow {
        target: background
        radius: background.radius
        // Detached Dashboard retains its own shadow owner, but shares the
        // physical Screen Edge elevation controls with connected surfaces.
        blur: Math.max(0, Math.min(32, Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
        spread: 0
        offset: Qt.vector2d(0, 0)
        color: Qt.alpha(Appearance.m3colors.m3shadow, Math.max(0, Math.min(1.0, Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70))))
        visible: !root.embeddedSurface && (Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true) && !Appearance.gameModeMinimal
    }

    Rectangle {
        id: background
        anchors.fill: parent
        clip: true
        color: root.embeddedSurface ? "transparent" : Appearance.colors.colLayer0
        radius: root.embeddedSurface ? 0 : Appearance.rounding.large
        border.width: 0
        border.color: "transparent"

        ColumnLayout {
            id: mainColumn
            readonly property bool compact: (Config.options?.dashboard?.appearance?.density ?? "comfortable") === "compact"
            anchors.fill: parent
            anchors.margins: root.embeddedSurface ? 0 : (compact ? 12 : 16)
            spacing: compact ? 8 : 12

            DashboardHeader {
                id: dashboardHeader
                Layout.fillWidth: true
                visible: root.showHeader || root.pageIds.length > 1
                showActions: root.showHeader
                currentPage: root.currentPage
                pageCount: root.pageIds.length
                pageIds: root.pageIds
                navigationAllowed: root.navigationAllowed
                reorderAllowed: root.editMode && !root._agendaDialogShown
                onPageMoveRequested: (id,target) => dashboardCanvas.movePage(id,target,root.pageIds)
                onHorizontalWheel: event => root.handlePageWheel(event, false)
                onPageRequested: index => {root.resetPageWheel();root.selectPage(root.pageIds[index])}
                editMode: dashboardCanvas.editMode
                onEditModeRequested: {
                    if (dashboardCanvas.editMode)
                        dashboardCanvas.commitEditMode();
                    else
                        dashboardCanvas.beginEditMode();
                }
            }

            Item {
                id: pages
                objectName: "dashboardPages"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                // Editing must see the original workspace immediately, including
                // entry during an already running page transition.
                readonly property real slideProgress: root.editMode ? root.pageIds.indexOf("dashboard") : pagePosition
                property real pagePosition: root.currentPage
                Behavior on pagePosition {
                    enabled: root.presentationActive && Appearance.animationsEnabled && !root.editMode
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.OutCubic
                    }
                }
                DashboardCanvas {
                    id: dashboardCanvas
                    width: pages.width
                    height: pages.height
                    x: (root.pageIds.indexOf("dashboard") - pages.slideProgress) * pages.width
                    visible: Math.abs(pages.slideProgress - root.pageIds.indexOf("dashboard")) < 1
                    enabled: root.currentPageId === "dashboard"
                    presentationActive: root.presentationActive && root.currentPageId === "dashboard"
                    warmContent: root.warmContent
                    onRequestEventsDialog: event => root.openAgendaDialog(event)
                }
                Loader {
                    id: musicPage
                    width: pages.width
                    height: pages.height
                    x: (root.pageIds.indexOf("music") - pages.slideProgress) * pages.width
                    visible: root.musicEnabled && Math.abs(pages.slideProgress - root.pageIds.indexOf("music")) < 1
                    enabled: root.currentPageId === "music"
                    active: root.musicEnabled && root.musicVisited && (root.presentationActive || root.warmContent)
                    sourceComponent: DashboardMusic {
                        backend: root.musicBackend ?? LocalMusic
                        presentationActive: root.presentationActive && root.currentPageId === "music"
                    }
                }
                // Handle page gestures above the canvas and its scrollable widgets.
                Loader {
                    id:plannerPage
                    width:pages.width;height:pages.height
                    x:(root.pageIds.indexOf("weeklyPlanner")-pages.slideProgress)*pages.width
                    visible:Math.abs(pages.slideProgress-root.pageIds.indexOf("weeklyPlanner"))<1
                    enabled:root.currentPageId==="weeklyPlanner"
                    active:root.plannerVisited && (root.presentationActive || root.warmContent)
                    sourceComponent:DashboardWeeklyPlanner {
                        presentationActive:root.presentationActive && root.currentPageId==="weeklyPlanner"
                        onRequestEventsDialog:event=>root.openAgendaDialog(event)
                    }
                }
                // Pointer handlers leave clicks and vertical scrolling to those widgets.
                Item {
                    anchors.fill: parent
                    z: 100
                    WheelHandler {
                        target: null
                        orientation: Qt.Horizontal
                        blocking: false
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        enabled: root.navigationAllowed
                        onWheel: event => root.handlePageWheel(event, true)
                    }
                }
            }
        }

        Loader {
            id: agendaDialogLoader
            anchors.fill: parent
            z: 200
            active: root._agendaDialogLoaded
            sourceComponent: EventsDialog {objectName:"dashboardAgendaDialog"}
            onLoaded: {
                item.show = Qt.binding(() => root._agendaDialogShown);
                if (root._agendaEditEvent) {
                    item.loadEvent(root._agendaEditEvent);
                } else {
                    item.resetForm();
                    if (root._agendaPrefillDate)
                        item.eventDate = root._agendaPrefillDate;
                    root.prefillAgendaTime();
                }
                item.forceActiveFocus();
            }
            Connections {
                target: agendaDialogLoader.item
                function onDismiss() {
                    root._agendaDialogShown = false;
                }
            }
        }
    }
}
