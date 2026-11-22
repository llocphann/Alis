pragma ComponentBehavior: Bound

import qs.modules.bootGreeting
import qs.modules.cheatsheet
import qs.modules.onScreenKeyboard
import qs.modules.recordingOsd
import qs.modules.tilingOverlay
import qs.modules.overview
import qs.modules.regionSelector
import qs.modules.screenCorners
import qs.modules.sessionScreen
import qs.modules.wallpaperSelector
import qs.modules.wallpaperLauncher

import qs.modules.waffle.actionCenter
import qs.modules.waffle.looks
import qs.modules.waffle.altSwitcher as WaffleAltSwitcherModule
import qs.modules.waffle.background as WaffleBackgroundModule
import qs.modules.waffle.bar as WaffleBarModule
import qs.modules.waffle.clipboard as WaffleClipboardModule
import qs.modules.waffle.notificationCenter
import qs.modules.waffle.onScreenDisplay as WaffleOSDModule
import qs.modules.waffle.polkit as WafflePolkitModule
import qs.modules.waffle.startMenu
import qs.modules.waffle.widgets
import qs.modules.waffle.backdrop as WaffleBackdropModule
import qs.modules.waffle.notificationPopup as WaffleNotificationPopupModule
import qs.modules.waffle.taskview as WaffleTaskViewModule

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services
import qs.services.deferred

Item {
    id: root

    readonly property var waffleAltSwitcherOptions:
        Config.options?.waffles?.altSwitcher ?? ({})
    readonly property string waffleAltSwitcherPreset:
        root.waffleAltSwitcherOptions.preset ?? "thumbnails"
    readonly property bool waffleAltSwitcherVisual:
        root.waffleAltSwitcherPreset !== "none"
        && !((root.waffleAltSwitcherOptions.noVisualUi ?? false)
            && root.waffleAltSwitcherPreset !== "skew")

    // Immediate panels — visible at first frame or must catch early events
    component PanelLoader: LazyLoader {
        id: panelLoader
        required property string identifier
        property bool extraCondition: true
        readonly property bool enabledPanel: Config.ready
            && (Config.options?.enabledPanels ?? []).includes(identifier)
            && extraCondition
        active: enabledPanel
    }

    // Deferred panels — loaded asynchronously after first frame to reduce boot contention
    component DeferredPanelLoader: LazyLoader {
        id: deferredPanelLoader
        required property string identifier
        property bool extraCondition: true
        readonly property bool enabledPanel: Config.ready
            && (Config.options?.enabledPanels ?? []).includes(identifier)
            && extraCondition
        loading: Config.ready && GlobalStates.shellEntryReady && enabledPanel
        activeAsync: Config.ready && GlobalStates.deferredPanelsReady && enabledPanel
    }

    readonly property bool keepPanelsWarm: Boolean(Config.options?.performance?.keepPanelsWarm ?? false)
    onKeepPanelsWarmChanged: {
        if (!keepPanelsWarm && waffleDashboardLoader.dashboardMounted && !waffleDashboardLoader.wantOpen)
            waffleDashboardIdleEvictTimer.restart()
        else if (keepPanelsWarm)
            waffleDashboardIdleEvictTimer.stop()
        if (!keepPanelsWarm && waffleClipboardLoader.clipboardMounted && !waffleClipboardLoader.wantOpen)
            waffleClipboardCloseTimer.restart()
        else if (keepPanelsWarm)
            waffleClipboardCloseTimer.stop()
    }

    component OnDemandPanelLoader: LazyLoader {
        id: onDemandLoader
        required property string identifier
        required property bool open
        property int closeGraceMs: 250
        property int reopenCooldownMs: 0
        property bool resident: open
        property Timer closeGrace: Timer {
            interval: root.keepPanelsWarm
                ? Math.max(onDemandLoader.closeGraceMs, 60000)
                : Math.max(onDemandLoader.closeGraceMs, onDemandLoader.reopenCooldownMs)
            onTriggered: onDemandLoader.resident = onDemandLoader.open
        }
        readonly property bool enabledPanel: Config.ready
            && (Config.options?.enabledPanels ?? []).includes(identifier)
        onOpenChanged: {
            if (open) {
                closeGrace.stop()
                resident = true
            } else {
                closeGrace.restart()
            }
        }
        loading: enabledPanel && resident
        activeAsync: enabledPanel && GlobalStates.deferredPanelsReady && resident
    }

    readonly property int wafflePanelCloseGraceMs:
        Looks.transition.enabled ? Looks.transition.duration.medium + 80 : 60

    Component.onCompleted: {
        // Clear any stale non-Waffle sidebar states when entering Waffle family
        GlobalStates.sidebarLeftOpen = false
        GlobalStates.sidebarRightOpen = false
    }

    // === Immediate feedback panels within the deferred host ===
    // Core Waffle surfaces (bar/background/backdrop) are owned by the critical
    // startup host so they are not delayed by the rest of this module.
    PanelLoader { identifier: "wNotificationPopup"; component: WaffleNotificationPopupModule.WaffleNotificationPopup {} }
    PanelLoader { identifier: "wOnScreenDisplay"; component: WaffleOSDModule.WaffleOSD {} }

    // === Deferred panels ===
    OnDemandPanelLoader { identifier: "wStartMenu"; open: GlobalStates.searchOpen; closeGraceMs: root.wafflePanelCloseGraceMs; reopenCooldownMs: 1200; component: WaffleStartMenu {} }
    OnDemandPanelLoader { identifier: "wActionCenter"; open: GlobalStates.waffleActionCenterOpen; closeGraceMs: Looks.transition.enabled ? Looks.transition.duration.medium + 40 : 40; reopenCooldownMs: 900; component: WaffleActionCenter {} }
    OnDemandPanelLoader { identifier: "wNotificationCenter"; open: GlobalStates.waffleNotificationCenterOpen; closeGraceMs: root.wafflePanelCloseGraceMs; component: WaffleNotificationCenter {} }
    OnDemandPanelLoader { identifier: "wWidgets"; open: GlobalStates.waffleWidgetsOpen && (Config.options?.waffles?.modules?.widgets ?? true); closeGraceMs: root.wafflePanelCloseGraceMs; component: WaffleWidgets {} }
    DeferredPanelLoader { identifier: "wPolkit"; component: WafflePolkitModule.WafflePolkit {} }
    OnDemandPanelLoader { identifier: "wSessionScreen"; open: GlobalStates.sessionOpen; component: SessionScreen {} }
    OnDemandPanelLoader { identifier: "wTaskView"; open: GlobalStates.waffleTaskViewOpen; component: WaffleTaskViewModule.WaffleTaskView {} }

    // Shared modules that work with waffle
    DeferredPanelLoader { identifier: "iiBootGreeting"; component: BootGreeting {} }
    OnDemandPanelLoader { identifier: "iiCheatsheet"; open: GlobalStates.cheatsheetOpen; component: Cheatsheet {} }
    Timer {
        id: waffleDashboardIdleEvictTimer
        interval: 60000
        repeat: false
        onTriggered: {
            if (!waffleDashboardLoader.wantOpen && !root.keepPanelsWarm)
                waffleDashboardLoader.dashboardMounted = false
        }
    }
    LazyLoader {
        id: waffleDashboardLoader
        objectName: "waffleDashboardLoader"
        property bool dashboardMounted: GlobalStates.dashboardOpen
        readonly property bool wantOpen: GlobalStates.dashboardOpen
        onWantOpenChanged: {
            if (wantOpen) {
                waffleDashboardIdleEvictTimer.stop()
                dashboardMounted = true
                if (!(Config.options?.waffles?.behavior?.allowMultiplePanels ?? false)) {
                    GlobalStates.searchOpen = false
                    GlobalStates.waffleActionCenterOpen = false
                    GlobalStates.waffleNotificationCenterOpen = false
                    GlobalStates.waffleWidgetsOpen = false
                    GlobalStates.waffleClipboardOpen = false
                    GlobalStates.waffleTaskViewOpen = false
                }
            } else if (dashboardMounted && !root.keepPanelsWarm) {
                waffleDashboardIdleEvictTimer.restart()
            }
        }
        loading: Config.ready && Config.options?.panelFamily === "waffle" && (wantOpen || dashboardMounted)
        activeAsync: Config.ready && GlobalStates.deferredPanelsReady
            && Config.options?.panelFamily === "waffle" && (wantOpen || dashboardMounted)
        source: "../dashboard/Dashboard.qml"
    }
    Connections {
        target: GlobalStates
        enabled: !(Config.options?.waffles?.behavior?.allowMultiplePanels ?? false)
        function onSearchOpenChanged(): void { if (GlobalStates.searchOpen) GlobalStates.dashboardOpen = false }
        function onWaffleActionCenterOpenChanged(): void { if (GlobalStates.waffleActionCenterOpen) GlobalStates.dashboardOpen = false }
        function onWaffleNotificationCenterOpenChanged(): void { if (GlobalStates.waffleNotificationCenterOpen) GlobalStates.dashboardOpen = false }
        function onWaffleWidgetsOpenChanged(): void { if (GlobalStates.waffleWidgetsOpen) GlobalStates.dashboardOpen = false }
        function onWaffleTaskViewOpenChanged(): void { if (GlobalStates.waffleTaskViewOpen) GlobalStates.dashboardOpen = false }
    }
    OnDemandPanelLoader { identifier: "iiOnScreenKeyboard"; open: GlobalStates.oskOpen; component: OnScreenKeyboard {} }
    OnDemandPanelLoader { identifier: "iiOverview"; open: GlobalStates.overviewOpen; closeGraceMs: Appearance.animation.elementMoveExit.duration + 80; component: Overview {} }

    DeferredPanelLoader { identifier: "iiRegionSelector"; component: RegionSelector {} }
    DeferredPanelLoader { identifier: "iiScreenCorners"; component: ScreenCorners {} }

    OnDemandPanelLoader { identifier: "iiWallpaperSelector"; open: GlobalStates.wallpaperLauncherOpen; closeGraceMs: Appearance.animationsEnabled ? Math.max(240, Appearance.animation.elementMoveExit.duration + 60) : 40; component: WallpaperLauncher {} }
    OnDemandPanelLoader { identifier: "iiRecordingOsd"; open: RecorderStatus.isRecording; closeGraceMs: 250; component: RecordingOsd {} }

    OnDemandPanelLoader {
        identifier: "iiTilingOverlay"
        open: GlobalStates.tilingOverlayPickerOpen || GlobalStates.tilingOverlayOsdOpen
        closeGraceMs: 250
        component: TilingOverlay {}
    }

    Timer {
        id: waffleClipboardCloseTimer
        interval: root.keepPanelsWarm ? 60000 : root.wafflePanelCloseGraceMs
        repeat: false
        onTriggered: {
            if (!waffleClipboardLoader.wantOpen && !root.keepPanelsWarm)
                waffleClipboardLoader.clipboardMounted = false
        }
    }
    LazyLoader {
        id: waffleClipboardLoader
        property bool clipboardMounted: GlobalStates.waffleClipboardOpen
        readonly property bool wantOpen: GlobalStates.waffleClipboardOpen
        onWantOpenChanged: {
            if (wantOpen) {
                waffleClipboardCloseTimer.stop()
                clipboardMounted = true
            } else if (clipboardMounted && !root.keepPanelsWarm) {
                waffleClipboardCloseTimer.restart()
            }
        }
        loading: Config.ready && GlobalStates.shellEntryReady
            && Config.options?.panelFamily === "waffle"
            && (wantOpen || clipboardMounted)
        activeAsync: Config.ready && GlobalStates.deferredPanelsReady
            && Config.options?.panelFamily === "waffle"
            && (wantOpen || clipboardMounted)
        component: WaffleClipboardModule.WaffleClipboard {}
    }

    LazyLoader {
        id: waffleAltSwitcherLoader
        loading: Config.ready && GlobalStates.shellEntryReady
            && Config.options?.panelFamily === "waffle"
            && root.waffleAltSwitcherVisual
        activeAsync: Config.ready && GlobalStates.deferredPanelsReady
            && Config.options?.panelFamily === "waffle"
            && root.waffleAltSwitcherVisual
        component: WaffleAltSwitcherModule.WaffleAltSwitcher {}
    }

    WaffleBackgroundModule.WaffleShellEditHud {}
}
