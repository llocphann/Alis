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

    property bool vertical: false
    property string dockPosition: "bottom"
    property var parentWindow: null
    readonly property string surfaceDialect: Appearance.surfaceDialectFor("")
    readonly property bool zzzStyle: surfaceDialect === "zzz"
    readonly property bool alisStyle: surfaceDialect === "alis"

    property Item lastHoveredButton
    property bool buttonHovered: false
    property bool contextMenuOpen: false
    property bool requestDockShow: contextMenuOpen
    property var abyssMenuPresenter: null
    property var abyssMenuHoverPresenter: null

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
        id: rebuildTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root.enabled)
                root._doRebuildDockItems()
        }
    }

    function rebuildDockItems() {
        if (!root.enabled)
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
        enabled: root.enabled
        function onValuesChanged() {
            root.rebuildDockItems()
        }
    }

    Connections {
        target: CompositorService
        enabled: root.enabled
        function onSortedToplevelsChanged() {
            root.rebuildDockItems()
        }
    }

    Connections {
        target: Config.options?.dock
        enabled: root.enabled
        function onPinnedAppsChanged() {
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
        enabled: root.enabled
        function onAppIdentityRulesChanged() {
            root.rebuildDockItems()
        }
    }

    function syncSortingDemand(): void {
        if (root.enabled && !_sortingConsumerAcquired) {
            CompositorService.acquireSortingConsumer()
            _sortingConsumerAcquired = true
            rebuildDockItems()
        } else if (!root.enabled && _sortingConsumerAcquired) {
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
    onEnabledChanged: {
        syncSortingDemand()
        if (enabled) root.refreshAxisLayout()
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

        readonly property bool _animOk: Appearance.animationsEnabled

        add: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "opacity,scale"; from: 0; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
        }
        remove: Transition {
            enabled: listView._animOk
            NumberAnimation { properties: "opacity,scale"; to: 0; duration: Appearance.animation.elementMoveExit.duration; easing.type: Appearance.animation.elementMoveExit.type; easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve }
        }
        displaced: Transition {}
        addDisplaced: Transition {}
        removeDisplaced: Transition {}
        move: Transition {}
        moveDisplaced: Transition {}

        model: ScriptModel {
            objectProp: "uniqueId"
            values: root.enabled ? root.dockItems : []
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
