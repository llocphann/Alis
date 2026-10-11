pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.mediaControls
import qs.modules.abyss.looks
import "DashboardMusicModel.js" as Library

Item {
    id: root
    objectName: "dashboardMusic"
    // A visual-only preference: leave Flickable/wheel/key navigation alive.
    readonly property bool showMusicScrollbars: Config.options?.dashboard?.music?.showScrollbars ?? true
    required property var backend
    property bool presentationActive: visible
    // Queue is a compact preview until hovered; expand it upwards by shrinking
    // the same DashMedia card and suspending only its EQ/DSP consumer.
    property bool queueExpanded: false
    property string sourceMode: ""
    // One Library column; tabs only change the browsing surface, not playback.
    property string libraryTab: "genre"
    property string selectedGenre: ""
    property string selectedFolder: ""
    property var selectedGenres: []
    property var selectedFolders: []
    property int genreSelectionAnchor: -1
    property int folderSelectionAnchor: -1
    property string resultFolder: ""
    property alias query: search.text
    property var selectedKeys: []
    property int selectionAnchor: -1
    property string selectedPlaylistName: ""
    readonly property var selectedPlaylist: (backend.playlists ?? []).find(value => String(value.name ?? "") === selectedPlaylistName) ?? null
    property bool browserRestored: false
    property Item contextAnchor: null
    property var contextActions: []
    property bool playlistDialogVisible: false
    property var pendingPlaylistTracks: []
    readonly property var tracks: backend.libraryTracks ?? []
    readonly property var genres: Library.genres(tracks)
    readonly property var folders: Library.roots(tracks)
    readonly property bool hasLyrics: (backend.localLyricsLines ?? []).some(line => String(line.text ?? "").trim().length > 0)
    readonly property var results: {
        if (sourceMode === "queue") {
            const entries = (backend.activeQueue ?? []).map((track, index) => ({
                        kind: "track",
                        track,
                        name: String(track.title || track.uri || ""),
                        queueIndex: index
                    }));
            if (!query.trim())
                return entries;
            const matched = new Set(Library.matching(backend.activeQueue ?? [], query));
            return entries.filter(entry => matched.has(entry.track));
        }
        if (sourceMode === "playlist")
            return Library.matching(selectedPlaylist?.tracks ?? [], query).map(track => ({
                        kind: "track",
                        track,
                        name: String(track.title || track.uri || "")
                    }));
        if (query.trim())
            return Library.matching(tracks, query).map(track => ({
                        kind: "track",
                        track,
                        name: String(track.title || track.uri || "")
                    }));
        return Library.results(tracks, sourceMode, selectedGenres,
            selectedFolders.length === 1 ? resultFolder : selectedFolders);
    }
    readonly property var selectedTracks: Library.selectedTracks(sourceMode === "playlist" ? (selectedPlaylist?.tracks ?? []) : sourceMode === "queue" ? (backend.activeQueue ?? []) : tracks, selectedKeys)
     readonly property var allResultTracks: Library.selectedTracks(
        sourceMode === "playlist" ? (selectedPlaylist?.tracks ?? []) :
        sourceMode === "queue" ? (backend.activeQueue ?? []) : tracks,
        results.map(entry => Library.key(entry)))
    // MPD command/decoder/connection errors must be visible to the user.
    // This is a read-only presentation of the existing LocalMusic backend.
    readonly property string backendError: String(root.backend?.error ?? "").trim()
    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    readonly property color ink: abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000") : Appearance.colors.colOnSurface
    readonly property color mutedInk: abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : Qt.alpha("#000000", .66)) : Appearance.colors.colSubtext
    readonly property color accent: abyss ? AbyssStyle.accent : Appearance.colors.colPrimary
    readonly property color surface: abyss ? AbyssStyle.contentLayer : Appearance.colors.colLayer1
    function clearSelection(): void {
        selectedKeys = [];
        selectionAnchor = -1;
    }
    function rememberBrowser(): void {
        if (!browserRestored)
            return;
        GlobalStates.dashboardMusicBrowser = {
            mode: sourceMode,
            tab: libraryTab,
            genre: selectedGenre,
            folder: selectedFolder,
            genres: selectedGenres,
            folders: selectedFolders,
            path: resultFolder,
            query,
            playlist: selectedPlaylistName
        };
    }
    Component.onCompleted: {
        const saved = GlobalStates.dashboardMusicBrowser;
        sourceMode = String(saved.mode ?? "");
        libraryTab = ["genre", "folder"].includes(saved.tab) ? saved.tab
            : (sourceMode === "folder" || sourceMode === "playlist" ? "folder" : "genre");
        selectedGenre = String(saved.genre ?? "");
        selectedFolder = String(saved.folder ?? "");
        selectedGenres = Array.isArray(saved.genres) ? saved.genres.filter(value => typeof value === "string")
            : (sourceMode === "genre" ? [selectedGenre] : []);
        selectedFolders = Array.isArray(saved.folders) ? saved.folders.filter(value => typeof value === "string")
            : (sourceMode === "folder" ? [selectedFolder] : []);
        resultFolder = String(saved.path ?? "");
        query = String(saved.query ?? "");
        selectedPlaylistName = String(saved.playlist ?? "");
        browserRestored = true;
    }
    onSourceModeChanged: {
        clearSelection();
        rememberBrowser();
    }
    onResultFolderChanged: {
        clearSelection();
        rememberBrowser();
    }
    onQueryChanged: {
        clearSelection();
        rememberBrowser();
    }
    onLibraryTabChanged: rememberBrowser()
    onSelectedGenreChanged: rememberBrowser()
    onSelectedFolderChanged: rememberBrowser()
    onSelectedGenresChanged: rememberBrowser()
    onSelectedFoldersChanged: rememberBrowser()
    onSelectedPlaylistNameChanged: rememberBrowser()
    // First Escape clears the active library drill-down, second closes Dashboard.
    function restoreBrowserColumns(): bool {
        if (playlistDialogVisible) {
            playlistDialogVisible = false
            return true
        }
        if (!["genre", "folder", "playlist"].includes(sourceMode))
            return false
        sourceMode = ""
        selectedGenre = ""
        selectedFolder = ""
        selectedGenres = []
        selectedFolders = []
        genreSelectionAnchor = -1
        folderSelectionAnchor = -1
        selectedPlaylistName = ""
        resultFolder = ""
        query = ""
        clearSelection()
        rememberBrowser()
        return true
    }
    function switchLibraryTab(tab): void {
        if (tab !== "genre" && tab !== "folder")
            return
        libraryTab = tab
        if (["genre", "folder", "playlist"].includes(sourceMode)) {
            sourceMode = ""
            selectedGenre = ""
            selectedFolder = ""
            selectedGenres = []
            selectedFolders = []
            genreSelectionAnchor = -1
            folderSelectionAnchor = -1
            selectedPlaylistName = ""
            resultFolder = ""
            query = ""
            clearSelection()
        }
        rememberBrowser()
    }
    function chooseGenre(value, modifiers = 0): void {
        const values = genres.map(entry => entry.key);
        const next = Library.selectValues(values, sourceMode === "genre" ? selectedGenres : [],
            genreSelectionAnchor, values.indexOf(value), !!(modifiers & Qt.ControlModifier), !!(modifiers & Qt.ShiftModifier));
        libraryTab = "genre"
        query = "";
        sourceMode = "genre";
        selectedGenre = value;
        selectedGenres = next.keys;
        genreSelectionAnchor = next.anchor;
        clearSelection();
    }
    function chooseFolder(path, modifiers = 0): void {
        const values = folders.map(entry => entry.path);
        const next = Library.selectValues(values, sourceMode === "folder" ? selectedFolders : [],
            folderSelectionAnchor, values.indexOf(path), !!(modifiers & Qt.ControlModifier), !!(modifiers & Qt.ShiftModifier));
        libraryTab = "folder"
        query = "";
        sourceMode = "folder";
        selectedFolder = path;
        selectedFolders = next.keys;
        folderSelectionAnchor = next.anchor;
        resultFolder = next.keys.length === 1 ? next.keys[0] : "";
        clearSelection();
    }
    function choosePlaylist(value): void {
        libraryTab = "folder"
        query = "";
        sourceMode = "playlist";
        selectedPlaylistName = String(value.name ?? "");
        clearSelection();
    }
    function selectEntry(index, modifiers): void {
        const next = Library.select(results, selectedKeys, selectionAnchor, index, !!(modifiers & Qt.ControlModifier), !!(modifiers & Qt.ShiftModifier));
        selectedKeys = next.keys;
        selectionAnchor = next.anchor;
    }
    function activate(entry): void {
        if (entry.kind === "folder") {
            selectedFolders = [entry.path];
            resultFolder = entry.path;
        } else if (sourceMode === "queue")
            backend.jumpTo(entry.queueIndex);
        else
            backend.enqueueTrack(entry.track, true);
    }
    function panHorizontally(amount): bool {
        const next = Math.max(0, Math.min(horizontal.contentWidth - horizontal.width, horizontal.contentX - amount));
        if (Math.abs(next - horizontal.contentX) < .01)
            return false;
        horizontal.contentX = next;
        return true;
    }
    function openContext(entry, index, anchor): void {
        if (!selectedKeys.includes(Library.key(entry)))
            selectEntry(index, 0);
        const snapshot = selectedTracks.slice();
        contextAnchor = anchor;
        contextActions = [
            {
                iconName: "play_arrow",
                monochromeIcon: true,
                text: Translation.tr("Play selection"),
                action: () => backend.playQueue(snapshot, 0, Translation.tr("Selection"))
            },
            {
                iconName: "playlist_add",
                monochromeIcon: true,
                text: Translation.tr("Add to queue"),
                action: () => backend.enqueueTracks(snapshot)
            },
            {
                iconName: "library_add",
                monochromeIcon: true,
                text: Translation.tr("Create playlist…"),
                action: () => openCreatePlaylist(snapshot)
            }
        ];
        for (const playlist of backend.playlists ?? []) {
            const name = String(playlist.name ?? "");
            if (name)
                contextActions.push({
                    iconName: "queue_music",
                    monochromeIcon: true,
                    text: Translation.tr("Add to %1").arg(name),
                    action: () => backend.addTracksToPlaylist(name, snapshot)
                });
        }
        if (sourceMode === "queue")
            contextActions.push({
                iconName: "remove",
                monochromeIcon: true,
                text: Translation.tr("Remove from queue"),
                action: () => {
                    const current = (backend.activeQueue ?? []).findIndex(track => track === entry.track || (entry.track.queueId !== undefined && track.queueId === entry.track.queueId));
                    if (current >= 0)
                        backend.removeQueueTrack(current);
                }
            });
        contextMenu.requestOpen();
    }
    function openCreatePlaylist(values): void {
        pendingPlaylistTracks = values.slice();
        if (!values.length)
            return;
        playlistName.text = "";
        playlistDialogVisible = true;
        Qt.callLater(() => playlistName.forceActiveFocus());
    }
    function commitPlaylist(): void {
        const name = playlistName.text.trim();
        if (!name || !pendingPlaylistTracks.length)
            return;
        backend.createPlaylist(name, pendingPlaylistTracks);
        playlistDialogVisible = false;
        pendingPlaylistTracks = [];
    }
    onPresentationActiveChanged: if (!presentationActive) {
        queueCollapseTimer.stop();
        queueExpanded = false;
        contextMenu.close();
        playlistDialogVisible = false;
        pendingPlaylistTracks = [];
    }

    Timer {
        id: queueCollapseTimer
        interval: 160
        repeat: false
        onTriggered: if (!queueHover.hovered) root.queueExpanded = false
    }

    QtObject {
        id: playerAdapter
        readonly property string title: root.backend.currentTitle ?? ""
        readonly property string artist: root.backend.currentArtist ?? ""
        readonly property string album: root.backend.currentAlbum ?? ""
        readonly property string artUrl: root.backend.currentArt ?? ""
        readonly property real position: root.backend.lyricsPosition ?? 0
        readonly property real length: root.backend.currentDuration ?? 0
        readonly property bool isPlaying: root.backend.playing ?? false
        readonly property bool canSeek: root.backend.hasCurrentTrack ?? false
        readonly property bool canGoPrevious: root.backend.canGoPrevious ?? false
        readonly property bool canGoNext: root.backend.canGoNext ?? false
        readonly property bool shuffleSupported: root.backend.available ?? false
        readonly property bool shuffle: root.backend.shuffleMode ?? false
        readonly property bool repeatSupported: root.backend.available ?? false
        readonly property int repeatMode: root.backend.repeatMode ?? 0
        function togglePlaying(): void {
            root.backend.togglePlaying();
        }
        function previous(): void {
            root.backend.previous();
        }
        function next(): void {
            root.backend.next();
        }
        function seek(seconds): void {
            root.backend.seek(seconds);
        }
        function toggleShuffle(): void {
            root.backend.toggleShuffle();
        }
        function cycleRepeat(): void {
            root.backend.cycleRepeatMode();
        }
    }
    component MusicScrollBar: ScrollBar {
        id: scrollbar
        policy: root.showMusicScrollbars ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        implicitWidth: 10
        padding: 2
        minimumSize: .05
        contentItem: Rectangle {
            implicitWidth: 6
            implicitHeight: 36
            radius: width / 2
            color: root.accent
            opacity: scrollbar.pressed || scrollbar.active ? .9 : .45
        }
    }
    component Pane: Rectangle {
        property string title: ""
        default property alias content: body.data
        color: root.surface
        radius: root.abyss ? 18 : Appearance.rounding.small
        clip: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: parent.parent.title
                color: root.ink
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
    component Entry: AbstractButton {
        id: entry
        property string caption: ""
        property string detail: ""
        property bool selected: false
        property string glyph: ""
        property string artUrl: ""
        property bool modifierSelection: false
        signal modifierClicked(int modifiers)
        hoverEnabled: true
        implicitHeight: detail ? 52 : 38
        Accessible.name: caption
        MouseArea {
            anchors.fill: parent
            enabled: entry.modifierSelection
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => entry.modifierClicked(event.modifiers)
        }
        background: Rectangle {
            radius: 10
            color: Qt.alpha(root.accent, entry.selected ? .20 : entry.hovered ? .10 : 0)
        }
        contentItem: RowLayout {
            spacing: 5
            Item {
                visible: entry.glyph.length > 0 || entry.artUrl.length > 0
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Image {
                    id: cover
                    anchors.fill: parent
                    source: entry.artUrl
                    asynchronous: true
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectCrop
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready
                    text: entry.glyph
                    color: root.mutedInk
                    iconSize: 20
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: entry.caption
                    color: root.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: entry.detail.length > 0
                    text: entry.detail
                    color: root.mutedInk
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }
        }
        leftPadding: 8
        rightPadding: 8
        topPadding: 6
        bottomPadding: 6
    }
    Rectangle {
        id: backendErrorBar
        objectName: "musicBackendError"
        visible: root.presentationActive && root.backendError.length > 0
        z: 2
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: visible ? 36 : 0
        radius: 10
        color: Qt.alpha(Appearance.colors.colError, 0.12)
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colError, 0.28)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 7
            MaterialSymbol {
                text: "error_outline"
                iconSize: 16
                color: Appearance.colors.colError
            }
            StyledText {
                Layout.fillWidth: true
                text: "MPD: " + root.backendError
                color: Appearance.colors.colError
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            AbyssButton {
                visible: typeof root.backend?.refreshStatus === "function"
                text: Translation.tr("Retry")
                outlined: true
                onClicked: root.backend.refreshStatus()
            }
        }
    }
    Flickable {
        id: horizontal
        objectName: "musicColumnsViewport"
        anchors.fill: parent
        anchors.topMargin: backendErrorBar.visible ? backendErrorBar.height + 6 : 0
        contentWidth: Math.max(width, root.hasLyrics ? 1120 : 980)
        contentHeight: height
        onContentWidthChanged: contentX = Math.max(0, Math.min(contentX, contentWidth - width))
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.horizontal: ScrollBar {
            policy: root.showMusicScrollbars ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
        Row {
            width: horizontal.contentWidth
            height: horizontal.height
            spacing: 8
            // The media/DSP controls need a bounded width; Results gets the
            // recovered horizontal space instead of an oversized media column.
            readonly property int shownColumns: root.hasLyrics ? 4 : 3
            readonly property real mediaColumnWidth: Math.min(380, Math.max(315, width * .29))
            readonly property real remainingWidth: width - spacing * (shownColumns - 1) - mediaColumnWidth
            readonly property real libraryWidth: remainingWidth * (root.hasLyrics ? .32 : .34)
            readonly property real resultsWidth: remainingWidth * (root.hasLyrics ? .45 : .66)
            readonly property real lyricsWidth: root.hasLyrics
                ? Math.max(0, remainingWidth - libraryWidth - resultsWidth) : 0
            Pane {
                id: libraryPane
                objectName: "musicLibrary"
                width: parent.libraryWidth
                height: parent.height
                title: Translation.tr("Library")
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        AbyssButton {
                            objectName: "musicGenreTab"
                            Layout.fillWidth: true
                            text: Translation.tr("Genre")
                            outlined: false
                            // Keep tab highlight declarative; a button click must
                            // not imperatively toggle away the bound checked state.
                            checked: root.libraryTab === "genre"
                            onClicked: root.switchLibraryTab("genre")
                        }
                        AbyssButton {
                            objectName: "musicFolderTab"
                            Layout.fillWidth: true
                            text: Translation.tr("Folders")
                            outlined: false
                            // Keep tab highlight declarative; a button click must
                            // not imperatively toggle away the bound checked state.
                            checked: root.libraryTab === "folder"
                            onClicked: root.switchLibraryTab("folder")
                        }
                    }
                    Item {
                        objectName: "musicGenres"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.libraryTab === "genre"
                        ListView {
                            id: genreList
                            objectName: "musicGenreList"
                            anchors.fill: parent
                            model: root.genres
                            clip: true
                            spacing: 3
                            ScrollBar.vertical: MusicScrollBar {}
                            delegate: Entry {
                                required property var modelData
                                width: ListView.view.width
                                caption: modelData.key || Translation.tr("Unknown genre")
                                detail: Translation.tr("%1 tracks").arg(modelData.count)
                                selected: root.sourceMode === "genre" && root.selectedGenres.includes(modelData.key)
                                modifierSelection: true
                                onModifierClicked: modifiers => root.chooseGenre(modelData.key, modifiers)
                                onClicked: root.chooseGenre(modelData.key)
                            }
                        }
                    }
                    Item {
                        objectName: "musicFolders"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.libraryTab === "folder"
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            ListView {
                                id: folderList
                                objectName: "musicFolderList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: root.folders
                                clip: true
                                spacing: 3
                                ScrollBar.vertical: MusicScrollBar {}
                                delegate: Entry {
                                    required property var modelData
                                    width: ListView.view.width
                                    caption: modelData.name
                                    detail: Translation.tr("%1 tracks").arg(modelData.count)
                                    selected: root.sourceMode === "folder" && root.selectedFolders.includes(modelData.path)
                                    modifierSelection: true
                                    onModifierClicked: modifiers => root.chooseFolder(modelData.path, modifiers)
                                    onClicked: root.chooseFolder(modelData.path)
                                }
                            }
                            StyledText {
                                visible: (root.backend.playlists ?? []).length > 0
                                text: Translation.tr("Playlists")
                                color: root.ink
                            }
                            ListView {
                                id: playlistList
                                objectName: "musicPlaylistList"
                                visible: count > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(contentHeight, parent.height * .35)
                                model: root.backend.playlists ?? []
                                clip: true
                                ScrollBar.vertical: MusicScrollBar {}
                                delegate: Entry {
                                    required property var modelData
                                    width: ListView.view.width
                                    caption: String(modelData.name ?? "")
                                    detail: Translation.tr("%1 tracks").arg(modelData.tracks?.length ?? 0)
                                    glyph: "queue_music"
                                    selected: root.sourceMode === "playlist" && root.selectedPlaylist === modelData
                                    onClicked: root.choosePlaylist(modelData)
                                    onDoubleClicked: root.backend.playCollection(modelData)
                                }
                            }
                            AbyssButton {
                                Layout.fillWidth: true
                                text: Translation.tr("Update")
                                glyph: "refresh"
                                outlined: false
                                enabled: root.backend.available ?? false
                                onClicked: root.backend.updateDatabase()
                            }
                        }
                    }
                }
            }
            Pane {
                objectName: "musicResults"
                width: parent.resultsWidth
                height: parent.height
                title: root.sourceMode === "queue" ? Translation.tr("Queue") : root.sourceMode === "playlist" ? String(root.selectedPlaylist?.name ?? Translation.tr("Playlist")) : root.sourceMode === "genre" ? root.selectedGenres.map(value => value || Translation.tr("Unknown genre")).join(", ") : root.sourceMode === "folder" ? (root.selectedFolders.length > 1 ? root.selectedFolders.map(value => value || Translation.tr("Music library")).join(", ") : root.resultFolder || Translation.tr("Music library")) : Translation.tr("Results")
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 36
                        Layout.maximumHeight: 36
                        spacing: 3
                        ToolbarTextField {
                            id: search
                            objectName: "musicSearch"
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.minimumWidth: 0
                            placeholderText: Translation.tr("Search music")
                        }
                        AbyssButton {
                            objectName: "musicQueue"
                            compact: true
                            glyph: "queue_music"
                            description: Translation.tr("Queue")
                            outlined: false
                            onClicked: {
                                root.query = "";
                                root.sourceMode = "queue";
                            }
                        }
                        AbyssButton {
                            visible: root.sourceMode === "queue"
                            compact: true
                            glyph: "delete_sweep"
                            description: Translation.tr("Clear queue")
                            outlined: false
                            onClicked: root.backend.clearQueue()
                        }
                    }
                    AbyssButton {
                        visible: root.sourceMode === "folder" && root.resultFolder.length > 0
                        text: Translation.tr("Parent folder")
                        glyph: "arrow_upward"
                        outlined: false
                        onClicked: root.resultFolder = Library.parent(root.resultFolder)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        AbyssButton {
                            objectName: "musicPlayAll"
                            Layout.fillWidth: true
                            compact: false
                            glyph: "play_arrow"
                            text: Translation.tr("Play All")
                            outlined: false
                            enabled: root.allResultTracks.length > 0
                            onClicked: root.backend.playQueue(root.allResultTracks, 0, Translation.tr("Results"))
                        }
                        AbyssButton {
                            objectName: "musicPlaySelection"
                            Layout.fillWidth: true
                            compact: false
                            glyph: "playlist_play"
                            text: Translation.tr("Play Selected")
                            outlined: false
                            enabled: root.selectedTracks.length > 0
                            onClicked: root.backend.playQueue(root.selectedTracks, 0, Translation.tr("Selection"))
                        }
                        AbyssButton {
                            objectName: "musicEnqueueSelection"
                            compact: true
                            glyph: "playlist_add"
                            description: Translation.tr("Add to queue")
                            outlined: false
                            enabled: root.selectedTracks.length > 0
                            onClicked: root.backend.enqueueTracks(root.selectedTracks)
                        }
                    }
                    ListView {
                        id: resultList
                        objectName: "musicResultList"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.results
                        clip: true
                        spacing: 3
                        ScrollBar.vertical: MusicScrollBar {}
                        delegate: Entry {
                            id: resultEntry
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            caption: modelData.name
                            glyph: modelData.kind === "folder" ? "folder" : "music_note"
                            artUrl: modelData.kind === "track" ? String(modelData.track.artUrl ?? modelData.track.art ?? "") : ""
                            detail: modelData.kind === "folder" ? Translation.tr("Folder · %1 tracks").arg(modelData.count) : String(modelData.track.artist ?? "")
                            selected: root.selectedKeys.includes(Library.key(modelData))
                            onClicked: root.selectEntry(index, 0)
                            Keys.onReturnPressed: root.activate(modelData)
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: event => {
                                    if (event.button === Qt.RightButton)
                                        root.openContext(resultEntry.modelData, resultEntry.index, resultEntry);
                                    else
                                        root.selectEntry(resultEntry.index, event.modifiers);
                                }
                                onDoubleClicked: event => {
                                    if (event.button === Qt.LeftButton)
                                        root.activate(resultEntry.modelData);
                                }
                            }
                        }
                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            color: root.mutedInk
                            visible: root.results.length === 0
                            text: root.sourceMode || root.query ? Translation.tr("No tracks") : ""
                        }
                    }
                }
            }
            Item {
                objectName: "musicPlaybackAndQueue"
                width: parent.mediaColumnWidth
                height: parent.height
                readonly property real spacing: 8
                // Render the same Dashboard Media card as the Dashboard tab.
                // The optional playback adapter keeps this card on LocalMusic/
                // MPD even when a global MPRIS player is absent.
                DashMedia {
                    id: musicPlayer
                    objectName: "musicPlayer"
                    width: parent.width
                    // Natural media height includes PlayerControl, LocalMusic
                    // volume and (unless Queue hovered) the shared DSP.
                    // Never stretch the card into a tall empty container.
                    // Remaining height belongs to Queue, keeping a small queue
                    // viewport available on short screens.
                    height: Math.max(0, Math.min(
                        Math.ceil(implicitHeight),
                        parent.height - parent.spacing - 108))
                    mediaBackend: root.backend
                    playbackAdapter: playerAdapter
                    showEqualizer: !root.queueExpanded
                    presentationActive: root.presentationActive
                    Behavior on height {
                        enabled: root.presentationActive && Appearance.animationsEnabled
                        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
                    }
                }
                Pane {
                    id: musicQueuePanel
                    objectName: "musicQueuePanel"
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(0, parent.height - musicPlayer.height - parent.spacing)
                    title: Translation.tr("Queue")
                    // One animation clock (Player height) keeps the Queue's
                    // bottom fixed while its top edge slides upwards.
                    HoverHandler {
                        id: queueHover
                        parent: musicQueuePanel
                        enabled: root.presentationActive
                        onHoveredChanged: {
                            if (hovered) {
                                queueCollapseTimer.stop()
                                root.queueExpanded = true
                            } else {
                                queueCollapseTimer.restart()
                            }
                        }
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("%1 tracks").arg((root.backend.activeQueue ?? []).length)
                                color: root.mutedInk
                            }
                            AbyssButton {
                                objectName: "musicClearQueue"
                                compact: true
                                glyph: "delete_sweep"
                                description: Translation.tr("Clear queue")
                                outlined: false
                                enabled: (root.backend.activeQueue ?? []).length > 0
                                onClicked: root.backend.clearQueue()
                            }
                        }
                        ListView {
                            id: queueList
                            objectName: "musicQueueList"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            model: root.backend.activeQueue ?? []
                            ScrollBar.vertical: MusicScrollBar {}
                            delegate: Entry {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                caption: String(modelData.title || modelData.uri || "")
                                detail: String(modelData.artist ?? "")
                                glyph: "music_note"
                                artUrl: String(modelData.artUrl ?? modelData.art ?? "")
                                onDoubleClicked: root.backend.jumpTo(index)
                            }
                        }
                    }
                }
            }
            Pane {
                objectName: "musicLyrics"
                visible: root.hasLyrics
                width: root.hasLyrics ? parent.lyricsWidth : 0
                height: parent.height
                title: Translation.tr("Lyrics")
                ListView {
                    id: lyricsList
                    objectName: "musicLyricsList"
                    anchors.fill: parent
                    clip: true
                    spacing: 12
                    model: root.backend.localLyricsLines ?? []
                    ScrollBar.vertical: MusicScrollBar {}
                    currentIndex: root.presentationActive ? (root.backend.localLyricsActiveIndex ?? -1) : -1
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: height * .35
                    preferredHighlightEnd: height * .65
                    delegate: StyledText {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        text: String(modelData.text ?? "")
                        wrapMode: Text.WordWrap
                        color: index === ListView.view.currentIndex ? root.ink : root.mutedInk
                        font.weight: index === ListView.view.currentIndex ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }
    ContextMenu {
        id: contextMenu
        anchorItem: root.contextAnchor ?? root
        model: root.contextActions
        closeOnHoverLost: false
        closeOnFocusLost: true
    }
    Rectangle {
        anchors.fill: parent
        visible: root.playlistDialogVisible
        z: 100
        color: Qt.alpha(root.surface, .9)
        MouseArea {
            anchors.fill: parent
            onClicked: root.playlistDialogVisible = false
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 320)
            height: 160
            radius: 18
            color: root.surface
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8
                StyledText {
                    text: Translation.tr("Create playlist…")
                    color: root.ink
                }
                ToolbarTextField {
                    id: playlistName
                    objectName: "musicPlaylistName"
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Playlist name")
                    onAccepted: root.commitPlaylist()
                    Keys.onEscapePressed: root.playlistDialogVisible = false
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item {
                        Layout.fillWidth: true
                    }
                    AbyssButton {
                        text: Translation.tr("Cancel")
                        outlined: false
                        onClicked: root.playlistDialogVisible = false
                    }
                    AbyssButton {
                        text: Translation.tr("Create")
                        outlined: false
                        enabled: playlistName.text.trim().length > 0
                        onClicked: root.commitPlaylist()
                    }
                }
            }
        }
    }
}
