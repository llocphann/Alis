import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Clean, lightweight single-plate Settings section card.
 * Tonal elevation with tinted icon badge, crisp title header, subtle bottom divider,
 * and zero Edit-Layout scaling/drag overhead.
 */
Item {
    id: root

    property string title: ""
    property string icon: ""
    property bool expanded: true
    property bool collapsible: true
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

    // Compatibility & page host metadata
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
    property int irisSectionNumber: 0
    property int irisSectionTotal: 0
    readonly property string irisNumberText: (root.irisSectionNumber > 0 && root.irisSectionTotal > 0)
        ? ((root.irisSectionNumber < 10 ? "0" : "") + String(root.irisSectionNumber) + " / " + (root.irisSectionTotal < 10 ? "0" : "") + String(root.irisSectionTotal))
        : ""
    property bool _consumesBentoExtraHeight: false
    property real _bentoExtraHeight: 0
    property var _peerModuleIds: []
    property string moduleId: ""

    readonly property real renderedCardWidth: card.width
    readonly property real renderedCardHeight: card.height
    readonly property real contentScaleFactor: 1.0
    readonly property bool compactMode: card.width > 0 && card.width < 340
    readonly property bool wideMode: card.width >= 680
    readonly property int effectiveInnerColumns: 1
    readonly property bool isCanvasMode: false
    readonly property bool effectiveCollapsible: false

    readonly property real _pad: root.flatEmbedded
        ? 0
        : (root.compactMode
            ? Math.max(10, Math.round(SettingsMaterialPreset.cardPadding * 0.78))
            : SettingsMaterialPreset.cardPadding)
    readonly property real headerImplicitHeight: root.showHeader ? headerBackground.implicitHeight : 0
    readonly property real chromeImplicitHeight: (root.showHeader ? (headerBackground.implicitHeight + cardColumn.spacing) : 0) + root._pad * 2
    readonly property real naturalCardImplicitHeight: sectionContent.implicitHeight + root.chromeImplicitHeight
    readonly property real cardImplicitHeight: card.implicitHeight
    readonly property real _effectiveCardHeight: card.implicitHeight + Math.max(0, root._bentoExtraHeight)
    readonly property real _bottomGap: (root._cardSubTabActive && root._hasNextActiveCard)
        ? SettingsMaterialPreset.pageSpacing
        : 0

    clip: !root._cardSubTabActive
    opacity: root._cardSubTabActive ? 1 : 0
    enabled: root._cardSubTabActive

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: -1
    Layout.maximumWidth: 16777215
    Layout.fillHeight: false
    Layout.alignment: Qt.AlignTop
    Layout.preferredHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0
    Layout.maximumHeight: root._cardSubTabActive
        ? (root.Layout.fillHeight ? 16777215 : (root._effectiveCardHeight + root._bottomGap))
        : 0
    Layout.minimumHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0
    implicitHeight: root._cardSubTabActive ? (root._effectiveCardHeight + root._bottomGap) : 0

    function _findTopPage() {
        var p = root._initialParent ? root._initialParent : root.parent
        while (p) {
            if (p.hasOwnProperty("settingsPageIndex"))
                return p
            p = p.parent
        }
        return null
    }

    function _ensureTopPage() {
        if (!root._initialParent && root.parent)
            root._initialParent = root.parent
        var found = _findTopPage()
        if (found !== root._topPage) {
            if (root._topPage && typeof root._topPage.unregisterCardSection === "function")
                root._topPage.unregisterCardSection(root)
            root._topPage = found
            root._currentHostPage = found
            if (found && found.settingsPageIndex !== undefined && found.settingsPageIndex >= 0)
                root._originPageIndex = found.settingsPageIndex
            if (root._topPage && typeof root._topPage.registerCardSection === "function")
                root._topPage.registerCardSection(root)
        }
    }

    Timer {
        id: topPageSyncTimer
        interval: 0
        repeat: false
        onTriggered: {
            root._ensureTopPage()
            if (root._topPage && typeof root._topPage.notifyCardEligibilityChanged === "function")
                root._topPage.notifyCardEligibilityChanged()
        }
    }

    function isCardEligibleForTabs() {
        if (!root._participatesInLayout || !root.title || root.title.length === 0)
            return false
        if (!root.visible)
            return false
        if (root.settingsTaskSection && root.settingsTaskSection.length > 0
                && root._topPage && root._topPage._hasTaskNavigatorTabs
                && root._topPage.settingsTaskNavigator) {
            var navOpts = root._topPage.settingsTaskNavigator.options || []
            var currentTask = (root._topPage.hasOwnProperty("activeSection")
                    && root._topPage.activeSection !== undefined
                    && String(root._topPage.activeSection).length > 0)
                ? String(root._topPage.activeSection)
                : String(root._topPage.settingsTaskNavigator.currentValue ?? "")
            var matchesNavOption = false
            for (var i = 0; i < navOpts.length; i++) {
                if (String(navOpts[i]?.value ?? "") === root.settingsTaskSection) {
                    matchesNavOption = true
                    break
                }
            }
            if (matchesNavOption && currentTask.length > 0 && root.settingsTaskSection !== currentTask)
                return false
        }
        return true
    }

    function ensureControlOnActiveSectionSubTab(control) {}
    function rowPeerSections() { return [root] }
    function setRowExpanded(nextExpanded) {
        if (root._topPage && root._topPage.hasCardSubTabs) {
            root.expanded = true
            return
        }
        root.expanded = nextExpanded
    }

    onVisibleChanged: {
        topPageSyncTimer.restart()
        if (root._topPage && !root._topPage._isDestroying && typeof root._topPage.notifyCardEligibilityChanged === "function")
            root._topPage.notifyCardEligibilityChanged()
    }

    onTitleChanged: {
        if (root._topPage && !root._topPage._isDestroying && typeof root._topPage.notifyCardEligibilityChanged === "function")
            root._topPage.notifyCardEligibilityChanged()
    }

    function _findSettingsContext() {
        var page = null
        var p = root._initialParent ? root._initialParent : root.parent
        while (p) {
            if (!page && p.hasOwnProperty("settingsPageIndex")) {
                page = p
                break
            }
            p = p.parent
        }
        return { page: page }
    }

    function focusFromSettingsSearch() {
        if (root._topPage && typeof root._topPage.selectCardSection === "function")
            root._topPage.selectCardSection(root)
        root.expanded = true
        root.forceActiveFocus()
    }

    Component.onCompleted: {
        root._ensureTopPage()
        topPageSyncTimer.restart()

        if (!enableSettingsSearch || !root.title)
            return
        if (typeof SettingsSearchRegistry === "undefined")
            return

        if (SettingsSearchRegistry.registerCollapsibleSection)
            SettingsSearchRegistry.registerCollapsibleSection(root)

        var ctx = _findSettingsContext()
        var page = ctx.page

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: root.title,
            label: root.title,
            description: "",
            keywords: []
        })
    }

    Component.onDestruction: {
        topPageSyncTimer.stop()
        if (root._topPage && !root._topPage._isDestroying && typeof root._topPage.unregisterCardSection === "function")
            root._topPage.unregisterCardSection(root)
        if (typeof SettingsSearchRegistry !== "undefined") {
            if (SettingsSearchRegistry.unregisterCollapsibleSection)
                SettingsSearchRegistry.unregisterCollapsibleSection(root)
            SettingsSearchRegistry.unregisterControl(root)
        }
    }

    // Subtle elevation shadow for non-Waffle cards
    Rectangle {
        visible: Appearance.effectsEnabled && !SettingsMaterialPreset.waffle && !root.flatEmbedded
        opacity: root._cardSubTabActive ? 0.55 : 0
        x: card.x
        y: card.y + 1.5
        width: card.width
        height: card.height
        radius: card.radius
        color: Appearance.colors.colShadow
        z: -1
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.top: parent.top
        width: root.width
        height: Math.max(root._effectiveCardHeight, root.height - root._bottomGap)
        implicitHeight: (root.expanded ? sectionContent.implicitHeight : 0) + root.chromeImplicitHeight
        radius: root.flatEmbedded ? 0 : SettingsMaterialPreset.cardRadius
        color: root.flatEmbedded ? "transparent" : SettingsMaterialPreset.cardColor
        border.width: root.flatEmbedded ? 0 : 1
        border.color: root.flatEmbedded ? "transparent" : SettingsMaterialPreset.cardBorderColor

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                margins: root._pad
            }
            spacing: root.compactMode
                ? Math.max(8, Math.round(SettingsMaterialPreset.groupSpacing * 0.9))
                : Math.round(10 * Appearance.fontSizeScale)

            Item {
                id: headerBackground
                visible: root.showHeader
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + (root.expanded && !root.flatEmbedded ? 10 : 4)

                RowLayout {
                    id: headerRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        bottomMargin: root.expanded && !root.flatEmbedded ? 10 : 0
                    }
                    spacing: 9

                    // Refined tinted icon badge (Material/Abyss) or clean icon (Waffle)
                    Rectangle {
                        visible: root.icon && root.icon.length > 0 && !SettingsMaterialPreset.waffle && !root.flatEmbedded
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Math.round(28 * Appearance.fontSizeScale)
                        implicitHeight: implicitWidth
                        radius: 8
                        color: SettingsMaterialPreset.accentTint
                        border.width: 1
                        border.color: SettingsMaterialPreset.accentBorder

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.icon
                            iconSize: Math.round(16 * Appearance.fontSizeScale)
                            color: SettingsMaterialPreset.iconExpandedColor
                        }
                    }

                    MaterialSymbol {
                        visible: root.icon && root.icon.length > 0 && (SettingsMaterialPreset.waffle || root.flatEmbedded)
                        Layout.alignment: Qt.AlignVCenter
                        text: root.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: SettingsMaterialPreset.iconExpandedColor
                    }

                    StyledText {
                        font.family: SettingsMaterialPreset.fontFamily
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        verticalAlignment: Text.AlignVCenter
                        text: root.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: SettingsMaterialPreset.titleExpandedColor
                    }
                }

                Rectangle {
                    visible: root.expanded && !root.flatEmbedded
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: SettingsMaterialPreset.plateDividerColor
                }
            }

            ColumnLayout {
                id: sectionContent
                objectName: "sectionContent"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.fillHeight: root.expanded
                visible: root.expanded
                spacing: root.compactMode
                    ? Math.max(6, Math.round(root.spacing * 0.85))
                    : root.spacing
            }
        }
    }
}
