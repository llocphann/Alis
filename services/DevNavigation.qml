pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services.deferred
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var baseDestinations: [
        { id: "sidebar-left/ai", family: "shared", surface: "sidebar-left", view: "ai", safe: true, settleMs: 500 },
        { id: "sidebar-left/translator", family: "shared", surface: "sidebar-left", view: "translator", safe: true, settleMs: 350 },
        { id: "sidebar-left/news", family: "shared", surface: "sidebar-left", view: "news", safe: true, settleMs: 500 },
        { id: "sidebar-left/music", family: "ii", surface: "dashboard", view: "music", safe: true, settleMs: 450 },
        { id: "sidebar-left/tools", family: "shared", surface: "sidebar-left", view: "tools", safe: true, settleMs: 350 },
        { id: "sidebar-right/controls", family: "shared", surface: "sidebar-right", view: "controls", safe: true, settleMs: 350 },
        { id: "sidebar-right/calendar", family: "shared", surface: "sidebar-right", view: "calendar", safe: true, settleMs: 350 },
        { id: "sidebar-right/events", family: "shared", surface: "sidebar-right", view: "events", safe: true, settleMs: 350 },
        { id: "sidebar-right/todo", family: "shared", surface: "sidebar-right", view: "todo", safe: true, settleMs: 350 },
        { id: "sidebar-right/notepad", family: "shared", surface: "sidebar-right", view: "notepad", safe: true, settleMs: 350 },
        { id: "sidebar-right/calculator", family: "shared", surface: "sidebar-right", view: "calculator", safe: true, settleMs: 350 },
        { id: "sidebar-right/sysmon", family: "shared", surface: "sidebar-right", view: "sysmon", safe: true, settleMs: 350 },
        { id: "sidebar-right/weather", family: "shared", surface: "sidebar-right", view: "weather", safe: true, settleMs: 450 },
        { id: "sidebar-right/timer", family: "shared", surface: "sidebar-right", view: "timer", safe: true, settleMs: 350 },
        { id: "control-panel", family: "ii", surface: "control-panel", view: "", safe: true, settleMs: 350 },
        { id: "dashboard", family: "ii", surface: "dashboard", view: "", safe: true, settleMs: 450 },
        { id: "dashboard/music", family: "ii", surface: "dashboard", view: "music", safe: true, settleMs: 450 },
        { id: "notification-center", family: "ii", surface: "notification-center", view: "", safe: true, settleMs: 350 },
        { id: "media-controls", family: "shared", surface: "media-controls", view: "", safe: true, settleMs: 350 },
        { id: "clipboard", family: "shared", surface: "clipboard", view: "", safe: true, settleMs: 350 },
        { id: "cheatsheet", family: "shared", surface: "cheatsheet", view: "", safe: true, settleMs: 350 },
        { id: "overview", family: "shared", surface: "overview", view: "", safe: true, settleMs: 450 },
        { id: "overview/actions", family: "shared", surface: "overview", view: "actions", safe: true, settleMs: 450 },
        { id: "overview/clipboard", family: "shared", surface: "overview", view: "clipboard", safe: true, settleMs: 450 },
        { id: "wallpaper/grid", family: "ii", surface: "wallpaper-grid", view: "", safe: true, settleMs: 500 },
        { id: "wallpaper/coverflow", family: "ii", surface: "wallpaper-coverflow", view: "", safe: true, settleMs: 500 },
        { id: "tiling/picker", family: "shared", surface: "tiling", view: "picker", safe: true, settleMs: 350 },
        { id: "tiling/osd", family: "shared", surface: "tiling", view: "osd", safe: true, settleMs: 350 },
        { id: "waffle/start", family: "waffle", surface: "waffle-search", view: "start", safe: true, settleMs: 350 },
        { id: "waffle/all-apps", family: "waffle", surface: "waffle-search", view: "all-apps", safe: true, settleMs: 350 },
        { id: "waffle/search", family: "waffle", surface: "waffle-search", view: "search", safe: true, settleMs: 450 },
        { id: "waffle/action-center", family: "waffle", surface: "waffle-action-center", view: "", safe: true, settleMs: 350 },
        { id: "waffle/notification-center", family: "waffle", surface: "waffle-notification-center", view: "", safe: true, settleMs: 350 },
        { id: "waffle/widgets", family: "waffle", surface: "waffle-widgets", view: "", safe: true, settleMs: 350 },
        { id: "waffle/taskview", family: "waffle", surface: "waffle-taskview", view: "", safe: true, settleMs: 450 }
    ]
    property var settingsDestinations: []
    readonly property var destinations: baseDestinations.concat(settingsDestinations)
    property string currentDestination: ""
    property string requestedWaffleStartView: "start"

    function registerSettingsPages(pages): void {
        const out = []
        const list = pages ?? []
        for (let index = 0; index < list.length; index++) {
            const page = list[index]
            if (page?.devNavigationHidden === true) continue
            const key = String(page?.key ?? "")
            if (key.length === 0) continue
            out.push({ id: "settings/" + key, family: "shared", surface: "settings", view: key, pageIndex: index, safe: true, settleMs: 300 })
        }
        settingsDestinations = out
    }

    function entryFor(destination: string): var {
        if (destination === "sidebar-left/ytmusic")
            return destinations.find(entry => entry.id === "sidebar-left/music") ?? null
        return destinations.find(entry => entry.id === destination) ?? null
    }

    function closeAll(): void {
        GlobalStates.sidebarLeftOpen = false
        GlobalStates.sidebarRightOpen = false
        GlobalStates.closeNotificationCenter()
        GlobalStates.controlPanelOpen = false
        GlobalStates.dashboardOpen = false
        GlobalStates.mediaControlsOpen = false
        GlobalStates.clipboardOpen = false
        GlobalStates.cheatsheetOpen = false
        GlobalStates.overviewOpen = false
        GlobalStates.wallpaperSelectorOpen = false
        GlobalStates.coverflowSelectorOpen = false
        GlobalStates.tilingOverlayPickerOpen = false
        GlobalStates.tilingOverlayOsdOpen = false
        GlobalStates.settingsOverlayOpen = false
        GlobalStates.searchOpen = false
        GlobalStates.waffleActionCenterOpen = false
        GlobalStates.waffleNotificationCenterOpen = false
        GlobalStates.waffleWidgetsOpen = false
        GlobalStates.waffleTaskViewOpen = false
        GlobalStates.sidebarRightRequestedWidget = ""
        requestedWaffleStartView = "start"
        LauncherSearch.query = ""
        currentDestination = ""
    }

    function request(destination: string): string {
        const entry = entryFor(destination)
        if (!entry) return "error:unknown-destination"
        const family = Config.options?.panelFamily ?? "ii"
        if (entry.family !== "shared" && entry.family !== family
                && !(entry.family === "ii" && family === "abyss"))
            return "error:requires-family-" + entry.family

        closeAll()
        currentDestination = destination
        switch (entry.surface) {
        case "sidebar-left": GlobalStates.openSidebarLeft(""); break
        case "sidebar-right":
            GlobalStates.sidebarRightRequestedWidget = entry.view
            GlobalStates.openSidebarRight("")
            break
        case "notification-center":
            if (!GlobalStates.openNotificationCenter("")) {
                currentDestination = ""
                return "error:notification-center-unavailable"
            }
            break
        case "control-panel": GlobalStates.controlPanelOpen = true; break
        case "dashboard":
            GlobalStates.dashboardPage = entry.view === "music" ? 1 : 0
            GlobalStates.dashboardOpen = true
            break
        case "media-controls": GlobalStates.mediaControlsOpen = true; break
        case "clipboard": GlobalStates.clipboardOpen = true; break
        case "cheatsheet": GlobalStates.cheatsheetOpen = true; break
        case "overview":
            GlobalStates.overviewSearchPrefix = entry.view === "actions"
                ? (Config.options?.search?.prefix?.action ?? "/")
                : entry.view === "clipboard" ? (Config.options?.search?.prefix?.clipboard ?? ";") : ""
            GlobalStates.openOverview("")
            break
        case "wallpaper-grid": GlobalStates.wallpaperSelectorOpen = true; break
        case "wallpaper-coverflow": GlobalStates.coverflowSelectorOpen = true; break
        case "tiling":
            GlobalStates.tilingOverlayPickerOpen = entry.view === "picker"
            GlobalStates.tilingOverlayOsdOpen = entry.view === "osd"
            break
        case "settings":
            GlobalStates.openSettingsPage(entry.pageIndex ?? -1)
            break
        case "waffle-search":
            requestedWaffleStartView = entry.view
            LauncherSearch.query = entry.view === "search" ? "a" : ""
            GlobalStates.searchOpen = true
            break
        case "waffle-action-center": GlobalStates.waffleActionCenterOpen = true; break
        case "waffle-notification-center": GlobalStates.waffleNotificationCenterOpen = true; break
        case "waffle-widgets": GlobalStates.waffleWidgetsOpen = true; break
        case "waffle-taskview": GlobalStates.waffleTaskViewOpen = true; break
        default: currentDestination = ""; return "error:unsupported-surface"
        }
        return "ok:" + destination
    }

    IpcHandler {
        target: "dev"
        function list(): string { return JSON.stringify(root.destinations) }
        function open(destination: string): string { return root.request(destination) }
        function close(): void { root.closeAll() }
        function current(): string { return root.currentDestination.length > 0 ? root.currentDestination : "closed" }
    }
}
