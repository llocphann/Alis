import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property string title: ""
    property string icon: ""
    property bool expanded: true
    property bool collapsible: true
    // Embedded consumers can reuse only the section content without inheriting
    // Settings' collapsible title/drop-down chrome.
    property bool showHeader: true
    property int animationDuration: Appearance.animation.elementMove.duration
    property string settingsTaskSection: ""
    default property alias contentData: sectionContent.data

    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1
    property bool syncRowExpansion: false
    property bool _syncingRowExpansion: false

    // Card Sub-Tab state managed by ContentPage
    property var _topPage: null
    property Item _initialParent: null
    property int _declarationOrder: -1
    property string _cardSubTabKey: ""
    property bool _cardSubTabActive: true
    property bool _hasNextActiveCard: false
    property bool _preventBentoReparent: false
    property string bentoColumn: ""
    property bool _consumesBentoExtraHeight: false
    property real _bentoExtraHeight: 0
    readonly property real cardImplicitHeight: card.implicitHeight
    readonly property real naturalCardImplicitHeight: root.cardImplicitHeight
    readonly property real chromeImplicitHeight: (root.showHeader ? (headerBackground.implicitHeight + SettingsMaterialPreset.groupSpacing) : 0) + SettingsMaterialPreset.cardPadding * 2
    readonly property real _effectiveCardHeight: card.implicitHeight + Math.max(0, root._bentoExtraHeight)
    readonly property real _bottomGap: (root._cardSubTabActive && root._hasNextActiveCard)
        ? SettingsMaterialPreset.pageSpacing
        : 0
    readonly property bool effectiveCollapsible: false

    clip: !root._cardSubTabActive
    opacity: root._cardSubTabActive ? 1 : 0
    enabled: root._cardSubTabActive

    Layout.fillWidth: true
    Layout.fillHeight: false
    Layout.alignment: Qt.AlignTop
    Layout.preferredHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0
    Layout.maximumHeight: root._cardSubTabActive
        ? (root.Layout.fillHeight ? 16777215 : (root._effectiveCardHeight + root._bottomGap))
        : 0
    Layout.minimumHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0
    implicitHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0

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
            if (root._topPage && typeof root._topPage.registerCardSection === "function") {
                root._topPage.registerCardSection(root);
            }
        }
    }

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
        if (!root.showHeader || !root.title || root.title.length === 0)
            return false;
        if (!root.visible)
            return false;
        if (root.settingsTaskSection && root.settingsTaskSection.length > 0
                && root._topPage && root._topPage._hasTaskNavigatorTabs
                && root._topPage.settingsTaskNavigator) {
            var navOpts = root._topPage.settingsTaskNavigator.options || [];
            var currentTask = String(root._topPage.settingsTaskNavigator.currentValue ?? "");
            var matchesNavOption = false;
            for (var i = 0; i < navOpts.length; i++) {
                if (String(navOpts[i]?.value ?? "") === root.settingsTaskSection) {
                    matchesNavOption = true;
                    break;
                }
            }
            if (matchesNavOption && currentTask.length > 0 && root.settingsTaskSection !== currentTask) {
                return false;
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
        if (root._topPage && !root._topPage._isDestroying && typeof root._topPage.notifyCardEligibilityChanged === "function") {
            root._topPage.notifyCardEligibilityChanged();
        }
    }

    onNaturalCardImplicitHeightChanged: {
        if (root.visible && root._topPage && !root._topPage._isDestroying && root._topPage._activeLeftBentoCards) {
            root._topPage._syncBentoColumnHeights(root._topPage._activeLeftBentoCards, root._topPage._activeRightBentoCards);
        }
    }

    function _findSettingsContext() {
        var page = null;
        var p = root.parent;
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
        if (typeof SettingsSearchRegistry !== "undefined") {
            if (SettingsSearchRegistry.unregisterCollapsibleSection) {
                SettingsSearchRegistry.unregisterCollapsibleSection(root);
            }
            SettingsSearchRegistry.unregisterControl(root);
        }
    }

    // Lightweight Material offset shadow avoids a GPU-blurred shadow per card.
    Rectangle {
        visible: root._cardSubTabActive && Appearance.effectsEnabled
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
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(implicitHeight, root.height - root._bottomGap)
        implicitHeight: cardColumn.implicitHeight + SettingsMaterialPreset.cardPadding * 2
        radius: SettingsMaterialPreset.cardRadius
        color: SettingsMaterialPreset.cardColor
        border.width: Config.options?.panelFamily === "abyss" ? 0 : 1
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
                margins: SettingsMaterialPreset.cardPadding
            }
            spacing: SettingsMaterialPreset.groupSpacing

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
                        text: root.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        marquee: true
                        maximumLineCount: 1
                        color: root.expanded
                            ? SettingsMaterialPreset.titleExpandedColor
                            : SettingsMaterialPreset.titleCollapsedColor
                        Layout.fillWidth: true

                        Behavior on color {
                            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }

                    MaterialSymbol {
                        visible: root.effectiveCollapsible
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
                Layout.fillHeight: root.expanded
                implicitHeight: root.expanded ? sectionContent.implicitHeight : 0
                clip: true
                enabled: root.expanded

                ColumnLayout {
                    id: sectionContent
                    objectName: "sectionContent"
                    width: parent.width
                    height: (root._consumesBentoExtraHeight || root._bentoExtraHeight > 0) ? Math.max(implicitHeight, parent.height) : implicitHeight
                    spacing: SettingsMaterialPreset.groupSpacing
                    opacity: root.expanded ? 1 : 0
                }
            }
        }
    }
}
