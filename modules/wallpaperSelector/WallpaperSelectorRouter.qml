pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

Scope {
    id: root
    readonly property var focusedScreen: GlobalStates.focusedScreen
    readonly property string focusedMonitorName: focusedScreen?.name ?? ""
    readonly property var defaultScreen: focusedScreen ?? GlobalStates.primaryScreen
    readonly property string defaultMonitorName: defaultScreen?.name ?? focusedMonitorName
    property string _pendingSurface: ""
    property string _pendingLauncherMode: ""

    Process {
        id: niriOutputDetector
        property string _buffer: ""
        stdout: SplitParser { onRead: data => niriOutputDetector._buffer += data + "\n" }
        onExited: (code, status) => {
            let monitorName = ""
            if (code === 0 && niriOutputDetector._buffer) {
                try { monitorName = JSON.parse(niriOutputDetector._buffer).name || "" }
                catch (error) {}
            }
            niriOutputDetector._buffer = ""
            if (!monitorName) monitorName = root.defaultMonitorName
            const surface = root._pendingSurface
            const launcherMode = root._pendingLauncherMode
            root._pendingSurface = ""
            root._pendingLauncherMode = ""
            root._openResolvedSurface(surface, monitorName, launcherMode)
        }
    }

    function _openResolvedSurface(surface: string, monitorName: string,
            launcherMode: string): void {
        if (surface === "coverflow")
            root._toggleCoverflowWithMonitor(monitorName)
        else if (surface === "launcher")
            root._commitLauncher(launcherMode, monitorName)
        else
            root._openWithMonitor(monitorName)
    }

    function _openOnFocusedMonitor(surface: string,
            launcherMode: string): void {
        if (CompositorService.isNiri) {
            if (niriOutputDetector.running)
                return
            root._pendingSurface = surface
            root._pendingLauncherMode = launcherMode
            niriOutputDetector.exec(["niri", "msg", "-j", "focused-output"])
            return
        }
        root._openResolvedSurface(surface, root.defaultMonitorName, launcherMode)
    }

    function _openWithMonitor(monitorName: string): void {
        GlobalStates.wallpaperSelectorTargetMonitor = monitorName || ""
        Config.setNestedValue("wallpaperSelector.targetMonitor", monitorName || "")
        GlobalStates.wallpaperSelectorOpen = true
    }

    function _toggleCoverflowWithMonitor(monitorName: string): void {
        GlobalStates.wallpaperSelectorOpen = false
        GlobalStates.wallpaperSelectorTargetMonitor = monitorName || ""
        Config.setNestedValue("wallpaperSelector.targetMonitor", monitorName || "")
        GlobalStates.coverflowSelectorOpen = !GlobalStates.coverflowSelectorOpen
    }

    function toggleCoverflow(): void { root.toggle() }
    function toggle(): void {
        if (GlobalStates.wallpaperLauncherOpen) {GlobalStates.wallpaperLauncherOpen=false;return}
        if (Config.options?.panelFamily==="waffle" && Wallpapers.currentSelectionTarget()==="main"
                && !(Config.options?.waffles?.background?.useMainWallpaper ?? true))
            Config.setNestedValue("wallpaperSelector.selectionTarget","waffle")
        root._openLauncher("","")
    }

    // An empty mode means "match what is on screen": opening the picker while a
    // video wallpaper is applied must land on Animated, not on Static where the
    // current wallpaper cannot even appear.
    function _resolveLauncherMode(mode: string, monitorName: string): string {
        if (mode === "animated" || mode === "static")
            return mode
        const currentPath = Wallpapers.currentWallpaperPathForTarget(
            Wallpapers.currentSelectionTarget(),
            (Config.options?.background?.multiMonitor?.enable ?? false)
                ? monitorName : "")
        return WallpaperListener.isAnimatedPath(currentPath) ? "animated" : "static"
    }

    function _commitLauncher(mode: string, monitorName: string): void {
        const nextMode = root._resolveLauncherMode(mode, monitorName)
        GlobalStates.wallpaperSelectorOpen = false
        GlobalStates.coverflowSelectorOpen = false
        // Opening the launcher makes it the active picker, so the wallpaper
        // shortcut keeps opening it instead of falling back to the grid.
        // The grid button inside the launcher is the way back out.
        Config.setNestedValue("wallpaperSelector.style", "caelestia")
        GlobalStates.wallpaperLauncherMode = nextMode
        const target = Wallpapers.currentSelectionTarget()
        GlobalStates.wallpaperSelectionTarget = target
        Config.setNestedValue("wallpaperSelector.selectionTarget", target)
        GlobalStates.wallpaperSelectorTargetMonitor = monitorName || ""
        Config.setNestedValue("wallpaperSelector.targetMonitor", monitorName || "")
        GlobalStates.wallpaperLauncherOpen = true
    }

    function _openLauncher(mode: string, requestedMonitor: string): void {
        const configuredMonitor = GlobalStates.wallpaperSelectorTargetMonitor
            || (Config.options?.wallpaperSelector?.targetMonitor ?? "")
        const monitorName = requestedMonitor || configuredMonitor
        if (monitorName)
            root._commitLauncher(mode, monitorName)
        else
            root._openOnFocusedMonitor("launcher", mode)
    }

    function openLauncher(mode: string): void {
        root._openLauncher(mode, "")
    }

    IpcHandler {
        target: "wallpaperSelector"
        function toggle(): void { root.toggle() }
        function open(): void {
            if (!GlobalStates.wallpaperSelectorOpen
                    && !GlobalStates.wallpaperLauncherOpen
                    && !GlobalStates.coverflowSelectorOpen)
                root.toggle()
        }
        function close(): void {
            GlobalStates.wallpaperSelectorOpen = false
            GlobalStates.wallpaperLauncherOpen = false
            GlobalStates.coverflowSelectorOpen = false
        }
        function openLauncher(mode: string): void { root.openLauncher(mode) }
        function toggleOnMonitor(monitorName: string): void {
            if(GlobalStates.wallpaperLauncherOpen && GlobalStates.wallpaperSelectorTargetMonitor===monitorName)
                GlobalStates.wallpaperLauncherOpen=false
            else root._openLauncher("",monitorName)
        }
        function random(): void { Wallpapers.randomFromCurrentFolder() }
        function apply(filePath: string): void {
            const cleaned = FileUtils.trimFileProtocol(String(filePath ?? "")).trim()
            if (cleaned.length === 0)
                return
            Wallpapers.select(cleaned)
        }
        function status(): string {
            return JSON.stringify({
                style: "caelestia",
                gridOpen: GlobalStates.wallpaperSelectorOpen,
                launcherOpen: GlobalStates.wallpaperLauncherOpen,
                coverflowOpen: GlobalStates.coverflowSelectorOpen,
                targetMonitor: GlobalStates.wallpaperSelectorTargetMonitor
                    || (Config.options?.wallpaperSelector?.targetMonitor ?? ""),
                focusedMonitor: root.focusedMonitorName,
                selectionTarget: Wallpapers.currentSelectionTarget(),
                multiMonitor: Config.options?.background?.multiMonitor?.enable ?? false
            })
        }
    }

    IpcHandler {
        target: "coverflowSelector"
        function toggle(): void { root.toggleCoverflow() }
        function open(): void {
            if (!GlobalStates.wallpaperLauncherOpen)
                root.toggleCoverflow()
        }
        function close(): void { GlobalStates.wallpaperLauncherOpen = false }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Item {
            GlobalShortcut { name: "wallpaperSelectorToggle"; description: "Toggle wallpaper selector"; onPressed: root.toggle() }
            GlobalShortcut { name: "wallpaperSelectorRandom"; description: "Select random wallpaper in current folder"; onPressed: Wallpapers.randomFromCurrentFolder() }
            GlobalShortcut { name: "coverflowSelectorToggle"; description: "Toggle coverflow wallpaper selector"; onPressed: root.toggleCoverflow() }
        }
    }
}
