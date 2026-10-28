pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.qmlmodels
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.mediaControls

Item {
    id: root
    property alias inputField: searchField
    property string section: "songs"
    property string browserFolder: ""
    property var selectedTrackKeys: []
    property var selectedFolderPaths: []
    property int selectionAnchorIndex: -1
    property Item contextAnchor: null
    property var contextMenuModel: []
    property bool playlistDialogVisible: false
    property var pendingPlaylistTracks: []

    QtObject {
        id: localMusicPlayerAdapter
        readonly property string title: LocalMusic.currentTitle
        readonly property string artist: LocalMusic.currentArtist
        readonly property string album: LocalMusic.currentAlbum
        readonly property string artUrl: LocalMusic.currentArt
        readonly property real position: LocalMusic.lyricsPosition
        readonly property real length: LocalMusic.currentDuration
        readonly property bool isPlaying: LocalMusic.playing
        readonly property bool canSeek: LocalMusic.hasCurrentTrack
        readonly property bool canGoPrevious: LocalMusic.canGoPrevious
        readonly property bool canGoNext: LocalMusic.canGoNext
        readonly property bool shuffleSupported: LocalMusic.available
        readonly property bool shuffle: LocalMusic.shuffleMode
        readonly property bool repeatSupported: LocalMusic.available
        readonly property int repeatMode: LocalMusic.repeatMode
        function togglePlaying(): void { LocalMusic.togglePlaying() }
        function previous(): void { LocalMusic.previous() }
        function next(): void { LocalMusic.next() }
        function seek(seconds): void { LocalMusic.seek(seconds) }
        function toggleShuffle(): void { LocalMusic.toggleShuffle() }
        function cycleRepeat(): void { LocalMusic.cycleRepeatMode() }
    }

    readonly property string query: searchField.text.trim().toLowerCase()
    readonly property var filteredTracks: {
        if (!root.query) return LocalMusic.libraryTracks
        const result = []
        for (const track of LocalMusic.libraryTracks) {
            const rawTitle = track?.title
            const rawArtist = track?.artist
            const rawAlbum = track?.album
            const rawFolder = track?.folder
            const title = String(rawTitle ?? "").toLowerCase()
            const artist = String(rawArtist ?? "").toLowerCase()
            const album = String(rawAlbum ?? "").toLowerCase()
            const folder = String(rawFolder ?? "").toLowerCase()
            const haystack = title + " " + artist + " " + album + " " + folder
            if (haystack.includes(root.query))
                result.push(track)
        }
        return result
    }
    readonly property var songEntries: root.buildSongEntries()
    readonly property var selectedTracks: root.resolveSelectedTracks()
    readonly property int selectedEntryCount:
        root.selectedTrackKeys.length + root.selectedFolderPaths.length

    function trackKey(track): string {
        return String(track?.uri ?? track?.path ?? "")
    }

    function normalizedFolder(value): string {
        let normalized = String(value ?? "")
        while (normalized.startsWith("/"))
            normalized = normalized.substring(1)
        while (normalized.endsWith("/"))
            normalized = normalized.substring(0, normalized.length - 1)
        return normalized
    }

    function buildSongEntries(): var {
        if (root.query.length > 0) {
            return root.filteredTracks.map(track =>
                Object.assign({ entryType: "track" }, track))
        }

        const current = root.normalizedFolder(root.browserFolder)
        const prefix = current.length > 0 ? current + "/" : ""
        const childMap = {}
        const directTracks = []

        for (const track of LocalMusic.libraryTracks) {
            const folder = root.normalizedFolder(track?.folder)
            if (current.length > 0) {
                if (folder === current) {
                    directTracks.push(track)
                    continue
                }
                if (!folder.startsWith(prefix))
                    continue
            } else if (folder.length === 0) {
                directTracks.push(track)
                continue
            }

            const rest = current.length > 0 ? folder.substring(prefix.length) : folder
            if (rest.length === 0) {
                directTracks.push(track)
                continue
            }

            const childName = rest.split("/")[0]
            const childPath = prefix + childName
            if (!childMap[childPath]) {
                childMap[childPath] = {
                    entryType: "folder",
                    name: childName,
                    path: childPath,
                    subtitle: childPath,
                    count: 0
                }
            }
            childMap[childPath].count += 1
        }

        const folders = Object.keys(childMap)
            .map(path => childMap[path])
            .sort((a, b) => String(a.name).localeCompare(String(b.name)))
        const tracks = directTracks.map(track =>
            Object.assign({ entryType: "track" }, track))
        return folders.concat(tracks)
    }

    function folderTracks(path): var {
        const normalized = root.normalizedFolder(path)
        const prefix = normalized.length > 0 ? normalized + "/" : ""
        return LocalMusic.libraryTracks.filter(track => {
            const folder = root.normalizedFolder(track?.folder)
            return folder === normalized || (prefix.length > 0 && folder.startsWith(prefix))
        })
    }

    function parentFolder(path): string {
        const normalized = root.normalizedFolder(path)
        const split = normalized.lastIndexOf("/")
        return split < 0 ? "" : normalized.substring(0, split)
    }

    function navigateFolder(path): void {
        root.browserFolder = root.normalizedFolder(path)
        root.clearSelection()
    }

    function clearSelection(): void {
        root.selectedTrackKeys = []
        root.selectedFolderPaths = []
        root.selectionAnchorIndex = -1
    }

    function isTrackSelected(track): bool {
        return root.selectedTrackKeys.includes(root.trackKey(track))
    }

    function isFolderSelected(path): bool {
        return root.selectedFolderPaths.includes(root.normalizedFolder(path))
    }

    function resolveSelectedTracks(): var {
        const selectedTracks = new Set(root.selectedTrackKeys)
        const selectedFolders = root.selectedFolderPaths
            .map(path => root.normalizedFolder(path))
            .filter(path => path.length > 0)

        return LocalMusic.libraryTracks.filter(track => {
            const key = root.trackKey(track)
            if (selectedTracks.has(key))
                return true
            const folder = root.normalizedFolder(track?.folder)
            return selectedFolders.some(path =>
                folder === path || folder.startsWith(path + "/"))
        })
    }

    function applyRangeSelection(entryIndex, additive): void {
        const from = Math.min(root.selectionAnchorIndex, entryIndex)
        const to = Math.max(root.selectionAnchorIndex, entryIndex)
        const tracks = additive ? root.selectedTrackKeys.slice() : []
        const folders = additive ? root.selectedFolderPaths.slice() : []
        const trackSet = new Set(tracks)
        const folderSet = new Set(folders)

        for (const entry of root.songEntries.slice(from, to + 1)) {
            if (entry?.entryType === "folder") {
                const path = root.normalizedFolder(entry?.path)
                if (path.length > 0 && !folderSet.has(path)) {
                    folders.push(path)
                    folderSet.add(path)
                }
            } else if (entry?.entryType === "track") {
                const key = root.trackKey(entry)
                if (key.length > 0 && !trackSet.has(key)) {
                    tracks.push(key)
                    trackSet.add(key)
                }
            }
        }

        root.selectedTrackKeys = tracks
        root.selectedFolderPaths = folders
    }

    function selectTrack(track, entryIndex, modifiers): void {
        const key = root.trackKey(track)
        if (!key) return

        const controlHeld = (modifiers & Qt.ControlModifier) !== 0
        const shiftHeld = (modifiers & Qt.ShiftModifier) !== 0

        if (shiftHeld && root.selectionAnchorIndex >= 0) {
            root.applyRangeSelection(entryIndex, controlHeld)
            return
        }

        if (controlHeld) {
            const next = root.selectedTrackKeys.slice()
            const existing = next.indexOf(key)
            if (existing >= 0)
                next.splice(existing, 1)
            else
                next.push(key)
            root.selectedTrackKeys = next
            root.selectionAnchorIndex = entryIndex
            return
        }

        root.selectedTrackKeys = [key]
        root.selectedFolderPaths = []
        root.selectionAnchorIndex = entryIndex
    }

    function selectFolder(folder, entryIndex, modifiers): void {
        const path = root.normalizedFolder(folder?.path)
        if (!path) return

        const controlHeld = (modifiers & Qt.ControlModifier) !== 0
        const shiftHeld = (modifiers & Qt.ShiftModifier) !== 0

        if (shiftHeld && root.selectionAnchorIndex >= 0) {
            root.applyRangeSelection(entryIndex, controlHeld)
            return
        }

        if (controlHeld) {
            const next = root.selectedFolderPaths.slice()
            const existing = next.indexOf(path)
            if (existing >= 0)
                next.splice(existing, 1)
            else
                next.push(path)
            root.selectedFolderPaths = next
            root.selectionAnchorIndex = entryIndex
            return
        }

        root.selectedTrackKeys = []
        root.selectedFolderPaths = [path]
        root.selectionAnchorIndex = entryIndex
    }

    function buildTrackContextMenu(tracks, playText): var {
        const snapshot = (tracks ?? []).slice()
        if (snapshot.length === 0) return []

        const model = [
            {
                iconName: "play_arrow",
                monochromeIcon: true,
                text: playText,
                action: () => LocalMusic.playQueue(snapshot, 0, playText)
            },
            {
                iconName: "playlist_add",
                monochromeIcon: true,
                text: Translation.tr("Add to queue"),
                action: () => LocalMusic.enqueueTracks(snapshot)
            },
            { type: "separator" },
            {
                iconName: "library_add",
                monochromeIcon: true,
                text: Translation.tr("Create playlist…"),
                action: () => root.openCreatePlaylist(snapshot)
            }
        ]

        for (const playlist of LocalMusic.playlists) {
            const name = String(playlist?.name ?? "")
            if (!name) continue
            model.push({
                iconName: "queue_music",
                monochromeIcon: true,
                text: Translation.tr("Add to %1").arg(name),
                action: () => LocalMusic.addTracksToPlaylist(name, snapshot)
            })
        }
        return model
    }

    function openTrackContext(track, entryIndex, anchor): void {
        if (!root.isTrackSelected(track))
            root.selectTrack(track, entryIndex, 0)
        const tracks = root.isTrackSelected(track) ? root.selectedTracks : [track]
        root.contextAnchor = anchor
        root.contextMenuModel = root.buildTrackContextMenu(
            tracks,
            tracks.length > 1 ? Translation.tr("Play selection") : Translation.tr("Play"))
        musicContextMenu.requestOpen()
    }

    function openFolderContext(folder, entryIndex, anchor): void {
        if (!root.isFolderSelected(folder?.path))
            root.selectFolder(folder, entryIndex, 0)
        const tracks = root.selectedTracks
        root.contextAnchor = anchor
        root.contextMenuModel = root.buildTrackContextMenu(
            tracks,
            root.selectedEntryCount > 1
                ? Translation.tr("Play selection")
                : Translation.tr("Play folder"))
        musicContextMenu.requestOpen()
    }

    function openCreatePlaylist(tracks): void {
        root.pendingPlaylistTracks = (tracks ?? []).slice()
        if (root.pendingPlaylistTracks.length === 0) return
        playlistNameField.text = ""
        root.playlistDialogVisible = true
        Qt.callLater(() => playlistNameField.forceActiveFocus())
    }

    function closePlaylistDialog(): void {
        root.playlistDialogVisible = false
        root.pendingPlaylistTracks = []
        playlistNameField.text = ""
    }

    function commitPlaylistDialog(): void {
        const name = playlistNameField.text.trim()
        if (!name || root.pendingPlaylistTracks.length === 0) return
        LocalMusic.createPlaylist(name, root.pendingPlaylistTracks)
        root.closePlaylistDialog()
    }

    onQueryChanged: root.clearSelection()
    onSectionChanged: if (root.section !== "songs") root.clearSelection()

    function formatTime(seconds): string {
        const value = Math.max(0, Math.floor(Number(seconds) || 0))
        const minutes = Math.floor(value / 60)
        const rest = value % 60
        return minutes + ":" + (rest < 10 ? "0" : "") + rest
    }

    function sectionIndex(): int {
        switch (root.section) {
        case "playlists": return 1
        case "queue": return 2
        case "lyrics": return 3
        default: return 0
        }
    }

    CavaProcess {
        id: localMusicCava
        active: root.visible && GlobalStates.sidebarLeftOpen
            && LocalMusic.playing
        sampleCount: 64
    }

    component ToolIconButton: RippleButton {
        id: toolButton
        property string symbol: ""
        property string tip: ""
        property bool showTip: true
        property color iconColor: Appearance.colors.colOnLayer1
        property color backgroundColor: "transparent"
        property color hoverColor: Appearance.colors.colLayer1Hover
        property color rippleColor: Appearance.colors.colLayer1Active
        implicitWidth: 38
        implicitHeight: 38
        buttonRadius: Appearance.rounding.full
        colBackground: toolButton.backgroundColor
        colBackgroundHover: toolButton.hoverColor
        colRipple: toolButton.rippleColor
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: toolButton.symbol
            iconSize: 20
            color: toolButton.iconColor
        }
        StyledToolTip {
            visible: toolButton.showTip && toolButton.tip.length > 0
            text: toolButton.tip
        }
    }

    component FolderRow: Rectangle {
        id: folderRow
        required property var folder
        required property int folderIndex
        property bool selected: false
        signal activated()
        signal selectionRequested(int modifiers)
        signal contextRequested()

        implicitHeight: 52
        radius: Appearance.rounding.small
        color: selected
            ? Appearance.colors.colPrimaryContainer
            : (folderMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Appearance.rounding.small
                color: folderRow.selected
                    ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colSecondaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: folderRow.selected ? "folder_check" : "folder"
                    iconSize: 21
                    color: folderRow.selected
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: String(folderRow.folder?.name ?? "")
                    color: folderRow.selected
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 songs").arg(folderRow.folder?.count ?? 0)
                    color: folderRow.selected
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: "chevron_right"
                iconSize: 20
                color: folderRow.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext
            }
        }

        MouseArea {
            id: folderMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    folderRow.contextRequested()
                    return
                }
                const selecting = (event.modifiers & Qt.ControlModifier) !== 0
                    || (event.modifiers & Qt.ShiftModifier) !== 0
                if (selecting)
                    folderRow.selectionRequested(event.modifiers)
                else
                    folderRow.activated()
            }
        }
    }

    component TrackRow: Rectangle {
        id: trackRow
        required property var track
        required property int trackIndex
        property bool active: String(track?.path ?? "") === LocalMusic.currentPath
        property bool selected: false
        property bool removable: false
        signal activated()
        signal removeRequested()
        signal selectionRequested(int modifiers)
        signal contextRequested()

        implicitHeight: 50
        radius: Appearance.rounding.small
        color: selected
            ? Appearance.colors.colPrimaryContainer
            : active
                ? Appearance.colors.colSecondaryContainer
                : (rowMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 8
            z: 1
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Appearance.rounding.small
                color: trackRow.selected
                    ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colLayer2
                clip: true
                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: String(trackRow.track?.art ?? "")
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 72
                    sourceSize.height: 72
                    visible: status === Image.Ready
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: coverImage.status !== Image.Ready
                    text: trackRow.active && LocalMusic.playing ? "graphic_eq" : "music_note"
                    iconSize: 20
                    color: trackRow.selected
                        ? Appearance.colors.colOnSecondaryContainer
                        : (trackRow.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: String(trackRow.track?.title ?? "")
                    color: trackRow.selected
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: trackRow.active || trackRow.selected ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const artist = String(trackRow.track?.artist ?? "")
                        const album = String(trackRow.track?.album ?? "")
                        return artist && album ? artist + " • " + album : (artist || album)
                    }
                    visible: text.length > 0
                    color: trackRow.selected
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }
            StyledText {
                text: trackRow.track?.duration > 0 ? root.formatTime(trackRow.track.duration) : ""
                color: trackRow.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
            }
            ToolIconButton {
                visible: trackRow.removable
                Layout.preferredWidth: visible ? 30 : 0
                Layout.preferredHeight: 30
                symbol: "close"
                tip: Translation.tr("Remove")
                onClicked: trackRow.removeRequested()
            }
        }
        MouseArea {
            id: rowMouse
            z: 0
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    trackRow.contextRequested()
                    return
                }
                trackRow.forceActiveFocus()
                trackRow.selectionRequested(event.modifiers)
            }
            onDoubleClicked: trackRow.activated()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol { text: "library_music"; iconSize: 26; color: Appearance.colors.colPrimary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Music")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "MPD · " + LocalMusic.mpdHost + ":" + LocalMusic.mpdPort
                        + (LocalMusic.libraryFolder.length > 0 ? " · " + LocalMusic.libraryFolder : "")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                }
            }
            ToolIconButton {
                symbol: "folder_open"
                tip: Translation.tr("Folder")
                onClicked: folderDialog.open()
            }
            ToolIconButton {
                symbol: "database"
                tip: Translation.tr("Update")
                enabled: LocalMusic.available && !LocalMusic.scanning
                onClicked: LocalMusic.updateDatabase()
            }
            ToolIconButton {
                symbol: "refresh"
                tip: Translation.tr("Refresh")
                enabled: !LocalMusic.scanning
                onClicked: LocalMusic.rescan()
            }
        }

        // Keep now-playing above navigation, but preserve the classic Music
        // transport-adjacent controls as their own simple row.
        Item {
            id: nowPlayingPanel
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Appearance.sizes.mediaControlsHeight : 0
            visible: LocalMusic.hasCurrentTrack

            PlayerControl {
                anchors.fill: parent
                player: LocalMusic.mprisPlayer
                playbackAdapter: localMusicPlayerAdapter
                visualizerPoints: localMusicCava.points
                visualizerMaxValue: Math.max(1, localMusicCava.normalizationCeiling)
                radius: Appearance.rounding.normal
            }
        }

        RowLayout {
            id: classicPlaybackOptions
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 34 : 0
            visible: LocalMusic.hasCurrentTrack
            spacing: 6

            Item { Layout.fillWidth: true }
            MaterialSymbol {
                text: LocalMusic.volume <= 0 ? "volume_off"
                    : (LocalMusic.volume < 0.5 ? "volume_down" : "volume_up")
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
            StyledSlider {
                Layout.preferredWidth: 100
                configuration: StyledSlider.Configuration.XS
                stopIndicatorValues: []
                from: 0
                to: 1
                liveValue: LocalMusic.volume
                onSeekCommitted: (val) => LocalMusic.setVolume(val)
                scrollable: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Item { Layout.fillWidth: true }
            Repeater {
                model: [
                    { id: "songs", label: Translation.tr("Songs"), icon: "music_note" },
                    { id: "playlists", label: Translation.tr("Playlists"), icon: "queue_music" },
                    { id: "queue", label: Translation.tr("Queue"), icon: "format_list_numbered" },
                    { id: "lyrics", label: Translation.tr("Lyrics"), icon: "lyrics" }
                ]
                delegate: RippleButton {
                    id: sectionButton
                    required property var modelData
                    readonly property bool selected: root.section === modelData.id
                    implicitWidth: selected
                        ? Math.max(72, sectionContent.implicitWidth + 20)
                        : 30
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: selected
                        ? Appearance.colors.colSecondaryContainer
                        : "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.section = modelData.id

                    Behavior on implicitWidth {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }

                    contentItem: Item {
                        RowLayout {
                            id: sectionContent
                            anchors.centerIn: parent
                            spacing: sectionButton.selected ? 5 : 0

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                text: sectionButton.modelData.icon
                                iconSize: sectionButton.selected ? 17 : 15
                                fill: sectionButton.selected ? 1 : 0
                                color: sectionButton.selected
                                    ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                visible: sectionButton.selected
                                text: sectionButton.modelData.label
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            id: searchShell
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 42 : 0
            visible: root.section === "songs"
            radius: Appearance.rounding.full
            color: searchField.activeFocus
                ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colLayer2
            border.width: 1
            border.color: searchField.activeFocus
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOutlineVariant

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
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 7

                MaterialSymbol {
                    text: "search"
                    iconSize: 19
                    color: searchField.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }

                ToolbarTextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 38
                    colBackground: "transparent"
                    leftPadding: 0
                    rightPadding: 4
                    placeholderText: Translation.tr("Search music")
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            StackLayout {
                anchors.fill: parent
                currentIndex: root.sectionIndex()

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            spacing: 4

                            ToolIconButton {
                                visible: root.query.length === 0 && root.browserFolder.length > 0
                                Layout.preferredWidth: visible ? 30 : 0
                                Layout.preferredHeight: 30
                                symbol: "arrow_back"
                                tip: Translation.tr("Back")
                                onClicked: root.navigateFolder(root.parentFolder(root.browserFolder))
                            }

                            MaterialSymbol {
                                text: root.query.length > 0 ? "search" : "folder_open"
                                iconSize: 17
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.query.length > 0
                                    ? Translation.tr("Search results")
                                    : (root.browserFolder.length > 0
                                        ? root.browserFolder.split("/").join(" / ")
                                        : Translation.tr("Songs"))
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideMiddle
                            }

                            StyledText {
                                visible: root.selectedEntryCount > 0
                                text: Translation.tr("%1 selected").arg(root.selectedEntryCount)
                                color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                            }

                            ToolIconButton {
                                visible: root.selectedEntryCount > 0
                                Layout.preferredWidth: visible ? 30 : 0
                                Layout.preferredHeight: 30
                                symbol: "play_arrow"
                                tip: Translation.tr("Play selection")
                                onClicked: {
                                    const tracks = root.selectedTracks
                                    if (tracks.length > 0)
                                        LocalMusic.playQueue(tracks, 0, Translation.tr("Play selection"))
                                }
                            }
                            ToolIconButton {
                                visible: root.selectedEntryCount > 0
                                Layout.preferredWidth: visible ? 30 : 0
                                Layout.preferredHeight: 30
                                symbol: "playlist_add"
                                tip: Translation.tr("Add to queue")
                                onClicked: {
                                    const tracks = root.selectedTracks
                                    if (tracks.length > 0)
                                        LocalMusic.enqueueTracks(tracks)
                                }
                            }
                            ToolIconButton {
                                visible: root.selectedEntryCount > 0
                                Layout.preferredWidth: visible ? 30 : 0
                                Layout.preferredHeight: 30
                                symbol: "deselect"
                                tip: Translation.tr("Clear selection")
                                onClicked: root.clearSelection()
                            }
                        }

                        ListView {
                            id: songsList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            model: root.songEntries

                            delegate: DelegateChooser {
                                role: "entryType"

                                DelegateChoice {
                                    roleValue: "folder"
                                    FolderRow {
                                        id: folderDelegate
                                        required property var modelData
                                        required property int index
                                        width: ListView.view.width
                                        folder: modelData
                                        folderIndex: index
                                        selected: root.isFolderSelected(modelData.path)
                                        onActivated: root.navigateFolder(modelData.path)
                                        onSelectionRequested: modifiers =>
                                            root.selectFolder(modelData, index, modifiers)
                                        onContextRequested:
                                            root.openFolderContext(modelData, index, folderDelegate)
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "track"
                                    TrackRow {
                                        id: songRow
                                        required property var modelData
                                        required property int index
                                        width: ListView.view.width
                                        track: modelData
                                        trackIndex: index
                                        selected: root.isTrackSelected(modelData)
                                        onSelectionRequested: modifiers =>
                                            root.selectTrack(modelData, index, modifiers)
                                        onContextRequested:
                                            root.openTrackContext(modelData, index, songRow)
                                        onActivated: LocalMusic.enqueueTrack(modelData, true)
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !LocalMusic.scanning && root.songEntries.length === 0
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.query.length > 0 ? "search_off" : "music_off"
                            iconSize: 42
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("No results")
                            color: Appearance.colors.colSubtext
                        }
                        RippleButton {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 120
                            implicitHeight: 38
                            visible: root.query.length === 0
                            enabled: LocalMusic.available
                            onClicked: LocalMusic.updateDatabase()
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: Translation.tr("Update")
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                Item {
                    ListView {
                        anchors.fill: parent
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        model: LocalMusic.playlists
                        delegate: Rectangle {
                            id: playlistRow
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: 66
                            radius: Appearance.rounding.small
                            color: playlistMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12
                                Rectangle {
                                    Layout.preferredWidth: 44; Layout.preferredHeight: 44
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colSecondaryContainer
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "queue_music"
                                        iconSize: 22
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(playlistRow.modelData?.name ?? "")
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        text: Translation.tr("%1 songs").arg(playlistRow.modelData?.tracks?.length ?? 0)
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                                MaterialSymbol { text: "play_arrow"; iconSize: 22; color: Appearance.colors.colPrimary }
                            }
                            MouseArea {
                                id: playlistMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: LocalMusic.playCollection(playlistRow.modelData)
                            }
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: LocalMusic.playlists.length === 0
                        text: Translation.tr("No playlists")
                        color: Appearance.colors.colSubtext
                    }
                }

                Item {
                    RowLayout {
                        id: queueHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: visible ? 34 : 0
                        visible: LocalMusic.activeQueue.length > 0
                        spacing: 6

                        StyledText {
                            text: Translation.tr("%1 songs").arg(LocalMusic.activeQueue.length)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            implicitHeight: 30
                            implicitWidth: clearQueueContent.implicitWidth + 22
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            onClicked: LocalMusic.clearQueue()
                            contentItem: Item {
                                RowLayout {
                                    id: clearQueueContent
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                        text: "delete_sweep"
                                        iconSize: 17
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                        text: Translation.tr("Clear")
                                        color: Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        anchors.top: queueHeader.visible ? queueHeader.bottom : parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        model: LocalMusic.activeQueue
                        delegate: TrackRow {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            track: modelData
                            trackIndex: index
                            removable: true
                            onActivated: LocalMusic.jumpTo(index)
                            onRemoveRequested: LocalMusic.removeQueueTrack(index)
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: LocalMusic.activeQueue.length === 0
                        text: Translation.tr("Queue")
                        color: Appearance.colors.colSubtext
                    }
                }

                Item {
                    ListView {
                        id: lyricsList
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        model: LocalMusic.localLyricsLines
                        currentIndex: LocalMusic.localLyricsActiveIndex

                        onCurrentIndexChanged: {
                            if (currentIndex >= 0)
                                Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Center))
                        }

                        header: ColumnLayout {
                            width: lyricsList.width
                            spacing: 2
                            visible: LocalMusic.hasLocalLyrics
                            StyledText {
                                Layout.fillWidth: true
                                text: LocalMusic.localLyricsSynced
                                    ? Translation.tr("Synced local lyrics")
                                    : Translation.tr("Local lyrics")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Directories.shortHomePath(LocalMusic.localLyricsPath)
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                elide: Text.ElideMiddle
                            }
                            Item { Layout.preferredHeight: 6 }
                        }

                        delegate: Rectangle {
                            id: lyricRow
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            implicitHeight: lyricText.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: index === LocalMusic.localLyricsActiveIndex
                                ? Appearance.colors.colSecondaryContainer : "transparent"

                            WordSyncedLyricLine {
                                id: lyricText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                lineData: lyricRow.modelData
                                nextLineTime: (lyricRow.index + 1 < LocalMusic.localLyricsLines.length)
                                    ? Number(LocalMusic.localLyricsLines[lyricRow.index + 1]?.time ?? -1)
                                    : -1
                                active: lyricRow.index === LocalMusic.localLyricsActiveIndex
                                playing: LocalMusic.playing
                                synced: LocalMusic.localLyricsSynced
                                position: LocalMusic.lyricsPosition
                                horizontalAlignment: Text.AlignHCenter
                                fontPixelSize: lyricRow.index === LocalMusic.localLyricsActiveIndex
                                    ? Appearance.font.pixelSize.normal
                                    : Appearance.font.pixelSize.small
                                activeFontWeight: Font.Medium
                                inactiveFontWeight: Font.Normal
                                activeColor: Appearance.colors.colOnSecondaryContainer
                                inactiveColor: Appearance.colors.colOnLayer1
                                accentColor: Appearance.colors.colPrimary
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 40, 280)
                        spacing: 8
                        visible: !LocalMusic.hasLocalLyrics
                        LoadingText {
                            Layout.alignment: Qt.AlignHCenter
                            visible: LocalMusic.localLyricsStatus === "loading"
                        }
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            visible: LocalMusic.localLyricsStatus !== "loading"
                            text: "lyrics"
                            iconSize: 36
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: LocalMusic.localLyricsStatus !== "loading"
                            text: LocalMusic.currentPath.length === 0
                                ? Translation.tr("Nothing playing")
                                : Translation.tr("No local .lrc or .txt lyrics beside this track")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }
            MaterialLoadingIndicator { anchors.centerIn: parent; visible: LocalMusic.scanning }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 34 : 0
            visible: !LocalMusic.available || !LocalMusic.mprisAvailable
            radius: Appearance.rounding.small
            color: Appearance.colors.colErrorContainer
            StyledText {
                anchors.centerIn: parent
                text: !LocalMusic.available
                    ? "MPD · " + LocalMusic.mpdHost + ":" + LocalMusic.mpdPort
                    : Translation.tr("Waiting for mpd-mpris")
                color: Appearance.colors.colOnErrorContainer
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    ContextMenu {
        id: musicContextMenu
        anchorItem: root.contextAnchor ?? root
        model: root.contextMenuModel
        closeOnHoverLost: false
        closeOnFocusLost: true
        popupAbove: false
    }

    Rectangle {
        id: playlistDialogOverlay
        anchors.fill: parent
        visible: root.playlistDialogVisible
        z: 100
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.closePlaylistDialog()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 320)
            height: 162
            z: 1
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Create playlist")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 songs").arg(root.pendingPlaylistTracks.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                ToolbarTextField {
                    id: playlistNameField
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 38
                    placeholderText: Translation.tr("Playlist name")
                    onAccepted: root.commitPlaylistDialog()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.closePlaylistDialog()
                            event.accepted = true
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        onClicked: root.closePlaylistDialog()
                        contentItem: StyledText {
                            anchors.fill: parent
                            text: Translation.tr("Cancel")
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 34
                        enabled: playlistNameField.text.trim().length > 0
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        onClicked: root.commitPlaylistDialog()
                        contentItem: StyledText {
                            anchors.fill: parent
                            text: Translation.tr("Create")
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: Translation.tr("Music")
        onAccepted: LocalMusic.setLibraryFolder(String(selectedFolder))
    }
}
