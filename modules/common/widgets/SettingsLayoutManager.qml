pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick

/**
 * Inert compatibility facade retained after removing Settings Edit Layout.
 * Always reports editMode === false and performs no layout/canvas mutations.
 */
QtObject {
    id: root

    readonly property bool editMode: false
    readonly property bool innerEditMode: false
    readonly property bool snapEnabled: false
    readonly property int gridSize: 16
    readonly property string gridStyle: "off"

    property string activeCustomTabId: ""
    property string selectedModuleId: ""
    property string openCustomizeModuleId: ""
    property bool moduleDrawerOpen: false
    property string requestedPromptMode: ""
    property string activePromptMode: ""

    property int layoutRevision: 0
    property int liveCardRevision: 0
    readonly property bool canUndo: false
    readonly property bool canRedo: false
    readonly property bool draggingModule: false
    readonly property bool dragActive: false
    readonly property string draggedModuleId: ""
    readonly property var hoveredDropTarget: null
    readonly property string hoveredDropTargetId: ""
    readonly property var customTabs: []
    readonly property bool hasAnySliderCustomizations: false
    property var availablePages: []
    property var availableNavigationPages: []

    function beginEditMode(): void {}
    function commitEditMode(): void {}
    function cancelEditMode(): bool { return false }
    function handleEscape(): bool { return false }
    function requestInlinePrompt(mode: string): void {}
    function undo(): void {}
    function redo(): void {}
    function resetAll(): void {}
    function getPageLayoutConfig(pageIndex, customTabId) { return { layoutMode: "bento", leftColumnRatio: 0.5 } }
    function getCustomTab(tabId) { return null }
    function getModuleConfig(moduleId) { return null }
    function getEffectiveSubTabs(pageIndex, customTabId, baseSpecs) { return baseSpecs || [] }
    function getDonorPageIndexes(pageIndex, customTabId) { return [] }
    function getForeignCardsForTarget(pageIndex, customTabId, subTabKey, hasSubTabs) { return [] }
    function isModuleMovedAway(moduleId, pageIndex, customTabId, subTabKey, hasSubTabs) { return false }
    function hasInnerCustomizations(containerId) { return false }
    function getSliderConfig(sliderId) { return null }
    function registerDropTarget(targetId, item, spec) {}
    function unregisterDropTarget(targetId, item) {}
    function registerLiveCard(moduleId, item, meta) {}
    function unregisterLiveCard(moduleId, item) {}
    function makeModuleId(pageIndex, title, order) { return "p" + pageIndex + ":" + String(order || 0) }
}
