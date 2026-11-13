import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string title: ""
    property string icon: ""
    property bool expanded: true
    property bool collapsible: true
    // Embedded consumers can reuse only the section content without inheriting
    // Settings' collapsible title/drop-down chrome.
    property bool showHeader: true
    property bool flatEmbedded: false
    property bool allowEditWithoutHeader: false
    readonly property bool _participatesInLayout: root.showHeader || root.allowEditWithoutHeader
    property int animationDuration: Appearance.animation.elementMove.duration
    property string settingsTaskSection: ""
    property real spacing: SettingsMaterialPreset.groupSpacing
    default property alias contentData: sectionContent.data

    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1
    property bool syncRowExpansion: false
    property bool _syncingRowExpansion: false

    // Card Sub-Tab & Host state managed by ContentPage / SettingsLayoutManager
    property var _topPage: null
    property Item _currentHostPage: root._topPage
    property Item _initialParent: null
    property int _declarationOrder: -1
    property int _originPageIndex: -1
    property string _cardSubTabKey: ""
    property bool _cardSubTabActive: true
    property bool _isForeignHosted: false
    property bool _hasNextActiveCard: false
    property bool _preventBentoReparent: false
    property string bentoColumn: ""
    property bool _consumesBentoExtraHeight: false
    property real _bentoExtraHeight: 0
    property var _peerModuleIds: []

    // Deterministic module ID for layout persistence and cross-tab moves
    property string moduleId: ""

    readonly property var moduleConfig: (root.moduleId.length > 0)
        ? SettingsLayoutManager.getModuleConfig(root.moduleId)
        : null
    readonly property string customColumn: root.moduleConfig?.column ?? "auto"
    readonly property real customWidthRatio: root.moduleConfig?.widthRatio ?? 0
    readonly property real customHeight: root.moduleConfig?.customHeight ?? 0
    readonly property int innerColumns: root.moduleConfig?.innerColumns ?? 0
    readonly property string contentFitMode: root.moduleConfig?.contentFitMode ?? "scale"
    readonly property real moduleWidthRatio: root.customWidthRatio
    readonly property real moduleCustomHeight: root.customHeight
    readonly property int moduleInnerColumns: root.innerColumns
    readonly property string moduleContentFitMode: root.contentFitMode

    // Live drag-resize preview state (committed once on mouse release to avoid per-pixel config/layout thrashing)
    property real _resizePreviewWidthRatio: -1
    property real _resizePreviewHeight: -1
    property real _resizePreviewCanvasX: -1
    property real _resizePreviewCanvasY: -1
    property real _resizePreviewCanvasW: -1
    property real _resizePreviewCanvasH: -1

    readonly property real _effectiveWidthRatio: root._resizePreviewWidthRatio >= 0
        ? root._resizePreviewWidthRatio
        : root.customWidthRatio
    readonly property real _effectiveCustomHeight: root._resizePreviewHeight >= 0
        ? root._resizePreviewHeight
        : root.customHeight
    readonly property bool _hasExplicitHeight: root._effectiveCustomHeight > 0
        || (root.isCanvasMode && (root._resizePreviewCanvasH > 0 || (root.moduleConfig?.canvasH ?? 0) > 0))

    readonly property bool _foreignHosted: root._isForeignHosted
    readonly property string _hostedByCustomTabId: String(root._currentHostPage?.customTabId ?? "")
    readonly property bool isMovedToForeignPage: root.moduleId.length > 0
        && SettingsLayoutManager.isModuleMovedAway(root.moduleId, root._originPageIndex, "", root.settingsTaskSection || root._cardSubTabKey || "", false)
    readonly property bool isCanvasMode: Boolean(
        root._currentHostPage
        && root._currentHostPage.isCanvasLayoutMode
        && root.parent
        && root.parent.objectName === "freeformCanvasContainer"
    )
    readonly property bool hasCustomModuleSizing: root.customColumn !== "auto"
        || root.customWidthRatio > 0
        || root.customHeight > 0
        || root.innerColumns > 0
        || (root.moduleConfig?.order ?? 0) > 0
        || (root.moduleConfig?.canvasX ?? -1) >= 0
        || (root.moduleConfig?.canvasY ?? -1) >= 0
        || (root.moduleConfig?.canvasW ?? 0) > 0
        || (root.moduleConfig?.canvasH ?? 0) > 0
        || root.contentFitMode !== "scale"
        || root._isForeignHosted
        || (Boolean(root.moduleConfig?.targetSubTab) && root.moduleConfig?.targetSubTab !== (root.moduleConfig?.originSubTab ?? ""))

    // Responsive breakpoints based on actual rendered card width
    readonly property real renderedCardWidth: card.width
    readonly property real renderedCardHeight: card.height
    readonly property real contentScaleFactor: contentContainer._scaleFactor
    readonly property bool compactMode: card.width > 0 && card.width < 340
    readonly property bool wideMode: card.width >= 680
    readonly property int effectiveInnerColumns: root.innerColumns > 0
        ? root.innerColumns
        : (root.wideMode && sectionContent.children.length > 1 ? 2 : 1)

    // Ensure foreign-hosted or sub-tab-moved cards remain visible even if their origin page had a conditional visible binding
    Binding {
        target: root
        property: "visible"
        value: true
        when: (root._isForeignHosted || Boolean(root.moduleConfig?.targetSubTab)) && (root.moduleConfig?.visible ?? true)
        restoreMode: Binding.RestoreBindingOrValue
    }

    onModuleConfigChanged: {
        if (!Boolean(moduleEditOverlayLoader.item?.resizing)) {
            root._resizePreviewWidthRatio = -1;
            root._resizePreviewHeight = -1;
            root._resizePreviewCanvasX = -1;
            root._resizePreviewCanvasY = -1;
            root._resizePreviewCanvasW = -1;
            root._resizePreviewCanvasH = -1;
        }
        if (root.isCanvasMode && root.moduleConfig) {
            if (root.moduleConfig.canvasX >= 0)
                root.x = root.moduleConfig.canvasX;
            if (root.moduleConfig.canvasY >= 0)
                root.y = root.moduleConfig.canvasY;
            if (root.moduleConfig.canvasW > 0) {
                root.width = root.moduleConfig.canvasW;
            } else if (root._currentHostPage) {
                const availW = Math.max(480, root._currentHostPage.width - 48);
                root.width = Math.max(240, Math.floor((availW - SettingsMaterialPreset.pageSpacing) / 2));
            }
            if (root.moduleConfig.canvasH > 0) {
                root.height = root.moduleConfig.canvasH;
            } else {
                root.height = Math.max(120, Math.round(root.naturalCardImplicitHeight));
            }
        }
    }

    readonly property real chromeImplicitHeight: (root.showHeader ? (headerBackground.implicitHeight + SettingsMaterialPreset.groupSpacing) : 0) + (root.flatEmbedded ? 0 : SettingsMaterialPreset.cardPadding * 2)
    readonly property real naturalCardImplicitHeight: sectionContent.implicitHeight + root.chromeImplicitHeight
    readonly property real cardImplicitHeight: root._effectiveCustomHeight > 0
        ? Math.max(88, root._effectiveCustomHeight)
        : card.implicitHeight
    readonly property real _effectiveCardHeight: root._effectiveCustomHeight > 0
        ? Math.max(88, root._effectiveCustomHeight)
        : (card.implicitHeight + Math.max(0, root._bentoExtraHeight))
    readonly property real _bottomGap: (!root.isCanvasMode && root._cardSubTabActive && root._hasNextActiveCard)
        ? SettingsMaterialPreset.pageSpacing
        : 0
    readonly property bool effectiveCollapsible: false

    clip: !root._cardSubTabActive
    opacity: root._cardSubTabActive ? 1 : 0
    enabled: root._cardSubTabActive

    readonly property real _parentAvailableWidth: Math.max(220, root.width > 0 ? root.width : (root.parent ? root.parent.width : 480))

    // Keep root filling its column slot so parent ColumnLayout never collapses when card.width is scaled down
    Layout.fillWidth: !root.isCanvasMode
    Layout.preferredWidth: -1
    Layout.maximumWidth: 16777215
    Layout.fillHeight: false
    Layout.alignment: Qt.AlignTop
    Layout.preferredHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0
    Layout.maximumHeight: root._cardSubTabActive
        ? ((root.Layout.fillHeight && root._effectiveCustomHeight <= 0) ? 16777215 : (root._effectiveCardHeight + root._bottomGap))
        : 0
    Layout.minimumHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0
    implicitHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0

    property bool showMoveMenu: false
    onShowMoveMenuChanged: {
        if (root.showMoveMenu) {
            if (root.moduleId.length > 0)
                SettingsLayoutManager.openCustomizeModuleId = root.moduleId;
        } else if (SettingsLayoutManager.openCustomizeModuleId === root.moduleId) {
            SettingsLayoutManager.openCustomizeModuleId = "";
        }
    }

    Connections {
        target: SettingsLayoutManager
        function onOpenCustomizeModuleIdChanged() {
            if (root.showMoveMenu && SettingsLayoutManager.openCustomizeModuleId !== root.moduleId)
                root.showMoveMenu = false;
        }
    }

    z: root.showMoveMenu
        ? 100
        : (Boolean(moduleEditOverlayLoader.item?.resizing || moduleEditOverlayLoader.item?.isBeingDragged)
            ? 90
            : (Boolean(moduleEditOverlayLoader.item?.isSelected)
                ? 30
                : (root.isModuleEditHovered ? 20 : 0)))

    function _findTopPage() {
        var p = root._initialParent ? root._initialParent : root.parent;
        while (p) {
            if (p.hasOwnProperty("settingsPageIndex")) {
                return p;
            }
            p = p.parent;
        }
        return null;
    }

    function _syncModuleRegistration() {
        var originIdx = root._originPageIndex;
        if (originIdx < 0 && root._topPage && root._topPage.settingsPageIndex !== undefined && root._topPage.settingsPageIndex >= 0)
            originIdx = root._topPage.settingsPageIndex;
        root._originPageIndex = originIdx;

        if (originIdx >= 0 && (!root.moduleId || root.moduleId.indexOf("custom:") === 0)
                && root._participatesInLayout && (root.title || root._declarationOrder >= 0)) {
            if (root.moduleId) {
                SettingsLayoutManager.unregisterLiveCard(root.moduleId, root);
                SettingsLayoutManager.unregisterDropTarget("card:" + root.moduleId, root);
            }
            root.moduleId = SettingsLayoutManager.makeModuleId(originIdx, root.title, root._declarationOrder);
        }
        if (root.moduleId && root._participatesInLayout && originIdx >= 0) {
            SettingsLayoutManager.registerLiveCard(root.moduleId, root, {
                title: root.title,
                icon: root.icon || "tune",
                originPageIndex: originIdx,
                originSubTab: root.settingsTaskSection || root._cardSubTabKey || ""
            });
            SettingsLayoutManager.registerDropTarget("card:" + root.moduleId, root, {
                kind: "card",
                moduleId: root.moduleId,
                pageIndex: (root._currentHostPage && root._currentHostPage.settingsPageIndex !== undefined)
                    ? root._currentHostPage.settingsPageIndex
                    : originIdx,
                customTabId: String(root._currentHostPage?.customTabId ?? ""),
                subTabKey: String(root._currentHostPage?.activeSubTabKey ?? ""),
                column: root.bentoColumn || root.customColumn || "auto",
                peerModuleIds: root._peerModuleIds,
                label: root.title
            });
        }
    }

    function _ensureTopPage() {
        if (!root._initialParent && root.parent) {
            root._initialParent = root.parent;
        }
        var found = _findTopPage();
        if (found !== root._topPage) {
            if (root._topPage && typeof root._topPage.unregisterCardSection === "function") {
                root._topPage.unregisterCardSection(root);
            }
            root._topPage = found;
            if (!root._currentHostPage)
                root._currentHostPage = found;
            if (root._topPage && typeof root._topPage.registerCardSection === "function") {
                root._topPage.registerCardSection(root);
            }
        }
        root._syncModuleRegistration();
    }

    onBentoColumnChanged: root._syncModuleRegistration()
    on_PeerModuleIdsChanged: root._syncModuleRegistration()
    on_CurrentHostPageChanged: root._syncModuleRegistration()

    Timer {
        id: topPageSyncTimer
        interval: 0
        repeat: false
        onTriggered: {
            root._ensureTopPage();
            if (root._topPage && typeof root._topPage.notifyCardEligibilityChanged === "function") {
                root._topPage.notifyCardEligibilityChanged();
            }
        }
    }

    function isCardEligibleForTabs() {
        if (!root._participatesInLayout || !root.title || root.title.length === 0)
            return false;
        if (!root.visible)
            return false;
        if (root.moduleConfig && root.moduleConfig.visible === false)
            return false;
        var hostPage = root._currentHostPage ? root._currentHostPage : root._topPage;
        if (!root._isForeignHosted && root.moduleId && hostPage) {
            var hostPageIdx = hostPage.settingsPageIndex !== undefined ? hostPage.settingsPageIndex : -1;
            var hostCustomTabId = String(hostPage.customTabId ?? "");
            var hostSubTab = String(hostPage.activeSubTabKey ?? "");
            var hostHasSubTabs = Boolean(hostPage._hasEffectiveSubTabs);
            if (SettingsLayoutManager.isModuleMovedAway(root.moduleId, hostPageIdx, hostCustomTabId, hostSubTab, hostHasSubTabs))
                return false;
        }
        if (!root._isForeignHosted
                && !(root.moduleConfig && root.moduleConfig.targetSubTab)) {
            if (root._topPage && root._topPage.customActiveSubTab && root._topPage.customActiveSubTab.length > 0
                    && root._topPage.activeSubTabKey === root._topPage.customActiveSubTab) {
                return false;
            }
            if (root.settingsTaskSection && root.settingsTaskSection.length > 0
                    && root._topPage && root._topPage._hasTaskNavigatorTabs
                    && root._topPage.settingsTaskNavigator) {
                var navOpts = root._topPage.settingsTaskNavigator.options || [];
                var currentTask = (root._topPage.hasOwnProperty("activeSection") && root._topPage.activeSection !== undefined && String(root._topPage.activeSection).length > 0)
                    ? String(root._topPage.activeSection)
                    : String(root._topPage.settingsTaskNavigator.currentValue ?? "");
                var matchesNavOption = false;
                for (var i = 0; i < navOpts.length; i++) {
                    if (String(navOpts[i]?.value ?? "") === root.settingsTaskSection) {
                        matchesNavOption = true;
                        break;
                    }
                }
                var effectiveTaskSection = root.settingsTaskSection;
                var effSpecs = root._topPage.effectiveSubTabSpecs || [];
                if (effSpecs.length > 0 && !effSpecs.some(function(s) { return s && s.key === effectiveTaskSection; })) {
                    effectiveTaskSection = String(effSpecs[0]?.key ?? "");
                }
                if (matchesNavOption && currentTask.length > 0 && effectiveTaskSection !== currentTask) {
                    return false;
                }
            }
        }
        return true;
    }

    function ensureControlOnActiveSectionSubTab(control) {
        // Pagination is handled at ContentPage level.
    }

    function rowPeerSections() {
        return [root];
    }

    function setRowExpanded(nextExpanded) {
        if (root._topPage && root._topPage.hasCardSubTabs) {
            root.expanded = true;
            return;
        }
        root.expanded = nextExpanded;
    }

    onVisibleChanged: {
        topPageSyncTimer.restart();
        if (root._topPage && !root._topPage._isDestroying && typeof root._topPage.notifyCardEligibilityChanged === "function") {
            root._topPage.notifyCardEligibilityChanged();
        }
    }

    onTitleChanged: {
        root._syncModuleRegistration();
        if (root._topPage && !root._topPage._isDestroying && typeof root._topPage.notifyCardEligibilityChanged === "function") {
            root._topPage.notifyCardEligibilityChanged();
        }
    }

    onNaturalCardImplicitHeightChanged: {
        var host = root._currentHostPage ? root._currentHostPage : root._topPage;
        if (root.visible && host && !host._isDestroying && typeof host._scheduleBentoHeightSync === "function") {
            host._scheduleBentoHeightSync();
        }
    }

    function _findSettingsContext() {
        var page = null;
        var p = root._initialParent ? root._initialParent : root.parent;
        while (p) {
            if (!page && p.hasOwnProperty("settingsPageIndex")) {
                page = p;
                break;
            }
            p = p.parent;
        }
        return { page: page };
    }

    function focusFromSettingsSearch() {
        if (root._topPage && typeof root._topPage.selectCardSection === "function") {
            root._topPage.selectCardSection(root);
        }
        root.expanded = true;
        root.forceActiveFocus();
    }

    Component.onCompleted: {
        root._ensureTopPage();
        topPageSyncTimer.restart();

        if (!enableSettingsSearch || !root.title)
            return;
        if (typeof SettingsSearchRegistry === "undefined")
            return;

        if (SettingsSearchRegistry.registerCollapsibleSection) {
            SettingsSearchRegistry.registerCollapsibleSection(root);
        }

        var ctx = _findSettingsContext();
        var page = ctx.page;

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: root.title,
            label: root.title,
            description: "",
            keywords: []
        });
    }

    Component.onDestruction: {
        topPageSyncTimer.stop();
        if (root.moduleId) {
            SettingsLayoutManager.unregisterDropTarget("card:" + root.moduleId, root);
            SettingsLayoutManager.unregisterLiveCard(root.moduleId, root);
        }
        if (typeof SettingsSearchRegistry !== "undefined") {
            if (SettingsSearchRegistry.unregisterCollapsibleSection) {
                SettingsSearchRegistry.unregisterCollapsibleSection(root);
            }
            SettingsSearchRegistry.unregisterControl(root);
        }
    }

    // Lightweight Material offset shadow avoids a GPU-blurred shadow per card.
    Rectangle {
        visible: Appearance.effectsEnabled
        opacity: root._cardSubTabActive ? 1 : 0
        x: card.x + 0.5
        y: card.y + 1.5
        width: card.width
        height: card.height
        radius: card.radius
        color: Appearance.colors.colShadow
        z: -1
    }

    // Subtle Material left accent bar when expanded.
    Rectangle {
        id: accentBar
        visible: root._cardSubTabActive && root.showHeader
        anchors {
            left: card.left
            top: card.top
            bottom: card.bottom
            leftMargin: 0
            topMargin: SettingsMaterialPreset.cardRadius
            bottomMargin: SettingsMaterialPreset.cardRadius
        }
        width: 2
        radius: 1
        color: SettingsMaterialPreset.accentColor
        opacity: root.expanded
            ? 0.6
            : (headerMouseArea.containsMouse ? 0.3 : 0)
        z: 1
        Behavior on opacity {
            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on width {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    Rectangle {
        id: card
        visible: true

        anchors.left: parent.left
        anchors.top: parent.top
        width: root.isCanvasMode
            ? Math.max(180, root.width)
            : ((root._effectiveWidthRatio > 0 && root._effectiveWidthRatio < 0.99)
                ? Math.max(200, Math.round(root.width * root._effectiveWidthRatio))
                : root.width)
        height: root.isCanvasMode
            ? Math.max(88, root.height)
            : (root._effectiveCustomHeight > 0
                ? root._effectiveCardHeight
                : Math.max(root._effectiveCardHeight, root.height - root._bottomGap))
        implicitHeight: (root.expanded ? (root._effectiveCustomHeight > 0 ? Math.max(48, root._effectiveCustomHeight - root.chromeImplicitHeight) : contentContainer._scaledNaturalContentHeight) : 0) + root.chromeImplicitHeight
        radius: root.flatEmbedded ? 0 : SettingsMaterialPreset.cardRadius
        color: root.flatEmbedded ? "transparent" : SettingsMaterialPreset.cardColor
        border.width: (root.flatEmbedded || Config.options?.panelFamily === "abyss") ? 0 : 1
        border.color: SettingsMaterialPreset.cardBorderColor

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on border.width {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                margins: root.flatEmbedded
                    ? 0
                    : (root.compactMode
                        ? Math.max(8, Math.round(SettingsMaterialPreset.cardPadding * 0.72))
                        : SettingsMaterialPreset.cardPadding)
            }
            spacing: root.compactMode
                ? Math.max(6, Math.round(SettingsMaterialPreset.groupSpacing * 0.75))
                : SettingsMaterialPreset.groupSpacing

            Rectangle {
                id: headerBackground
                visible: root.showHeader
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + SettingsMaterialPreset.headerPaddingY * 2
                radius: SettingsMaterialPreset.headerRadius
                color: headerMouseArea.containsMouse && root.effectiveCollapsible
                    ? SettingsMaterialPreset.headerHoverColor
                    : ColorUtils.applyAlpha(SettingsMaterialPreset.headerHoverColor, 0)

                Behavior on color {
                    animation: ColorAnimation { duration: Appearance.animation.stateChange.duration; easing.type: Appearance.animation.stateChange.type; easing.bezierCurve: Appearance.animation.stateChange.bezierCurve }
                }

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.leftMargin: SettingsMaterialPreset.headerPaddingX
                    anchors.rightMargin: SettingsMaterialPreset.headerPaddingX
                    spacing: 8

                    // Icon with expand-state color
                    Loader {
                        active: root.icon && root.icon.length > 0
                        visible: active
                        Layout.alignment: Qt.AlignVCenter

                        readonly property color _iconColor: root.expanded
                            ? SettingsMaterialPreset.iconExpandedColor
                            : SettingsMaterialPreset.iconCollapsedColor

                        sourceComponent: Item {
                            id: iconHost
                            implicitWidth: Appearance.font.pixelSize.larger
                            implicitHeight: implicitWidth
                            readonly property color iconColor: root.expanded
                                ? SettingsMaterialPreset.iconExpandedColor
                                : SettingsMaterialPreset.iconCollapsedColor

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.icon
                                iconSize: Appearance.font.pixelSize.larger
                                color: iconHost.iconColor

                                Behavior on color {
                                    animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        verticalAlignment: Text.AlignVCenter
                        text: root.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        marquee: true
                        maximumLineCount: 1
                        color: root.expanded
                            ? SettingsMaterialPreset.titleExpandedColor
                            : SettingsMaterialPreset.titleCollapsedColor

                        Behavior on color {
                            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }

                    // Foreign origin badge when moved from another tab/page
                    Rectangle {
                        visible: root._isForeignHosted && root._originPageIndex >= 0
                        Layout.alignment: Qt.AlignVCenter
                        height: 20
                        width: originBadgeRow.implicitWidth + 10
                        radius: 10
                        color: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colPrimary, 0.35)

                        Row {
                            id: originBadgeRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "shortcut"
                                iconSize: 12
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: SettingsLayoutManager.availablePages?.[root._originPageIndex]?.name ?? ("Page " + root._originPageIndex)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }

                    MaterialSymbol {
                        visible: root.effectiveCollapsible
                        Layout.alignment: Qt.AlignVCenter
                        text: "expand_more"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        rotation: root.expanded ? 180 : 0
                        Behavior on rotation {
                            enabled: Appearance.animationsEnabled
                            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }

                }

                MouseArea {
                    id: headerMouseArea
                    anchors.fill: parent
                    hoverEnabled: root.effectiveCollapsible
                    cursorShape: root.effectiveCollapsible ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.effectiveCollapsible) {
                            root.setRowExpanded(!root.expanded);
                        }
                    }
                }
            }

            Item {
                id: contentContainer
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.fillHeight: root.expanded
                implicitHeight: root.expanded
                    ? (root._effectiveCustomHeight > 0
                        ? Math.max(48, root._effectiveCustomHeight - root.chromeImplicitHeight)
                        : contentContainer._scaledNaturalContentHeight)
                    : 0
                clip: true
                enabled: root.expanded

                // Acyclic base width: sectionContent.width NEVER depends on _scaleFactor or implicitHeight,
                // preventing Flow / word-wrap fixed-point oscillation when scaling modules.
                readonly property real _naturalColumnContentWidth: Math.max(
                    380,
                    Math.min(
                        (root.bentoColumn === "full" || root.customColumn === "full") ? 760 : 468,
                        (root.isCanvasMode ? 460 : root.width) - SettingsMaterialPreset.cardPadding * 2
                    )
                )
                readonly property real _baseContentWidth: root.contentFitMode === "scale"
                    ? ((root._effectiveWidthRatio > 0 && root._effectiveWidthRatio < 0.99)
                        ? Math.max(contentFlickable.width, contentContainer._naturalColumnContentWidth)
                        : Math.max(380, contentFlickable.width))
                    : Math.max(1, contentFlickable.width)
                readonly property real _widthScale: (root.contentFitMode === "scale"
                    && contentFlickable.width > 0
                    && _baseContentWidth > 0)
                    ? Math.min(1.0, contentFlickable.width / _baseContentWidth)
                    : 1.0
                readonly property real _scaledNaturalContentHeight: root.contentFitMode === "scale"
                    ? Math.round(sectionContent.implicitHeight * contentContainer._widthScale)
                    : sectionContent.implicitHeight
                readonly property real _heightScale: (root._hasExplicitHeight
                    && root.contentFitMode === "scale"
                    && contentContainer.height > 0
                    && sectionContent.implicitHeight > contentContainer.height
                    && sectionContent.implicitHeight > 0)
                    ? Math.min(1.0, contentContainer.height / sectionContent.implicitHeight)
                    : 1.0
                readonly property real _scaleFactor: root.contentFitMode === "scale"
                    ? Math.max(0.35, Math.min(_widthScale, _heightScale))
                    : 1.0
                readonly property bool _needsScroll: root._hasExplicitHeight
                    && root.contentFitMode === "scroll"
                    && sectionContent.implicitHeight > contentContainer.height + 4

                Flickable {
                    id: contentFlickable
                    anchors.fill: parent
                    clip: true
                    interactive: contentContainer._needsScroll
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: root.contentFitMode === "scale"
                        ? Math.round(sectionContent.implicitHeight * contentContainer._scaleFactor)
                        : sectionContent.implicitHeight

                    onInteractiveChanged: {
                        if (!contentFlickable.interactive && contentFlickable.contentY !== 0)
                            contentFlickable.contentY = 0;
                    }

                    ScrollBar.vertical: StyledScrollBar {
                        policy: contentContainer._needsScroll ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        visible: contentContainer._needsScroll
                    }

                    ColumnLayout {
                        id: sectionContent
                        objectName: "sectionContent"
                        x: (root.contentFitMode === "scale" && contentContainer._scaleFactor < contentContainer._widthScale)
                            ? Math.max(0, Math.round((contentFlickable.width - width * contentContainer._scaleFactor) / 2))
                            : 0
                        width: contentContainer._baseContentWidth
                        height: (root._hasExplicitHeight || contentContainer.height > implicitHeight)
                            ? Math.max(implicitHeight, Math.floor(contentContainer.height / Math.max(0.35, contentContainer._scaleFactor)))
                            : ((!root.isCanvasMode && (root._consumesBentoExtraHeight || root._bentoExtraHeight > 0))
                                ? (implicitHeight + Math.max(0, root._bentoExtraHeight))
                                : implicitHeight)
                        spacing: root.compactMode
                            ? Math.max(6, Math.round(root.spacing * 0.75))
                            : root.spacing
                        opacity: root.expanded ? 1 : 0

                        transform: Scale {
                            origin.x: 0
                            origin.y: 0
                            xScale: contentContainer._scaleFactor
                            yScale: contentContainer._scaleFactor
                        }
                    }

                    SettingsInnerReorderOverlay {
                        anchors.fill: sectionContent
                        targetLayout: sectionContent
                        containerId: root.moduleId ? (root.moduleId + ":direct") : ""
                        activeInSettings: root.moduleId.length > 0 && root._participatesInLayout
                    }
                }
            }
        }

        HoverHandler {
            id: cardEditHover
            enabled: SettingsLayoutManager.editMode
        }
    }

    readonly property bool isModuleEditHovered: cardEditHover.hovered
        || Boolean(moduleEditOverlayLoader.item?.isControlsActive)

    // --- Edit Mode Overlay: Direct Header Drag, Clean Action Pill, Customize Popover & 8-Direction Resize Handles ---
    Loader {
        id: moduleEditOverlayLoader
        anchors.fill: card
        z: 40
        active: SettingsLayoutManager.editMode && root._participatesInLayout && root.moduleId.length > 0
        sourceComponent: Item {
            id: editOverlay
            objectName: "moduleEditOverlay"

            HoverHandler {
                id: overlayEditHover
            }

            readonly property bool isSelected: SettingsLayoutManager.selectedModuleId === root.moduleId
            readonly property bool isBeingDragged: SettingsLayoutManager.draggingModule
                && SettingsLayoutManager.draggedModuleId === root.moduleId
            readonly property bool isDropTargetHovered: SettingsLayoutManager.draggingModule
                && SettingsLayoutManager.hoveredDropTarget?.spec?.kind === "card"
                && SettingsLayoutManager.hoveredDropTarget?.spec?.moduleId === root.moduleId
            readonly property bool dropInsertAfter: Boolean(SettingsLayoutManager.hoveredDropTarget?.insertAfter)

            property bool resizing: false
            property string activeResizeEdge: ""

            readonly property bool isControlsActive: cardEditHover.hovered
                || overlayEditHover.hovered
                || editOverlay.isSelected
                || editOverlay.resizing
                || editOverlay.isBeingDragged
                || root.showMoveMenu

            function startDragFromPoint(scenePt) {
                SettingsLayoutManager.selectedModuleId = root.moduleId;
                root.showMoveMenu = false;
                if (root.isCanvasMode) {
                    const cfg = SettingsLayoutManager.getModuleConfig(root.moduleId);
                    editOverlay.startCanvasX = cfg.canvasX >= 0 ? cfg.canvasX : root.x;
                    editOverlay.startCanvasY = cfg.canvasY >= 0 ? cfg.canvasY : root.y;
                    editOverlay.dragStartSceneX = scenePt.x;
                    editOverlay.dragStartSceneY = scenePt.y;
                }
                SettingsLayoutManager.beginModuleDrag(root.moduleId, root, scenePt.x, scenePt.y);
            }

            function updateDragFromPoint(scenePt) {
                SettingsLayoutManager.updateModuleDrag(scenePt.x, scenePt.y);
                if (root.isCanvasMode && (!SettingsLayoutManager.hoveredDropTarget || SettingsLayoutManager.hoveredDropTarget.spec?.kind === "canvas")) {
                    const dx = scenePt.x - editOverlay.dragStartSceneX;
                    const dy = scenePt.y - editOverlay.dragStartSceneY;
                    const nx = Math.max(0, Math.round(editOverlay.startCanvasX + dx));
                    const ny = Math.max(0, Math.round(editOverlay.startCanvasY + dy));
                    root._resizePreviewCanvasX = nx;
                    root._resizePreviewCanvasY = ny;
                    root.x = nx;
                    root.y = ny;
                }
            }

            function finishDragFromPoint(scenePt) {
                if (root.isCanvasMode && root._resizePreviewCanvasX >= 0 && (!SettingsLayoutManager.hoveredDropTarget || SettingsLayoutManager.hoveredDropTarget.spec?.kind === "canvas")) {
                    const finalX = root._resizePreviewCanvasX;
                    const finalY = root._resizePreviewCanvasY;
                    root._resizePreviewCanvasX = -1;
                    root._resizePreviewCanvasY = -1;
                    SettingsLayoutManager.cancelModuleDrag();
                    SettingsLayoutManager.resizeModule(root.moduleId, {
                        canvasX: finalX,
                        canvasY: finalY
                    });
                    return;
                }
                root._resizePreviewCanvasX = -1;
                root._resizePreviewCanvasY = -1;
                SettingsLayoutManager.finishModuleDrag(scenePt.x, scenePt.y);
            }

            // Selection & Edit border around card
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: editOverlay.isBeingDragged
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    : (editOverlay.resizing ? Qt.alpha(Appearance.colors.colPrimary, 0.08) : "transparent")
                border.width: editOverlay.isSelected || editOverlay.resizing || editOverlay.isDropTargetHovered ? 2 : 1
                border.color: editOverlay.isDropTargetHovered
                    ? Appearance.colors.colPrimary
                    : (editOverlay.isSelected || editOverlay.resizing
                        ? Appearance.colors.colPrimary
                        : (editOverlay.isControlsActive
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.55)
                            : Qt.alpha(Appearance.colors.colPrimary, 0.20)))
            }

            // Direct Header Drag Area: grab anywhere on the module header to drag-and-drop or click to select
            MouseArea {
                id: headerDirectDragArea
                anchors.left: parent.left
                anchors.right: cardEditToolbar.visible ? cardEditToolbar.left : parent.right
                anchors.top: parent.top
                anchors.margins: 4
                height: root.showHeader ? Math.max(32, headerBackground.height + 8) : 14
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property point pressScenePt: Qt.point(0, 0)
                property bool dragStarted: false

                onPressed: mouse => {
                    SettingsLayoutManager.selectedModuleId = root.moduleId;
                    pressScenePt = headerDirectDragArea.mapToItem(null, mouse.x, mouse.y);
                    dragStarted = false;
                }

                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const scenePt = headerDirectDragArea.mapToItem(null, mouse.x, mouse.y);
                    if (!dragStarted) {
                        if (Math.hypot(scenePt.x - pressScenePt.x, scenePt.y - pressScenePt.y) < 5)
                            return;
                        dragStarted = true;
                        editOverlay.startDragFromPoint(pressScenePt);
                    }
                    editOverlay.updateDragFromPoint(scenePt);
                }

                onReleased: mouse => {
                    if (dragStarted) {
                        const scenePt = headerDirectDragArea.mapToItem(null, mouse.x, mouse.y);
                        editOverlay.finishDragFromPoint(scenePt);
                    }
                    dragStarted = false;
                }

                onCanceled: {
                    if (dragStarted)
                        SettingsLayoutManager.cancelModuleDrag();
                    dragStarted = false;
                }
            }

            // Drop insertion line indicator when another module is dragged over this card
            Rectangle {
                visible: editOverlay.isDropTargetHovered
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                y: editOverlay.dropInsertAfter ? (parent.height - 3) : 0
                height: 4
                radius: 2
                color: Appearance.colors.colPrimary
            }

            // Simplified Top-Right Module Edit Pill: Drag + Reset (when customized) + Customize Popover
            Rectangle {
                id: cardEditToolbar
                objectName: "cardEditToolbar"
                visible: editOverlay.isControlsActive
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 8
                anchors.topMargin: 6
                height: 28
                width: actionBarRow.implicitWidth + 10
                radius: 14
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.55)

                Row {
                    id: actionBarRow
                    anchors.centerIn: parent
                    spacing: 4

                    // 1. Drag Handle
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 22
                        radius: 11
                        color: moduleDragArea.pressed
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.30)
                            : (moduleDragArea.containsMouse ? Qt.alpha(Appearance.colors.colPrimary, 0.18) : "transparent")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "drag_indicator"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }

                        MouseArea {
                            id: moduleDragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            onPressed: mouse => {
                                const scenePt = moduleDragArea.mapToItem(null, mouse.x, mouse.y);
                                editOverlay.startDragFromPoint(scenePt);
                            }

                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return;
                                const scenePt = moduleDragArea.mapToItem(null, mouse.x, mouse.y);
                                editOverlay.updateDragFromPoint(scenePt);
                            }

                            onReleased: mouse => {
                                const scenePt = moduleDragArea.mapToItem(null, mouse.x, mouse.y);
                                editOverlay.finishDragFromPoint(scenePt);
                            }

                            onCanceled: SettingsLayoutManager.cancelModuleDrag()
                        }

                        StyledToolTip {
                            extraVisibleCondition: moduleDragArea.containsMouse && !moduleDragArea.pressed
                            text: Translation.tr("Drag to move this module to another column, sub-tab, or sidebar tab")
                        }
                    }

                    // 2. Quick Reset Pill (visible only when module has custom size/column/tab placement)
                    Rectangle {
                        objectName: "moduleResetQuickButton"
                        visible: root.hasCustomModuleSizing
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        width: resetQuickRow.implicitWidth + 12
                        radius: 11
                        color: resetModMouse.containsMouse
                            ? Qt.alpha(Appearance.colors.colError, 0.22)
                            : Qt.alpha(Appearance.colors.colLayer2, 0.85)

                        Row {
                            id: resetQuickRow
                            anchors.centerIn: parent
                            spacing: 3

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "restart_alt"
                                iconSize: 13
                                color: resetModMouse.containsMouse ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Reset")
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: resetModMouse.containsMouse ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                            }
                        }

                        MouseArea {
                            id: resetModMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.showMoveMenu = false;
                                SettingsLayoutManager.resetModule(root.moduleId);
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: resetModMouse.containsMouse
                            text: Translation.tr("Reset this module to its default size and position")
                        }
                    }

                    // 3. Unified "Customize" Button (opens clear, labeled module options & move menu)
                    Rectangle {
                        id: customizeBtn
                        objectName: "moduleCustomizeButton"
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        width: customizeBtnRow.implicitWidth + 14
                        radius: 11
                        color: root.showMoveMenu || moveMenuMouse.containsMouse
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.25)
                            : Qt.alpha(Appearance.colors.colPrimary, 0.14)

                        Row {
                            id: customizeBtnRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "tune"
                                iconSize: 13
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Customize")
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                            }
                        }

                        MouseArea {
                            id: moveMenuMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                SettingsLayoutManager.selectedModuleId = root.moduleId;
                                root.showMoveMenu = !root.showMoveMenu;
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: moveMenuMouse.containsMouse && !root.showMoveMenu
                            text: Translation.tr("Customize module column, width, scale/scroll behavior, or move to another tab")
                        }
                    }
                }
            }

            // Unified Module Customize Popover (clear, labeled controls for Placement, Width, Fit Mode, Move & Hide)
            Rectangle {
                id: moveTargetPopup
                objectName: "moduleCustomizePopover"
                visible: root.showMoveMenu
                anchors.right: parent.right
                anchors.top: cardEditToolbar.bottom
                anchors.rightMargin: 8
                anchors.topMargin: 4
                width: Math.min(288, Math.max(236, parent.width - 16))
                height: Math.min(Math.max(220, parent.height - 42), movePopupColumn.implicitHeight + 20)
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.55)
                z: 60
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: width
                    contentHeight: movePopupColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: movePopupColumn
                        width: parent.width
                        spacing: 8

                        // Section 1: Column Placement
                        StyledText {
                            text: Translation.tr("Column Placement")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { col: "auto", label: Translation.tr("Auto"), icon: "auto_awesome" },
                                    { col: "full", label: Translation.tr("Full"), icon: "view_agenda" },
                                    { col: "left", label: Translation.tr("Left"), icon: "dock_to_left" },
                                    { col: "right", label: Translation.tr("Right"), icon: "dock_to_right" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isCurrentCol: root.customColumn === modelData.col
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: Appearance.rounding.small
                                    color: isCurrentCol
                                        ? Appearance.colors.colPrimaryContainer
                                        : (colOptMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                                    border.width: isCurrentCol ? 1 : 0
                                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.icon
                                            iconSize: 13
                                            color: parent.parent.isCurrentCol ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: modelData.label
                                            font.pixelSize: 10
                                            font.weight: parent.parent.isCurrentCol ? Font.DemiBold : Font.Medium
                                            color: parent.parent.isCurrentCol ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        }
                                    }

                                    MouseArea {
                                        id: colOptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SettingsLayoutManager.resizeModule(root.moduleId, { column: modelData.col })
                                    }
                                }
                            }
                        }

                        // Section 2: Module Width Preset
                        StyledText {
                            text: Translation.tr("Module Width")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { ratio: 0, label: "100%" },
                                    { ratio: 0.85, label: "85%" },
                                    { ratio: 0.75, label: "75%" },
                                    { ratio: 0.6, label: "60%" },
                                    { ratio: 0.5, label: "50%" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isCurrentWidth: (modelData.ratio === 0 && root.customWidthRatio <= 0)
                                        || (modelData.ratio > 0 && Math.abs(root.customWidthRatio - modelData.ratio) < 0.04)
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Appearance.rounding.small
                                    color: isCurrentWidth
                                        ? Appearance.colors.colPrimaryContainer
                                        : (widthOptMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                                    border.width: isCurrentWidth ? 1 : 0
                                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                                    StyledText {
                                        anchors.centerIn: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData.label
                                        font.pixelSize: 10
                                        font.weight: parent.isCurrentWidth ? Font.DemiBold : Font.Medium
                                        color: parent.isCurrentWidth ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                    }

                                    MouseArea {
                                        id: widthOptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SettingsLayoutManager.resizeModule(root.moduleId, { widthRatio: modelData.ratio })
                                    }
                                }
                            }
                        }

                        // Section 3: Resize Fit Mode (Auto Scale vs Scroll)
                        StyledText {
                            text: Translation.tr("When Resized")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { mode: "scale", label: Translation.tr("Auto Scale"), icon: "fit_screen" },
                                    { mode: "scroll", label: Translation.tr("Scroll"), icon: "swap_vert" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isCurrentFit: root.contentFitMode === modelData.mode
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: Appearance.rounding.small
                                    color: isCurrentFit
                                        ? Appearance.colors.colPrimaryContainer
                                        : (fitOptMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                                    border.width: isCurrentFit ? 1 : 0
                                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.icon
                                            iconSize: 13
                                            color: parent.parent.isCurrentFit ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: modelData.label
                                            font.pixelSize: 10
                                            font.weight: parent.parent.isCurrentFit ? Font.DemiBold : Font.Medium
                                            color: parent.parent.isCurrentFit ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        }
                                    }

                                    MouseArea {
                                        id: fitOptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SettingsLayoutManager.resizeModule(root.moduleId, { contentFitMode: modelData.mode })
                                    }
                                }
                            }
                        }

                        // Section 4: Quick Actions (Reset / Return to Origin / Hide)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Rectangle {
                                visible: root.hasCustomModuleSizing || root._isForeignHosted
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Appearance.rounding.small
                                color: popupResetMouse.containsMouse
                                    ? Qt.alpha(Appearance.colors.colPrimary, 0.22)
                                    : Appearance.colors.colLayer2

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root._isForeignHosted ? "undo" : "restart_alt"
                                        iconSize: 13
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: root._isForeignHosted
                                            ? Translation.tr("Return to Origin")
                                            : Translation.tr("Reset Default")
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colPrimary
                                    }
                                }

                                MouseArea {
                                    id: popupResetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.showMoveMenu = false;
                                        SettingsLayoutManager.resetModule(root.moduleId);
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Appearance.rounding.small
                                color: popupHideMouse.containsMouse
                                    ? Qt.alpha(Appearance.colors.colError, 0.22)
                                    : Appearance.colors.colLayer2

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "visibility_off"
                                        iconSize: 13
                                        color: popupHideMouse.containsMouse ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Hide Module")
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: popupHideMouse.containsMouse ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                                    }
                                }

                                MouseArea {
                                    id: popupHideMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.showMoveMenu = false;
                                        SettingsLayoutManager.setModuleVisible(root.moduleId, false);
                                    }
                                }
                            }
                        }

                        // Section 5: Move Module To Tab / Sub-Tab
                        StyledText {
                            text: Translation.tr("Move Module To Tab")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        // Sub-tabs of the current host page
                        Repeater {
                            model: (root._currentHostPage && root._currentHostPage.effectiveSubTabSpecs)
                                ? root._currentHostPage.effectiveSubTabSpecs
                                : []

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Appearance.rounding.small
                                color: subTabMoveMouse.containsMouse
                                    ? Appearance.colors.colLayer2Hover
                                    : Appearance.colors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData.icon || "tab"
                                        iconSize: 14
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: `${Translation.tr("Sub-Tab")}: ${modelData.label}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: subTabMoveMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const hp = root._currentHostPage;
                                        SettingsLayoutManager.moveModuleToTarget(root.moduleId, {
                                            targetPageIndex: (hp && hp.settingsPageIndex !== undefined) ? hp.settingsPageIndex : root._originPageIndex,
                                            targetCustomTabId: String(hp?.customTabId ?? ""),
                                            targetSubTab: String(modelData.key ?? "")
                                        });
                                        root.showMoveMenu = false;
                                    }
                                }
                            }
                        }

                        // Custom Sidebar Tabs
                        Repeater {
                            model: SettingsLayoutManager.customTabs

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Appearance.rounding.small
                                color: customTabMoveMouse.containsMouse
                                    ? Appearance.colors.colLayer2Hover
                                    : Appearance.colors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData.icon || "dashboard_customize"
                                        iconSize: 14
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: `${Translation.tr("Custom Tab")}: ${modelData.label}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: customTabMoveMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        SettingsLayoutManager.moveModuleToTarget(root.moduleId, {
                                            targetPageIndex: -1,
                                            targetCustomTabId: modelData.id,
                                            targetSubTab: ""
                                        });
                                        root.showMoveMenu = false;
                                    }
                                }
                            }
                        }

                        // Quick button: Move to a newly created Custom Tab
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: Appearance.rounding.small
                            color: newTabMoveMouse.containsMouse
                                ? Qt.alpha(Appearance.colors.colPrimary, 0.25)
                                : Qt.alpha(Appearance.colors.colPrimary, 0.14)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "add_box"
                                    iconSize: 14
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("+ New Custom Tab with this Module")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colPrimary
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: newTabMoveMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const newTabId = SettingsLayoutManager.createCustomTab(root.title || "Custom Tab", root.icon || "tune", 0);
                                    SettingsLayoutManager.moveModuleToTarget(root.moduleId, {
                                        targetPageIndex: -1,
                                        targetCustomTabId: newTabId,
                                        targetSubTab: ""
                                    });
                                    root.showMoveMenu = false;
                                }
                            }
                        }

                        // Built-in Sidebar Pages
                        Repeater {
                            model: SettingsLayoutManager.availableNavigationPages

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Appearance.rounding.small
                                color: pageMoveMouse.containsMouse
                                    ? Appearance.colors.colLayer2Hover
                                    : Appearance.colors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData.icon || "settings"
                                        iconSize: 14
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: pageMoveMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        SettingsLayoutManager.moveModuleToTarget(root.moduleId, {
                                            targetPageIndex: modelData.pageIndex ?? modelData.index,
                                            targetCustomTabId: "",
                                            targetSubTab: ""
                                        });
                                        root.showMoveMenu = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Live Size & Scale Badge at bottom-right of the module (shown only when hovered / active)
            Rectangle {
                visible: editOverlay.isControlsActive && (editOverlay.resizing || editOverlay.isSelected || root.hasCustomModuleSizing)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 10
                anchors.bottomMargin: 8
                height: 22
                width: sizeBadgeRow.implicitWidth + 12
                radius: 11
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.55)

                Row {
                    id: sizeBadgeRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        text: `${Math.round(card.width)} × ${Math.round(card.height)} px`
                        font.pixelSize: 10
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        visible: root._effectiveWidthRatio > 0
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        text: `• ${Math.round(root._effectiveWidthRatio * 100)}%W`
                        font.pixelSize: 10
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        visible: contentContainer._scaleFactor < 0.99
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        text: `• ${Math.round(contentContainer._scaleFactor * 100)}% scale`
                        font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            property real dragStartSceneX: 0
            property real dragStartSceneY: 0
            property real startWidthPx: 0
            property real startHeightPx: 0
            property real startCanvasX: 0
            property real startCanvasY: 0

            // Resize Handles (E, S, SE in Bento mode; E, W, S, SW, SE in Canvas mode) with live preview & double-click reset
            component CardResizeHandle: Rectangle {
                id: rh
                objectName: "cardResizeHandle_" + rh.edge
                required property string edge
                readonly property bool isCorner: edge.length === 2
                readonly property bool isHorizontal: edge === "e" || edge === "w"
                readonly property bool isHandleEnabled: rh.edge === "e"
                    || rh.edge === "s"
                    || rh.edge === "se"
                    || (root.isCanvasMode && (rh.edge === "w" || rh.edge === "sw"))

                visible: editOverlay.isControlsActive && rh.isHandleEnabled
                width: isCorner ? 14 : (isHorizontal ? 7 : 36)
                height: isCorner ? 14 : (isHorizontal ? 36 : 7)
                radius: width / 2
                color: rhMouse.pressed || rhMouse.containsMouse
                    ? Appearance.colors.colPrimary
                    : Qt.alpha(Appearance.colors.colPrimary, 0.55)

                anchors.top: edge.includes("n") ? parent.top : undefined
                anchors.bottom: edge.includes("s") ? parent.bottom : undefined
                anchors.left: edge.includes("w") ? parent.left : undefined
                anchors.right: edge.includes("e") ? parent.right : undefined
                anchors.horizontalCenter: (edge === "n" || edge === "s") ? parent.horizontalCenter : undefined
                anchors.verticalCenter: (edge === "e" || edge === "w") ? parent.verticalCenter : undefined
                anchors.margins: -3

                MouseArea {
                    id: rhMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: {
                        if (rh.edge === "nw" || rh.edge === "se")
                            return Qt.SizeFDiagCursor;
                        if (rh.edge === "ne" || rh.edge === "sw")
                            return Qt.SizeBDiagCursor;
                        if (rh.edge === "n" || rh.edge === "s")
                            return Qt.SizeVerCursor;
                        return Qt.SizeHorCursor;
                    }

                    onPressed: mouse => {
                        SettingsLayoutManager.selectedModuleId = root.moduleId;
                        root.showMoveMenu = false;
                        const pt = rhMouse.mapToItem(null, mouse.x, mouse.y);
                        editOverlay.dragStartSceneX = pt.x;
                        editOverlay.dragStartSceneY = pt.y;
                        editOverlay.startWidthPx = card.width;
                        editOverlay.startHeightPx = card.height;
                        editOverlay.startCanvasX = root.x;
                        editOverlay.startCanvasY = root.y;
                        editOverlay.activeResizeEdge = rh.edge;
                        editOverlay.resizing = true;
                    }

                    onPositionChanged: mouse => {
                        if (!pressed || !editOverlay.resizing)
                            return;
                        const pt = rhMouse.mapToItem(null, mouse.x, mouse.y);
                        const dx = pt.x - editOverlay.dragStartSceneX;
                        const dy = pt.y - editOverlay.dragStartSceneY;

                        if (root.isCanvasMode) {
                            let nx = editOverlay.startCanvasX;
                            let ny = editOverlay.startCanvasY;
                            let nw = editOverlay.startWidthPx;
                            let nh = editOverlay.startHeightPx;
                            if (rh.edge.includes("e"))
                                nw = Math.max(200, Math.round(editOverlay.startWidthPx + dx));
                            if (rh.edge.includes("w")) {
                                nw = Math.max(200, Math.round(editOverlay.startWidthPx - dx));
                                nx = Math.max(0, Math.round(editOverlay.startCanvasX + dx));
                            }
                            if (rh.edge.includes("s"))
                                nh = Math.max(88, Math.round(editOverlay.startHeightPx + dy));
                            if (rh.edge.includes("n")) {
                                nh = Math.max(88, Math.round(editOverlay.startHeightPx - dy));
                                ny = Math.max(0, Math.round(editOverlay.startCanvasY + dy));
                            }
                            root._resizePreviewCanvasX = nx;
                            root._resizePreviewCanvasY = ny;
                            root._resizePreviewCanvasW = nw;
                            root._resizePreviewCanvasH = nh;
                            root._resizePreviewHeight = nh;
                            root.x = nx;
                            root.y = ny;
                            root.width = nw;
                            root.height = nh;
                            return;
                        }

                        if (rh.edge.includes("e") || rh.edge.includes("w")) {
                            const signedDx = rh.edge.includes("w") ? -dx : dx;
                            const nextWidthPx = Math.max(200, editOverlay.startWidthPx + signedDx);
                            const availW = Math.max(240, root._parentAvailableWidth);
                            const ratio = Math.min(1.0, Math.max(0.25, nextWidthPx / availW));
                            root._resizePreviewWidthRatio = ratio >= 0.97 ? 0 : ratio;
                        }
                        if (rh.edge.includes("s") || rh.edge.includes("n")) {
                            const signedDy = rh.edge.includes("n") ? -dy : dy;
                            root._resizePreviewHeight = Math.max(88, Math.round(editOverlay.startHeightPx + signedDy));
                        }
                    }

                    onReleased: {
                        const wasResizing = editOverlay.resizing;
                        editOverlay.resizing = false;
                        editOverlay.activeResizeEdge = "";
                        if (!wasResizing) {
                            root._resizePreviewWidthRatio = -1;
                            root._resizePreviewHeight = -1;
                            root._resizePreviewCanvasX = -1;
                            root._resizePreviewCanvasY = -1;
                            root._resizePreviewCanvasW = -1;
                            root._resizePreviewCanvasH = -1;
                            return;
                        }

                        if (root.isCanvasMode && root._resizePreviewCanvasW > 0) {
                            const spec = {
                                canvasX: root._resizePreviewCanvasX >= 0 ? root._resizePreviewCanvasX : root.x,
                                canvasY: root._resizePreviewCanvasY >= 0 ? root._resizePreviewCanvasY : root.y,
                                canvasW: root._resizePreviewCanvasW,
                                canvasH: root._resizePreviewCanvasH,
                                customHeight: root._resizePreviewCanvasH
                            };
                            root._resizePreviewCanvasX = -1;
                            root._resizePreviewCanvasY = -1;
                            root._resizePreviewCanvasW = -1;
                            root._resizePreviewCanvasH = -1;
                            root._resizePreviewHeight = -1;
                            SettingsLayoutManager.resizeModule(root.moduleId, spec);
                            return;
                        }

                        const spec = {};
                        let hasChanges = false;
                        if (root._resizePreviewWidthRatio >= 0) {
                            spec.widthRatio = root._resizePreviewWidthRatio;
                            root._resizePreviewWidthRatio = -1;
                            hasChanges = true;
                        }
                        if (root._resizePreviewHeight >= 0) {
                            spec.customHeight = root._resizePreviewHeight;
                            root._resizePreviewHeight = -1;
                            hasChanges = true;
                        }
                        if (hasChanges) {
                            SettingsLayoutManager.resizeModule(root.moduleId, spec);
                        }
                    }

                    onCanceled: {
                        editOverlay.resizing = false;
                        editOverlay.activeResizeEdge = "";
                        root._resizePreviewWidthRatio = -1;
                        root._resizePreviewHeight = -1;
                        root._resizePreviewCanvasX = -1;
                        root._resizePreviewCanvasY = -1;
                        root._resizePreviewCanvasW = -1;
                        root._resizePreviewCanvasH = -1;
                    }

                    onDoubleClicked: {
                        editOverlay.resizing = false;
                        editOverlay.activeResizeEdge = "";
                        root._resizePreviewWidthRatio = -1;
                        root._resizePreviewHeight = -1;
                        root._resizePreviewCanvasX = -1;
                        root._resizePreviewCanvasY = -1;
                        root._resizePreviewCanvasW = -1;
                        root._resizePreviewCanvasH = -1;
                        SettingsLayoutManager.resizeModule(root.moduleId, {
                            widthRatio: 0,
                            customHeight: 0,
                            canvasW: 0,
                            canvasH: 0
                        });
                    }
                }
            }

            CardResizeHandle { edge: "n" }
            CardResizeHandle { edge: "s" }
            CardResizeHandle { edge: "e" }
            CardResizeHandle { edge: "w" }
            CardResizeHandle { edge: "nw" }
            CardResizeHandle { edge: "ne" }
            CardResizeHandle { edge: "sw" }
            CardResizeHandle { edge: "se" }
        }
    }
}
