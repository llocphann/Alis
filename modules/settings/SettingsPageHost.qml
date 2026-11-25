pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "SettingsPageLoadingState.js" as PageLoadState

Item {
    id: root

    required property var pages
    required property int requestedIndex
    property bool loadEnabled: true
    property bool backgroundWarmup: false
    property int cacheLimit: (Config.options?.performance?.lowPower ?? false) ? 2 : 6

    signal pageNavigationRequested(int pageIndex)

    property int _pendingSectionPageIndex: -1
    property string _pendingSection: ""

    function _activateSectionOnItem(item, sectionValue: string): void {
        if (!item || !sectionValue || sectionValue.length === 0)
            return
        if (item.hasOwnProperty("_persistedSectionRestored"))
            item._persistedSectionRestored = true
        if (typeof item.activateSettingsSearchSection === "function")
            item.activateSettingsSearchSection(sectionValue)
        else if (item.hasOwnProperty("activeSection"))
            item.activeSection = sectionValue
        if (item.settingsTaskNavigator && typeof item.settingsTaskNavigator.selected === "function")
            item.settingsTaskNavigator.selected(sectionValue)
        if (typeof item._savePersistedSection === "function")
            item._savePersistedSection()
        if (typeof item._updateCardTabs === "function" && !item.embedded)
            item._updateCardTabs()
        if (typeof item._scheduleCardTabsUpdate === "function")
            item._scheduleCardTabsUpdate()
        if (typeof item.scrollToIrisSection === "function")
            Qt.callLater(() => { if (item) item.scrollToIrisSection(sectionValue) })
    }

    function _applySectionToPage(targetPageIndex: int, targetSection: string): void {
        root._pendingSectionPageIndex = targetPageIndex
        root._pendingSection = targetSection
        const loader = root._loaderFor(targetPageIndex)
        if (loader && loader.item) {
            root._activateSectionOnItem(loader.item, targetSection)
            root._pendingSectionPageIndex = -1
            root._pendingSection = ""
        }
    }

    function _siblingPagesForIndex(pageIdx: int): var {
        const cats = SettingsPageRegistry.defaultCategories ?? []
        for (let i = 0; i < cats.length; i++) {
            const cPages = (cats[i]?.pages ?? []).filter(
                idx => root.pages[idx] && SettingsPageRegistry.isPageApplicable(idx))
            if (cPages.length > 1 && cPages.includes(pageIdx)) {
                return cPages.map(idx => Object.assign({}, root.pages[idx], { realIndex: idx }))
            }
        }
        return []
    }

    readonly property int currentIndex: _currentIndex
    readonly property bool error: _errorIndex === requestedIndex
    readonly property Item currentItem: {
        void(_statusRevision)
        const loader = _loaderFor(_currentIndex)
        return loader?.item ?? null
    }
    readonly property bool loading: {
        return PageLoadState.shouldShow(
            loadEnabled, requestedIndex, pages.length,
            _sourceFor(requestedIndex) !== "",
            _errorIndex, _currentIndex, _pageStatuses[_currentIndex] ?? Loader.Null,
            _pendingIndex, _pageStatuses[_pendingIndex] ?? Loader.Null, Loader.Ready)
    }

    property int _currentIndex: -1
    property int _pendingIndex: -1
    property int _direction: 1
    property bool _transitionRunning: false
    property var _retainedIndices: []
    property var _lruIndices: []
    property var _pageStatuses: ({})
    property int _statusRevision: 0
    property int _errorIndex: -1
    property int _requestGeneration: 0

    clip: _transitionRunning

    function _sourceFor(index) {
        if (index < 0 || index >= pages.length)
            return ""
        const source = pages[index]?.component ?? ""
        if (source.startsWith("/"))
            return "file://" + source
        return source
    }

    // Fixed small pool of reusable Loader slots instead of instantiating ~45
    // Loaders + Connections upfront on first Settings open. Constant pool size
    // ensures changing cacheLimit (e.g. toggling lowPower) never destroys the
    // currently visible slot via Repeater model resizing.
    readonly property int _slotPoolSize: 8

    function _loaderFor(index) {
        if (index < 0 || index >= pages.length)
            return null
        for (let i = 0; i < pageRepeater.count; i++) {
            const slot = pageRepeater.itemAt(i)
            if (slot && slot.pageIndex === index)
                return slot
        }
        return null
    }

    function _syncResidency() {
        const retained = loadEnabled ? _retainedIndices : []
        let statusesChanged = false
        let nextStatuses = null
        // Release evicted or disabled slots first so they become reusable immediately.
        for (let i = 0; i < pageRepeater.count; i++) {
            const slot = pageRepeater.itemAt(i)
            if (!slot)
                continue
            if (slot.pageIndex >= 0 && retained.indexOf(slot.pageIndex) < 0) {
                const oldIdx = slot.pageIndex
                if (!nextStatuses)
                    nextStatuses = Object.assign({}, _pageStatuses)
                nextStatuses[oldIdx] = Loader.Null
                statusesChanged = true
                slot.pageIndex = -1
                slot.opacity = 0
                slot.x = 0
            }
        }
        if (statusesChanged) {
            _pageStatuses = nextStatuses
            _statusRevision++
        }
        if (!loadEnabled)
            return
        // Assign a free pool slot to every retained page index that lacks one.
        for (let r = 0; r < retained.length; r++) {
            const targetIdx = retained[r]
            if (targetIdx < 0 || targetIdx >= pages.length || _loaderFor(targetIdx) !== null)
                continue
            for (let i = 0; i < pageRepeater.count; i++) {
                const slot = pageRepeater.itemAt(i)
                if (slot && slot.pageIndex < 0) {
                    slot.pageIndex = targetIdx
                    break
                }
            }
        }
    }

    function _retain(index) {
        if (index < 0)
            return

        let retained = _retainedIndices.slice()
        let lru = _lruIndices.filter(value => value !== index)
        if (retained.indexOf(index) < 0) {
            // Never allow retained indices to exceed the fixed slot pool; evict
            // oldest non-active LRU slots first so rapid switching across >8
            // pages always receives a free Loader slot and never deadlocks.
            const maxPool = Math.max(2, root._slotPoolSize)
            while (retained.length >= maxPool) {
                let evictIndex = -1
                for (let i = 0; i < lru.length; i++) {
                    const candidate = lru[i]
                    if (candidate !== _currentIndex
                            && candidate !== _pendingIndex
                            && candidate !== requestedIndex
                            && candidate !== index) {
                        evictIndex = candidate
                        lru.splice(i, 1)
                        break
                    }
                }
                if (evictIndex < 0)
                    break
                retained = retained.filter(value => value !== evictIndex)
            }
            retained.push(index)
            _retainedIndices = retained
        }

        lru.push(index)
        _lruIndices = lru
        _syncResidency()
    }

    function _trimCache() {
        const limit = Math.min(root._slotPoolSize, Math.max(2, cacheLimit))
        let retained = _retainedIndices.slice()
        let lru = _lruIndices.slice()

        while (retained.length > limit) {
            let evictIndex = -1
            for (let i = 0; i < lru.length; i++) {
                const candidate = lru[i]
                if (candidate !== _currentIndex
                        && candidate !== _pendingIndex
                        && candidate !== requestedIndex) {
                    evictIndex = candidate
                    lru.splice(i, 1)
                    break
                }
            }

            if (evictIndex < 0)
                break
            retained = retained.filter(value => value !== evictIndex)
        }

        _retainedIndices = retained
        _lruIndices = lru.filter(value => retained.indexOf(value) >= 0)
        _syncResidency()
    }

    function _reset() {
        _requestGeneration++
        switchAnimation.stop()
        _transitionRunning = false
        _currentIndex = -1
        _pendingIndex = -1
        _retainedIndices = []
        _lruIndices = []
        _errorIndex = -1
        _syncResidency()
        _statusRevision++
    }

    function _scheduleRequestPage() {
        const generation = ++_requestGeneration
        Qt.callLater(function() {
            if (generation !== root._requestGeneration)
                return
            root._requestPage(generation)
        })
    }

    function _requestPage(generation) {
        if (generation !== undefined
                && generation !== root._requestGeneration)
            return
        if (!loadEnabled || requestedIndex < 0 || requestedIndex >= pages.length)
            return

        if (_transitionRunning) {
            switchAnimation.complete()
            if (generation !== undefined
                    && generation !== root._requestGeneration)
                return
        }

        if (_currentIndex < 0) {
            _currentIndex = requestedIndex
            _errorIndex = -1
            _retain(_currentIndex)
            _trimCache()
            const loader = _loaderFor(_currentIndex)
            if (loader) {
                loader.opacity = 1
                loader.x = 0
            }
            return
        }

        if (requestedIndex === _currentIndex) {
            if (_errorIndex === requestedIndex) {
                _errorIndex = -1
                _retain(_currentIndex)
            }
            _retain(_currentIndex)
            _trimCache()
            return
        }

        if (_pendingIndex >= 0) {
            const stalePending = _loaderFor(_pendingIndex)
            if (stalePending) {
                stalePending.opacity = 0
                stalePending.x = 0
            }
        }

        _direction = requestedIndex >= _currentIndex ? 1 : -1
        _pendingIndex = requestedIndex
        _errorIndex = -1

        _retain(_pendingIndex)
        _trimCache()
        const pendingLoader = _loaderFor(_pendingIndex)
        if (pendingLoader) {
            pendingLoader.opacity = 0
            pendingLoader.x = _direction * Appearance.sizes.spacingMedium * 2
        }

        const pendingIndex = _pendingIndex
        const pendingGeneration = _requestGeneration
        Qt.callLater(function() {
            if (pendingGeneration !== root._requestGeneration
                    || pendingIndex !== root._pendingIndex)
                return
            const loader = root._loaderFor(pendingIndex)
            if (loader)
                root._handleStatus(pendingIndex, loader.status)
        })
    }

    function _handleStatus(index, status) {
        if (index < 0)
            return
        const statuses = Object.assign({}, _pageStatuses)
        statuses[index] = status
        _pageStatuses = statuses
        _statusRevision++

        if (status === Loader.Error && (index === _currentIndex || index === _pendingIndex)) {
            console.warn("SettingsPageHost: failed to load page", index, _sourceFor(index))
            _errorIndex = index
            if (index === _pendingIndex)
                _pendingIndex = -1

            _retainedIndices = _retainedIndices.filter(value => value !== index)
            _lruIndices = _lruIndices.filter(value => value !== index)
            _syncResidency()
            return
        }

        if (index === _currentIndex && _pendingIndex < 0 && status === Loader.Ready) {
            if (_errorIndex === index)
                _errorIndex = -1
            const currentLoader = _loaderFor(index)
            if (currentLoader) {
                currentLoader.opacity = 1
                currentLoader.x = 0
            }
            return
        }

        if (index !== _pendingIndex || _transitionRunning)
            return

        if (status !== Loader.Ready)
            return

        if (_pendingIndex !== requestedIndex) {
            const staleLoader = _loaderFor(_pendingIndex)
            if (staleLoader) {
                staleLoader.opacity = 0
                staleLoader.x = 0
            }
            _pendingIndex = -1
            root._scheduleRequestPage()
            return
        }

        if (!Appearance.animationsEnabled || Appearance.animation.elementMoveFast.duration <= 0) {
            _finishSwap()
            return
        }

        const currentLoader = _loaderFor(_currentIndex)
        const pendingLoader = _loaderFor(_pendingIndex)
        if (!currentLoader || !pendingLoader) {
            _finishSwap()
            return
        }

        currentFade.target = currentLoader
        pendingFade.target = pendingLoader
        pendingSlide.target = pendingLoader
        _transitionRunning = true
        switchAnimation.start()
    }

    property int _pendingFromSubTabIndex: -1

    function _finishSwap() {
        if (_pendingIndex < 0)
            return

        const oldIndex = _currentIndex
        const nextIndex = _pendingIndex
        const oldLoader = _loaderFor(oldIndex)
        const nextLoader = _loaderFor(nextIndex)

        if (oldLoader) {
            oldLoader.opacity = 0
            oldLoader.x = 0
        }
        if (nextLoader) {
            nextLoader.opacity = 1
            nextLoader.x = 0
        }

        _currentIndex = nextIndex
        _pendingIndex = -1
        _transitionRunning = false
        _retain(_currentIndex)
        _trimCache()

        if (nextIndex === _pendingSectionPageIndex && _pendingSection.length > 0 && nextLoader && nextLoader.item) {
            _activateSectionOnItem(nextLoader.item, _pendingSection)
            _pendingSectionPageIndex = -1
            _pendingSection = ""
        }

        if (_pendingFromSubTabIndex >= 0 && nextLoader && nextLoader.item && typeof nextLoader.item.animateSubTabFrom === "function") {
            const fromSubIdx = _pendingFromSubTabIndex
            _pendingFromSubTabIndex = -1
            const toSubIdx = nextLoader.item._activeSubTabIndex ?? 0
            const dir = toSubIdx >= fromSubIdx ? 1 : -1
            nextLoader.item.animateSubTabFrom(fromSubIdx, dir)
        } else {
            _pendingFromSubTabIndex = -1
        }

        if (requestedIndex !== _currentIndex)
            root._scheduleRequestPage()
    }

    onRequestedIndexChanged: root._scheduleRequestPage()
    onLoadEnabledChanged: {
        if (loadEnabled)
            root._scheduleRequestPage()
        else
            _reset()
    }
    onCacheLimitChanged: _trimCache()
    Component.onCompleted: {
        SettingsArrangement.migrateLegacyPageIndices()
        root._scheduleRequestPage()
    }
    Connections {
        target: Config
        function onReadyChanged(): void {
            if (Config.ready)
                SettingsArrangement.migrateLegacyPageIndices()
        }
    }

    Repeater {
        id: pageRepeater
        model: root._slotPoolSize

        delegate: Loader {
            id: pageLoader
            required property int index
            property int pageIndex: -1
            readonly property var hostSiblingPages: pageIndex >= 0 ? root._siblingPagesForIndex(pageIndex) : []

            anchors.fill: parent
            active: root.loadEnabled && pageIndex >= 0
            source: pageIndex >= 0 ? root._sourceFor(pageIndex) : ""
            asynchronous: pageIndex !== root._currentIndex || root.backgroundWarmup
                || ((Quickshell.env("QT_QUICK_BACKEND") !== "software") && status !== Loader.Ready)
            visible: active && (pageIndex === root._currentIndex || pageIndex === root._pendingIndex)
            enabled: pageIndex === root._currentIndex
                && root._pendingIndex < 0
                && !root._transitionRunning
            z: pageIndex === root._pendingIndex ? 1 : 0

            onStatusChanged: root._handleStatus(pageIndex, status)
            onLoaded: {
                if (item && item.hasOwnProperty("categorySiblingPages"))
                    item.categorySiblingPages = Qt.binding(() => pageLoader.hostSiblingPages)
                if (pageLoader.pageIndex === root._pendingSectionPageIndex && root._pendingSection.length > 0) {
                    root._activateSectionOnItem(item, root._pendingSection)
                    root._pendingSectionPageIndex = -1
                    root._pendingSection = ""
                } else if (item && typeof item._restorePersistedSection === "function") {
                    item._restorePersistedSection()
                }
                if (item && typeof item._updateCardTabs === "function" && !item.embedded && !item._initialCardTabsSynced)
                    item._updateCardTabs()
                if (root.currentItem && root.currentItem !== item && typeof root.currentItem._scheduleCardTabsUpdate === "function")
                    root.currentItem._scheduleCardTabsUpdate()
            }
            Connections {
                target: pageLoader.item && pageLoader.item.hasOwnProperty("categorySiblingPages") ? pageLoader.item : null
                ignoreUnknownSignals: true
                function onPageNavigationRequested(targetPageIndex: int): void {
                    root._pendingFromSubTabIndex = pageLoader.item ? (pageLoader.item._activeSubTabIndex ?? -1) : -1
                    root._pendingSectionPageIndex = -1
                    root._pendingSection = ""
                    root.pageNavigationRequested(targetPageIndex)
                }
                function onPageSectionNavigationRequested(targetPageIndex: int, targetSection: string): void {
                    root._pendingFromSubTabIndex = pageLoader.item ? (pageLoader.item._activeSubTabIndex ?? -1) : -1
                    root._applySectionToPage(targetPageIndex, targetSection)
                    root.pageNavigationRequested(targetPageIndex)
                }
            }
            onActiveChanged: {
                root._statusRevision++
                if (!active) {
                    opacity = 0
                    x = 0
                }
            }
        }

        onItemAdded: (index, item) => {
            root._syncResidency()
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.error
        color: SettingsMaterialPreset.cardColor
        z: 20

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 420)
            spacing: Appearance.sizes.spacingSmall

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "error"
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colError
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("This settings page could not be loaded.")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Check Alis logs for the QML error, then retry after correcting it.")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignHCenter
                materialIcon: "refresh"
                mainText: Translation.tr("Retry")
                onClicked: root._scheduleRequestPage()
            }
        }
    }

    ParallelAnimation {
        id: switchAnimation

        NumberAnimation {
            id: currentFade
            property: "opacity"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            id: pendingFade
            property: "opacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            id: pendingSlide
            property: "x"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }

        onFinished: root._finishSwap()
    }
}
