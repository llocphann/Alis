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
    readonly property var _customPageModelMemo: ({signature:"",tabs:[]})
    readonly property var customPageModel: {
        // Config can republish equal tab definitions while saving a layout.
        // Only identity/order belongs to the Repeater; current names remain
        // in customTabs for the header and dialogs. Retain live canvas drafts.
        const signature = JSON.stringify(root.customTabs.map(tab => tab.id))
        const memo = root._customPageModelMemo
        if (memo.signature !== signature) {
            memo.signature = signature
            memo.tabs = root.customTabs
        }
        return memo.tabs
    }
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
    property bool editMode: root.canvasController?.editMode ?? false
    onEditModeChanged: {
        if (!editMode) {
            root._navigationDraftOrder = null
        } else if (root.currentPageId !== "dashboard"
                && !root.customTabs.some(tab => tab.id === root.currentPageId)) {
            // Music/Planner use the main canvas for Edit. Show that canvas;
            // a custom tab keeps its own selected, editable canvas instead.
            root.selectPage("dashboard")
        }
    }
    Connections {
        target: root.canvasController
        function onEffectivePageOrderChanged(): void {
            // Reorder creates the navigation snapshot to avoid a controller /
            // selected-page binding cycle. Undo and Reset must update it too.
            if (root.editMode && root._navigationDraftOrder !== null)
                root._navigationDraftOrder = Array.from(root.canvasController.effectivePageOrder)
        }
    }
    property var musicBackend: null
    property bool musicVisited: currentPageId === "music"
    property bool plannerVisited: currentPageId === "weeklyPlanner"
    property string _pendingPageId: ""
    property string _synchronousPageId: ""
    property bool _userPageNavigation: false
    readonly property bool pendingPageReady: {
        if (_pendingPageId === "dashboard") return true
        if (_pendingPageId === "music") return musicPage.status === Loader.Ready
        if (_pendingPageId === "weeklyPlanner") return plannerPage.status === Loader.Ready
        const index = root.customTabs.findIndex(tab => tab.id === root._pendingPageId)
        return index >= 0 && (customPagesRepeater.itemAt(index)?.pageReady ?? false)
    }
    // Incubate only the requested page while the current page stays usable.
    // Commit after readiness on another event turn, before the unchanged slide.
    Timer {
        interval: 0
        running: root._pendingPageId.length > 0 && root.pendingPageReady
        onTriggered: root.commitPendingPage()
    }
    property string _pendingNewEditId: ""
    // Loader completion can run inside slideProgress evaluation. Enter edit
    // on the next event turn, after that binding has finished, without holding
    // a callback to a delegate that may already have been removed.
    Timer {
        interval: 0
        running: root._pendingNewEditId.length > 0 && root.presentationActive
            && root.currentPageId === root._pendingNewEditId
            && root.canvasController !== null
        onTriggered: {
            const editor = root.canvasController
            root._pendingNewEditId = ""
            editor.beginEditMode()
        }
    }
    property bool _sessionWasVisible: false
    property bool _customDialogShown: false
    property string _customDialogMode: ""
    property string _customDialogId: ""
    property string _customDialogName: ""
    property string _customDialogError: ""
    readonly property bool tabNamingActive: root._customDialogShown && root._customDialogMode !== "delete"
    function setCustomTabName(name): void {
        root._customDialogName = String(name ?? "")
        root._customDialogError = ""
    }
    function cancelCustomTabDialog(): void {
        root._customDialogShown = false
    }
    onCurrentPageIdChanged: {
        if (_pendingPageId.length && _pendingPageId !== currentPageId)
            _pendingPageId = ""
        if (_pendingNewEditId.length && currentPageId !== _pendingNewEditId)
            _pendingNewEditId = ""
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
        // Restoration, inactivity and edit flows keep their synchronous API.
        // Switching this flag only affects the explicitly selected Loader.
        root._synchronousPageId = id
        GlobalStates.dashboardPageId = id
        const legacy = PagePolicy.defaultOrder.indexOf(id)
        if (legacy >= 0 && GlobalStates.dashboardPage !== legacy)
            GlobalStates.dashboardPage = legacy
        root._pendingPageId = ""
    }
    function requestPage(id): void {
        if (!root.navigationAllowed || !root.pageIds.includes(id)) return
        if (id === root.currentPageId) { root._pendingPageId = ""; return }
        root._synchronousPageId = ""
        root._userPageNavigation = true
        root._pendingPageId = id
    }
    function commitPendingPage(): void {
        const id = root._pendingPageId
        if (!id || !root.pendingPageReady) return
        if (!root.navigationAllowed || !root.pageIds.includes(id)) {
            root._pendingPageId = ""
            return
        }
        root.selectPage(id)
    }
    function pageLoadFailed(id): void {
        if (root._pendingPageId !== id) return
        root._pendingPageId = ""
        console.warn("[Dashboard] Requested tab could not be loaded")
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
        const result = PagePolicy.advance(_pageWheelState, movement, phase, Date.now(), pageIds,
            root._pendingPageId || currentPageId, contentConsumed)
        _pageWheelState = result.state
        event.accepted = result.accepted
        if (!_pageWheelState.phased && _pageWheelState.direction) pageWheelIdle.restart()
        else pageWheelIdle.stop()
        if (result.target) requestPage(result.target)
    }
    onNavigationAllowedChanged: if (!navigationAllowed) {
        resetPageWheel()
        root._pendingPageId = ""
    }
    Timer {id:pageWheelIdle;interval:180;repeat:false;onTriggered:root._pageWheelState=PagePolicy.idle()}
    Connections {
        target: GlobalStates
        function onDashboardPageChanged(): void {
            const id = PagePolicy.defaultOrder[GlobalStates.dashboardPage] ?? "dashboard"
            root.selectPage(root.pageIds.includes(id) ? id : root.pageIds[0])
        }
        function onDashboardPageIdChanged(): void {
            if (!Config.ready || !GlobalStates.dashboardSelectionRestored) return
            const id = GlobalStates.dashboardPageId
            if (root.pageIds.includes(id)
                    && Config.options?.dashboard?.lastPageId !== id)
                Config.setNestedValue("dashboard.lastPageId",id)
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return
            root.restoreLastPage()
            if (root.presentationActive) root.sessionShown()
        }
    }
    function restoreLastPage(): void {
        if (!Config.ready || GlobalStates.dashboardSelectionRestored) return
        GlobalStates.dashboardSelectionRestored = true
        const saved = String(Config.options?.dashboard?.lastPageId ?? "dashboard")
        if (root.pageIds.includes(saved))
            GlobalStates.dashboardPageId = saved
    }
    function sessionShown(): void {
        if (!Config.ready || root._sessionWasVisible) return
        root.restoreLastPage()
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
        else {
            root._pendingPageId = ""
            root._pendingNewEditId = ""
            root.sessionHidden()
        }
    }
    onPageIdsChanged: {
        if (root._pendingPageId.length && !root.pageIds.includes(root._pendingPageId))
            root._pendingPageId = ""
        if (!root.pageIds.includes(GlobalStates.dashboardPageId))
            GlobalStates.dashboardPageId = root.pageIds[0]
    }
    Component.onCompleted: {
        if (Config.ready) root.restoreLastPage()
        if (!root.pageIds.includes(GlobalStates.dashboardPageId)) {
            const legacy = PagePolicy.defaultOrder[GlobalStates.dashboardPage]
            root.selectPage(root.pageIds.includes(legacy) ? legacy : root.pageIds[0])
        }
        if (root.presentationActive) root.sessionShown()
    }

    function setDefaultTab(id): void {
        if (!root.pageIds.includes(id)) return
        Config.setNestedValue("dashboard.defaultTabId", id)
    }
    function openCustomTabDialog(mode, id): void {
        // Create/rename/delete are Edit Dashboard actions. Keep the editor
        // transaction alive while its toolbar is temporarily replaced.
        if (!root.editMode) return
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
        // Save the pending layout transaction before switching tabs or
        // deleting one; a conflict leaves both the editor and prompt intact.
        if (root.editMode) {
            const editor = root.canvasController
            editor?.commitEditMode()
            if (editor?.editMode) {
                root._customDialogError = editor.layoutMessage
                    || Translation.tr("Resolve the Dashboard edit conflict first")
                return
            }
        }
        if (mode === "create") {
            if (stored.length >= 20) {
                root._customDialogError = Translation.tr("Maximum 20 custom tabs")
                return
            }
            const layouts = Array.from(Config.options?.dashboard?.customTabLayouts ?? [])
            let createdId = TabPolicy.nextId(stored)
            let suffix = Number(createdId.slice(7)) || 1
            while (stored.some(tab => tab.id === createdId)
                    || layouts.some(layout => layout?.id === createdId))
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
            const layouts = Array.from(Config.options?.dashboard?.customTabLayouts ?? [])
                .filter(layout => layout?.id !== id)
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
        if (root.editMode) {
            dashboardHeader.cancelPageDrag()
            root.canvasController?.cancelEditMode()
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
                navigationPage: root.pageIds.indexOf(root._pendingPageId || root.currentPageId)
                pageCount: root.pageIds.length
                pageIds: root.pageIds
                navigationAllowed: root.navigationAllowed
                reorderAllowed: root.editMode && !root._agendaDialogShown
                customTabs: root.customTabs
                defaultTabId: Config.options?.dashboard?.defaultTabId ?? ""
                onSetDefaultTabRequested: id => root.setDefaultTab(id)
                onCreateTabRequested: root.openCustomTabDialog("create", "")
                onRenameTabRequested: id => root.openCustomTabDialog("rename", id)
                onDeleteTabRequested: id => root.openCustomTabDialog("delete", id)
                onPageMoveRequested: (id,target) => root.moveTab(id,target)
                onHorizontalWheel: event => root.handlePageWheel(event, false)
                onPageRequested: index => {root.resetPageWheel();root.requestPage(root.pageIds[index])}
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
                readonly property real slideProgress: root.editMode ? root.currentPage : pagePosition
                property real pagePosition: root.currentPage
                Behavior on pagePosition {
                    enabled: root.presentationActive && Appearance.animationsEnabled && !root.editMode
                    // Match the Weather Popup's shared spatial motion profile.
                    // Dashboard panel entrance/exit retains its separate motion.
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
                // Translate the page strip once per frame instead of updating
                // each widget-heavy page's x independently. This preserves the
                // existing horizontal viewport and all page/Loader identities.
                Item {
                    id: pageStrip
                    width: pages.width
                    height: pages.height
                    x: -pages.slideProgress * pages.width
                    DashboardCanvas {
                        id: dashboardCanvas
                        width: pages.width
                        height: pages.height
                        x: root.pageIds.indexOf("dashboard") * pages.width
                        visible: Math.abs(pages.slideProgress - root.pageIds.indexOf("dashboard")) < 1
                        enabled: root.currentPageId === "dashboard"
                        presentationActive: root.presentationActive && root.currentPageId === "dashboard"
                        warmContent: root.warmContent
                        onRequestEventsDialog: event => root.openAgendaDialog(event)
                    }
                    Loader {
                        id: musicPage
                        objectName: "dashboardMusicPageLoader"
                        asynchronous: root._userPageNavigation && root._synchronousPageId !== "music"
                        onStatusChanged: if (status === Loader.Error) root.pageLoadFailed("music")
                        width: pages.width
                        height: pages.height
                        x: root.pageIds.indexOf("music") * pages.width
                        visible: root.musicEnabled && Math.abs(pages.slideProgress - root.pageIds.indexOf("music")) < 1
                        enabled: root.currentPageId === "music"
                        active: root.musicEnabled && (root.musicVisited || root._pendingPageId === "music")
                            && (root.presentationActive || root.warmContent)
                        sourceComponent: DashboardMusic {
                            backend: root.musicBackend ?? LocalMusic
                            presentationActive: root.presentationActive && root.currentPageId === "music"
                        }
                    }
                    // Handle page gestures above the canvas and its scrollable widgets.
                    Loader {
                        id:plannerPage
                        objectName: "dashboardPlannerPageLoader"
                        asynchronous: root._userPageNavigation && root._synchronousPageId !== "weeklyPlanner"
                        onStatusChanged: if (status === Loader.Error) root.pageLoadFailed("weeklyPlanner")
                        width:pages.width;height:pages.height
                        x:root.pageIds.indexOf("weeklyPlanner")*pages.width
                        visible:Math.abs(pages.slideProgress-root.pageIds.indexOf("weeklyPlanner"))<1
                        enabled:root.currentPageId==="weeklyPlanner"
                        active:(root.plannerVisited || root._pendingPageId === "weeklyPlanner")
                            && (root.presentationActive || root.warmContent)
                        sourceComponent:DashboardWeeklyPlanner {
                            presentationActive:root.presentationActive && root.currentPageId==="weeklyPlanner"
                            onRequestEventsDialog:event=>root.openPlannerEventEditor(event)
                        }
                    }
                    // Custom canvases have isolated geometry but share the exact
                    // same Dashboard widget component implementations and services.
                    Repeater {
                        id: customPagesRepeater
                        model: root.customPageModel
                        delegate: Item {
                            id: customTabHost
                            required property var modelData
                            readonly property int pageIndex: root.pageIds.indexOf(modelData.id)
                            property var canvasController: customCanvasLoader.item
                            readonly property bool pageReady: customCanvasLoader.status === Loader.Ready
                            width: pages.width
                            height: pages.height
                            x: pageIndex * pages.width
                            visible: pageIndex >= 0 && Math.abs(pages.slideProgress - pageIndex) < 1
                            enabled: root.currentPageId === modelData.id
    
                            Loader {
                                id: customCanvasLoader
                                objectName: "dashboardCustomPageLoader-" + customTabHost.modelData.id
                                asynchronous: root._userPageNavigation
                                    && root._synchronousPageId !== customTabHost.modelData.id
                                onStatusChanged: if (status === Loader.Error)
                                    root.pageLoadFailed(customTabHost.modelData.id)
                                anchors.fill: parent
                                // Reordering changes pageIndex before slideProgress
                                // catches up. Keep the selected canvas and its draft
                                // alive through that temporary visibility change.
                                active: (root.presentationActive && (customTabHost.visible
                                        || root.currentPageId === customTabHost.modelData.id
                                        || root._pendingPageId === customTabHost.modelData.id))
                                    || (root.warmContent && root.currentPageId === customTabHost.modelData.id)
                                sourceComponent: DashboardCanvas {
                                    customTabId: customTabHost.modelData.id
                                    warmContent: root.warmContent
                                    presentationActive: root.presentationActive
                                        && root.currentPageId === customTabHost.modelData.id
                                    onRequestEventsDialog: event => root.openAgendaDialog(event)
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
            // Name editing lives in DashboardEditToolbar at its own position;
            // only destructive deletion uses the centered confirmation overlay.
            visible: root._customDialogShown && root._customDialogMode === "delete"
            mode: root._customDialogMode
            tabName: root._customDialogName
            errorText: root._customDialogError
            onNameEdited: name => {
                root._customDialogName = name
                root._customDialogError = ""
            }
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
