pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.wallpaperLauncher

FocusScope {
    id: root
    objectName: "wallpaperLauncherContent"

    property string outputName: ""
    property string monitorName: outputName
    property bool embedded: true
    property string browseFolder: Config.options?.wallpapers?.directory ?? ""
    property string selectedColor: ""
    property bool favouritesOnly: false
    property string activeTab: GlobalStates.wallpaperLauncherMode === "animated" ? "animated" : "static"
    property string initialWallpaperPath: ""
    property var undoStack: []

    readonly property var colorPalette: [
        { id: "", label: "All", swatch: "transparent" },
        { id: "red", label: "Red", swatch: "#ef4444" },
        { id: "orange", label: "Orange", swatch: "#f97316" },
        { id: "yellow", label: "Yellow", swatch: "#eab308" },
        { id: "green", label: "Green", swatch: "#22c55e" },
        { id: "cyan", label: "Cyan", swatch: "#06b6d4" },
        { id: "blue", label: "Blue", swatch: "#3b82f6" },
        { id: "purple", label: "Purple", swatch: "#a855f7" },
        { id: "pink", label: "Pink", swatch: "#ec4899" },
        { id: "monochrome", label: "Mono", swatch: "#94a3b8" }
    ]

    readonly property var transitionOptions: [
        { value: "alisMelt", label: Translation.tr("Liquid"), icon: "water" },
        { value: "wallfx", label: Translation.tr("Outline"), icon: "draw" },
        { value: "fade", label: Translation.tr("Fade"), icon: "motion_photos_on" },
        { value: "wipe", label: Translation.tr("Wipe"), icon: "left_panel_open" },
        { value: "grow", label: Translation.tr("Grow"), icon: "filter_center_focus" },
        { value: "outer", label: Translation.tr("Outer"), icon: "blur_circular" },
        { value: "random", label: Translation.tr("Random"), icon: "casino" }
    ]

    readonly property var schemeOptions: [
        { value: "auto", label: Translation.tr("Auto"), icon: "auto_awesome" },
        { value: "scheme-tonal-spot", label: Translation.tr("Tonal Spot"), icon: "palette" },
        { value: "scheme-expressive", label: Translation.tr("Expressive"), icon: "flare" },
        { value: "scheme-fidelity", label: Translation.tr("Fidelity"), icon: "verified" },
        { value: "scheme-neutral", label: Translation.tr("Neutral"), icon: "tonality" },
        { value: "scheme-monochrome", label: Translation.tr("Monochrome"), icon: "filter_b_and_w" },
        { value: "scheme-content", label: Translation.tr("Content"), icon: "image" },
        { value: "scheme-rainbow", label: Translation.tr("Rainbow"), icon: "gradient" }
    ]

    readonly property string mode: GlobalStates.wallpaperLauncherMode
    readonly property string displayMode: mode
    readonly property var libraryEntries: mode === "animated" ? library.animatedEntries : library.staticEntries
    readonly property var entries: carousel.entries
    readonly property string selectionTarget: Wallpapers.currentSelectionTarget()
    readonly property string selectionMonitorName: (Config.options?.background?.multiMonitor?.enable ?? false) ? monitorName : ""
    readonly property string currentWallpaperPath: Wallpapers.currentWallpaperPathForTarget(selectionTarget, selectionMonitorName)
    readonly property int currentIndex: carousel.currentIndex
    readonly property int count: carousel.count
    readonly property string selectedPath: carousel.selectedPath
    readonly property bool loading: library.scanning

    readonly property real desiredDockWidth: Math.round(Math.min(1080, Math.max(820, dock.implicitWidth + 32)))
    readonly property real desiredDockHeight: Math.round(dock.implicitHeight + 4)

    implicitWidth: desiredDockWidth
    implicitHeight: desiredDockHeight
    focus: true

    signal closeRequested()

    function _extraScanRoots(): var {
        if (browseFolder)
            return []
        const candidates = []
        const defaultRoot = FileUtils.trimFileProtocol(Directories.wallpapersPath)
        const curDir = FileUtils.trimFileProtocol(FileUtils.parentDirectory(currentWallpaperPath))
        if (curDir && curDir !== defaultRoot) {
            const parentDir = FileUtils.trimFileProtocol(FileUtils.parentDirectory(curDir))
            const genericDirs = [
                "/",
                Directories.homePath,
                Directories.picturesPath,
                Directories.documentsPath,
                Directories.videosPath,
                Directories.downloadsPath,
                `${Directories.homePath}/Shared_Documents`
            ]
            const parentName = FileUtils.folderNameForPath(parentDir).toLowerCase()
            const curName = FileUtils.folderNameForPath(curDir)
            if (parentDir && !parentDir.startsWith("/tmp") && !genericDirs.includes(parentDir)
                    && (parentName.includes("wallpaper") || /^\d+[_\-\s]/.test(curName)))
                candidates.push(parentDir)
            candidates.push(curDir)
        }
        if (Wallpapers.effectiveDirectory)
            candidates.push(Wallpapers.effectiveDirectory)
        return candidates
    }

    function refreshLibrary(force = false): void {
        library.refresh(browseFolder || Directories.wallpapersPath, root._extraScanRoots(), force)
    }

    function focusPrimarySurface(): void {
        if (dock.searchInputItem)
            dock.searchInputItem.focus = false
        root.forceActiveFocus()
    }

    function setMode(nextMode: string): void {
        if (!["static", "animated"].includes(nextMode))
            return
        GlobalStates.wallpaperLauncherMode = nextMode
        root.activeTab = nextMode
        GlobalStates.wallpaperLauncherSearchText = ""
        root.focusPrimarySurface()
        Qt.callLater(carousel.syncCurrentIndexAndPreview)
    }

    function toggleColorFilter(colorId: string): void {
        if (colorId)
            library.ensureColorTags()
        root.selectedColor = (root.selectedColor === colorId) ? "" : colorId
        root.focusPrimarySurface()
    }

    function applyPathLive(path: string): void {
        if (!path)
            return
        const prev = String(root.currentWallpaperPath ?? "")
        if (prev.length > 0 && prev !== path) {
            const nextUndo = root.undoStack.slice()
            if (nextUndo[nextUndo.length - 1] !== prev)
                nextUndo.push(prev)
            root.undoStack = nextUndo
        }
        Wallpapers.commitWallpaperPreview(path)
        Wallpapers.applySelectionTarget(path, selectionTarget, Appearance.m3colors.darkmode, selectionMonitorName)
        root.focusPrimarySurface()
    }

    function applyPath(path: string): void {
        if (!path)
            return
        Wallpapers.commitWallpaperPreview(path)
        Wallpapers.applySelectionTarget(path, selectionTarget, Appearance.m3colors.darkmode, selectionMonitorName)
        GlobalStates.wallpaperLauncherOpen = false
        root.closeRequested()
    }

    function undoLastWallpaper(): void {
        if (root.undoStack.length === 0)
            return
        const nextUndo = root.undoStack.slice()
        const prev = nextUndo.pop()
        root.undoStack = nextUndo
        if (prev) {
            Wallpapers.commitWallpaperPreview(prev)
            Wallpapers.applySelectionTarget(prev, selectionTarget, Appearance.m3colors.darkmode, selectionMonitorName)
            Qt.callLater(carousel.syncCurrentIndexAndPreview)
        }
        root.focusPrimarySurface()
    }

    function pickRandomWallpaper(): void {
        const list = carousel.filteredEntries ?? []
        if (list.length === 0)
            return
        let chosenIndex = Math.floor(Math.random() * list.length)
        if (list.length > 1 && chosenIndex === carousel.currentIndex)
            chosenIndex = (chosenIndex + 1) % list.length
        const chosen = list[chosenIndex]
        if (chosen?.path) {
            carousel.currentIndex = chosenIndex
            carousel.positionViewAtIndex(chosenIndex, ListView.Contain)
            root.applyPathLive(chosen.path)
        }
    }

    function previewPath(path: string): void {
        if (!path || path === root.currentWallpaperPath) {
            Wallpapers.cancelWallpaperPreview()
            root.focusPrimarySurface()
            return
        }
        Wallpapers.previewWallpaper(path, root.selectionMonitorName)
        root.focusPrimarySurface()
    }

    function commitAndClose(): void {
        const highlighted = root.selectedPath
        if (highlighted && highlighted !== root.currentWallpaperPath) {
            Wallpapers.commitWallpaperPreview(highlighted)
            Wallpapers.applySelectionTarget(highlighted, selectionTarget, Appearance.m3colors.darkmode, selectionMonitorName)
        } else {
            Wallpapers.cancelWallpaperPreview()
        }
        GlobalStates.wallpaperLauncherOpen = false
        root.closeRequested()
    }

    function cancelAndClose(): void {
        Wallpapers.cancelWallpaperPreview()
        if (root.initialWallpaperPath.length > 0 && root.currentWallpaperPath !== root.initialWallpaperPath) {
            Wallpapers.applySelectionTarget(root.initialWallpaperPath, selectionTarget, Appearance.m3colors.darkmode, selectionMonitorName)
        }
        root.undoStack = []
        GlobalStates.wallpaperLauncherOpen = false
        root.closeRequested()
    }

    function handleEscape(): bool {
        const searchField = dock.searchInputItem
        if (searchField && searchField.activeFocus && searchField.text.length > 0) {
            searchField.text = ""
            root.focusPrimarySurface()
            return true
        }
        Wallpapers.cancelWallpaperPreview()
        root.focusPrimarySurface()
        GlobalStates.wallpaperLauncherOpen = false
        root.closeRequested()
        return true
    }

    function moveSelection(delta: int): void {
        carousel.moveSelection(delta)
    }

    function activateCurrent(): void {
        carousel.activateCurrent()
    }

    function openGrid(): void {
        Wallpapers.cancelWallpaperPreview()
        GlobalStates.wallpaperLauncherOpen = false
        GlobalStates.wallpaperSelectorOpen = true
    }

    function statusJson(): string {
        return JSON.stringify({
            open: GlobalStates.wallpaperLauncherOpen,
            style: "abyss-dock",
            mode: mode,
            index: currentIndex,
            count: count,
            path: selectedPath,
            target: selectionTarget,
            monitor: selectionMonitorName,
            previewPath: Wallpapers.internalPreviewPath,
            previewMonitor: Wallpapers.internalPreviewMonitor,
            awwwPreview: AwwwBackend.previewActive
        })
    }

    IpcHandler {
        target: "wallpaperLauncher"
        enabled: root.visible
        function next(): void { root.moveSelection(1) }
        function previous(): void { root.moveSelection(-1) }
        function applyCurrent(): void { root.activateCurrent() }
        function status(): string { return root.statusJson() }
    }

    Timer {
        id: focusDeferTimer
        interval: 0
        repeat: false
        property bool alsoSyncCarousel: false
        onTriggered: {
            root.focusPrimarySurface()
            if (alsoSyncCarousel) {
                alsoSyncCarousel = false
                carousel.syncCurrentIndexAndPreview()
            }
        }
    }

    function _beginSession(): void {
        root.initialWallpaperPath = String(root.currentWallpaperPath ?? "")
        root.undoStack = []
        if (GlobalStates.wallpaperLauncherMode === "animated" && root.activeTab === "static")
            root.activeTab = "animated"
        else if (GlobalStates.wallpaperLauncherMode === "static" && root.activeTab === "animated")
            root.activeTab = "static"
        root.refreshLibrary(true)
        focusDeferTimer.alsoSyncCarousel = true
        focusDeferTimer.restart()
    }

    onBrowseFolderChanged: if (GlobalStates.wallpaperLauncherOpen) refreshLibrary(true)
    onVisibleChanged: if (visible) focusDeferTimer.restart()
    onEnabledChanged: if (enabled) focusDeferTimer.restart()
    Component.onCompleted: {
        if (GlobalStates.wallpaperLauncherOpen)
            root._beginSession()
    }
    Component.onDestruction: {
        Wallpapers.cancelWallpaperPreview()
        GlobalStates.setSettingsNativeDialogVisible("wallpaperLauncherFolder", false)
    }

    Connections {
        target: GlobalStates
        function onWallpaperLauncherOpenChanged(): void {
            if (GlobalStates.wallpaperLauncherOpen)
                root._beginSession()
            else
                Wallpapers.cancelWallpaperPreview()
        }
        function onWallpaperLauncherModeChanged(): void {
            if (["static", "animated"].includes(GlobalStates.wallpaperLauncherMode)
                    && (root.activeTab === "static" || root.activeTab === "animated")) {
                root.activeTab = GlobalStates.wallpaperLauncherMode
            }
        }
    }

    FolderDialog {
        id: folderPicker
        title: Translation.tr("Wallpaper folder")
        currentFolder: root.browseFolder ? "file://" + root.browseFolder : "file://" + Directories.wallpapersPath
        onAccepted: {
            const chosen = FileUtils.trimFileProtocol(String(selectedFolder))
            root.browseFolder = chosen
            Config.setNestedValue("wallpapers.directory", chosen)
        }
        onVisibleChanged: GlobalStates.setSettingsNativeDialogVisible("wallpaperLauncherFolder", visible)
    }

    WallpaperLibrary {
        id: library
    }

    component QuickActionPill: Rectangle {
        id: pill
        property string icon: ""
        property string label: ""
        property string tooltipText: ""
        property bool active: false
        signal clicked()

        implicitHeight: 30
        height: 30
        implicitWidth: pill.label.length > 0 ? Math.ceil(pillRow.implicitWidth + 18) : 30
        width: implicitWidth
        radius: 15
        opacity: pill.enabled ? 1.0 : 0.38
        color: pill.active
            ? Qt.alpha(Appearance.colors.colPrimary, 0.24)
            : (pillMouse.containsMouse && pill.enabled
                ? Appearance.colors.colLayer2Hover
                : Qt.alpha(Appearance.colors.colLayer2, 0.56))
        border.width: 1
        border.color: pill.active
            ? Qt.alpha(Appearance.colors.colPrimary, 0.62)
            : Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: (pill.icon.length > 0 && pill.label.length > 0) ? 5 : 0
            MaterialSymbol {
                visible: pill.icon.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                fill: pill.active && pill.icon === "favorite" ? 1 : 0
                iconSize: 16
                color: pill.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: pill.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: Text.AlignVCenter
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: pill.active ? Font.DemiBold : Font.Medium
                color: pill.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            enabled: pill.enabled
            hoverEnabled: true
            cursorShape: pill.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: pill.clicked()
        }

        StyledToolTip {
            position: "top"
            extraVisibleCondition: pillMouse.containsMouse && pill.tooltipText.length > 0
            text: pill.tooltipText
        }
    }

    AbyssCustomizationDock {
        id: dock
        anchors.fill: parent
        embeddedSurface: root.embedded
        trayExpanded: true
        trayHeight: 118
        showUndo: true
        canUndo: root.undoStack.length > 0
        undoObjectName: "wallpaperUndoButton"
        showRedo: false
        showSearch: root.activeTab === "static" || root.activeTab === "animated"
        searchObjectName: "wallpaperSearch"
        searchPlaceholder: Translation.tr("Search wallpapers...")
        searchText: GlobalStates.wallpaperLauncherSearchText
        showCancel: true
        cancelObjectName: "wallpaperCancelButton"
        doneObjectName: "wallpaperDoneButton"
        doneLabel: Translation.tr("Done")
        activeTab: root.activeTab
        autoSwitchTab: false
        tabs: [
            {
                key: "static",
                label: Translation.tr("Static"),
                icon: "image",
                badge: (library.staticEntries?.length ?? 0) > 0 ? String(library.staticEntries.length) : ""
            },
            {
                key: "animated",
                label: Translation.tr("Animated"),
                icon: "movie",
                badge: (library.animatedEntries?.length ?? 0) > 0 ? String(library.animatedEntries.length) : ""
            },
            {
                key: "color",
                label: Translation.tr("Color & Theme"),
                icon: "palette",
                badge: root.selectedColor.length > 0 ? "1" : ""
            },
            {
                key: "effects",
                label: Translation.tr("Effects"),
                icon: "auto_awesome"
            }
        ]

        onTabClicked: key => {
            if (key === "static" || key === "animated") {
                root.setMode(key)
            } else {
                if (key === "color")
                    library.ensureColorTags()
                root.activeTab = key
                root.focusPrimarySurface()
            }
        }
        onSearchEdited: text => {
            GlobalStates.wallpaperLauncherSearchText = text
        }
        onUndoClicked: root.undoLastWallpaper()
        onCancelClicked: root.cancelAndClose()
        onDoneClicked: root.commitAndClose()

        trailingControls: [
            QuickActionPill {
                objectName: "wallpaperFavouritesFilter"
                icon: "favorite"
                active: root.favouritesOnly
                tooltipText: root.favouritesOnly
                    ? Translation.tr("Showing favourites only")
                    : Translation.tr("Filter favourite wallpapers")
                onClicked: {
                    root.favouritesOnly = !root.favouritesOnly
                    root.focusPrimarySurface()
                }
            },
            QuickActionPill {
                objectName: "wallpaperRandom"
                icon: "casino"
                enabled: carousel.count > 0
                tooltipText: Translation.tr("Pick random wallpaper")
                onClicked: root.pickRandomWallpaper()
            },
            QuickActionPill {
                objectName: "wallpaperFolder"
                icon: "folder_open"
                active: root.browseFolder.length > 0
                tooltipText: root.browseFolder.length > 0
                    ? FileUtils.folderNameForPath(root.browseFolder)
                    : Translation.tr("Choose wallpaper folder")
                onClicked: folderPicker.open()
            },
            QuickActionPill {
                objectName: "wallpaperOpenGrid"
                icon: "grid_view"
                tooltipText: Translation.tr("Open full wallpaper browser")
                onClicked: root.openGrid()
            },
            QuickActionPill {
                objectName: "wallpaperRefresh"
                icon: "refresh"
                enabled: !root.loading
                tooltipText: Translation.tr("Refresh wallpaper library")
                onClicked: root.refreshLibrary(true)
            }
        ]

        // ── Tier 2a: Horizontal Wallpaper Gallery (Static / Animated) ──
        Item {
            id: galleryPane
            anchors.fill: parent
            visible: root.activeTab === "static" || root.activeTab === "animated"

            ListView {
                id: carousel
                objectName: "wallpaperCarousel"
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 720
                highlightMoveDuration: Appearance.animationsEnabled ? 180 : 0

                property var entries: root.libraryEntries
                property var fallbackEntries: (Config.options?.background?.enableAnimation ?? true)
                    ? (root.mode === "animated" ? library.staticEntries : library.animatedEntries)
                    : []
                property string searchText: GlobalStates.wallpaperLauncherSearchText
                property string selectedColor: root.selectedColor
                property bool favouritesOnly: root.favouritesOnly
                property var colorTagsByPath: library.colorTagsByPath
                property string currentWallpaperPath: root.currentWallpaperPath
                property string monitorName: root.selectionMonitorName
                property string _effectiveSearchText: searchText
                property int _lastFavouritesRevSeen: Wallpapers.favouritesRevision
                property real _wheelAccum: 0
                property double _lastWheelStepMs: 0
                readonly property real cardWidth: Math.round(168 * Appearance.fontSizeScale)
                readonly property real cardHeight: Math.max(96, carousel.height - 2)

                Timer {
                    id: searchDebounce
                    interval: 80
                    repeat: false
                    onTriggered: carousel._effectiveSearchText = carousel.searchText
                }

                readonly property var filteredEntries: {
                    const src = carousel.entries ?? []
                    const query = carousel._effectiveSearchText.trim().toLowerCase()
                    const color = carousel.selectedColor.trim().toLowerCase()
                    const favOnly = carousel.favouritesOnly
                    if (!query && !color && !favOnly)
                        return src
                    let favDb = null
                    if (favOnly) {
                        void Wallpapers.favouritesRevision
                        favDb = Wallpapers.favouritesDb ?? {}
                    }
                    const tagMap = carousel.colorTagsByPath ?? {}
                    const tokens = query ? query.split(/\s+/).filter(Boolean) : []
                    const matchesEntry = entry => {
                        if (favOnly) {
                            const p = entry.path ?? ""
                            const n = entry.name ?? ""
                            if (!favDb[p] && !favDb[n])
                                return false
                        }
                        if (tokens.length > 0) {
                            const haystack = entry.searchKey ?? `${entry.relativePath ?? ""} ${entry.name ?? ""} ${entry.kind ?? ""}`.toLowerCase()
                            for (let i = 0; i < tokens.length; ++i) {
                                if (!haystack.includes(tokens[i]))
                                    return false
                            }
                        }
                        if (color) {
                            const tags = tagMap[entry.path] ?? []
                            if (!Array.isArray(tags) || !tags.includes(color))
                                return false
                        }
                        return true
                    }
                    const primary = src.filter(matchesEntry)
                    if ((!query && !favOnly) || !carousel.fallbackEntries || carousel.fallbackEntries.length === 0)
                        return primary
                    const seen = new Set(primary.map(e => e.path))
                    const secondary = carousel.fallbackEntries.filter(e => !seen.has(e.path) && matchesEntry(e))
                    return primary.concat(secondary)
                }

                readonly property string selectedPath: {
                    const list = carousel.filteredEntries ?? []
                    if (list.length === 0)
                        return ""
                    const safeIdx = Math.min(Math.max(0, carousel.currentIndex), list.length - 1)
                    return list[safeIdx]?.path ?? ""
                }

                model: carousel.filteredEntries
                onFilteredEntriesChanged: carousel.syncCurrentIndexAndPreview()

                function syncCurrentIndex(): void {
                    const list = carousel.filteredEntries ?? []
                    if (list.length === 0) {
                        carousel.currentIndex = 0
                        carousel._lastFavouritesRevSeen = Wallpapers.favouritesRevision
                        return
                    }
                    if (carousel.favouritesOnly && carousel._lastFavouritesRevSeen !== Wallpapers.favouritesRevision) {
                        carousel._lastFavouritesRevSeen = Wallpapers.favouritesRevision
                        carousel.currentIndex = Math.min(Math.max(0, carousel.currentIndex), list.length - 1)
                        return
                    }
                    carousel._lastFavouritesRevSeen = Wallpapers.favouritesRevision
                    const idx = list.findIndex(entry => entry.path === carousel.currentWallpaperPath)
                    carousel.currentIndex = Math.max(0, idx)
                    carousel.positionViewAtIndex(carousel.currentIndex, ListView.Contain)
                }

                function syncCurrentIndexAndPreview(): void {
                    carousel.syncCurrentIndex()
                    previewDebounce.restart()
                }

                function moveSelection(delta: int): void {
                    const total = carousel.count
                    if (total <= 0)
                        return
                    const base = carousel.currentIndex < 0 ? 0 : carousel.currentIndex
                    const next = ((base + delta) % total + total) % total
                    carousel.currentIndex = next
                    carousel.positionViewAtIndex(next, ListView.Contain)
                }

                function activateCurrent(): void {
                    const entry = carousel.filteredEntries?.[carousel.currentIndex]
                    if (entry?.path)
                        root.applyPath(entry.path)
                }

                function previewCurrent(): void {
                    if (!GlobalStates.wallpaperLauncherOpen)
                        return
                    const entry = carousel.filteredEntries?.[carousel.currentIndex]
                    if (!entry?.path || entry.path === carousel.currentWallpaperPath) {
                        Wallpapers.cancelWallpaperPreview()
                        return
                    }
                    Wallpapers.previewWallpaper(entry.path, carousel.monitorName)
                }

                Timer {
                    id: syncIndexTimer
                    interval: 0
                    repeat: false
                    onTriggered: carousel.syncCurrentIndexAndPreview()
                }

                Component.onCompleted: {
                    carousel._effectiveSearchText = carousel.searchText
                    syncIndexTimer.restart()
                }
                onCurrentWallpaperPathChanged: syncIndexTimer.restart()
                onSearchTextChanged: {
                    if (carousel.searchText.trim().length === 0 || (carousel.entries?.length ?? 0) <= 200) {
                        searchDebounce.stop()
                        carousel._effectiveSearchText = carousel.searchText
                        syncIndexTimer.restart()
                    } else {
                        searchDebounce.restart()
                    }
                }
                onSelectedColorChanged: syncIndexTimer.restart()
                onFavouritesOnlyChanged: syncIndexTimer.restart()
                onCurrentIndexChanged: previewDebounce.restart()

                Timer {
                    id: previewDebounce
                    interval: carousel.entries === null ? 180
                        : ((carousel.filteredEntries?.[carousel.currentIndex]?.kind ?? "static") === "static" ? 160 : 450)
                    onTriggered: carousel.previewCurrent()
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const dx = Number(event.angleDelta.x ?? 0)
                        const dy = Number(event.angleDelta.y ?? 0)
                        const primary = Math.abs(dx) >= Math.abs(dy) ? dx : dy
                        if (primary === 0)
                            return
                        const stepPx = primary * 1.15
                        carousel.contentX = Math.max(
                            0,
                            Math.min(Math.max(0, carousel.contentWidth - carousel.width), carousel.contentX - stepPx)
                        )
                        event.accepted = true
                    }
                }

                delegate: Item {
                    id: cardDelegate
                    required property var modelData
                    required property int index

                    readonly property bool isCurrent: index === carousel.currentIndex
                    readonly property bool isApplied: modelData.path === carousel.currentWallpaperPath
                    readonly property bool isFavourite: {
                        void Wallpapers.favouritesRevision
                        return Wallpapers.isFavourite(cardDelegate.modelData.path)
                    }

                    width: carousel.cardWidth
                    height: carousel.cardHeight

                    Rectangle {
                        id: cardFrame
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 4
                        height: Math.max(66, parent.height - 24)
                        radius: 13
                        color: Qt.alpha(Appearance.colors.colLayer2, 0.72)
                        border.width: cardDelegate.isCurrent || cardDelegate.isApplied ? 2 : 1
                        border.color: cardDelegate.isApplied
                            ? Appearance.colors.colPrimary
                            : (cardDelegate.isCurrent
                                ? Qt.alpha(Appearance.colors.colPrimary, 0.85)
                                : (cardMouse.containsMouse
                                    ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.55)
                                    : Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)))
                        scale: cardMouse.pressed ? 0.96 : (cardMouse.containsMouse || cardDelegate.isCurrent ? 1.02 : 1.0)

                        Behavior on scale {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: cardFrame.border.width
                            radius: Math.max(4, cardFrame.radius - cardFrame.border.width)
                            color: Qt.alpha(Appearance.colors.colLayer2, 0.85)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: cardDelegate.modelData.kind !== "static" ? "movie" : "image"
                                iconSize: 26
                                color: Appearance.colors.colSubtext
                            }

                            ThumbnailImage {
                                id: thumb
                                objectName: "wallpaperCardImage"
                                anchors.fill: parent
                                sourcePath: cardDelegate.modelData.path
                                sourceSize.width: Math.max(1, Math.ceil(cardFrame.width * 2))
                                sourceSize.height: Math.max(1, Math.ceil(cardFrame.height * 2))
                                fillMode: Image.PreserveAspectCrop
                                generateThumbnail: true
                                mipmap: false
                            }

                            // Applied badge
                            Rectangle {
                                visible: cardDelegate.isApplied
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                width: 22
                                height: 22
                                radius: 11
                                color: Appearance.colors.colPrimary

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "check"
                                    iconSize: 15
                                    color: Appearance.colors.colOnPrimary
                                }
                            }

                            // Animated badge
                            Rectangle {
                                visible: cardDelegate.modelData.kind !== "static" && !cardDelegate.isApplied
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                width: 22
                                height: 22
                                radius: 11
                                color: Qt.alpha(Appearance.colors.colLayer1, 0.78)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "motion_photos_on"
                                    iconSize: 14
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            // Favourite toggle badge
                            Rectangle {
                                id: favBadge
                                objectName: "wallpaperCardFavourite"
                                visible: cardDelegate.isFavourite || cardDelegate.isCurrent || cardMouse.containsMouse || favMouse.containsMouse
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 6
                                width: 22
                                height: 22
                                radius: 11
                                color: cardDelegate.isFavourite
                                    ? Appearance.colors.colPrimary
                                    : Qt.alpha(Appearance.colors.colLayer1, 0.76)
                                border.width: 1
                                border.color: cardDelegate.isFavourite
                                    ? "transparent"
                                    : Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "favorite"
                                    fill: cardDelegate.isFavourite ? 1 : 0
                                    iconSize: 13
                                    color: cardDelegate.isFavourite
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }

                    StyledText {
                        objectName: "wallpaperCardLabel"
                        anchors.top: cardFrame.bottom
                        anchors.topMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: String(cardDelegate.modelData.name ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: cardDelegate.isCurrent || cardDelegate.isApplied ? Font.DemiBold : Font.Normal
                        color: cardDelegate.isCurrent || cardDelegate.isApplied
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnLayer1
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            carousel.currentIndex = cardDelegate.index
                            previewDebounce.stop()
                            root.previewPath(cardDelegate.modelData.path)
                        }
                        onDoubleClicked: {
                            carousel.currentIndex = cardDelegate.index
                            previewDebounce.stop()
                            root.applyPath(cardDelegate.modelData.path)
                        }
                    }

                    MouseArea {
                        id: favMouse
                        x: cardFrame.x + 8
                        y: cardFrame.y + 8
                        width: 24
                        height: 24
                        z: 3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            mouse.accepted = true
                            Wallpapers.toggleFavourite(cardDelegate.modelData.path)
                        }
                    }
                }
            }

            LoadingText {
                anchors.centerIn: parent
                visible: carousel.count === 0 && root.loading
            }

            Row {
                anchors.centerIn: parent
                spacing: 8
                visible: carousel.count === 0 && !root.loading

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("No matching wallpapers")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                QuickActionPill {
                    visible: root.selectedColor.length > 0 || root.favouritesOnly || GlobalStates.wallpaperLauncherSearchText.length > 0
                    icon: "filter_alt_off"
                    label: Translation.tr("Clear filters")
                    onClicked: {
                        root.selectedColor = ""
                        root.favouritesOnly = false
                        GlobalStates.wallpaperLauncherSearchText = ""
                        root.focusPrimarySurface()
                    }
                }
            }
        }

        // ── Tier 2b: Color Filter & Matugen Palette Theme ──
        ColumnLayout {
            id: colorPane
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 10
            visible: root.activeTab === "color"

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Color filter")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                Row {
                    id: colorFilterBar
                    objectName: "wallpaperColorFilterBar"
                    spacing: 6

                    Repeater {
                        model: root.colorPalette
                        delegate: Rectangle {
                            id: swatchItem
                            required property var modelData
                            readonly property bool isAll: modelData.id === ""
                            readonly property bool active: root.selectedColor === modelData.id
                            objectName: "wallpaperColorSwatch_" + (modelData.id || "all")

                            width: isAll ? 42 : 24
                            height: 24
                            radius: 12
                            color: isAll
                                ? (active ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colLayer2, 0.72))
                                : modelData.swatch
                            border.width: active ? 2 : 1
                            border.color: active
                                ? Appearance.colors.colOnLayer1
                                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)

                            StyledText {
                                anchors.centerIn: parent
                                visible: swatchItem.isAll
                                text: Translation.tr("All")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: swatchItem.active ? Font.DemiBold : Font.Medium
                                color: swatchItem.active
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer1
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !swatchItem.isAll && swatchItem.active
                                text: "check"
                                iconSize: 13
                                color: "#ffffff"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.toggleColorFilter(swatchItem.modelData.id)
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                QuickActionPill {
                    visible: root.selectedColor.length > 0
                    icon: "visibility"
                    label: Translation.tr("Show %1 matches").arg(carousel.count)
                    active: true
                    onClicked: {
                        root.activeTab = GlobalStates.wallpaperLauncherMode === "animated" ? "animated" : "static"
                        root.focusPrimarySurface()
                    }
                }

                QuickActionPill {
                    icon: Appearance.m3colors.darkmode ? "dark_mode" : "light_mode"
                    label: Appearance.m3colors.darkmode ? Translation.tr("Dark") : Translation.tr("Light")
                    active: !Appearance.m3colors.darkmode
                    tooltipText: Translation.tr("Toggle Dark / Light palette mode")
                    onClicked: {
                        MaterialThemeLoader.setDarkMode(!Appearance.m3colors.darkmode)
                        root.focusPrimarySurface()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Palette")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    contentWidth: schemeRow.implicitWidth
                    contentHeight: 32
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: schemeRow
                        height: parent.height
                        spacing: 6

                        Repeater {
                            model: root.schemeOptions
                            delegate: QuickActionPill {
                                required property var modelData
                                readonly property string currentScheme: Config.options?.appearance?.palette?.type ?? "auto"
                                icon: modelData.icon ?? ""
                                label: modelData.label
                                active: currentScheme === modelData.value
                                onClicked: {
                                    Config.setNestedValue("appearance.palette.type", modelData.value)
                                    if (!ThemeService.isAutoTheme) {
                                        const hex = MaterialThemeLoader.colorToHex(Appearance.m3colors.m3primary)
                                        const modeStr = Appearance.m3colors.darkmode ? "dark" : "light"
                                        MaterialThemeLoader.applySchemeVariant(hex, modelData.value, modeStr)
                                    } else if (root.currentWallpaperPath) {
                                        Wallpapers.applySelectionTarget(
                                            root.currentWallpaperPath,
                                            root.selectionTarget,
                                            Appearance.m3colors.darkmode,
                                            root.selectionMonitorName
                                        )
                                    }
                                    root.focusPrimarySurface()
                                }
                            }
                        }
                    }
                }

                QuickActionPill {
                    icon: "contrast"
                    label: Translation.tr("Auto mode")
                    active: Config.options?.appearance?.wallpaperTheming?.autoDarkLightMode ?? false
                    tooltipText: Translation.tr("Automatically choose light or dark mode from wallpaper brightness")
                    onClicked: {
                        Config.setNestedValue(
                            "appearance.wallpaperTheming.autoDarkLightMode",
                            !(Config.options?.appearance?.wallpaperTheming?.autoDarkLightMode ?? false)
                        )
                        root.focusPrimarySurface()
                    }
                }
            }
        }

        // ── Tier 2c: Wallpaper Transitions & Effects ──
        ColumnLayout {
            id: effectsPane
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 10
            visible: root.activeTab === "effects"

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Transition")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                QuickActionPill {
                    icon: (Config.options?.background?.transition?.enable ?? true) ? "motion_photos_on" : "motion_photos_off"
                    label: (Config.options?.background?.transition?.enable ?? true) ? Translation.tr("On") : Translation.tr("Off")
                    active: Config.options?.background?.transition?.enable ?? true
                    onClicked: {
                        Config.setNestedValue(
                            "background.transition.enable",
                            !(Config.options?.background?.transition?.enable ?? true)
                        )
                        root.focusPrimarySurface()
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    contentWidth: transitionRow.implicitWidth
                    contentHeight: 32
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    enabled: Config.options?.background?.transition?.enable ?? true
                    opacity: enabled ? 1.0 : 0.42

                    Row {
                        id: transitionRow
                        height: parent.height
                        spacing: 6

                        Repeater {
                            model: root.transitionOptions
                            delegate: QuickActionPill {
                                required property var modelData
                                readonly property string rawActiveTransition: Config.options?.background?.transition?.type ?? "alisMelt"
                                readonly property string activeTransition: rawActiveTransition === "inirMelt" ? "alisMelt" : rawActiveTransition
                                icon: modelData.icon
                                label: modelData.label
                                active: activeTransition === modelData.value
                                onClicked: {
                                    Config.setNestedValue("background.transition.type", modelData.value)
                                    if (modelData.value === "wallfx")
                                        Wallpapers.refreshWallfxStatus()
                                    root.focusPrimarySurface()
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Options")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                QuickActionPill {
                    icon: "movie"
                    label: Translation.tr("Animated wallpapers")
                    active: Config.options?.background?.enableAnimation ?? true
                    onClicked: {
                        Config.setNestedValue(
                            "background.enableAnimation",
                            !(Config.options?.background?.enableAnimation ?? true)
                        )
                        root.focusPrimarySurface()
                    }
                }

                QuickActionPill {
                    icon: "blur_on"
                    label: Translation.tr("Wallpaper blur")
                    active: Config.options?.abyss?.effects?.blur?.enabled ?? true
                    onClicked: {
                        Config.setNestedValue(
                            "abyss.effects.blur.enabled",
                            !(Config.options?.abyss?.effects?.blur?.enabled ?? true)
                        )
                        root.focusPrimarySurface()
                    }
                }

                QuickActionPill {
                    icon: "monitor"
                    label: Translation.tr("Per-monitor wallpaper")
                    active: Config.options?.background?.multiMonitor?.enable ?? false
                    onClicked: {
                        Config.setNestedValue(
                            "background.multiMonitor.enable",
                            !(Config.options?.background?.multiMonitor?.enable ?? false)
                        )
                        root.focusPrimarySurface()
                    }
                }

                QuickActionPill {
                    icon: "aspect_ratio"
                    label: Translation.tr("Shrink desktop stage")
                    active: Config.options?.abyss?.editStage?.wallpaperPreview ?? true
                    enabled: Config.options?.abyss?.editStage?.enable ?? true
                    onClicked: {
                        Config.setNestedValue(
                            "abyss.editStage.wallpaperPreview",
                            !(Config.options?.abyss?.editStage?.wallpaperPreview ?? true)
                        )
                        root.focusPrimarySurface()
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    Keys.onPressed: event => {
        const searchField = dock.searchInputItem
        const searchFocused = Boolean(searchField && searchField.activeFocus)
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const alt = (event.modifiers & Qt.AltModifier) !== 0
        const keyText = String(event.text ?? "").toLowerCase()

        if (event.key === Qt.Key_Escape) {
            root.handleEscape()
            event.accepted = true
        } else if (searchFocused && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.activateCurrent()
            event.accepted = true
        } else if (searchFocused && event.key === Qt.Key_Down) {
            root.moveSelection(1)
            root.focusPrimarySurface()
            event.accepted = true
        } else if (searchFocused && event.key === Qt.Key_Up) {
            root.moveSelection(-1)
            root.focusPrimarySurface()
            event.accepted = true
        } else if ((ctrl && ((Qt.Key_F !== undefined && event.key === Qt.Key_F) || keyText === "f"))
                || (!searchFocused && !ctrl && !alt && ((Qt.Key_Slash !== undefined && event.key === Qt.Key_Slash) || event.text === "/"))) {
            if (root.activeTab !== "static" && root.activeTab !== "animated")
                root.activeTab = GlobalStates.wallpaperLauncherMode === "animated" ? "animated" : "static"
            if (searchField)
                searchField.forceActiveFocus()
            event.accepted = true
        } else if (ctrl && ((Qt.Key_Z !== undefined && event.key === Qt.Key_Z) || keyText === "z")) {
            root.undoLastWallpaper()
            event.accepted = true
        } else if (ctrl && ((Qt.Key_D !== undefined && event.key === Qt.Key_D) || keyText === "d")) {
            if (root.selectedPath)
                Wallpapers.toggleFavourite(root.selectedPath)
            event.accepted = true
        } else if (!searchFocused && !ctrl && !alt
                && (event.key === Qt.Key_Left || event.key === Qt.Key_Up
                    || (Qt.Key_H !== undefined && (event.key === Qt.Key_H || event.key === Qt.Key_K)))) {
            root.moveSelection(-1)
            event.accepted = true
        } else if (!searchFocused && !ctrl && !alt
                && (event.key === Qt.Key_Right || event.key === Qt.Key_Down
                    || (Qt.Key_L !== undefined && (event.key === Qt.Key_L || event.key === Qt.Key_J)))) {
            root.moveSelection(1)
            event.accepted = true
        } else if (!searchFocused && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.activateCurrent()
            event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.setMode(GlobalStates.wallpaperLauncherMode === "static" ? "animated" : "static")
            event.accepted = true
        } else if (!searchFocused && !ctrl && !alt && event.text && event.text.length === 1 && event.text >= " ") {
            if (root.activeTab !== "static" && root.activeTab !== "animated")
                root.activeTab = GlobalStates.wallpaperLauncherMode === "animated" ? "animated" : "static"
            if (searchField) {
                searchField.forceActiveFocus()
                searchField.text += event.text
            }
            event.accepted = true
        }
    }
}
