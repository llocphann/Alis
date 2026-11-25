import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.settings
import qs.modules.settings.iris
import "SettingsHierarchy.js" as Hierarchy
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.perimeter
import qs.modules.common.functions as CF
import qs.modules.waffle.settings as WaffleSettings

/**
 * Settings UI as a layer shell overlay panel.
 * Allows users to see live changes to the shell (sidebars, bar, etc.)
 * without opening a separate window. Loaded by the main shell when
 * Config.options?.settingsUi?.overlayMode is true.
 */
Scope {
    id: root
    // Optional host supplied by a family's continuous surface compositor.
    // The ordinary Material layer host remains unchanged when this is null.
    property Item embeddedHost: null
    property var pageHost: null

    property bool settingsOpen: GlobalStates.settingsOverlayOpen ?? false

    // Keep the PanelWindow alive through the card's exit slide. Backdrop and
    // scrim state snap; top-level Settings presentation is slide-only.
    // When hosted inside AbyssSettingsContent, AbyssBodyHost owns lifecycle/retention.
    property bool _panelLoaded: settingsOpen || _closeAnimRunning || Boolean(root.embeddedHost)
    property bool _closeAnimRunning: false
    property real _surfaceReveal: settingsOpen ? 1 : 0
    readonly property real _screenEdgeThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))


    Behavior on _surfaceReveal {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: SurfaceMotion.duration
            easing.type: SurfaceMotion.easingType
        }
    }

    onSettingsOpenChanged: {
        if (root.embeddedHost) {
            _closeAnimRunning = false
            closeAnimTimer.stop()
            _surfaceReveal = settingsOpen ? 1 : 0
            return
        }
        if (settingsOpen) {
            _closeAnimRunning = false
            closeAnimTimer.stop()
            _surfaceReveal = 0
            Qt.callLater(() => {
                if (root.settingsOpen)
                    root._surfaceReveal = 1
            })
        } else {
            _surfaceReveal = 0
            _closeAnimRunning = true
            closeAnimTimer.restart()
        }
    }

    // Keep the native host alive until the bottom-edge exit slide completes.
    Timer {
        id: closeAnimTimer
        interval: SurfaceMotion.duration + 40
        repeat: false
        onTriggered: _closeAnimRunning = false
    }

    // ── Search & iRiS Navigation State (shared contract with settings.qml) ──
    property string overlaySearchText: ""
    property var overlaySearchResults: []
    property int overlaySearchSelectedIndex: 0
    property Item searchFieldItem: null
    property Item homeViewItem: null
    property Item searchViewItem: null

    property bool showingHome: false
    property var _historyStack: []
    property int _historyIndex: -1
    property bool _historyNavigating: false
    readonly property bool canGoBack: root._historyIndex > 0
    readonly property bool canGoForward: root._historyIndex >= 0 && root._historyIndex + 1 < root._historyStack.length

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
        if (root.overlaySearchText.length > 0) {
            root.overlaySearchText = ""
            root.overlaySearchResults = []
            if (root.searchFieldItem)
                root.searchFieldItem.text = ""
        }
        root.showingHome = true
        root._pushHistoryEntry(true, root.overlayCurrentPage)
    }

    function navigateToArea(pageIndex: int): void {
        if (root.overlaySearchText.length > 0) {
            root.overlaySearchText = ""
            root.overlaySearchResults = []
            if (root.searchFieldItem)
                root.searchFieldItem.text = ""
        }
        const safe = SettingsPageRegistry.safePageIndex(pageIndex)
        root.showingHome = false
        if (root.pageHost?.currentItem
                && typeof root.pageHost.currentItem.exitSubView === "function"
                && Boolean(root.pageHost.currentItem.isSubViewActive)
                && root.overlayCurrentPage === safe) {
            root.pageHost.currentItem.exitSubView()
        }
        if (root.overlayCurrentPage !== safe) {
            root.overlayCurrentPage = safe
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
            root.overlayCurrentPage = SettingsPageRegistry.safePageIndex(Number(entry.pageIndex ?? 2))
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
            root.overlayCurrentPage = SettingsPageRegistry.safePageIndex(Number(entry.pageIndex ?? 2))
        }
        root._historyNavigating = false
    }

    function moveOverlaySearchSelection(delta: int): void {
        const count = root.overlaySearchResults?.length ?? 0
        if (count <= 0) {
            root.overlaySearchSelectedIndex = 0
            return
        }
        root.overlaySearchSelectedIndex = Math.max(0, Math.min(count - 1, root.overlaySearchSelectedIndex + delta))
    }

    function acceptOverlaySearchSelection(): void {
        const count = root.overlaySearchResults?.length ?? 0
        if (count > 0) {
            const idx = Math.max(0, Math.min(count - 1, root.overlaySearchSelectedIndex))
            root.openOverlaySearchResult(root.overlaySearchResults[idx])
            return
        }
        const places = root.searchViewItem?.matchingPlaces ?? []
        if (places.length > 0) {
            const p = places[0]
            root.openOverlaySearchResult({
                pageIndex: Number(p.pageIndex),
                section: String(p.section || ""),
                label: String(p.section || p.title || ""),
                isSection: true
            })
        }
    }

    function handleEscape(): bool {
        if (root.overlaySearchText.length > 0) {
            root.openOverlaySearchResult({})
            return true
        }
        if (Boolean(root.homeViewItem?.editingTiles)) {
            root.homeViewItem.editingTiles = false
            return true
        }
        if (!root.showingHome && typeof root.pageHost?.currentItem?.handleEscape === "function"
                && root.pageHost.currentItem.handleEscape()) {
            return true
        }
        if (!root.showingHome && Boolean(root.pageHost?.currentItem?.isSubViewActive)
                && typeof root.pageHost.currentItem.exitSubView === "function") {
            root.pageHost.currentItem.exitSubView()
            return true
        }
        return false
    }

    // Navigation target for search results (no visual spotlight)
    property var searchTargetControl: null

    function getWaffleSettingsPageIndex() {
        for (var i = 0; i < overlayPages.length; i++) {
            var componentPath = String(overlayPages[i]?.component || "");
            if (componentPath.indexOf("modules/settings/WaffleConfig.qml") >= 0) {
                return i;
            }
        }
        return -1;
    }

    function recomputeOverlaySearchResults() {
        var q = String(overlaySearchText || "").toLowerCase().trim();
        if (!q.length) {
            overlaySearchResults = [];
            return;
        }

        var terms = q.split(/\s+/).filter(t => t.length > 0);
        var results = [];

        var isWaffleActive = Config.options?.panelFamily === "waffle";
        var wafflePageIndex = getWaffleSettingsPageIndex();

        const overlaySearchIndex = SettingsPageRegistry.searchIndex();

        // 1. Static index
        for (var i = 0; i < overlaySearchIndex.length; i++) {
            var entry = overlaySearchIndex[i];
            if (!SettingsPageRegistry.isPageApplicable(entry.pageIndex)) continue;
            if (wafflePageIndex >= 0 && entry.pageIndex === wafflePageIndex && !isWaffleActive)
                continue;

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
                    score: score + 500,
                    isSection: true
                });
            }
        }

        // 2. Dynamic widget registry
        if (typeof SettingsSearchRegistry !== "undefined") {
            var widgetResults = SettingsSearchRegistry.buildResults(overlaySearchText);
            widgetResults = widgetResults.filter(r => SettingsPageRegistry.isPageApplicable(r.pageIndex));
            if (!isWaffleActive && wafflePageIndex >= 0) {
                widgetResults = widgetResults.filter(r => r.pageIndex !== wafflePageIndex);
            }
            // Prefer real controls (dynamic registry entries with optionId)
            for (var wr = 0; wr < widgetResults.length; wr++) {
                widgetResults[wr].score = (widgetResults[wr].score || 0) + 2000;
            }
            results = results.concat(widgetResults);
        }

        // 3. Sort and deduplicate
        results.sort((a, b) => b.score - a.score);
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

        overlaySearchResults = unique.slice(0, 50);
        overlaySearchSelectedIndex = 0;
    }

    // ── Search navigation system ──
    property int pendingSpotlightOptionId: -1
    property string pendingSpotlightLabel: ""
    property string pendingSpotlightSection: ""
    property int pendingSpotlightPageIndex: -1
    property bool pendingSpotlightIsSection: false
    property bool pendingSpotlightSectionApplied: false
    property int spotlightRetryCount: 0
    property int spotlightMaxRetries: 15

    function openOverlaySearchResult(entry) {
        // Clear search immediately
        overlaySearchText = "";
        overlaySearchResults = [];
        overlaySearchSelectedIndex = 0;
        if (root.searchFieldItem) root.searchFieldItem.text = "";

        // Reset any previous search target
        resetSearchTarget();

        if (!entry || entry.pageIndex === undefined || entry.pageIndex < 0) return;

        root.showingHome = false;

        // Store spotlight target info
        pendingSpotlightOptionId = (entry.optionId !== undefined) ? entry.optionId : -1;
        pendingSpotlightLabel = entry.label || "";
        pendingSpotlightSection = entry.section || "";
        pendingSpotlightPageIndex = entry.pageIndex;
        pendingSpotlightIsSection = (entry.optionId === undefined) && (entry.isSection === true);

        // Navigate to page (this triggers page load if needed)
        if (pendingSpotlightSection.length > 0 && root.pageHost && typeof root.pageHost._applySectionToPage === "function") {
            root.pageHost._applySectionToPage(entry.pageIndex, pendingSpotlightSection);
            pendingSpotlightSectionApplied = true;
        }
        if (overlayCurrentPage !== entry.pageIndex) {
            overlayCurrentPage = entry.pageIndex;
        } else {
            root._pushHistoryEntry(false, entry.pageIndex);
            IrisState.recordVisit(entry.pageIndex);
        }

        // Always try navigation (with retry for lazy-loaded widgets)
        if (pendingSpotlightOptionId >= 0 || pendingSpotlightLabel.length > 0) {
            spotlightRetryCount = 0;
            spotlightPageLoadTimer.restart();
        }
    }

    // Timer to wait for page load and widget registration
    Timer {
        id: spotlightPageLoadTimer
        interval: 150
        onTriggered: root.trySpotlight()
    }

    function trySpotlight() {
        if (root.showingHome || pendingSpotlightPageIndex < 0 || root.overlayCurrentPage !== pendingSpotlightPageIndex) {
            resetSearchTarget();
            return;
        }
        const pageItem = root.pageHost?.currentItem
        if (!pageItem || root.pageHost.currentIndex !== pendingSpotlightPageIndex) {
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
            // Remove page name prefix from sectionGroup if present (supports both delimiters)
            // e.g., "Themes · Colors" or "Themes › Colors" -> "Colors"
            var sectionParts = sectionLower.split(/[·›]/).map(p => p.trim()).filter(p => p.length > 0);
            var sectionOnly = sectionParts.length > 1 ? sectionParts[sectionParts.length - 1] : sectionLower;

            for (var i = 0; i < SettingsSearchRegistry.entries.length; i++) {
                var e = SettingsSearchRegistry.entries[i];
                if (e.pageIndex !== pendingSpotlightPageIndex)
                    continue;

                var eLabelLower = (e.label || "").toLowerCase();
                var eSectionLower = (e.section || "").toLowerCase();
                var eSectionParts = eSectionLower.split(/[·›]/).map(p => p.trim()).filter(p => p.length > 0);
                var eSectionOnly = eSectionParts.length > 1 ? eSectionParts[eSectionParts.length - 1] : eSectionLower;

                if (pendingSpotlightIsSection) {
                    // Prefer matching the section title control.
                    // Registry section titles commonly appear in e.label (SettingsCardSection/CollapsibleSection).
                    if (eLabelLower === labelLower || eLabelLower === sectionOnly) {
                        control = e.control;
                        break;
                    }
                    if (eSectionOnly === sectionOnly || eSectionOnly === labelLower) {
                        control = e.control;
                        break;
                    }
                } else {
                    // Exact label match
                    if (eLabelLower === labelLower) {
                        control = e.control;
                        break;
                    }

                    // Section title match (for SettingsCardSection / CollapsibleSection)
                    if (eSectionOnly === sectionOnly || eSectionOnly === labelLower) {
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
        var posInContent = control.mapToItem(flick.contentItem, 0, 0);
        var controlYInContent = posInContent.y;

        // Calculate target scroll position to center the control in viewport
        var viewportHeight = flick.height;
        var controlHeight = control.height;
        var targetScrollY = controlYInContent - (viewportHeight / 2) + (controlHeight / 2);

        // Clamp to valid scroll range (non-interactive pages must remain at contentY = 0)
        var maxScroll = flick.interactive ? Math.max(0, flick.contentHeight - flick.height) : 0;
        targetScrollY = Math.max(0, Math.min(targetScrollY, maxScroll));

        // Scroll to position - set directly to bypass animation
        flick.contentY = targetScrollY;
        searchTargetControl = control;
        pendingSpotlightOptionId = -1;
        pendingSpotlightLabel = "";
        pendingSpotlightSection = "";
        pendingSpotlightPageIndex = -1;
        pendingSpotlightIsSection = false;
        pendingSpotlightSectionApplied = false;
    }

    function resetSearchTarget() {
        spotlightPageLoadTimer.stop();
        searchTargetControl = null;
        pendingSpotlightOptionId = -1;
        pendingSpotlightLabel = "";
        pendingSpotlightSection = "";
        pendingSpotlightPageIndex = -1;
        pendingSpotlightIsSection = false;
        pendingSpotlightSectionApplied = false;
    }

    Connections {
        target: SettingsPageRegistry
        function onHomeRequested() {
            if (!root.settingsOpen) return
            root.showHomeView()
        }
        function onNavigateRequested(pageIndex, section) {
            if (!root.settingsOpen) return
            root.showingHome = false
            if (section.length > 0)
                root.openOverlaySearchResult({ pageIndex: pageIndex,
                    section: section, label: section, isSection: true })
            else
                root.navigateToArea(pageIndex)
        }
    }

    function consumeSettingsDeepLink(): bool {
        if (!root.settingsOpen)
            return false
        const requestedPage = GlobalStates.settingsOverlayRequestedPage ?? -1
        const requestedSection = String(
            GlobalStates.settingsOverlayRequestedSection ?? "").trim()
        // Section and page are written as two property changes. While the
        // overlay is already open, the section signal can arrive first; keep
        // it pending until the page target is available so the deep link is
        // consumed atomically.
        if (requestedPage < 0)
            return false

        // A deep link can arrive before Persistent finishes loading. Preserve
        // it across navigation initialization; the persisted page must not
        // silently evict the requested page (and its focused editor).
        if (!root._navigationInitialized)
            root._initialDeepLinkPage = requestedPage
        GlobalStates.settingsOverlayRequestedPage = -1
        GlobalStates.settingsOverlayRequestedSection = ""
        if (!SettingsPageRegistry.isPageApplicable(requestedPage)) {
            // Discard any spotlight targeting a retired page, including 35.
            root.overlayCurrentPage = SettingsPageRegistry.safePageIndex(requestedPage)
            return true
        }

        if (requestedPage >= 0 && requestedSection.length > 0) {
            root.openOverlaySearchResult({
                pageIndex: requestedPage,
                pageName: "",
                section: requestedSection,
                label: requestedSection,
                isSection: true
            })
            return true
        }
        if (requestedPage >= 0) {
            root.overlayCurrentPage = requestedPage
            return true
        }
        return false
    }

    function findParentFlickable(item) {
        var p = item ? item.parent : null;
        while (p) {
            if (p.hasOwnProperty("contentY") && p.hasOwnProperty("contentHeight") && p.hasOwnProperty("contentItem")) {
                return p;
            }
            p = p.parent;
        }
        return null;
    }

    property string _lastFamily: Config.options?.panelFamily ?? "ii"

    Connections {
        target: Config.options ?? null
        function onPanelFamilyChanged() {
            const nextFamily = Config.options?.panelFamily ?? "ii";
            if (nextFamily === root._lastFamily)
                return;
            root._lastFamily = nextFamily;
            root.overlayCurrentPage = 0;
        }
    }

    Connections {
        target: GlobalStates
        function onSettingsOverlayOpenChanged() {
            if (GlobalStates.settingsOverlayOpen)
                root.consumeSettingsDeepLink()
        }
    }

    function applyDevDestination(): void {
        if (!DevNavigation.currentDestination.startsWith("settings/")) return
        const key = DevNavigation.currentDestination.substring("settings/".length)
        const index = root.overlayPages.findIndex(page => page.key === key)
        if (index >= 0) root.overlayCurrentPage = index
    }

    Connections {
        target: DevNavigation
        function onCurrentDestinationChanged(): void { root.applyDevDestination() }
    }

    // settingsNav is owned by shell.qml — see the comment there.
    Connections {
        target: GlobalStates
        function onSettingsOverlayRequestedPageChanged() {
            root.consumeSettingsDeepLink()
        }
        function onSettingsOverlayRequestedSectionChanged() {
            root.consumeSettingsDeepLink()
        }
    }

    Loader {
        id: panelLoader
        active: root._panelLoaded
        asynchronous: Quickshell.env("QT_QUICK_BACKEND") !== "software"
            && status !== Loader.Ready
            && Boolean(root.embeddedHost)

        sourceComponent: Item {
            id: settingsPanel
            parent: root.embeddedHost ?? nativeHost.item?.contentItem ?? null
            anchors.fill: parent
            visible: root.settingsOpen || root._closeAnimRunning || Boolean(root.embeddedHost?.participant?.visualResident)
            readonly property var screen: root.embeddedHost?.QsWindow?.window?.screen ?? nativeHost.item?.screen ?? null
            Loader {
                id: nativeHost
                active: !root.embeddedHost
                source: active ? "SettingsOverlayNativeHost.qml" : ""
                onLoaded: item.controller = root
            }

            // Blurred backdrop — see SettingsFocus for the contract. Both overlay
            // layouts read the same setting, so the option in Settings UI means
            // the same thing whichever chrome is selected.
            readonly property int backdropBlur:
                Config.options?.settingsUi?.overlayAppearance?.backdropBlur ?? 0

            Loader {
                anchors.fill: parent
                z: -1
                active: !root.embeddedHost && settingsPanel.backdropBlur > 0 && Appearance.effectsEnabled
                visible: active && (GlobalStates.settingsOverlayOpen ?? false)

                sourceComponent: GlassBackground {
                    anchors.fill: parent
                    radius: 0
                    forceBackdrop: true
                    blurStrength: settingsPanel.backdropBlur / 100
                    screenX: 0
                    screenY: 0
                    screenWidth: settingsPanel.width
                    screenHeight: settingsPanel.height
                    fallbackColor: "transparent"
                    auroraTransparency: 0.35

                    opacity: (GlobalStates.settingsOverlayOpen ?? false) ? 1 : 0
                }
            }

            // Global Escape key shortcut for standalone/native host mode
            Shortcut {
                sequences: ["Escape"]
                context: Qt.WindowShortcut
                enabled: !root.embeddedHost && root.settingsOpen
                onActivated: {
                    if (!root.handleEscape()) {
                        GlobalStates.settingsOverlayOpen = false;
                    }
                }
            }

            Shortcut {
                sequences: ["Ctrl+F"]
                enabled: root.settingsOpen
                context: Qt.WindowShortcut
                onActivated: {
                    if (root.searchFieldItem)
                        root.searchFieldItem.forceActiveFocus()
                }
            }

            // Focus grab for Hyprland
            CompositorFocusGrab {
                id: grab
                windows: nativeHost.item ? [nativeHost.item] : []
                active: false
                onCleared: () => {
                    if (!active && !GlobalStates.settingsNativeDialogOpen)
                        GlobalStates.settingsOverlayOpen = false
                }
            }

            Connections {
                target: GlobalStates
                function onSettingsOverlayOpenChanged() {
                    grabTimer.restart()
                }
                function onSettingsNativeDialogOpenChanged() {
                    grabTimer.restart()
                }
            }

            Timer {
                id: grabTimer
                interval: 100
                onTriggered: grab.active = !root.embeddedHost && (GlobalStates.settingsOverlayOpen ?? false)
                    && !GlobalStates.settingsNativeDialogOpen
            }

            // Dim only the workspace, never the physical Screen Edge or the
            // translucent connected body. The card cutout follows its slide.
            SettingsWorkspaceScrim {
                id: scrimBg
                anchors.fill: parent
                outputName: String(settingsPanel.screen?.name ?? "")
                cardRect: Qt.rect(settingsCard.x, settingsCard.y,
                    settingsCard.width, settingsCard.height)
                cardRadius: settingsCard.radius
                dim: !root.embeddedHost && (GlobalStates.settingsOverlayOpen ?? false)
                    ? (Config.options?.settingsUi?.overlayAppearance?.scrimDim ?? 35) / 100 : 0
            }

            // Click-outside-to-close hit area — a sibling of scrimBg, not a child.
            // It used to live inside scrimBg, whose `visible: opacity > 0` goes
            // false whenever scrimDim is set to 0 (fully transparent scrim):
            // QtQuick excludes invisible items from hit-testing, so a MouseArea
            // inside an invisible parent silently stops receiving clicks. Scrim
            // dim and click-outside-to-close are independent concerns and must
            // not share one visibility flag.
            MouseArea {
                anchors.fill: parent
                visible: GlobalStates.settingsOverlayOpen ?? false
                enabled: !GlobalStates.settingsNativeDialogOpen && !PolkitService.active
                onClicked: GlobalStates.settingsOverlayOpen = false
            }

            // ── Floating settings card (no separate drop shadow — the card
            //    sits on the scrim backdrop; the panel border provides depth) ──
// ── Bottom-connected settings popup ──
            ConnectedSurfaceAbyssEdgeSurface {
                id: settingsAbyssSurface
                visible: !root.embeddedHost && Config.options?.panelFamily !== "waffle"
                z: 1
                anchors.fill: parent
                edge: "bottom"
                ownerThickness: root._screenEdgeThickness
                outputRect: Qt.rect(0, 0, settingsPanel.width, settingsPanel.height)
                bodyRect: Qt.rect(settingsCard.x, settingsCard.y,
                    settingsCard.width, settingsCard.height)
                bodyRadius: settingsCard.radius
                fillColor: settingsCard.surfaceFillColor
                progress: root.settingsOpen || root._closeAnimRunning ? 1 : 0
                // Connected Settings is another Screen Edge-owned surface:
                // use the same physical elevation controls as Popups/Sidebars.
                shadowEnabled: Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
                shadowExtent: Math.max(0, Math.min(32,
                    Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
                shadowColor: Qt.alpha(Appearance.m3colors.m3shadow,
                    Math.max(0, Math.min(1.0,
                        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70))))
            }

            Rectangle {
                id: settingsCard
                parent: root.embeddedHost ?? settingsPanel

                readonly property real waffleBarReserve: (!root.embeddedHost && Config.options?.panelFamily === "waffle"
                    && (GlobalStates.barOpen ?? true)) ? 48 : 0
                readonly property real waffleWorkTop: (settingsCard.waffleBarReserve > 0
                    && !(Config.options?.waffles?.bar?.bottom ?? true)) ? settingsCard.waffleBarReserve : 0
                readonly property real waffleWorkHeight: Math.max(0, settingsPanel.height - settingsCard.waffleBarReserve)

                readonly property real maxCardWidth: root.embeddedHost
                    ? root.embeddedHost.width
                    : (Config.options?.panelFamily === "waffle"
                        ? Math.round(Math.min(
                            1600,
                            Math.max(900, settingsPanel.width * 0.90),
                            Math.max(0, settingsPanel.width - 48)))
                        : Math.round(Math.min(
                            Math.max(480, settingsPanel.width - 48),
                            settingsPanel.width * (Config.options?.dashboard?.widthRatio ?? 0.72) + 40)))
                readonly property real _panelAvailHeight: Config.options?.panelFamily === "waffle"
                    ? settingsCard.waffleWorkHeight
                    : settingsPanel.height
                readonly property real maxCardHeight: root.embeddedHost
                    ? root.embeddedHost.height
                    : (Config.options?.panelFamily === "waffle"
                        ? Math.round(Math.max(560, Math.min(
                            Math.round(1280 * Math.max(1, Appearance.fontSizeScale)),
                            Math.round(settingsCard._panelAvailHeight * 0.92),
                            Math.max(0, settingsCard._panelAvailHeight - 40))))
                        : Math.round(Math.min(
                            Math.max(360, settingsCard._panelAvailHeight - 40),
                            settingsCard._panelAvailHeight * (Config.options?.dashboard?.heightRatio ?? 0.72) + 40)))
                // Structural connected chrome: the same Material surface token as
                // Screen Edge. Preserve colLayer0's global transparency as-is.
                readonly property color surfaceFillColor: Appearance.colors.colLayer0

                anchors.horizontalCenter: parent.horizontalCenter
                y: root.embeddedHost ? 0 : (Config.options?.panelFamily === "waffle"
                    ? settingsCard.waffleWorkTop + Math.round((settingsCard.waffleWorkHeight - height) / 2)
                    : settingsPanel.height - root._screenEdgeThickness - height
                        + (1 - root._surfaceReveal) * height)
                width: maxCardWidth
                height: maxCardHeight
                radius: SettingsMaterialPreset.waffle ? 8 : Appearance.rounding.windowRounding
                bottomLeftRadius: Config.options?.panelFamily === "waffle" ? radius : 0
                bottomRightRadius: Config.options?.panelFamily === "waffle" ? radius : 0
                color: SettingsMaterialPreset.waffle ? SettingsMaterialPreset.windowColor : "transparent"
                clip: true

                border.width: (!root.embeddedHost && SettingsMaterialPreset.waffle) ? 1 : 0
                border.color: (!root.embeddedHost && SettingsMaterialPreset.waffle)
                    ? SettingsMaterialPreset.cardBorderColor : "transparent"
                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }

                // Scale + fade. Exit uses elementMoveExit (snappy ~200ms accel) so
                // the close feels immediate and matches the window-mode settings;
                // enter reuses the same Behavior (200ms is smooth enough on open).
                // Instant show/hide — matches the window-mode settings UI.
                // No scale/opacity fade (the fade felt heavy and the scrim
                // backdrop already carries the transition).
                opacity: 1
                visible: root.settingsOpen || root._closeAnimRunning || Boolean(root.embeddedHost?.participant?.visualResident)
                z: 2

                // Material-only v1.0: retired shell-wide style backdrops are not
                // instantiated in the active Settings surface.

                // Prevent clicks from closing
                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => mouse.accepted = true
                }

                // ── Main content: Redesigned Split-Pane Studio Settings ──
                ColumnLayout {
                    id: mainLayout
                    anchors {
                        fill: parent
                        margins: SettingsMaterialPreset.waffle ? 0 : 12
                    }
                    z: 2
                    spacing: 0

                    WaffleSettings.WWin11SettingsTitleBar {
                        id: waffleOverlayTitleBar
                        visible: SettingsMaterialPreset.waffle
                        Layout.fillWidth: true
                        embedded: Boolean(root.embeddedHost)
                        isOverlay: true
                        canGoBack: root.canGoBack || root.overlaySearchText.length > 0
                        onBackRequested: {
                            if (root.overlaySearchText.length > 0)
                                root.openOverlaySearchResult({})
                            else
                                root.goBack()
                        }
                        onSwitchModeRequested: {
                            Config.setNestedValue("waffles.settings.windowMode", true)
                            Config.setNestedValue("settingsUi.overlayMode", false)
                            GlobalStates.settingsOverlayOpen = false
                            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings-window"])
                        }
                        onLockRequested: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "lock", "activate"])
                        onCloseRequested: GlobalStates.settingsOverlayOpen = false
                    }

                    // ── Split-pane Navigation Rail + Workspace ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: SettingsMaterialPreset.waffle ? 14 : 0
                        Layout.bottomMargin: SettingsMaterialPreset.waffle ? 10 : 0
                        spacing: SettingsMaterialPreset.waffle ? 8 : 12

                        // ── Left Navigation Sidebar ──
                        Rectangle {
                            id: navColumn
                            readonly property bool compact: SettingsMaterialPreset.useCompactNav(settingsCard.width, false)
                            objectName: "settingsOverlayNavColumn"
                            Layout.fillHeight: true
                            Layout.preferredWidth: SettingsMaterialPreset.waffle
                                ? Math.min(SettingsMaterialPreset.waffleRailWidth, Math.max(216, Math.round(settingsCard.width * 0.24)))
                                : (compact ? SettingsMaterialPreset.compactNavWidth : SettingsMaterialPreset.navSidebarWidth)
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

                            Binding {
                                target: root
                                property: "searchFieldItem"
                                value: SettingsMaterialPreset.waffle
                                    ? waffleOverlayRailHeader.searchField
                                    : (navColumn.compact ? compactOverlaySearchField : overlaySearchField)
                            }

                            WaffleSettings.WWin11SettingsRailHeader {
                                id: waffleOverlayRailHeader
                                visible: SettingsMaterialPreset.waffle
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    margins: 2
                                }
                                searchQuery: root.overlaySearchText
                                resultCount: root.overlaySearchResults.length
                                onAccountClicked: root.navigateToArea(1)
                                onSearchTextEdited: query => {
                                    root.overlaySearchText = query
                                    root.recomputeOverlaySearchResults()
                                }
                                onFocusResultsRequested: overlayLiveSearch.focusResults()
                                onAcceptCurrentResultRequested: overlayLiveSearch.activateCurrent()
                                onClearSearchRequested: root.openOverlaySearchResult({})
                                onEscapeEmptySearchRequested: {
                                    if (!root.handleEscape())
                                        GlobalStates.settingsOverlayOpen = false
                                }
                            }

                            // ── Sidebar Header: Identity + Integrated Search (Material / Abyss) ──
                            ColumnLayout {
                                id: sidebarTopHeader
                                visible: !SettingsMaterialPreset.waffle
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    topMargin: 12
                                    leftMargin: navColumn.compact ? 8 : 12
                                    rightMargin: navColumn.compact ? 8 : 12
                                }
                                spacing: 10

                                // Identity Row
                                RippleButton {
                                    id: overlayIdentityButton
                                    objectName: "settingsIdentityAboutButton"
                                    readonly property bool isAboutSelected: !root.showingHome && root.overlayCurrentPage === 40
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
                                            root.overlayCurrentPage = 40
                                            if (root.overlaySearchText.length > 0)
                                                root.openOverlaySearchResult({})
                                        }
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("About Alis & system info")
                                    }

                                    contentItem: Item {
                                        implicitWidth: overlayIdentityRow.implicitWidth
                                        implicitHeight: overlayIdentityRow.implicitHeight

                                        RowLayout {
                                            id: overlayIdentityRow
                                            anchors {
                                                fill: parent
                                                leftMargin: navColumn.compact ? 0 : 6
                                                rightMargin: navColumn.compact ? 0 : 6
                                            }
                                            spacing: 10

                                            Item {
                                                Layout.alignment: navColumn.compact ? Qt.AlignHCenter : Qt.AlignVCenter
                                                Layout.fillWidth: navColumn.compact
                                                implicitWidth: 34
                                                implicitHeight: 34

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 34
                                                    height: 34
                                                    radius: width / 2
                                                    color: SettingsMaterialPreset.cardColor
                                                    border.width: 1.5
                                                    border.color: overlayIdentityButton.isAboutSelected
                                                        ? Appearance.colors.colPrimary
                                                        : SettingsMaterialPreset.accentBorder
                                                }

                                                Rectangle {
                                                    id: overlayAvatarMask
                                                    anchors.centerIn: parent
                                                    width: 30
                                                    height: 30
                                                    radius: width / 2
                                                    visible: false
                                                }

                                                Image {
                                                    id: overlayAvatarImage
                                                    anchors.centerIn: parent
                                                    width: 30
                                                    height: 30
                                                    source: Directories.userAvatarSourcePrimary
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    cache: true
                                                    smooth: true
                                                    mipmap: true
                                                    visible: status === Image.Ready
                                                    layer.enabled: visible
                                                    layer.effect: GE.OpacityMask {
                                                        maskSource: overlayAvatarMask
                                                    }
                                                    onStatusChanged: {
                                                        if (status === Image.Error) {
                                                            const nextSource = Directories.nextAvatarSource(source)
                                                            if (nextSource.length > 0 && nextSource !== source)
                                                                source = nextSource
                                                        }
                                                    }
                                                }

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: overlayAvatarImage.status !== Image.Ready
                                                    text: "person"
                                                    iconSize: 18
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }

                                            ColumnLayout {
                                                visible: !navColumn.compact
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: Translation.tr("Settings")
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                    font {
                                                        family: Appearance.font.family.title
                                                        pixelSize: Appearance.font.pixelSize.large
                                                        weight: Font.DemiBold
                                                    }
                                                    color: overlayIdentityButton.isAboutSelected
                                                        ? SettingsMaterialPreset.navSelectedTextColor
                                                        : Appearance.colors.colOnLayer0
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: SystemInfo.displayName || SystemInfo.username
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: overlayIdentityButton.isAboutSelected
                                                        ? SettingsMaterialPreset.navSelectedTextColor
                                                        : SettingsMaterialPreset.secondaryTextColor
                                                    opacity: overlayIdentityButton.isAboutSelected ? 0.82 : 1.0
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }
                                            }
                                        }
                                    }
                                }

                                // Integrated Search Pill (expanded sidebar)
                                Rectangle {
                                    id: overlaySearchContainer
                                    visible: !navColumn.compact
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.round(34 * Appearance.fontSizeScale)
                                    radius: SettingsMaterialPreset.searchRadius
                                    color: overlaySearchField.activeFocus
                                        ? SettingsMaterialPreset.cardColor
                                        : SettingsMaterialPreset.controlSurface
                                    border.width: overlaySearchField.activeFocus ? 1.5 : 1
                                    border.color: overlaySearchField.activeFocus
                                        ? Appearance.colors.colPrimary
                                        : SettingsMaterialPreset.controlBorderColor

                                    Behavior on color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                    }
                                    Behavior on border.color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: root.overlaySearchResults.length > 0 ? "manage_search" : "search"
                                            iconSize: 16
                                            color: overlaySearchField.activeFocus
                                                ? Appearance.colors.colPrimary
                                                : SettingsMaterialPreset.secondaryTextColor
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            StyledText {
                                                anchors.fill: parent
                                                verticalAlignment: Text.AlignVCenter
                                                visible: overlaySearchField.text.length === 0 && !overlaySearchField.activeFocus
                                                text: Translation.tr("Search...")
                                                font.family: SettingsMaterialPreset.fontFamily
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: SettingsMaterialPreset.secondaryTextColor
                                                elide: Text.ElideRight
                                            }

                                            TextInput {
                                                id: overlaySearchField
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
                                                    visible: overlaySearchField.cursorVisible
                                                    width: 1.8
                                                    color: Appearance.colors.colPrimary
                                                }

                                                Connections {
                                                    target: root
                                                    function onOverlaySearchTextChanged() {
                                                        if (overlaySearchField.text !== root.overlaySearchText)
                                                            overlaySearchField.text = root.overlaySearchText
                                                    }
                                                }

                                                onTextChanged: {
                                                    if (root.overlaySearchText !== text) {
                                                        root.overlaySearchText = text
                                                        root.recomputeOverlaySearchResults()
                                                    }
                                                }

                                                Keys.onPressed: event => {
                                                    if (event.key === Qt.Key_Down && root.overlaySearchResults.length > 0) {
                                                        overlayLiveSearch.focusResults()
                                                        event.accepted = true
                                                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                                            && root.overlaySearchResults.length > 0) {
                                                        overlayLiveSearch.activateCurrent()
                                                        event.accepted = true
                                                    } else if (event.key === Qt.Key_Escape) {
                                                        if (root.overlaySearchText.length > 0) {
                                                            root.openOverlaySearchResult({})
                                                        } else {
                                                            overlaySearchField.focus = false
                                                            if (!root.handleEscape())
                                                                GlobalStates.settingsOverlayOpen = false
                                                        }
                                                        event.accepted = true
                                                    }
                                                }
                                            }
                                        }

                                        // Subtle Ctrl+F keycap hint when idle
                                        Rectangle {
                                            visible: root.overlaySearchText.length === 0 && !overlaySearchField.activeFocus
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitHeight: 19
                                            implicitWidth: searchHintKey.implicitWidth + 10
                                            radius: 5
                                            color: SettingsMaterialPreset.cardColor
                                            border.width: 1
                                            border.color: SettingsMaterialPreset.controlBorderColor

                                            StyledText {
                                                id: searchHintKey
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: "^F"
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Medium
                                                color: SettingsMaterialPreset.secondaryTextColor
                                            }
                                        }

                                        // Live clear button (centered icon)
                                        RippleButton {
                                            visible: root.overlaySearchText.length > 0
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 22
                                            Layout.alignment: Qt.AlignVCenter
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: "transparent"
                                            colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                                            onClicked: {
                                                root.openOverlaySearchResult({})
                                                overlaySearchField.forceActiveFocus()
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

                            // ── Canonical Category Navigation List ──
                            Flickable {
                                id: navFlickable
                                anchors {
                                    top: SettingsMaterialPreset.waffle ? waffleOverlayRailHeader.bottom : sidebarTopHeader.bottom
                                    left: parent.left
                                    right: parent.right
                                    bottom: SettingsMaterialPreset.waffle ? parent.bottom : overlayNavActions.top
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
                                                idx => root.overlayPages[idx] && SettingsPageRegistry.isPageApplicable(idx)).map(
                                                idx => Object.assign({}, root.overlayPages[idx], { realIndex: idx }))
                                            readonly property bool hasActivePage: navHeadingGroup.groupPages.some(
                                                item => item.realIndex === root.overlayCurrentPage)
                                            objectName: navHeadingGroup.groupPages.length > 0
                                                ? ("settingsNav_" + (navHeadingGroup.groupPages[0].key || ""))
                                                : ("settingsNavGroup_" + index)
                                            visible: navHeadingGroup.groupPages.length > 0
                                            Layout.fillWidth: true
                                            implicitHeight: SettingsMaterialPreset.waffle
                                                ? Math.round(38 * Appearance.fontSizeScale)
                                                : Math.round(38 * Appearance.fontSizeScale)
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
                                                    if (overlayPagesHost.currentItem && typeof overlayPagesHost.currentItem.exitSubView === "function" && overlayPagesHost.currentItem.isSubViewActive)
                                                        overlayPagesHost.currentItem.exitSubView()
                                                    if (root.overlayCurrentPage !== hubEntry.realIndex)
                                                        root.activateNavigation(hubEntry)
                                                    if (root.overlaySearchText.length > 0)
                                                        root.openOverlaySearchResult({})
                                                }
                                            }

                                            // Left active accent indicator pill
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
                                                extraVisibleCondition: navColumn.compact
                                                text: navHeadingGroup.headingTitle
                                            }

                                            contentItem: Item {
                                                implicitWidth: navItemContentRow.implicitWidth
                                                implicitHeight: navItemContentRow.implicitHeight

                                                // Compact mode: icon dead-center inside button
                                                MaterialSymbol {
                                                    visible: navColumn.compact
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

                                                // Expanded mode: clean aligned icon + label
                                                RowLayout {
                                                    id: navItemContentRow
                                                    visible: !navColumn.compact
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

                            // ── Minimal Clean Footer (centered Window mode toggle; Edit Layout & Edit Navigation removed) ──
                            ColumnLayout {
                                id: overlayNavActions
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

                                RippleButton {
                                    id: overlayWindowToggle
                                    objectName: "overlayWindowModeButton"
                                    Accessible.name: Translation.tr("Window")
                                    Layout.fillWidth: true
                                    implicitHeight: Math.round(34 * Appearance.fontSizeScale)
                                    buttonRadius: 10
                                    colBackground: SettingsMaterialPreset.controlSurface
                                    colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover

                                    onClicked: {
                                        Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings-window"])
                                        Config.setNestedValue("settingsUi.overlayMode", false)
                                        GlobalStates.settingsOverlayOpen = false
                                    }

                                    contentItem: Item {
                                        implicitWidth: overlayWindowRow.implicitWidth
                                        implicitHeight: overlayWindowRow.implicitHeight

                                        Row {
                                            id: overlayWindowRow
                                            anchors.centerIn: parent
                                            spacing: navColumn.compact ? 0 : 7

                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: "open_in_new"
                                                iconSize: 16
                                                color: SettingsMaterialPreset.secondaryTextColor
                                            }

                                            StyledText {
                                                visible: !navColumn.compact
                                                anchors.verticalCenter: parent.verticalCenter
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: Translation.tr("Window")
                                                font.family: SettingsMaterialPreset.fontFamily
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Medium
                                                color: SettingsMaterialPreset.textColor
                                            }
                                        }
                                    }

                                    StyledToolTip {
                                        position: "top"
                                        text: Translation.tr("Switch to window mode")
                                    }
                                }
                            }
                        }

                        // ── Right Workspace Area ──
                        Rectangle {
                            id: overlayContentContainer
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.normal
                            // settingsAbyssSurface owns the structural colLayer0 body; keep inner content transparent.
                            color: "transparent"
                            border.width: 0
                            border.color: "transparent"
                            clip: true

                            // ── Sticky Workspace Header ──
                            Item {
                                id: overlayPageHeader
                                anchors { top: parent.top; left: parent.left; right: parent.right }
                                readonly property var meta: root.overlayPages[root.overlayCurrentPage] ?? {}
                                readonly property var activeCategory: SettingsPageRegistry.defaultCategories.find(
                                    cat => (cat?.pages ?? []).includes(root.overlayCurrentPage)) ?? null
                                readonly property var groupPages: (activeCategory?.pages ?? []).filter(
                                    idx => root.overlayPages[idx] && SettingsPageRegistry.isPageApplicable(idx)).map(
                                    idx => Object.assign({}, root.overlayPages[idx], { realIndex: idx }))
                                readonly property Item activePageItem: overlayPagesHost.currentItem
                                readonly property bool isOnInPageSubView: Boolean(activePageItem?.isSubViewActive)
                                readonly property bool isDrilledDown: isOnInPageSubView
                                readonly property string backLabel: activeCategory?.label || meta.name || Translation.tr("Back")
                                readonly property string activeTitle: isOnInPageSubView && String(activePageItem?.activeSubViewTitle || "").length > 0
                                    ? String(activePageItem.activeSubViewTitle)
                                    : String(activeCategory?.label || meta.name || "")
                                readonly property string activeIcon: String(meta.icon || "settings")

                                function navigateBack(): void {
                                    if (overlayPageHeader.isOnInPageSubView && overlayPageHeader.activePageItem
                                            && typeof overlayPageHeader.activePageItem.exitSubView === "function") {
                                        overlayPageHeader.activePageItem.exitSubView()
                                    }
                                }

                                height: root.overlaySearchText.trim().length > 0
                                    ? (navColumn.compact && !SettingsMaterialPreset.waffle ? Math.round(50 * Appearance.fontSizeScale) : 0)
                                    : (SettingsMaterialPreset.waffle ? 56 : Math.max(Math.round(54 * Appearance.fontSizeScale), overlayPageHeaderRow.implicitHeight + 10))
                                visible: height > 0

                                WaffleSettings.WWin11SettingsBreadcrumb {
                                    id: waffleOverlayBreadcrumb
                                    visible: SettingsMaterialPreset.waffle
                                    anchors.fill: parent
                                    categoryTitle: overlayPageHeader.activeTitle
                                    hasSubTabs: Boolean(overlayPageHeader.activePageItem?._subTabItems?.length > 1)
                                    subPageTitle: String(overlayPageHeader.activePageItem?.activeSubTabLabel ?? "")
                                    contentLeftMargin: Number(overlayPageHeader.activePageItem?._horizontalMargin ?? 28)
                                    onCategoryRootClicked: {
                                        const items = overlayPageHeader.activePageItem?._subTabItems ?? []
                                        if (items.length > 0 && typeof overlayPageHeader.activePageItem?.activateSubTabItem === "function")
                                            overlayPageHeader.activePageItem.activateSubTabItem(items[0])
                                    }
                                }

                                RowLayout {
                                    id: overlayPageHeaderRow
                                    visible: !SettingsMaterialPreset.waffle
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    anchors.topMargin: 4
                                    anchors.bottomMargin: 6
                                    spacing: 11

                                    RippleButton {
                                        id: overlayBackBtn
                                        objectName: "settingsOverlayHeaderBackButton"
                                        visible: overlayPageHeader.isDrilledDown && root.overlaySearchText.trim().length === 0
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitHeight: 30
                                        implicitWidth: overlayBackRow.implicitWidth + 18
                                        buttonRadius: height / 2
                                        colBackground: SettingsMaterialPreset.pillSelectedColor
                                        colBackgroundHover: SettingsMaterialPreset.pillSelectedHoverColor
                                        onClicked: overlayPageHeader.navigateBack()
                                        StyledToolTip { text: Translation.tr("Go back") }

                                        contentItem: Item {
                                            implicitWidth: overlayBackRow.implicitWidth
                                            implicitHeight: overlayBackRow.implicitHeight
                                            Row {
                                                id: overlayBackRow
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
                                                    text: overlayPageHeader.backLabel
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: Font.DemiBold
                                                    color: SettingsMaterialPreset.pillSelectedTextColor
                                                }
                                            }
                                        }
                                    }

                                    // Refined rounded-square category icon badge
                                    Rectangle {
                                        visible: root.overlaySearchText.trim().length === 0
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
                                            text: overlayPageHeader.activeIcon
                                            iconSize: 18
                                            color: Appearance.colors.colPrimary
                                        }
                                    }

                                    ColumnLayout {
                                        visible: root.overlaySearchText.trim().length === 0
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: overlayPageHeader.activeTitle
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
                                            text: String(overlayPageHeader.meta.desc ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: SettingsMaterialPreset.secondaryTextColor
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }

                                    // Inline search bar when sidebar is in compact icon-rail mode
                                    Rectangle {
                                        visible: navColumn.compact
                                        Layout.fillWidth: root.overlaySearchText.trim().length > 0
                                        Layout.preferredWidth: root.overlaySearchText.trim().length > 0 ? 320 : 210
                                        Layout.maximumWidth: root.overlaySearchText.trim().length > 0 ? 480 : 240
                                        Layout.preferredHeight: Math.round(34 * Appearance.fontSizeScale)
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: SettingsMaterialPreset.searchRadius
                                        color: compactOverlaySearchField.activeFocus
                                            ? SettingsMaterialPreset.cardColor
                                            : SettingsMaterialPreset.controlSurface
                                        border.width: compactOverlaySearchField.activeFocus ? 1.5 : 1
                                        border.color: compactOverlaySearchField.activeFocus
                                            ? Appearance.colors.colPrimary
                                            : SettingsMaterialPreset.controlBorderColor

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: root.overlaySearchResults.length > 0 ? "manage_search" : "search"
                                                iconSize: 16
                                                color: compactOverlaySearchField.activeFocus
                                                    ? Appearance.colors.colPrimary
                                                    : SettingsMaterialPreset.secondaryTextColor
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                StyledText {
                                                    anchors.fill: parent
                                                    verticalAlignment: Text.AlignVCenter
                                                    visible: compactOverlaySearchField.text.length === 0 && !compactOverlaySearchField.activeFocus
                                                    text: Translation.tr("Search settings...")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: SettingsMaterialPreset.secondaryTextColor
                                                    elide: Text.ElideRight
                                                }

                                                TextInput {
                                                    id: compactOverlaySearchField
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
                                                        visible: compactOverlaySearchField.cursorVisible
                                                        width: 1.8
                                                        color: Appearance.colors.colPrimary
                                                    }

                                                    Connections {
                                                        target: root
                                                        function onOverlaySearchTextChanged() {
                                                            if (compactOverlaySearchField.text !== root.overlaySearchText)
                                                                compactOverlaySearchField.text = root.overlaySearchText
                                                        }
                                                    }

                                                    onTextChanged: {
                                                        if (root.overlaySearchText !== text) {
                                                            root.overlaySearchText = text
                                                            root.recomputeOverlaySearchResults()
                                                        }
                                                    }

                                                    Keys.onPressed: event => {
                                                        if (event.key === Qt.Key_Down && root.overlaySearchResults.length > 0) {
                                                            overlayLiveSearch.focusResults()
                                                            event.accepted = true
                                                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                                                && root.overlaySearchResults.length > 0) {
                                                            overlayLiveSearch.activateCurrent()
                                                            event.accepted = true
                                                        } else if (event.key === Qt.Key_Escape) {
                                                            if (root.overlaySearchText.length > 0) {
                                                                root.openOverlaySearchResult({})
                                                            } else {
                                                                compactOverlaySearchField.focus = false
                                                                if (!root.handleEscape())
                                                                    GlobalStates.settingsOverlayOpen = false
                                                            }
                                                            event.accepted = true
                                                        }
                                                    }
                                                }
                                            }

                                            RippleButton {
                                                visible: root.overlaySearchText.length > 0
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                Layout.alignment: Qt.AlignVCenter
                                                buttonRadius: Appearance.rounding.full
                                                colBackground: "transparent"
                                                colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                                                onClicked: {
                                                    root.openOverlaySearchResult({})
                                                    compactOverlaySearchField.forceActiveFocus()
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
                                    function onOverlayCurrentPageChanged() { if (Appearance.animationsEnabled) overlayPageHeaderSwap.restart() }
                                }
                                SequentialAnimation {
                                    id: overlayPageHeaderSwap
                                    NumberAnimation { target: overlayPageHeaderRow; property: "opacity"; to: 0.35; duration: Appearance.animation.elementMoveFast.duration / 2; easing.type: Appearance.animation.elementMoveFast.type }
                                    NumberAnimation { target: overlayPageHeaderRow; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type }
                                }

                                Rectangle {
                                    visible: !SettingsMaterialPreset.waffle
                                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                                    height: 1
                                    color: SettingsMaterialPreset.plateDividerColor
                                }
                            }

                            SettingsPageHost {
                                id: overlayPagesHost
                                Component.onCompleted: root.pageHost = this
                                Component.onDestruction: if (root.pageHost === this) root.pageHost = null
                                anchors { top: overlayPageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                                pages: root.overlayPages
                                requestedIndex: root.overlayCurrentPage
                                visible: root.overlaySearchText.trim().length === 0
                                enabled: visible && root.settingsOpen
                                backgroundWarmup: Boolean(root.embeddedHost) && !root.settingsOpen
                                loadEnabled: Config.ready && (root.settingsOpen || Boolean(root.embeddedHost))
                                onPageNavigationRequested: pageIndex => root.overlayCurrentPage = pageIndex
                            }

                            SettingsPageLoadingOverlay {
                                anchors.fill: overlayPagesHost
                                loading: overlayPagesHost.loading && !overlayPagesHost.error
                                title: String(root.overlayPages?.[root.overlayCurrentPage]?.name ?? "")
                                icon: String(root.overlayPages?.[root.overlayCurrentPage]?.icon ?? "tune")
                                z: 15
                            }

                            SettingsLiveSearchResults {
                                id: overlayLiveSearch
                                anchors { top: overlayPageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                                z: 20
                                query: root.overlaySearchText
                                results: root.overlaySearchResults
                                searchField: root.searchFieldItem
                                iconForPage: index => SettingsPageRegistry.iconForPage(index)
                                onActivated: entry => root.openOverlaySearchResult(entry)
                                onCloseRequested: root.openOverlaySearchResult({})
                            }
                        }
                    }
                }

                // Escape key handler + Ctrl+F
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        if (!root.handleEscape()) {
                            GlobalStates.settingsOverlayOpen = false
                        }
                        event.accepted = true
                    } else if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_F) {
                            if (root.searchFieldItem)
                                root.searchFieldItem.forceActiveFocus()
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Tab) {
                            root.navigateToArea(root.nextNavPage(overlayCurrentPage))
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Backtab) {
                            root.navigateToArea(root.prevNavPage(overlayCurrentPage))
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

                Component.onCompleted: {
                    if (GlobalStates.settingsOverlayOpen) {
                        Qt.callLater(() => {
                            if (GlobalStates.settingsOverlayOpen)
                                settingsCard.forceActiveFocus()
                        })
                    }
                }

                // Grab focus when opened
                Connections {
                    target: GlobalStates
                    function onSettingsOverlayOpenChanged() {
                        if (GlobalStates.settingsOverlayOpen) {
                            Qt.callLater(() => {
                                if (GlobalStates.settingsOverlayOpen)
                                    settingsCard.forceActiveFocus()
                            })
                        }
                    }
                }
            }
        }
    }

    // ── Page definitions (same as settings.qml) ──
    property int overlayCurrentPage: 0
    property bool _navigationInitialized: false
    property int _initialDeepLinkPage: -1
    property int _prevPage: 0
    property int _slideDir: 1

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

    function _persistOverlayPage(): void {
        if (root._navigationInitialized && Persistent.ready && Persistent.states?.settings) {
            const pageIdx = Math.max(0,
                Math.min(root.overlayCurrentPage, root.overlayPages.length - 1))
            Persistent.states.settings.iiPage = pageIdx
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
        const pending = GlobalStates.settingsOverlayRequestedPage ?? -1
        const pendingSection = String(GlobalStates.settingsOverlayRequestedSection ?? "").trim()
        const initialPage = root._initialDeepLinkPage >= 0
            ? root._initialDeepLinkPage
            : pending >= 0 ? pending : persisted
        if (pending >= 0) {
            GlobalStates.settingsOverlayRequestedPage = -1
            GlobalStates.settingsOverlayRequestedSection = ""
        }
        root.overlayCurrentPage = SettingsPageRegistry.safePageIndex(initialPage)
        root._prevPage = root.overlayCurrentPage
        root.navGroup = Hierarchy.parentKey(root.overlayPages[root.overlayCurrentPage])
        root._navigationInitialized = true
        root._initialDeepLinkPage = -1
        root._historyStack = [{ home: false, pageIndex: root.overlayCurrentPage }]
        root._historyIndex = 0
        IrisState.recordVisit(root.overlayCurrentPage)
        root._persistOverlayPage()
        if (pending >= 0 && pendingSection.length > 0 && SettingsPageRegistry.isPageApplicable(pending)) {
            root.openOverlaySearchResult({
                pageIndex: root.overlayCurrentPage,
                pageName: "",
                section: pendingSection,
                label: pendingSection,
                isSection: true
            })
        }
    }

    onOverlayCurrentPageChanged: {
        const safe = SettingsPageRegistry.safePageIndex(root.overlayCurrentPage)
        if (safe !== root.overlayCurrentPage) {
            root.overlayCurrentPage = safe
            return
        }
        root._slideDir = root.overlayCurrentPage > root._prevPage ? 1 : -1
        root._prevPage = root.overlayCurrentPage
        if (root._navigationInitialized && !root._historyNavigating) {
            root.showingHome = false
            root._pushHistoryEntry(false, root.overlayCurrentPage)
            IrisState.recordVisit(root.overlayCurrentPage)
        }
        root._persistOverlayPage()
        root.navGroup=Hierarchy.parentKey(root.overlayPages[root.overlayCurrentPage])
        // Published for settingsNav, which shell.qml owns for both chromes.
        GlobalStates.settingsOverlayCurrentPage = root.overlayCurrentPage
    }

    Connections {
        target: Persistent
        function onReadyChanged() { root.initializeNavigation() }
    }

    Component.onCompleted: {
        root.initializeNavigation()
        if (GlobalStates.settingsOverlayOpen)
            root.consumeSettingsDeepLink()
    }

    // One continuous tab list; saved category metadata only supplies ordering.
    readonly property var overlayPages: SettingsPageRegistry.pages.map(p => {
        if (!p) return null
        var entry = Object.assign({}, p)
        entry.component = Quickshell.shellPath(p.component)
        return entry
    })

    property string navGroup: ""
    readonly property var navPageOrder: SettingsPageRegistry.navigationPageIndexes(false)
    readonly property var visibleNavItems: Hierarchy.entries(overlayPages, navPageOrder,
        navGroup, overlayCurrentPage, false)
    function activateNavigation(entry): void {
        if (entry.back) { navGroup="";return }
        if (entry.groupKey) navGroup=entry.groupKey
        root.overlayCurrentPage=entry.realIndex
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



}
