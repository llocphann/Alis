pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import "modules/common/PanelFamilyPolicy.js" as FamilyPolicy
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root
    // Shell entry animation gate — starts false, set true after delay so panels slide in
    property bool shellEntryReady: false
    // Deferred panel loading gate — non-critical panels wait for this before activating
    property bool deferredPanelsReady: false
    // Captured once per shell root at Config.ready: only a cold Abyss/Niri
    // session should perform the empirically validated perimeter recreation.
    // Cleared before the recreation, and on manual family changes.
    property bool abyssColdPerimeterRecreatePending: false
    // Startup lifecycle — singleton preserves one-shot state across hot reloads.
    property bool bootGreetingOpen: false
    property bool bootGreetingDone: false
    property bool startupLockDone: false
    property bool barOpen: true
    // Each connected Bar popup holds its output's auto-hide Bar until its
    // retract animation finishes. A keyed lease keeps simultaneous popups on
    // different outputs from releasing one another's hold.
    property int _nextBarPopupLeaseId: 0
    property var _barPopupHoverLeases: ({})

    function allocateBarPopupHoverLease(): int {
        root._nextBarPopupLeaseId++
        return root._nextBarPopupLeaseId
    }

    function setBarPopupHoverLease(leaseId: int, outputName: string, held: bool): void {
        if (leaseId <= 0)
            return
        const key = String(leaseId)
        const name = held ? String(outputName ?? "") : ""
        const previous = root._barPopupHoverLeases[key] ?? ""
        if (previous === name)
            return
        const next = Object.assign({}, root._barPopupHoverLeases)
        if (name.length > 0)
            next[key] = name
        else
            delete next[key]
        root._barPopupHoverLeases = next
    }

    function barPopupHoverHeld(outputName: string): bool {
        const name = String(outputName ?? "")
        if (!name)
            return false
        const leases = root._barPopupHoverLeases
        for (const key in leases) {
            if (leases[key] === name)
                return true
        }
        return false
    }
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property string sidebarLeftTargetOutput: ""
    // Hover/clickless opens are leases, not sticky semantic opens. Abyss uses
    // this to slide a sidebar away after the pointer leaves while shortcuts,
    // clicks and IPC keep their existing explicit lifetime.
    property bool sidebarLeftTransient: false
    property bool sidebarLeftExpanded: false
    // A left-sidebar feature requests the panel stay open through implicit closes
    // (backdrop click / focus loss) and yield keyboard focus — e.g. the InnerTune
    // device-flow login, where the user must type a code into an external browser.
    property bool sidebarLeftHoldOpen: false
    property bool aiChatDetached: false
    property bool sidebarRightOpen: false
    property string sidebarRightTargetOutput: ""
    property bool sidebarRightTransient: false
    // Material notification center: explicit opens are held independently
    // from transient bottom-right hover ownership published by the popup.
    property bool notificationCenterExplicitOpen: false
    property string notificationCenterTargetOutput: ""
    property string notificationCenterHoverOutput: ""
    readonly property bool notificationCenterAvailable:
        (Config.options?.panelFamily ?? "ii") !== "waffle"
        && (Config.options?.notificationCenter?.enable ?? true)
        && ((Config.options?.panelFamily === "abyss")
            ? (Config.options?.enabledPanels ?? []).includes("abyssNotificationCenter")
            : (Config.options?.enabledPanels ?? []).includes("iiScreenCorners"))
    readonly property bool notificationCenterOpen:
        root.notificationCenterAvailable
        && (root.notificationCenterExplicitOpen
            || root.notificationCenterHoverOutput.length > 0)

    // Hover ownership is tied to a concrete output. If that monitor disappears
    // while the pointer-owned popup is alive, do not leave a stale lease that
    // keeps notificationCenterOpen true and suppresses transient toasts.
    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            const hoverOutput = root.notificationCenterHoverOutput
            const connected = Quickshell.screens.map(
                screen => String(screen?.name ?? ""))
            if (hoverOutput && !connected.includes(hoverOutput))
                root.notificationCenterHoverOutput = ""

            const oldLeases = root._barPopupHoverLeases
            const nextLeases = {}
            for (const key in oldLeases) {
                if (connected.includes(oldLeases[key]))
                    nextLeases[key] = oldLeases[key]
            }
            if (Object.keys(nextLeases).length !== Object.keys(oldLeases).length)
                root._barPopupHoverLeases = nextLeases
        }
    }

    // Shell-lifetime ToastManager publishes itself here only as a presentation
    // bridge. Queue/debounce/cooldown ownership remains in ToastManager.
    property var toastManager: null

    property string abyssPopupKind: ""
    property string abyssPopupTargetOutput: ""
    property string abyssPopupEdge: ""
    property real abyssPopupAlong: 0
    // Dock application menus are rehosted by the same connected Abyss popup
    // body as Bar popups. The model intentionally stays runtime-only because
    // its actions are live function closures owned by DockAppButton.
    property var abyssDockMenuModel: []
    property string abyssDockMenuOwnerId: ""
    property bool abyssDockMenuTriggerHovered: false
    property string abyssClipboardTargetOutput: ""
    property bool abyssEditing: false
    property string abyssEditorTargetOutput: ""
    function startAbyssEditing(outputName): void {
        if (Config.options?.panelFamily !== "abyss" || root.screenLocked) return
        // The Abyss live Edge editor is a mutually-exclusive desktop editing
        // mode. Clear stale generic shell-layout/widget editor state first so
        // every entrypoint (Settings header, desktop context menu, IPC) lands
        // in the same editor instead of toggling or stacking two edit modes.
        root.setShellLayoutEditMode(false)
        root.setWidgetEditMode(false)
        root.abyssEditorTargetOutput = root.resolveOutputName(String(outputName ?? ""),[])
        root.sessionOpen = false
        root.cheatsheetOpen = false
        ShellUpdates.closeOverlay()
        root.wallpaperSelectorOpen = false
        root.wallpaperLauncherOpen = false
        root.coverflowSelectorOpen = false
        root.settingsOverlayOpen = false
        root.dashboardOpen = false
        root.controlPanelOpen = false
        root.overviewOpen = false
        root.clipboardOpen = false
        root.closeSidebarLeft()
        root.closeSidebarRight()
        root.closeNotificationCenter()
        root.abyssPopupKind = ""
        root.mediaControlsOpen = false
        root.abyssEditing = true
    }
    property bool mediaControlsOpen: false
    signal osdRequested(string kind)
    signal osdDismissed()
    property string abyssOsdKind: "volume"
    property string abyssOsdMessage: ""
    property string abyssOsdHoverOutput: ""
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool osdMicOpen: false
    property bool osdMediaOpen: false
    property string osdMediaAction: "play" // "play", "pause", "next", "previous"
    signal osdMediaActionTriggered(string action)

    function showMediaAction(action: string): void {
        const normalized = String(action ?? "")
        if (!["play", "pause", "next", "previous"].includes(normalized))
            return
        root.osdMediaAction = normalized
        root.osdMediaOpen = true
        root.osdMediaActionTriggered(normalized)
    }

    property bool osdKeyboardLayoutOpen: false
    property bool oskOpen: false
    property string oskTargetMonitor: ""
    onOskOpenChanged: if (oskOpen)
        oskTargetMonitor=focusedScreen?.name ?? primaryScreen?.name ?? ""
    property bool overlayOpen: false
    property bool overviewOpen: false
    property string overviewMode: "default"
    property string overviewTargetOutput: ""
    property string overviewSearchPrefix: ""
    property bool altSwitcherOpen: false
    signal altSwitcherCommand(string command)
    property int activeContextMenuCount: 0
    property var activeContextMenu: null
    property bool clipboardOpen: false
    property bool settingsOverlayOpen: false
    property string settingsOverlayTargetOutput: ""
    readonly property string settingsOverlayPresentationOutput: root.resolveOutputName(settingsOverlayTargetOutput,[])
    property int settingsOverlayRequestedPage: -1 // Set before opening to navigate to a specific page
    property string settingsOverlayRequestedSection: "" // Optional deep-link target inside the requested page
    property int settingsOverlayCurrentPage: -1 // Published by whichever overlay chrome is loaded
    property var _settingsNativeDialogs: ({})
    readonly property bool settingsNativeDialogOpen:
        Object.keys(root._settingsNativeDialogs).length > 0

    function openSettingsPage(index: int): void {
        root.openSettingsSection(index, "")
    }

    function openSettingsSection(index: int, section: string): void {
        const route = FamilyPolicy.settingsRoute(Config.options?.panelFamily,index,section)
        index = route.pageIndex
        const targetSection = route.section.trim()
        const isWaffle = Config.options?.panelFamily === "waffle"
            && Config.options?.waffles?.settings?.useMaterialStyle !== true
        if (isWaffle) {
            Quickshell.execDetached([Quickshell.shellPath("scripts/inir"),
                "waffle-settings-window"])
        } else if (Config.options?.panelFamily === "abyss" || (Config.options?.settingsUi?.overlayMode ?? false)) {
            root.settingsOverlayTargetOutput = root.resolveOutputName("",[])
            root.settingsOverlayRequestedSection = targetSection
            root.settingsOverlayRequestedPage = index
            root.settingsOverlayOpen = true
        } else {
            const command = ["/usr/bin/env", `QS_SETTINGS_PAGE=${index}`]
            if (targetSection.length > 0)
                command.push("QS_SETTINGS_SECTION=" + targetSection)
            command.push(Quickshell.shellPath("scripts/inir"), "settings-window")
            Quickshell.execDetached(command)
        }
    }

    function setSettingsNativeDialogVisible(dialogKey: string, visible: bool): void {
        const key = String(dialogKey ?? "").trim()
        if (!key) return
        const next = Object.assign({}, root._settingsNativeDialogs)
        if (visible)
            next[key] = true
        else
            delete next[key]
        root._settingsNativeDialogs = next
    }

    property bool regionSelectorOpen: false
    property var regionSelectorAction: 0
    property var regionSelectorMode: 0
    // Explicit screenshot callers must remain deterministic. The dedicated
    // Niri binds for screenshot, OCR and visual search are separate contracts;
    // opening one must never inherit state left by another tool.
    function openRegionScreenshot(): void {
        regionSelectorAction = 0
        regionSelectorMode = 0
        regionSelectorOpen = true
    }

    // The unified snip menu may restore the last toolbar choice. Raw ordinals
    // mirror RegionSelection's enums: action 0 Shot, 1 Edit, 2 Search, 3 OCR
    // (record is never restored); mode 0 rectangle, 1 circle.
    function openRememberedRegionTool(): void {
        let action = 0
        let mode = 0
        if (Config.options?.regionSelector?.rememberSnipChoice ?? true) {
            const savedAction = Config.options?.regionSelector?.lastAction ?? 0
            const savedMode = Config.options?.regionSelector?.lastMode ?? 0
            if (savedAction >= 0 && savedAction <= 3) action = savedAction
            if (savedMode === 1) mode = savedMode
        }
        regionSelectorAction = action
        regionSelectorMode = mode
        regionSelectorOpen = true
    }
    property bool tilingOverlayPickerOpen: false
    property bool tilingOverlayOsdOpen: false
    // Native screenshot annotation editor (Edit action)
    property bool annotationEditorOpen: false
    property string annotationEditorPath: ""
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool wallpaperLauncherOpen: false
    property string wallpaperLauncherMode: "static"
    property string wallpaperLauncherSearchText: ""
    property bool widgetEditMode: false
    property string selectedDesktopWidget: ""
    property string selectedDesktopItem: ""
    property string desktopWidgetQuickControls: ""
    property bool shellLayoutEditMode: false

    // Per-output controls retain their Background context while the existing
    // Abyss body host owns painting, clipping and input. Identity checks protect
    // a replacement output from a retiring window's unregister callback.
    property var desktopWidgetEditors: ({})
    function registerDesktopWidgetEditor(outputName: string, item: var): void {
        if (!outputName || !item || desktopWidgetEditors[outputName] === item) return
        const next = Object.assign({}, desktopWidgetEditors)
        next[outputName] = item
        desktopWidgetEditors = next
    }
    function unregisterDesktopWidgetEditor(outputName: string, item: var): void {
        if (!outputName || desktopWidgetEditors[outputName] !== item) return
        const next = Object.assign({}, desktopWidgetEditors)
        delete next[outputName]
        desktopWidgetEditors = next
    }

    function setWidgetEditMode(enabled: bool): void {
        if (enabled)
            shellLayoutEditMode = false
        else {
            selectedDesktopWidget = ""
            selectedDesktopItem = ""
            desktopWidgetQuickControls = ""
        }
        widgetEditMode = enabled
    }

    function selectDesktopWidget(instanceKey: string): void {
        if (!widgetEditMode)
            return
        selectedDesktopWidget = String(instanceKey ?? "")
        selectedDesktopItem = ""
    }

    function clearDesktopWidgetSelection(): void {
        selectedDesktopWidget = ""
        selectedDesktopItem = ""
        desktopWidgetQuickControls = ""
    }

    function selectDesktopItem(instanceKey: string): void {
        selectedDesktopItem = String(instanceKey ?? "")
        selectedDesktopWidget = ""
    }

    function clearDesktopItemSelection(): void {
        selectedDesktopItem = ""
    }

    function requestDesktopWidgetQuickControls(instanceKey: string): void {
        if (!widgetEditMode)
            return
        const key = String(instanceKey ?? "")
        selectedDesktopWidget = key
        desktopWidgetQuickControls = key
    }

    function setShellLayoutEditMode(enabled: bool): void {
        if (enabled) {
            widgetEditMode = false
            selectedDesktopWidget = ""
            selectedDesktopItem = ""
            desktopWidgetQuickControls = ""
        }
        shellLayoutEditMode = enabled
    }
    // Navigate sidebar right to a specific widget by type (e.g. "notepad", "calendar")
    property string sidebarRightRequestedWidget: ""
    // Dialog requests from other panels (e.g. left sidebar → right sidebar)
    property bool requestWifiDialog: false
    property bool requestBluetoothDialog: false
    // Selection targets: "main", "backdrop", "waffle", "waffle-backdrop"
    property string wallpaperSelectionTarget: "main"
    // Target monitor for wallpaper selector (set before opening, avoids config timing issues)
    property string wallpaperSelectorTargetMonitor: ""
    onWallpaperSelectorOpenChanged: {
        if (wallpaperSelectorOpen) {
            // Old callers retain target/output before reaching the one picker.
            wallpaperSelectorOpen=false
            wallpaperLauncherMode=WallpaperListener.isAnimatedPath(Wallpapers.currentWallpaperPathForTarget(Wallpapers.currentSelectionTarget(),wallpaperSelectorTargetMonitor)) ? "animated" : "static"
            wallpaperLauncherOpen=true
        }
    }
    onWallpaperLauncherOpenChanged: {
        if (!wallpaperLauncherOpen) {
            // Restore the configured wallpaper if the user browsed away without applying.
            Wallpapers.cancelWallpaperPreview()
            wallpaperSelectionTarget = "main"
            wallpaperSelectorTargetMonitor = ""
            if (Config.options?.wallpaperSelector?.selectionTarget
                    && Config.options.wallpaperSelector.selectionTarget !== "main")
                Config.setNestedValue("wallpaperSelector.selectionTarget", "main")
            if (Config.options?.wallpaperSelector?.targetMonitor)
                Config.setNestedValue("wallpaperSelector.targetMonitor", "")
        }
    }
    property bool cheatsheetOpen: false
    property bool coverflowSelectorOpen: false
    onCoverflowSelectorOpenChanged: {
        if (coverflowSelectorOpen) {
            // Old callers retain target/output before reaching the one picker.
            coverflowSelectorOpen=false
            wallpaperLauncherMode=WallpaperListener.isAnimatedPath(Wallpapers.currentWallpaperPathForTarget(Wallpapers.currentSelectionTarget(),wallpaperSelectorTargetMonitor)) ? "animated" : "static"
            wallpaperLauncherOpen=true
        }
    }
    property bool controlPanelOpen: false
    property bool dashboardOpen: false
    property int dashboardPage: 0
    property string dashboardPageId: "dashboard"
    // Lightweight browsing identity survives the bounded Dashboard UI cache.
    property var dashboardMusicBrowser: ({})
    property bool workspaceShowNumbers: false
    property var activeBooruImageMenu: null  // Track which BooruImage has its menu open
    property var activeTaskViewMenu: null  // Track which WindowThumbnail has its menu open
    // Waffle-specific states
    property bool searchOpen: false
    property bool waffleActionCenterOpen: false
    property bool waffleNotificationCenterOpen: false
    property bool waffleWidgetsOpen: false
    property bool waffleAltSwitcherOpen: false
    property bool waffleClipboardOpen: false
    property bool waffleTaskViewOpen: false
    // Panel family transition animation state
    property string familyTransitionTarget: "ii"
    property bool familyTransitionActive: false
    property string familyTransitionDirection: "left" // "left" = current exits left, new enters from right

    signal requestRipple(real x, real y, string screenName)

    // User-configured fallback for singular panels such as wallpaper pickers.
    // Empty string uses the first available Quickshell screen.
    readonly property var primaryScreen: {
        const name = Config.options?.display?.primaryMonitor ?? ""
        if (name.length > 0) {
            const s = Quickshell.screens.find(scr => scr.name === name)
            if (s) return s
        }
        return Quickshell.screens[0]
    }

    // Focus-following screen for singular interactive surfaces. Keep this
    // separate from primaryScreen: the latter is a user fallback, while this
    // follows the compositor and only falls back when focus cannot be resolved.
    readonly property var focusedScreen: {
        let name = ""
        if (CompositorService.isNiri)
            name = NiriService.currentOutput ?? ""
        else if (CompositorService.isHyprland)
            name = Hyprland.focusedMonitor?.name ?? ""
        return Quickshell.screens.find(screen => (screen?.name ?? "") === name)
            ?? root.primaryScreen
            ?? Quickshell.screens[0]
            ?? null
    }

    function connectedOutputNames(allowedOutputs): var {
        const connected = Quickshell.screens
            .map(screen => String(screen?.name ?? ""))
            .filter(name => name.length > 0)
        if (!Array.isArray(allowedOutputs) || allowedOutputs.length === 0)
            return connected
        const enabled = connected.filter(name => allowedOutputs.includes(name))
        return enabled.length > 0 ? enabled : connected
    }

    function resolveOutputName(requestedOutput, allowedOutputs): string {
        const names = root.connectedOutputNames(allowedOutputs)
        if (names.length === 0)
            return ""
        const requested = String(requestedOutput ?? "")
        if (requested.length > 0 && names.includes(requested))
            return requested
        const focused = String(root.focusedScreen?.name ?? "")
        if (focused.length > 0 && names.includes(focused))
            return focused
        const primary = String(root.primaryScreen?.name ?? "")
        if (primary.length > 0 && names.includes(primary))
            return primary
        return names[0]
    }

    readonly property string overviewPresentationOutput:
        root.resolveOutputName(root.overviewTargetOutput, [])
    readonly property string sidebarLeftPresentationOutput:
        root.resolveOutputName(root.sidebarLeftTargetOutput,
            Config.options?.sidebar?.screenList ?? [])
    readonly property string sidebarRightPresentationOutput:
        root.resolveOutputName(root.sidebarRightTargetOutput,
            Config.options?.sidebar?.screenList ?? [])

    readonly property string notificationCenterPresentationOutput:
        root.resolveOutputName(root.notificationCenterTargetOutput,
            Config.options?.notificationCenter?.screenList ?? [])

    function openOverview(outputName): void {
        overviewMode = "default"
        overviewTargetOutput = root.resolveOutputName(outputName, [])
        overviewOpen = true
    }

    function closeOverview(): void {
        overviewOpen = false
    }

    function toggleOverview(outputName): void {
        const resolved = root.resolveOutputName(outputName, [])
        if (overviewOpen && overviewMode === "default" && overviewPresentationOutput === resolved)
            root.closeOverview()
        else
            root.openOverview(resolved)
    }

    function openTaskView(outputName): void {
        overviewMode = "taskview"
        overviewSearchPrefix = ""
        overviewTargetOutput = root.resolveOutputName(outputName, [])
        overviewOpen = true
    }

    function toggleTaskView(outputName): void {
        const resolved = root.resolveOutputName(outputName, [])
        if (overviewOpen && overviewMode === "taskview" && overviewPresentationOutput === resolved)
            root.closeOverview()
        else
            root.openTaskView(resolved)
    }

    function openSidebarLeft(outputName, transient): void {
        sidebarLeftTargetOutput = root.resolveOutputName(outputName,
            Config.options?.sidebar?.screenList ?? [])
        sidebarLeftTransient = transient === true
        sidebarLeftOpen = true
    }

    function closeSidebarLeft(): void {
        sidebarLeftOpen = false
        sidebarLeftTransient = false
    }

    function toggleSidebarLeft(outputName): void {
        const resolved = root.resolveOutputName(outputName,
            Config.options?.sidebar?.screenList ?? [])
        if (sidebarLeftOpen && sidebarLeftPresentationOutput === resolved)
            root.closeSidebarLeft()
        else
            root.openSidebarLeft(resolved, false)
    }

    function openSidebarRight(outputName, transient): void {
        sidebarRightTargetOutput = root.resolveOutputName(outputName,
            Config.options?.sidebar?.screenList ?? [])
        sidebarRightTransient = transient === true
        sidebarRightOpen = true
    }

    function openNotificationCenter(outputName): bool {
        if (!root.notificationCenterAvailable)
            return false
        notificationCenterTargetOutput = root.resolveOutputName(outputName,
            Config.options?.notificationCenter?.screenList ?? [])
        notificationCenterExplicitOpen = true
        return true
    }

    function closeNotificationCenter(): void {
        notificationCenterExplicitOpen = false
        notificationCenterTargetOutput = ""
        notificationCenterHoverOutput = ""
    }

    function toggleNotificationCenter(outputName): bool {
        if (!root.notificationCenterAvailable)
            return false
        const resolved = root.resolveOutputName(outputName,
            Config.options?.notificationCenter?.screenList ?? [])
        if (notificationCenterExplicitOpen
                && notificationCenterPresentationOutput === resolved) {
            root.closeNotificationCenter()
            return false
        }
        return root.openNotificationCenter(resolved)
    }

    function setNotificationCenterHoverOutput(outputName, open): void {
        const name = String(outputName ?? "")
        if (!open) {
            if (notificationCenterHoverOutput === name)
                notificationCenterHoverOutput = ""
            return
        }
        if (!root.notificationCenterAvailable || name.length === 0)
            return
        notificationCenterHoverOutput = name
    }

    function closeSidebarRight(): void {
        sidebarRightOpen = false
        sidebarRightTransient = false
    }

    function toggleSidebarRight(outputName): void {
        const resolved = root.resolveOutputName(outputName,
            Config.options?.sidebar?.screenList ?? [])
        if (sidebarRightOpen && sidebarRightPresentationOutput === resolved)
            root.closeSidebarRight()
        else
            root.openSidebarRight(resolved, false)
    }

    onOverviewOpenChanged: {
        if (overviewOpen && overviewTargetOutput.length === 0)
            overviewTargetOutput = root.resolveOutputName("", [])
    }

    onSidebarLeftOpenChanged: {
        if (sidebarLeftOpen && sidebarLeftTargetOutput.length === 0)
            sidebarLeftTargetOutput = root.resolveOutputName("",
                Config.options?.sidebar?.screenList ?? [])
    }

    // Close other waffle popups when one opens (unless allowMultiplePanels is enabled)
    property bool _allowMultiple: Config.options?.waffles?.behavior?.allowMultiplePanels ?? false
    onSearchOpenChanged: {
        if (searchOpen && !_allowMultiple) {
            waffleActionCenterOpen = false
            waffleNotificationCenterOpen = false
            waffleWidgetsOpen = false
            waffleClipboardOpen = false
        }
    }
    onWaffleActionCenterOpenChanged: {
        if (waffleActionCenterOpen && !_allowMultiple) {
            searchOpen = false
            waffleNotificationCenterOpen = false
            waffleWidgetsOpen = false
            waffleClipboardOpen = false
        }
    }
    onWaffleNotificationCenterOpenChanged: {
        if (waffleNotificationCenterOpen) {
            if (!_allowMultiple) {
                searchOpen = false
                waffleActionCenterOpen = false
                waffleWidgetsOpen = false
                waffleClipboardOpen = false
            }
            // Mark notifications as read when opening notification center
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }
    onWaffleWidgetsOpenChanged: {
        if (waffleWidgetsOpen && !_allowMultiple) {
            searchOpen = false
            waffleActionCenterOpen = false
            waffleNotificationCenterOpen = false
            waffleClipboardOpen = false
        }
    }
    onWaffleClipboardOpenChanged: {
        if (waffleClipboardOpen && !_allowMultiple) {
            searchOpen = false
            waffleActionCenterOpen = false
            waffleNotificationCenterOpen = false
            waffleWidgetsOpen = false
            waffleTaskViewOpen = false
        }
    }
    onWaffleTaskViewOpenChanged: {
        if (waffleTaskViewOpen && !_allowMultiple) {
            searchOpen = false
            waffleActionCenterOpen = false
            waffleNotificationCenterOpen = false
            waffleWidgetsOpen = false
            waffleClipboardOpen = false
        }
    }

    onSidebarRightOpenChanged: {
        if (sidebarRightOpen && sidebarRightTargetOutput.length === 0)
            sidebarRightTargetOutput = root.resolveOutputName("",
                Config.options?.sidebar?.screenList ?? [])
    }

    onNotificationCenterAvailableChanged: {
        if (!notificationCenterAvailable)
            root.closeNotificationCenter()
    }

    onNotificationCenterOpenChanged: {
        if (!notificationCenterOpen)
            return
        // Let output policy settle first. An explicit request can be rejected
        // immediately by the target ScreenCorners host (for example while a
        // fullscreen app owns that output); such an invisible request must not
        // consume unread state.
        Qt.callLater(() => {
            if (!root.notificationCenterOpen
                    || !(Config.options?.notificationCenter?.markReadOnOpen ?? true))
                return
            // The current backend models unread state as the transient popup flag.
            // Preserve the legacy "viewing history consumes the toast" behavior as
            // one truthful setting rather than exposing two controls that cannot be
            // independent without a separate persisted read-state model.
            Notifications.timeoutAll()
            Notifications.markAllRead()
        })
    }

    onScreenLockedChanged: {
        if (screenLocked)
            root.closeNotificationCenter()
    }

    property real screenZoom: 1
    onScreenZoomChanged: {
        // Niri doesn't have native zoom support like Hyprland's cursor:zoom_factor
        // The IPC handler still works but zoom is Hyprland-only for now
        if (!CompositorService.isHyprland)
            return;
        Quickshell.execDetached(["hyprctl", "keyword", "cursor:zoom_factor", root.screenZoom.toString()]);
    }
    Behavior on screenZoom {
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: GlobalShortcut {
            name: "workspaceNumber"
            description: "Hold to show workspace numbers, release to show icons"

            onPressed: {
                root.superDown = true
            }
            onReleased: {
                root.superDown = false
            }
        }
    }

    IpcHandler {
		target: "zoom"

		function zoomIn(): void {
            screenZoom = Math.min(screenZoom + 0.4, 3.0)
        }

        function zoomOut(): void {
            screenZoom = Math.max(screenZoom - 0.4, 1)
        }
	}
}
