pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks as Waffle
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
    property bool waffleMenu: false
    property bool warmContent: false
    property bool presentationActive: GlobalStates.dashboardOpen || GlobalStates.overviewOpen
    property bool _firstSurfaceReady: false
    property bool _surfaceCompleted: false
    readonly property bool _rawContentReady: {
        if (root.currentPageId === "dashboard")
            return dashboardCanvas.widgetsReady
        if (root.currentPageId === "music")
            return musicPage.status === Loader.Ready
        if (root.currentPageId === "weeklyPlanner")
            return plannerPage.status === Loader.Ready
        if (root.currentPageId === "spacedRepetition")
            return spacedRepetitionPage.status === Loader.Ready
        if (root.currentPageId === "exercisesTracker")
            return exercisesTrackerPage.status === Loader.Ready
        const index = root.customTabs.findIndex(tab => tab.id === root.currentPageId)
        return index < 0 || (customPagesRepeater.itemAt(index)?.pageReady ?? true)
    }
    function _syncFirstSurfaceReady(): void {
        if (root._surfaceCompleted && root._rawContentReady && (root.presentationActive || root.warmContent))
            root._firstSurfaceReady = true
    }
    on_RawContentReadyChanged: root._syncFirstSurfaceReady()
    onWarmContentChanged: if (warmContent) root._syncFirstSurfaceReady()
    readonly property bool contentReady: _firstSurfaceReady || _rawContentReady

    readonly property bool musicEnabled: Config.options?.dashboard?.music?.enable ?? true
    readonly property bool spacedRepetitionPluginManaged: AlisIntergration.available
        && AlisIntergration.installedPlugins.some(plugin => plugin.id === "spaced_repetition")
    readonly property bool spacedRepetitionEnabled: (spacedRepetitionPluginManaged ? AlisIntergration.spacedRepetitionEnabled : true)
        && (Config.options?.dashboard?.spacedRepetition?.enable ?? true)
        && (Config.options?.dashboard?.pageOrderVersion ?? 1) >= 1
        && Array.from(dashboardCanvas.effectivePageOrder ?? []).includes("spacedRepetition")
    readonly property bool exercisesTrackerEnabled: AlisIntergration.exercisesTrackerEnabled
        && (Config.options?.dashboard?.exercisesTracker?.enable ?? true)
        && AlisIntergration.exercisesTrackerDashboardSource().length > 0
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
    readonly property var availablePageIds: {
        const base = TabPolicy.available(root.customTabs, root.musicEnabled, root.spacedRepetitionEnabled)
        if (!root.exercisesTrackerEnabled)
            return base
        const customIdx = base.findIndex(id => id.startsWith("custom-"))
        if (customIdx < 0)
            return base.concat(["exercisesTracker"])
        const copy = base.slice()
        copy.splice(customIdx, 0, "exercisesTracker")
        return copy
    }
    readonly property var pageIds: PagePolicy.ordered(
        root._navigationDraftOrder ?? dashboardCanvas.effectivePageOrder,
        root.availablePageIds)
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
    property bool spacedRepetitionVisited: currentPageId === "spacedRepetition"
    property bool exercisesTrackerVisited: currentPageId === "exercisesTracker"
    property double _musicLastActiveMs: currentPageId === "music" ? Date.now() : 0
    property double _plannerLastActiveMs: currentPageId === "weeklyPlanner" ? Date.now() : 0
    property double _srLastActiveMs: currentPageId === "spacedRepetition" ? Date.now() : 0
    property double _exLastActiveMs: currentPageId === "exercisesTracker" ? Date.now() : 0
    property string _prevPageId: currentPageId
    function _touchDashboardTabTimestamp(pageId): void {
        const now = Date.now()
        if (pageId === "music") _musicLastActiveMs = now
        else if (pageId === "weeklyPlanner") _plannerLastActiveMs = now
        else if (pageId === "spacedRepetition") _srLastActiveMs = now
        else if (pageId === "exercisesTracker") _exLastActiveMs = now
    }
    function _evictIdleDashboardTabs(forceAllInactive): void {
        if (Config.options?.performance?.keepPanelsWarm ?? false)
            return
        const now = Date.now()
        const ttl = 240000
        if (root.musicVisited && !(root.presentationActive && root.currentPageId === "music")
                && (forceAllInactive || (_musicLastActiveMs > 0 && now - _musicLastActiveMs >= ttl))) {
            root.musicVisited = false
            root._musicLastActiveMs = 0
        }
        if (root.plannerVisited && !(root.presentationActive && root.currentPageId === "weeklyPlanner")
                && (forceAllInactive || (_plannerLastActiveMs > 0 && now - _plannerLastActiveMs >= ttl))) {
            root.plannerVisited = false
            root._plannerLastActiveMs = 0
        }
        if (root.spacedRepetitionVisited && !(root.presentationActive && root.currentPageId === "spacedRepetition")
                && (forceAllInactive || (_srLastActiveMs > 0 && now - _srLastActiveMs >= ttl))) {
            root.spacedRepetitionVisited = false
            root._srLastActiveMs = 0
        }
        if (root.exercisesTrackerVisited && !(root.presentationActive && root.currentPageId === "exercisesTracker")
                && (forceAllInactive || (_exLastActiveMs > 0 && now - _exLastActiveMs >= ttl))) {
            root.exercisesTrackerVisited = false
            root._exLastActiveMs = 0
        }
    }
    Timer {
        id: tabIdleEvictTimer
        interval: 30000
        repeat: true
        running: !(Config.options?.performance?.keepPanelsWarm ?? false)
            && (root.musicVisited || root.plannerVisited || root.spacedRepetitionVisited || root.exercisesTrackerVisited)
        onTriggered: root._evictIdleDashboardTabs(false)
    }
    Connections {
        target: MemoryPressureService
        function onPressureExceeded(): void { root._evictIdleDashboardTabs(true) }
    }
    readonly property var exercisesTrackerItem: exercisesTrackerPage.item
    property string _pendingPageId: ""
    property string _synchronousPageId: ""
    property bool _userPageNavigation: false
    // Keep only outgoing custom canvases alive until the slide finishes.
    // Crossing an unselected tab must not initialize its widgets.
    property var _slideHeldCustomIds: []
    // Persist the last tab after the slide and a short idle interval,
    // not during the frames which move the widget-heavy page strip.
    property string _pageSavePendingId: ""
    function flushPageSelection(): void {
        const id = root._pageSavePendingId
        root._pageSavePendingId = ""
        if (id.length > 0 && Config.ready && root.pageIds.includes(id)
                && Config.options?.dashboard?.lastPageId !== id)
            Config.setNestedValue("dashboard.lastPageId", id)
    }
    readonly property bool pendingPageReady: {
        if (_pendingPageId === "dashboard") return true
        if (_pendingPageId === "music") return musicPage.status === Loader.Ready
        if (_pendingPageId === "weeklyPlanner") return plannerPage.status === Loader.Ready
        if (_pendingPageId === "spacedRepetition") return spacedRepetitionPage.status === Loader.Ready
        if (_pendingPageId === "exercisesTracker") return exercisesTrackerPage.status === Loader.Ready
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
        if (root._prevPageId !== currentPageId) {
            root._touchDashboardTabTimestamp(root._prevPageId)
            root._prevPageId = currentPageId
        }
        root._touchDashboardTabTimestamp(currentPageId)
        if (_pendingPageId.length && _pendingPageId !== currentPageId)
            _pendingPageId = ""
        if (_pendingNewEditId.length && currentPageId !== _pendingNewEditId)
            _pendingNewEditId = ""
        if (currentPageId === "music") musicVisited = true
        if (currentPageId === "weeklyPlanner") plannerVisited = true
        if (currentPageId === "spacedRepetition") {
            spacedRepetitionVisited = true
            if (root.presentationActive)
                Qt.callLater(() => root.focusPrimarySurface())
        }
        if (currentPageId === "exercisesTracker") {
            exercisesTrackerVisited = true
            if (root.presentationActive)
                Qt.callLater(() => root.focusPrimarySurface())
        }
    }

    readonly property bool navigationAllowed: root.presentationActive && pageIds.length > 1
        && !root.editMode && !root._agendaDialogShown && !root._customDialogShown
        && !(musicPage.item?.playlistDialogVisible ?? false)
        && !(plannerPage.item?.sideView === "events")
    readonly property bool pageSlideInFlight: Math.abs(pages.pagePosition - root.currentPage) > 0.01
    property bool _skipSyncOnLegacyPageChange: false
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
        const previousId = root.currentPageId
        if (previousId !== id && previousId.startsWith("custom-")
                && !root._slideHeldCustomIds.includes(previousId))
            root._slideHeldCustomIds = root._slideHeldCustomIds.concat([previousId])
        GlobalStates.dashboardPageId = id
        const legacy = PagePolicy.defaultOrder.indexOf(id)
        if (legacy >= 0 && GlobalStates.dashboardPage !== legacy)
            GlobalStates.dashboardPage = legacy
        root._pendingPageId = ""
    }
    function selectPageAsync(id): void {
        if (!pageIds.includes(id)) return
        root._synchronousPageId = ""
        const previousId = root.currentPageId
        if (previousId !== id && previousId.startsWith("custom-")
                && !root._slideHeldCustomIds.includes(previousId))
            root._slideHeldCustomIds = root._slideHeldCustomIds.concat([previousId])
        root._skipSyncOnLegacyPageChange = true
        GlobalStates.dashboardPageId = id
        const legacy = PagePolicy.defaultOrder.indexOf(id)
        if (legacy >= 0 && GlobalStates.dashboardPage !== legacy)
            GlobalStates.dashboardPage = legacy
        root._skipSyncOnLegacyPageChange = false
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
        if (root.pageSlideInFlight) {
            if (movement.x && Math.abs(movement.x) > Math.abs(movement.y))
                event.accepted = true
            return
        }
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
            if (root._skipSyncOnLegacyPageChange) return
            const id = PagePolicy.defaultOrder[GlobalStates.dashboardPage] ?? "dashboard"
            root.selectPage(root.pageIds.includes(id) ? id : root.pageIds[0])
        }
        function onDashboardPageIdChanged(): void {
            if (!Config.ready || !GlobalStates.dashboardSelectionRestored) return
            const id = GlobalStates.dashboardPageId
            if (root.pageIds.includes(id))
                root._pageSavePendingId = id
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return
            Qt.callLater(() => {
                if (!Config.ready) return
                root.restoreLastPage()
                if (root.presentationActive) root.sessionShown()
            })
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
        if (target !== root.currentPageId) root.selectPageAsync(target)
    }
    function sessionHidden(): void {
        if (!root._sessionWasVisible) return
        root._sessionWasVisible = false
        Config.setNestedValue("dashboard.lastHiddenAtMs", Date.now())
    }
    onPresentationActiveChanged: {
        root._touchDashboardTabTimestamp(root.currentPageId)
        if (root.presentationActive) {
            root.sessionShown()
            root._syncFirstSurfaceReady()
        } else {
            // A hidden Dashboard may be unloaded before a deferred Timer fires.
            root.flushPageSelection()
            root._pendingPageId = ""
            root._pendingNewEditId = ""
            root._slideHeldCustomIds = []
            root.sessionHidden()
        }
    }
    onPageIdsChanged: {
        if (root._pendingPageId.length && !root.pageIds.includes(root._pendingPageId))
            root._pendingPageId = ""
        if (!root.pageIds.includes(GlobalStates.dashboardPageId)) {
            Qt.callLater(() => {
                if (root.pageIds.length > 0 && !root.pageIds.includes(GlobalStates.dashboardPageId))
                    GlobalStates.dashboardPageId = root.pageIds[0]
            })
        }
    }
    Component.onCompleted: {
        if (Config.ready) root.restoreLastPage()
        if (!root.pageIds.includes(GlobalStates.dashboardPageId)) {
            const legacy = PagePolicy.defaultOrder[GlobalStates.dashboardPage]
            root.selectPageAsync(root.pageIds.includes(legacy) ? legacy : root.pageIds[0])
        }
        if (root.presentationActive) root.sessionShown()
        root._surfaceCompleted = true
        root._syncFirstSurfaceReady()
    }
    Component.onDestruction: {
        if (root._sessionWasVisible) {
            root.flushPageSelection()
            root.sessionHidden()
        }
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

    readonly property bool showHeader: true

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
        if (currentPageId === "spacedRepetition" && (spacedRepetitionPage.item?.handleEscape() ?? false))
            return true
        if (currentPageId === "exercisesTracker" && (root.exercisesTrackerItem?.handleEscape?.() ?? false))
            return true
        if (currentPageId === "music" && (musicPage.item?.restoreBrowserColumns() ?? false))
            return true
        if (currentPageId === "weeklyPlanner" && (plannerPage.item?.handleEscape() ?? false))
            return true
        if (currentPageId === "dashboard" || root.customTabs.some(tab => tab.id === currentPageId))
            return root.canvasController?.handleEscape() ?? false
        return false
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
    function focusPrimarySurface(): void {
        if (root.currentPageId === "spacedRepetition" && spacedRepetitionPage.item && spacedRepetitionPage.visible) {
            spacedRepetitionPage.item.focusPrimarySurface()
            return
        }
        if (root.currentPageId === "exercisesTracker" && root.exercisesTrackerItem && exercisesTrackerPage.visible) {
            if (typeof root.exercisesTrackerItem.focusPrimarySurface === "function")
                root.exercisesTrackerItem.focusPrimarySurface()
            else
                root.exercisesTrackerItem.forceActiveFocus()
            return
        }
        root.forceActiveFocus()
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
        objectName: "dashboardSurfaceBackground"
        anchors.fill: parent
        clip: true
        color: root.embeddedSurface ? "transparent"
            : root.waffleMenu ? Waffle.Looks.colors.bgPanelFooterBase : Appearance.colors.colLayer0
        radius: root.embeddedSurface ? 0 : root.waffleMenu ? Waffle.Looks.radius.large : Appearance.rounding.large
        border.width: root.waffleMenu ? 1 : 0
        border.color: root.waffleMenu ? Waffle.Looks.colors.bg2Border : "transparent"

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: !root.embeddedSurface && root.waffleMenu
            color: Waffle.Looks.colors.bgPanelBody
        }

        ColumnLayout {
            id: mainColumn
            readonly property bool compact: root.waffleMenu
            anchors.fill: parent
            anchors.margins: root.embeddedSurface ? 0 : (compact ? 12 : 16)
            spacing: compact ? 8 : 12

            DashboardHeader {
                id: dashboardHeader
                waffleMenu: root.waffleMenu
                Layout.fillWidth: true
                visible: root.showHeader || root.pageIds.length > 1
                showActions: root.showHeader
                currentPage: root.currentPage
                // Link the indicator to the page strip's single frame-by-frame
                // motion; no separate dot timer or repaint-heavy page state.
                indicatorProgress: pages.slideProgress
                navigationPage: root.pageIds.indexOf(root._pendingPageId || root.currentPageId)
                pageCount: root.pageIds.length
                pageIds: root.pageIds
                navigationAllowed: root.navigationAllowed
                pageSlideInFlight: root.pageSlideInFlight
                reorderAllowed: root.editMode && !root._agendaDialogShown
                customTabs: root.customTabs
                defaultTabId: Config.options?.dashboard?.defaultTabId ?? ""
                onSetDefaultTabRequested: id => root.setDefaultTab(id)
                onCreateTabRequested: root.openCustomTabDialog("create", "")
                onRenameTabRequested: id => root.openCustomTabDialog("rename", id)
                onDeleteTabRequested: id => root.openCustomTabDialog("delete", id)
                onPageMoveRequested: (id,target) => root.moveTab(id,target)
                onHorizontalWheel: event => root.handlePageWheel(event, false)
                onPageRequested: index => {
                    root.resetPageWheel()
                    const targetId = root.pageIds[index]
                    if (root.editMode) {
                        if (targetId && (targetId === "dashboard" || targetId.startsWith("custom-")) && targetId !== root.currentPageId) {
                            const prevEditor = root.canvasController
                            prevEditor?.commitEditMode()
                            root._pendingNewEditId = targetId
                            root.selectPage(targetId)
                        }
                        return
                    }
                    root.requestPage(targetId)
                }
                editMode: root.editMode
                onEditModeRequested: {
                    if (root.canvasController?.editMode)
                        root.canvasController.commitEditMode();
                    else
                        root.canvasController?.beginEditMode();
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                visible: root.waffleMenu && dashboardHeader.visible
                color: Waffle.Looks.colors.bgPanelSeparator
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
                    // The Weather curve overshoots: on a full-width tab this
                    // visibly reverses near the target. Use monotone easing
                    // without changing configured movement duration.
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }
                // Keep the outgoing custom canvas until the slide is over.
                // Release on a later event turn, not inside frame evaluation.
                Timer {
                    interval: 0
                    running: root._slideHeldCustomIds.length > 0
                        && (!root.presentationActive || root.editMode
                            || !Appearance.animationsEnabled
                            || Math.abs(pages.pagePosition - root.currentPage) < 0.001)
                    onTriggered: root._slideHeldCustomIds = []
                }
                // Config.setNestedValue() emits global configChanged and
                // schedules a disk write at 50ms. Neither belongs inside
                // the page animation. Coalesce rapid tab choices; persist
                // when the slide is finished and navigation is briefly idle.
                Timer {
                    interval: 200
                    running: root._pageSavePendingId.length > 0
                        && (!root.presentationActive || root.editMode
                            || !Appearance.animationsEnabled
                            || Math.abs(pages.pagePosition - root.currentPage) < 0.001)
                    onTriggered: root.flushPageSelection()
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
                        menuPresentation: root.waffleMenu
                        width: pages.width
                        height: pages.height
                        x: root.pageIds.indexOf("dashboard") * pages.width
                        visible: Math.abs(pages.slideProgress - root.pageIds.indexOf("dashboard")) < 1
                        enabled: root.currentPageId === "dashboard"
                        presentationActive: root.presentationActive && (root.currentPageId === "dashboard"
                            || (root.pageIds.indexOf("dashboard") >= 0
                                && Math.abs(pages.slideProgress - root.pageIds.indexOf("dashboard")) < 0.999))
                        layer.enabled: visible && Math.abs(pages.pagePosition - root.currentPage) > 0.001
                        warmContent: root.warmContent && root.currentPageId === "dashboard"
                        onRequestEventsDialog: event => root.openAgendaDialog(event)
                    }
                    Loader {
                        id: musicPage
                        objectName: "dashboardMusicPageLoader"
                        asynchronous: root._synchronousPageId !== "music" && status !== Loader.Ready
                        onStatusChanged: if (status === Loader.Error) root.pageLoadFailed("music")
                        width: pages.width
                        height: pages.height
                        x: root.pageIds.indexOf("music") * pages.width
                        visible: root.musicEnabled && Math.abs(pages.slideProgress - root.pageIds.indexOf("music")) < 1
                        enabled: root.currentPageId === "music"
                        layer.enabled: visible && Math.abs(pages.pagePosition - root.currentPage) > 0.001
                        active: root.musicEnabled && (root.musicVisited || root._pendingPageId === "music")
                            && (root.presentationActive || root.warmContent)
                        function _syncMusicSource(): void {
                            if (active) {
                                if (!item) {
                                    setSource(Qt.resolvedUrl("DashboardMusic.qml"), {
                                        backend: root.musicBackend ?? LocalMusic,
                                        presentationActive: root.presentationActive && root.currentPageId === "music"
                                    })
                                }
                            } else if (source.toString().length > 0) {
                                source = ""
                            }
                        }
                        Component.onCompleted: _syncMusicSource()
                        onActiveChanged: _syncMusicSource()
                        Binding {
                            target: musicPage.item
                            property: "backend"
                            when: musicPage.status === Loader.Ready && musicPage.item !== null
                            value: root.musicBackend ?? LocalMusic
                        }
                        Binding {
                            target: musicPage.item
                            property: "presentationActive"
                            when: musicPage.status === Loader.Ready && musicPage.item !== null
                            value: root.presentationActive && root.currentPageId === "music"
                        }
                    }
                    // Handle page gestures above the canvas and its scrollable widgets.
                    Loader {
                        id:plannerPage
                        objectName: "dashboardPlannerPageLoader"
                        asynchronous: root._synchronousPageId !== "weeklyPlanner" && status !== Loader.Ready
                        onStatusChanged: if (status === Loader.Error) root.pageLoadFailed("weeklyPlanner")
                        width:pages.width;height:pages.height
                        x:root.pageIds.indexOf("weeklyPlanner")*pages.width
                        visible:Math.abs(pages.slideProgress-root.pageIds.indexOf("weeklyPlanner"))<1
                        enabled:root.currentPageId==="weeklyPlanner"
                        layer.enabled:visible && Math.abs(pages.pagePosition-root.currentPage)>0.001
                        active:(root.plannerVisited || root._pendingPageId === "weeklyPlanner")
                            && (root.presentationActive || root.warmContent)
                        source: active ? Qt.resolvedUrl("DashboardWeeklyPlanner.qml") : ""
                        Binding {
                            target: plannerPage.item
                            property: "presentationActive"
                            when: plannerPage.status === Loader.Ready && plannerPage.item !== null
                            value: root.presentationActive && (root.currentPageId === "weeklyPlanner"
                                || (root.pageIds.indexOf("weeklyPlanner") >= 0
                                    && Math.abs(pages.slideProgress - root.pageIds.indexOf("weeklyPlanner")) < 0.999))
                        }
                        Connections {
                            target: plannerPage.item
                            ignoreUnknownSignals: true
                            function onRequestEventsDialog(event) {
                                root.openPlannerEventEditor(event)
                            }
                        }
                    }
                    Loader {
                        id: spacedRepetitionPage
                        objectName: "dashboardSpacedRepetitionPageLoader"
                        asynchronous: root._synchronousPageId !== "spacedRepetition" && status !== Loader.Ready
                        onStatusChanged: if (status === Loader.Error) root.pageLoadFailed("spacedRepetition")
                        onLoaded: if (root.presentationActive && root.currentPageId === "spacedRepetition") Qt.callLater(() => root.focusPrimarySurface())
                        onVisibleChanged: if (visible && root.presentationActive && root.currentPageId === "spacedRepetition") Qt.callLater(() => root.focusPrimarySurface())
                        width: pages.width
                        height: pages.height
                        x: root.pageIds.indexOf("spacedRepetition") * pages.width
                        visible: root.spacedRepetitionEnabled && Math.abs(pages.slideProgress - root.pageIds.indexOf("spacedRepetition")) < 1
                        enabled: root.currentPageId === "spacedRepetition"
                        layer.enabled: visible && Math.abs(pages.pagePosition - root.currentPage) > 0.001
                        active: root.spacedRepetitionEnabled
                            && (root.spacedRepetitionVisited || root._pendingPageId === "spacedRepetition")
                            && (root.presentationActive || root.warmContent)
                        source: active ? (AlisIntergration.spacedRepetitionDashboardSource() || Qt.resolvedUrl("DashboardSpacedRepetition.qml")) : ""
                        Binding {
                            target: spacedRepetitionPage.item
                            property: "presentationActive"
                            when: spacedRepetitionPage.status === Loader.Ready && spacedRepetitionPage.item !== null
                            value: root.presentationActive && (root.currentPageId === "spacedRepetition"
                                || (root.pageIds.indexOf("spacedRepetition") >= 0
                                    && Math.abs(pages.slideProgress - root.pageIds.indexOf("spacedRepetition")) < 0.999))
                        }
                    }
                    Loader {
                        id: exercisesTrackerPage
                        objectName: "dashboardExercisesTrackerPageLoader"
                        asynchronous: root._synchronousPageId !== "exercisesTracker" && status !== Loader.Ready
                        onStatusChanged: if (status === Loader.Error) root.pageLoadFailed("exercisesTracker")
                        onLoaded: if (root.presentationActive && root.currentPageId === "exercisesTracker") Qt.callLater(() => root.focusPrimarySurface())
                        onVisibleChanged: if (visible && root.presentationActive && root.currentPageId === "exercisesTracker") Qt.callLater(() => root.focusPrimarySurface())
                        width: pages.width
                        height: pages.height
                        x: root.pageIds.indexOf("exercisesTracker") * pages.width
                        visible: root.exercisesTrackerEnabled && Math.abs(pages.slideProgress - root.pageIds.indexOf("exercisesTracker")) < 1
                        enabled: root.currentPageId === "exercisesTracker"
                        layer.enabled: visible && Math.abs(pages.pagePosition - root.currentPage) > 0.001
                        active: root.exercisesTrackerEnabled
                            && (root.exercisesTrackerVisited || root._pendingPageId === "exercisesTracker")
                            && (root.presentationActive || root.warmContent)
                        source: active ? AlisIntergration.exercisesTrackerDashboardSource() : ""
                        Binding {
                            target: root.exercisesTrackerItem
                            property: "presentationActive"
                            when: exercisesTrackerPage.status === Loader.Ready && root.exercisesTrackerItem !== null
                            value: root.presentationActive && (root.currentPageId === "exercisesTracker"
                                || (root.pageIds.indexOf("exercisesTracker") >= 0
                                    && Math.abs(pages.slideProgress - root.pageIds.indexOf("exercisesTracker")) < 0.999))
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
                            layer.enabled: visible && Math.abs(pages.pagePosition - root.currentPage) > 0.001
    
                            Loader {
                                id: customCanvasLoader
                                objectName: "dashboardCustomPageLoader-" + customTabHost.modelData.id
                                asynchronous: root._synchronousPageId !== customTabHost.modelData.id
                                onStatusChanged: if (status === Loader.Error)
                                    root.pageLoadFailed(customTabHost.modelData.id)
                                anchors.fill: parent
                                // Load only the selected/requested page; never
                                // allocate heavy widgets while sliding past.
                                active: (root.presentationActive
                                        && (root.currentPageId === customTabHost.modelData.id
                                            || root._pendingPageId === customTabHost.modelData.id
                                            || root._slideHeldCustomIds.includes(customTabHost.modelData.id)))
                                    || (root.warmContent
                                        && root.currentPageId === customTabHost.modelData.id)
                                sourceComponent: DashboardCanvas {
                                    menuPresentation: root.waffleMenu
                                    customTabId: customTabHost.modelData.id
                                    warmContent: root.warmContent
                                    presentationActive: root.presentationActive
                                        && (root.currentPageId === customTabHost.modelData.id
                                            || (customTabHost.pageIndex >= 0
                                                && Math.abs(pages.slideProgress - customTabHost.pageIndex) < 0.999))
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

                AlisLoadingScreen {
                    id: dashboardTabLoadingScreen
                    objectName: "dashboardTabLoadingScreen"
                    anchors.fill: parent
                    z: 90
                    readonly property string loadingTargetId: root._pendingPageId.length > 0
                        ? root._pendingPageId : root.currentPageId
                    readonly property bool tabLoading: root.presentationActive
                        && ((root._pendingPageId.length > 0 && !root.pendingPageReady)
                            || (!root._rawContentReady && (!root.embeddedSurface || root._firstSurfaceReady)))
                    loading: tabLoading
                    title: {
                        const tid = loadingTargetId
                        if (tid === "music") return Translation.tr("Local Music")
                        if (tid === "weeklyPlanner") return Translation.tr("Planner")
                        if (tid === "spacedRepetition") return Translation.tr("Spaced Repetition")
                        if (tid === "exercisesTracker") return Translation.tr("Exercises")
                        if (tid === "dashboard") return Translation.tr("Dashboard")
                        const custom = root.customTabs.find(t => t.id === tid)
                        return custom ? String(custom.name ?? Translation.tr("Dashboard")) : Translation.tr("Dashboard")
                    }
                    icon: {
                        const tid = loadingTargetId
                        if (tid === "music") return "music_note"
                        if (tid === "weeklyPlanner") return "calendar_month"
                        if (tid === "spacedRepetition") return "school"
                        if (tid === "exercisesTracker") return "fitness_center"
                        if (tid === "dashboard") return "dashboard"
                        return "dashboard_customize"
                    }
                    fillSurface: true
                    backdropOpacity: 0.86
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
