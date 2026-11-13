pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import "SettingsLayoutPolicy.js" as LayoutPolicy

QtObject {
    id: root

    property bool editMode: false
    property bool innerEditMode: false
    property bool snapEnabled: true
    property int gridSize: 16
    property string gridStyle: "dots" // "dots" | "lines" | "cross" | "off"

    // When non-empty, SettingsPageHost renders the user-created CustomSettingsTabPage
    property string activeCustomTabId: ""
    property string selectedModuleId: ""
    property string openCustomizeModuleId: ""
    property bool moduleDrawerOpen: false
    property string requestedPromptMode: ""
    property string activePromptMode: ""

    // Transactional snapshot captured when entering editMode so Cancel / Escape discards unsaved edits
    property string _editEntrySnapshot: ""
    property string _editEntryCustomTabId: ""

    // Incremented on state changes so QML layout bindings re-evaluate
    property int layoutRevision: 0
    // Incremented on live-card registration/unregistration without invalidating donor-page state bindings
    property int liveCardRevision: 0

    // Undo / Redo history stacks of serialized state strings
    property var _undoStack: []
    property var _redoStack: []
    readonly property bool canUndo: _undoStack.length > 0
    readonly property bool canRedo: _redoStack.length > 0

    // Parsed state object from Config.options.settingsUi.moduleLayout
    readonly property string rawLayoutJson: Config.options?.settingsUi?.moduleLayout ?? ""
    property string _lastCommittedJson: rawLayoutJson
    property var state: LayoutPolicy.parseState(rawLayoutJson)

    onRawLayoutJsonChanged: {
        if (root.rawLayoutJson === root._lastCommittedJson)
            return
        root._lastCommittedJson = root.rawLayoutJson
        root.state = LayoutPolicy.parseState(root.rawLayoutJson)
        root.layoutRevision++
    }

    onEditModeChanged: {
        if (root.editMode) {
            root._editEntrySnapshot = LayoutPolicy.serializeState(root.state)
            root._editEntryCustomTabId = root.activeCustomTabId
            root._undoStack = []
            root._redoStack = []
        } else {
            root.draggingModule = false
            root.draggedModuleId = ""
            root.hoveredDropTarget = null
            root.selectedModuleId = ""
            root.openCustomizeModuleId = ""
            root.moduleDrawerOpen = false
            root.requestedPromptMode = ""
            root.activePromptMode = ""
        }
    }

    function beginEditMode(): void {
        if (!root.editMode)
            root.editMode = true
    }

    function commitEditMode(): void {
        if (!root.editMode)
            return
        root._editEntrySnapshot = LayoutPolicy.serializeState(root.state)
        root._editEntryCustomTabId = root.activeCustomTabId
        root.editMode = false
    }

    function cancelEditMode(): bool {
        if (!root.editMode)
            return false
        const snap = root._editEntrySnapshot
        root._undoStack = []
        root._redoStack = []
        root.draggingModule = false
        root.draggedModuleId = ""
        root.hoveredDropTarget = null
        root.selectedModuleId = ""
        root.openCustomizeModuleId = ""
        root.moduleDrawerOpen = false
        root.requestedPromptMode = ""
        root.activePromptMode = ""
        root.state = LayoutPolicy.parseState(snap)
        root._lastCommittedJson = snap
        Config.setNestedValue("settingsUi.moduleLayout", snap)
        if (root.activeCustomTabId.length > 0 && !root.getCustomTab(root.activeCustomTabId)) {
            root.activeCustomTabId = (root._editEntryCustomTabId && root.getCustomTab(root._editEntryCustomTabId))
                ? root._editEntryCustomTabId
                : ""
        }
        root.editMode = false
        root.layoutRevision++
        return true
    }

    function handleEscape(): bool {
        if (root.activePromptMode.length > 0) {
            root.activePromptMode = ""
            root.requestedPromptMode = ""
            return true
        }
        if (root.openCustomizeModuleId.length > 0) {
            root.openCustomizeModuleId = ""
            return true
        }
        if (root.moduleDrawerOpen) {
            root.moduleDrawerOpen = false
            return true
        }
        if (root.editMode) {
            root.cancelModuleDrag()
            return root.cancelEditMode()
        }
        return false
    }

    function requestInlinePrompt(mode: string): void {
        if (!root.editMode)
            root.editMode = true
        root.activePromptMode = mode
        root.requestedPromptMode = mode
    }

    // Live SettingsCardSection registry: moduleId -> QQuickItem
    property var _liveCardsByModuleId: ({})
    property var _liveCardMetaByModuleId: ({})

    // Global drag state for moving SettingsCardSection modules across cards/columns/tabs
    property bool draggingModule: false
    readonly property bool dragActive: root.draggingModule
    property string draggedModuleId: ""
    property string draggedModuleTitle: ""
    property string draggedModuleIcon: "tune"
    property int draggedOriginPageIndex: -1
    property string draggedOriginSubTab: ""
    property real dragSceneX: 0
    property real dragSceneY: 0
    property real dragCardWidth: 320
    property real dragCardHeight: 140
    property var hoveredDropTarget: null
    readonly property string hoveredDropTargetId: String(root.hoveredDropTarget?.targetId ?? "")

    // Populated by SettingsPageHost so widgets in modules/common/widgets can list pages without circular imports
    property var availablePages: []
    property var availableNavigationPages: []

    // Registered drop targets: targetId -> { item, spec }
    property var _dropTargets: ({})

    function _commitState(nextState, recordUndo): void {
        const currentSerialized = LayoutPolicy.serializeState(root.state)
        const nextSerialized = LayoutPolicy.serializeState(nextState)
        if (currentSerialized === nextSerialized)
            return

        if (recordUndo !== false) {
            const stack = root._undoStack.slice()
            stack.push(currentSerialized)
            if (stack.length > 40)
                stack.shift()
            root._undoStack = stack
            root._redoStack = []
        }

        root.state = LayoutPolicy.parseState(nextState)
        root._lastCommittedJson = nextSerialized
        Config.setNestedValue("settingsUi.moduleLayout", nextSerialized)
        root.layoutRevision++
    }

    function undo(): bool {
        if (root._undoStack.length === 0)
            return false
        const currentSerialized = LayoutPolicy.serializeState(root.state)
        const undoStack = root._undoStack.slice()
        const prevSerialized = undoStack.pop()
        root._undoStack = undoStack

        const redoStack = root._redoStack.slice()
        redoStack.push(currentSerialized)
        root._redoStack = redoStack

        root.state = LayoutPolicy.parseState(prevSerialized)
        root._lastCommittedJson = prevSerialized
        Config.setNestedValue("settingsUi.moduleLayout", prevSerialized)
        root.layoutRevision++
        return true
    }

    function redo(): bool {
        if (root._redoStack.length === 0)
            return false
        const currentSerialized = LayoutPolicy.serializeState(root.state)
        const redoStack = root._redoStack.slice()
        const nextSerialized = redoStack.pop()
        root._redoStack = redoStack

        const undoStack = root._undoStack.slice()
        undoStack.push(currentSerialized)
        root._undoStack = undoStack

        root.state = LayoutPolicy.parseState(nextSerialized)
        root._lastCommittedJson = nextSerialized
        Config.setNestedValue("settingsUi.moduleLayout", nextSerialized)
        root.layoutRevision++
        return true
    }

    function resetAll(): void {
        root._commitState(LayoutPolicy.emptyState(), true)
        root.activeCustomTabId = ""
        root.selectedModuleId = ""
        root.openCustomizeModuleId = ""
        root.moduleDrawerOpen = false
    }

    // --- Live Card Registry ---

    function makeModuleId(originPageIndex: int, title: string, fallbackIndex: int): string {
        return LayoutPolicy.makeModuleId(originPageIndex, title, fallbackIndex)
    }

    function registerLiveCard(moduleId: string, cardItem: Item, meta: var): void {
        if (!moduleId || !cardItem)
            return
        const nextMeta = {
            moduleId: moduleId,
            title: LayoutPolicy.humanizeModuleTitle(meta?.title ?? cardItem.title ?? "", moduleId),
            icon: String(meta?.icon ?? cardItem.icon ?? "tune"),
            originPageIndex: Number.isInteger(meta?.originPageIndex) ? meta.originPageIndex : -1,
            originSubTab: String(meta?.originSubTab ?? "")
        }
        const prevCard = root._liveCardsByModuleId[moduleId]
        const prevMeta = root._liveCardMetaByModuleId[moduleId]
        if (prevCard === cardItem
            && prevMeta
            && prevMeta.title === nextMeta.title
            && prevMeta.icon === nextMeta.icon
            && prevMeta.originPageIndex === nextMeta.originPageIndex
            && prevMeta.originSubTab === nextMeta.originSubTab) {
            return
        }

        root._liveCardsByModuleId[moduleId] = cardItem
        root._liveCardMetaByModuleId[moduleId] = nextMeta
        root.liveCardRevision++
    }

    function unregisterLiveCard(moduleId: string, cardItem: Item): void {
        if (!moduleId)
            return
        if (root._liveCardsByModuleId[moduleId] && (!cardItem || root._liveCardsByModuleId[moduleId] === cardItem)) {
            delete root._liveCardsByModuleId[moduleId]
            root.liveCardRevision++
        }
    }

    function getLiveCard(moduleId: string): Item {
        void root.liveCardRevision
        return root._liveCardsByModuleId[moduleId] ?? null
    }

    function getForeignModuleIdsForTarget(targetPageIndex: int, targetCustomTabId: string, targetSubTab: string, hasSubTabs: bool): var {
        void root.layoutRevision
        return LayoutPolicy.getForeignModuleIdsForTarget(
            root.state, targetPageIndex, targetCustomTabId, targetSubTab, hasSubTabs
        )
    }

    function getForeignCardsForTarget(targetPageIndex: int, targetCustomTabId: string, targetSubTab: string, hasSubTabs: bool): var {
        void root.layoutRevision
        void root.liveCardRevision
        const ids = LayoutPolicy.getForeignModuleIdsForTarget(
            root.state, targetPageIndex, targetCustomTabId, targetSubTab, hasSubTabs
        )
        const cards = []
        for (let i = 0; i < ids.length; i++) {
            const card = root._liveCardsByModuleId[ids[i]]
            if (card)
                cards.push(card)
        }
        return cards
    }

    function getDonorPageIndexes(targetPageIndex: int, targetCustomTabId: string): var {
        void root.layoutRevision
        return LayoutPolicy.getDonorPageIndexesForTarget(root.state, targetPageIndex, targetCustomTabId)
    }

    function isModuleMovedAway(moduleId: string, currentPageIndex: int, currentCustomTabId: string, currentSubTab: string, hasSubTabs: bool): bool {
        void root.layoutRevision
        return LayoutPolicy.isModuleMovedAway(
            root.state, moduleId, currentPageIndex, currentCustomTabId, currentSubTab, hasSubTabs
        )
    }

    function isModuleHostedOnTarget(moduleId: string, targetPageIndex: int, targetCustomTabId: string, targetSubTab: string, hasSubTabs: bool): bool {
        void root.layoutRevision
        return LayoutPolicy.isModuleHostedOnTarget(
            root.state, moduleId, targetPageIndex, targetCustomTabId, targetSubTab, hasSubTabs
        )
    }

    function pageNameForIndex(pageIndex: int): string {
        if (pageIndex < 0)
            return "Custom Tab"
        const direct = root.availablePages?.[pageIndex]?.name
        if (direct && String(direct).trim().length > 0)
            return String(direct).trim()
        const navList = root.availableNavigationPages ?? []
        for (let i = 0; i < navList.length; i++) {
            if (navList[i]?.pageIndex === pageIndex && navList[i]?.name)
                return String(navList[i].name).trim()
        }
        return "Page " + (pageIndex + 1)
    }

    function pageIconForIndex(pageIndex: int): string {
        if (pageIndex < 0)
            return "dashboard_customize"
        const direct = root.availablePages?.[pageIndex]?.icon
        if (direct && String(direct).trim().length > 0)
            return String(direct).trim()
        const navList = root.availableNavigationPages ?? []
        for (let i = 0; i < navList.length; i++) {
            if (navList[i]?.pageIndex === pageIndex && navList[i]?.icon)
                return String(navList[i].icon).trim()
        }
        return "settings"
    }

    function getAllKnownModules(): var {
        void root.layoutRevision
        void root.liveCardRevision
        const result = []
        const seen = ({})
        const metaKeys = Object.keys(root._liveCardMetaByModuleId)
        for (let i = 0; i < metaKeys.length; i++) {
            const id = metaKeys[i]
            const m = root._liveCardMetaByModuleId[id]
            const cfg = LayoutPolicy.getModuleConfig(root.state, id)
            seen[id] = true
            result.push({
                moduleId: id,
                title: LayoutPolicy.humanizeModuleTitle(m.title || cfg.title || "", id),
                icon: m.icon || cfg.icon || "tune",
                originPageIndex: m.originPageIndex >= 0 ? m.originPageIndex : cfg.originPageIndex,
                originSubTab: m.originSubTab || cfg.originSubTab,
                targetPageIndex: cfg.targetPageIndex,
                targetCustomTabId: cfg.targetCustomTabId,
                targetSubTab: cfg.targetSubTab,
                visible: cfg.visible,
                column: cfg.column
            })
        }
        const stateKeys = Object.keys(root.state.modules ?? ({}))
        for (let j = 0; j < stateKeys.length; j++) {
            const sid = stateKeys[j]
            if (seen[sid])
                continue
            const scfg = LayoutPolicy.getModuleConfig(root.state, sid)
            result.push({
                moduleId: sid,
                title: LayoutPolicy.humanizeModuleTitle(scfg.title || "", sid),
                icon: scfg.icon || "tune",
                originPageIndex: scfg.originPageIndex,
                originSubTab: scfg.originSubTab,
                targetPageIndex: scfg.targetPageIndex,
                targetCustomTabId: scfg.targetCustomTabId,
                targetSubTab: scfg.targetSubTab,
                visible: scfg.visible,
                column: scfg.column
            })
        }
        return result
    }

    // --- Module Configuration & Sizing ---

    function getModuleConfig(moduleId: string): var {
        void root.layoutRevision
        return LayoutPolicy.getModuleConfig(root.state, moduleId)
    }

    function updateModuleConfig(moduleId: string, patch: var): void {
        if (!moduleId)
            return
        const meta = root._liveCardMetaByModuleId[moduleId]
        const fullPatch = Object.assign({}, patch ?? ({}))
        if (meta) {
            if (fullPatch.originPageIndex === undefined && meta.originPageIndex >= 0)
                fullPatch.originPageIndex = meta.originPageIndex
            if (fullPatch.originSubTab === undefined && meta.originSubTab)
                fullPatch.originSubTab = meta.originSubTab
            if (!fullPatch.title && meta.title)
                fullPatch.title = LayoutPolicy.humanizeModuleTitle(meta.title, moduleId)
            if (!fullPatch.icon && meta.icon)
                fullPatch.icon = meta.icon
        } else if (!fullPatch.title) {
            const existingTitle = LayoutPolicy.getModuleConfig(root.state, moduleId).title
            fullPatch.title = LayoutPolicy.humanizeModuleTitle(existingTitle || "", moduleId)
        }
        const next = LayoutPolicy.updateModuleConfig(root.state, moduleId, fullPatch)
        root._commitState(next, true)
    }

    function resizeModule(moduleId: string, sizeSpec: var): void {
        if (!moduleId || !sizeSpec)
            return
        const next = LayoutPolicy.resizeModule(root.state, moduleId, sizeSpec, root.snapEnabled, root.gridSize)
        root._commitState(next, true)
    }

    function moveModuleToTarget(moduleId: string, targetSpec: var): void {
        if (!moduleId || !targetSpec)
            return
        const meta = root._liveCardMetaByModuleId[moduleId] ?? ({})
        const cfg = LayoutPolicy.getModuleConfig(root.state, moduleId)
        const originInfo = {
            originPageIndex: meta.originPageIndex >= 0 ? meta.originPageIndex : cfg.originPageIndex,
            originSubTab: meta.originSubTab || cfg.originSubTab,
            title: LayoutPolicy.humanizeModuleTitle(meta.title || cfg.title || "", moduleId),
            icon: meta.icon || cfg.icon || "tune"
        }
        const next = LayoutPolicy.moveModuleToTarget(root.state, moduleId, originInfo, targetSpec)
        root._commitState(next, true)
    }

    function reorderModulesInBucket(orderedModuleIds: var, columnOverride: string): void {
        const next = LayoutPolicy.reorderModulesInBucket(root.state, orderedModuleIds, columnOverride)
        root._commitState(next, true)
    }

    function setModuleVisible(moduleId: string, visible: bool): void {
        root.updateModuleConfig(moduleId, { visible: visible })
    }

    function resetModule(moduleId: string): void {
        if (!moduleId)
            return
        const next = LayoutPolicy.resetModule(root.state, moduleId)
        root._commitState(next, true)
    }

    function autoFitPageModules(pageIndex: int, customTabId: string): void {
        const next = LayoutPolicy.cloneState(root.state)
        const curTabId = String(customTabId || "").trim()
        const resetPrefixes = []
        if (curTabId.length === 0 && pageIndex >= 0)
            resetPrefixes.push("p" + pageIndex + ":")
        const mKeys = Object.keys(next.modules)
        for (let i = 0; i < mKeys.length; i++) {
            const id = mKeys[i]
            const entry = next.modules[id]
            if (!entry)
                continue
            const onPage = curTabId.length > 0
                ? (entry.targetCustomTabId === curTabId)
                : (!entry.targetCustomTabId && (entry.targetPageIndex === pageIndex || (entry.targetPageIndex < 0 && entry.originPageIndex === pageIndex)))
            if (onPage) {
                resetPrefixes.push(id + ":")
                const isNativeUnmoved = curTabId.length === 0
                    && (entry.targetPageIndex < 0 || entry.targetPageIndex === entry.originPageIndex)
                    && (entry.targetSubTab === "" || entry.targetSubTab === entry.originSubTab)
                if (isNativeUnmoved) {
                    delete next.modules[id]
                } else {
                    entry.widthRatio = 0
                    entry.customHeight = 0
                    entry.innerColumns = 0
                    entry.column = "auto"
                    entry.order = 0
                    entry.contentFitMode = "scale"
                    entry.visible = true
                    entry.canvasX = -1
                    entry.canvasY = -1
                    entry.canvasW = 0
                    entry.canvasH = 0
                }
            }
        }
        const matchesPrefix = (key) => {
            for (let p = 0; p < resetPrefixes.length; p++) {
                if (key.indexOf(resetPrefixes[p]) === 0)
                    return true
            }
            return false
        }
        const ioKeys = Object.keys(next.innerOrders ?? ({}))
        for (let j = 0; j < ioKeys.length; j++) {
            if (matchesPrefix(ioKeys[j]))
                delete next.innerOrders[ioKeys[j]]
        }
        const iiKeys = Object.keys(next.innerItems ?? ({}))
        for (let k = 0; k < iiKeys.length; k++) {
            if (matchesPrefix(iiKeys[k]))
                delete next.innerItems[iiKeys[k]]
        }
        const sKeys = Object.keys(next.sliders ?? ({}))
        for (let s = 0; s < sKeys.length; s++) {
            if (matchesPrefix(sKeys[s]))
                delete next.sliders[sKeys[s]]
        }
        const pageKey = LayoutPolicy.makePageKey(pageIndex, customTabId)
        if (next.pageLayouts[pageKey]) {
            next.pageLayouts[pageKey].layoutMode = "bento"
            next.pageLayouts[pageKey].leftColumnRatio = 0.5
        }
        root.openCustomizeModuleId = ""
        root._commitState(next, true)
    }

    // --- Page Layout & Sub-Tab Management ---

    function getPageLayoutConfig(pageIndex: int, customTabId: string): var {
        void root.layoutRevision
        return LayoutPolicy.getPageLayoutConfig(root.state, pageIndex, customTabId)
    }

    function updatePageLayoutConfig(pageIndex: int, customTabId: string, patch: var): void {
        const next = LayoutPolicy.updatePageLayoutConfig(root.state, pageIndex, customTabId, patch)
        root._commitState(next, true)
    }

    function updatePageLayoutConfigNoUndo(pageIndex: int, customTabId: string, patch: var): void {
        const next = LayoutPolicy.updatePageLayoutConfig(root.state, pageIndex, customTabId, patch)
        root._commitState(next, false)
    }

    function togglePageLayoutMode(pageIndex: int, customTabId: string): string {
        const cur = root.getPageLayoutConfig(pageIndex, customTabId)
        const nextMode = cur.layoutMode === "canvas" ? "bento" : "canvas"
        root.updatePageLayoutConfig(pageIndex, customTabId, { layoutMode: nextMode })
        return nextMode
    }

    function setLeftColumnRatio(pageIndex: int, customTabId: string, ratio: real): void {
        root.updatePageLayoutConfig(pageIndex, customTabId, { leftColumnRatio: ratio })
    }

    function getEffectiveSubTabs(pageIndex: int, customTabId: string, baseSubTabs: var): var {
        void root.layoutRevision
        return LayoutPolicy.getEffectiveSubTabs(root.state, pageIndex, customTabId, baseSubTabs)
    }

    function createSubTab(pageIndex: int, customTabId: string, label: string, icon: string, baseSubTabs: var): string {
        const res = LayoutPolicy.createSubTab(root.state, pageIndex, customTabId, label, icon, baseSubTabs)
        root._commitState(res.state, true)
        return res.subTabKey
    }

    function renameSubTab(pageIndex: int, customTabId: string, subTabKey: string, newLabel: string): void {
        const next = LayoutPolicy.renameSubTab(root.state, pageIndex, customTabId, subTabKey, newLabel)
        root._commitState(next, true)
    }

    function deleteSubTab(pageIndex: int, customTabId: string, subTabKey: string, baseSubTabs: var): void {
        const next = LayoutPolicy.deleteSubTab(root.state, pageIndex, customTabId, subTabKey, baseSubTabs)
        root._commitState(next, true)
    }

    function reorderSubTab(pageIndex: int, customTabId: string, subTabKey: string, direction: int, baseSubTabs: var): void {
        const next = LayoutPolicy.reorderSubTab(root.state, pageIndex, customTabId, subTabKey, direction, baseSubTabs)
        root._commitState(next, true)
    }

    // --- Custom Sidebar Tabs Management ---

    readonly property var customTabs: {
        void root.layoutRevision
        return root.state.customTabs ?? []
    }

    function getCustomTab(tabId: string): var {
        void root.layoutRevision
        const list = root.state.customTabs ?? []
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === tabId)
                return list[i]
        }
        return null
    }

    function createCustomTab(label: string, icon: string, categoryIndex: int): string {
        const res = LayoutPolicy.createCustomTab(root.state, label, icon, categoryIndex)
        root._commitState(res.state, true)
        root.activeCustomTabId = res.tabId
        return res.tabId
    }

    function renameCustomTab(tabId: string, newLabel: string, newIcon: string): void {
        const next = LayoutPolicy.renameCustomTab(root.state, tabId, newLabel, newIcon)
        root._commitState(next, true)
    }

    function deleteCustomTab(tabId: string): void {
        if (!tabId)
            return
        if (root.activeCustomTabId === tabId)
            root.activeCustomTabId = ""
        const next = LayoutPolicy.deleteCustomTab(root.state, tabId)
        root._commitState(next, true)
    }

    function moveCustomTab(tabId: string, direction: int, targetCategoryIndex: int): void {
        const next = LayoutPolicy.moveCustomTab(root.state, tabId, direction, targetCategoryIndex)
        root._commitState(next, true)
    }

    // --- Inner Module Settings Item Ordering & Sizing ---

    function hasInnerCustomizations(containerId: string): bool {
        void root.layoutRevision
        return LayoutPolicy.hasInnerCustomizations(root.state, containerId)
    }

    function getInnerOrder(containerId: string, defaultKeys: var): var {
        void root.layoutRevision
        return LayoutPolicy.getInnerOrder(root.state, containerId, defaultKeys)
    }

    function moveInnerItem(containerId: string, itemKey: string, directionOrTargetKey: var, defaultKeys: var): void {
        const next = LayoutPolicy.moveInnerItem(root.state, containerId, itemKey, directionOrTargetKey, defaultKeys)
        root._commitState(next, true)
    }

    function getInnerItemConfig(itemId: string): var {
        void root.layoutRevision
        return LayoutPolicy.getInnerItemConfig(root.state, itemId)
    }

    function updateInnerItemConfig(itemId: string, patch: var): void {
        const next = LayoutPolicy.updateInnerItemConfig(root.state, itemId, patch)
        root._commitState(next, true)
    }

    // --- Slider Customization (Orientation & Size) ---

    readonly property bool hasAnySliderCustomizations: {
        void root.layoutRevision
        return Object.keys(root.state?.sliders ?? ({})).length > 0
    }

    function getSliderConfig(sliderId: string): var {
        void root.layoutRevision
        return LayoutPolicy.getSliderConfig(root.state, sliderId)
    }

    function updateSliderConfig(sliderId: string, patch: var): void {
        const next = LayoutPolicy.updateSliderConfig(root.state, sliderId, patch)
        root._commitState(next, true)
    }

    function toggleSliderOrientation(sliderId: string): string {
        const next = LayoutPolicy.toggleSliderOrientation(root.state, sliderId)
        root._commitState(next, true)
        return LayoutPolicy.getSliderConfig(next, sliderId).orientation
    }

    function resizeSlider(sliderId: string, length: real, thickness: real, configuration: string): void {
        const next = LayoutPolicy.resizeSlider(root.state, sliderId, length, thickness, configuration)
        root._commitState(next, true)
    }

    function resetSlider(sliderId: string): void {
        const next = LayoutPolicy.resetSlider(root.state, sliderId)
        root._commitState(next, true)
    }

    // --- Global Module Drag & Drop Coordinator ---

    function registerDropTarget(targetId: string, itemOrSpec, spec): void {
        if (!targetId || !itemOrSpec)
            return
        let item = itemOrSpec
        let resolvedSpec = spec ?? ({})
        if (itemOrSpec && typeof itemOrSpec === "object" && itemOrSpec.item && typeof itemOrSpec.mapFromItem !== "function") {
            item = itemOrSpec.item
            resolvedSpec = Object.assign({}, itemOrSpec)
            delete resolvedSpec.item
        }
        if (!item)
            return
        root._dropTargets[targetId] = {
            targetId: targetId,
            item: item,
            spec: resolvedSpec
        }
    }

    function unregisterDropTarget(targetId: string, item): void {
        if (!targetId)
            return
        const current = root._dropTargets[targetId]
        if (current && (!item || current.item === item)) {
            delete root._dropTargets[targetId]
        }
    }

    function _priorityForDropKind(kind: string): int {
        switch (kind) {
        case "subtab":
            return 100
        case "sidebar-custom-tab":
            return 95
        case "sidebar-page":
            return 90
        case "card":
            return 70
        case "column":
            return 50
        case "canvas":
            return 30
        default:
            return 10
        }
    }

    function hitTestDropTarget(sceneX: real, sceneY: real): var {
        const keys = Object.keys(root._dropTargets)
        let best = null
        let bestPriority = -1

        for (let i = 0; i < keys.length; i++) {
            const entry = root._dropTargets[keys[i]]
            const item = entry?.item
            if (!item || !item.visible || item.width <= 0 || item.height <= 0)
                continue
            if (entry.spec?.moduleId && entry.spec.moduleId === root.draggedModuleId)
                continue

            const localPt = item.mapFromItem(null, sceneX, sceneY)
            if (localPt.x >= 0 && localPt.x <= item.width && localPt.y >= 0 && localPt.y <= item.height) {
                const prio = root._priorityForDropKind(String(entry.spec?.kind ?? ""))
                if (prio > bestPriority) {
                    bestPriority = prio
                    best = {
                        targetId: entry.targetId,
                        item: item,
                        spec: entry.spec,
                        localX: localPt.x,
                        localY: localPt.y,
                        insertAfter: localPt.y > item.height * 0.5
                    }
                }
            }
        }
        return best
    }

    function beginModuleDrag(moduleId: string, cardItem: Item, sceneX: real, sceneY: real): void {
        if (!moduleId || !cardItem)
            return
        const meta = root._liveCardMetaByModuleId[moduleId] ?? ({})
        root.draggedModuleId = moduleId
        root.draggedModuleTitle = LayoutPolicy.humanizeModuleTitle(cardItem.title || meta.title || "", moduleId)
        root.draggedModuleIcon = String(cardItem.icon || meta.icon || "tune")
        root.draggedOriginPageIndex = meta.originPageIndex >= 0 ? meta.originPageIndex : -1
        root.draggedOriginSubTab = String(meta.originSubTab ?? "")
        root.dragCardWidth = Math.max(220, Math.min(520, cardItem.width || 320))
        root.dragCardHeight = Math.max(96, Math.min(340, cardItem.height || 140))
        root.dragSceneX = sceneX
        root.dragSceneY = sceneY
        root.selectedModuleId = moduleId
        root.draggingModule = true
        root.hoveredDropTarget = root.hitTestDropTarget(sceneX, sceneY)
    }

    function updateModuleDrag(sceneX: real, sceneY: real): void {
        if (!root.draggingModule)
            return
        root.dragSceneX = sceneX
        root.dragSceneY = sceneY
        root.hoveredDropTarget = root.hitTestDropTarget(sceneX, sceneY)
    }

    function cancelModuleDrag(): void {
        root.draggingModule = false
        root.draggedModuleId = ""
        root.hoveredDropTarget = null
    }

    function finishModuleDrag(sceneX: real, sceneY: real): bool {
        if (!root.draggingModule)
            return false
        const moduleId = root.draggedModuleId
        const hit = root.hitTestDropTarget(sceneX, sceneY) ?? root.hoveredDropTarget
        root.draggingModule = false
        root.draggedModuleId = ""
        root.hoveredDropTarget = null

        if (!moduleId || !hit || !hit.spec)
            return false

        const spec = hit.spec
        const kind = String(spec.kind ?? "")

        if (kind === "subtab") {
            root.moveModuleToTarget(moduleId, {
                targetPageIndex: Number.isInteger(spec.pageIndex) ? spec.pageIndex : -1,
                targetCustomTabId: String(spec.customTabId ?? ""),
                targetSubTab: String(spec.subTabKey ?? ""),
                column: "auto"
            })
            return true
        }

        if (kind === "sidebar-page") {
            root.moveModuleToTarget(moduleId, {
                targetPageIndex: Number.isInteger(spec.pageIndex) ? spec.pageIndex : -1,
                targetCustomTabId: "",
                targetSubTab: "",
                column: "auto"
            })
            return true
        }

        if (kind === "sidebar-custom-tab") {
            root.moveModuleToTarget(moduleId, {
                targetPageIndex: -1,
                targetCustomTabId: String(spec.customTabId ?? ""),
                targetSubTab: "",
                column: "auto"
            })
            return true
        }

        if (kind === "column") {
            root.moveModuleToTarget(moduleId, {
                targetPageIndex: Number.isInteger(spec.pageIndex) ? spec.pageIndex : -1,
                targetCustomTabId: String(spec.customTabId ?? ""),
                targetSubTab: String(spec.subTabKey ?? ""),
                column: String(spec.column ?? "auto")
            })
            return true
        }

        if (kind === "canvas") {
            const gx = LayoutPolicy.snapValue(Math.max(0, hit.localX - root.dragCardWidth * 0.5), root.gridSize, root.snapEnabled)
            const gy = LayoutPolicy.snapValue(Math.max(0, hit.localY - 28), root.gridSize, root.snapEnabled)
            root.moveModuleToTarget(moduleId, {
                targetPageIndex: Number.isInteger(spec.pageIndex) ? spec.pageIndex : -1,
                targetCustomTabId: String(spec.customTabId ?? ""),
                targetSubTab: String(spec.subTabKey ?? ""),
                canvasX: gx,
                canvasY: gy
            })
            return true
        }

        if (kind === "card") {
            const targetCardId = String(spec.moduleId ?? "")
            const targetCfg = root.getModuleConfig(targetCardId)
            const peerOrder = Array.isArray(spec.peerModuleIds) ? spec.peerModuleIds.slice() : []
            const targetCol = String(spec.column || targetCfg.column || "auto")

            root.moveModuleToTarget(moduleId, {
                targetPageIndex: Number.isInteger(spec.pageIndex) ? spec.pageIndex : targetCfg.targetPageIndex,
                targetCustomTabId: String(spec.customTabId ?? targetCfg.targetCustomTabId ?? ""),
                targetSubTab: String(spec.subTabKey ?? targetCfg.targetSubTab ?? ""),
                column: targetCol
            })

            if (peerOrder.length > 0) {
                const filtered = peerOrder.filter(id => id !== moduleId)
                const idx = filtered.indexOf(targetCardId)
                if (idx >= 0) {
                    filtered.splice(hit.insertAfter ? idx + 1 : idx, 0, moduleId)
                    root.reorderModulesInBucket(filtered, targetCol)
                }
            }
            return true
        }

        return false
    }
}
