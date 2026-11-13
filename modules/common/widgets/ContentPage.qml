import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledFlickable {
    id: root
    property bool embedded: false
    property bool pageScrollEnabled: true
    property real bottomContentPadding: 0
    // Metadata for Settings pages
    property int settingsPageIndex: -1
    property string settingsPageName: ""
    property string customTabId: ""
    property var settingsTaskNavigator: null

    // Sub-Tab Bar & Category Sibling Sub-Page state
    property var categorySiblingPages: (parent && parent.hostSiblingPages !== undefined) ? parent.hostSiblingPages : []
    signal pageNavigationRequested(int targetPageIndex)
    signal pageSectionNavigationRequested(int targetPageIndex, string targetSection)

    property bool isSubViewActive: false
    property string activeSubViewTitle: ""
    property string activeSubViewIcon: ""
    property string _subViewKind: ""
    property double _lastSubTabWheelMs: 0
    property real _wheelDeltaAccum: 0

    default property alias contentData: pageBodyColumn.data
    property alias navigatorHeaderHost: navigatorHeaderHost
    property alias pageBodyColumn: pageBodyColumn
    property alias contentColumn: contentColumn

    property var _registeredCards: []
    property var _activeForeignCards: []
    property var _eligibleCards: []
    property var _cardPages: []
    property var _cardPageOptions: []
    property string activeCardSubTab: ""
    property string customActiveSubTab: ""
    property var activeCardItem: null
    property bool _cardTabsUpdateScheduled: false
    property bool _isDestroying: false
    property bool _persistedSectionRestored: false
    property bool _suppressSectionPersist: false
    property int _topBentoCount: 0
    property int _leftBentoCount: 0
    property int _rightBentoCount: 0
    property int _activeCanvasCount: 0

    readonly property var pageLayoutConfig: SettingsLayoutManager.getPageLayoutConfig(root.settingsPageIndex, root.customTabId)
    readonly property bool isCanvasLayoutMode: !root.embedded && (root.pageLayoutConfig?.layoutMode === "canvas")
    readonly property real leftColumnRatio: root.pageLayoutConfig?.leftColumnRatio ?? 0.5
    property real _previewLeftColumnRatio: -1
    readonly property real effectiveLeftColumnRatio: root._previewLeftColumnRatio > 0 ? root._previewLeftColumnRatio : root.leftColumnRatio

    Connections {
        target: SettingsLayoutManager
        function onLayoutRevisionChanged() {
            if (!root.embedded && !root._isDestroying)
                root._scheduleCardTabsUpdate();
        }
        function onLiveCardRevisionChanged() {
            if (!root.embedded && !root._isDestroying)
                root._scheduleCardTabsUpdate();
        }
        function onEditModeChanged() {
            if (!root.embedded && !root._isDestroying)
                root._scheduleCardTabsUpdate();
        }
    }

    function _restorePersistedSection() {
        if (root.embedded || root._persistedSectionRestored || root.settingsPageIndex < 0 || !Persistent.ready || !Persistent.states?.settings)
            return;
        root._persistedSectionRestored = true;
        var raw = String(Persistent.states.settings.pageSections || "{}");
        var map = {};
        try {
            map = JSON.parse(raw) || {};
        } catch (e) {
            map = {};
        }
        var entry = map[String(root.settingsPageIndex)];
        if (!entry || typeof entry !== "object")
            return;
        root._suppressSectionPersist = true;
        if (entry.section && typeof entry.section === "string" && entry.section.length > 0) {
            var validSection = true;
            if (root.settingsTaskNavigator && (root.settingsTaskNavigator.options?.length ?? 0) > 0) {
                validSection = false;
                var navOpts = root.settingsTaskNavigator.options;
                for (var i = 0; i < navOpts.length; i++) {
                    if (navOpts[i] && String(navOpts[i].value || "") === entry.section) {
                        validSection = true;
                        break;
                    }
                }
            }
            if (validSection) {
                if (root.hasOwnProperty("activeSection")) {
                    root.activeSection = entry.section;
                }
                if (root.settingsTaskNavigator && typeof root.settingsTaskNavigator.selected === "function") {
                    root.settingsTaskNavigator.selected(entry.section);
                }
            }
        }
        if (entry.cardTab && typeof entry.cardTab === "string" && entry.cardTab.length > 0) {
            root.activeCardSubTab = entry.cardTab;
        }
        root._suppressSectionPersist = false;
        if (!root.embedded) {
            root._updateCardTabs();
        }
        root._scheduleCardTabsUpdate();
    }

    function _savePersistedSection() {
        if (root.embedded || root._isDestroying || root._suppressSectionPersist || !root._persistedSectionRestored || root.settingsPageIndex < 0 || !Persistent.ready || !Persistent.states?.settings)
            return;
        var raw = String(Persistent.states.settings.pageSections || "{}");
        var map = {};
        try {
            map = JSON.parse(raw) || {};
        } catch (e) {
            map = {};
        }
        var secVal = "";
        if (root.hasOwnProperty("activeSection") && root.activeSection !== undefined) {
            secVal = String(root.activeSection || "");
        } else if (root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined) {
            secVal = String(root.settingsTaskNavigator.currentValue || "");
        }
        var cardVal = root._cardPageOptions.length > 1 ? String(root.activeCardSubTab || "") : "";
        var prev = map[String(root.settingsPageIndex)];
        if (prev && prev.section === secVal && prev.cardTab === cardVal)
            return;
        map[String(root.settingsPageIndex)] = {
            section: secVal,
            cardTab: cardVal
        };
        Persistent.states.settings.pageSections = JSON.stringify(map);
    }

    Connections {
        target: root
        ignoreUnknownSignals: true
        function onActiveSectionChanged() {
            root._savePersistedSection();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root._restorePersistedSection();
        }
    }

    onSettingsTaskNavigatorChanged: {
        if (root.settingsTaskNavigator && !root.embedded) {
            root._persistedSectionRestored = false;
            root._restorePersistedSection();
        }
    }

    Component.onCompleted: {
        root._restorePersistedSection();
        if (!root.embedded) {
            root._updateCardTabs();
        } else {
            root._syncPageBodyWrappers();
        }
    }

    readonly property bool _hasTaskNavigatorTabs: !root.embedded
        && root.settingsTaskNavigator !== null
        && (root.settingsTaskNavigator.activeNavigator ?? root.settingsTaskNavigator.visible)
        && Boolean(root.settingsTaskNavigator.showTabBar)
        && (root.settingsTaskNavigator.options?.length ?? 0) > 1

    readonly property bool hasCardSubTabs: !root.embedded
        && root._cardPageOptions.length > 1

    readonly property bool abyssTaskStyle: Config.options?.panelFamily === "abyss"

    onCustomTabIdChanged: {
        if (!root.embedded && !root._isDestroying) {
            root.customActiveSubTab = "";
            root._updateCardTabs();
            root._scheduleCardTabsUpdate();
        }
    }

    onCustomActiveSubTabChanged: {
        if (!root.embedded && !root._isDestroying) {
            root._scheduleCardTabsUpdate();
        }
    }

    readonly property var baseSubTabSpecs: {
        if (root.embedded)
            return [];
        var specs = [];
        if (root._hasTaskNavigatorTabs && root.settingsTaskNavigator) {
            var tOpts = root.settingsTaskNavigator.options || [];
            for (var i = 0; i < tOpts.length; i++) {
                var topt = tOpts[i];
                if (!topt) continue;
                specs.push({
                    key: String(topt.value || ""),
                    label: String(topt.displayName || ""),
                    icon: String(topt.icon || "tune")
                });
            }
        } else if (root._cardPageOptions.length > 1) {
            for (var j = 0; j < root._cardPageOptions.length; j++) {
                var popt = root._cardPageOptions[j];
                if (!popt) continue;
                specs.push({
                    key: String(popt.value || ""),
                    label: String(popt.displayName || ""),
                    icon: String(popt.icon || "tune")
                });
            }
        }
        return specs;
    }

    readonly property var effectiveSubTabSpecs: {
        void SettingsLayoutManager.layoutRevision;
        if (root.embedded)
            return [];
        return SettingsLayoutManager.getEffectiveSubTabs(
            root.settingsPageIndex,
            root.customTabId,
            root.baseSubTabSpecs
        );
    }

    readonly property bool _hasEffectiveSubTabs: !root.embedded
        && (root.effectiveSubTabSpecs.length > 1 || root._subTabItems.length > 1)

    readonly property string activeSubTabKey: {
        if (root.customActiveSubTab && root.effectiveSubTabSpecs.some(s => s && s.key === root.customActiveSubTab && s.custom))
            return root.customActiveSubTab;
        if (root._hasTaskNavigatorTabs) {
            if (root.hasOwnProperty("activeSection") && root.activeSection !== undefined && String(root.activeSection).length > 0)
                return String(root.activeSection);
            if (root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined && String(root.settingsTaskNavigator.currentValue).length > 0)
                return String(root.settingsTaskNavigator.currentValue);
        }
        if (root.hasCardSubTabs && root.activeCardSubTab.length > 0)
            return root.activeCardSubTab;
        if (root.effectiveSubTabSpecs.length > 0)
            return String(root.effectiveSubTabSpecs[0].key || "");
        return "";
    }

    readonly property string activeSubTabLabel: {
        var items = root._subTabItems || [];
        for (var j = 0; j < items.length; j++) {
            if (items[j] && items[j].active)
                return String(items[j].title || "");
        }
        var cur = root.activeSubTabKey;
        var specs = root.effectiveSubTabSpecs || [];
        for (var i = 0; i < specs.length; i++) {
            if (specs[i] && specs[i].key === cur)
                return String(specs[i].label || cur);
        }
        return cur;
    }

    // Unified single-row centered sub-tab items across category sibling pages & task sections & custom sub-tabs
    readonly property var _subTabItems: {
        void SettingsLayoutManager.layoutRevision;
        if (root.embedded)
            return [];
        var list = [];
        var siblings = root.categorySiblingPages || [];
        var curTaskVal = root.customActiveSubTab.length > 0
            ? root.customActiveSubTab
            : ((root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined)
                ? String(root.settingsTaskNavigator.currentValue)
                : "");

        if (siblings.length > 0) {
            for (var s = 0; s < siblings.length; s++) {
                var sp = siblings[s];
                if (!sp) continue;
                var pIdx = Number(sp.realIndex);
                var isCurrentPage = (pIdx === root.settingsPageIndex);
                var hasRawSubTabs = (sp.subTabs || []).length > 0;
                var rawSubTabs = (sp.subTabs || []).map(function(st) {
                    return { key: String(st?.value ?? ""), label: String(st?.name ?? ""), icon: String(st?.icon || sp.icon || "tune") };
                });
                var pSubTabs = SettingsLayoutManager.getEffectiveSubTabs(pIdx, "", rawSubTabs);
                if (hasRawSubTabs && pSubTabs.length > 0) {
                    for (var stIdx = 0; stIdx < pSubTabs.length; stIdx++) {
                        var st = pSubTabs[stIdx];
                        if (!st) continue;
                        var stVal = String(st.key || "");
                        var isStActive = isCurrentPage && (
                            curTaskVal === stVal
                            || (curTaskVal.length === 0 && stIdx === 0)
                        );
                        list.push({
                            kind: st.custom ? "customSubTab" : "pageSection",
                            title: String(st.label || ""),
                            icon: String(st.icon || sp.icon || "tune"),
                            value: stVal,
                            pageIndex: pIdx,
                            orderKey: "p" + pIdx + ":" + stVal,
                            _initIdx: list.length,
                            active: isStActive
                        });
                    }
                } else {
                    var spKey = String(sp.key || "overview");
                    var spLayout = SettingsLayoutManager.getPageLayoutConfig(pIdx, "");
                    var spLabel = (spLayout && spLayout.renamedSubTabs && spLayout.renamedSubTabs[spKey])
                        ? String(spLayout.renamedSubTabs[spKey])
                        : ((spLayout && spLayout.renamedSubTabs && spLayout.renamedSubTabs["overview"])
                            ? String(spLayout.renamedSubTabs["overview"])
                            : String(sp.name || ""));
                    list.push({
                        kind: "siblingPage",
                        title: spLabel,
                        icon: String(sp.icon || "settings"),
                        value: spKey,
                        pageIndex: pIdx,
                        orderKey: "p" + pIdx + ":" + spKey,
                        _initIdx: list.length,
                        active: isCurrentPage && root.customActiveSubTab.length === 0
                    });
                    for (var cIdx = 0; cIdx < pSubTabs.length; cIdx++) {
                        var cst = pSubTabs[cIdx];
                        if (!cst || !cst.custom || cst.key === "overview") continue;
                        var cstVal = String(cst.key || "");
                        list.push({
                            kind: "customSubTab",
                            title: String(cst.label || ""),
                            icon: String(cst.icon || sp.icon || "tune"),
                            value: cstVal,
                            pageIndex: pIdx,
                            orderKey: "p" + pIdx + ":" + cstVal,
                            _initIdx: list.length,
                            active: isCurrentPage && root.customActiveSubTab === cstVal
                        });
                    }
                }
            }

            if (list.length > 1) {
                var hubPageIndex = Number(siblings[0].realIndex);
                var hubPl = SettingsLayoutManager.getPageLayoutConfig(hubPageIndex, "");
                var curPl = SettingsLayoutManager.getPageLayoutConfig(root.settingsPageIndex, "");
                var rawOrder = (hubPl && hubPl.subTabOrder && hubPl.subTabOrder.length > 0)
                    ? hubPl.subTabOrder
                    : ((curPl && curPl.subTabOrder && curPl.subTabOrder.length > 0) ? curPl.subTabOrder : []);
                var orderArr = rawOrder.some(function(k) { return String(k).indexOf(":") > 0; })
                    ? rawOrder
                    : [];
                if (orderArr.length > 0) {
                    list.sort(function(a, b) {
                        var ia = orderArr.indexOf(a.orderKey);
                        var ib = orderArr.indexOf(b.orderKey);
                        if (ia < 0 && ib < 0)
                            return a._initIdx - b._initIdx;
                        if (ia < 0)
                            return 1;
                        if (ib < 0)
                            return -1;
                        return ia - ib;
                    });
                }
            }
        } else if (root.effectiveSubTabSpecs.length > 1) {
            for (var i = 0; i < root.effectiveSubTabSpecs.length; i++) {
                var spec = root.effectiveSubTabSpecs[i];
                if (!spec) continue;
                var sVal = String(spec.key || "");
                var itemKind = spec.custom
                    ? "customSubTab"
                    : (root._hasTaskNavigatorTabs ? "task" : "cardPage");
                var activeVal = root._hasTaskNavigatorTabs
                    ? curTaskVal
                    : (root.customActiveSubTab || (root.hasCardSubTabs ? root.activeCardSubTab : ""));
                list.push({
                    kind: itemKind,
                    title: String(spec.label || ""),
                    icon: String(spec.icon || "tune"),
                    value: sVal,
                    pageIndex: root.settingsPageIndex,
                    orderKey: sVal,
                    _initIdx: list.length,
                    active: (activeVal === sVal || (activeVal.length === 0 && i === 0))
                });
            }
        }
        return list.length > 1 ? list : [];
    }

    readonly property int _activeSubTabIndex: {
        var items = root._subTabItems || [];
        for (var i = 0; i < items.length; i++) {
            if (items[i] && items[i].active)
                return i;
        }
        return 0;
    }

    readonly property bool canMoveSubTabLeft: !root.embedded && root._subTabItems.length > 1 && root._activeSubTabIndex > 0
    readonly property bool canMoveSubTabRight: !root.embedded && root._subTabItems.length > 1 && root._activeSubTabIndex >= 0 && root._activeSubTabIndex < root._subTabItems.length - 1
    readonly property bool canRenameActiveSubTab: !root.embedded && (root._subTabItems.length > 0 || (root.effectiveSubTabSpecs.length > 0 && root.activeSubTabKey.length > 0))
    readonly property bool canDeleteActiveSubTab: {
        if (root.embedded)
            return false;
        var items = root._subTabItems || [];
        if (items.length > 1) {
            var curItem = items[root._activeSubTabIndex];
            if (curItem && curItem.kind === "siblingPage")
                return false;
            return Boolean(curItem);
        }
        return root.effectiveSubTabSpecs.length > 1 && root.activeSubTabKey.length > 0;
    }

    function reorderActiveSubTab(direction: int): bool {
        var items = root._subTabItems || [];
        if (items.length > 1) {
            var curIdx = root._activeSubTabIndex;
            var targetIdx = Math.max(0, Math.min(items.length - 1, curIdx + direction));
            if (targetIdx === curIdx)
                return false;
            var siblings = root.categorySiblingPages || [];
            if (siblings.length > 0 && root.customTabId.length === 0) {
                var order = items.map(function(it) {
                    return String(it.orderKey || ("p" + it.pageIndex + ":" + it.value));
                });
                var moved = order.splice(curIdx, 1)[0];
                order.splice(targetIdx, 0, moved);
                var hubPageIndex = Number(siblings[0].realIndex);
                SettingsLayoutManager.updatePageLayoutConfig(hubPageIndex, "", { subTabOrder: order });
                if (root.settingsPageIndex >= 0 && root.settingsPageIndex !== hubPageIndex) {
                    SettingsLayoutManager.updatePageLayoutConfigNoUndo(root.settingsPageIndex, "", { subTabOrder: order });
                }
                return true;
            }
        }
        if (root.effectiveSubTabSpecs.length > 1 && root.activeSubTabKey.length > 0) {
            SettingsLayoutManager.reorderSubTab(
                root.settingsPageIndex,
                root.customTabId,
                root.activeSubTabKey,
                direction,
                root.baseSubTabSpecs
            );
            return true;
        }
        return false;
    }

    function renameActiveSubTab(newLabel: string): void {
        var clean = String(newLabel || "").trim();
        if (!clean)
            return;
        var items = root._subTabItems || [];
        if (items.length > 0 && root._activeSubTabIndex >= 0 && root._activeSubTabIndex < items.length) {
            var curItem = items[root._activeSubTabIndex];
            var targetPage = (curItem && curItem.pageIndex !== undefined && curItem.pageIndex >= 0)
                ? curItem.pageIndex
                : root.settingsPageIndex;
            var targetKey = String(curItem?.value || root.activeSubTabKey || "overview");
            SettingsLayoutManager.renameSubTab(targetPage, root.customTabId, targetKey, clean);
            return;
        }
        if (root.activeSubTabKey.length > 0) {
            SettingsLayoutManager.renameSubTab(root.settingsPageIndex, root.customTabId, root.activeSubTabKey, clean);
        }
    }

    function createNewSubTab(label: string): string {
        var clean = String(label || "").trim();
        if (!clean)
            return "";
        var priorItems = (root._subTabItems || []).slice();
        var activeIdx = root._activeSubTabIndex;
        var newKey = SettingsLayoutManager.createSubTab(
            root.settingsPageIndex,
            root.customTabId,
            clean,
            "tab",
            root.baseSubTabSpecs
        );
        if (newKey) {
            var siblings = root.categorySiblingPages || [];
            if (siblings.length > 0 && root.customTabId.length === 0) {
                var order = priorItems.map(function(it) {
                    return String(it.orderKey || ("p" + it.pageIndex + ":" + it.value));
                });
                var newOrderKey = "p" + root.settingsPageIndex + ":" + newKey;
                order = order.filter(function(k) { return k !== newOrderKey; });
                var insertAt = (activeIdx >= 0 && activeIdx < order.length) ? (activeIdx + 1) : order.length;
                order.splice(insertAt, 0, newOrderKey);
                var hubPageIndex = Number(siblings[0].realIndex);
                SettingsLayoutManager.updatePageLayoutConfigNoUndo(hubPageIndex, "", { subTabOrder: order });
                if (root.settingsPageIndex >= 0 && root.settingsPageIndex !== hubPageIndex) {
                    SettingsLayoutManager.updatePageLayoutConfigNoUndo(root.settingsPageIndex, "", { subTabOrder: order });
                }
            }
            root.customActiveSubTab = newKey;
            root._updateCardTabs();
            root._scheduleCardTabsUpdate();
        }
        return newKey;
    }

    function deleteActiveSubTab(): bool {
        var items = root._subTabItems || [];
        if (items.length > 1 && root._activeSubTabIndex >= 0 && root._activeSubTabIndex < items.length) {
            var curItem = items[root._activeSubTabIndex];
            if (curItem && curItem.kind === "siblingPage")
                return false;
            var targetPage = (curItem && curItem.pageIndex !== undefined && curItem.pageIndex >= 0)
                ? curItem.pageIndex
                : root.settingsPageIndex;
            var targetKey = String(curItem?.value || root.activeSubTabKey || "");
            if (targetKey.length > 0) {
                var siblings = root.categorySiblingPages || [];
                var removedOrderKey = String(curItem.orderKey || ("p" + targetPage + ":" + targetKey));
                var nextOrder = items
                    .map(function(it) { return String(it.orderKey || ("p" + it.pageIndex + ":" + it.value)); })
                    .filter(function(k) { return k !== removedOrderKey && k !== targetKey; });
                SettingsLayoutManager.deleteSubTab(targetPage, root.customTabId, targetKey, root.baseSubTabSpecs);
                if (siblings.length > 0 && root.customTabId.length === 0) {
                    var hubPageIndex = Number(siblings[0].realIndex);
                    SettingsLayoutManager.updatePageLayoutConfigNoUndo(hubPageIndex, "", { subTabOrder: nextOrder });
                    if (root.settingsPageIndex >= 0 && root.settingsPageIndex !== hubPageIndex) {
                        SettingsLayoutManager.updatePageLayoutConfigNoUndo(root.settingsPageIndex, "", { subTabOrder: nextOrder });
                    }
                }
                root.customActiveSubTab = "";
                root._updateCardTabs();
                root._scheduleCardTabsUpdate();
                return true;
            }
        }
        if (root.effectiveSubTabSpecs.length > 1 && root.activeSubTabKey.length > 0) {
            SettingsLayoutManager.deleteSubTab(root.settingsPageIndex, root.customTabId, root.activeSubTabKey, root.baseSubTabSpecs);
            root.customActiveSubTab = "";
            root._updateCardTabs();
            root._scheduleCardTabsUpdate();
            return true;
        }
        return false;
    }

    readonly property real availableCardContentHeight: {
        const baseH = root.height > 80 ? root.height : 560;
        const tabBarH = subTabBarContainer.visible ? (subTabBarContainer.implicitHeight + contentColumn.spacing) : 0;
        const margins = (root.embedded ? 0 : 24);
        const cardChrome = SettingsMaterialPreset.cardPadding * 2 + 48;
        return Math.max(220, baseH - margins - tabBarH - cardChrome);
    }

    property int _subTabAnimFromIndex: -1
    property real _subTabContentSlideOffset: 0
    property real _subTabContentOpacity: 1.0

    ParallelAnimation {
        id: subTabContentAnim
        NumberAnimation {
            target: root
            property: "_subTabContentOpacity"
            from: 0.35
            to: 1.0
            duration: Appearance.animationsEnabled ? Math.max(120, Appearance.animation.elementMoveFast.duration) : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "_subTabContentSlideOffset"
            to: 0
            duration: Appearance.animationsEnabled ? Math.max(140, Appearance.animation.elementMoveFast.duration) : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    function triggerSubTabContentTransition(direction: int) {
        if (!Appearance.animationsEnabled || root.embedded)
            return;
        subTabContentAnim.stop();
        root._subTabContentOpacity = 0.35;
        root._subTabContentSlideOffset = (direction >= 0 ? 1 : -1) * 18;
        subTabContentAnim.start();
    }

    function animateSubTabFrom(fromIndex: int, direction: int) {
        if (!Appearance.animationsEnabled || root.embedded)
            return;
        if (fromIndex >= 0 && fromIndex !== root._activeSubTabIndex) {
            root._subTabAnimFromIndex = fromIndex;
            Qt.callLater(function() {
                activeSubTabPill.snapFromIndex(fromIndex);
                root._subTabAnimFromIndex = -1;
            });
        }
        triggerSubTabContentTransition(direction);
    }

    function activateSubTabItem(item) {
        if (!item)
            return;
        var items = root._subTabItems || [];
        var curIdx = root._activeSubTabIndex;
        var targetIdx = items.indexOf(item);
        var dir = (targetIdx >= 0 && curIdx >= 0 && targetIdx !== curIdx) ? (targetIdx > curIdx ? 1 : -1) : 1;

        if (item.kind === "customSubTab") {
            if (item.pageIndex >= 0 && item.pageIndex !== root.settingsPageIndex && root.customTabId.length === 0) {
                root.pageSectionNavigationRequested(item.pageIndex, item.value);
                return;
            }
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir);
            root.customActiveSubTab = String(item.value || "");
            if (root.hasOwnProperty("activeSection"))
                root.activeSection = item.value;
            root.contentY = 0;
            root._updateCardTabs();
            root._scheduleCardTabsUpdate();
        } else if (item.kind === "pageSection") {
            root.customActiveSubTab = "";
            if (item.pageIndex === root.settingsPageIndex) {
                if (targetIdx !== curIdx)
                    root.triggerSubTabContentTransition(dir);
                if (root.hasOwnProperty("activeSection"))
                    root.activeSection = item.value;
                if (root.settingsTaskNavigator)
                    root.settingsTaskNavigator.selected(item.value);
                root._savePersistedSection();
                root.contentY = 0;
                root._updateCardTabs();
                root._scheduleCardTabsUpdate();
            } else if (item.pageIndex >= 0) {
                root.pageSectionNavigationRequested(item.pageIndex, item.value);
            }
        } else if (item.kind === "siblingPage") {
            root.customActiveSubTab = "";
            if (item.pageIndex >= 0 && item.pageIndex !== root.settingsPageIndex) {
                root.pageNavigationRequested(item.pageIndex);
            } else {
                if (targetIdx !== curIdx)
                    root.triggerSubTabContentTransition(dir);
                root.contentY = 0;
                root._updateCardTabs();
                root._scheduleCardTabsUpdate();
            }
        } else if (item.kind === "task") {
            root.customActiveSubTab = "";
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir);
            if (root.settingsTaskNavigator) {
                root.settingsTaskNavigator.selected(item.value);
            }
            root._savePersistedSection();
            root.contentY = 0;
            root._updateCardTabs();
            root._scheduleCardTabsUpdate();
        } else if (item.kind === "cardPage") {
            root.customActiveSubTab = "";
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir);
            root.selectCardSubTab(item.value);
            root._savePersistedSection();
            root._updateCardTabs();
            root._scheduleCardTabsUpdate();
        }
    }

    function stepSubTab(direction: int) {
        var items = root._subTabItems || [];
        if (items.length <= 1 || direction === 0)
            return;
        var cur = root._activeSubTabIndex;
        var next = cur + (direction > 0 ? 1 : -1);
        if (next < 0 || next >= items.length)
            return;
        root.activateSubTabItem(items[next]);
    }

    function _handleSubTabWheel(wheelEvent, allowVertical: bool) {
        var items = root._subTabItems || [];
        if (items.length <= 1)
            return;
        var dx = wheelEvent.angleDelta.x;
        var dy = wheelEvent.angleDelta.y;
        // Only switch sub-tabs on horizontal scroll
        if (Math.abs(dx) < 1 || Math.abs(dx) <= Math.abs(dy)) {
            root._wheelDeltaAccum = 0;
            return;
        }
        var now = Date.now();
        if (now - root._lastSubTabWheelMs < 150) {
            wheelEvent.accepted = true;
            return;
        }
        root._wheelDeltaAccum += dx;
        if (Math.abs(root._wheelDeltaAccum) >= 30) {
            var dir = root._wheelDeltaAccum < 0 ? 1 : -1;
            root._wheelDeltaAccum = 0;
            root._lastSubTabWheelMs = now;
            root.stepSubTab(dir);
            wheelEvent.accepted = true;
        }
    }

    function syncTaskNavigatorSelection(val) {
        root.activeCardSubTab = "";
        root.contentY = 0;
        root._scheduleCardTabsUpdate();
    }

    function selectTaskOptionFromDrillDown(val) {
        if (!root.settingsTaskNavigator)
            return;
        root.settingsTaskNavigator.selected(val);
        root.syncTaskNavigatorSelection(val);
    }

    function selectCardSubTabFromDrillDown(key, title, icon) {
        if (!key)
            return;
        root.activeCardSubTab = key;
        root.contentY = 0;
        root._updateCardTabs();
    }

    function exitSubView() {
        root.isSubViewActive = false;
        root.activeSubViewTitle = "";
        root.activeSubViewIcon = "";
        root.activeCardSubTab = "";
        root.contentY = 0;
        root._updateCardTabs();
    }

    function registerCardSection(card) {
        if (root._isDestroying || !card || _registeredCards.indexOf(card) >= 0)
            return;
        var next = _registeredCards.slice();
        next.push(card);
        _registeredCards = next;
        _scheduleCardTabsUpdate();
    }

    function unregisterCardSection(card) {
        if (root._isDestroying)
            return;
        var idx = _registeredCards.indexOf(card);
        if (idx < 0)
            return;
        var next = _registeredCards.slice();
        next.splice(idx, 1);
        _registeredCards = next;
        _scheduleCardTabsUpdate();
    }

    function notifyCardEligibilityChanged() {
        if (root._isDestroying)
            return;
        _scheduleCardTabsUpdate();
    }

    Timer {
        id: cardTabsUpdateTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root._isDestroying)
                return;
            root._cardTabsUpdateScheduled = false;
            root._updateCardTabs();
        }
    }

    Timer {
        id: bentoSyncTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root._isDestroying)
                return;
            root._syncBentoColumnHeights(root._activeLeftBentoCards, root._activeRightBentoCards);
            root._syncPageBodyWrappers();
        }
    }

    function _scheduleBentoHeightSync() {
        if (root._isDestroying || root.embedded)
            return;
        bentoSyncTimer.restart();
    }

    function _returnForeignCardToOrigin(fc) {
        if (!fc)
            return;
        fc._isForeignHosted = false;
        fc._currentHostPage = fc._topPage;
        fc._bentoExtraHeight = 0;
        if (fc._initialParent && (fc.parent === topBentoColumn || fc.parent === leftBentoColumn || fc.parent === rightBentoColumn || fc.parent === hiddenCardsPark || fc.parent === freeformCanvasContainer)) {
            fc.parent = fc._initialParent;
        }
        if (fc._topPage && !fc._topPage._isDestroying && typeof fc._topPage._scheduleCardTabsUpdate === "function") {
            fc._topPage._scheduleCardTabsUpdate();
        }
    }

    function _returnAllForeignCardsToOrigin() {
        var list = root._activeForeignCards || [];
        root._activeForeignCards = [];
        for (var i = 0; i < list.length; i++) {
            root._returnForeignCardToOrigin(list[i]);
        }
    }

    Component.onDestruction: {
        root._isDestroying = true;
        cardTabsUpdateTimer.stop();
        bentoSyncTimer.stop();
        SettingsLayoutManager.unregisterDropTarget("col-top:" + root.settingsPageIndex + ":" + root.customTabId, topBentoColumn);
        SettingsLayoutManager.unregisterDropTarget("col-left:" + root.settingsPageIndex + ":" + root.customTabId, leftBentoColumn);
        SettingsLayoutManager.unregisterDropTarget("col-right:" + root.settingsPageIndex + ":" + root.customTabId, rightBentoColumn);
        SettingsLayoutManager.unregisterDropTarget("canvas:" + root.settingsPageIndex + ":" + root.customTabId, freeformCanvasContainer);
        root._returnAllForeignCardsToOrigin();
    }

    function _scheduleCardTabsUpdate() {
        if (root._isDestroying || root.embedded || _cardTabsUpdateScheduled)
            return;
        _cardTabsUpdateScheduled = true;
        cardTabsUpdateTimer.restart();
    }

    function selectCardSubTab(key) {
        if (!key || activeCardSubTab === key)
            return;
        activeCardSubTab = key;
        root.contentY = 0;
        _updateCardTabs();
    }

    function selectCardSection(card) {
        if (!card)
            return;
        if (card.settingsTaskSection && root._hasTaskNavigatorTabs) {
            root.selectTaskOptionFromDrillDown(card.settingsTaskSection);
        }
        if (card._cardSubTabKey) {
            activeCardSubTab = card._cardSubTabKey;
            if (root._cardPageOptions.length > 1 && card._cardSubTabKey !== root._cardPageOptions[0].value) {
                for (var i = 1; i < root._cardPageOptions.length; i++) {
                    if (root._cardPageOptions[i].value === card._cardSubTabKey) {
                        root.selectCardSubTabFromDrillDown(
                            card._cardSubTabKey,
                            root._cardPageOptions[i].displayName,
                            root._cardPageOptions[i].icon);
                        break;
                    }
                }
            }
        }
        root.contentY = 0;
        _updateCardTabs();
    }

    function _hasIntermediateLoader(c) {
        if (!c)
            return true;
        var p = c._initialParent ? c._initialParent : c.parent;
        var originRoot = c._topPage ? c._topPage : root;
        while (p
                && p !== root && p !== originRoot
                && p !== pageBodyColumn && p !== originRoot.pageBodyColumn
                && p !== topBentoColumn && p !== leftBentoColumn && p !== rightBentoColumn
                && p !== hiddenCardsPark && p !== freeformCanvasContainer) {
            if (p.hasOwnProperty("sourceComponent") && p.hasOwnProperty("status")) {
                return true;
            }
            p = p.parent;
        }
        return false;
    }

    function _canReparentToBento(c) {
        if (!c || c._preventBentoReparent || !(c.showHeader || c.allowEditWithoutHeader) || !c.title || c.title.length === 0)
            return false;
        return !_hasIntermediateLoader(c);
    }

    function _cardHeight(c) {
        if (!c)
            return 0;
        var h = c.naturalCardImplicitHeight !== undefined
            ? c.naturalCardImplicitHeight
            : (c.cardImplicitHeight !== undefined ? c.cardImplicitHeight : c.implicitHeight);
        return Math.max(96, (h && h > 40) ? h : 180);
    }

    function _buildPageTitle(pageCards, idx) {
        if (!pageCards || pageCards.length === 0)
            return Translation.tr("Section") + " " + (idx + 1);
        var t0 = String(pageCards[0].title || "").trim();
        if (pageCards.length === 1)
            return t0;
        var t1 = String(pageCards[1].title || "").replace(/\s*\([^)]*\)\s*/g, "").trim();
        if (t1.length > 0 && t1 !== t0 && (t0.length + t1.length <= 32)) {
            return t0 + " & " + t1;
        }
        return t0;
    }

    function _buildPageSubtitle(pageCards) {
        if (!pageCards || pageCards.length <= 1)
            return "";
        var names = [];
        for (var i = 0; i < pageCards.length; i++) {
            var t = String(pageCards[i].title || "").trim();
            if (t.length > 0 && names.indexOf(t) < 0)
                names.push(t);
        }
        return names.join(" · ");
    }

    function _ensureDeclarationOrder() {
        var nextOrder = 0;
        for (var k = 0; k < _registeredCards.length; k++) {
            if (_registeredCards[k] && _registeredCards[k]._declarationOrder >= nextOrder) {
                nextOrder = _registeredCards[k]._declarationOrder + 1;
            }
        }
        function walk(node) {
            if (!node || node === hiddenCardsPark || node === topBentoColumn || node === leftBentoColumn || node === rightBentoColumn || node === freeformCanvasContainer)
                return;
            if (node.hasOwnProperty("_declarationOrder") && node._declarationOrder < 0) {
                node._declarationOrder = nextOrder++;
            }
            var ch = node.children || [];
            for (var i = 0; i < ch.length; i++) {
                walk(ch[i]);
            }
        }
        walk(pageBodyColumn);
        for (var m = 0; m < _registeredCards.length; m++) {
            if (_registeredCards[m] && _registeredCards[m]._declarationOrder < 0) {
                _registeredCards[m]._declarationOrder = nextOrder++;
            }
        }
        _registeredCards.sort(function(a, b) {
            var oa = (a && a._declarationOrder >= 0) ? a._declarationOrder : 999999;
            var ob = (b && b._declarationOrder >= 0) ? b._declarationOrder : 999999;
            return oa - ob;
        });
    }

    property var _activeTopBentoCards: []
    property var _activeLeftBentoCards: []
    property var _activeRightBentoCards: []

    function _syncBentoColumnHeights(leftCards, rightCards) {
        var allCards = _registeredCards.concat(root._activeForeignCards || []);
        var targetCard = null;
        var targetExtra = 0;

        var canStretch = !root.isCanvasLayoutMode
            && leftCards && rightCards
            && leftCards.length > 0 && rightCards.length > 0;

        if (canStretch) {
            for (var ci = 0; ci < leftCards.length; ci++) {
                var lc = leftCards[ci];
                var lCustomH = lc ? (lc._effectiveCustomHeight !== undefined ? lc._effectiveCustomHeight : lc.customHeight) : 0;
                var lCustomW = lc ? (lc._effectiveWidthRatio !== undefined ? lc._effectiveWidthRatio : lc.customWidthRatio) : 0;
                if (lc && (lCustomH > 0 || lCustomW > 0 || lc._preventBentoReparent)) {
                    canStretch = false;
                    break;
                }
            }
        }
        if (canStretch) {
            for (var cj = 0; cj < rightCards.length; cj++) {
                var rc = rightCards[cj];
                var rCustomH = rc ? (rc._effectiveCustomHeight !== undefined ? rc._effectiveCustomHeight : rc.customHeight) : 0;
                var rCustomW = rc ? (rc._effectiveWidthRatio !== undefined ? rc._effectiveWidthRatio : rc.customWidthRatio) : 0;
                if (rc && (rCustomH > 0 || rCustomW > 0 || rc._preventBentoReparent)) {
                    canStretch = false;
                    break;
                }
            }
        }

        if (canStretch) {
            var gap = SettingsMaterialPreset.pageSpacing;
            var leftNaturalH = 0;
            for (var a = 0; a < leftCards.length; a++) {
                leftNaturalH += _cardHeight(leftCards[a]) + (a < leftCards.length - 1 ? gap : 0);
            }
            var rightNaturalH = 0;
            for (var b = 0; b < rightCards.length; b++) {
                rightNaturalH += _cardHeight(rightCards[b]) + (b < rightCards.length - 1 ? gap : 0);
            }
            var diff = Math.round(Math.abs(leftNaturalH - rightNaturalH));
            if (diff > 1) {
                var shorterList = leftNaturalH < rightNaturalH ? leftCards : rightCards;
                for (var si = 0; si < shorterList.length; si++) {
                    if (shorterList[si] && shorterList[si]._consumesBentoExtraHeight && !shorterList[si]._preventBentoReparent && shorterList[si]._bentoExtraHeight !== undefined) {
                        targetCard = shorterList[si];
                        targetExtra = diff;
                        break;
                    }
                }
                if (!targetCard && shorterList.length > 0) {
                    var lastShort = shorterList[shorterList.length - 1];
                    if (lastShort && !lastShort._preventBentoReparent && lastShort._bentoExtraHeight !== undefined) {
                        targetCard = lastShort;
                        targetExtra = diff;
                    }
                }
            }
        }

        for (var n = 0; n < allCards.length; n++) {
            var cardItem = allCards[n];
            if (!cardItem || cardItem._bentoExtraHeight === undefined)
                continue;
            var desired = (cardItem === targetCard) ? targetExtra : 0;
            if (Math.abs(cardItem._bentoExtraHeight - desired) > 1) {
                cardItem._bentoExtraHeight = desired;
            }
        }
    }

    function _reparentColumnOrdered(columnItem, cardsList, reparentedOutList, bodyDirectOutList) {
        var reparentable = [];
        var peerIds = cardsList.map(function(item) { return item ? item.moduleId : ""; }).filter(Boolean);
        var peerKey = peerIds.join("|");
        for (var idx = 0; idx < cardsList.length; idx++) {
            var c = cardsList[idx];
            if (!Array.isArray(c._peerModuleIds) || c._peerModuleIds.join("|") !== peerKey) {
                c._peerModuleIds = peerIds;
            }
            if (_canReparentToBento(c)) {
                reparentable.push(c);
            } else if (c.parent === pageBodyColumn) {
                c.Layout.fillHeight = false;
                bodyDirectOutList.push(c);
            }
            c._cardSubTabActive = true;
            c._hasNextActiveCard = false;
            if (!c.expanded) c.expanded = true;
        }

        // Check if columnItem.children already matches reparentable in exact order
        var colChildren = columnItem.children || [];
        var currentInCol = [];
        for (var ci = 0; ci < colChildren.length; ci++) {
            if (reparentable.indexOf(colChildren[ci]) >= 0) {
                currentInCol.push(colChildren[ci]);
            }
        }
        var needsReorder = (currentInCol.length !== reparentable.length);
        if (!needsReorder) {
            for (var k = 0; k < reparentable.length; k++) {
                if (currentInCol[k] !== reparentable[k]) {
                    needsReorder = true;
                    break;
                }
            }
        }
        if (needsReorder) {
            for (var p = 0; p < reparentable.length; p++) {
                if (reparentable[p].parent === columnItem) {
                    reparentable[p].parent = hiddenCardsPark;
                }
            }
        }
        for (var r = 0; r < reparentable.length; r++) {
            var rc = reparentable[r];
            rc.Layout.fillHeight = false;
            if (columnItem === topBentoColumn && contentColumn.width > 0) {
                rc.width = contentColumn.width;
            } else if ((columnItem === leftBentoColumn || columnItem === rightBentoColumn) && columnItem.width > 0) {
                rc.width = columnItem.width;
            }
            rc.parent = columnItem;
            reparentedOutList.push(rc);
        }
        return reparentable.length;
    }

    function _applyCanvasPlacement(cardsList) {
        var activeCards = cardsList || [];
        var availW = Math.max(520, contentColumn.width > 100 ? contentColumn.width : 920);
        var colW = Math.max(240, Math.floor((availW - 24) / 2));
        var curLeftY = 12;
        var curRightY = 12;
        var canvasCount = 0;

        for (var i = 0; i < activeCards.length; i++) {
            var c = activeCards[i];
            if (!c || !_canReparentToBento(c))
                continue;
            c._cardSubTabActive = true;
            c._hasNextActiveCard = false;
            c._bentoExtraHeight = 0;
            if (!c.expanded) c.expanded = true;
            c.parent = freeformCanvasContainer;

            var cfg = c.moduleConfig;
            var cw = (cfg && cfg.canvasW > 0) ? cfg.canvasW : colW;
            var ch = (cfg && cfg.canvasH > 0) ? cfg.canvasH : _cardHeight(c);
            var cx = (cfg && cfg.canvasX >= 0) ? cfg.canvasX : ((i % 2 === 0) ? 8 : (colW + 20));
            var cy = (cfg && cfg.canvasY >= 0) ? cfg.canvasY : ((i % 2 === 0) ? curLeftY : curRightY);

            c.x = cx;
            c.y = cy;
            c.width = Math.min(availW - 16, cw);
            c.height = ch;

            if (i % 2 === 0)
                curLeftY = Math.max(curLeftY, cy + ch + 16);
            else
                curRightY = Math.max(curRightY, cy + ch + 16);
            canvasCount++;
        }

        for (var m = 0; m < _registeredCards.length; m++) {
            var cardItem = _registeredCards[m];
            if (!cardItem || !(cardItem.showHeader || cardItem.allowEditWithoutHeader) || !cardItem.title)
                continue;
            if (activeCards.indexOf(cardItem) < 0 && !cardItem._isForeignHosted) {
                cardItem._cardSubTabActive = false;
                cardItem._hasNextActiveCard = false;
                if (_canReparentToBento(cardItem))
                    cardItem.parent = hiddenCardsPark;
            }
        }

        root._activeTopBentoCards = [];
        root._activeLeftBentoCards = [];
        root._activeRightBentoCards = [];
        root._topBentoCount = 0;
        root._leftBentoCount = 0;
        root._rightBentoCount = 0;
        root._activeCanvasCount = canvasCount;
    }

    function _applyBentoPlacement(chosenPage) {
        root._activeCanvasCount = 0;
        var topCards = chosenPage ? (chosenPage.top || []) : [];
        var leftCards = chosenPage ? (chosenPage.left || []) : [];
        var rightCards = chosenPage ? (chosenPage.right || []) : [];
        var activeCards = chosenPage ? (chosenPage.cards || []) : [];

        var reparentedTopList = [];
        var reparentedLeftList = [];
        var reparentedRightList = [];
        var bodyDirectCards = [];

        var topReparented = _reparentColumnOrdered(topBentoColumn, topCards, reparentedTopList, bodyDirectCards);
        var leftReparented = _reparentColumnOrdered(leftBentoColumn, leftCards, reparentedLeftList, bodyDirectCards);
        var rightReparented = _reparentColumnOrdered(rightBentoColumn, rightCards, reparentedRightList, bodyDirectCards);

        for (var ti = 0; ti < reparentedTopList.length; ti++) {
            reparentedTopList[ti]._hasNextActiveCard = (ti < reparentedTopList.length - 1);
        }
        for (var li = 0; li < reparentedLeftList.length; li++) {
            reparentedLeftList[li]._hasNextActiveCard = (li < reparentedLeftList.length - 1);
        }
        for (var ri = 0; ri < reparentedRightList.length; ri++) {
            reparentedRightList[ri]._hasNextActiveCard = (ri < reparentedRightList.length - 1);
        }
        for (var bi = 0; bi < bodyDirectCards.length; bi++) {
            var bc = bodyDirectCards[bi];
            bc._hasNextActiveCard = (activeCards.indexOf(bc) < activeCards.length - 1);
        }

        for (var m = 0; m < _registeredCards.length; m++) {
            var cardItem = _registeredCards[m];
            if (!cardItem)
                continue;
            if (!(cardItem.showHeader || cardItem.allowEditWithoutHeader) || !cardItem.title || cardItem.title.length === 0) {
                cardItem._cardSubTabActive = true;
                cardItem._hasNextActiveCard = false;
                continue;
            }
            if (activeCards.indexOf(cardItem) < 0 && !cardItem._isForeignHosted) {
                cardItem._cardSubTabActive = false;
                cardItem._hasNextActiveCard = false;
                if (_canReparentToBento(cardItem)) {
                    cardItem.parent = hiddenCardsPark;
                }
            }
        }

        root._activeTopBentoCards = reparentedTopList;
        root._activeLeftBentoCards = reparentedLeftList;
        root._activeRightBentoCards = reparentedRightList;
        _syncBentoColumnHeights(reparentedLeftList, reparentedRightList);
        bentoSyncTimer.restart();

        root._topBentoCount = topReparented;
        root._leftBentoCount = leftReparented;
        root._rightBentoCount = rightReparented;
        _syncPageBodyWrappers();
    }

    function _isWrapperContainer(item) {
        if (!item)
            return false;
        if (item.hasOwnProperty("_preventBentoReparent") && item.hasOwnProperty("_cardSubTabActive"))
            return false;
        if (item.hasOwnProperty("sourceComponent") && item.hasOwnProperty("status"))
            return false;
        for (var i = 0; i < _registeredCards.length; i++) {
            var c = _registeredCards[i];
            var p = c ? c._initialParent : null;
            while (p && p !== pageBodyColumn && p !== root) {
                if (p === item)
                    return true;
                p = p.parent;
            }
        }
        var cls = String(item);
        return cls.indexOf("GridLayout") >= 0 || cls.indexOf("ColumnLayout") >= 0;
    }

    function _wrapperHasActiveVisibleChild(item) {
        if (!item || !item.visible)
            return false;
        var ch = item.children || [];
        for (var i = 0; i < ch.length; i++) {
            var sub = ch[i];
            if (!sub || !sub.visible || sub === hiddenCardsPark)
                continue;
            if (sub.hasOwnProperty("showTabBar") && sub.hasOwnProperty("options"))
                continue;
            if (sub.hasOwnProperty("_cardSubTabActive") && !sub._cardSubTabActive)
                continue;
            if (typeof sub.itemAt === "function" && sub.hasOwnProperty("delegate"))
                continue;
            if (sub.hasOwnProperty("sourceComponent") && sub.hasOwnProperty("status")) {
                if (sub.active)
                    return true;
                continue;
            }
            if (_isWrapperContainer(sub)) {
                if (_wrapperHasActiveVisibleChild(sub))
                    return true;
                continue;
            }
            if (sub.implicitHeight > 0 || sub.height > 0)
                return true;
        }
        return false;
    }

    function _syncWrapperItem(item) {
        if (!item || !_isWrapperContainer(item))
            return;
        var ch = item.children || [];
        for (var i = 0; i < ch.length; i++) {
            if (ch[i] && _isWrapperContainer(ch[i]))
                _syncWrapperItem(ch[i]);
        }
        if (!root.embedded && !_wrapperHasActiveVisibleChild(item)) {
            item.Layout.preferredHeight = 0;
            item.Layout.maximumHeight = 0;
        } else {
            item.Layout.preferredHeight = -1;
            item.Layout.maximumHeight = 16777215;
        }
    }

    function _isActivePageBodyBlock(bItem) {
        if (!bItem || !bItem.visible || bItem === hiddenCardsPark)
            return false;
        if (typeof bItem.itemAt === "function" && bItem.hasOwnProperty("delegate"))
            return false;
        if (bItem.hasOwnProperty("showTabBar") && bItem.hasOwnProperty("options"))
            return bItem.implicitHeight > 0;
        if (bItem.hasOwnProperty("_cardSubTabActive"))
            return Boolean(bItem._cardSubTabActive) && (bItem.implicitHeight > 0 || bItem.height > 0);
        if (bItem.hasOwnProperty("sourceComponent") && bItem.hasOwnProperty("status"))
            return Boolean(bItem.active) && ((bItem.item && bItem.item.implicitHeight > 0) || bItem.implicitHeight > 0 || bItem.height > 0);
        if (_isWrapperContainer(bItem))
            return _wrapperHasActiveVisibleChild(bItem);
        return bItem.implicitHeight > 0 || bItem.height > 0;
    }

    function _syncPageBodyWrappers() {
        var ch = pageBodyColumn.children || [];
        for (var i = 0; i < ch.length; i++) {
            var item = ch[i];
            if (!item || !_isWrapperContainer(item))
                continue;
            _syncWrapperItem(item);
        }
        var activeBlocks = [];
        for (var j = 0; j < ch.length; j++) {
            if (_isActivePageBodyBlock(ch[j]))
                activeBlocks.push(ch[j]);
        }
        var gap = SettingsMaterialPreset.pageSpacing;
        for (var k = 0; k < ch.length; k++) {
            var blk = ch[k];
            if (!blk)
                continue;
            var aIdx = activeBlocks.indexOf(blk);
            var hasNext = (aIdx >= 0 && aIdx < activeBlocks.length - 1);
            var nextTopMargin = (hasNext && activeBlocks[aIdx + 1] && activeBlocks[aIdx + 1].Layout)
                ? (Number(activeBlocks[aIdx + 1].Layout.topMargin) || 0)
                : 0;
            if (blk.hasOwnProperty("_hasNextActiveCard")) {
                blk._hasNextActiveCard = hasNext && (nextTopMargin < gap);
            } else if (blk.Layout !== undefined) {
                var desiredBottom = hasNext ? Math.max(0, gap - Math.max(0, nextTopMargin)) : 0;
                if (Math.abs((Number(blk.Layout.bottomMargin) || 0) - desiredBottom) > 0.5)
                    blk.Layout.bottomMargin = desiredBottom;
            }
        }
    }

    function _updateCardTabs() {
        if (root.embedded || root._isDestroying)
            return;

        var currentSpecs = SettingsLayoutManager.getEffectiveSubTabs(
            root.settingsPageIndex,
            root.customTabId,
            root.baseSubTabSpecs
        ) || [];
        if (root.customActiveSubTab.length > 0) {
            var stillExists = false;
            for (var si = 0; si < currentSpecs.length; si++) {
                if (currentSpecs[si] && currentSpecs[si].key === root.customActiveSubTab && currentSpecs[si].custom) {
                    stillExists = true;
                    break;
                }
            }
            if (!stillExists) {
                root.customActiveSubTab = "";
            }
        }
        if (root.customActiveSubTab.length === 0
                && currentSpecs.length > 0
                && root._hasTaskNavigatorTabs
                && root.settingsTaskNavigator
                && root.settingsTaskNavigator.currentValue !== undefined) {
            var curTask = String(root.settingsTaskNavigator.currentValue || "");
            if (curTask.length > 0 && !currentSpecs.some(function(s) { return s && s.key === curTask; })) {
                var fallbackSpec = currentSpecs[0];
                if (fallbackSpec && fallbackSpec.key) {
                    if (fallbackSpec.custom) {
                        root.customActiveSubTab = String(fallbackSpec.key);
                    } else {
                        if (root.hasOwnProperty("activeSection"))
                            root.activeSection = String(fallbackSpec.key);
                        if (typeof root.settingsTaskNavigator.selected === "function")
                            root.settingsTaskNavigator.selected(String(fallbackSpec.key));
                    }
                }
            }
        }

        var aliveCards = [];
        for (var r = 0; r < _registeredCards.length; r++) {
            var rcItem = _registeredCards[r];
            if (rcItem && rcItem.parent)
                aliveCards.push(rcItem);
        }
        if (aliveCards.length !== _registeredCards.length)
            _registeredCards = aliveCards;

        _ensureDeclarationOrder();

        // Sync foreign cards targeting this page / custom tab / sub-tab
        var foreignCards = SettingsLayoutManager.getForeignCardsForTarget(
            root.settingsPageIndex,
            root.customTabId,
            root.activeSubTabKey,
            root._hasEffectiveSubTabs
        ) || [];

        var prevForeign = root._activeForeignCards || [];
        for (var pf = 0; pf < prevForeign.length; pf++) {
            var oldFc = prevForeign[pf];
            if (oldFc && foreignCards.indexOf(oldFc) < 0) {
                root._returnForeignCardToOrigin(oldFc);
            }
        }
        root._activeForeignCards = foreignCards;

        var eligible = [];
        var usedKeys = {};
        for (var i = 0; i < _registeredCards.length; i++) {
            var c = _registeredCards[i];
            if (!c)
                continue;
            if (!(c.showHeader || c.allowEditWithoutHeader) || !c.title || c.title.length === 0) {
                c._isForeignHosted = false;
                c._currentHostPage = root;
                c._cardSubTabActive = true;
                c._hasNextActiveCard = false;
                continue;
            }
            if (c.moduleId
                    && SettingsLayoutManager.isModuleMovedAway(c.moduleId, root.settingsPageIndex, root.customTabId, "", false)
                    && c._isForeignHosted
                    && c._currentHostPage
                    && c._currentHostPage !== root
                    && !c._currentHostPage._isDestroying) {
                continue;
            }
            c._isForeignHosted = false;
            c._currentHostPage = root;
            if (c.isCardEligibleForTabs()) {
                // If the user explicitly moved this module to a specific sub-tab on the same page, filter by that sub-tab
                var mCfg = c.moduleConfig;
                if (root._hasEffectiveSubTabs && mCfg && mCfg.targetSubTab && root.activeSubTabKey && mCfg.targetSubTab !== root.activeSubTabKey) {
                    continue;
                }
                var baseKey = String(c.title || ("card_" + i));
                var key = baseKey;
                if (usedKeys[key]) {
                    usedKeys[key]++;
                    key = baseKey + "##" + usedKeys[key];
                } else {
                    usedKeys[key] = 1;
                }
                c._cardSubTabKey = key;
                eligible.push(c);
            }
        }

        for (var fi = 0; fi < foreignCards.length; fi++) {
            var fc = foreignCards[fi];
            if (!fc || eligible.indexOf(fc) >= 0)
                continue;
            fc._isForeignHosted = true;
            fc._currentHostPage = root;
            eligible.push(fc);
        }

        // Sort eligible cards by user-saved module order when present, otherwise declaration order
        eligible.sort(function(a, b) {
            var oa = (a && a.moduleConfig && a.moduleConfig.order > 0) ? a.moduleConfig.order : (10000 + (a ? a._declarationOrder : 0));
            var ob = (b && b.moduleConfig && b.moduleConfig.order > 0) ? b.moduleConfig.order : (10000 + (b ? b._declarationOrder : 0));
            return oa - ob;
        });

        _eligibleCards = eligible;

        // Register column & canvas drop targets for this page
        SettingsLayoutManager.registerDropTarget("col-top:" + root.settingsPageIndex + ":" + root.customTabId, topBentoColumn, {
            kind: "column",
            column: "full",
            pageIndex: root.settingsPageIndex,
            customTabId: root.customTabId,
            subTabKey: root.activeSubTabKey,
            label: Translation.tr("Full Width Top")
        });
        SettingsLayoutManager.registerDropTarget("col-left:" + root.settingsPageIndex + ":" + root.customTabId, leftBentoColumn, {
            kind: "column",
            column: "left",
            pageIndex: root.settingsPageIndex,
            customTabId: root.customTabId,
            subTabKey: root.activeSubTabKey,
            label: Translation.tr("Left Column")
        });
        SettingsLayoutManager.registerDropTarget("col-right:" + root.settingsPageIndex + ":" + root.customTabId, rightBentoColumn, {
            kind: "column",
            column: "right",
            pageIndex: root.settingsPageIndex,
            customTabId: root.customTabId,
            subTabKey: root.activeSubTabKey,
            label: Translation.tr("Right Column")
        });
        SettingsLayoutManager.registerDropTarget("canvas:" + root.settingsPageIndex + ":" + root.customTabId, freeformCanvasContainer, {
            kind: "canvas",
            pageIndex: root.settingsPageIndex,
            customTabId: root.customTabId,
            subTabKey: root.activeSubTabKey,
            label: Translation.tr("Freeform Canvas")
        });

        if (eligible.length === 0) {
            _cardPages = [];
            _cardPageOptions = [];
            activeCardItem = null;
            _applyBentoPlacement(null);
            return;
        }

        if (root.isCanvasLayoutMode) {
            _cardPages = [eligible];
            _cardPageOptions = [];
            activeCardItem = eligible[0];
            _applyCanvasPlacement(eligible);
            return;
        }

        var firstPageCap = 999999;
        var detailPageCap = 999999;
        var gap = SettingsMaterialPreset.pageSpacing;
        var twoCols = (root.width <= 0 || root.width >= 560);

        // Pack eligible cards into 2-column Bento pages
        var pages = [];
        var curPage = { cards: [], top: [], left: [], right: [], leftH: 0, rightH: 0 };

        for (var idx = 0; idx < eligible.length; idx++) {
            var card = eligible[idx];
            var ch = _cardHeight(card);
            var cap = pages.length === 0 ? firstPageCap : detailPageCap;
            var effectiveCol = (card.customColumn && card.customColumn !== "auto")
                ? card.customColumn
                : card.bentoColumn;

            if (effectiveCol === "full" || effectiveCol === "top") {
                curPage.top.push(card);
                curPage.cards.push(card);
            } else if (twoCols && effectiveCol === "left") {
                curPage.left.push(card);
                curPage.leftH += (curPage.left.length > 1 ? gap : 0) + ch;
                curPage.cards.push(card);
            } else if (twoCols && effectiveCol === "right") {
                curPage.right.push(card);
                curPage.rightH += (curPage.right.length > 1 ? gap : 0) + ch;
                curPage.cards.push(card);
            } else if (curPage.left.length === 0) {
                curPage.left.push(card);
                curPage.leftH = ch;
                curPage.cards.push(card);
            } else if (twoCols && curPage.right.length === 0) {
                curPage.right.push(card);
                curPage.rightH = ch;
                curPage.cards.push(card);
            } else if (!twoCols) {
                if (curPage.leftH + gap + ch <= cap) {
                    curPage.left.push(card);
                    curPage.leftH += gap + ch;
                    curPage.cards.push(card);
                } else {
                    pages.push(curPage);
                    curPage = { cards: [card], top: [], left: [card], right: [], leftH: ch, rightH: 0 };
                }
            } else {
                // Deterministic alternating placement so cards never swap columns when heights change
                var preferLeft = (curPage.left.length <= curPage.right.length);
                if (preferLeft && (curPage.leftH + gap + ch <= cap)) {
                    curPage.left.push(card);
                    curPage.leftH += gap + ch;
                    curPage.cards.push(card);
                } else if (!preferLeft && (curPage.rightH + gap + ch <= cap)) {
                    curPage.right.push(card);
                    curPage.rightH += gap + ch;
                    curPage.cards.push(card);
                } else if (curPage.leftH + gap + ch <= cap) {
                    curPage.left.push(card);
                    curPage.leftH += gap + ch;
                    curPage.cards.push(card);
                } else if (curPage.rightH + gap + ch <= cap) {
                    curPage.right.push(card);
                    curPage.rightH += gap + ch;
                    curPage.cards.push(card);
                } else {
                    pages.push(curPage);
                    curPage = { cards: [card], top: [], left: [card], right: [], leftH: ch, rightH: 0 };
                }
            }
        }
        if (curPage.cards.length > 0) {
            pages.push(curPage);
        }

        if (pages.length <= 1) {
            _cardPages = pages.length === 1 ? [pages[0].cards] : [];
            _cardPageOptions = [];
            activeCardItem = eligible[0];
            activeCardSubTab = activeCardItem ? activeCardItem._cardSubTabKey : "";
            _applyBentoPlacement(pages[0] || null);
            return;
        }

        var opts = [];
        var seenLabels = {};
        for (var q = 0; q < pages.length; q++) {
            var pCards = pages[q].cards;
            var pageKey = pCards[0]._cardSubTabKey || ("page_" + q);
            for (var cIdx = 0; cIdx < pCards.length; cIdx++) {
                pCards[cIdx]._cardSubTabKey = pageKey;
            }
            var rawTitle = _buildPageTitle(pCards, q);
            var label = rawTitle;
            if (seenLabels[label]) {
                seenLabels[label]++;
                label = rawTitle + " " + seenLabels[label];
            } else {
                seenLabels[label] = 1;
            }
            opts.push({
                displayName: label,
                description: _buildPageSubtitle(pCards),
                icon: (pCards[0].icon && pCards[0].icon.length > 0) ? pCards[0].icon : "tune",
                value: pageKey
            });
        }

        _cardPages = pages.map(p => p.cards);
        _cardPageOptions = opts;

        var chosenPageIdx = 0;
        for (var k = 0; k < opts.length; k++) {
            if (opts[k].value === activeCardSubTab) {
                chosenPageIdx = k;
                break;
            }
        }
        activeCardSubTab = opts[chosenPageIdx].value;
        var chosenPage = pages[chosenPageIdx];
        activeCardItem = chosenPage.cards.length > 0 ? chosenPage.cards[0] : null;
        _applyBentoPlacement(chosenPage);
    }

    onEmbeddedChanged: {
        if (embedded) {
            cardTabsUpdateTimer.stop();
            bentoSyncTimer.stop();
            _cardTabsUpdateScheduled = false;
            _topBentoCount = 0;
            _leftBentoCount = 0;
            _rightBentoCount = 0;
            _activeCanvasCount = 0;
            root._returnAllForeignCardsToOrigin();
            for (var i = 0; i < _registeredCards.length; i++) {
                var c = _registeredCards[i];
                if (c) {
                    if (c._initialParent && (c.parent === topBentoColumn || c.parent === leftBentoColumn || c.parent === rightBentoColumn || c.parent === hiddenCardsPark || c.parent === freeformCanvasContainer)) {
                        c.parent = c._initialParent;
                    }
                    c._bentoExtraHeight = 0;
                    c._cardSubTabActive = true;
                    c._hasNextActiveCard = false;
                }
            }
            _syncPageBodyWrappers();
        } else {
            _updateCardTabs();
            _scheduleCardTabsUpdate();
        }
    }

    onVisibleChanged: {
        if (visible && !embedded) {
            _updateCardTabs();
            _scheduleCardTabsUpdate();
        }
    }

    property bool _lastTwoColsState: (width <= 0 || width >= 560)

    onHeightChanged: {
        root._clampScrollPosition();
    }

    onWidthChanged: {
        var nextTwoCols = (width <= 0 || width >= 560);
        if (nextTwoCols !== root._lastTwoColsState) {
            root._lastTwoColsState = nextTwoCols;
            if (visible && !embedded && width > 300) {
                _scheduleCardTabsUpdate();
            }
        } else if (visible && !embedded && root.isCanvasLayoutMode && width > 300) {
            _scheduleCardTabsUpdate();
        }
    }

    on_HasTaskNavigatorTabsChanged: {
        if (!embedded) {
            _scheduleCardTabsUpdate();
        }
    }

    onCategorySiblingPagesChanged: {
        if (!embedded) {
            _scheduleCardTabsUpdate();
        }
    }

    on_ActiveSubTabIndexChanged: {
        Qt.callLater(() => {
            if (!root._isDestroying && subTabFlickable && typeof subTabFlickable.ensureActiveVisible === "function")
                subTabFlickable.ensureActiveVisible();
        });
    }

    clip: !embedded
    showVerticalScrollBar: false
    readonly property real standardPageBodyHeight: Math.max(400, SettingsMaterialPreset.standardBentoHeight)
    readonly property real pageContentBodyHeight: {
        if (root._isDestroying || !contentColumn)
            return 0;
        if (root.embedded)
            return Number(contentColumn.implicitHeight) || 0;
        var total = 0;
        var sections = 0;
        var gap = Number(contentColumn.spacing) || 0;
        if (freeformCanvasContainer && freeformCanvasContainer.visible && freeformCanvasContainer.implicitHeight > 0) {
            total += freeformCanvasContainer.implicitHeight;
            sections++;
        }
        if (topBentoColumn && topBentoColumn.visible) {
            var topH = topBentoColumn.activeCardsImplicitHeight > 0
                ? topBentoColumn.activeCardsImplicitHeight
                : topBentoColumn.implicitHeight;
            if (topH > 0) {
                total += (sections > 0 ? gap : 0) + topH;
                sections++;
            }
        }
        if (bentoColumnsRow && bentoColumnsRow.visible && bentoColumnsRow.implicitHeight > 0) {
            total += (sections > 0 ? gap : 0) + bentoColumnsRow.implicitHeight;
            sections++;
        }
        if (pageBodyColumn && pageBodyColumn.visible) {
            var bodyH = 0;
            var bodyCount = 0;
            var bodyCh = pageBodyColumn.children || [];
            for (var bi = 0; bi < bodyCh.length; bi++) {
                var bItem = bodyCh[bi];
                if (!bItem || !bItem.visible || bItem.implicitHeight <= 0)
                    continue;
                if (bItem.hasOwnProperty("showTabBar") && bItem.hasOwnProperty("options"))
                    continue;
                if (_isWrapperContainer(bItem) && !_wrapperHasActiveVisibleChild(bItem))
                    continue;
                bodyH += (bodyCount > 0 ? pageBodyColumn.spacing : 0) + bItem.implicitHeight;
                bodyCount++;
            }
            if (bodyH > 0) {
                total += (sections > 0 ? gap : 0) + bodyH;
                sections++;
            }
        }
        return Number(total) || 0;
    }
    readonly property bool exceedsStandardHeight: !root.embedded
        && (root.pageContentBodyHeight > root.standardPageBodyHeight + 2)
    // Bottom-docked Settings customization dock (standalone / non-Abyss overlay) covers the
    // page's lower edge while editing. Hosts publish its overlap here so the page can scroll
    // its last cards clear above the dock; availableCardContentHeight is intentionally unaffected.
    property real editBottomScrollReserve: 0
    readonly property real _editScrollReserve: (!root.embedded && root.pageScrollEnabled && SettingsLayoutManager.editMode)
        ? Math.max(0, Number(root.editBottomScrollReserve) || 0) : 0
    // Allow vertical scrolling (without scrollbar) only when page content height exceeds the Themes & Style / Custom Theme standard height
    interactive: !embedded && pageScrollEnabled && (root.exceedsStandardHeight || root._editScrollReserve > 0) && !SettingsLayoutManager.draggingModule

    function _clampScrollPosition() {
        if (root.embedded || root._clampingScroll)
            return;
        root._clampingScroll = true;
        if (!root.interactive) {
            if (!SettingsLayoutManager.draggingModule && Math.abs(root.contentY) > 0.5) {
                root.scrollTargetY = 0;
                root.contentY = 0;
            }
            root._clampingScroll = false;
            return;
        }
        var maxY = Math.max(0, root.contentHeight - root.height);
        if (root.contentY > maxY + 0.5) {
            root.scrollTargetY = maxY;
            root.contentY = maxY;
        } else if (root.contentY < -0.5) {
            root.scrollTargetY = 0;
            root.contentY = 0;
        }
        root._clampingScroll = false;
    }

    onInteractiveChanged: root._clampScrollPosition()
    onContentHeightChanged: root._clampScrollPosition()
    onContentYChanged: {
        if (!root.embedded && !root.interactive && !SettingsLayoutManager.draggingModule && !root._clampingScroll && Math.abs(root.contentY) > 0.5) {
            root._clampScrollPosition();
        }
    }
    implicitHeight: embedded ? contentColumn.implicitHeight : 0
    Layout.preferredHeight: embedded ? contentColumn.implicitHeight : -1
    Layout.maximumHeight: embedded && contentColumn.implicitHeight <= 0 ? 0 : -1
    contentHeight: (!embedded && pageScrollEnabled && (root.exceedsStandardHeight || root._editScrollReserve > 0))
        ? Math.max(height + 1, contentColumn.implicitHeight + root.bottomContentPadding + 20) + root._editScrollReserve
        : (root.embedded ? contentColumn.implicitHeight + root.bottomContentPadding : height)
    implicitWidth: embedded ? 0 : contentColumn.implicitWidth

    readonly property real maxContentWidth: Math.min(1320, Math.max(920, root.width - 40))
    readonly property real _horizontalMargin: {
        if (root.embedded) return 0
        const w = root.width
        if (w > maxContentWidth + 40) return (w - maxContentWidth) / 2
        if (w > 900) return 20
        if (w > 600) return 16
        return 12
    }

    // Horizontal touchpad/mouse wheel scroll anywhere on the page switches sub-tabs
    WheelHandler {
        id: pageHorizontalWheelHandler
        enabled: !root.embedded && root._subTabItems.length > 1
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root._handleSubTabWheel(event, false)
    }

    // Invisible park for inactive Bento cards (keeps visible=true so card bindings stay intact)
    ColumnLayout {
        id: hiddenCardsPark
        visible: true
        width: Math.max(360, (contentColumn.width - SettingsMaterialPreset.pageSpacing) / 2)
        height: 0
        spacing: 0
        clip: true
        opacity: 0
        enabled: false
    }

    ColumnLayout {
        id: contentColumn
        objectName: "contentColumn"
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.embedded ? 0 : 10
            bottomMargin: root.embedded ? 0 : 10
            leftMargin: root._horizontalMargin
            rightMargin: root._horizontalMargin
        }
        spacing: root.embedded ? 0 : SettingsMaterialPreset.pageSpacing

        ColumnLayout {
            id: navigatorHeaderHost
            objectName: "navigatorHeaderHost"
            Layout.fillWidth: true
            spacing: 0
            visible: false
        }

        // Single-Row Centered Sub-Tab Bar (supports click + horizontal scroll / mouse wheel + drag-and-drop module target)
        Item {
            id: subTabBarContainer
            objectName: "settingsSubTabBarContainer"
            visible: !root.embedded && (root._subTabItems.length > 1 || SettingsLayoutManager.editMode)
            Layout.fillWidth: true
            implicitHeight: visible ? 40 : 0

            Rectangle {
                id: subTabTrack
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width, subTabRow.implicitWidth + 8)
                height: 40
                radius: 20
                color: SettingsMaterialPreset.cardColor
                border.width: 1
                border.color: SettingsMaterialPreset.cardBorderColor

                WheelHandler {
                    id: subTabWheelHandler
                    orientation: Qt.Horizontal
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => root._handleSubTabWheel(event, false)
                }

                Flickable {
                    id: subTabFlickable
                    anchors.fill: parent
                    anchors.margins: 4
                    contentWidth: subTabRow.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    interactive: contentWidth > width + 2

                    Behavior on contentX {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    function ensureActiveVisible() {
                        if (contentWidth <= width) {
                            contentX = 0;
                            return;
                        }
                        var idx = root._activeSubTabIndex;
                        var btn = subTabRepeater.itemAt(idx);
                        if (!btn)
                            return;
                        var targetX = btn.x + btn.width / 2 - width / 2;
                        contentX = Math.max(0, Math.min(contentWidth - width, targetX));
                    }

                    onWidthChanged: Qt.callLater(ensureActiveVisible)

                    Rectangle {
                        id: activeSubTabPill
                        readonly property int pillIndex: root._subTabAnimFromIndex >= 0
                            ? root._subTabAnimFromIndex
                            : root._activeSubTabIndex
                        readonly property Item activeBtn: subTabRepeater.itemAt(pillIndex)
                        property bool animReady: true

                        function snapFromIndex(fromIdx: int) {
                            var fromBtn = subTabRepeater.itemAt(fromIdx);
                            if (!fromBtn)
                                return;
                            animReady = false;
                            x = subTabRow.x + fromBtn.x;
                            width = fromBtn.width;
                            animReady = true;
                            var toBtn = subTabRepeater.itemAt(root._activeSubTabIndex);
                            if (toBtn) {
                                x = Qt.binding(function() { return activeSubTabPill.activeBtn ? subTabRow.x + activeSubTabPill.activeBtn.x : 0; });
                                width = Qt.binding(function() { return activeSubTabPill.activeBtn ? activeSubTabPill.activeBtn.width : 0; });
                            }
                        }

                        visible: activeBtn !== null && activeBtn !== undefined && width > 0
                        x: activeBtn ? subTabRow.x + activeBtn.x : 0
                        y: (parent.height - height) / 2
                        width: activeBtn ? activeBtn.width : 0
                        height: 32
                        radius: 16
                        color: Appearance.colors.colPrimaryContainer
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colPrimary, 0.35)

                        Behavior on x {
                            enabled: Appearance.animationsEnabled && activeSubTabPill.animReady
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        Behavior on width {
                            enabled: Appearance.animationsEnabled && activeSubTabPill.animReady
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }

                    Row {
                        id: subTabRow
                        x: Math.max(0, (subTabFlickable.width - implicitWidth) / 2)
                        height: parent.height
                        spacing: 4

                        Repeater {
                            id: subTabRepeater
                            model: root._subTabItems

                            delegate: RippleButton {
                                id: subTabButton
                                required property int index
                                required property var modelData
                                readonly property bool isCurrent: Boolean(modelData.active)
                                readonly property string dropTargetId: `subtab:${modelData.pageIndex ?? root.settingsPageIndex}:${root.customTabId}:${modelData.value}`
                                readonly property bool isDropHovered: SettingsLayoutManager.draggingModule
                                    && SettingsLayoutManager.hoveredDropTarget?.targetId === subTabButton.dropTargetId

                                implicitHeight: 32
                                implicitWidth: tabPillContent.implicitWidth + (SettingsLayoutManager.editMode && isCurrent ? 18 : 24)
                                anchors.verticalCenter: parent.verticalCenter
                                buttonRadius: 16
                                toggled: isCurrent
                                colBackground: isDropHovered ? Qt.alpha(Appearance.colors.colPrimary, 0.25) : "transparent"
                                colBackgroundHover: SettingsMaterialPreset.headerHoverColor
                                colBackgroundToggled: activeSubTabPill.visible ? "transparent" : Appearance.colors.colPrimaryContainer
                                colBackgroundToggledHover: Qt.alpha(Appearance.colors.colPrimaryContainerHover, 0.35)
                                onClicked: root.activateSubTabItem(modelData)

                                Component.onCompleted: {
                                    SettingsLayoutManager.registerDropTarget(subTabButton.dropTargetId, subTabButton, {
                                        kind: modelData.kind === "siblingPage" ? "sidebar-page" : "subtab",
                                        pageIndex: (modelData.pageIndex !== undefined && modelData.pageIndex >= 0) ? modelData.pageIndex : root.settingsPageIndex,
                                        customTabId: root.customTabId,
                                        subTabKey: String(modelData.value || ""),
                                        label: String(modelData.title || "")
                                    });
                                }

                                Component.onDestruction: {
                                    SettingsLayoutManager.unregisterDropTarget(subTabButton.dropTargetId, subTabButton);
                                }

                                Rectangle {
                                    visible: subTabButton.isDropHovered
                                    anchors.fill: parent
                                    radius: 16
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Appearance.colors.colPrimary
                                }

                                contentItem: Item {
                                    implicitWidth: tabPillContent.implicitWidth
                                    implicitHeight: tabPillContent.implicitHeight

                                    Row {
                                        id: tabPillContent
                                        anchors.centerIn: parent
                                        spacing: 5

                                        RippleButton {
                                            visible: SettingsLayoutManager.editMode && subTabButton.isCurrent && root.canMoveSubTabLeft
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            buttonRadius: 10
                                            colBackground: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.08)
                                            colBackgroundHover: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.20)
                                            onClicked: root.reorderActiveSubTab(-1)
                                            StyledToolTip { text: Translation.tr("Move sub-tab left") }
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "chevron_left"
                                                    iconSize: 14
                                                    color: Appearance.colors.colOnPrimaryContainer
                                                }
                                            }
                                        }

                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: subTabButton.modelData.icon || "tune"
                                            iconSize: 16
                                            color: subTabButton.isCurrent
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : SettingsMaterialPreset.navigationIconColor(
                                                    subTabButton.index,
                                                    Math.max(1, root._subTabItems.length),
                                                    false)
                                        }

                                        StyledText {
                                            id: subTabLabel
                                            anchors.verticalCenter: parent.verticalCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: subTabButton.modelData.title || ""
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: subTabButton.isCurrent ? Font.DemiBold : Font.Medium
                                            color: subTabButton.isCurrent
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnSurface
                                        }

                                        RippleButton {
                                            visible: SettingsLayoutManager.editMode && subTabButton.isCurrent && root._subTabItems.length > 0
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            buttonRadius: 10
                                            colBackground: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.08)
                                            colBackgroundHover: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.20)
                                            onClicked: SettingsLayoutManager.requestInlinePrompt("rename-subtab")
                                            StyledToolTip { text: Translation.tr("Rename sub-tab") }
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "edit"
                                                    iconSize: 12
                                                    color: Appearance.colors.colOnPrimaryContainer
                                                }
                                            }
                                        }

                                        RippleButton {
                                            visible: SettingsLayoutManager.editMode && subTabButton.isCurrent && root._subTabItems.length > 1
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            buttonRadius: 10
                                            colBackground: Qt.alpha(Appearance.colors.colError, 0.14)
                                            colBackgroundHover: Qt.alpha(Appearance.colors.colError, 0.28)
                                            onClicked: root.deleteActiveSubTab()
                                            StyledToolTip { text: Translation.tr("Delete sub-tab (modules stay safe)") }
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "close"
                                                    iconSize: 13
                                                    color: Appearance.colors.colError
                                                }
                                            }
                                        }

                                        RippleButton {
                                            visible: SettingsLayoutManager.editMode && subTabButton.isCurrent && root.canMoveSubTabRight
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            buttonRadius: 10
                                            colBackground: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.08)
                                            colBackgroundHover: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.20)
                                            onClicked: root.reorderActiveSubTab(1)
                                            StyledToolTip { text: Translation.tr("Move sub-tab right") }
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "chevron_right"
                                                    iconSize: 14
                                                    color: Appearance.colors.colOnPrimaryContainer
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Quick "+" pill in Sub-Tab bar during Edit Mode to create a new Sub-Tab
                        RippleButton {
                            id: addSubTabPillBtn
                            objectName: "addSubTabPillButton"
                            visible: SettingsLayoutManager.editMode
                            implicitHeight: 32
                            implicitWidth: addSubTabPillRow.implicitWidth + 20
                            anchors.verticalCenter: parent.verticalCenter
                            buttonRadius: 16
                            colBackground: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                            colBackgroundHover: Qt.alpha(Appearance.colors.colPrimary, 0.24)
                            onClicked: {
                                SettingsLayoutManager.requestInlinePrompt("new-subtab");
                            }

                            StyledToolTip {
                                text: Translation.tr("Add a new sub-tab to this page")
                            }

                            contentItem: Item {
                                implicitWidth: addSubTabPillRow.implicitWidth
                                implicitHeight: addSubTabPillRow.implicitHeight

                                Row {
                                    id: addSubTabPillRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "add"
                                        iconSize: 15
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Tab")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Freeform 2D Canvas Container (when pageLayoutConfig.layoutMode === "canvas")
        Rectangle {
            id: freeformCanvasContainer
            objectName: "freeformCanvasContainer"
            visible: !root.embedded && root.isCanvasLayoutMode
            Layout.fillWidth: true
            implicitHeight: {
                if (!visible) return 0;
                var maxY = 520;
                var ch = freeformCanvasContainer.children || [];
                for (var i = 0; i < ch.length; i++) {
                    var item = ch[i];
                    if (item && item.visible && item !== canvasGridVisual)
                        maxY = Math.max(maxY, item.y + item.height + 32);
                }
                return maxY;
            }
            radius: SettingsMaterialPreset.cardRadius
            color: SettingsLayoutManager.editMode
                ? Qt.alpha(Appearance.colors.colLayer1, 0.5)
                : "transparent"
            border.width: SettingsLayoutManager.editMode ? 1 : 0
            border.color: Qt.alpha(Appearance.colors.colPrimary, 0.35)

            DotGridCanvas {
                id: canvasGridVisual
                anchors.fill: parent
                visible: SettingsLayoutManager.editMode && SettingsLayoutManager.snapEnabled
                gridSize: Math.max(12, SettingsLayoutManager.gridSize)
                dotRadius: 1.2
                dotAlpha: 0.25
                dotColor: Appearance.colors.colPrimary
            }
        }

        // Full-Width Top Bento Section for cards with bentoColumn === "full" or "top"
        ColumnLayout {
            id: topBentoColumn
            objectName: "topBentoColumn"
            visible: !root.embedded && !root.isCanvasLayoutMode && (root._topBentoCount > 0 || SettingsLayoutManager.draggingModule)
            width: contentColumn.width
            readonly property real activeCardsImplicitHeight: {
                var list = root._activeTopBentoCards || [];
                var sum = 0;
                for (var i = 0; i < list.length; i++) {
                    var c = list[i];
                    if (c && c.visible)
                        sum += c.implicitHeight;
                }
                return sum;
            }
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root._topBentoCount > 0
                ? (activeCardsImplicitHeight > 0 ? activeCardsImplicitHeight : implicitHeight)
                : (SettingsLayoutManager.draggingModule ? 44 : 0)
            Layout.maximumHeight: root._topBentoCount > 0
                ? (activeCardsImplicitHeight > 0 ? activeCardsImplicitHeight : implicitHeight)
                : (SettingsLayoutManager.draggingModule ? 44 : 0)
            Layout.alignment: Qt.AlignTop
            spacing: 0
            opacity: root._subTabContentOpacity
            transform: Translate {
                x: root._subTabContentSlideOffset
            }

            Rectangle {
                visible: root._topBentoCount === 0 && SettingsLayoutManager.draggingModule
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Qt.alpha(Appearance.colors.colPrimary, 0.10)
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Drop here for Full-Width Top Section")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // 2-Column macOS Sequoia Bento Grid for active SettingsCardSection cards
        RowLayout {
            id: bentoColumnsRow
            objectName: "bentoColumnsRow"
            visible: !root.embedded && !root.isCanvasLayoutMode && (root._leftBentoCount > 0 || root._rightBentoCount > 0 || SettingsLayoutManager.draggingModule)
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: SettingsLayoutManager.editMode ? 8 : SettingsMaterialPreset.pageSpacing
            opacity: root._subTabContentOpacity
            transform: Translate {
                x: root._subTabContentSlideOffset
            }

            ColumnLayout {
                id: leftBentoColumn
                objectName: "leftBentoColumn"
                visible: root._leftBentoCount > 0 || SettingsLayoutManager.draggingModule
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.minimumWidth: 0
                Layout.preferredWidth: Math.round(1000 * root.effectiveLeftColumnRatio)
                Layout.preferredHeight: root._leftBentoCount > 0
                    ? implicitHeight
                    : (SettingsLayoutManager.draggingModule ? Math.max(80, rightBentoColumn.implicitHeight) : 0)
                Layout.maximumHeight: root._leftBentoCount > 0
                    ? implicitHeight
                    : (SettingsLayoutManager.draggingModule ? Math.max(80, rightBentoColumn.implicitHeight) : 0)
                Layout.alignment: Qt.AlignTop
                spacing: 0

                Rectangle {
                    visible: root._leftBentoCount === 0 && SettingsLayoutManager.draggingModule
                    Layout.fillWidth: true
                    implicitHeight: Math.max(80, rightBentoColumn.implicitHeight)
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.10)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Drop here for Left Column")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Interactive Column Split Handle in Edit Mode (drag left/right to resize Bento column ratio)
            Rectangle {
                id: bentoSplitHandle
                visible: SettingsLayoutManager.editMode && root._leftBentoCount > 0 && root._rightBentoCount > 0
                Layout.preferredWidth: 10
                Layout.fillHeight: true
                Layout.minimumHeight: 80
                radius: 5
                color: splitDragArea.pressed || splitDragArea.containsMouse
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.35)
                    : Qt.alpha(Appearance.colors.colOutlineVariant, 0.25)

                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: 36
                    radius: 2
                    color: splitDragArea.pressed || splitDragArea.containsMouse
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }

                MouseArea {
                    id: splitDragArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SplitHCursor

                    property real startSceneX: 0
                    property real startRatio: 0.5
                    property bool draggingSplit: false

                    onPressed: mouse => {
                        const pt = splitDragArea.mapToItem(null, mouse.x, mouse.y);
                        startSceneX = pt.x;
                        startRatio = root.leftColumnRatio;
                        draggingSplit = true;
                    }

                    onPositionChanged: mouse => {
                        if (!pressed || !draggingSplit)
                            return;
                        const pt = splitDragArea.mapToItem(null, mouse.x, mouse.y);
                        const dx = pt.x - startSceneX;
                        const totalW = Math.max(400, bentoColumnsRow.width);
                        const nextRatio = Math.max(0.25, Math.min(0.75, startRatio + dx / totalW));
                        root._previewLeftColumnRatio = nextRatio;
                    }

                    onReleased: {
                        const wasDragging = draggingSplit;
                        draggingSplit = false;
                        if (wasDragging && root._previewLeftColumnRatio > 0) {
                            const finalRatio = root._previewLeftColumnRatio;
                            root._previewLeftColumnRatio = -1;
                            SettingsLayoutManager.setLeftColumnRatio(root.settingsPageIndex, root.customTabId, finalRatio);
                        } else {
                            root._previewLeftColumnRatio = -1;
                        }
                    }

                    onCanceled: {
                        draggingSplit = false;
                        root._previewLeftColumnRatio = -1;
                    }

                    onDoubleClicked: {
                        draggingSplit = false;
                        root._previewLeftColumnRatio = -1;
                        SettingsLayoutManager.setLeftColumnRatio(root.settingsPageIndex, root.customTabId, 0.5);
                    }
                }

                StyledToolTip {
                    extraVisibleCondition: splitDragArea.containsMouse && !splitDragArea.pressed
                    text: Translation.tr("Drag left/right to adjust Bento column width ratio (double-click to reset to 50/50)")
                }
            }

            ColumnLayout {
                id: rightBentoColumn
                objectName: "rightBentoColumn"
                visible: root._rightBentoCount > 0 || SettingsLayoutManager.draggingModule
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.minimumWidth: 0
                Layout.preferredWidth: Math.round(1000 * (1.0 - root.effectiveLeftColumnRatio))
                Layout.preferredHeight: root._rightBentoCount > 0
                    ? implicitHeight
                    : (SettingsLayoutManager.draggingModule ? Math.max(80, leftBentoColumn.implicitHeight) : 0)
                Layout.maximumHeight: root._rightBentoCount > 0
                    ? implicitHeight
                    : (SettingsLayoutManager.draggingModule ? Math.max(80, leftBentoColumn.implicitHeight) : 0)
                Layout.alignment: Qt.AlignTop
                spacing: 0

                Rectangle {
                    visible: root._rightBentoCount === 0 && SettingsLayoutManager.draggingModule
                    Layout.fillWidth: true
                    implicitHeight: Math.max(80, leftBentoColumn.implicitHeight)
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.10)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Drop here for Right Column")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }

        ColumnLayout {
            id: pageBodyColumn
            objectName: "pageBodyColumn"
            visible: true
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: implicitHeight
            Layout.maximumHeight: implicitHeight
            Layout.topMargin: (!root.embedded && (topBentoColumn.visible || bentoColumnsRow.visible || freeformCanvasContainer.visible) && implicitHeight <= 0)
                ? -SettingsMaterialPreset.pageSpacing
                : 0
            spacing: 0
            opacity: root._subTabContentOpacity
            transform: Translate {
                x: root._subTabContentSlideOffset
            }
        }
    }
}
