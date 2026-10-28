import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Item {
    id: root
    property bool _sortingConsumerAcquired: false
    property bool residentDelegates: false
    readonly property bool activeModel: root.residentDelegates || root.enabled

    property bool vertical: false
    property string dockPosition: "bottom"
    property var parentWindow: null
    readonly property string surfaceDialect: Appearance.surfaceDialectFor("")
    readonly property bool zzzStyle: surfaceDialect === "zzz"
    readonly property bool alisStyle: surfaceDialect === "alis"

    property Item lastHoveredButton
    property bool buttonHovered: false
    property bool buttonPressed: false
    property bool suppressHoverPopup: false
    property bool contextMenuOpen: false
    property string draggedUniqueId: ""
    property string draggedSection: ""
    property bool draggedIsPinned: false
    property int draggedSourceIndex: -1
    property int draggedTargetIndex: -1
    property real dragStartAxis: 0
    property real dragMinAxis: 0
    property real dragMaxAxis: 0
    property real dragPointerAxis: 0
    property real dragGrabOffset: 25
    property bool _pendingPinnedOrderCommit: false
    property bool _committingReorder: false
    readonly property bool reorderingActive: draggedUniqueId.length > 0
    property bool requestDockShow: contextMenuOpen || reorderingActive || buttonPressed || buttonHovered
    property var abyssMenuPresenter: null
    property var abyssMenuHoverPresenter: null
    property var abyssMenuClosePresenter: null

    signal closeAllContextMenus(var exceptOwner)

    readonly property real axisExtent: {
        const values = root.dockItems ?? []
        let extent = 0
        for (const item of values)
            extent += item?.appId === "SEPARATOR" ? 8 : 50
        if (values.length > 1)
            extent += (values.length - 1) * 2
        return extent
    }
    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical
    implicitWidth: vertical ? 50 : axisExtent
    implicitHeight: vertical ? axisExtent : 50

    function openAbyssContextMenu(model, button): bool {
        if (!root.abyssMenuPresenter || !button)
            return false
        const point = button.mapToItem(root, button.width / 2, button.height / 2)
        const ownerId = String(button.appToplevel?.uniqueId
            ?? button.appToplevel?.originalAppId
            ?? button.appToplevel?.appId ?? "")
        root.abyssMenuPresenter(model, point.x, point.y, ownerId)
        return true
    }
    function setAbyssContextMenuHover(button, hovered): void {
        if (!root.abyssMenuHoverPresenter || !button)
            return
        const ownerId = String(button.appToplevel?.uniqueId
            ?? button.appToplevel?.originalAppId
            ?? button.appToplevel?.appId ?? "")
        root.abyssMenuHoverPresenter(ownerId, hovered)
    }

    function itemAxisStart(index): real {
        const values = root.dockItems ?? []
        let pos = 0
        for (let i = 0; i < index && i < values.length; i++)
            pos += (values[i]?.appId === "SEPARATOR" ? 8 : 50) + 2
        return pos
    }

    function _isCompatibleDragItem(item): bool {
        return Boolean(item)
            && item.appId !== "SEPARATOR"
            && String(item.section ?? "") === root.draggedSection
            && Boolean(item.pinned) === root.draggedIsPinned
    }

    function _commitPinnedOrderFromDockItems(): void {
        const rawPinned = Config.options?.dock?.pinnedApps ?? []
        const currentPinned = Array.from(rawPinned, id => String(id ?? "").trim()).filter(id => id.length > 0)
        if (currentPinned.length <= 1)
            return

        const originalCaseByLower = new Map()
        for (const id of currentPinned) {
            const lower = id.toLowerCase()
            if (!originalCaseByLower.has(lower))
                originalCaseByLower.set(lower, id)
        }

        const reorderedSectionIds = []
        const reorderedLowerSet = new Set()
        for (const item of (root.dockItems ?? [])) {
            if (!root._isCompatibleDragItem(item))
                continue
            const lower = String(item.appId ?? "").toLowerCase()
            if (!lower || reorderedLowerSet.has(lower))
                continue
            reorderedLowerSet.add(lower)
            reorderedSectionIds.push(originalCaseByLower.get(lower)
                ?? String(item.originalAppId ?? item.appId ?? ""))
        }

        if (reorderedSectionIds.length <= 1)
            return

        let cursor = 0
        const nextPinned = currentPinned.map(id => {
            const lower = id.toLowerCase()
            if (reorderedLowerSet.has(lower) && cursor < reorderedSectionIds.length)
                return reorderedSectionIds[cursor++]
            return id
        })

        if (JSON.stringify(nextPinned) !== JSON.stringify(currentPinned))
            Config.setNestedValue("dock.pinnedApps", nextPinned)
    }

    function _syncRunningOrderFromDockItems(): void {
        const nextOrder = []
        const seen = new Set()
        for (const item of (root.dockItems ?? [])) {
            if (!item || item.appId === "SEPARATOR" || item.pinned)
                continue
            const lower = String(item.appId ?? "").toLowerCase()
            if (lower && !seen.has(lower)) {
                seen.add(lower)
                nextOrder.push(lower)
            }
        }
        for (const existing of (root._runningAppOrder ?? [])) {
            if (!seen.has(existing)) {
                seen.add(existing)
                nextOrder.push(existing)
            }
        }
        root._runningAppOrder = nextOrder
    }

    function beginAppDrag(button, pointerAxis, grabOffset): void {
        if (!button || !button.appToplevel || button.isSeparator)
            return
        const values = root.dockItems ?? []
        const fromIdx = values.findIndex(item => item?.uniqueId === button.appToplevel.uniqueId)
        if (fromIdx < 0)
            return
        rebuildTimer.stop()
        commitReorderResetTimer.stop()
        root.suppressHoverPopup = true
        root.draggedUniqueId = String(button.appToplevel.uniqueId ?? "")
        root.draggedSection = String(button.appToplevel.section ?? "")
        root.draggedIsPinned = Boolean(button.appToplevel.pinned)
        root.draggedSourceIndex = fromIdx
        root.draggedTargetIndex = fromIdx
        root.dragStartAxis = root.itemAxisStart(fromIdx)
        let minAxis = root.dragStartAxis
        let maxAxis = root.dragStartAxis
        for (let i = 0; i < values.length; i++) {
            if (!root._isCompatibleDragItem(values[i]))
                continue
            const slotStart = root.itemAxisStart(i)
            if (slotStart < minAxis)
                minAxis = slotStart
            if (slotStart > maxAxis)
                maxAxis = slotStart
        }
        root.dragMinAxis = minAxis
        root.dragMaxAxis = maxAxis
        root.dragGrabOffset = Number.isFinite(grabOffset) ? grabOffset : 25
        root.dragPointerAxis = pointerAxis
        root._pendingPinnedOrderCommit = false
        root.closeAllContextMenus(null)
        if (root.abyssMenuClosePresenter)
            root.abyssMenuClosePresenter()
    }

    function updateAppDrag(pointerAxis): void {
        if (!root.reorderingActive)
            return
        root.dragPointerAxis = pointerAxis
        const values = root.dockItems ?? []
        const fromIdx = root.draggedSourceIndex
        if (fromIdx < 0 || fromIdx >= values.length)
            return

        const clampedStart = Math.max(root.dragMinAxis,
            Math.min(root.dragMaxAxis, pointerAxis - root.dragGrabOffset))
        const draggedCenter = clampedStart + 25
        let bestIdx = fromIdx
        let bestDist = Infinity
        for (let i = 0; i < values.length; i++) {
            if (!root._isCompatibleDragItem(values[i]))
                continue
            const slotCenter = root.itemAxisStart(i) + 25
            const dist = Math.abs(draggedCenter - slotCenter)
            if (dist < bestDist) {
                bestDist = dist
                bestIdx = i
            }
        }
        root.draggedTargetIndex = bestIdx
    }

    function visualOffsetForIndex(index, pointerAxis, targetIndex): real {
        if (!root.reorderingActive || root.draggedSourceIndex < 0 || targetIndex < 0)
            return 0
        const fromIdx = root.draggedSourceIndex
        if (index === fromIdx) {
            const desiredStart = Math.max(root.dragMinAxis,
                Math.min(root.dragMaxAxis, pointerAxis - root.dragGrabOffset))
            return desiredStart - root.dragStartAxis
        }
        const values = root.dockItems ?? []
        if (index < 0 || index >= values.length || !root._isCompatibleDragItem(values[index]))
            return 0
        const step = 52
        if (fromIdx < targetIndex && index > fromIdx && index <= targetIndex)
            return -step
        if (fromIdx > targetIndex && index >= targetIndex && index < fromIdx)
            return step
        return 0
    }

    function endAppDrag(): void {
        if (!root.reorderingActive)
            return
        const values = root.dockItems ?? []
        const fromIdx = root.draggedSourceIndex
        const toIdx = root.draggedTargetIndex
        const moved = fromIdx >= 0 && toIdx >= 0 && fromIdx !== toIdx
            && fromIdx < values.length && toIdx < values.length
        const wasPinned = root.draggedIsPinned

        root.suppressHoverPopup = true
        root._committingReorder = true
        commitReorderResetTimer.restart()

        root.draggedUniqueId = ""
        root.draggedSourceIndex = -1
        root.draggedTargetIndex = -1

        if (moved) {
            const nextItems = values.slice()
            const [movedItem] = nextItems.splice(fromIdx, 1)
            nextItems.splice(toIdx, 0, movedItem)
            for (let i = 0; i < nextItems.length; i++)
                nextItems[i].order = i
            root.dockItems = nextItems
            listView.forceLayout()
            if (wasPinned)
                root._commitPinnedOrderFromDockItems()
            else
                root._syncRunningOrderFromDockItems()
        }

        root.draggedSection = ""
        root.draggedIsPinned = false
        root._pendingPinnedOrderCommit = false
        if (!moved)
            root.rebuildDockItems()
    }

    property var dockItems: []
    property var toplevelsByUniqueId: ({})
    property var _runningAppOrder: []

    readonly property bool separatePinnedFromRunning: Config.options?.dock?.separatePinnedFromRunning ?? true
    onSeparatePinnedFromRunningChanged: {
        root.rebuildDockItems()
    }

    property var _cachedIgnoredRegexes: []
    property var _lastIgnoredRegexStrings: []

    function _getIgnoredRegexes(): list<var> {
        const ignoredRegexStrings = Config.options?.dock?.ignoredAppRegexes ?? [];
        if (JSON.stringify(ignoredRegexStrings) !== JSON.stringify(_lastIgnoredRegexStrings)) {
            const systemIgnored = ["^$", "^portal$", "^x-run-dialog$", "^kdialog$", "^org.freedesktop.impl.portal.*"];
            const allIgnored = ignoredRegexStrings.concat(systemIgnored);
            _cachedIgnoredRegexes = allIgnored.map(pattern => new RegExp(pattern, "i"));
            _lastIgnoredRegexStrings = ignoredRegexStrings.slice();
        }
        return _cachedIgnoredRegexes;
    }

    Timer {
        id: commitReorderResetTimer
        interval: 180
        repeat: false
        onTriggered: {
            root._committingReorder = false
            root.suppressHoverPopup = false
        }
    }

    Timer {
        id: rebuildTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root.activeModel && !root.reorderingActive)
                root._doRebuildDockItems()
        }
    }

    function rebuildDockItems() {
        if (!root.activeModel || root.reorderingActive)
            return
        rebuildTimer.restart()
    }

    function _toplevelLiveKey(toplevel) {
        if (!toplevel) return ""
        if (toplevel._sourceKey !== undefined && toplevel._sourceKey !== null)
            return String(toplevel._sourceKey)
        return `${toplevel.appId || ""}::${toplevel.title || ""}`
    }

    function _dockItemsEqual(oldItems, newItems): bool {
        if (oldItems.length !== newItems.length) return false
        for (let i = 0; i < oldItems.length; i++) {
            const o = oldItems[i], n = newItems[i]
            if (o.uniqueId !== n.uniqueId || o.pinned !== n.pinned || o.section !== n.section) return false
            const oTL = o.toplevels, nTL = n.toplevels
            if (oTL.length !== nTL.length) return false
            for (let j = 0; j < oTL.length; j++) {
                if (root._toplevelLiveKey(oTL[j]) !== root._toplevelLiveKey(nTL[j])) return false
                if (!!oTL[j].activated !== !!nTL[j].activated) return false
            }
        }
        return true
    }

    function _doRebuildDockItems() {
        const pinnedApps = Config.options?.dock?.pinnedApps ?? [];
        const pinnedIds = new Set(pinnedApps.map(id => String(id ?? "").toLowerCase()));
        const hiddenPinnedIds = new Set((Config.options?.dock?.hiddenPinnedApps ?? [])
            .map(id => String(id ?? "").toLowerCase()));
        const visiblePinnedApps = pinnedApps.filter(appId =>
            !hiddenPinnedIds.has(String(appId ?? "").toLowerCase()));
        const ignoredRegexes = _getIgnoredRegexes();
        const separatePinnedFromRunning = root.separatePinnedFromRunning;

        const tmToplevels = ToplevelManager.toplevels.values;
        const sorted = CompositorService.sortedToplevels;
        const sortedHasItems = sorted && sorted.length > 0;
        const niriAuthoritative = CompositorService.isNiri;
        const allToplevels = niriAuthoritative
            ? (sorted ?? [])
            : (sortedHasItems ? sorted : tmToplevels);

        const liveToplevelCounts = new Map();
        const crossCheck = sortedHasItems && !niriAuthoritative;
        if (crossCheck) {
            for (const tl of tmToplevels) {
                const key = root._toplevelLiveKey(tl);
                liveToplevelCounts.set(key, (liveToplevelCounts.get(key) ?? 0) + 1);
            }
        }

        const runningAppsMap = new Map();
        for (const toplevel of allToplevels) {
            if (!toplevel.appId) continue;
            if (toplevel.appId === "" || toplevel.appId === "null") continue;
            if (crossCheck) {
                const key = root._toplevelLiveKey(toplevel);
                const count = liveToplevelCounts.get(key) ?? 0;
                if (count <= 0) continue;
                liveToplevelCounts.set(key, count - 1);
            }
            const effectiveId = AppSearch.resolveWindowIdentity(toplevel);
            const lowerAppId = effectiveId.toLowerCase();

            if (pinnedIds.has(lowerAppId) && hiddenPinnedIds.has(lowerAppId))
                continue;

            if (ignoredRegexes.some(re => re.test(effectiveId))) {
                continue;
            }

            if (!runningAppsMap.has(lowerAppId)) {
                runningAppsMap.set(lowerAppId, {
                    appId: effectiveId,
                    toplevels: [],
                    pinned: false
                });
            }
            runningAppsMap.get(lowerAppId).toplevels.push(toplevel);
        }

        const currentRunning = new Set(runningAppsMap.keys());
        const runningOrder = root._runningAppOrder.filter(appId => currentRunning.has(appId));
        const runningOrderSet = new Set(runningOrder);
        for (const [lowerAppId] of runningAppsMap) {
            if (!runningOrderSet.has(lowerAppId)) {
                runningOrderSet.add(lowerAppId);
                runningOrder.push(lowerAppId);
            }
        }
        root._runningAppOrder = runningOrder;
        const runningOrderIndex = new Map();
        for (let i = 0; i < runningOrder.length; ++i) {
            const appId = runningOrder[i];
            if (!runningOrderIndex.has(appId))
                runningOrderIndex.set(appId, i);
        }

        const values = [];
        let order = 0;

        if (!separatePinnedFromRunning) {
            for (const appId of visiblePinnedApps) {
                const lowerAppId = appId.toLowerCase();
                const runningEntry = runningAppsMap.get(lowerAppId);
                if (!runningEntry && !AppSearch.lookupDesktopEntry(appId))
                    continue;
                values.push({
                    uniqueId: "app-" + lowerAppId,
                    appId: lowerAppId,
                    toplevels: runningEntry?.toplevels ?? [],
                    pinned: true,
                    originalAppId: appId,
                    section: "pinned",
                    order: order++
                });
                runningAppsMap.delete(lowerAppId);
            }

            if (values.length > 0 && runningAppsMap.size > 0) {
                values.push({
                    uniqueId: "separator",
                    appId: "SEPARATOR",
                    toplevels: [],
                    pinned: false,
                    originalAppId: "SEPARATOR",
                    section: "separator",
                    order: order++
                });
            }

            const running = Array.from(runningAppsMap.entries())
                .sort((a, b) => runningOrderIndex.get(a[0])
                    - runningOrderIndex.get(b[0]));
            for (const [lowerAppId, entry] of running) {
                values.push({
                    uniqueId: "app-" + lowerAppId,
                    appId: lowerAppId,
                    toplevels: entry.toplevels,
                    pinned: false,
                    originalAppId: entry.appId,
                    section: "open",
                    order: order++
                });
            }
        } else {
            for (const appId of visiblePinnedApps) {
                const lowerAppId = appId.toLowerCase();
                if (!runningAppsMap.has(lowerAppId)) {
                    if (!AppSearch.lookupDesktopEntry(appId))
                        continue;
                    values.push({
                        uniqueId: "app-" + lowerAppId,
                        appId: lowerAppId,
                        toplevels: [],
                        pinned: true,
                        originalAppId: appId,
                        section: "pinned",
                        order: order++
                    });
                }
            }

            const hasPinnedOnly = values.length > 0;
            const hasRunning = runningAppsMap.size > 0;

            if (hasPinnedOnly && hasRunning) {
                values.push({
                    uniqueId: "separator",
                    appId: "SEPARATOR",
                    toplevels: [],
                    pinned: false,
                    originalAppId: "SEPARATOR",
                    section: "separator",
                    order: order++
                });
            }

            const sortedRunningApps = [];
            for (const [lowerAppId, entry] of runningAppsMap) {
                sortedRunningApps.push({
                    lowerAppId: lowerAppId,
                    entry: entry
                });
            }
            const pinnedOrder = new Map()
            for (let i = 0; i < visiblePinnedApps.length; i++)
                pinnedOrder.set(visiblePinnedApps[i].toLowerCase(), i)

            sortedRunningApps.sort((a, b) => {
                const aPinned = pinnedOrder.has(a.lowerAppId)
                const bPinned = pinnedOrder.has(b.lowerAppId)
                if (aPinned && bPinned)
                    return pinnedOrder.get(a.lowerAppId) - pinnedOrder.get(b.lowerAppId)
                if (aPinned !== bPinned)
                    return aPinned ? -1 : 1
                return runningOrderIndex.get(a.lowerAppId)
                    - runningOrderIndex.get(b.lowerAppId)
            });

            for (const {lowerAppId, entry} of sortedRunningApps) {
                values.push({
                    uniqueId: "app-" + lowerAppId,
                    appId: lowerAppId,
                    toplevels: entry.toplevels,
                    pinned: pinnedIds.has(lowerAppId),
                    originalAppId: entry.appId,
                    section: "running",
                    order: order++
                });
            }
        }

        const tlMap = {}
        for (const v of values) tlMap[v.uniqueId] = v.toplevels
        root.toplevelsByUniqueId = tlMap

        if (!_dockItemsEqual(dockItems, values)) {
            dockItems = values
        }
    }

    Connections {
        target: ToplevelManager.toplevels
        enabled: root.activeModel
        function onValuesChanged() {
            root.rebuildDockItems()
        }
    }

    Connections {
        target: CompositorService
        enabled: root.activeModel
        function onSortedToplevelsChanged() {
            root.rebuildDockItems()
        }
    }

    Connections {
        target: Config.options?.dock
        enabled: root.activeModel
        function onPinnedAppsChanged() {
            if (!root._committingReorder)
                root.rebuildDockItems()
        }
        function onHiddenPinnedAppsChanged() {
            root.rebuildDockItems()
        }
        function onIgnoredAppRegexesChanged() {
            root.rebuildDockItems()
        }
    }
    Connections {
        target: Config.options?.windows
        enabled: root.activeModel
        function onAppIdentityRulesChanged() {
            root.rebuildDockItems()
        }
    }

    function syncSortingDemand(): void {
        if (root.activeModel && !_sortingConsumerAcquired) {
            CompositorService.acquireSortingConsumer()
            _sortingConsumerAcquired = true
            rebuildDockItems()
        } else if (!root.activeModel && _sortingConsumerAcquired) {
            rebuildTimer.stop()
            CompositorService.releaseSortingConsumer()
            _sortingConsumerAcquired = false
        }
    }

    function refreshAxisLayout(): void {
        root.closeAllContextMenus(null)
        root.rebuildDockItems()
        Qt.callLater(() => {
            listView.forceLayout()
            listView.positionViewAtBeginning()
            Qt.callLater(() => listView.forceLayout())
        })
    }

    onVerticalChanged: root.refreshAxisLayout()
    onDockPositionChanged: root.refreshAxisLayout()
    onActiveModelChanged: {
        syncSortingDemand()
        if (activeModel) root.refreshAxisLayout()
    }
    Component.onCompleted: syncSortingDemand()
    Component.onDestruction: {
        if (_sortingConsumerAcquired)
            CompositorService.releaseSortingConsumer()
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: 2
        orientation: root.vertical ? ListView.Vertical : ListView.Horizontal
        implicitWidth: root.implicitWidth
        implicitHeight: root.implicitHeight
        // Dock item counts are small. Keep every delegate resident so an
        // orientation switch cannot strand a virtualized horizontal viewport
        // while the same ListView becomes vertical (or vice versa).
        cacheBuffer: Math.max(256, root.axisExtent + 100)
        interactive: false
        clip: false

        Behavior on implicitWidth {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
        }
        Behavior on implicitHeight {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
        }

        readonly property bool _animOk: Appearance.animationsEnabled && !root._committingReorder

        add: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "opacity,scale"; from: 0; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
        }
        remove: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "opacity,scale"; to: 0; duration: Appearance.animation.elementMoveExit.duration; easing.type: Appearance.animation.elementMoveExit.type; easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve }
        }
        displaced: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "x,y"; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
        }
        addDisplaced: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "x,y"; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
        }
        removeDisplaced: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "x,y"; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
        }
        move: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "x,y"; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
        }
        moveDisplaced: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "x,y"; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
        }

        model: ScriptModel {
            objectProp: "uniqueId"
            values: root.activeModel ? root.dockItems : []
        }

        delegate: DockAppButton {
            id: dockDelegate
            required property var modelData
            required property int index
            appToplevel: modelData
            appListRoot: root
            vertical: root.vertical

            anchors.verticalCenter: !root.vertical ? parent?.verticalCenter : undefined
            anchors.horizontalCenter: root.vertical ? parent?.horizontalCenter : undefined

            topInset: 0
            bottomInset: 0
            leftInset: 0
            rightInset: 0

        }
    }

}
