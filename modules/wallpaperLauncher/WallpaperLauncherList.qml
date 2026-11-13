pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

PathView {
    id: root

    required property var entries
    property var fallbackEntries: []
    required property string searchText
    required property string currentWallpaperPath
    required property string monitorName
    property string selectedColor: ""
    property bool favouritesOnly: false
    property var colorTagsByPath: ({})
    property int maxVisibleItems: 5
    property real cardWidth: Math.round(240 * Appearance.fontSizeScale)
    property real cardHeight: Math.round(cardWidth * 9 / 16) + 40
    property real _wheelAccum: 0
    property double _lastWheelStepMs: 0
    property string _effectiveSearchText: searchText
    property int _lastFavouritesRevSeen: Wallpapers.favouritesRevision

    Timer {
        id: searchDebounce
        interval: 80
        repeat: false
        onTriggered: root._effectiveSearchText = root.searchText
    }

    signal applyRequested(string path)

    readonly property real itemWidth: cardWidth * .8
    readonly property var filteredEntries: {
        const query = _effectiveSearchText.trim().toLowerCase()
        const color = selectedColor.trim().toLowerCase()
        const favOnly = favouritesOnly
        if (!query && !color && !favOnly) return entries
        let favDb = null
        if (favOnly) {
            void Wallpapers.favouritesRevision
            favDb = Wallpapers.favouritesDb ?? {}
        }
        const tagMap = colorTagsByPath ?? {}
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
                for (let i = 0; i < tokens.length; i++) {
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
        const primary = entries.filter(matchesEntry)
        if ((!query && !favOnly) || !fallbackEntries || fallbackEntries.length === 0)
            return primary
        const seen = new Set(primary.map(e => e.path))
        const secondary = fallbackEntries.filter(e => !seen.has(e.path) && matchesEntry(e))
        return primary.concat(secondary)
    }
    readonly property int visibleItems: {
        let visible = Math.min(maxVisibleItems, filteredEntries.length)
        if (visible === 2) return 1
        if (visible > 1 && visible % 2 === 0) visible--
        return visible
    }
    readonly property string selectedPath: {
        const list = filteredEntries ?? []
        if (list.length === 0) return ""
        const safeIdx = Math.min(Math.max(0, currentIndex), list.length - 1)
        return list[safeIdx]?.path ?? ""
    }

    implicitWidth: itemWidth * Math.max(1, visibleItems)
    implicitHeight: cardHeight
    pathItemCount: visibleItems
    cacheItemCount: 4
    interactive: count > 1
    snapMode: PathView.SnapToItem
    maximumFlickVelocity: 1100
    flickDeceleration: 2400
    highlightMoveDuration: Appearance.animationsEnabled ? 220 : 0
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange

    model: root.filteredEntries
    onFilteredEntriesChanged: root.syncCurrentIndexAndPreview()

    function syncCurrentIndex(): void {
        const list = root.filteredEntries ?? []
        if (list.length === 0) {
            root.currentIndex = 0
            root._lastFavouritesRevSeen = Wallpapers.favouritesRevision
            return
        }
        if (root.favouritesOnly && root._lastFavouritesRevSeen !== Wallpapers.favouritesRevision) {
            root._lastFavouritesRevSeen = Wallpapers.favouritesRevision
            root.currentIndex = Math.min(Math.max(0, root.currentIndex), list.length - 1)
            return
        }
        root._lastFavouritesRevSeen = Wallpapers.favouritesRevision
        const index = list.findIndex(entry => entry.path === root.currentWallpaperPath)
        root.currentIndex = Math.max(0, index)
    }

    function syncCurrentIndexAndPreview(): void {
        root.syncCurrentIndex()
        previewDebounce.restart()
    }

    function moveSelection(delta: int): void {
        if (count <= 0) return
        const steps = Math.abs(delta)
        for (let step = 0; step < steps; step++) {
            if (delta > 0)
                incrementCurrentIndex()
            else if (delta < 0)
                decrementCurrentIndex()
        }
    }

    function activateCurrent(): void {
        const entry = root.filteredEntries?.[currentIndex]
        if (entry?.path) root.applyRequested(entry.path)
    }

    // Show the highlighted entry on the desktop. Wallpapers routes static to
    // awww and animated to the internal renderer, so the preview always uses
    // the same engine that will render the wallpaper once applied.
    function previewCurrent(): void {
        // The surface is retained while closed, and the applied wallpaper can
        // change from elsewhere. Never repaint the desktop when not open.
        if (!GlobalStates.wallpaperLauncherOpen) return
        const entry = root.filteredEntries?.[currentIndex]
        if (!entry?.path || entry.path === root.currentWallpaperPath) {
            // Back on the applied wallpaper — drop the preview instead of
            // repainting what is already on screen.
            Wallpapers.cancelWallpaperPreview()
            return
        }
        Wallpapers.previewWallpaper(entry.path, root.monitorName)
    }

    Component.onCompleted: {
        root._effectiveSearchText = root.searchText
        Qt.callLater(syncCurrentIndexAndPreview)
    }
    Component.onDestruction: Wallpapers.cancelWallpaperPreview()
    onCurrentWallpaperPathChanged: Qt.callLater(syncCurrentIndexAndPreview)
    onSearchTextChanged: {
        if (searchText.trim().length === 0 || (entries?.length ?? 0) <= 200) {
            searchDebounce.stop()
            root._effectiveSearchText = searchText
            Qt.callLater(syncCurrentIndexAndPreview)
        } else {
            searchDebounce.restart()
        }
    }
    onSelectedColorChanged: Qt.callLater(syncCurrentIndexAndPreview)
    onFavouritesOnlyChanged: Qt.callLater(syncCurrentIndexAndPreview)
    // The desktop always shows the highlighted card, however the highlight
    // moved — navigation, search filtering, or switching Static/Animated.
    onCurrentIndexChanged: previewDebounce.restart()

    Timer {
        id: previewDebounce
        // Static previews are a cheap awww call, but every animated preview
        // spins up a fresh decoder for a full-resolution clip. Only load one
        // once the user has actually settled on a card.
        interval: root.entries === null ? 180
            : (root.filteredEntries?.[root.currentIndex]?.kind === "static" ? 180 : 500)
        onTriggered: root.previewCurrent()
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const dx = Number(event.angleDelta.x ?? 0)
            const dy = Number(event.angleDelta.y ?? 0)
            const primary = Math.abs(dx) >= Math.abs(dy) ? dx : dy
            if (primary === 0)
                return
            const now = Date.now()
            if (now - root._lastWheelStepMs > 320)
                root._wheelAccum = 0
            root._wheelAccum += primary
            if (Math.abs(root._wheelAccum) >= 90 && (now - root._lastWheelStepMs) >= 110) {
                const step = root._wheelAccum > 0 ? -1 : 1
                root._wheelAccum = 0
                root._lastWheelStepMs = now
                root.moveSelection(step)
            }
            event.accepted = true
        }
    }

    delegate: WallpaperLauncherItem {
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        onActivated: selectedIndex => {
            root.currentIndex = selectedIndex
            const entry = root.filteredEntries?.[selectedIndex]
            if (entry?.path) root.applyRequested(entry.path)
        }
    }

    path: Path {
        startY: root.height / 2
        PathAttribute { name: "z"; value: 0 }
        PathLine { x: root.width / 2; relativeY: 0 }
        PathAttribute { name: "z"; value: 1 }
        PathLine { x: root.width; relativeY: 0 }
    }
}
