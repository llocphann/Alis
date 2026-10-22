pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.sidebarRight.events
import "DashboardPagePolicy.js" as PagePolicy
import "DashboardCustomTabPolicy.js" as TabPolicy

Item {
    id: root

    property int screenWidth: 1920
    property int screenHeight: 1080
    property bool embeddedSurface: false
    property bool warmContent: false
    property bool presentationActive: GlobalStates.dashboardOpen || GlobalStates.overviewOpen

    readonly property bool musicEnabled: Config.options?.dashboard?.music?.enable ?? true
    readonly property var customTabs: TabPolicy.tabs(Config.options?.dashboard?.customTabs)
    property var _navigationDraftOrder: null
    readonly property var pageIds: PagePolicy.ordered(
        root._navigationDraftOrder ?? dashboardCanvas.effectivePageOrder,
        TabPolicy.available(root.customTabs, root.musicEnabled))
    readonly property string currentPageId: pageIds.includes(GlobalStates.dashboardPageId)
        ? GlobalStates.dashboardPageId : pageIds[0]
    readonly property int currentPage: pageIds.indexOf(currentPageId)
    readonly property var canvasController: {
        if (root.currentPageId === "dashboard") return dashboardCanvas
        const index = root.customTabs.findIndex(tab => tab.id === root.currentPageId)
        return index < 0 ? dashboardCanvas
            : (customPagesRepeater.itemAt(index)?.canvasController ?? null)
    }
    readonly property bool editMode: root.canvasController?.editMode ?? false
    onEditModeChanged: if (!editMode) root._navigationDraftOrder = null
    property var musicBackend: null
    property bool musicVisited: currentPageId === "music"
    property bool plannerVisited: currentPageId === "weeklyPlanner"
    property string _pendingNewEditId: ""
    property bool _sessionWasVisible: false
    property bool _customDialogShown: false
    property string _customDialogMode: ""
    property string _customDialogId: ""
    property string _customDialogName: ""
    property string _customDialogError: ""
    onCurrentPageIdChanged: {
        if (currentPageId === "music") musicVisited = true
        if (currentPageId === "weeklyPlanner") plannerVisited = true
    }

    readonly property bool navigationAllowed: root.presentationActive && pageIds.length > 1
        && !root.editMode && !root._agendaDialogShown && !root._customDialogShown
        && !(musicPage.item?.playlistDialogVisible ?? false)
        && !(plannerPage.item?.sideView === "events")
    property var _pageWheelState: PagePolicy.idle()
    function resetPageWheel(): void {
        pageWheelIdle.stop()
        _pageWheelState = PagePolicy.idle()
    }
    function selectPage(id): void {
        if (!pageIds.includes(id)) return
        GlobalStates.dashboardPageId = id
        const legacy = PagePolicy.defaultOrder.indexOf(id)
        if (legacy >= 0 && GlobalStates.dashboardPage !== legacy)
            GlobalStates.dashboardPage = legacy
    }
    function moveTab(id, target): void {
        const controller = root.canvasController
        if (!controller?.editMode) return
        if (controller.movePage(id, target, root.pageIds))
            root._navigationDraftOrder = Array.from(controller.effectivePageOrder)
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
    function sessionShown(): void {
        if (root._sessionWasVisible) return
        root._sessionWasVisible = true
        const configured = String(Config.options?.dashboard?.defaultTabId ?? "")
        if (configured.length && !root.pageIds.includes(configured))
            Config.setNestedValue("dashboard.defaultTabId", "dashboard")
        const target = TabPolicy.selectAfterInactivity(Date.now(),
            Config.options?.dashboard?.lastHiddenAtMs ?? 0,
            Config.options?.dashboard?.inactiveMinutes ?? 0,
            configured, root.pageIds, root.currentPageId)
        if (target !== root.currentPageId) root.selectPage(target)
    }
    function sessionHidden(): void {
        if (!root._sessionWasVisible) return
        root._sessionWasVisible = false
        Config.setNestedValue("dashboard.lastHiddenAtMs", Date.now())
    }
    onPresentationActiveChanged: {
        if (root.presentationActive) root.sessionShown()
        else root.sessionHidden()
    }
    onPageIdsChanged: {
        if (!root.pageIds.includes(GlobalStates.dashboardPageId))
            GlobalStates.dashboardPageId = root.pageIds[0]
    }
    Component.onCompleted: {
        if (!root.pageIds.includes(GlobalStates.dashboardPageId)) {
            const legacy = PagePolicy.defaultOrder[GlobalStates.dashboardPage]
            root.selectPage(root.pageIds.includes(legacy) ? legacy : root.pageIds[0])
        }
        if (root.presentationActive) root.sessionShown()
    }

    function openCustomTabDialog(mode, id): void {
        if (root.editMode) return
        root._customDialogMode = mode
        root._customDialogId = id ?? ""
        root._customDialogName = root.customTabs.find(tab => tab.id === id)?.name ?? ""
        root._customDialogError = ""
        root._customDialogShown = true
    }
    function acceptCustomTabDialog(): void {
        if (!root._customDialogShown) return
        const mode = root._customDialogMode
        const id = root._customDialogId
        const stored = root.customTabs.slice()
        if (mode === "create" || mode === "rename") {
            const invalid = TabPolicy.errorForName(stored, root._customDialogName,
                mode === "rename" ? id : "")
            if (invalid.length) {
                root._customDialogError = Translation.tr(invalid)
                return
            }
        }
        if (mode === "create") {
            if (stored.length >= 20) {
                root._customDialogError = Translation.tr("Maximum 20 custom tabs")
                return
            }
            const layouts = Config.options?.dashboard?.customTabLayouts ?? ({})
            let createdId = TabPolicy.nextId(stored)
            let suffix = 1
            while (Object.prototype.hasOwnProperty.call(layouts, createdId))
                createdId = "custom-" + (++suffix)
            const next = stored.concat([{id:createdId, name:root._customDialogName.trim()}])
            const order = PagePolicy.normalized(Config.options?.dashboard?.pageOrder)
                .filter(page => page !== createdId).concat([createdId])
            Config.setNestedValues({
                "dashboard.customTabs":next,
                "dashboard.pageOrder":order,
                "dashboard.pageOrderVersion":1
            })
            root._pendingNewEditId = createdId
            GlobalStates.dashboardPageId = createdId
        } else if (mode === "rename") {
            if (!stored.some(tab => tab.id === id)) return
            Config.setNestedValue("dashboard.customTabs", stored.map(tab =>
                tab.id === id ? {id:id,name:root._customDialogName.trim()} : tab))
        } else if (mode === "delete") {
            if (!stored.some(tab => tab.id === id)) return
            const layouts = Object.assign({}, Config.options?.dashboard?.customTabLayouts ?? ({}))
            delete layouts[id]
            const updates = {
                "dashboard.customTabs":stored.filter(tab => tab.id !== id),
                "dashboard.customTabLayouts":layouts,
                "dashboard.pageOrder":PagePolicy.normalized(
                    Config.options?.dashboard?.pageOrder).filter(page => page !== id)
            }
            if (Config.options?.dashboard?.defaultTabId === id)
                updates["dashboard.defaultTabId"] = "dashboard"
            if (GlobalStates.dashboardPageId === id)
                GlobalStates.dashboardPageId = "dashboard"
            Config.setNestedValues(updates)
        }
        root._customDialogShown = false
    }

    readonly property bool showHeader: Config.options?.dashboard?.showHeader ?? true

    property var _agendaEditEvent: null
    property var _agendaPrefillDate: null
    property bool _agendaPrefillTime: false
    property bool _agendaDialogShown: false
    property bool _agendaDialogLoaded: false

    function handleEscape(): bool {
        if (root._customDialogShown) {
            root._customDialogShown = false
            return true
        }
        // Edit Mode owns the first Escape, regardless of widget selection or
        // in-progress tab drag. This is the same discard path as Cancel.
        if (dashboardCanvas.editMode) {
            dashboardHeader.cancelPageDrag()
            dashboardCanvas.cancelEditMode()
            return true
        }
        if (dashboardHeader.cancelPageDrag()) return true
        if (_agendaDialogShown) {
            _agendaDialogShown = false
            return true
        }
        if (currentPageId==="weeklyPlanner" && plannerPage.item?.sideView==="events") {
            plannerPage.item.closeInlineEventEditor()
            return true
        }
        return currentPageId === "music" && (musicPage.item?.restoreBrowserColumns() ?? false)
    }

    function openPlannerEventEditor(arg): void {
        // Only Planner uses the embedded Events column; all other Agenda
        // surfaces retain the existing modal route.
        plannerPage.item?.openInlineEventEditor(arg)
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
                customTabs: root.customTabs
                onCreateTabRequested: root.openCustomTabDialog("create", "")
                onRenameTabRequested: id => root.openCustomTabDialog("rename", id)
                onDeleteTabRequested: id => root.openCustomTabDialog("delete", id)
                onPageMoveRequested: (id,target) => root.moveTab(id,target)
                onHorizontalWheel: event => root.handlePageWheel(event, false)
                onPageRequested: index => {root.resetPageWheel();root.selectPage(root.pageIds[index])}
                editMode: root.editMode
                onEditModeRequested: {
                    if (root.canvasController?.editMode)
                        root.canvasController.commitEditMode();
                    else
                        root.canvasController?.beginEditMode();
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
                        onRequestEventsDialog:event=>root.openPlannerEventEditor(event)
                    }
                }
                // Custom canvases have isolated geometry but share the exact
                // same Dashboard widget component implementations and services.
                Repeater {
                    id: customPagesRepeater
                    model: root.customTabs
                    delegate: Item {
                        id: customTabHost
                        required property var modelData
                        readonly property int slot: root.pageIds.indexOf(modelData.id)
                        property var canvasController: customCanvasLoader.item
                        width: pages.width
                        height: pages.height
                        x: (slot - pages.slideProgress) * pages.width
                        visible: slot >= 0 && Math.abs(pages.slideProgress - slot) < 1
                        enabled: root.currentPageId === modelData.id

                        Loader {
                            id: customCanvasLoader
                            anchors.fill: parent
                            active: (customTabHost.visible && root.presentationActive)
                                || (root.warmContent && root.currentPageId === customTabHost.modelData.id)
                            sourceComponent: DashboardCanvas {
                                customTabId: customTabHost.modelData.id
                                warmContent: root.warmContent
                                presentationActive: root.presentationActive
                                    && root.currentPageId === customTabHost.modelData.id
                                onRequestEventsDialog: event => root.openAgendaDialog(event)
                            }
                            onLoaded: {
                                if (root._pendingNewEditId === customTabHost.modelData.id) {
                                    root._pendingNewEditId = ""
                                    item.beginEditMode()
                                }
                            }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(320, parent.width - 40)
                            spacing: 12
                            visible: customCanvasLoader.item !== null
                                && !customCanvasLoader.item.editMode
                                && (customCanvasLoader.item.visibleIds?.length ?? 0) === 0
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("This tab is empty")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer0
                            }
                            RippleButton {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 120
                                implicitHeight: 34
                                buttonText: Translation.tr("Add widgets")
                                onClicked: customCanvasLoader.item?.beginEditMode()
                                contentItem: StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Add widgets")
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
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

        DashboardCustomTabDialog {
            anchors.fill: parent
            z: 220
            visible: root._customDialogShown
            mode: root._customDialogMode
            tabName: root._customDialogName
            errorText: root._customDialogError
            onTabNameChanged: if (visible) root._customDialogName = tabName
            onAcceptRequested: name => {
                root._customDialogName = name
                root.acceptCustomTabDialog()
            }
            onDismissRequested: root._customDialogShown = false
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
