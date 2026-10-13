//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env ALIS_STANDALONE_WINDOW=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Launcher keeps QT_SCALE_FACTOR=1; shell scaling lives in appearance.typography.sizeScale

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.settings
import "modules/settings/SettingsHierarchy.js" as Hierarchy
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false
    // Pages come from the shared registry; resolve component paths to absolute
    // shell URLs so the Loaders work regardless of this file's location.
    readonly property var pages: SettingsPageRegistry.pages.map(p => {
        if (!p) return null
        var entry = Object.assign({}, p)
        entry.component = Quickshell.shellPath(p.component)
        return entry
    })
    property int currentPage: 0
    property bool navEditMode: false
    property int _requestedStartPage: -1
    property string _requestedStartSection: ""
    property bool _navigationInitialized: false

    function _persistCurrentPage(): void {
        if (root._navigationInitialized && Persistent.ready && Persistent.states?.settings)
            Persistent.states.settings.iiPage = Math.max(0, Math.min(root.currentPage, root.pages.length - 1))
    }

    function initializeNavigation(): void {
        if (root._navigationInitialized || !Persistent.ready)
            return
        const persisted = Persistent.states?.settings?.iiPage ?? 0
        const requested = root._requestedStartPage >= 0 ? root._requestedStartPage : persisted
        root.currentPage = Math.max(0, Math.min(requested, root.pages.length - 1))
        root._navigationInitialized = true
        root._persistCurrentPage()
        if (root._requestedStartSection.length > 0) {
            root.pendingSpotlightSection = root._requestedStartSection
            root.pendingSpotlightPageIndex = root.currentPage
            root.trySpotlight()
        }
    }

    onCurrentPageChanged: {
        root._persistCurrentPage()
        root.navGroup=Hierarchy.parentKey(root.pages[root.currentPage])
    }

    property bool uiReady: Config.ready

    property string navGroup: ""
    readonly property var navPageOrder: SettingsPageRegistry.navigationPageIndexes(false)
    readonly property var visibleNavItems: Hierarchy.entries(pages, navPageOrder,
        navGroup, currentPage, navEditMode)
    function activateNavigation(entry): void {
        if (entry.back) { navGroup="";return }
        if (entry.groupKey) navGroup=entry.groupKey
        root.currentPage=entry.realIndex
    }

    function nextNavPage(current) {
        var idx = navPageOrder.indexOf(current);
        if (idx < 0) return navPageOrder.length > 0 ? navPageOrder[0] : 0;
        return navPageOrder[(idx + 1) % navPageOrder.length];
    }
    function prevNavPage(current) {
        var idx = navPageOrder.indexOf(current);
        if (idx < 0) return navPageOrder.length > 0 ? navPageOrder[navPageOrder.length - 1] : 0;
        return navPageOrder[(idx - 1 + navPageOrder.length) % navPageOrder.length];
    }

    // Global settings search
    property string settingsSearchText: ""
    property var settingsSearchResults: []

    // Search navigation focus state
    property var searchTargetControl: null

    // Static section/option index — shared with the overlay via SettingsPageRegistry.
    function getWaffleSettingsPageIndex() {
        for (var i = 0; i < pages.length; i++) {
            if ((pages[i]?.component || "").indexOf("modules/settings/WaffleConfig.qml") >= 0)
                return i;
        }
        return -1;
    }

    function recomputeSettingsSearchResults() {
        var q = String(settingsSearchText || "").toLowerCase().trim();
        if (!q.length) {
            settingsSearchResults = [];
            return;
        }

        var terms = q.split(/\s+/).filter(t => t.length > 0);
        var results = [];

        // Check if waffle family is active
        var isWaffleActive = Config.options?.panelFamily === "waffle";
        var wafflePageIndex = getWaffleSettingsPageIndex();
        var easyOn = false;

        // 1. Buscar en el índice estático de secciones (para navegación rápida a secciones)
        const settingsSearchIndex = SettingsPageRegistry.searchIndex();
        for (var i = 0; i < settingsSearchIndex.length; i++) {
            var entry = settingsSearchIndex[i];
            if (!SettingsPageRegistry.isPageApplicable(entry.pageIndex)) continue;

            // Skip Waffle Style page if waffle family is not active
            if (wafflePageIndex >= 0 && entry.pageIndex === wafflePageIndex && !isWaffleActive) {
                continue;
            }

            // Skip non-essential pages in easy mode
            if (easyOn && entry.pageIndex >= 0 && entry.pageIndex < pages.length
                && pages[entry.pageIndex].essential !== true) {
                continue;
            }

            var label = (entry.label || "").toLowerCase();
            var desc = (entry.description || "").toLowerCase();
            var page = (entry.pageName || "").toLowerCase();
            var sect = (entry.section || "").toLowerCase();
            var kw = (entry.keywords || []).join(" ").toLowerCase();

            var matchCount = 0;
            var score = 0;

            for (var j = 0; j < terms.length; j++) {
                var term = terms[j];
                if (label.indexOf(term) >= 0 || desc.indexOf(term) >= 0 ||
                    page.indexOf(term) >= 0 || sect.indexOf(term) >= 0 || kw.indexOf(term) >= 0) {
                    matchCount++;
                    if (label.indexOf(term) === 0) score += 800;
                    else if (label.indexOf(term) > 0) score += 400;
                    if (kw.indexOf(term) >= 0) score += 300;
                    if (sect.indexOf(term) >= 0) score += 200;
                }
            }

            if (matchCount === terms.length) {
                results.push({
                    pageIndex: entry.pageIndex,
                    pageName: entry.pageName,
                    section: entry.section,
                    label: entry.label,
                    labelHighlighted: SettingsSearchRegistry.highlightTerms(entry.label, terms),
                    description: entry.description,
                    descriptionHighlighted: SettingsSearchRegistry.highlightTerms(entry.description, terms),
                    score: score + 500, // Bonus para secciones principales
                    isSection: true
                });
            }
        }

        // 2. Buscar en el registro dinámico de widgets
        if (typeof SettingsSearchRegistry !== "undefined") {
            var widgetResults = SettingsSearchRegistry.buildResults(settingsSearchText);
            widgetResults = widgetResults.filter(r => SettingsPageRegistry.isPageApplicable(r.pageIndex));
            // Filter out Waffle Style widgets if waffle family is not active
            if (!isWaffleActive) {
                widgetResults = widgetResults.filter(r => r.pageIndex !== wafflePageIndex);
            }
            if (easyOn) {
                widgetResults = widgetResults.filter(r =>
                    r.pageIndex >= 0 && r.pageIndex < pages.length
                    && pages[r.pageIndex].essential === true);
            }
            // Prefer real controls (dynamic registry entries with optionId)
            for (var wr = 0; wr < widgetResults.length; wr++) {
                widgetResults[wr].score = (widgetResults[wr].score || 0) + 2000;
            }
            results = results.concat(widgetResults);
        }

        // 3. Ordenar por score y eliminar duplicados
        results.sort((a, b) => b.score - a.score);

        // Eliminar duplicados por pageIndex+label, preferring entries with optionId
        var seen = {};
        var unique = [];
        for (var k = 0; k < results.length; k++) {
            var r = results[k];
            var key = String(r.pageIndex) + "|" + String(r.label || "").toLowerCase();
            if (!seen[key]) {
                seen[key] = { index: unique.length, hasOptionId: r.optionId !== undefined };
                unique.push(r);
            } else if (r.optionId !== undefined && !seen[key].hasOptionId) {
                unique[seen[key].index] = r;
                seen[key].hasOptionId = true;
            }
        }

        settingsSearchResults = unique.slice(0, 50);
    }

    Connections {
        target: SettingsPageRegistry
        function onNavigateRequested(pageIndex, section) {
            if (section.length > 0)
                root.openSearchResult({ pageIndex: pageIndex, section: section,
                    label: section, isSection: true })
            else
                root.currentPage = pageIndex
        }
    }

    // Pending search navigation target data
    property int pendingSpotlightOptionId: -1
    property string pendingSpotlightLabel: ""
    property string pendingSpotlightSection: ""
    property int pendingSpotlightPageIndex: -1
    property bool pendingSpotlightIsSection: false
    property var searchTargetFlickable: null

    function openSearchResult(entry) {
        // Clear search immediately
        settingsSearchText = "";
        if (settingsSearchField) {
            settingsSearchField.text = "";
        }

        // Reset existing search target state
        resetSearchTarget();

        if (!entry || entry.pageIndex === undefined || entry.pageIndex < 0) {
            return;
        }

        // Store navigation target info
        pendingSpotlightOptionId = (entry.optionId !== undefined) ? entry.optionId : -1;
        pendingSpotlightLabel = entry.label || "";
        pendingSpotlightSection = entry.section || "";
        pendingSpotlightPageIndex = entry.pageIndex;
        pendingSpotlightIsSection = (entry.optionId === undefined) && (entry.isSection === true);

        // Navigate to page (this triggers page load if needed)
        if (currentPage !== entry.pageIndex) {
            currentPage = entry.pageIndex;
        }

        // Always try to resolve and navigate target (with retry for lazy-loaded widgets)
        if (pendingSpotlightOptionId >= 0 || pendingSpotlightLabel.length > 0) {
            spotlightRetryCount = 0;
            spotlightPageLoadTimer.restart();
        }
    }

    property int spotlightRetryCount: 0
    property int spotlightMaxRetries: 15

    // Timer to wait for page load and widget registration
    Timer {
        id: spotlightPageLoadTimer
        interval: 150
        onTriggered: root.trySpotlight()
    }

    function trySpotlight() {
        const pageItem = pagesStack.currentItem
        if (pageItem && pagesStack.currentIndex === pendingSpotlightPageIndex
                && pendingSpotlightSection.length > 0
                && typeof pageItem.activateSettingsSearchSection === "function")
            pageItem.activateSettingsSearchSection(pendingSpotlightSection)

        var control = pendingSpotlightIsSection
            ? SettingsSearchRegistry.findSectionControl(pendingSpotlightPageIndex,pendingSpotlightSection || pendingSpotlightLabel) : null;

        // Try by optionId first
        if (pendingSpotlightOptionId >= 0) {
            control = SettingsSearchRegistry.getControlById(pendingSpotlightOptionId);
        }

        // Fallback: search in registry by various criteria
        // IMPORTANT: for static index entries (no optionId), treat as section navigation.
        // Don't guess a specific control by fuzzy label matching.
        if (!control && !pendingSpotlightIsSection && (pendingSpotlightLabel.length > 0 || pendingSpotlightSection.length > 0)) {
            var labelLower = pendingSpotlightLabel.toLowerCase();
            var sectionLower = pendingSpotlightSection.toLowerCase();
            // Remove page name prefix from section if present (supports both delimiters)
            // e.g., "Themes › Global Style" or "Themes · Global Style" -> "Global Style"
            var sectionParts = sectionLower.split(/[·›]/).map(p => p.trim()).filter(p => p.length > 0);
            var sectionOnly = sectionParts.length > 1 ? sectionParts[sectionParts.length - 1] : sectionLower;

            for (var i = 0; i < SettingsSearchRegistry.entries.length; i++) {
                var e = SettingsSearchRegistry.entries[i];
                if (e.pageIndex === pendingSpotlightPageIndex) {
                    var eLabelLower = (e.label || "").toLowerCase();
                    var eSectionLower = (e.section || "").toLowerCase();

                    if (pendingSpotlightIsSection) {
                        // Prefer matching the section title control.
                        if (eLabelLower === labelLower || eLabelLower === sectionOnly) {
                            control = e.control;
                            break;
                        }
                        if (eSectionLower === sectionOnly || eSectionLower === labelLower) {
                            control = e.control;
                            break;
                        }
                    } else {
                        // Exact label match
                        if (eLabelLower === labelLower) {
                            control = e.control;
                            break;
                        }
                        // Section title match (for SettingsCardSection)
                        if (eSectionLower === sectionOnly || eSectionLower === labelLower) {
                            control = e.control;
                            break;
                        }
                        // Label contains search term
                        if (labelLower.length > 2 && eLabelLower.indexOf(labelLower) >= 0) {
                            control = e.control;
                            break;
                        }
                        // Keywords contain search term
                        if (e.keywords && e.keywords.some(k => k.toLowerCase() === labelLower)) {
                            control = e.control;
                            break;
                        }
                    }
                }
            }
        }

        if (control) {
            navigateToSearchControl(control);
        } else if (spotlightRetryCount < spotlightMaxRetries) {
            spotlightRetryCount++;
            spotlightPageLoadTimer.restart();
        } else {
            // Give up after max retries - clear pending data
            pendingSpotlightOptionId = -1;
            pendingSpotlightLabel = "";
            pendingSpotlightSection = "";
            pendingSpotlightPageIndex = -1;
            pendingSpotlightIsSection = false;
        }
    }

    function navigateToSearchControl(control) {
        if (!control) return;

        // Expand the section containing the control and collapse others
        if (typeof SettingsSearchRegistry !== "undefined") {
            SettingsSearchRegistry.activateTaskSectionForControl(control);
            SettingsSearchRegistry.expandSectionForControl(control);
        }

        // Find the parent Flickable (ContentPage/StyledFlickable)
        var flick = findParentFlickable(control);
        if (!flick) {
            pendingSpotlightOptionId = -1;
            pendingSpotlightLabel = "";
            pendingSpotlightPageIndex = -1;
            return;
        }

        // Use mapToItem to get the control's position relative to the Flickable's contentItem
        // This accounts for all intermediate containers (ColumnLayout margins, etc.)
        var posInContent = control.mapToItem(flick.contentItem, 0, 0);
        var controlYInContent = posInContent.y;

        // Calculate target scroll position to center the control in viewport
        var viewportHeight = flick.height;
        var controlHeight = control.height;
        var targetScrollY = controlYInContent - (viewportHeight / 2) + (controlHeight / 2);

        // Clamp to valid scroll range
        var maxScroll = Math.max(0, flick.contentHeight - flick.height);
        targetScrollY = Math.max(0, Math.min(targetScrollY, maxScroll));

        // Store the target scroll position for later verification
        spotlightTargetScrollY = targetScrollY;

        // Scroll to position - set directly to bypass animation
        flick.contentY = targetScrollY;

        // Store references for optional focus retries
        searchTargetControl = control;
        searchTargetFlickable = flick;

        // Clear pending data after successful navigation
        pendingSpotlightOptionId = -1;
        pendingSpotlightLabel = "";
        pendingSpotlightSection = "";
        pendingSpotlightPageIndex = -1;
        pendingSpotlightIsSection = false;
    }

    property real spotlightTargetScrollY: 0

    function findParentFlickable(item) {
        var p = item ? item.parent : null;
        while (p) {
            // Check for Flickable properties (contentY, contentHeight, contentItem)
            if (p.hasOwnProperty("contentY") &&
                p.hasOwnProperty("contentHeight") &&
                p.hasOwnProperty("contentItem")) {
                return p;
            }
            p = p.parent;
        }
        return null;
    }

    function resetSearchTarget() {
        searchTargetControl = null;
        searchTargetFlickable = null;
        spotlightTargetScrollY = 0;
        pendingSpotlightOptionId = -1;
        pendingSpotlightLabel = "";
        pendingSpotlightSection = "";
        pendingSpotlightPageIndex = -1;
        pendingSpotlightIsSection = false;
    }

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"

    Component.onCompleted: {
        Quickshell.watchFiles = false
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed

        // Config can become ready before this standalone root finishes loading.
        // Mirror shell.qml's already-ready path so the window never keeps the
        // singleton's stale/default palette for its first frame.
        if (Config.ready) {
            Qt.callLater(() => ThemeService.applyCurrentTheme())
        }

        const startPage = parseInt(Quickshell.env("QS_SETTINGS_PAGE"));
        if (!isNaN(startPage)) root._requestedStartPage = startPage;

        root._requestedStartSection = Quickshell.env("QS_SETTINGS_SECTION") || ""
        root.initializeNavigation()
    }

    Connections {
        target: Persistent
        function onReadyChanged() { root.initializeNavigation() }
    }

    // Apply theme when Config is ready
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) ThemeService.applyCurrentTheme()
        }
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    // Match Screen Edge's render path: keep the native window transparent and
    // let one QML surface own colLayer0, including any global transparency.
    color: "transparent"

    Rectangle {
        id: windowBaseSurface
        anchors.fill: parent
        z: 0
        color: root.uiReady ? Appearance.colors.colLayer0 : "transparent"
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: settingsSearchField.forceActiveFocus()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }
        z: 2
        visible: root.uiReady
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Tab) {
                    root.currentPage = root.nextNavPage(root.currentPage)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Backtab) {
                    root.currentPage = root.prevNavPage(root.currentPage)
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar with integrated search
            id: settingsHeader
            visible: Config.options?.windows?.showTitlebar ?? true
            Layout.fillWidth: true
            Layout.preferredHeight: root.navEditMode ? 58 : 52
            Layout.leftMargin: 12
            Layout.rightMargin: 6

            Behavior on Layout.preferredHeight {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementResize.duration }
            }

            function slotBlock(index: int): string {
                return SettingsChromeLayout.headerOrder[index] ?? ""
            }

            readonly property real headerGap: root.navEditMode ? 8 : 12
            readonly property real identityWidth: root.navEditMode ? 176 : 210
            readonly property real actionsWidth: Math.max(108, actionsRow.implicitWidth)
            readonly property bool defaultOrder: SettingsChromeLayout.headerOrder.join(",") === "identity,search,actions"

            function searchWidth(): real {
                const preferred = root.navEditMode ? 420 : 480
                const minimum = root.navEditMode ? 150 : 200
                if (settingsHeader.defaultOrder) {
                    const side = Math.max(settingsHeader.identityWidth, settingsHeader.actionsWidth)
                    return Math.max(minimum, Math.min(preferred,
                        settingsHeader.width - 2 * (side + settingsHeader.headerGap)))
                }
                return Math.max(minimum, Math.min(preferred,
                    settingsHeader.width - settingsHeader.identityWidth
                        - settingsHeader.actionsWidth - 2 * settingsHeader.headerGap))
            }

            function slotWidth(index: int): real {
                const block = settingsHeader.slotBlock(index)
                if (block === "identity")
                    return settingsHeader.identityWidth
                if (block === "actions")
                    return settingsHeader.actionsWidth
                return settingsHeader.searchWidth()
            }

            function slotX(index: int): real {
                const block = settingsHeader.slotBlock(index)
                if (settingsHeader.defaultOrder) {
                    if (block === "identity")
                        return 0
                    if (block === "actions")
                        return Math.max(0, settingsHeader.width - settingsHeader.actionsWidth)
                    return Math.max(0, (settingsHeader.width - settingsHeader.searchWidth()) / 2)
                }

                const total = settingsHeader.identityWidth + settingsHeader.searchWidth()
                    + settingsHeader.actionsWidth + 2 * settingsHeader.headerGap
                let x = Math.max(0, (settingsHeader.width - total) / 2)
                for (let i = 0; i < index; ++i)
                    x += settingsHeader.slotWidth(i) + settingsHeader.headerGap
                return x
            }


            Item {
                anchors.fill: parent

                Item {
                    id: settingsHeaderSlot0
                    x: settingsHeader.slotX(0)
                    width: settingsHeader.slotWidth(0)
                    height: parent.height
                }
                Item {
                    id: settingsHeaderSlot1
                    x: settingsHeader.slotX(1)
                    width: settingsHeader.slotWidth(1)
                    height: parent.height
                }
                Item {
                    id: settingsHeaderSlot2
                    x: settingsHeader.slotX(2)
                    width: settingsHeader.slotWidth(2)
                    height: parent.height
                }
            }

            Item {
                id: headerIdentity
                parent: SettingsChromeLayout.columnFor("identity") === 0 ? settingsHeaderSlot0
                    : SettingsChromeLayout.columnFor("identity") === 1 ? settingsHeaderSlot1
                    : settingsHeaderSlot2
                anchors.fill: parent
                anchors.topMargin: 4
                anchors.bottomMargin: 4

                RowLayout {
                    anchors.fill: parent
                    spacing: 9

                    Item {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: Appearance.colors.colPrimary
                        }

                        Rectangle {
                            id: settingsAvatarMask
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            radius: width / 2
                            visible: false
                        }

                        Image {
                            id: settingsAvatarImage
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            source: settingsAvatarResolver.resolvedSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true
                            sourceSize.width: 64
                            sourceSize.height: 64
                            visible: status === Image.Ready
                            layer.enabled: visible
                            layer.effect: OpacityMask { maskSource: settingsAvatarMask }

                            onStatusChanged: {
                                if (settingsAvatarImage.status !== Image.Error)
                                    return
                                const next = settingsAvatarResolver.avatarIndex + 1
                                if (next < Directories.userAvatarPaths.length)
                                    settingsAvatarResolver.avatarIndex = next
                            }
                        }

                        QtObject {
                            id: settingsAvatarResolver
                            property int avatarIndex: 0
                            readonly property string resolvedSource: Directories.avatarSourceAt(avatarIndex)
                            readonly property string primaryWatch: Directories.userAvatarSourcePrimary
                            onPrimaryWatchChanged: avatarIndex = 0
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: settingsAvatarImage.status !== Image.Ready
                            text: "person"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer0
                            text: Translation.tr("Settings")
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.title
                                variableAxes: Appearance.font.variableAxes.title
                            }
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: SystemInfo.displayName || SystemInfo.username
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                        }
                    }
                }

                SettingsChromeEditFrame {
                    anchors.fill: parent
                    active: root.navEditMode
                    blockId: "identity"
                    label: Translation.tr("Identity")
                    targetIndex: SettingsChromeLayout.columnFor("identity")
                }
            }

            Rectangle {
                id: searchContainer
                parent: SettingsChromeLayout.columnFor("search") === 0 ? settingsHeaderSlot0
                    : SettingsChromeLayout.columnFor("search") === 1 ? settingsHeaderSlot1
                    : settingsHeaderSlot2
                anchors.fill: parent
                anchors.topMargin: root.navEditMode ? 8 : 6
                anchors.bottomMargin: root.navEditMode ? 8 : 6
                radius: Appearance.rounding.full
                color: settingsSearchField.activeFocus
                    ? Appearance.colors.colLayer1
                    : Appearance.colors.colLayer0
                border.width: settingsSearchField.activeFocus ? 2 : 1
                border.color: settingsSearchField.activeFocus
                    ? Appearance.colors.colPrimary
                    : Appearance.m3colors.m3outlineVariant

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    // Icono animado
                    MaterialShapeWrappedMaterialSymbol {
                        id: settingsSearchIcon
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: Appearance.font.pixelSize.huge
                        shape: root.settingsSearchText.length > 0
                            ? MaterialShape.Shape.SoftBurst
                            : MaterialShape.Shape.Cookie7Sided
                        text: root.settingsSearchResults.length > 0 ? "manage_search" : "search"
                    }

                    // Campo de texto
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Placeholder text (behind TextField, separate element)
                        StyledText {
                            id: searchPlaceholder
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Search settings... (Ctrl+F)")
                            color: Appearance.colors.colSubtext
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.normal
                            }
                            visible: settingsSearchField.text.length === 0 && !settingsSearchField.activeFocus
                        }

                        TextInput {
                            id: settingsSearchField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            verticalAlignment: Text.AlignVCenter

                            color: Appearance.colors.colOnLayer1
                            selectionColor: Appearance.colors.colPrimaryContainer
                            selectedTextColor: Appearance.colors.colOnPrimaryContainer
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.normal
                            }

                            // Custom cursor color
                            cursorVisible: activeFocus
                            cursorDelegate: Rectangle {
                                visible: settingsSearchField.cursorVisible
                                width: 2
                                color: Appearance.colors.colPrimary

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: settingsSearchField.cursorVisible
                                    NumberAnimation { to: 0; duration: 530 }
                                    NumberAnimation { to: 1; duration: 530 }
                                }
                            }

                            text: root.settingsSearchText
                            onTextChanged: {
                                root.settingsSearchText = text;
                                root.recomputeSettingsSearchResults();
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down && root.settingsSearchResults.length > 0) {
                                    settingsLiveSearch.focusResults()
                                    event.accepted = true
                                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && root.settingsSearchResults.length > 0) {
                                    settingsLiveSearch.activateCurrent()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    root.openSearchResult({})
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    // Botón de limpiar
                    RippleButton {
                        id: clearButton
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        Layout.alignment: Qt.AlignVCenter
                        buttonRadius: Appearance.rounding.full
                        visible: root.settingsSearchText.length > 0
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }

                        onClicked: {
                            settingsSearchField.text = "";
                            settingsSearchField.forceActiveFocus();
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    // Badge de resultados
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: resultsCountText.implicitWidth + 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                        visible: root.settingsSearchText.length > 0 && root.settingsSearchResults.length > 0
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer

                        StyledText {
                            id: resultsCountText
                            anchors.centerIn: parent
                            text: root.settingsSearchResults.length.toString()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                SettingsChromeEditFrame {
                    anchors.fill: parent
                    active: root.navEditMode
                    blockId: "search"
                    label: Translation.tr("Search")
                    targetIndex: SettingsChromeLayout.columnFor("search")
                }
            }

            Item {
                id: headerActions
                parent: SettingsChromeLayout.columnFor("actions") === 0 ? settingsHeaderSlot0
                    : SettingsChromeLayout.columnFor("actions") === 1 ? settingsHeaderSlot1
                    : settingsHeaderSlot2
                anchors.fill: parent
                anchors.topMargin: root.navEditMode ? 8 : 6
                anchors.bottomMargin: root.navEditMode ? 8 : 6

                RowLayout {
                    id: actionsRow
                    anchors.fill: parent
                    spacing: 4

                    RippleButton {
                        visible:Config.options?.panelFamily === "abyss"
                        buttonRadius:Appearance.rounding.full;implicitWidth:35;implicitHeight:35
                        onClicked:Quickshell.execDetached([Quickshell.shellPath("scripts/alis"),"ipc","call","abyss","editLayout"])
                        contentItem:MaterialSymbol {anchors.centerIn:parent;text:"dashboard_customize";iconSize:20}
                        StyledToolTip {text:Translation.tr("Edit Abyss Layout")}
                    }

                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 35
                        implicitHeight: 35
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "lock", "activate"])
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "lock"
                            iconSize: 20
                        }
                    }

                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 35
                        implicitHeight: 35
                        onClicked: root.close()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 20
                        }
                    }
                }

                SettingsChromeEditFrame {
                    anchors.fill: parent
                    active: root.navEditMode
                    blockId: "actions"
                    label: Translation.tr("Actions")
                    targetIndex: SettingsChromeLayout.columnFor("actions")
                }
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: root.navEditMode ? 228 : 204

                Behavior on implicitWidth {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }

                Flickable {
                    id: navRailFlickable
                    visible: !root.navEditMode || navEditLoader.status !== Loader.Ready
                    anchors.fill: parent
                    anchors.bottomMargin: navBottomActions.height + 8
                    contentHeight: navCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    ScrollBar.vertical: StyledScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                        id: navCol
                        width: parent.width
                        spacing: SettingsMaterialPreset.navItemSpacing

                        Repeater {
                            id: navRepeater
                            model: root.visibleNavItems

                            delegate: RippleButton {
                                id: navBtn
                                objectName:"settingsNav_"+(modelData.groupKey || modelData.key || "back")
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: SettingsMaterialPreset.navItemHeight
                                rippleEnabled: true
                                buttonRadius: Math.min(width, height) / 2
                                readonly property int pageRealIndex: modelData.realIndex
                                toggled: Hierarchy.selected(modelData,root.pages,root.currentPage)
                                colBackground: "transparent"
                                colBackgroundToggled: Appearance.colors.colPrimaryContainer
                                colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: root.activateNavigation(modelData)

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 9
                                    spacing: 9

                                    MaterialSymbol {
                                        text: navBtn.modelData.icon || ""
                                        iconSize: 18
                                        color: SettingsMaterialPreset.navigationIconColor(
                                            navBtn.index, root.visibleNavItems.length, navBtn.toggled)
                                        rotation: navBtn.modelData.iconRotation || 0
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: navBtn.modelData.name || ""
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: navBtn.toggled ? Font.DemiBold : Font.Normal
                                        color: navBtn.toggled
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnSurfaceVariant
                                        elide: Text.ElideRight
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                        }
                                    }
                                    MaterialSymbol {visible:!!navBtn.modelData.groupKey;text:"chevron_right";iconSize:18;color:Appearance.colors.colOnSurfaceVariant}
                                }
                            }
                        }
                    }
                }

                Loader {
                    id: navEditLoader
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        bottom: navBottomActions.top
                        bottomMargin: 8
                    }
                    active: root.navEditMode
                    asynchronous: true
                    visible: status === Loader.Ready
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    sourceComponent: Component {
                        SettingsNavEditPane {
                            currentPage: root.currentPage
                            onPageActivated: pageIndex => root.currentPage = pageIndex
                            onPageHidden: pageIndex => {
                                if (root.currentPage !== pageIndex)
                                    return
                                Qt.callLater(() => {
                                    if (root.navPageOrder.length > 0)
                                        root.currentPage = root.navPageOrder[0]
                                })
                            }
                            onDoneRequested: root.navEditMode = false
                        }
                    }
                }

                // Bottom actions: config file + overlay mode
                ColumnLayout {
                    id: navBottomActions
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 2

                    RippleButton {
                        id: navEditToggle
                        readonly property color editSurface: Appearance.colors.colPrimaryContainer
                        readonly property color editSurfaceHover: Appearance.colors.colPrimaryContainerHover
                        readonly property color editForeground: Appearance.colors.colOnPrimaryContainer
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        toggled: root.navEditMode
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colBackgroundToggled: editSurface
                        colBackgroundToggledHover: editSurfaceHover
                        onClicked: root.navEditMode = !root.navEditMode


                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 10

                            MaterialSymbol {
                                text: root.navEditMode ? "done" : "edit"
                                iconSize: 18
                                color: root.navEditMode
                                    ? navEditToggle.editForeground
                                    : Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.navEditMode
                                    ? Translation.tr("Done")
                                    : Translation.tr("Edit navigation")
                                font {
                                    family: Appearance.font.family.main
                                    pixelSize: Appearance.font.pixelSize.small
                                }
                                color: root.navEditMode
                                    ? navEditToggle.editForeground
                                    : Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        StyledToolTip {
                            position: "top"
                            text: root.navEditMode
                                ? Translation.tr("Finish editing navigation")
                                : Translation.tr("Reorder or hide Settings pages directly in the sidebar")
                        }
                    }

                    RippleButton {
                        id: configFileBtn
                        property bool justCopied: false
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover

                        onClicked: Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`)
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            configFileBtn.justCopied = true;
                            revertTextTimer.restart();
                        }

                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: configFileBtn.justCopied = false
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 10

                            MaterialSymbol {
                                text: configFileBtn.justCopied ? "check" : "edit"
                                iconSize: 18
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: configFileBtn.justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                                font {
                                    family: Appearance.font.family.main
                                    pixelSize: Appearance.font.pixelSize.small
                                }
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        StyledToolTip {
                            position: "top"
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    RippleButton {
                        id: overlayToggleBtn
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover

                        onClicked: {
                            Config.setNestedValue("settingsUi.overlayMode", true)
                            settingsRestartTimer.restart()
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 10

                            MaterialSymbol {
                                text: "layers"
                                iconSize: 18
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Overlay")
                                font {
                                    family: Appearance.font.family.main
                                    pixelSize: Appearance.font.pixelSize.small
                                }
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        StyledToolTip {
                            position: "top"
                            text: Translation.tr("Switch to overlay mode")
                        }
                    }
                }

                Timer {
                    id: settingsRestartTimer
                    interval: 500
                    onTriggered: {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"])
                        Qt.quit()
                    }
                }
            }

            Rectangle { // Content container
                id: contentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The windowBaseSurface owns the structural fill. Repainting
                // colLayer0 here would double-composite global transparency.
                color: "transparent"
                radius: Appearance.rounding.windowRounding - root.contentPadding
                border.width: 0
                border.color: "transparent"

                // ── Page header: icon + name + description ──
                Item {
                    id: windowPageHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    readonly property var meta: root.pages[root.currentPage] ?? {}
                    height: root.settingsSearchText.trim().length > 0 ? 0 : 48
                    visible: root.settingsSearchText.trim().length === 0

                    RowLayout {
                        id: windowPageHeaderRow
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 10

                        MaterialShapeWrappedMaterialSymbol {
                            text: windowPageHeader.meta.icon ?? ""
                            iconSize: 15
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            text: windowPageHeader.meta.name ?? ""
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.DemiBold
                            }
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: windowPageHeader.meta.desc ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() { if (Appearance.animationsEnabled) windowPageHeaderSwap.restart() }
                    }
                    SequentialAnimation {
                        id: windowPageHeaderSwap
                        NumberAnimation { target: windowPageHeaderRow; property: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration / 2; easing.type: Appearance.animation.elementMoveFast.type }
                        NumberAnimation { target: windowPageHeaderRow; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                        height: 1
                        color: Appearance.m3colors.m3outlineVariant
                        opacity: 0.5
                    }
                }

                SettingsPageHost {
                    id: pagesStack
                    anchors { top: windowPageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

                    pages: root.pages
                    requestedIndex: root.currentPage
                    visible: root.settingsSearchText.trim().length === 0
                    enabled: visible
                    loadEnabled: Config.ready && root._navigationInitialized

                    SettingsPageLoadingOverlay {
                        anchors.fill: parent
                        loading: pagesStack.loading && !pagesStack.error
                        z: 15
                    }

                }

                // Live search is the page content, never a floating dropdown.
                // The page host stays loaded but hidden so leaving search restores
                // the same page/section state without another expensive load.
                SettingsLiveSearchResults {
                    id: settingsLiveSearch
                    anchors.fill: parent
                    z: 20
                    query: root.settingsSearchText
                    results: root.settingsSearchResults
                    searchField: settingsSearchField
                    iconForPage: index => SettingsPageRegistry.iconForPage(index)
                    onActivated: entry => root.openSearchResult(entry)
                    onCloseRequested: root.openSearchResult({})
                }

            }
        }
    }
}
