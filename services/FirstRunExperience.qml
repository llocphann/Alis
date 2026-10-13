pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string firstRunNotifSummary: "Welcome to Alis!"
    property string firstRunNotifBody: "Hit Super+/ for a list of keybinds"
    property string defaultWallpaperPath: ""
    property bool _pendingFirstRun: false
    property bool _dockStyleNormalized: false
    property bool _markerProbeRequested: false

    function _normalizeDockStyle(): void {
        if (root._dockStyleNormalized || !Config.ready)
            return

        root._dockStyleNormalized = true
        if ((Config.options?.dock?.style ?? "panel") !== "panel")
            Config.setNestedValue("dock.style", "panel")
    }

    function load() {
        root._normalizeDockStyle()

        if (root._markerProbeRequested || listWallpapersProc.running)
            return

        root._markerProbeRequested = true
        firstRunMarker.reload()
    }

    function enableNextTime() {
        Quickshell.execDetached(["/usr/bin/rm", "-f", root.firstRunFilePath])
    }
    function disableNextTime() {
        const parentDir = root.firstRunFilePath.substring(0, root.firstRunFilePath.lastIndexOf('/'))
        Quickshell.execDetached([
            "/bin/sh",
            "-c",
            "mkdir -p -- \"$1\" && printf '%s\\n' \"$2\" > \"$3\"",
            "first-run-marker",
            parentDir,
            root.firstRunFileContent,
            root.firstRunFilePath
        ])
    }

    function handleFirstRun(): void {
        if (root.defaultWallpaperPath.length > 0)
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath])
        Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "welcome"])
    }

    function _persistAndHandleFirstRun(): void {
        if (root.defaultWallpaperPath.length > 0)
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath])

        const parentDir = root.firstRunFilePath.substring(0, root.firstRunFilePath.lastIndexOf('/'))
        const launcherPath = Quickshell.shellPath("scripts/inir")
        // Keep marker persistence and welcome launch in one process so the
        // launcher cannot win the scheduling race. The welcome still opens if
        // persistence fails; the semicolon intentionally preserves that fallback.
        Quickshell.execDetached([
            "/bin/sh",
            "-c",
            "mkdir -p -- \"$1\" && printf '%s\\n' \"$2\" > \"$3\"; exec \"$4\" welcome",
            "first-run-marker",
            parentDir,
            root.firstRunFileContent,
            root.firstRunFilePath,
            launcherPath
        ])
    }

    function _completeFirstRun(): void {
        if (listWallpapersProc._candidates.length > 0) {
            const sorted = [...listWallpapersProc._candidates].sort()
            root.defaultWallpaperPath = sorted.find(path => path.endsWith("/qs-niri.jpg"))
                ?? sorted[0]
        }
        if (root._pendingFirstRun) {
            root._persistAndHandleFirstRun()
            root._pendingFirstRun = false
        }
    }

    Connections {
        target: Config
        function onReadyChanged(): void {
            if (Config.ready)
                root._normalizeDockStyle()
        }
    }

    Process {
        id: listWallpapersProc
        property string wallDir: FileUtils.trimFileProtocol(`${Directories.assetsPath}/wallpapers`)
        property var _candidates: []
        property bool startObserved: false
        command: ["/bin/sh", "-c", `find "${wallDir}" -maxdepth 1 -type f \\( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \\) 2>/dev/null`]
        stdout: SplitParser {
            onRead: (line) => {
                const trimmed = line.trim()
                if (trimmed.length > 0)
                    listWallpapersProc._candidates.push(trimmed)
            }
        }
        onRunningChanged: {
            if (listWallpapersProc.running) {
                listWallpapersProc.startObserved = false
                listWallpapersProc._candidates = []
                root.defaultWallpaperPath = ""
                return
            }
            if (listWallpapersProc.startObserved)
                return

            console.warn("[FirstRunExperience] Failed to start wallpaper discovery")
            root._completeFirstRun()
        }
        onStarted: listWallpapersProc.startObserved = true
        onExited: (exitCode) => root._completeFirstRun()
    }

    FileView {
        id: firstRunMarker
        path: root.firstRunFilePath
        watchChanges: false
        blockLoading: true
        printErrors: false

        onLoaded: {
            if (!root._markerProbeRequested)
                return
            root._markerProbeRequested = false
            root._pendingFirstRun = false
        }

        onLoadFailed: error => {
            if (!root._markerProbeRequested)
                return
            root._markerProbeRequested = false
            root._pendingFirstRun = true
            if (!listWallpapersProc.running)
                listWallpapersProc.running = true
        }
    }
}
