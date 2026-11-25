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
import qs.modules.settings.iris
import "modules/settings/SettingsHierarchy.js" as Hierarchy
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.waffle.settings as WaffleSettings

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
    property int _requestedStartPage: -1
    property string _requestedStartSection: ""
    property bool _navigationInitialized: false

    property bool showingHome: false
    property var _historyStack: []
    property int _historyIndex: -1
    property bool _historyNavigating: false
    readonly property bool canGoBack: root._historyIndex > 0
    readonly property bool canGoForward: root._historyIndex >= 0 && root._historyIndex + 1 < root._historyStack.length
    property int settingsSearchSelectedIndex: 0

    function _pushHistoryEntry(isHome: bool, pageIdx: int): void {
        if (root._historyNavigating)
            return
        const cur = root._historyIndex >= 0 && root._historyIndex < root._historyStack.length
            ? root._historyStack[root._historyIndex]
            : null
        if (cur && Boolean(cur.home) === isHome && (isHome || Number(cur.pageIndex) === pageIdx))
            return
        const next = root._historyStack.slice(0, root._historyIndex + 1)
        next.push({ home: isHome, pageIndex: pageIdx })
        if (next.length > 32)
            next.shift()
        root._historyStack = next
        root._historyIndex = next.length - 1
    }

    function showHomeView(): void {
        if (root.settingsSearchText.length > 0) {
            root.settingsSearchText = ""
            root.settingsSearchResults = []
            if (settingsSearchField)
                settingsSearchField.text = ""
            if (compactSettingsSearchField)
                compactSettingsSearchField.text = ""
            if (waffleWindowRailHeader.searchField)
                waffleWindowRailHeader.searchField.text = ""
        }
        root.showingHome = true
        root._pushHistoryEntry(true, root.currentPage)
    }

    function navigateToArea(pageIndex: int): void {
        if (root.settingsSearchText.length > 0) {
            root.settingsSearchText = ""
            root.settingsSearchResults = []
            if (settingsSearchField)
                settingsSearchField.text = ""
            if (compactSettingsSearchField)
                compactSettingsSearchField.text = ""
            if (waffleWindowRailHeader.searchField)
                waffleWindowRailHeader.searchField.text = ""
        }
        const safe = SettingsPageRegistry.safePageIndex(pageIndex)
        root.showingHome = false
        if (pagesStack?.currentItem
                && typeof pagesStack.currentItem.exitSubView === "function"
                && Boolean(pagesStack.currentItem.isSubViewActive)
                && root.currentPage === safe) {
            pagesStack.currentItem.exitSubView()
        }
        if (root.currentPage !== safe) {
            root.currentPage = safe
        } else {
            root._pushHistoryEntry(false, safe)
            IrisState.recordVisit(safe)
        }
    }

    function goBack(): void {
        if (!root.canGoBack)
            return
        root._historyNavigating = true
        root._historyIndex = Math.max(0, root._historyIndex - 1)
        const entry = root._historyStack[root._historyIndex]
        if (entry?.home) {
            root.showingHome = true
        } else if (entry) {
            root.showingHome = false
            root.currentPage = SettingsPageRegistry.safePageIndex(Number(entry.pageIndex ?? 2))
        }
        root._historyNavigating = false
    }

    function goForward(): void {
        if (!root.canGoForward)
            return
        root._historyNavigating = true
        root._historyIndex = Math.min(root._historyStack.length - 1, root._historyIndex + 1)
        const entry = root._historyStack[root._historyIndex]
        if (entry?.home) {
            root.showingHome = true
        } else if (entry) {
            root.showingHome = false
            root.currentPage = SettingsPageRegistry.safePageIndex(Number(entry.pageIndex ?? 2))
        }
        root._historyNavigating = false
    }

    function moveSettingsSearchSelection(delta: int): void {
        const count = root.settingsSearchResults?.length ?? 0
        if (count <= 0) {
            root.settingsSearchSelectedIndex = 0
            return
        }
        root.settingsSearchSelectedIndex = Math.max(0, Math.min(count - 1, root.settingsSearchSelectedIndex + delta))
    }

    function acceptSettingsSearchSelection(): void {
        const count = root.settingsSearchResults?.length ?? 0
        if (count > 0) {
            const idx = Math.max(0, Math.min(count - 1, root.settingsSearchSelectedIndex))
            root.openSearchResult(root.settingsSearchResults[idx])
        }
    }

    function preferredCategoryEntry(categoryLabel: string, groupPages: var): var {
        if (!groupPages || groupPages.length === 0)
            return null
        if (Persistent.ready && Persistent.states?.settings) {
            try {
                const map = JSON.parse(String(Persistent.states.settings.categoryPages || "{}")) || {}
                const savedIdx = Number(map[categoryLabel] ?? -1)
                if (savedIdx >= 0) {
                    const found = groupPages.find(item => item.realIndex === savedIdx)
                    if (found)
                        return found
                }
            } catch (e) {}
        }
        return groupPages[0]
    }

    function _persistCurrentPage(): void {
        if (root._navigationInitialized && Persistent.ready && Persistent.states?.settings) {
            Persistent.states.settings.iiPage = Math.max(0, Math.min(root.currentPage, root.pages.length - 1))
            const pageIdx = Persistent.states.settings.iiPage
            const cats = SettingsPageRegistry.defaultCategories ?? []
            for (let i = 0; i < cats.length; i++) {
                const cat = cats[i]
                if (cat && Array.isArray(cat.pages) && cat.pages.includes(pageIdx) && cat.label) {
                    let map = {}
                    try {
                        map = JSON.parse(String(Persistent.states.settings.categoryPages || "{}")) || {}
                    } catch (e) {
                        map = {}
                    }
                    if (map[cat.label] !== pageIdx) {
                        map[cat.label] = pageIdx
                        Persistent.states.settings.categoryPages = JSON.stringify(map)
                    }
                    break
                }
            }
        }
    }

    function initializeNavigation(): void {
        if (root._navigationInitialized || !Persistent.ready)
            return
        const persisted = Persistent.states?.settings?.iiPage ?? 0
        const requested = root._requestedStartPage >= 0 ? root._requestedStartPage : persisted
        root.currentPage = SettingsPageRegistry.safePageIndex(requested)
        root.navGroup = Hierarchy.parentKey(root.pages[root.currentPage])
        // A stale external deep link must not spotlight a control in a retired page.
        if (root._requestedStartPage >= 0
                && !SettingsPageRegistry.isPageApplicable(root._requestedStartPage))
            root._requestedStartSection = ""
        root._navigationInitialized = true
        root._historyStack = [{ home: false, pageIndex: root.currentPage }]
        root._historyIndex = 0
        IrisState.recordVisit(root.currentPage)
        root._persistCurrentPage()
        if (root._requestedStartSection.length > 0) {
            root.pendingSpotlightSection = root._requestedStartSection
            root.pendingSpotlightPageIndex = root.currentPage
            root.pendingSpotlightSectionApplied = false
            root.trySpotlight()
        }
    }

    onCurrentPageChanged: {
        const safe = SettingsPageRegistry.safePageIndex(root.currentPage)
        if (safe !== root.currentPage) {
            root.currentPage = safe
            return
        }
        if (root._navigationInitialized && !root._historyNavigating) {
            root.showingHome = false
            root._pushHistoryEntry(false, root.currentPage)
            IrisState.recordVisit(root.currentPage)
        }
        root._persistCurrentPage()
        root.navGroup=Hierarchy.parentKey(root.pages[root.currentPage])
    }

    property bool uiReady: Config.ready && Persistent.ready && root._navigationInitialized

    property string navGroup: ""
    readonly property var navPageOrder: SettingsPageRegistry.navigationPageIndexes(false)
    readonly property var visibleNavItems: Hierarchy.entries(pages, navPageOrder,
        navGroup, currentPage, false)
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
    property bool pendingSpotlightSectionApplied: false
    property var searchTargetFlickable: null

    function openSearchResult(entry) {
        // Clear search immediately
        settingsSearchText = "";
        if (settingsSearchField) {
            settingsSearchField.text = "";
        }
        if (waffleWindowRailHeader.searchField) {
            waffleWindowRailHeader.searchField.text = "";
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
        if (pendingSpotlightSection.length > 0 && pagesStack && typeof pagesStack._applySectionToPage === "function") {
            pagesStack._applySectionToPage(entry.pageIndex, pendingSpotlightSection);
            pendingSpotlightSectionApplied = true;
        }
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
        if (pendingSpotlightPageIndex < 0 || root.currentPage !== pendingSpotlightPageIndex) {
            resetSearchTarget();
            return;
        }
        const pageItem = pagesStack.currentItem
        if (!pageItem || pagesStack.currentIndex !== pendingSpotlightPageIndex) {
            if (spotlightRetryCount < spotlightMaxRetries) {
                spotlightRetryCount++;
                spotlightPageLoadTimer.restart();
            } else {
                resetSearchTarget();
            }
            return;
        }
        if (!pendingSpotlightSectionApplied && pendingSpotlightSection.length > 0
                && typeof pageItem.activateSettingsSearchSection === "function") {
            pageItem.activateSettingsSearchSection(pendingSpotlightSection)
            pendingSpotlightSectionApplied = true
        }

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
            pendingSpotlightSectionApplied = false;
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

        // Clamp to valid scroll range (non-interactive pages must remain at contentY = 0)
        var maxScroll = flick.interactive ? Math.max(0, flick.contentHeight - flick.height) : 0;
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
        pendingSpotlightSectionApplied = false;
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
        spotlightPageLoadTimer.stop();
        searchTargetControl = null;
        searchTargetFlickable = null;
        spotlightTargetScrollY = 0;
        pendingSpotlightOptionId = -1;
        pendingSpotlightLabel = "";
        pendingSpotlightSection = "";
        pendingSpotlightPageIndex = -1;
        pendingSpotlightIsSection = false;
        pendingSpotlightSectionApplied = false;
    }

    visible: true
    onClosing: Qt.quit()
    title: "alis Settings"

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
        if (root.uiReady && !root._firstFramePainted)
            Qt.callLater(() => { root._firstFramePainted = true })
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

    Connections {
        target: Config.options ?? null
        function onPanelFamilyChanged() {
            if (!SettingsPageRegistry.isPageApplicable(root.currentPage))
                root.currentPage = 0
        }
    }

    readonly property real waffleBarReserve: Config.options?.panelFamily === "waffle" ? 48 : 0
    readonly property real _screenW: Screen.width > 0 ? Screen.width : 1920
    readonly property real targetWindowWidth: Config.options?.panelFamily === "waffle"
        ? Math.round(Math.min(
            1600,
            Math.max(900, root._screenW * 0.90),
            Math.max(750, root._screenW - 48)))
        : Math.round(Math.min(
            Math.max(750, root._screenW - 48),
            root._screenW * (Config.options?.dashboard?.widthRatio ?? 0.72) + 40))
    readonly property real _screenAvailHeight: Math.max(0, (Screen.height > 0 ? Screen.height : 1200) - root.waffleBarReserve)
    readonly property real targetWindowHeight: Config.options?.panelFamily === "waffle"
        ? Math.round(Math.max(560, Math.min(
            Math.round(1280 * Math.max(1, Appearance.fontSizeScale)),
            Math.round(root._screenAvailHeight * 0.92),
            Math.max(500, root._screenAvailHeight - 40))))
        : Math.round(Math.min(
            Math.max(500, root._screenAvailHeight - 40),
            root._screenAvailHeight * (Config.options?.dashboard?.heightRatio ?? 0.72) + 40))

    function handleEscape(): bool {
        if (root.settingsSearchText.length > 0) {
            root.openSearchResult({})
            return true
        }
        if (typeof pagesStack?.currentItem?.handleEscape === "function"
                && pagesStack.currentItem.handleEscape()) {
            return true
        }
        if (Boolean(pagesStack?.currentItem?.isSubViewActive)
                && typeof pagesStack.currentItem.exitSubView === "function") {
            pagesStack.currentItem.exitSubView()
            return true
        }
        return false
    }

    function dismissFromEscape(): void {
        if (!root.handleEscape())
            root.close()
    }

    property bool _firstFramePainted: false
    onUiReadyChanged: {
        if (root.uiReady && !root._firstFramePainted)
            Qt.callLater(() => { root._firstFramePainted = true })
    }

    minimumWidth: 750
    minimumHeight: 500
    width: targetWindowWidth
    height: targetWindowHeight
    // Match Screen Edge's render path: keep the native window transparent and
    // let one QML surface own colLayer0, including any global transparency.
    color: "transparent"

    Rectangle {
        id: windowBaseSurface
        anchors.fill: parent
        z: 0
        visible: !SettingsMaterialPreset.waffle
        color: root.uiReady ? Appearance.colors.colLayer0 : "transparent"
    }

    AlisLoadingScreen {
        id: windowStartupLoadingScreen
        objectName: "settingsWindowStartupLoadingScreen"
        anchors.fill: parent
        z: 5
        loading: !root.uiReady
        title: Translation.tr("Settings")
        icon: "tune"
        fillSurface: true
        backdropOpacity: 0.96
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: {
            if (SettingsMaterialPreset.waffle)
                waffleWindowRailHeader.focusSearch()
            else if (navRailWrapper.compact)
                compactSettingsSearchField.forceActiveFocus()
            else
                settingsSearchField.forceActiveFocus()
        }
    }

    Shortcut {
        id: windowEscapeShortcut
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: !settingsSearchField.activeFocus
            && !compactSettingsSearchField.activeFocus
            && !waffleWindowRailHeader.searchField.activeFocus
        onActivated: root.dismissFromEscape()
    }

    Rectangle {
        id: windowMainFrame
        anchors.fill: parent
        z: 2
        color: (SettingsMaterialPreset.waffle && root.uiReady)
            ? SettingsMaterialPreset.windowColor
            : "transparent"
        visible: root.uiReady
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.dismissFromEscape()
                event.accepted = true
                return
            }
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Tab) {
                    root.currentPage = root.nextNavPage(root.currentPage)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Backtab) {
                    root.currentPage = root.prevNavPage(root.currentPage)
                    event.accepted = true
                }
            } else if (event.modifiers === Qt.AltModifier) {
                if (event.key === Qt.Key_Left) {
                    root.goBack()
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.goForward()
                    event.accepted = true
                }
            }
        }

        WaffleSettings.WWin11SettingsTitleBar {
            id: waffleWindowTitleBar
            visible: SettingsMaterialPreset.waffle && (Config.options?.windows?.showTitlebar ?? true)
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            embedded: false
            isOverlay: false
            canGoBack: root.canGoBack || root.settingsSearchText.length > 0
            onBackRequested: {
                if (root.settingsSearchText.length > 0)
                    root.openSearchResult({})
                else
                    root.goBack()
            }
            onSwitchModeRequested: {
                Config.setNestedValue("waffles.settings.windowMode", false)
                Config.setNestedValue("settingsUi.overlayMode", true)
                settingsRestartTimer.restart()
            }
            onLockRequested: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "lock", "activate"])
            onCloseRequested: root.close()
        }

        RowLayout {
            id: windowBodyRow
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: waffleWindowTitleBar.visible ? waffleWindowTitleBar.height : (SettingsMaterialPreset.waffle ? 8 : 12)
                leftMargin: SettingsMaterialPreset.waffle ? 14 : 12
                rightMargin: SettingsMaterialPreset.waffle ? 0 : 12
                bottomMargin: SettingsMaterialPreset.waffle ? 10 : 12
            }
            spacing: SettingsMaterialPreset.waffle ? 8 : 12

            // ── Left Navigation Sidebar ──
            Rectangle {
                id: navRailWrapper
                objectName: "settingsWindowNavRail"
                Layout.fillHeight: true
                readonly property bool compact: SettingsMaterialPreset.useCompactNav(windowMainFrame.width, false)
                readonly property real targetRailWidth: SettingsMaterialPreset.waffle
                    ? Math.min(SettingsMaterialPreset.waffleRailWidth, Math.max(216, Math.round(windowMainFrame.width * 0.24)))
                    : (compact ? SettingsMaterialPreset.compactNavWidth : SettingsMaterialPreset.navSidebarWidth)
                Layout.preferredWidth: targetRailWidth
                implicitWidth: targetRailWidth
                radius: SettingsMaterialPreset.waffle ? Appearance.rounding.normal : SettingsMaterialPreset.cardRadius
                color: SettingsMaterialPreset.waffle ? "transparent" : SettingsMaterialPreset.sidebarColor
                border.width: SettingsMaterialPreset.waffle ? 0 : 1
                border.color: SettingsMaterialPreset.waffle ? "transparent" : SettingsMaterialPreset.sidebarBorderColor

                Behavior on Layout.preferredWidth {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }

                WaffleSettings.WWin11SettingsRailHeader {
                    id: waffleWindowRailHeader
                    visible: SettingsMaterialPreset.waffle
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 2
                    }
                    searchQuery: root.settingsSearchText
                    resultCount: root.settingsSearchResults.length
                    onAccountClicked: root.navigateToArea(1)
                    onSearchTextEdited: query => {
                        root.settingsSearchText = query
                        root.recomputeSettingsSearchResults()
                    }
                    onFocusResultsRequested: settingsLiveSearch.focusResults()
                    onAcceptCurrentResultRequested: settingsLiveSearch.activateCurrent()
                    onClearSearchRequested: root.openSearchResult({})
                    onEscapeEmptySearchRequested: root.dismissFromEscape()
                }

                // ── Sidebar Header: Identity + Integrated Search ──
                ColumnLayout {
                    id: windowSidebarTopHeader
                    visible: !SettingsMaterialPreset.waffle
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 12
                        leftMargin: navRailWrapper.compact ? 8 : 12
                        rightMargin: navRailWrapper.compact ? 8 : 12
                    }
                    spacing: 10

                    RippleButton {
                        id: windowIdentityButton
                        objectName: "windowIdentityAboutButton"
                        readonly property bool isAboutSelected: !root.showingHome && root.currentPage === 40
                        Layout.fillWidth: true
                        implicitHeight: Math.max(46, Math.round(46 * Appearance.fontSizeScale))
                        buttonRadius: 11
                        toggled: isAboutSelected
                        colBackground: "transparent"
                        colBackgroundHover: SettingsMaterialPreset.navHoverColor
                        colBackgroundToggled: SettingsMaterialPreset.navSelectedColor
                        colBackgroundToggledHover: SettingsMaterialPreset.navSelectedHoverColor
                        Accessible.name: Translation.tr("About Alis")
                        onClicked: {
                            if (SettingsPageRegistry.isPageApplicable(40)) {
                                root.showingHome = false
                                root.currentPage = 40
                                if (root.settingsSearchText.length > 0)
                                    root.openSearchResult({})
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("About Alis & system info")
                        }

                        contentItem: Item {
                            implicitWidth: windowIdentityRow.implicitWidth
                            implicitHeight: windowIdentityRow.implicitHeight

                            RowLayout {
                                id: windowIdentityRow
                                anchors {
                                    fill: parent
                                    leftMargin: navRailWrapper.compact ? 0 : 6
                                    rightMargin: navRailWrapper.compact ? 0 : 6
                                }
                                spacing: 10

                                Item {
                                    Layout.alignment: navRailWrapper.compact ? Qt.AlignHCenter : Qt.AlignVCenter
                                    Layout.fillWidth: navRailWrapper.compact
                                    implicitWidth: 34
                                    implicitHeight: 34

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 34
                                        height: 34
                                        radius: width / 2
                                        color: SettingsMaterialPreset.cardColor
                                        border.width: 1.5
                                        border.color: windowIdentityButton.isAboutSelected
                                            ? Appearance.colors.colPrimary
                                            : SettingsMaterialPreset.accentBorder
                                    }

                                    Rectangle {
                                        id: settingsAvatarMask
                                        anchors.centerIn: parent
                                        width: 30
                                        height: 30
                                        radius: width / 2
                                        visible: false
                                    }

                                    Image {
                                        id: settingsAvatarImage
                                        anchors.centerIn: parent
                                        width: 30
                                        height: 30
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
                                    visible: !navRailWrapper.compact
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        color: windowIdentityButton.isAboutSelected
                                            ? SettingsMaterialPreset.navSelectedTextColor
                                            : Appearance.colors.colOnLayer0
                                        text: Translation.tr("Settings")
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font {
                                            family: Appearance.font.family.title
                                            pixelSize: Appearance.font.pixelSize.large
                                            weight: Font.DemiBold
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: SystemInfo.displayName || SystemInfo.username
                                        color: windowIdentityButton.isAboutSelected
                                            ? SettingsMaterialPreset.navSelectedTextColor
                                            : SettingsMaterialPreset.secondaryTextColor
                                        opacity: windowIdentityButton.isAboutSelected ? 0.82 : 1.0
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }
                        }
                    }

                    // Integrated Search Pill (expanded sidebar)
                    Rectangle {
                        id: searchContainer
                        visible: !navRailWrapper.compact
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(34 * Appearance.fontSizeScale)
                        radius: SettingsMaterialPreset.searchRadius
                        color: settingsSearchField.activeFocus
                            ? SettingsMaterialPreset.cardColor
                            : SettingsMaterialPreset.controlSurface
                        border.width: settingsSearchField.activeFocus ? 1.5 : 1
                        border.color: settingsSearchField.activeFocus
                            ? Appearance.colors.colPrimary
                            : SettingsMaterialPreset.controlBorderColor

                        Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: 150 } }
                        Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 6

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: root.settingsSearchResults.length > 0 ? "manage_search" : "search"
                                iconSize: 16
                                color: settingsSearchField.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : SettingsMaterialPreset.secondaryTextColor
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                StyledText {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Search...")
                                    color: SettingsMaterialPreset.secondaryTextColor
                                    font.family: SettingsMaterialPreset.fontFamily
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    visible: settingsSearchField.text.length === 0 && !settingsSearchField.activeFocus
                                    elide: Text.ElideRight
                                }

                                TextInput {
                                    id: settingsSearchField
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    color: SettingsMaterialPreset.textColor
                                    selectionColor: Appearance.colors.colPrimaryContainer
                                    selectedTextColor: Appearance.colors.colOnPrimaryContainer
                                    font.family: SettingsMaterialPreset.fontFamily
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    clip: true
                                    selectByMouse: true
                                    cursorVisible: activeFocus
                                    cursorDelegate: Rectangle {
                                        visible: settingsSearchField.cursorVisible
                                        width: 1.8
                                        color: Appearance.colors.colPrimary
                                    }

                                    Connections {
                                        target: root
                                        function onSettingsSearchTextChanged() {
                                            if (settingsSearchField.text !== root.settingsSearchText)
                                                settingsSearchField.text = root.settingsSearchText
                                        }
                                    }

                                    onTextChanged: {
                                        if (root.settingsSearchText !== text) {
                                            root.settingsSearchText = text
                                            root.recomputeSettingsSearchResults()
                                        }
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
                                            if (root.settingsSearchText.length > 0) {
                                                root.openSearchResult({})
                                            } else {
                                                settingsSearchField.focus = false
                                                root.dismissFromEscape()
                                            }
                                            event.accepted = true
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: root.settingsSearchText.length === 0 && !settingsSearchField.activeFocus
                                Layout.alignment: Qt.AlignVCenter
                                implicitHeight: 19
                                implicitWidth: winSearchHintKey.implicitWidth + 10
                                radius: 5
                                color: SettingsMaterialPreset.cardColor
                                border.width: 1
                                border.color: SettingsMaterialPreset.controlBorderColor

                                StyledText {
                                    id: winSearchHintKey
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "^F"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    color: SettingsMaterialPreset.secondaryTextColor
                                }
                            }

                            RippleButton {
                                id: clearButton
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                buttonRadius: Appearance.rounding.full
                                visible: root.settingsSearchText.length > 0
                                colBackground: "transparent"
                                colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                                onClicked: {
                                    root.openSearchResult({})
                                    settingsSearchField.forceActiveFocus()
                                }
                                StyledToolTip { text: Translation.tr("Clear search") }
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "close"
                                    iconSize: 14
                                    color: SettingsMaterialPreset.secondaryTextColor
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: SettingsMaterialPreset.plateDividerColor
                    }
                }

                Flickable {
                    id: navRailFlickable
                    anchors {
                        top: SettingsMaterialPreset.waffle ? waffleWindowRailHeader.bottom : windowSidebarTopHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: SettingsMaterialPreset.waffle ? parent.bottom : navBottomActions.top
                        topMargin: 8
                        leftMargin: SettingsMaterialPreset.waffle ? 2 : 8
                        rightMargin: SettingsMaterialPreset.waffle ? 2 : 8
                        bottomMargin: SettingsMaterialPreset.waffle ? 6 : 8
                    }
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
                        spacing: SettingsMaterialPreset.waffle ? 3 : 4

                        Repeater {
                            id: navRepeater
                            model: SettingsPageRegistry.defaultCategories

                            delegate: RippleButton {
                                id: navHeadingGroup
                                Accessible.name: navHeadingGroup.headingTitle
                                required property int index
                                required property var modelData
                                readonly property string headingTitle: String(navHeadingGroup.modelData?.label ?? "")
                                readonly property var groupPages: (navHeadingGroup.modelData?.pages ?? []).filter(
                                    idx => root.pages[idx] && SettingsPageRegistry.isPageApplicable(idx)).map(
                                    idx => Object.assign({}, root.pages[idx], { realIndex: idx }))
                                readonly property bool hasActivePage: navHeadingGroup.groupPages.some(
                                    item => item.realIndex === root.currentPage)
                                objectName: navHeadingGroup.groupPages.length > 0
                                    ? ("settingsNav_" + (navHeadingGroup.groupPages[0].key || ""))
                                    : ("settingsNavGroup_" + index)
                                visible: navHeadingGroup.groupPages.length > 0
                                Layout.fillWidth: true
                                implicitHeight: Math.round(38 * Appearance.fontSizeScale)
                                rippleEnabled: true
                                buttonRadius: SettingsMaterialPreset.navItemRadius
                                toggled: navHeadingGroup.hasActivePage
                                colBackground: "transparent"
                                colBackgroundHover: SettingsMaterialPreset.navHoverColor
                                colBackgroundToggled: SettingsMaterialPreset.navSelectedColor
                                colBackgroundToggledHover: SettingsMaterialPreset.navSelectedHoverColor

                                onClicked: {
                                    if (navHeadingGroup.groupPages.length > 0) {
                                        const hubEntry = root.preferredCategoryEntry(navHeadingGroup.headingTitle, navHeadingGroup.groupPages)
                                        if (pagesStack.currentItem && typeof pagesStack.currentItem.exitSubView === "function" && pagesStack.currentItem.isSubViewActive)
                                            pagesStack.currentItem.exitSubView()
                                        if (root.currentPage !== hubEntry.realIndex)
                                            root.activateNavigation(hubEntry)
                                        if (root.settingsSearchText.length > 0)
                                            root.openSearchResult({})
                                    }
                                }

                                Rectangle {
                                    objectName: SettingsMaterialPreset.waffle ? "waffleSettingsSelectionIndicator" : "settingsNavActiveIndicator"
                                    visible: navHeadingGroup.hasActivePage
                                    anchors.left: parent.left
                                    anchors.leftMargin: SettingsMaterialPreset.waffle ? 2 : 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 18
                                    radius: 1.5
                                    color: SettingsMaterialPreset.waffle
                                        ? SettingsMaterialPreset.accentColor
                                        : Appearance.colors.colPrimary
                                }

                                StyledToolTip {
                                    position: "right"
                                    extraVisibleCondition: navRailWrapper.compact
                                    text: navHeadingGroup.headingTitle
                                }

                                contentItem: Item {
                                    implicitWidth: winNavRow.implicitWidth
                                    implicitHeight: winNavRow.implicitHeight

                                    MaterialSymbol {
                                        visible: navRailWrapper.compact
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: navHeadingGroup.groupPages.length > 0
                                            ? SettingsPageRegistry.iconForPage(navHeadingGroup.groupPages[0].realIndex)
                                            : "folder"
                                        iconSize: 19
                                        color: SettingsMaterialPreset.navigationIconColor(
                                            navHeadingGroup.index,
                                            Math.max(1, SettingsPageRegistry.defaultCategories.length),
                                            navHeadingGroup.hasActivePage)
                                    }

                                    RowLayout {
                                        id: winNavRow
                                        visible: !navRailWrapper.compact
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: navHeadingGroup.groupPages.length > 0
                                                ? SettingsPageRegistry.iconForPage(navHeadingGroup.groupPages[0].realIndex)
                                                : "folder"
                                            iconSize: 18
                                            color: SettingsMaterialPreset.navigationIconColor(
                                                navHeadingGroup.index,
                                                Math.max(1, SettingsPageRegistry.defaultCategories.length),
                                                navHeadingGroup.hasActivePage)
                                        }

                                        StyledText {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            verticalAlignment: Text.AlignVCenter
                                            text: navHeadingGroup.headingTitle
                                            font.family: SettingsMaterialPreset.fontFamily
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: navHeadingGroup.hasActivePage ? Font.DemiBold : Font.Medium
                                            color: navHeadingGroup.hasActivePage
                                                ? SettingsMaterialPreset.navSelectedTextColor
                                                : SettingsMaterialPreset.textColor
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Clean Centered Footer: Config + Overlay (Edit Layout & Edit Navigation removed) ──
                ColumnLayout {
                    id: navBottomActions
                    visible: !SettingsMaterialPreset.waffle
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                        bottomMargin: 10
                        leftMargin: 8
                        rightMargin: 8
                    }
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: SettingsMaterialPreset.plateDividerColor
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: navRailWrapper.compact ? 1 : 2
                        uniformCellWidths: !navRailWrapper.compact
                        columnSpacing: 6
                        rowSpacing: 6

                        RippleButton {
                            id: configFileBtn
                            Accessible.name: configFileBtnLabel.text
                            property bool justCopied: false
                            Layout.fillWidth: true
                            implicitHeight: Math.round(34 * Appearance.fontSizeScale)
                            buttonRadius: 10
                            colBackground: SettingsMaterialPreset.controlSurface
                            colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover

                            onClicked: Qt.openUrlExternally(`${Directories.config}/alis/config.json`)
                            altAction: () => {
                                Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/alis/config.json`)
                                configFileBtn.justCopied = true
                                revertTextTimer.restart()
                            }

                            Timer {
                                id: revertTextTimer
                                interval: 1500
                                onTriggered: configFileBtn.justCopied = false
                            }

                            contentItem: Item {
                                implicitWidth: configBtnRow.implicitWidth
                                implicitHeight: configBtnRow.implicitHeight

                                Row {
                                    id: configBtnRow
                                    anchors.centerIn: parent
                                    spacing: navRailWrapper.compact ? 0 : 6

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: configFileBtn.justCopied ? "check" : "code"
                                        iconSize: 16
                                        color: configFileBtn.justCopied
                                            ? Appearance.colors.colPrimary
                                            : SettingsMaterialPreset.secondaryTextColor
                                    }

                                    StyledText {
                                        id: configFileBtnLabel
                                        visible: !navRailWrapper.compact
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: configFileBtn.justCopied ? Translation.tr("Copied") : Translation.tr("Config")
                                        font.family: SettingsMaterialPreset.fontFamily
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Medium
                                        color: SettingsMaterialPreset.textColor
                                    }
                                }
                            }

                            StyledToolTip {
                                position: "top"
                                text: Translation.tr("Open the shell config file\nRight-click to copy path")
                            }
                        }

                        RippleButton {
                            id: overlayToggleBtn
                            Accessible.name: overlayToggleBtnLabel.text
                            Layout.fillWidth: true
                            implicitHeight: Math.round(34 * Appearance.fontSizeScale)
                            buttonRadius: 10
                            colBackground: SettingsMaterialPreset.controlSurface
                            colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover

                            onClicked: {
                                Config.setNestedValue("settingsUi.overlayMode", true)
                                settingsRestartTimer.restart()
                            }

                            contentItem: Item {
                                implicitWidth: overlayBtnRow.implicitWidth
                                implicitHeight: overlayBtnRow.implicitHeight

                                Row {
                                    id: overlayBtnRow
                                    anchors.centerIn: parent
                                    spacing: navRailWrapper.compact ? 0 : 6

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "layers"
                                        iconSize: 16
                                        color: SettingsMaterialPreset.secondaryTextColor
                                    }

                                    StyledText {
                                        id: overlayToggleBtnLabel
                                        visible: !navRailWrapper.compact
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Overlay")
                                        font.family: SettingsMaterialPreset.fontFamily
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Medium
                                        color: SettingsMaterialPreset.textColor
                                    }
                                }
                            }

                            StyledToolTip {
                                position: "top"
                                text: Translation.tr("Switch to overlay mode")
                            }
                        }
                    }
                }

                Timer {
                    id: settingsRestartTimer
                    interval: 180
                    onTriggered: {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings", "--overlay"])
                        Qt.quit()
                    }
                }
            }

            // ── Right Workspace Area ──
            Rectangle {
                id: contentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                // windowBaseSurface owns the structural colLayer0 fill; keep inner content transparent.
                color: "transparent"
                radius: Appearance.rounding.windowRounding - root.contentPadding
                border.width: 0
                border.color: "transparent"
                clip: true

                Item {
                    id: windowPageHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    readonly property var meta: root.pages[root.currentPage] ?? {}
                    readonly property var activeCategory: SettingsPageRegistry.defaultCategories.find(
                        cat => (cat?.pages ?? []).includes(root.currentPage)) ?? null
                    readonly property Item activePageItem: pagesStack.currentItem
                    readonly property bool isOnInPageSubView: Boolean(activePageItem?.isSubViewActive)
                    readonly property bool isDrilledDown: isOnInPageSubView
                    readonly property string backLabel: activeCategory?.label || meta.name || Translation.tr("Back")
                    readonly property string activeTitle: isOnInPageSubView && String(activePageItem?.activeSubViewTitle || "").length > 0
                        ? String(activePageItem.activeSubViewTitle)
                        : String(activeCategory?.label || meta.name || "")
                    readonly property string activeIcon: String(meta.icon || "settings")

                    function navigateBack(): void {
                        if (windowPageHeader.isOnInPageSubView && windowPageHeader.activePageItem
                                && typeof windowPageHeader.activePageItem.exitSubView === "function") {
                            windowPageHeader.activePageItem.exitSubView()
                        }
                    }

                    height: root.settingsSearchText.trim().length > 0
                        ? (navRailWrapper.compact && !SettingsMaterialPreset.waffle ? Math.round(50 * Appearance.fontSizeScale) : 0)
                        : (SettingsMaterialPreset.waffle ? 56 : Math.max(Math.round(54 * Appearance.fontSizeScale), windowPageHeaderRow.implicitHeight + 10))
                    visible: height > 0

                    WaffleSettings.WWin11SettingsBreadcrumb {
                        id: waffleWindowBreadcrumb
                        visible: SettingsMaterialPreset.waffle
                        anchors.fill: parent
                        categoryTitle: windowPageHeader.activeTitle
                        hasSubTabs: Boolean(windowPageHeader.activePageItem?._subTabItems?.length > 1)
                        subPageTitle: String(windowPageHeader.activePageItem?.activeSubTabLabel ?? "")
                        contentLeftMargin: Number(windowPageHeader.activePageItem?._horizontalMargin ?? 28)
                        onCategoryRootClicked: {
                            const items = windowPageHeader.activePageItem?._subTabItems ?? []
                            if (items.length > 0 && typeof windowPageHeader.activePageItem?.activateSubTabItem === "function")
                                windowPageHeader.activePageItem.activateSubTabItem(items[0])
                        }
                    }

                    RowLayout {
                        id: windowPageHeaderRow
                        visible: !SettingsMaterialPreset.waffle
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 4
                        anchors.bottomMargin: 6
                        spacing: 11

                        RippleButton {
                            id: windowBackBtn
                            objectName: "settingsHeaderBackButton"
                            visible: windowPageHeader.isDrilledDown && root.settingsSearchText.trim().length === 0
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 30
                            implicitWidth: windowBackRow.implicitWidth + 18
                            buttonRadius: height / 2
                            colBackground: SettingsMaterialPreset.pillSelectedColor
                            colBackgroundHover: SettingsMaterialPreset.pillSelectedHoverColor
                            onClicked: windowPageHeader.navigateBack()
                            StyledToolTip { text: Translation.tr("Go back") }

                            contentItem: Item {
                                implicitWidth: windowBackRow.implicitWidth
                                implicitHeight: windowBackRow.implicitHeight
                                Row {
                                    id: windowBackRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "chevron_left"
                                        iconSize: 17
                                        color: SettingsMaterialPreset.pillSelectedTextColor
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: windowPageHeader.backLabel
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: SettingsMaterialPreset.pillSelectedTextColor
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.settingsSearchText.trim().length === 0
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 10
                            color: SettingsMaterialPreset.accentTint
                            border.width: 1
                            border.color: SettingsMaterialPreset.accentBorder

                            MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: windowPageHeader.activeIcon
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }
                        }

                        ColumnLayout {
                            visible: root.settingsSearchText.trim().length === 0
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: windowPageHeader.activeTitle
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.large
                                    weight: Font.DemiBold
                                }
                                color: SettingsMaterialPreset.textColor
                            }

                            StyledText {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: String(windowPageHeader.meta.desc ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: SettingsMaterialPreset.secondaryTextColor
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        // Compact-mode inline search field
                        Rectangle {
                            visible: navRailWrapper.compact
                            Layout.fillWidth: root.settingsSearchText.trim().length > 0
                            Layout.preferredWidth: root.settingsSearchText.trim().length > 0 ? 320 : 210
                            Layout.maximumWidth: root.settingsSearchText.trim().length > 0 ? 480 : 240
                            Layout.preferredHeight: Math.round(34 * Appearance.fontSizeScale)
                            Layout.alignment: Qt.AlignVCenter
                            radius: SettingsMaterialPreset.searchRadius
                            color: compactSettingsSearchField.activeFocus
                                ? SettingsMaterialPreset.cardColor
                                : SettingsMaterialPreset.controlSurface
                            border.width: compactSettingsSearchField.activeFocus ? 1.5 : 1
                            border.color: compactSettingsSearchField.activeFocus
                                ? Appearance.colors.colPrimary
                                : SettingsMaterialPreset.controlBorderColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 6

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: root.settingsSearchResults.length > 0 ? "manage_search" : "search"
                                    iconSize: 16
                                    color: compactSettingsSearchField.activeFocus
                                        ? Appearance.colors.colPrimary
                                        : SettingsMaterialPreset.secondaryTextColor
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: compactSettingsSearchField.text.length === 0 && !compactSettingsSearchField.activeFocus
                                        text: Translation.tr("Search settings...")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: SettingsMaterialPreset.secondaryTextColor
                                        elide: Text.ElideRight
                                    }

                                    TextInput {
                                        id: compactSettingsSearchField
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        color: SettingsMaterialPreset.textColor
                                        font.family: SettingsMaterialPreset.fontFamily
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        clip: true
                                        selectByMouse: true
                                        selectionColor: Appearance.colors.colPrimaryContainer
                                        selectedTextColor: Appearance.colors.colOnPrimaryContainer
                                        cursorVisible: activeFocus
                                        cursorDelegate: Rectangle {
                                            visible: compactSettingsSearchField.cursorVisible
                                            width: 1.8
                                            color: Appearance.colors.colPrimary
                                        }

                                        Connections {
                                            target: root
                                            function onSettingsSearchTextChanged() {
                                                if (compactSettingsSearchField.text !== root.settingsSearchText)
                                                    compactSettingsSearchField.text = root.settingsSearchText
                                            }
                                        }

                                        onTextChanged: {
                                            if (root.settingsSearchText !== text) {
                                                root.settingsSearchText = text
                                                root.recomputeSettingsSearchResults()
                                            }
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
                                                if (root.settingsSearchText.length > 0) {
                                                    root.openSearchResult({})
                                                } else {
                                                    compactSettingsSearchField.focus = false
                                                    root.dismissFromEscape()
                                                }
                                                event.accepted = true
                                            }
                                        }
                                    }
                                }

                                RippleButton {
                                    visible: root.settingsSearchText.length > 0
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    Layout.alignment: Qt.AlignVCenter
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                                    onClicked: {
                                        root.openSearchResult({})
                                        compactSettingsSearchField.forceActiveFocus()
                                    }
                                    contentItem: MaterialSymbol {
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "close"
                                        iconSize: 14
                                        color: SettingsMaterialPreset.secondaryTextColor
                                    }
                                }
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() { if (Appearance.animationsEnabled) windowPageHeaderSwap.restart() }
                    }
                    SequentialAnimation {
                        id: windowPageHeaderSwap
                        NumberAnimation { target: windowPageHeaderRow; property: "opacity"; to: 0.35; duration: Appearance.animation.elementMoveFast.duration / 2; easing.type: Appearance.animation.elementMoveFast.type }
                        NumberAnimation { target: windowPageHeaderRow; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type }
                    }

                    Rectangle {
                        visible: !SettingsMaterialPreset.waffle
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                        height: 1
                        color: SettingsMaterialPreset.plateDividerColor
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
                        && (root._firstFramePainted || Quickshell.env("QT_QUICK_BACKEND") === "software")
                    onPageNavigationRequested: pageIndex => root.currentPage = pageIndex

                    SettingsPageLoadingOverlay {
                        anchors.fill: parent
                        loading: pagesStack.loading && !pagesStack.error
                        title: String(root.pages?.[root.currentPage]?.name ?? "")
                        icon: String(root.pages?.[root.currentPage]?.icon ?? "tune")
                        z: 15
                    }
                }

                SettingsLiveSearchResults {
                    id: settingsLiveSearch
                    anchors { top: windowPageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    z: 20
                    query: root.settingsSearchText
                    results: root.settingsSearchResults
                    searchField: SettingsMaterialPreset.waffle
                        ? waffleWindowRailHeader.searchField
                        : (navRailWrapper.compact ? compactSettingsSearchField : settingsSearchField)
                    iconForPage: index => SettingsPageRegistry.iconForPage(index)
                    onActivated: entry => root.openSearchResult(entry)
                    onCloseRequested: root.openSearchResult({})
                }
            }
        }
    }
}
