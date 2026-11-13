pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.perimeter
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.sidebarLeft.news
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property int screenWidth: 1920
    property int screenHeight: 1080
    property var panelScreen: null
    property real panelScreenY: Appearance.sizes.hyprlandGapsOut
    property bool externalConnectedSurface: false
    readonly property color connectedSurfaceColor:
        sidebarLeftBackground.cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0
    readonly property real connectedSurfaceRadius: sidebarLeftBackground.radius
    // Only the INNER content plate follows the Abyss material. Outer panel,
    // seam, blur and opacity remain owned by the existing connected host.
    // Reuse the owner-approved Detailed Weather card palette, with live
    // theme/wallpaper bindings and unchanged Waffle/ii Material fallback.
    readonly property bool abyssInnerMaterial: Config.options?.panelFamily === "abyss"
    readonly property color innerContentSurfaceColor: root.abyssInnerMaterial
        ? Qt.alpha(ColorUtils.mix(AbyssStyle.contentLayer, AbyssStyle.accent, .88),
            AbyssStyle.contentOpacity)
        : Appearance.colors.colLayer1
    property bool panelVisible: false
    property bool geometryPreviewActive: false
    property string outerSizeMode: "full"
    property string attachedEdge: "left"

    property bool aiChatEnabled: true
    property bool translatorEnabled: (Config.options?.sidebar?.translator?.enable ?? false)
    property bool newsEnabled: Config.options?.sidebar?.news?.enable ?? true
    property bool toolsEnabled: Config.options?.sidebar?.tools?.enable ?? false

    // Tabs exposing contentPreferredHeight can let the panel hug their content.
    readonly property real activeTabContentHeight: swipeView.currentItem?.item?.contentPreferredHeight ?? -1
    readonly property bool activeTabEditing: swipeView.currentItem?.item?.editMode ?? false
    readonly property bool fitToContent:
        ((Config.options?.sidebar?.collapseWidgetsTab ?? false)
            || root.outerSizeMode === "fit")
        && !activeTabEditing && activeTabContentHeight > 0
    readonly property real availableContentHeight: Math.max(0,
        root.screenHeight - Appearance.sizes.hyprlandGapsOut * 2)
    readonly property real preferredContentHeight: root.fitToContent
        ? SidebarGeometry.leftFitHeight(root.availableContentHeight,
            sidebarLeftBackground.naturalFitHeight)
        : root.availableContentHeight
    readonly property real minimumUsefulHeight: Math.max(320,
        root.screenHeight * SidebarGeometry.leftFitMinRatio)
    readonly property real minimumUsefulWidth: 320
    readonly property real maximumUsefulWidth: 900

    readonly property var _tabDefaultOrder: [
        "ai", "translator", "news", "tools"
    ]
    readonly property var resolvedTabOrder: {
        const result = []
        const saved = Config.options?.sidebar?.left?.tabOrder ?? root._tabDefaultOrder
        for (let i = 0; i < saved.length; i++) {
            const id = saved[i]
            if (root._tabDefaultOrder.includes(id) && !result.includes(id)) result.push(id)
        }
        for (let i = 0; i < root._tabDefaultOrder.length; i++) {
            const id = root._tabDefaultOrder[i]
            if (!result.includes(id)) result.push(id)
        }
        return result
    }
    property string selectedTabId: ""
    property bool tabEditMode: false
    property int _prewarmCount: 0

    Timer {
        id: tabPrewarmTimer
        interval: 85
        repeat: true
        running: root.panelVisible && root._prewarmCount < (root.tabButtonList?.length ?? 0)
        onTriggered: root._prewarmCount++
    }

    // Enabled tabs rendered in the user's stable-id order.
    property var tabButtonList: {
        const result = []
        if (root.aiChatEnabled) result.push({ id: "ai", icon: "neurology", name: Translation.tr("Intelligence") })
        if (root.translatorEnabled) result.push({ id: "translator", icon: "translate", name: Translation.tr("Translator") })
        if (root.newsEnabled) result.push({ id: "news", icon: "newspaper", name: Translation.tr("News") })
        if (root.toolsEnabled) result.push({ id: "tools", icon: "build", name: Translation.tr("Tools") })
        result.sort((a, b) => root.resolvedTabOrder.indexOf(a.id) - root.resolvedTabOrder.indexOf(b.id))
        return result
    }

    function focusActiveItem() {
        swipeView.currentItem?.forceActiveFocus()
    }

    function persistTabMove(fromIndex: int, toIndex: int): void {
        if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0) return
        const movedTab = root.tabButtonList[fromIndex]
        const targetTab = root.tabButtonList[toIndex]
        if (!movedTab || !targetTab) return

        const order = [...root.resolvedTabOrder]
        const fromOrderIndex = order.indexOf(movedTab.id)
        const toOrderIndex = order.indexOf(targetTab.id)
        if (fromOrderIndex < 0 || toOrderIndex < 0) return

        const movedId = order.splice(fromOrderIndex, 1)[0]
        order.splice(toOrderIndex, 0, movedId)
        Config.setNestedValue("sidebar.left.tabOrder", order)
    }

    function syncSwipeItemsOrder(): void {
        const expected = root.tabButtonList ?? []
        let writePos = 0
        for (let i = 0; i < expected.length; i++) {
            const targetId = expected[i]?.id ?? ""
            if (!targetId) continue
            let foundIdx = -1
            for (let j = writePos; j < swipeView.count; j++) {
                const item = swipeView.itemAt(j)
                if (item && item.tabId === targetId) {
                    foundIdx = j
                    break
                }
            }
            if (foundIdx >= 0) {
                if (foundIdx !== writePos)
                    swipeView.moveItem(foundIdx, writePos)
                writePos++
            }
        }
    }

    function syncSelectedTabIndex(): void {
        root.syncSwipeItemsOrder()
        let index = root.selectedTabId
            ? root.tabButtonList.findIndex(tab => tab.id === root.selectedTabId)
            : -1
        if (index < 0 && root.tabButtonList.length > 0)
            index = Math.max(0, Math.min(swipeView.currentIndex, root.tabButtonList.length - 1))
        if (index >= 0) {
            if (swipeView.currentIndex !== index)
                swipeView.currentIndex = index
            tabBar.setCurrentIndex(index)
            root.selectedTabId = root.tabButtonList[index]?.id ?? ""
        }
    }

    function ensureActiveTabReady(): void {
        if (!GlobalStates.sidebarLeftOpen) return
        const currentTab = root.tabButtonList[swipeView.currentIndex]
        if (currentTab?.id === "ai") Ai.ensureInitialized()
    }

    function applyDevDestination(): void {
        if (!DevNavigation.currentDestination.startsWith("sidebar-left/")) return
        const view = DevNavigation.currentDestination.substring("sidebar-left/".length)
        const iconByView = {
            "ai": "neurology", "translator": "translate",
            "news": "newspaper", "tools": "build"
        }
        const icon = iconByView[view] ?? ""
        const index = root.tabButtonList.findIndex(tab => tab.icon === icon)
        if (index >= 0) swipeView.currentIndex = index
    }

    onTabButtonListChanged: Qt.callLater(root.syncSelectedTabIndex)

    Component.onCompleted: {
        root.applyDevDestination()
        Qt.callLater(() => {
            root.selectedTabId = root.tabButtonList[swipeView.currentIndex]?.id ?? ""
        })
    }
    Connections {
        target: DevNavigation
        function onCurrentDestinationChanged(): void { root.applyDevDestination() }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged(): void {
            if (GlobalStates.sidebarLeftOpen) root.ensureActiveTabReady()
            else root.tabEditMode = false
        }
    }

    StyledRectangularShadow {
        target: sidebarLeftBackground
        radius: sidebarLeftBackground.radius
        blur: Math.max(0, Math.min(32,
            Math.round(Config.options?.appearance?.screenEdge?.shadow?.size ?? 15)))
        spread: 0
        offset: Qt.vector2d(0, 0)
        color: ColorUtils.applyAlpha(Appearance.colors.colShadow,
            Math.max(0, Math.min(1.0,
                Number(Config.options?.appearance?.screenEdge?.shadow?.opacity ?? 0.70))))
        visible: root.panelVisible && !root.externalConnectedSurface
            && (Config.options?.appearance?.screenEdge?.shadow?.enabled ?? true)
            && !Appearance.gameModeMinimal
        joinLeft: root.attachedEdge === "left"
        joinRight: root.attachedEdge === "right"
    }

    RicelinSurface {
        anchors.fill: sidebarLeftBackground
        visible: !root.externalConnectedSurface && sidebarLeftBackground.islandStyle
        radius: sidebarLeftBackground.radius
        glassEnabled: true
        screen: root.panelScreen ?? root.QsWindow?.window?.screen ?? null
        glassScreenX: Appearance.sizes.hyprlandGapsOut
        glassScreenY: root.panelScreenY
        glassScreenWidth: root.screenWidth
        glassScreenHeight: root.screenHeight
    }

    Rectangle {
        id: sidebarLeftBackground

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        readonly property real naturalFitHeight: (toolbarContainer.visible
                ? toolbarContainer.implicitHeight + contentColumn.spacing : 0)
            + Math.max(0, Math.round(root.activeTabContentHeight))
            + contentColumn.anchors.topMargin + root.sidebarPadding
        height: root.fitToContent
            ? SidebarGeometry.leftFitHeight(parent.height, naturalFitHeight)
            : parent.height
        Behavior on height {
            enabled: Appearance.animationsEnabled && root.panelVisible
                && !root.geometryPreviewActive
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
        }
        property bool cardStyle: Config.options?.sidebar?.cardStyle ?? false
        // Ricelin island mode remains an explicit supported sidebar skin;
        // otherwise the sidebar uses the canonical Material surface.
        readonly property string surfaceDialect: Appearance.surfaceDialectFor(
            (Config.options?.sidebar?.style ?? "panel") === "island" ? "island" : "")
        readonly property bool islandStyle: surfaceDialect === "island"
        readonly property bool gameModeMinimal: Appearance.gameModeMinimal

        color: root.externalConnectedSurface
            ? "transparent"
            : (gameModeMinimal || islandStyle) ? "transparent"
            : (cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0)
        // Screen Edge owns the outer shell boundary. Drawing a second outline
        // here makes the edge/sidebar join read as two stacked cards.
        border.width: 0 // Screen Edge seam owns the outer boundary
        border.color: "transparent"
        radius: cardStyle
            ? Appearance.rounding.normal
            : (Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1)
        topLeftRadius: root.attachedEdge === "left" ? 0 : radius
        bottomLeftRadius: root.attachedEdge === "left" ? 0 : radius
        topRightRadius: root.attachedEdge === "right" ? 0 : radius
        bottomRightRadius: root.attachedEdge === "right" ? 0 : radius

        Behavior on radius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        clip: true

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: sidebarPadding
            anchors.topMargin: sidebarPadding - 4
            spacing: sidebarPadding

            // Tab bar
            Toolbar {
                id: toolbarContainer
                Layout.alignment: Qt.AlignHCenter
                enableShadow: false
                padding: 6
                implicitHeight: tabBar.implicitHeight + padding * 2
                transparent: false

                ToolbarTabBar {
                    id: tabBar
                    Layout.alignment: Qt.AlignHCenter
                    maxWidth: Math.max(0, root.width - (root.sidebarPadding * 2) - 64)
                    tabButtonList: root.tabButtonList
                    reorderEnabled: root.tabEditMode
                    onReorderRequested: (fromIndex, toIndex) => root.persistTabMove(fromIndex, toIndex)
                    // Don't bind to swipeView - let tabBar be the source of truth
                    onCurrentIndexChanged: {
                        if (swipeView.currentIndex !== currentIndex)
                            swipeView.currentIndex = currentIndex
                    }
                }

                ToolbarButton {
                    id: tabEditButton
                    Layout.preferredWidth: 38
                    visible: root.tabButtonList.length > 1
                    toggled: root.tabEditMode
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    downAction: () => root.tabEditMode = !root.tabEditMode
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.tabEditMode ? "done" : "edit"
                        iconSize: 19
                        color: tabEditButton.toggled
                            ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: root.tabEditMode
                            ? Translation.tr("Finish arranging tabs")
                            : Translation.tr("Arrange sidebar tabs")
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: !root.fitToContent
                implicitHeight: {
                    if (root.activeTabContentHeight <= 0) return 0
                    if (root.fitToContent)
                        return Math.round(root.activeTabContentHeight)
                    const chromeHeight = contentColumn.anchors.topMargin + root.sidebarPadding
                        + (toolbarContainer.visible ? toolbarContainer.implicitHeight + contentColumn.spacing : 0)
                    return Math.round(Math.max(0,
                        Math.min(root.activeTabContentHeight,
                            root.height - chromeHeight)))
                }
                id: sidebarLeftInnerSurface
                objectName: "sidebarLeftInnerSurface"
                radius: Appearance.rounding.normal
                // Material fallback: color: Appearance.colors.colLayer1
                color: root.innerContentSurfaceColor
                border.width: 0
                border.color: "transparent"
                // Organic morph on style/shape switch (organic-transitions)
                Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
                Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                // SwipeView with normal tab content
                SwipeView {
                    id: swipeView
                    anchors.fill: parent
                    spacing: 10
                    // Sync back to tabBar when swiping
                    onCurrentIndexChanged: {
                        if (tabBar.currentIndex !== currentIndex)
                            tabBar.setCurrentIndex(currentIndex)
                        const currentTab = root.tabButtonList[currentIndex]
                        root.selectedTabId = currentTab?.id ?? ""
                        root.ensureActiveTabReady()
                    }
                    Component.onCompleted: {
                        if (contentItem) {
                            if (contentItem.highlightMoveVelocity !== undefined)
                                contentItem.highlightMoveVelocity = -1
                            if (contentItem.highlightMoveDuration !== undefined)
                                contentItem.highlightMoveDuration = Qt.binding(() => Appearance.animationsEnabled ? 200 : 0)
                            if (contentItem.cacheBuffer !== undefined)
                                contentItem.cacheBuffer = Qt.binding(() => Math.max(0, Math.round(swipeView.width * 4)))
                        }
                    }
                    interactive: !root.tabEditMode
                        && !(currentItem?.item?.editMode ?? false)
                        && !(currentItem?.item?.dragPending ?? false)

                    clip: true
                    layer.enabled: root.panelVisible && !Appearance.gameModeMinimal
                        && Boolean(swipeView.contentItem?.moving)
                    layer.smooth: false
                    layer.mipmap: false
                    layer.effect: GE.OpacityMask {
                        maskSource: Rectangle {
                            width: swipeView.width
                            height: swipeView.height
                            radius: Appearance.rounding.small
                            Behavior on radius {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                            }
                        }
                    }

                    Instantiator {
                        model: root.tabButtonList
                        delegate: Loader {
                            id: tabLoader
                            required property var modelData
                            required property int index
                            readonly property string tabId: String(modelData?.id ?? "")
                            property bool everLoaded: false
                            readonly property bool shouldActivate: SwipeView.isCurrentItem
                                || swipeView.currentIndex === index
                                || (tabLoader.tabId !== "ai" && (index < root._prewarmCount
                                    || (root.panelVisible && (SwipeView.isNextItem || SwipeView.isPreviousItem))))
                            onShouldActivateChanged: {
                                if (shouldActivate && !everLoaded)
                                    everLoaded = true
                            }
                            Component.onCompleted: {
                                if (shouldActivate)
                                    everLoaded = true
                            }
                            active: everLoaded || shouldActivate
                            sourceComponent: {
                                switch (tabLoader.tabId) {
                                    case "ai": return aiChatComp
                                    case "translator": return translatorComp
                                    case "news": return newsComp
                                    case "tools": return toolsComp
                                    default: return null
                                }
                            }
                        }
                        onObjectAdded: (index, object) => {
                            swipeView.insertItem(Math.min(index, swipeView.count), object)
                            root.syncSwipeItemsOrder()
                            Qt.callLater(root.syncSelectedTabIndex)
                        }
                        onObjectRemoved: (index, object) => {
                            swipeView.removeItem(object)
                            root.syncSwipeItemsOrder()
                            Qt.callLater(root.syncSelectedTabIndex)
                        }
                    }
                }
            }
        }

        Component { id: aiChatComp; AiChat {} }
        Component { id: translatorComp; Translator {} }
        Component { id: newsComp; NewsView {} }
        Component { id: toolsComp; ToolsView {} }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (root.tabEditMode) {
                    root.tabEditMode = false
                    event.accepted = true
                    return
                }
                GlobalStates.sidebarLeftOpen = false
            }
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    swipeView.incrementCurrentIndex()
                    event.accepted = true
                }
                else if (event.key === Qt.Key_PageUp) {
                    swipeView.decrementCurrentIndex()
                    event.accepted = true
                }
                else if (event.key === Qt.Key_O) {
                    GlobalStates.sidebarLeftExpanded = !GlobalStates.sidebarLeftExpanded
                    event.accepted = true
                }
                else if (event.key === Qt.Key_P) {
                    GlobalStates.sidebarLeftOpen = false
                    GlobalStates.sidebarLeftExpanded = false
                    GlobalStates.aiChatDetached = true
                    event.accepted = true
                }
            }
        }
    }

    // The panel window remains output-height while fit-to-content is active.
    // Treat the vacated strip as backdrop so clicks there still dismiss it.
    MouseArea {
        anchors.top: sidebarLeftBackground.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        enabled: sidebarLeftBackground.height < root.height - 1
        onClicked: GlobalStates.sidebarLeftOpen = false
    }

    // ── Restore last active plugin (DISABLED — webapps) ────────────
    // Connections {
    //     target: Config
    //     function onReadyChanged() {
    //         if (Config.ready && root.pluginsEnabled) {
    //             root._tryRestoreLastPlugin()
    //         }
    //     }
    // }

    // Component.onCompleted: {
    //     if (Config.ready && root.pluginsEnabled) {
    //         root._tryRestoreLastPlugin()
    //     }
    // }
}
