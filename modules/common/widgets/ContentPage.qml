import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property bool embedded: false
    property real bottomContentPadding: 0
    // Metadata for Settings pages
    property int settingsPageIndex: -1
    property string settingsPageName: ""
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
    property var _eligibleCards: []
    property var _cardPages: []
    property var _cardPageOptions: []
    property string activeCardSubTab: ""
    property var activeCardItem: null
    property bool _cardTabsUpdateScheduled: false
    property bool _isDestroying: false
    property bool _persistedSectionRestored: false
    property bool _suppressSectionPersist: false
    property int _topBentoCount: 0
    property int _leftBentoCount: 0
    property int _rightBentoCount: 0

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

    // Unified single-row centered sub-tab items across category sibling pages & task sections
    readonly property var _subTabItems: {
        if (root.embedded)
            return [];
        var list = [];
        var siblings = root.categorySiblingPages || [];
        var curTaskVal = (root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined)
            ? String(root.settingsTaskNavigator.currentValue)
            : "";

        if (siblings.length > 0) {
            for (var s = 0; s < siblings.length; s++) {
                var sp = siblings[s];
                if (!sp) continue;
                var pIdx = Number(sp.realIndex);
                var isCurrentPage = (pIdx === root.settingsPageIndex);
                var pSubTabs = sp.subTabs || [];
                if (pSubTabs.length > 0) {
                    for (var stIdx = 0; stIdx < pSubTabs.length; stIdx++) {
                        var st = pSubTabs[stIdx];
                        if (!st) continue;
                        var stVal = String(st.value || "");
                        var isStActive = isCurrentPage && (
                            curTaskVal === stVal
                            || (curTaskVal.length === 0 && stIdx === 0)
                        );
                        list.push({
                            kind: "pageSection",
                            title: String(st.name || ""),
                            icon: String(st.icon || sp.icon || "tune"),
                            value: stVal,
                            pageIndex: pIdx,
                            active: isStActive
                        });
                    }
                } else {
                    list.push({
                        kind: "siblingPage",
                        title: String(sp.name || ""),
                        icon: String(sp.icon || "settings"),
                        value: String(sp.key || ""),
                        pageIndex: pIdx,
                        active: isCurrentPage
                    });
                }
            }
        } else if (root._hasTaskNavigatorTabs && root.settingsTaskNavigator) {
            var tOpts = root.settingsTaskNavigator.options || [];
            for (var i = 0; i < tOpts.length; i++) {
                var topt = tOpts[i];
                if (!topt) continue;
                var tVal = String(topt.value || "");
                list.push({
                    kind: "task",
                    title: String(topt.displayName || ""),
                    icon: String(topt.icon || "tune"),
                    value: tVal,
                    pageIndex: root.settingsPageIndex,
                    active: (curTaskVal === tVal || (curTaskVal.length === 0 && i === 0))
                });
            }
        } else if (root._cardPageOptions.length > 1) {
            for (var j = 0; j < root._cardPageOptions.length; j++) {
                var popt = root._cardPageOptions[j];
                if (!popt) continue;
                var pVal = String(popt.value || "");
                list.push({
                    kind: "cardPage",
                    title: String(popt.displayName || ""),
                    icon: String(popt.icon || "tune"),
                    value: pVal,
                    pageIndex: root.settingsPageIndex,
                    active: (root.activeCardSubTab === pVal || (root.activeCardSubTab.length === 0 && j === 0))
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

        if (item.kind === "pageSection") {
            if (item.pageIndex === root.settingsPageIndex) {
                if (targetIdx !== curIdx)
                    root.triggerSubTabContentTransition(dir);
                if (root.hasOwnProperty("activeSection"))
                    root.activeSection = item.value;
                if (root.settingsTaskNavigator)
                    root.settingsTaskNavigator.selected(item.value);
                root._savePersistedSection();
                root.contentY = 0;
                root._scheduleCardTabsUpdate();
            } else if (item.pageIndex >= 0) {
                root.pageSectionNavigationRequested(item.pageIndex, item.value);
            }
        } else if (item.kind === "siblingPage") {
            if (item.pageIndex >= 0 && item.pageIndex !== root.settingsPageIndex) {
                root.pageNavigationRequested(item.pageIndex);
            }
        } else if (item.kind === "task") {
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir);
            if (root.settingsTaskNavigator) {
                root.settingsTaskNavigator.selected(item.value);
            }
            root._savePersistedSection();
            root.contentY = 0;
            root._scheduleCardTabsUpdate();
        } else if (item.kind === "cardPage") {
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir);
            root.selectCardSubTab(item.value);
            root._savePersistedSection();
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
        var dy = allowVertical ? wheelEvent.angleDelta.y : 0;
        var primaryDelta = Math.abs(dx) >= Math.abs(dy) ? dx : dy;
        if (Math.abs(primaryDelta) < 1)
            return;
        var now = Date.now();
        if (now - root._lastSubTabWheelMs < 150) {
            wheelEvent.accepted = true;
            return;
        }
        root._wheelDeltaAccum += primaryDelta;
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
        }
    }

    Component.onDestruction: {
        root._isDestroying = true;
        cardTabsUpdateTimer.stop();
        bentoSyncTimer.stop();
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
        while (p && p !== root && p !== pageBodyColumn && p !== topBentoColumn && p !== leftBentoColumn && p !== rightBentoColumn && p !== hiddenCardsPark) {
            if (p.hasOwnProperty("sourceComponent") && p.hasOwnProperty("status")) {
                return true;
            }
            p = p.parent;
        }
        return false;
    }

    function _canReparentToBento(c) {
        if (!c || c._preventBentoReparent || !c.showHeader || !c.title || c.title.length === 0)
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
            if (!node || node === hiddenCardsPark || node === topBentoColumn || node === leftBentoColumn || node === rightBentoColumn)
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
        for (var n = 0; n < _registeredCards.length; n++) {
            if (_registeredCards[n] && _registeredCards[n]._bentoExtraHeight !== undefined) {
                _registeredCards[n]._bentoExtraHeight = 0;
            }
        }
        if (!leftCards || !rightCards || leftCards.length === 0 || rightCards.length === 0)
            return;

        var gap = SettingsMaterialPreset.pageSpacing;
        var leftNaturalH = 0;
        for (var a = 0; a < leftCards.length; a++) {
            leftNaturalH += _cardHeight(leftCards[a]) + (a < leftCards.length - 1 ? gap : 0);
        }
        var rightNaturalH = 0;
        for (var b = 0; b < rightCards.length; b++) {
            rightNaturalH += _cardHeight(rightCards[b]) + (b < rightCards.length - 1 ? gap : 0);
        }
        var diff = Math.abs(leftNaturalH - rightNaturalH);
        if (diff > 1) {
            if (leftNaturalH < rightNaturalH) {
                var assignedLeft = false;
                for (var li = 0; li < leftCards.length; li++) {
                    if (leftCards[li] && leftCards[li]._consumesBentoExtraHeight && leftCards[li]._bentoExtraHeight !== undefined) {
                        leftCards[li]._bentoExtraHeight = diff;
                        assignedLeft = true;
                        break;
                    }
                }
                if (!assignedLeft && leftCards.length > 0) {
                    var lastLeft = leftCards[leftCards.length - 1];
                    if (lastLeft && lastLeft._bentoExtraHeight !== undefined)
                        lastLeft._bentoExtraHeight = diff;
                }
            } else {
                var assignedRight = false;
                for (var ri = 0; ri < rightCards.length; ri++) {
                    if (rightCards[ri] && rightCards[ri]._consumesBentoExtraHeight && rightCards[ri]._bentoExtraHeight !== undefined) {
                        rightCards[ri]._bentoExtraHeight = diff;
                        assignedRight = true;
                        break;
                    }
                }
                if (!assignedRight && rightCards.length > 0) {
                    var lastRight = rightCards[rightCards.length - 1];
                    if (lastRight && lastRight._bentoExtraHeight !== undefined)
                        lastRight._bentoExtraHeight = diff;
                }
            }
        }
    }

    function _reparentColumnOrdered(columnItem, cardsList, reparentedOutList, bodyDirectOutList) {
        var reparentable = [];
        for (var idx = 0; idx < cardsList.length; idx++) {
            var c = cardsList[idx];
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
            rc.parent = columnItem;
            reparentedOutList.push(rc);
        }
        return reparentable.length;
    }

    function _applyBentoPlacement(chosenPage) {
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
            if (!cardItem.showHeader || !cardItem.title || cardItem.title.length === 0) {
                cardItem._cardSubTabActive = true;
                cardItem._hasNextActiveCard = false;
                continue;
            }
            if (activeCards.indexOf(cardItem) < 0) {
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
    }

    function _updateCardTabs() {
        if (root.embedded || root._isDestroying)
            return;

        var aliveCards = [];
        for (var r = 0; r < _registeredCards.length; r++) {
            var rcItem = _registeredCards[r];
            if (rcItem && rcItem.parent)
                aliveCards.push(rcItem);
        }
        if (aliveCards.length !== _registeredCards.length)
            _registeredCards = aliveCards;

        _ensureDeclarationOrder();

        var eligible = [];
        var usedKeys = {};
        for (var i = 0; i < _registeredCards.length; i++) {
            var c = _registeredCards[i];
            if (!c)
                continue;
            if (!c.showHeader || !c.title || c.title.length === 0) {
                c._cardSubTabActive = true;
                c._hasNextActiveCard = false;
                continue;
            }
            if (c.isCardEligibleForTabs()) {
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

        _eligibleCards = eligible;

        if (eligible.length === 0) {
            _cardPages = [];
            _cardPageOptions = [];
            activeCardItem = null;
            _applyBentoPlacement(null);
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

            if (card.bentoColumn === "full" || card.bentoColumn === "top") {
                curPage.top.push(card);
                curPage.cards.push(card);
            } else if (twoCols && card.bentoColumn === "left") {
                curPage.left.push(card);
                curPage.leftH += (curPage.left.length > 1 ? gap : 0) + ch;
                curPage.cards.push(card);
            } else if (twoCols && card.bentoColumn === "right") {
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
            for (var i = 0; i < _registeredCards.length; i++) {
                var c = _registeredCards[i];
                if (c) {
                    if (c._initialParent && (c.parent === topBentoColumn || c.parent === leftBentoColumn || c.parent === rightBentoColumn || c.parent === hiddenCardsPark)) {
                        c.parent = c._initialParent;
                    }
                    c._bentoExtraHeight = 0;
                    c._cardSubTabActive = true;
                    c._hasNextActiveCard = false;
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible && !embedded) {
            _updateCardTabs();
            _scheduleCardTabsUpdate();
        }
    }

    onHeightChanged: {
        if (visible && !embedded && height > 200) {
            _scheduleCardTabsUpdate();
        }
    }

    onWidthChanged: {
        if (visible && !embedded && width > 300) {
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
    // Allow scrolling only if a tall editor sub-view exceeds the viewport
    interactive: !embedded && contentHeight > height + 8
    implicitHeight: embedded ? contentColumn.implicitHeight : 0
    Layout.preferredHeight: embedded ? contentColumn.implicitHeight : -1
    Layout.maximumHeight: embedded && contentColumn.implicitHeight <= 0 ? 0 : -1
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding + (root.embedded ? 0 : 20)
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

        // Single-Row Centered Sub-Tab Bar (supports click + horizontal scroll / mouse wheel)
        Item {
            id: subTabBarContainer
            objectName: "settingsSubTabBarContainer"
            visible: !root.embedded && root._subTabItems.length > 1
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
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => root._handleSubTabWheel(event, true)
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

                                implicitHeight: 32
                                implicitWidth: tabPillContent.implicitWidth + 24
                                anchors.verticalCenter: parent.verticalCenter
                                buttonRadius: 16
                                toggled: isCurrent
                                colBackground: "transparent"
                                colBackgroundHover: SettingsMaterialPreset.headerHoverColor
                                colBackgroundToggled: activeSubTabPill.visible ? "transparent" : Appearance.colors.colPrimaryContainer
                                colBackgroundToggledHover: Qt.alpha(Appearance.colors.colPrimaryContainerHover, 0.35)
                                onClicked: root.activateSubTabItem(modelData)

                                contentItem: Item {
                                    implicitWidth: tabPillContent.implicitWidth
                                    implicitHeight: tabPillContent.implicitHeight

                                    Row {
                                        id: tabPillContent
                                        anchors.centerIn: parent
                                        spacing: 6

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
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Full-Width Top Bento Section for cards with bentoColumn === "full" or "top"
        ColumnLayout {
            id: topBentoColumn
            objectName: "topBentoColumn"
            visible: !root.embedded && root._topBentoCount > 0
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: implicitHeight
            Layout.maximumHeight: implicitHeight
            Layout.alignment: Qt.AlignTop
            spacing: 0
            opacity: root._subTabContentOpacity
            transform: Translate {
                x: root._subTabContentSlideOffset
            }
        }

        // 2-Column macOS Sequoia Bento Grid for active SettingsCardSection cards
        RowLayout {
            id: bentoColumnsRow
            objectName: "bentoColumnsRow"
            visible: !root.embedded && (root._leftBentoCount > 0 || root._rightBentoCount > 0)
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignTop
            spacing: SettingsMaterialPreset.pageSpacing
            opacity: root._subTabContentOpacity
            transform: Translate {
                x: root._subTabContentSlideOffset
            }

            ColumnLayout {
                id: leftBentoColumn
                objectName: "leftBentoColumn"
                visible: root._leftBentoCount > 0
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredWidth: 1
                Layout.preferredHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                Layout.alignment: Qt.AlignTop
                spacing: 0
            }

            ColumnLayout {
                id: rightBentoColumn
                objectName: "rightBentoColumn"
                visible: root._rightBentoCount > 0
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredWidth: 1
                Layout.preferredHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                Layout.alignment: Qt.AlignTop
                spacing: 0
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
            Layout.topMargin: (!root.embedded && (topBentoColumn.visible || bentoColumnsRow.visible) && implicitHeight <= 0)
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
