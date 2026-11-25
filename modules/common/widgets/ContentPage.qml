import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Clean, responsive Settings page canvas with centered segmented sub-tabs,
 * smooth horizontal wheel tab switching, section persistence, and natural
 * single-column card layout. Edit Layout / Canvas / Reparenting removed.
 */
StyledFlickable {
    id: root
    property bool embedded: false
    property bool pageScrollEnabled: true
    property real bottomContentPadding: 0
    property int settingsPageIndex: -1
    property string settingsPageName: ""
    property string customTabId: ""
    property var settingsTaskNavigator: null

    // Category sibling sub-pages injected by SettingsPageHost
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
    property var _registeredContentSections: []
    property var _eligibleCards: []
    property var irisSectionGroups: []
    property string _heldIrisSectionTitle: ""
    property int _irisGeometryRevision: 0
    property var _cardPages: []
    property var _cardPageOptions: []
    property string activeCardSubTab: ""
    property string customActiveSubTab: ""
    property var activeCardItem: null
    property bool _cardTabsUpdateScheduled: false
    property bool _initialCardTabsSynced: false
    property bool _isDestroying: false
    property bool _persistedSectionRestored: false
    property bool _suppressSectionPersist: false
    property bool bentoEqualizeToTarget: false
    readonly property real targetBentoHeight: 0
    readonly property real standardPageBodyHeight: 0
    readonly property bool exceedsStandardHeight: false
    readonly property bool isCanvasLayoutMode: false
    property real editBottomScrollReserve: 0

    function _restorePersistedSection() {
        if (root.embedded || root._persistedSectionRestored || root.settingsPageIndex < 0 || !Persistent.ready || !Persistent.states?.settings)
            return
        root._persistedSectionRestored = true
        var raw = String(Persistent.states.settings.pageSections || "{}")
        var map = {}
        try {
            map = JSON.parse(raw) || {}
        } catch (e) {
            map = {}
        }
        var entry = map[String(root.settingsPageIndex)]
        if (!entry || typeof entry !== "object")
            return
        root._suppressSectionPersist = true
        if (entry.section && typeof entry.section === "string" && entry.section.length > 0) {
            var validSection = true
            if (root.settingsTaskNavigator && (root.settingsTaskNavigator.options?.length ?? 0) > 0) {
                validSection = false
                var navOpts = root.settingsTaskNavigator.options
                for (var i = 0; i < navOpts.length; i++) {
                    if (navOpts[i] && String(navOpts[i].value || "") === entry.section) {
                        validSection = true
                        break
                    }
                }
            }
            if (validSection) {
                if (root.hasOwnProperty("activeSection"))
                    root.activeSection = entry.section
                if (root.settingsTaskNavigator && typeof root.settingsTaskNavigator.selected === "function")
                    root.settingsTaskNavigator.selected(entry.section)
            }
        }
        if (entry.cardTab && typeof entry.cardTab === "string" && entry.cardTab.length > 0)
            root.activeCardSubTab = entry.cardTab
        root._suppressSectionPersist = false
        if (!root.embedded && root._initialCardTabsSynced)
            root._updateCardTabs()
        else if (!root.embedded)
            root._scheduleCardTabsUpdate()
    }

    function _savePersistedSection() {
        if (root.embedded || root._isDestroying || root._suppressSectionPersist || !root._persistedSectionRestored || root.settingsPageIndex < 0 || !Persistent.ready || !Persistent.states?.settings)
            return
        var raw = String(Persistent.states.settings.pageSections || "{}")
        var map = {}
        try {
            map = JSON.parse(raw) || {}
        } catch (e) {
            map = {}
        }
        var secVal = ""
        if (root.hasOwnProperty("activeSection") && root.activeSection !== undefined)
            secVal = String(root.activeSection || "")
        else if (root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined)
            secVal = String(root.settingsTaskNavigator.currentValue || "")
        var cardVal = root._cardPageOptions.length > 1 ? String(root.activeCardSubTab || "") : ""
        var prev = map[String(root.settingsPageIndex)]
        if (prev && prev.section === secVal && prev.cardTab === cardVal)
            return
        map[String(root.settingsPageIndex)] = {
            section: secVal,
            cardTab: cardVal
        }
        Persistent.states.settings.pageSections = JSON.stringify(map)
    }

    Connections {
        target: root
        ignoreUnknownSignals: true
        function onActiveSectionChanged() {
            root._savePersistedSection()
            root._scheduleCardTabsUpdate()
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root._restorePersistedSection()
        }
    }

    onSettingsTaskNavigatorChanged: {
        if (root.settingsTaskNavigator && !root.embedded) {
            root._persistedSectionRestored = false
            root._restorePersistedSection()
        }
    }

    Component.onCompleted: {
        root._restorePersistedSection()
        if (!root.embedded)
            root._updateCardTabs()
        else
            root._syncPageBodyWrappers()
    }

    Component.onDestruction: {
        root._isDestroying = true
        cardTabsUpdateTimer.stop()
    }

    readonly property bool _hasTaskNavigatorTabs: !root.embedded
        && root.settingsTaskNavigator !== null
        && (root.settingsTaskNavigator.activeNavigator ?? root.settingsTaskNavigator.visible)
        && Boolean(root.settingsTaskNavigator.showTabBar)
        && (root.settingsTaskNavigator.options?.length ?? 0) > 1

    readonly property bool hasCardSubTabs: !root.embedded && root._cardPageOptions.length > 1
    readonly property bool abyssTaskStyle: Config.options?.panelFamily === "abyss"

    readonly property var baseSubTabSpecs: {
        if (root.embedded)
            return []
        var specs = []
        if (root._hasTaskNavigatorTabs && root.settingsTaskNavigator) {
            var tOpts = root.settingsTaskNavigator.options || []
            for (var i = 0; i < tOpts.length; i++) {
                var topt = tOpts[i]
                if (!topt) continue
                specs.push({
                    key: String(topt.value || ""),
                    label: String(topt.displayName || ""),
                    icon: String(topt.icon || "tune")
                })
            }
        } else if (root._cardPageOptions.length > 1) {
            for (var j = 0; j < root._cardPageOptions.length; j++) {
                var popt = root._cardPageOptions[j]
                if (!popt) continue
                specs.push({
                    key: String(popt.value || ""),
                    label: String(popt.displayName || ""),
                    icon: String(popt.icon || "tune")
                })
            }
        }
        return specs
    }

    readonly property var effectiveSubTabSpecs: root.baseSubTabSpecs
    readonly property bool _hasEffectiveSubTabs: !root.embedded
        && (root.effectiveSubTabSpecs.length > 1 || root._subTabItems.length > 1)

    readonly property string activeSubTabKey: {
        if (root._hasTaskNavigatorTabs) {
            if (root.hasOwnProperty("activeSection") && root.activeSection !== undefined && String(root.activeSection).length > 0)
                return String(root.activeSection)
            if (root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined && String(root.settingsTaskNavigator.currentValue).length > 0)
                return String(root.settingsTaskNavigator.currentValue)
        }
        if (root.hasCardSubTabs && root.activeCardSubTab.length > 0)
            return root.activeCardSubTab
        if (root.effectiveSubTabSpecs.length > 0)
            return String(root.effectiveSubTabSpecs[0].key || "")
        return ""
    }

    readonly property string activeSubTabLabel: {
        var items = root._subTabItems || []
        for (var j = 0; j < items.length; j++) {
            if (items[j] && items[j].active)
                return String(items[j].title || "")
        }
        var cur = root.activeSubTabKey
        var specs = root.effectiveSubTabSpecs || []
        for (var i = 0; i < specs.length; i++) {
            if (specs[i] && specs[i].key === cur)
                return String(specs[i].label || cur)
        }
        return cur
    }

    // Unified centered sub-tab strip across category sibling pages & in-page task sections
    readonly property var _subTabItems: {
        if (root.embedded)
            return []
        var list = []
        var siblings = root.categorySiblingPages || []
        var curTaskVal = (root.hasOwnProperty("activeSection") && root.activeSection !== undefined && String(root.activeSection).length > 0)
            ? String(root.activeSection)
            : ((root.settingsTaskNavigator && root.settingsTaskNavigator.currentValue !== undefined)
                ? String(root.settingsTaskNavigator.currentValue)
                : "")

        if (siblings.length > 0) {
            for (var s = 0; s < siblings.length; s++) {
                var sp = siblings[s]
                if (!sp) continue
                var pIdx = Number(sp.realIndex)
                var isCurrentPage = (pIdx === root.settingsPageIndex)
                var rawSubTabs = sp.subTabs || []
                if (rawSubTabs.length > 0) {
                    for (var stIdx = 0; stIdx < rawSubTabs.length; stIdx++) {
                        var st = rawSubTabs[stIdx]
                        if (!st) continue
                        var stVal = String(st.value || "")
                        var isStActive = isCurrentPage && (
                            curTaskVal === stVal
                            || (curTaskVal.length === 0 && stIdx === 0)
                        )
                        list.push({
                            kind: "pageSection",
                            title: String(st.name || ""),
                            icon: String(st.icon || sp.icon || "tune"),
                            value: stVal,
                            pageIndex: pIdx,
                            active: isStActive
                        })
                    }
                } else {
                    list.push({
                        kind: "siblingPage",
                        title: String(sp.name || ""),
                        icon: String(sp.icon || "settings"),
                        value: String(sp.key || "overview"),
                        pageIndex: pIdx,
                        active: isCurrentPage
                    })
                }
            }
        } else if (root.effectiveSubTabSpecs.length > 1) {
            for (var i = 0; i < root.effectiveSubTabSpecs.length; i++) {
                var spec = root.effectiveSubTabSpecs[i]
                if (!spec) continue
                var sVal = String(spec.key || "")
                var itemKind = root._hasTaskNavigatorTabs ? "task" : "cardPage"
                var activeVal = root._hasTaskNavigatorTabs
                    ? curTaskVal
                    : (root.hasCardSubTabs ? root.activeCardSubTab : "")
                list.push({
                    kind: itemKind,
                    title: String(spec.label || ""),
                    icon: String(spec.icon || "tune"),
                    value: sVal,
                    pageIndex: root.settingsPageIndex,
                    active: (activeVal === sVal || (activeVal.length === 0 && i === 0))
                })
            }
        }
        return list.length > 1 ? list : []
    }

    readonly property int _activeSubTabIndex: {
        var items = root._subTabItems || []
        for (var i = 0; i < items.length; i++) {
            if (items[i] && items[i].active)
                return i
        }
        return 0
    }

    property int _subTabAnimFromIndex: -1
    property real _subTabContentSlideOffset: 0
    property real _subTabContentOpacity: 1.0

    ParallelAnimation {
        id: subTabContentAnim
        NumberAnimation {
            target: root
            property: "_subTabContentOpacity"
            from: 0.45
            to: 1.0
            duration: Appearance.animationsEnabled ? Math.max(110, Appearance.animation.elementMoveFast.duration) : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "_subTabContentSlideOffset"
            to: 0
            duration: Appearance.animationsEnabled ? Math.max(130, Appearance.animation.elementMoveFast.duration) : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    function triggerSubTabContentTransition(direction: int) {
        if (!Appearance.animationsEnabled || root.embedded)
            return
        subTabContentAnim.stop()
        root._subTabContentOpacity = 0.45
        root._subTabContentSlideOffset = (direction >= 0 ? 1 : -1) * 14
        subTabContentAnim.start()
    }

    function animateSubTabFrom(fromIndex: int, direction: int) {
        if (!Appearance.animationsEnabled || root.embedded)
            return
        if (fromIndex >= 0 && fromIndex !== root._activeSubTabIndex) {
            root._subTabAnimFromIndex = fromIndex
            Qt.callLater(function() {
                activeSubTabPill.snapFromIndex(fromIndex)
                root._subTabAnimFromIndex = -1
            })
        }
        triggerSubTabContentTransition(direction)
    }

    function activateSubTabItem(item) {
        if (!item)
            return
        var items = root._subTabItems || []
        var curIdx = root._activeSubTabIndex
        var targetIdx = items.indexOf(item)
        var dir = (targetIdx >= 0 && curIdx >= 0 && targetIdx !== curIdx) ? (targetIdx > curIdx ? 1 : -1) : 1

        if (item.kind === "pageSection") {
            if (item.pageIndex === root.settingsPageIndex) {
                if (targetIdx !== curIdx)
                    root.triggerSubTabContentTransition(dir)
                if (root.hasOwnProperty("activeSection"))
                    root.activeSection = item.value
                if (root.settingsTaskNavigator)
                    root.settingsTaskNavigator.selected(item.value)
                root._savePersistedSection()
                root.contentY = 0
                root._updateCardTabs()
                root._scheduleCardTabsUpdate()
            } else if (item.pageIndex >= 0) {
                root.pageSectionNavigationRequested(item.pageIndex, item.value)
            }
        } else if (item.kind === "siblingPage") {
            if (item.pageIndex >= 0 && item.pageIndex !== root.settingsPageIndex) {
                root.pageNavigationRequested(item.pageIndex)
            } else {
                if (targetIdx !== curIdx)
                    root.triggerSubTabContentTransition(dir)
                root.contentY = 0
                root._updateCardTabs()
                root._scheduleCardTabsUpdate()
            }
        } else if (item.kind === "task") {
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir)
            if (root.settingsTaskNavigator)
                root.settingsTaskNavigator.selected(item.value)
            root._savePersistedSection()
            root.contentY = 0
            root._updateCardTabs()
            root._scheduleCardTabsUpdate()
        } else if (item.kind === "cardPage") {
            if (targetIdx !== curIdx)
                root.triggerSubTabContentTransition(dir)
            root.selectCardSubTab(item.value)
            root._savePersistedSection()
            root._updateCardTabs()
            root._scheduleCardTabsUpdate()
        }
    }

    function stepSubTab(direction: int) {
        var items = root._subTabItems || []
        if (items.length <= 1 || direction === 0)
            return
        var cur = root._activeSubTabIndex
        var next = cur + (direction > 0 ? 1 : -1)
        if (next < 0 || next >= items.length)
            return
        root.activateSubTabItem(items[next])
    }

    function _handleSubTabWheel(wheelEvent, allowVertical: bool) {
        var items = root._subTabItems || []
        if (items.length <= 1)
            return
        var dx = wheelEvent.angleDelta.x
        var dy = wheelEvent.angleDelta.y
        if (Math.abs(dx) < 1 || Math.abs(dx) <= Math.abs(dy)) {
            root._wheelDeltaAccum = 0
            return
        }
        var now = Date.now()
        if (now - root._lastSubTabWheelMs < 150) {
            wheelEvent.accepted = true
            return
        }
        root._wheelDeltaAccum += dx
        if (Math.abs(root._wheelDeltaAccum) >= 30) {
            var dir = root._wheelDeltaAccum < 0 ? 1 : -1
            root._wheelDeltaAccum = 0
            root._lastSubTabWheelMs = now
            root.stepSubTab(dir)
            wheelEvent.accepted = true
        }
    }

    function syncTaskNavigatorSelection(val) {
        root.activeCardSubTab = ""
        root.contentY = 0
        root._scheduleCardTabsUpdate()
    }

    function selectTaskOptionFromDrillDown(val) {
        if (!root.settingsTaskNavigator)
            return
        root.settingsTaskNavigator.selected(val)
        root.syncTaskNavigatorSelection(val)
    }

    function selectCardSubTabFromDrillDown(key, title, icon) {
        if (!key)
            return
        root.activeCardSubTab = key
        root.contentY = 0
        root._updateCardTabs()
    }

    function exitSubView() {
        root.isSubViewActive = false
        root.activeSubViewTitle = ""
        root.activeSubViewIcon = ""
        root.activeCardSubTab = ""
        root.contentY = 0
        root._updateCardTabs()
    }

    function registerContentSection(sec) {
        if (root._isDestroying || !sec || _registeredContentSections.indexOf(sec) >= 0)
            return
        var next = _registeredContentSections.slice()
        next.push(sec)
        _registeredContentSections = next
        _scheduleCardTabsUpdate()
    }

    function unregisterContentSection(sec) {
        if (root._isDestroying)
            return
        var idx = _registeredContentSections.indexOf(sec)
        if (idx < 0)
            return
        var next = _registeredContentSections.slice()
        next.splice(idx, 1)
        _registeredContentSections = next
        _scheduleCardTabsUpdate()
    }

    function registerCardSection(card) {
        if (root._isDestroying || !card || _registeredCards.indexOf(card) >= 0)
            return
        var next = _registeredCards.slice()
        next.push(card)
        _registeredCards = next
        _scheduleCardTabsUpdate()
    }

    function unregisterCardSection(card) {
        if (root._isDestroying)
            return
        var idx = _registeredCards.indexOf(card)
        if (idx < 0)
            return
        var next = _registeredCards.slice()
        next.splice(idx, 1)
        _registeredCards = next
        _scheduleCardTabsUpdate()
    }

    function notifyCardEligibilityChanged() {
        if (root._isDestroying)
            return
        _scheduleCardTabsUpdate()
    }

    function _scheduleBentoHeightSync() {}

    Timer {
        id: cardTabsUpdateTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root._isDestroying)
                return
            root._cardTabsUpdateScheduled = false
            root._updateCardTabs()
        }
    }

    function _scheduleCardTabsUpdate() {
        if (root._isDestroying || root.embedded || _cardTabsUpdateScheduled)
            return
        _cardTabsUpdateScheduled = true
        cardTabsUpdateTimer.restart()
    }

    function selectCardSubTab(key) {
        if (!key || activeCardSubTab === key)
            return
        activeCardSubTab = key
        root.contentY = 0
        _updateCardTabs()
    }

    function selectCardSection(card) {
        if (!card)
            return
        if (card.settingsTaskSection && root._hasTaskNavigatorTabs)
            root.selectTaskOptionFromDrillDown(card.settingsTaskSection)
        root.contentY = 0
        _updateCardTabs()
    }

    function _isInsideCardSection(item) {
        var p = item ? item.parent : null
        while (p && p !== root) {
            if (p.hasOwnProperty("bentoColumn") && p.hasOwnProperty("showHeader"))
                return true
            p = p.parent
        }
        return false
    }

    function _syncIrisSectionGroups() {
        if (root._isDestroying || root.embedded) {
            root.irisSectionGroups = []
            return
        }
        var items = []
        var cards = root._eligibleCards || []
        for (var i = 0; i < cards.length; i++) {
            var c = cards[i]
            if (c && c.visible && c.showHeader && c.title && String(c.title).trim().length > 0)
                items.push(c)
        }
        var secs = root._registeredContentSections || []
        for (var j = 0; j < secs.length; j++) {
            var s = secs[j]
            if (s && s.visible && s.title && String(s.title).trim().length > 0 && !_isInsideCardSection(s))
                items.push(s)
        }
        var total = items.length
        var groups = []
        for (var k = 0; k < total; k++) {
            var it = items[k]
            var num = k + 1
            if (it.irisSectionNumber !== undefined)
                it.irisSectionNumber = num
            if (it.irisSectionTotal !== undefined)
                it.irisSectionTotal = total
            var titleStr = String(it.title || "").trim()
            groups.push({
                index: num,
                title: titleStr,
                key: String(it._cardSubTabKey || titleStr || ("sec-" + k)),
                icon: String(it.icon || ""),
                targetItem: it
            })
        }
        root.irisSectionGroups = groups
        root._irisGeometryRevision++
    }

    function scrollToIrisSection(titleOrKey): bool {
        var needle = String(titleOrKey ?? "").trim()
        if (!needle || root.embedded)
            return false
        var lower = needle.toLowerCase()
        var groups = root.irisSectionGroups || []
        var match = null
        for (var i = 0; i < groups.length; i++) {
            var g = groups[i]
            if (!g) continue
            if (String(g.key || "").toLowerCase() === lower || String(g.title || "").toLowerCase() === lower) {
                match = g
                break
            }
        }
        if (!match) {
            for (var j = 0; j < groups.length; j++) {
                var gj = groups[j]
                if (!gj) continue
                if (String(gj.title || "").toLowerCase().indexOf(lower) >= 0) {
                    match = gj
                    break
                }
            }
        }
        if (!match || !match.targetItem || !match.targetItem.visible)
            return false
        var mapped = match.targetItem.mapToItem(contentColumn, 0, 0)
        var targetY = Math.max(0, contentColumn.y + (mapped ? mapped.y : 0) - 10)
        var maxY = root.interactive ? Math.max(0, root.contentHeight - root.height) : 0
        root.contentY = Math.min(targetY, maxY)
        return true
    }

    function _isWrapperContainer(item) {
        if (!item)
            return false
        if (item.hasOwnProperty("_preventBentoReparent") && item.hasOwnProperty("_cardSubTabActive"))
            return false
        if (item.hasOwnProperty("sourceComponent") && item.hasOwnProperty("status"))
            return false
        var cls = String(item)
        return cls.indexOf("GridLayout") >= 0 || cls.indexOf("ColumnLayout") >= 0
    }

    function _wrapperHasActiveVisibleChild(item) {
        if (!item || !item.visible)
            return false
        var ch = item.children || []
        for (var i = 0; i < ch.length; i++) {
            var sub = ch[i]
            if (!sub || !sub.visible)
                continue
            if (sub.hasOwnProperty("showTabBar") && sub.hasOwnProperty("options"))
                continue
            if (sub.hasOwnProperty("_cardSubTabActive") && !sub._cardSubTabActive)
                continue
            if (typeof sub.itemAt === "function" && sub.hasOwnProperty("delegate"))
                continue
            if (sub.hasOwnProperty("sourceComponent") && sub.hasOwnProperty("status")) {
                if (sub.active)
                    return true
                continue
            }
            if (_isWrapperContainer(sub)) {
                if (_wrapperHasActiveVisibleChild(sub))
                    return true
                continue
            }
            if (sub.implicitHeight > 0 || sub.height > 0)
                return true
        }
        return false
    }

    function _syncWrapperItem(item) {
        if (!item || !_isWrapperContainer(item))
            return
        var ch = item.children || []
        for (var i = 0; i < ch.length; i++) {
            if (ch[i] && _isWrapperContainer(ch[i]))
                _syncWrapperItem(ch[i])
        }
        if (!root.embedded && !_wrapperHasActiveVisibleChild(item)) {
            item.Layout.preferredHeight = 0
            item.Layout.maximumHeight = 0
        } else {
            item.Layout.preferredHeight = -1
            item.Layout.maximumHeight = 16777215
        }
    }

    function _isActivePageBodyBlock(bItem) {
        if (!bItem || !bItem.visible)
            return false
        if (typeof bItem.itemAt === "function" && bItem.hasOwnProperty("delegate"))
            return false
        if (bItem.hasOwnProperty("showTabBar") && bItem.hasOwnProperty("options"))
            return bItem.implicitHeight > 0
        if (bItem.hasOwnProperty("_cardSubTabActive"))
            return Boolean(bItem._cardSubTabActive) && (bItem.implicitHeight > 0 || bItem.height > 0)
        if (bItem.hasOwnProperty("sourceComponent") && bItem.hasOwnProperty("status"))
            return Boolean(bItem.active) && ((bItem.item && bItem.item.implicitHeight > 0) || bItem.implicitHeight > 0 || bItem.height > 0)
        if (_isWrapperContainer(bItem))
            return _wrapperHasActiveVisibleChild(bItem)
        return bItem.implicitHeight > 0 || bItem.height > 0
    }

    function _syncPageBodyWrappers() {
        var ch = pageBodyColumn.children || []
        for (var i = 0; i < ch.length; i++) {
            var item = ch[i]
            if (!item || !_isWrapperContainer(item))
                continue
            _syncWrapperItem(item)
        }
        var activeBlocks = []
        for (var j = 0; j < ch.length; j++) {
            if (_isActivePageBodyBlock(ch[j]))
                activeBlocks.push(ch[j])
        }
        var gap = SettingsMaterialPreset.pageSpacing
        for (var k = 0; k < ch.length; k++) {
            var blk = ch[k]
            if (!blk)
                continue
            var aIdx = activeBlocks.indexOf(blk)
            var hasNext = (aIdx >= 0 && aIdx < activeBlocks.length - 1)
            var nextTopMargin = (hasNext && activeBlocks[aIdx + 1] && activeBlocks[aIdx + 1].Layout)
                ? (Number(activeBlocks[aIdx + 1].Layout.topMargin) || 0)
                : 0
            if (blk.hasOwnProperty("_hasNextActiveCard")) {
                blk._hasNextActiveCard = hasNext && (nextTopMargin < gap)
            } else if (blk.Layout !== undefined) {
                var desiredBottom = hasNext ? Math.max(0, gap - Math.max(0, nextTopMargin)) : 0
                if (Math.abs((Number(blk.Layout.bottomMargin) || 0) - desiredBottom) > 0.5)
                    blk.Layout.bottomMargin = desiredBottom
            }
        }
    }

    function _updateCardTabs() {
        if (root.embedded || root._isDestroying)
            return
        root._initialCardTabsSynced = true

        var aliveCards = []
        for (var r = 0; r < _registeredCards.length; r++) {
            var rcItem = _registeredCards[r]
            if (rcItem && rcItem.parent && typeof rcItem.isCardEligibleForTabs === "function")
                aliveCards.push(rcItem)
        }
        if (aliveCards.length !== _registeredCards.length)
            _registeredCards = aliveCards

        var eligible = []
        for (var i = 0; i < _registeredCards.length; i++) {
            var c = _registeredCards[i]
            if (!c)
                continue
            if (!(c.showHeader || c.allowEditWithoutHeader) || !c.title || c.title.length === 0) {
                c._cardSubTabActive = true
                c._hasNextActiveCard = false
                continue
            }
            var isElig = c.isCardEligibleForTabs()
            c._cardSubTabActive = isElig
            if (isElig) {
                c._cardSubTabKey = String(c.title || ("card_" + i))
                if (!c.expanded)
                    c.expanded = true
                eligible.push(c)
            } else {
                c._hasNextActiveCard = false
            }
        }

        _eligibleCards = eligible
        _cardPages = eligible.length > 0 ? [eligible] : []
        _cardPageOptions = []
        activeCardItem = eligible.length > 0 ? eligible[0] : null
        activeCardSubTab = activeCardItem ? activeCardItem._cardSubTabKey : ""

        _syncPageBodyWrappers()
        _syncIrisSectionGroups()
    }

    onEmbeddedChanged: {
        if (embedded) {
            cardTabsUpdateTimer.stop()
            _cardTabsUpdateScheduled = false
            for (var i = 0; i < _registeredCards.length; i++) {
                var c = _registeredCards[i]
                if (c) {
                    c._bentoExtraHeight = 0
                    c._cardSubTabActive = true
                    c._hasNextActiveCard = false
                }
            }
            _syncPageBodyWrappers()
        } else {
            _updateCardTabs()
            _scheduleCardTabsUpdate()
        }
    }

    onVisibleChanged: {
        if (visible && !embedded) {
            _updateCardTabs()
            _scheduleCardTabsUpdate()
        }
    }

    on_HasTaskNavigatorTabsChanged: if (!embedded) _scheduleCardTabsUpdate()
    onCategorySiblingPagesChanged: if (!embedded) _scheduleCardTabsUpdate()
    onHeightChanged: root._clampScrollPosition()

    on_ActiveSubTabIndexChanged: {
        Qt.callLater(() => {
            if (!root._isDestroying && subTabFlickable && typeof subTabFlickable.ensureActiveVisible === "function")
                subTabFlickable.ensureActiveVisible()
        })
    }

    clip: !embedded
    showVerticalScrollBar: false
    readonly property bool overflowsViewport: !root.embedded
        && root.height > 80
        && (contentColumn.implicitHeight + root.bottomContentPadding + 20 > root.height + 2)
    interactive: !embedded && pageScrollEnabled && root.overflowsViewport

    property bool _clampingScroll: false
    function _clampScrollPosition() {
        if (root.embedded || root._clampingScroll)
            return
        root._clampingScroll = true
        if (!root.interactive) {
            if (Math.abs(root.contentY) > 0.5) {
                root.scrollTargetY = 0
                root.contentY = 0
            }
            root._clampingScroll = false
            return
        }
        var maxY = Math.max(0, root.contentHeight - root.height)
        if (root.contentY > maxY + 0.5) {
            root.scrollTargetY = maxY
            root.contentY = maxY
        } else if (root.contentY < -0.5) {
            root.scrollTargetY = 0
            root.contentY = 0
        }
        root._clampingScroll = false
    }

    onInteractiveChanged: root._clampScrollPosition()
    onContentHeightChanged: {
        root._clampScrollPosition()
        root._irisGeometryRevision++
    }
    onContentYChanged: {
        if (!root.embedded && !root.interactive && !root._clampingScroll && Math.abs(root.contentY) > 0.5)
            root._clampScrollPosition()
    }

    implicitHeight: embedded ? contentColumn.implicitHeight : 0
    Layout.preferredHeight: embedded ? contentColumn.implicitHeight : -1
    Layout.maximumHeight: embedded && contentColumn.implicitHeight <= 0 ? 0 : -1
    contentHeight: (!embedded && pageScrollEnabled && root.overflowsViewport)
        ? Math.max(height + 1, contentColumn.implicitHeight + root.bottomContentPadding + 24)
        : (root.embedded ? contentColumn.implicitHeight + root.bottomContentPadding : height)
    implicitWidth: embedded ? 0 : contentColumn.implicitWidth

    readonly property real maxContentWidth: Math.round((SettingsMaterialPreset.waffle ? 1280 : 1080) * Appearance.fontSizeScale)
    readonly property real _horizontalMargin: {
        if (root.embedded) return 0
        const w = root.width
        if (SettingsMaterialPreset.waffle) {
            if (w > 900) return 28
            if (w > 640) return 20
            return 14
        }
        if (w > maxContentWidth + 36) return Math.round((w - maxContentWidth) / 2)
        if (w > 760) return 18
        if (w > 540) return 14
        return 10
    }
    readonly property real _rightHorizontalMargin: {
        if (root.embedded || !SettingsMaterialPreset.waffle)
            return root._horizontalMargin
        const w = root.width
        return Math.max(root._horizontalMargin, Math.round(w - root._horizontalMargin - maxContentWidth))
    }

    // Horizontal wheel/touchpad scroll anywhere on the page switches sub-tabs
    WheelHandler {
        id: pageHorizontalWheelHandler
        enabled: !root.embedded && root._subTabItems.length > 1
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root._handleSubTabWheel(event, false)
    }

    Item {
        id: contentColumn
        objectName: "contentColumn"
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.embedded ? 0 : (SettingsMaterialPreset.waffle ? 4 : 10)
            bottomMargin: root.embedded ? 0 : 12
            leftMargin: root._horizontalMargin
            rightMargin: root._rightHorizontalMargin
        }
        readonly property real spacing: root.embedded ? 0 : SettingsMaterialPreset.pageSpacing
        readonly property real _yAfterNav: (navigatorHeaderHost.visible && navigatorHeaderHost.height > 0)
            ? (navigatorHeaderHost.height + spacing)
            : 0
        readonly property real _yAfterSubTabs: (subTabBarContainer.visible && subTabBarContainer.height > 0)
            ? (_yAfterNav + subTabBarContainer.height + spacing)
            : _yAfterNav
        readonly property real _yEnd: (pageBodyColumn.visible && pageBodyColumn.activeBodyImplicitHeight > 0)
            ? (_yAfterSubTabs + pageBodyColumn.activeBodyImplicitHeight)
            : (_yAfterSubTabs > 0 ? (_yAfterSubTabs - spacing) : 0)
        implicitWidth: Math.max(subTabBarContainer.implicitWidth, pageBodyColumn.implicitWidth)
        implicitHeight: _yEnd
        height: implicitHeight

        ColumnLayout {
            id: navigatorHeaderHost
            objectName: "navigatorHeaderHost"
            x: 0
            y: 0
            width: contentColumn.width
            height: visible ? implicitHeight : 0
            spacing: 0
            visible: false
        }

        // Sleek centered segmented sub-tab bar
        Item {
            id: subTabBarContainer
            objectName: "settingsSubTabBarContainer"
            visible: !root.embedded && root._subTabItems.length > 1
            x: 0
            y: contentColumn._yAfterNav
            width: contentColumn.width
            readonly property int trackHeight: Math.round(38 * Appearance.fontSizeScale)
            readonly property int pillHeight: Math.round(30 * Appearance.fontSizeScale)
            implicitHeight: visible ? trackHeight : 0
            height: implicitHeight

            Rectangle {
                id: subTabTrack
                objectName: "settingsSectionTabTrack"
                x: SettingsMaterialPreset.waffle ? 0 : Math.round((parent.width - width) / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width, subTabRow.implicitWidth + (SettingsMaterialPreset.waffle ? 0 : 8))
                height: subTabBarContainer.trackHeight
                radius: SettingsMaterialPreset.waffle ? 6 : Math.round(height / 2)
                color: SettingsMaterialPreset.waffle ? "transparent" : SettingsMaterialPreset.cardColor
                border.width: SettingsMaterialPreset.waffle ? 0 : 1
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
                    anchors.margins: SettingsMaterialPreset.waffle ? 0 : 4
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
                            contentX = 0
                            return
                        }
                        var idx = root._activeSubTabIndex
                        var btn = subTabRepeater.itemAt(idx)
                        if (!btn)
                            return
                        var targetX = btn.x + btn.width / 2 - width / 2
                        contentX = Math.max(0, Math.min(contentWidth - width, targetX))
                    }

                    onWidthChanged: Qt.callLater(ensureActiveVisible)

                    Rectangle {
                        id: activeSubTabPill
                        readonly property int pillIndex: root._subTabAnimFromIndex >= 0
                            ? root._subTabAnimFromIndex
                            : root._activeSubTabIndex
                        readonly property Item activeBtn: {
                            void subTabRepeater.delegateRevision
                            return subTabRepeater.itemAt(pillIndex)
                        }
                        property bool animReady: true

                        function snapFromIndex(fromIdx: int) {
                            var fromBtn = subTabRepeater.itemAt(fromIdx)
                            if (!fromBtn)
                                return
                            animReady = false
                            x = subTabRow.x + fromBtn.x
                            width = fromBtn.width
                            animReady = true
                            var toBtn = subTabRepeater.itemAt(root._activeSubTabIndex)
                            if (toBtn) {
                                x = Qt.binding(function() { return activeSubTabPill.activeBtn ? subTabRow.x + activeSubTabPill.activeBtn.x : 0 })
                                width = Qt.binding(function() { return activeSubTabPill.activeBtn ? activeSubTabPill.activeBtn.width : 0 })
                            }
                        }

                        visible: activeBtn !== null && activeBtn !== undefined && width > 0
                        x: activeBtn ? subTabRow.x + activeBtn.x : 0
                        y: (parent.height - height) / 2
                        width: activeBtn ? activeBtn.width : 0
                        height: subTabBarContainer.pillHeight
                        radius: SettingsMaterialPreset.waffle ? 6 : Math.round(height / 2)
                        color: SettingsMaterialPreset.waffle
                            ? SettingsMaterialPreset.navSelectedColor
                            : SettingsMaterialPreset.pillSelectedColor
                        border.width: SettingsMaterialPreset.waffle ? 0 : 1
                        border.color: SettingsMaterialPreset.accentBorder

                        Rectangle {
                            objectName: "waffleSettingsTabIndicator"
                            visible: SettingsMaterialPreset.waffle
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: Math.max(16, Math.min(28, Math.round(parent.width * 0.45)))
                            height: 3
                            radius: 1.5
                            color: SettingsMaterialPreset.accentColor
                        }

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
                        x: SettingsMaterialPreset.waffle ? 0 : Math.max(0, (subTabFlickable.width - implicitWidth) / 2)
                        height: parent.height
                        spacing: SettingsMaterialPreset.waffle ? 6 : 4

                        Repeater {
                            id: subTabRepeater
                            property int delegateRevision: 0
                            onItemAdded: delegateRevision++
                            onItemRemoved: delegateRevision++
                            model: root._subTabItems

                            delegate: RippleButton {
                                id: subTabButton
                                objectName: "settingsSubTab_" + index
                                required property int index
                                required property var modelData
                                readonly property bool isCurrent: Boolean(modelData.active)

                                implicitHeight: subTabBarContainer.pillHeight
                                implicitWidth: tabPillContent.implicitWidth + 24
                                anchors.verticalCenter: parent.verticalCenter
                                buttonRadius: SettingsMaterialPreset.waffle ? 6 : Math.round(implicitHeight / 2)
                                toggled: isCurrent
                                colBackground: "transparent"
                                colBackgroundHover: SettingsMaterialPreset.headerHoverColor
                                colBackgroundToggled: activeSubTabPill.visible ? "transparent" : SettingsMaterialPreset.navSelectedColor
                                colBackgroundToggledHover: SettingsMaterialPreset.waffle
                                    ? SettingsMaterialPreset.navSelectedHoverColor
                                    : Qt.alpha(Appearance.colors.colPrimaryContainerHover, 0.35)
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
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: subTabButton.modelData.icon || "tune"
                                            iconSize: 15
                                            color: SettingsMaterialPreset.waffle
                                                ? SettingsMaterialPreset.textColor
                                                : (subTabButton.isCurrent
                                                    ? SettingsMaterialPreset.pillSelectedTextColor
                                                    : SettingsMaterialPreset.navigationIconColor(
                                                        subTabButton.index,
                                                        Math.max(1, root._subTabItems.length),
                                                        false))
                                        }

                                        StyledText {
                                            id: subTabLabel
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: subTabButton.modelData.title || ""
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.family: SettingsMaterialPreset.fontFamily
                                            font.weight: subTabButton.isCurrent ? Font.DemiBold : Font.Medium
                                            color: SettingsMaterialPreset.waffle
                                                ? SettingsMaterialPreset.textColor
                                                : (subTabButton.isCurrent
                                                    ? SettingsMaterialPreset.pillSelectedTextColor
                                                    : SettingsMaterialPreset.textColor)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: pageBodyColumn
            objectName: "pageBodyColumn"
            visible: true
            x: 0
            y: contentColumn._yAfterSubTabs
            width: contentColumn.width
            readonly property real activeBodyImplicitHeight: {
                var bodyCh = pageBodyColumn.children || []
                var bodyH = 0
                var bodyCount = 0
                for (var bi = 0; bi < bodyCh.length; bi++) {
                    var bItem = bodyCh[bi]
                    if (!bItem || !bItem.visible || bItem.implicitHeight <= 0)
                        continue
                    if (bItem.hasOwnProperty("showTabBar") && bItem.hasOwnProperty("options"))
                        continue
                    if (root._isWrapperContainer(bItem) && !root._wrapperHasActiveVisibleChild(bItem))
                        continue
                    bodyH += (bodyCount > 0 ? pageBodyColumn.spacing : 0) + bItem.implicitHeight
                    bodyCount++
                }
                return bodyH
            }
            Layout.minimumWidth: 0
            spacing: 0
            opacity: root._subTabContentOpacity
            transform: Translate {
                x: root._subTabContentSlideOffset
            }
        }
    }
}
