pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.mediaControls
import qs.modules.abyss.looks
import qs.modules.waffle.looks as Waffle
import "DashboardMusicModel.js" as Library

Item {
    id: root
    objectName: "dashboardMusic"

    // Local MPD backend (real LocalMusic service or test mock implementing the same shape)
    required property var backend
    property bool presentationActive: visible
    readonly property bool showMusicScrollbars: Config.options?.dashboard?.music?.showScrollbars ?? false
    readonly property bool isWaffle: Config.options?.panelFamily === "waffle"
    readonly property bool isAbyss: Config.options?.panelFamily === "abyss"

    // Palette tokens shared cleanly across Abyss / Material / Waffle
    readonly property color colBg: root.isWaffle
        ? Waffle.Looks.colors.bgPanelFooterBase
        : (root.isAbyss ? AbyssStyle.contentLayer : Appearance.colors.colLayer1)
    readonly property color colSurface: root.isWaffle
        ? Waffle.Looks.colors.bg1
        : (root.isAbyss ? Qt.rgba(1, 1, 1, 0.04) : Appearance.colors.colLayer2)
    readonly property color colSurfaceHover: root.isWaffle
        ? Waffle.Looks.colors.bg1Hover
        : (root.isAbyss ? Qt.rgba(1, 1, 1, 0.08) : Appearance.colors.colLayer2Hover)
    readonly property color colBorder: root.isWaffle
        ? Waffle.Looks.colors.bg1Border
        : Appearance.colors.colLayer0Border
    readonly property color colText: root.isWaffle
        ? Waffle.Looks.colors.fg
        : Appearance.colors.colOnLayer1
    readonly property color colSubtext: root.isWaffle
        ? Waffle.Looks.colors.subfg
        : Appearance.colors.colSubtext
    readonly property color accent: root.isWaffle
        ? Waffle.Looks.colors.accent
        : Appearance.colors.colPrimary
    readonly property color colOnAccent: root.isWaffle
        ? Waffle.Looks.colors.accentFg
        : Appearance.colors.colOnPrimary
    readonly property string uiFont: root.isWaffle
        ? Waffle.Looks.font.family.ui
        : Appearance.font.family.main

    // Navigation & library browser state (persisted in GlobalStates.dashboardMusicBrowser)
    property string viewMode: "home" // home | albums | artists | songs | genre | folder | playlist | queue | search
    property string libraryTab: "genre" // genre | folder
    property string sourceMode: "" // "" when on clean Home overview; else genre | folder | playlist | queue | search | album | artist | songs
    property var selectedGenres: []
    property int genreAnchor: -1
    property var selectedFolders: []
    property int folderAnchor: -1
    property string resultFolder: ""
    property string selectedAlbum: ""
    property string selectedArtist: ""
    property string selectedPlaylist: ""
    property string query: ""
    property string sortField: "default" // default | title | artist | album | duration
    property bool sortAscending: true
    property var selectedKeys: []
    property int trackAnchor: -1

    property bool sidebarCollapsed: false
    property bool libraryExpanded: true
    property bool rightDrawerOpen: true
    property string rightDrawerTab: "queue" // queue | lyrics (also accepts legacy "eq")
    readonly property bool lyricsEqTabActive: root.rightDrawerTab === "lyrics" || root.rightDrawerTab === "eq"
    readonly property string activeSidebarKey: {
        if (root.sourceMode === "search" || root.viewMode === "search")
            return "search";
        if (root.sourceMode === "songs" || root.viewMode === "songs")
            return "songs";
        if (root.sourceMode === "album" || root.viewMode === "albums")
            return "albums";
        if (root.sourceMode === "artist" || root.viewMode === "artists")
            return "artists";
        if (root.sourceMode === "queue" || root.viewMode === "queue")
            return "queue";
        if (root.sourceMode === "genre" || root.viewMode === "genre")
            return "genre";
        if (root.sourceMode === "folder" || root.sourceMode === "playlist" || root.viewMode === "folder")
            return "folder";
        return "home";
    }
    property bool ambientOpen: false
    readonly property bool narrowLayout: width > 0 && width < 780

    property var _navHistory: []
    property int _navIndex: -1
    property bool _restoringState: false
    property bool _navigatingHistory: false
    readonly property bool canGoBack: _navIndex > 0
    readonly property bool canGoForward: _navIndex >= 0 && _navIndex < _navHistory.length - 1

    // Modals & context menu
    property bool playlistDialogVisible: false
    property var _playlistTargetTracks: []
    property var contextActions: []
    property bool contextMenuVisible: false
    property real contextMenuX: 0
    property real contextMenuY: 0

    readonly property var libraryTracks: root.backend?.libraryTracks ?? []
    readonly property var libraryIndex: Library.createIndex(root.libraryTracks)
    readonly property var genres: Library.genres(root.libraryTracks, root.libraryIndex)
    readonly property var folders: Library.roots(root.libraryTracks, root.libraryIndex)
    readonly property var albums: Library.albums(root.libraryTracks, root.libraryIndex)
    readonly property var artists: Library.artists(root.libraryTracks, root.libraryIndex)
    readonly property var playlists: root.backend?.playlists ?? []
    readonly property var activeQueue: root.backend?.activeQueue ?? []
    readonly property int currentQueueIndex: Number(root.backend?.currentIndex ?? -1)
    readonly property string currentTrackTitle: String(root.backend?.currentTitle ?? "")
    readonly property string currentTrackArtist: String(root.backend?.currentArtist ?? "")
    readonly property string currentTrackAlbum: String(root.backend?.currentAlbum ?? "")
    readonly property string currentTrackArt: root.resolveArt(root.backend?.currentArt ?? "")
    readonly property real currentPosition: Math.max(0, Number(root.backend?.currentPosition ?? 0) || 0)
    readonly property real currentDuration: Math.max(0, Number(root.backend?.currentDuration ?? 0) || 0)
    readonly property bool isPlaying: Boolean(root.backend?.playing)
    readonly property bool shuffleActive: Boolean(root.backend?.shuffleMode)
    readonly property int repeatModeValue: Number(root.backend?.repeatMode ?? 0) || 0
    readonly property var lyricsLines: root.backend?.localLyricsLines ?? []
    readonly property int lyricsActiveIndex: Number(root.backend?.localLyricsActiveIndex ?? -1)
    readonly property bool backendAvailable: root.backend ? (root.backend.available !== false) : false
    readonly property string backendError: String(root.backend?.error ?? "")
    readonly property bool showErrorBanner: !root.backendAvailable || root.backendError.length > 0

    readonly property var pinnedItems: {
        const items = [];
        for (const pl of root.playlists) {
            if (!pl || !pl.name) continue;
            const tracks = pl.tracks ?? [];
            const firstArt = tracks.length > 0 ? root.trackArt(tracks[0]) : "";
            items.push({
                kind: "playlist",
                key: String(pl.name),
                name: String(pl.name),
                sublabel: Translation.tr("Playlist · %1 songs").arg(tracks.length),
                art: firstArt,
                tracks: tracks
            });
            if (items.length >= 4) break;
        }
        for (const al of root.albums) {
            if (items.length >= 6) break;
            if (!al || !al.name) continue;
            items.push({
                kind: "album",
                key: String(al.key),
                name: String(al.name),
                sublabel: Translation.tr("Album · %1").arg(al.artist || Translation.tr("Local")),
                art: root.resolveArt(al.artUrl || al.art || ""),
                tracks: al.tracks ?? []
            });
        }
        return items;
    }

    readonly property var rawResults: {
        if (root.sourceMode === "search") {
            if (root.query.trim().length === 0)
                return [];
            return Library.search(root.libraryIndex, root.query).map(track => ({
                kind: "track",
                track: track,
                name: String(track?.title || track?.uri || "")
            }));
        }
        if (root.sourceMode === "genre") {
            return Library.results(root.libraryTracks, "genre", root.selectedGenres, "", root.libraryIndex);
        }
        if (root.sourceMode === "folder") {
            if (root.resultFolder.length > 0)
                return Library.contents(root.libraryTracks, root.resultFolder, root.libraryIndex);
            return Library.results(root.libraryTracks, "folder", "", root.selectedFolders, root.libraryIndex);
        }
        if (root.sourceMode === "album") {
            const album = root.albums.find(a => a.key === root.selectedAlbum);
            return (album?.tracks ?? []).map(track => ({
                kind: "track",
                track: track,
                name: String(track?.title || track?.uri || "")
            }));
        }
        if (root.sourceMode === "artist") {
            const artist = root.artists.find(a => a.key === root.selectedArtist);
            return (artist?.tracks ?? []).map(track => ({
                kind: "track",
                track: track,
                name: String(track?.title || track?.uri || "")
            }));
        }
        if (root.sourceMode === "playlist") {
            const pl = root.playlists.find(p => String(p?.name ?? "") === root.selectedPlaylist);
            return (pl?.tracks ?? []).map(track => ({
                kind: "track",
                track: track,
                name: String(track?.title || track?.uri || "")
            }));
        }
        if (root.sourceMode === "songs") {
            return root.libraryTracks.map(track => ({
                kind: "track",
                track: track,
                name: String(track?.title || track?.uri || "")
            }));
        }
        if (root.sourceMode === "queue") {
            const q = root.activeQueue;
            const indexed = [];
            for (let i = 0; i < q.length; ++i) {
                const track = q[i];
                if (!track) continue;
                indexed.push({
                    kind: "track",
                    track: track,
                    name: String(track?.title || track?.uri || ""),
                    queueIndex: i
                });
            }
            const qText = root.query.trim();
            if (qText.length === 0)
                return indexed;
            const matchedSet = new Set(Library.matching(q, qText, null));
            return indexed.filter(entry => matchedSet.has(entry.track));
        }
        return [];
    }

    readonly property var results: root.sortField === "default"
        ? root.rawResults
        : Library.sortEntries(root.rawResults, root.sortField, root.sortAscending)

    readonly property var allResultTracks: {
        if (root.sourceMode === "folder" && root.selectedFolders.length > 0 && root.resultFolder.length === 0) {
            const keys = root.selectedFolders.map(path => "d:" + path);
            return Library.selectedTracks(root.libraryTracks, keys, root.libraryIndex);
        }
        const out = [];
        for (const entry of root.results) {
            if (entry?.kind === "track" && entry.track)
                out.push(entry.track);
        }
        return out;
    }

    readonly property var selectedTracks: Library.selectedTracks(root.libraryTracks, root.selectedKeys, root.libraryIndex)

    readonly property var heroMeta: {
        const tracks = root.allResultTracks;
        const durStr = Library.formatDuration(Library.totalDuration(tracks));
        if (root.sourceMode === "album") {
            const al = root.albums.find(a => a.key === root.selectedAlbum);
            return {
                badge: Translation.tr("ALBUM"),
                title: al?.name || root.selectedAlbum || Translation.tr("Album"),
                subtitle: `${al?.artist || Translation.tr("Local Library")} · ${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
                art: root.resolveArt(al?.artUrl || al?.art || (tracks[0] ? root.trackArt(tracks[0]) : "")),
                isCircular: false,
                icon: "album"
            };
        }
        if (root.sourceMode === "artist") {
            const ar = root.artists.find(a => a.key === root.selectedArtist);
            return {
                badge: Translation.tr("ARTIST"),
                title: ar?.name || root.selectedArtist || Translation.tr("Artist"),
                subtitle: `${Translation.tr("%1 albums").arg(ar?.albumCount ?? 0)} · ${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
                art: root.resolveArt(ar?.artUrl || ar?.art || (tracks[0] ? root.trackArt(tracks[0]) : "")),
                isCircular: true,
                icon: "person"
            };
        }
        if (root.sourceMode === "playlist") {
            return {
                badge: Translation.tr("PLAYLIST"),
                title: root.selectedPlaylist || Translation.tr("Playlist"),
                subtitle: `${Translation.tr("Local playlist")} · ${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
                art: tracks[0] ? root.trackArt(tracks[0]) : "",
                isCircular: false,
                icon: "queue_music"
            };
        }
        if (root.sourceMode === "genre") {
            const title = root.selectedGenres.map(g => g || Translation.tr("Unknown genre")).join(", ");
            return {
                badge: Translation.tr("GENRE"),
                title: title || Translation.tr("Genres"),
                subtitle: `${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
                art: tracks[0] ? root.trackArt(tracks[0]) : "",
                isCircular: false,
                icon: "category"
            };
        }
        if (root.sourceMode === "folder") {
            const title = root.resultFolder.length > 0
                ? root.resultFolder
                : (root.selectedFolders.map(f => f || Translation.tr("Music library")).join(", ") || Translation.tr("Folders"));
            return {
                badge: Translation.tr("FOLDER"),
                title: title,
                subtitle: `${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
                art: tracks[0] ? root.trackArt(tracks[0]) : "",
                isCircular: false,
                icon: "folder"
            };
        }
        if (root.sourceMode === "queue") {
            return {
                badge: Translation.tr("QUEUE"),
                title: Translation.tr("Playback Queue"),
                subtitle: `${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
                art: root.currentTrackArt || (tracks[0] ? root.trackArt(tracks[0]) : ""),
                isCircular: false,
                icon: "playlist_play"
            };
        }
        if (root.sourceMode === "search") {
            return {
                badge: Translation.tr("SEARCH"),
                title: root.query.trim().length > 0 ? `"${root.query.trim()}"` : Translation.tr("Search Local Music"),
                subtitle: `${Translation.tr("%1 matches").arg(tracks.length)} · ${durStr}`,
                art: tracks[0] ? root.trackArt(tracks[0]) : "",
                isCircular: false,
                icon: "search"
            };
        }
        return {
            badge: Translation.tr("LOCAL LIBRARY"),
            title: Translation.tr("All Songs"),
            subtitle: `${Translation.tr("%1 songs").arg(tracks.length)} · ${durStr}`,
            art: tracks[0] ? root.trackArt(tracks[0]) : "",
            isCircular: false,
            icon: "library_music"
        };
    }

    // ── Local-only safe asset & backend helpers ──────────────────────────────
    function resolveArt(raw): string {
        const s = String(raw ?? "").trim();
        if (s.length === 0) return "";
        if (s.startsWith("file://") || s.startsWith("qrc:/") || s.startsWith("image://"))
            return s;
        if (s.startsWith("/"))
            return "file://" + s;
        return "";
    }

    function trackArt(track): string {
        if (!track) return "";
        return root.resolveArt(track.artUrl || track.art || "");
    }

    function _hasFn(name): bool {
        return Boolean(root.backend && typeof root.backend[name] === "function");
    }

    function _safePlayQueue(tracks, index, label): void {
        if (!tracks || tracks.length === 0) return;
        if (root._hasFn("playQueue"))
            root.backend.playQueue(tracks, index, label || "");
        else if (root._hasFn("enqueueTrack") && tracks[index])
            root.backend.enqueueTrack(tracks[index], true);
    }

    function _safeEnqueueTracks(tracks): void {
        if (!tracks || tracks.length === 0) return;
        if (root._hasFn("enqueueTracks"))
            root.backend.enqueueTracks(tracks);
        else if (root._hasFn("enqueueTrack"))
            for (const t of tracks) root.backend.enqueueTrack(t, false);
    }

    function _safeEnqueueTrack(track, playNow): void {
        if (!track) return;
        if (root._hasFn("enqueueTrack"))
            root.backend.enqueueTrack(track, Boolean(playNow));
        else if (playNow)
            root._safePlayQueue([track], 0, "");
    }

    function _safeTogglePlaying(): void {
        if (root._hasFn("togglePlaying"))
            root.backend.togglePlaying();
        else if (root.activeQueue.length > 0 && root._hasFn("jumpTo"))
            root.backend.jumpTo(Math.max(0, root.currentQueueIndex));
    }

    function _safeNext(): void {
        if (root._hasFn("next")) root.backend.next();
    }

    function _safePrevious(): void {
        if (root._hasFn("previous")) root.backend.previous();
    }

    function _safeSeek(seconds): void {
        if (root._hasFn("seek")) root.backend.seek(seconds);
    }

    function _safeSetVolume(value): void {
        if (root._hasFn("setVolume")) root.backend.setVolume(value);
    }

    function _safeToggleShuffle(): void {
        if (root._hasFn("toggleShuffle")) root.backend.toggleShuffle();
    }

    function _safeCycleRepeat(): void {
        if (root._hasFn("cycleRepeatMode")) root.backend.cycleRepeatMode();
    }

    function _safeJumpTo(index): void {
        if (root._hasFn("jumpTo")) root.backend.jumpTo(index);
    }

    function _safeRemoveQueueTrack(index): void {
        if (root._hasFn("removeQueueTrack")) root.backend.removeQueueTrack(index);
    }

    function _safeClearQueue(): void {
        if (root._hasFn("clearQueue")) root.backend.clearQueue();
    }

    function _safeUpdateDatabase(): void {
        if (root._hasFn("updateDatabase")) root.backend.updateDatabase();
        if (root._hasFn("rescan")) root.backend.rescan();
    }

    // ── State Persistence & Nav History ──────────────────────────────────────
    function _saveBrowserState(): void {
        if (root._restoringState) return;
        GlobalStates.dashboardMusicBrowser = {
            viewMode: root.viewMode,
            mode: root.sourceMode,
            tab: root.libraryTab,
            genres: (root.selectedGenres ?? []).slice(),
            folders: (root.selectedFolders ?? []).slice(),
            folder: root.resultFolder,
            album: root.selectedAlbum,
            artist: root.selectedArtist,
            playlist: root.selectedPlaylist,
            query: root.query,
            rightTab: root.rightDrawerTab,
            drawerOpen: root.rightDrawerOpen,
            sortField: root.sortField,
            sortAsc: root.sortAscending
        };
    }

    function _snapshotNav(): var {
        return {
            viewMode: root.viewMode,
            sourceMode: root.sourceMode,
            libraryTab: root.libraryTab,
            selectedGenres: (root.selectedGenres ?? []).slice(),
            selectedFolders: (root.selectedFolders ?? []).slice(),
            resultFolder: root.resultFolder,
            selectedAlbum: root.selectedAlbum,
            selectedArtist: root.selectedArtist,
            selectedPlaylist: root.selectedPlaylist
        };
    }

    function _pushHistory(): void {
        if (root._restoringState || root._navigatingHistory) return;
        const snap = root._snapshotNav();
        const serialized = JSON.stringify(snap);
        if (root._navIndex >= 0 && root._navIndex < root._navHistory.length) {
            if (JSON.stringify(root._navHistory[root._navIndex]) === serialized)
                return;
        }
        const next = root._navHistory.slice(0, root._navIndex + 1);
        next.push(snap);
        if (next.length > 24) next.shift();
        root._navHistory = next;
        root._navIndex = next.length - 1;
    }

    function _applyNavSnapshot(snap): void {
        if (!snap) return;
        root._navigatingHistory = true;
        try {
            root.viewMode = String(snap.viewMode ?? "home");
            root.sourceMode = String(snap.sourceMode ?? "");
            root.libraryTab = String(snap.libraryTab ?? "genre");
            root.selectedGenres = Array.isArray(snap.selectedGenres) ? snap.selectedGenres.slice() : [];
            root.selectedFolders = Array.isArray(snap.selectedFolders) ? snap.selectedFolders.slice() : [];
            root.resultFolder = String(snap.resultFolder ?? "");
            root.selectedAlbum = String(snap.selectedAlbum ?? "");
            root.selectedArtist = String(snap.selectedArtist ?? "");
            root.selectedPlaylist = String(snap.selectedPlaylist ?? "");
            root.selectedKeys = [];
        } finally {
            root._navigatingHistory = false;
        }
        root._saveBrowserState();
    }

    function goBack(): void {
        if (!root.canGoBack) return;
        root._navIndex = Math.max(0, root._navIndex - 1);
        root._applyNavSnapshot(root._navHistory[root._navIndex]);
    }

    function goForward(): void {
        if (!root.canGoForward) return;
        root._navIndex = Math.min(root._navHistory.length - 1, root._navIndex + 1);
        root._applyNavSnapshot(root._navHistory[root._navIndex]);
    }

    // ── Navigation / Browser API (preserving legacy contracts) ───────────────
    function switchLibraryTab(tab): void {
        const normalized = tab === "folder" ? "folder" : "genre";
        root.libraryTab = normalized;
        if (normalized === "genre") {
            root.sourceMode = root.selectedGenres.length > 0 ? "genre" : "";
            root.viewMode = "genre";
        } else {
            root.sourceMode = (root.selectedFolders.length > 0 || root.resultFolder.length > 0) ? "folder" : "";
            root.viewMode = "folder";
        }
        root._saveBrowserState();
    }

    function navigateHome(): void {
        root.sourceMode = "";
        root.viewMode = "home";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openAlbumsGrid(): void {
        root.sourceMode = "";
        root.viewMode = "albums";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openArtistsGrid(): void {
        root.sourceMode = "";
        root.viewMode = "artists";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openAllSongs(): void {
        root.sourceMode = "songs";
        root.viewMode = "songs";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openAlbum(albumKey): void {
        root.selectedAlbum = String(albumKey ?? "");
        root.sourceMode = "album";
        root.viewMode = "albums";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openArtist(artistKey): void {
        root.selectedArtist = String(artistKey ?? "");
        root.sourceMode = "artist";
        root.viewMode = "artists";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openPlaylist(playlistName): void {
        root.selectedPlaylist = String(playlistName ?? "");
        root.sourceMode = "playlist";
        root.viewMode = "folder";
        root.libraryTab = "folder";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function openQueueBrowser(): void {
        root.sourceMode = "queue";
        root.viewMode = "queue";
        root.selectedKeys = [];
        root._pushHistory();
        root._saveBrowserState();
    }

    function chooseGenre(genreKey, modifiers = 0): void {
        const mod = Number(modifiers) || 0;
        const ctrl = Boolean(mod & Qt.ControlModifier);
        const shift = Boolean(mod & Qt.ShiftModifier);
        const values = root.genres.map(g => g.key);
        const idx = values.indexOf(String(genreKey ?? ""));
        if (idx < 0) return;
        root.libraryTab = "genre";
        const sel = Library.selectValues(values, root.selectedGenres, root.genreAnchor, idx, ctrl, shift);
        root.selectedGenres = sel.keys;
        root.genreAnchor = sel.anchor;
        root.resultFolder = "";
        root.selectedKeys = [];
        if (root.selectedGenres.length > 0) {
            root.sourceMode = "genre";
            root.viewMode = "genre";
            root._pushHistory();
        } else {
            root.sourceMode = "";
            root.viewMode = "home";
        }
        root._saveBrowserState();
    }

    function chooseFolder(folderPath, modifiers = 0): void {
        const mod = Number(modifiers) || 0;
        const ctrl = Boolean(mod & Qt.ControlModifier);
        const shift = Boolean(mod & Qt.ShiftModifier);
        const values = root.folders.map(f => f.path);
        const idx = values.indexOf(String(folderPath ?? ""));
        if (idx < 0) return;
        root.libraryTab = "folder";
        const sel = Library.selectValues(values, root.selectedFolders, root.folderAnchor, idx, ctrl, shift);
        root.selectedFolders = sel.keys;
        root.folderAnchor = sel.anchor;
        root.resultFolder = "";
        root.selectedKeys = [];
        if (root.selectedFolders.length > 0) {
            root.sourceMode = "folder";
            root.viewMode = "folder";
            root._pushHistory();
        } else {
            root.sourceMode = "";
            root.viewMode = "home";
        }
        root._saveBrowserState();
    }

    function restoreBrowserColumns(): bool {
        if (root.contextMenuVisible) {
            root.contextMenuVisible = false;
            return true;
        }
        if (root.playlistDialogVisible) {
            root.playlistDialogVisible = false;
            return true;
        }
        if (root.ambientOpen) {
            root.ambientOpen = false;
            return true;
        }
        if (root.sourceMode === "folder" && root.resultFolder.length > 0) {
            const up = Library.parent(root.resultFolder);
            if (up.length > 0 && up !== root.resultFolder && !root.selectedFolders.includes(root.resultFolder)) {
                root.resultFolder = up;
                root.selectedKeys = [];
                root._saveBrowserState();
                return true;
            }
            root.resultFolder = "";
            root.selectedKeys = [];
            root._saveBrowserState();
            return true;
        }
        if (root.sourceMode.length > 0 || root.query.length > 0) {
            root.query = "";
            root.sourceMode = "";
            root.viewMode = "home";
            root.selectedGenres = [];
            root.selectedFolders = [];
            root.selectedAlbum = "";
            root.selectedArtist = "";
            root.selectedPlaylist = "";
            root.resultFolder = "";
            root.selectedKeys = [];
            root._saveBrowserState();
            return true;
        }
        return false;
    }

    function panHorizontally(amount): bool {
        const delta = Number(amount) || 0;
        const maxX = Math.max(0, musicColumnsViewport.contentWidth - musicColumnsViewport.width);
        if (maxX <= 1) return false;
        const nextX = Math.max(0, Math.min(maxX, musicColumnsViewport.contentX - delta));
        if (Math.abs(nextX - musicColumnsViewport.contentX) < 0.5)
            return false;
        musicColumnsViewport.contentX = nextX;
        return true;
    }

    function selectResultRow(index, modifiers): void {
        const mod = Number(modifiers) || 0;
        const ctrl = Boolean(mod & Qt.ControlModifier);
        const shift = Boolean(mod & Qt.ShiftModifier);
        const res = Library.select(root.results, root.selectedKeys, root.trackAnchor, index, ctrl, shift);
        root.selectedKeys = res.keys;
        root.trackAnchor = res.anchor;
    }

    function activateResultRow(entry, index): void {
        if (!entry) return;
        if (entry.kind === "folder") {
            root.sourceMode = "folder";
            root.viewMode = "folder";
            root.resultFolder = String(entry.path ?? "");
            root.selectedKeys = [];
            root._pushHistory();
            root._saveBrowserState();
            return;
        }
        if (entry.kind === "track" && entry.track) {
            if (root.sourceMode === "queue" && entry.queueIndex !== undefined) {
                root._safeJumpTo(entry.queueIndex);
            } else {
                root._safeEnqueueTrack(entry.track, true);
            }
        }
    }

    function openCreatePlaylist(tracks): void {
        const list = (tracks && tracks.length > 0) ? tracks : root.allResultTracks;
        root._playlistTargetTracks = list.slice();
        playlistNameInput.text = "";
        root.playlistDialogVisible = true;
        Qt.callLater(() => playlistNameInput.forceActiveFocus());
    }

    function commitPlaylist(): void {
        const name = playlistNameInput.text.trim();
        if (name.length === 0) return;
        if (root._hasFn("createPlaylist"))
            root.backend.createPlaylist(name, root._playlistTargetTracks);
        root.playlistDialogVisible = false;
    }

    function openContext(entry, index, item): void {
        if (!entry) return;
        const actions = [];
        if (entry.kind === "track" && entry.track) {
            const tracks = root.selectedTracks.length > 1 ? root.selectedTracks : [entry.track];
            actions.push({
                label: tracks.length > 1 ? Translation.tr("Play selected (%1)").arg(tracks.length) : Translation.tr("Play now"),
                icon: "play_arrow",
                action: () => {
                    if (tracks.length === 1) root._safeEnqueueTrack(tracks[0], true);
                    else root._safePlayQueue(tracks, 0, "");
                }
            });
            actions.push({
                label: Translation.tr("Add to queue"),
                icon: "queue_music",
                action: () => root._safeEnqueueTracks(tracks)
            });
            actions.push({
                label: Translation.tr("Save to playlist…"),
                icon: "playlist_add",
                action: () => root.openCreatePlaylist(tracks)
            });
            if (root.sourceMode === "queue" && entry.queueIndex !== undefined) {
                const qIdx = entry.queueIndex;
                actions.push({
                    label: Translation.tr("Remove from queue"),
                    icon: "delete",
                    action: () => root._safeRemoveQueueTrack(qIdx)
                });
            }
        } else if (entry.kind === "folder") {
            const folderPath = String(entry.path ?? "");
            actions.push({
                label: Translation.tr("Open folder"),
                icon: "folder_open",
                action: () => {
                    root.resultFolder = folderPath;
                    root.selectedKeys = [];
                    root._saveBrowserState();
                }
            });
            actions.push({
                label: Translation.tr("Play folder"),
                icon: "play_arrow",
                action: () => {
                    const t = Library.selectedTracks(root.libraryTracks, ["d:" + folderPath], root.libraryIndex);
                    root._safePlayQueue(t, 0, folderPath);
                }
            });
        }
        if (actions.length === 0) return;
        root.contextActions = actions;
        const pt = item ? item.mapToItem(root, Math.min(item.width * 0.5, 180), Math.min(item.height, 28)) : Qt.point(root.width * 0.4, root.height * 0.4);
        root.contextMenuX = Math.max(8, Math.min(root.width - 210, pt.x));
        root.contextMenuY = Math.max(8, Math.min(root.height - 160, pt.y));
        root.contextMenuVisible = true;
    }

    function toggleSort(field): void {
        if (root.sortField === field) {
            if (root.sortAscending) {
                root.sortAscending = false;
            } else {
                root.sortField = "default";
                root.sortAscending = true;
            }
        } else {
            root.sortField = field;
            root.sortAscending = true;
        }
        root._saveBrowserState();
    }

    onQueryChanged: {
        if (root._restoringState) return;
        if (root.query.trim().length > 0 && root.sourceMode !== "queue") {
            root.sourceMode = "search";
            root.viewMode = "search";
        } else if (root.query.trim().length === 0 && root.sourceMode === "search") {
            root.sourceMode = "";
            root.viewMode = "home";
        }
        root._saveBrowserState();
    }

    onLibraryTabChanged: root._saveBrowserState()
    onRightDrawerTabChanged: root._saveBrowserState()
    onRightDrawerOpenChanged: root._saveBrowserState()

    Component.onCompleted: {
        const saved = GlobalStates.dashboardMusicBrowser;
        if (saved && typeof saved === "object" && Object.keys(saved).length > 0) {
            root._restoringState = true;
            try {
                root.libraryTab = saved.tab === "folder" ? "folder" : "genre";
                root.selectedGenres = Array.isArray(saved.genres) ? saved.genres.slice() : [];
                root.selectedFolders = Array.isArray(saved.folders) ? saved.folders.slice() : [];
                root.resultFolder = String(saved.folder ?? "");
                root.selectedAlbum = String(saved.album ?? "");
                root.selectedArtist = String(saved.artist ?? "");
                root.selectedPlaylist = String(saved.playlist ?? "");
                root.query = String(saved.query ?? "");
                root.sourceMode = String(saved.mode ?? "");
                root.viewMode = String(saved.viewMode ?? (root.sourceMode || "home"));
                root.rightDrawerTab = String(saved.rightTab ?? "queue");
                root.rightDrawerOpen = saved.drawerOpen !== undefined ? Boolean(saved.drawerOpen) : true;
                root.sortField = String(saved.sortField ?? "default");
                root.sortAscending = saved.sortAsc !== undefined ? Boolean(saved.sortAsc) : true;
            } finally {
                root._restoringState = false;
            }
        }
        root._pushHistory();
    }

    // Shared ScrollBar honoring Config.options.dashboard.music.showScrollbars
    component SonoraScrollBar: ScrollBar {
        id: sb
        policy: root.showMusicScrollbars ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        visible: root.showMusicScrollbars && sb.size > 0 && sb.size < 0.999
        implicitWidth: orientation === Qt.Vertical ? 7 : 0
        implicitHeight: orientation === Qt.Horizontal ? 7 : 0
        background: Item { visible: false }
        contentItem: Rectangle {
            implicitWidth: 5
            implicitHeight: 5
            radius: 2.5
            color: root.accent
            opacity: root.showMusicScrollbars && sb.size > 0 && sb.size < 0.999
                ? (sb.pressed ? 0.95 : sb.hovered ? 0.85 : 0.65)
                : 0
        }
    }

    component CoverArtBox: Rectangle {
        id: artBox
        property string artSource: ""
        property string fallbackIcon: "music_note"
        property real iconScale: 0.44
        property bool circular: false
        radius: circular ? width / 2 : 6
        color: root.colSurface
        border.width: 1
        border.color: ColorUtils.applyAlpha(root.colBorder, 0.5)
        clip: true

        Image {
            id: coverImg
            anchors.fill: parent
            source: artBox.artSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            visible: artBox.artSource.length > 0 && status === Image.Ready
            layer.enabled: artBox.circular
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: coverImg.width
                    height: coverImg.height
                    radius: artBox.radius
                }
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: !coverImg.visible
            text: artBox.fallbackIcon
            iconSize: Math.max(14, Math.round(Math.min(artBox.width, artBox.height) * artBox.iconScale))
            color: root.colSubtext
        }
    }

    component SonoraPillButton: RippleButton {
        id: pillBtn
        property string iconName: ""
        property string labelText: ""
        property bool primaryFill: false
        implicitHeight: 30
        implicitWidth: pillRow.implicitWidth + (labelText.length > 0 ? 20 : 12)
        buttonRadius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.full
        colBackground: primaryFill ? root.accent : root.colSurface
        colBackgroundHover: primaryFill ? ColorUtils.applyAlpha(root.accent, 0.85) : root.colSurfaceHover
        contentItem: Item {
            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 5
                MaterialSymbol {
                    visible: pillBtn.iconName.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: pillBtn.iconName
                    iconSize: 16
                    color: pillBtn.primaryFill ? root.colOnAccent : root.colText
                }
                StyledText {
                    visible: pillBtn.labelText.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: pillBtn.labelText
                    font.family: root.uiFont
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: pillBtn.primaryFill ? Font.DemiBold : Font.Medium
                    color: pillBtn.primaryFill ? root.colOnAccent : root.colText
                }
            }
        }
    }

    component SidebarNavItem: RippleButton {
        id: navItem
        property string iconName: "home"
        property string labelText: ""
        property bool activeItem: false
        property bool indented: false
        property string trailingText: ""
        Layout.fillWidth: true
        implicitHeight: 28
        buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
        colBackground: activeItem ? ColorUtils.applyAlpha(root.accent, 0.16) : "transparent"
        colBackgroundHover: activeItem ? ColorUtils.applyAlpha(root.accent, 0.22) : root.colSurfaceHover
        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: navItem.indented ? 22 : 8
            anchors.rightMargin: 8
            spacing: 7
            MaterialSymbol {
                visible: navItem.iconName.length > 0
                text: navItem.iconName
                iconSize: 16
                color: navItem.activeItem ? root.accent : root.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: navItem.labelText
                font.family: root.uiFont
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: navItem.activeItem ? Font.DemiBold : Font.Normal
                color: navItem.activeItem ? root.colText : root.colSubtext
                elide: Text.ElideRight
            }
            StyledText {
                visible: navItem.trailingText.length > 0
                text: navItem.trailingText
                font.family: root.uiFont
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.colSubtext
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MAIN SONORA SHELL: TOP HEADER + 3-COLUMN BODY + PERSISTENT PLAYER BAR
    // ══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // 1. Sonora Top Header Bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
            color: root.colBg
            border.width: root.isWaffle ? 1 : 0
            border.color: root.colBorder

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 6

                RippleButton {
                    objectName: "musicSidebarToggle"
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                    colBackground: !root.sidebarCollapsed ? root.colSurface : "transparent"
                    colBackgroundHover: root.colSurfaceHover
                    onClicked: root.sidebarCollapsed = !root.sidebarCollapsed
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "left_panel_close"
                        iconSize: 17
                        color: root.colText
                    }
                    StyledToolTip { text: Translation.tr("Toggle library sidebar") }
                }

                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    enabled: root.canGoBack
                    opacity: enabled ? 1.0 : 0.35
                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: root.colSurfaceHover
                    onClicked: root.goBack()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: 18
                        color: root.colText
                    }
                    StyledToolTip { text: Translation.tr("Back") }
                }

                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    enabled: root.canGoForward
                    opacity: enabled ? 1.0 : 0.35
                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: root.colSurfaceHover
                    onClicked: root.goForward()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: 18
                        color: root.colText
                    }
                    StyledToolTip { text: Translation.tr("Forward") }
                }

                RippleButton {
                    objectName: "musicRescanButton"
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: root.colSurfaceHover
                    onClicked: root._safeUpdateDatabase()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 17
                        color: root.colText
                    }
                    StyledToolTip { text: Translation.tr("Rescan local MPD library") }
                }

                // Inline Search Pill
                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 110
                    Layout.maximumWidth: 420
                    implicitHeight: 28
                    radius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.full
                    color: root.colSurface
                    border.width: 1
                    border.color: searchField.activeFocus ? root.accent : ColorUtils.applyAlpha(root.colBorder, 0.45)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 6
                        spacing: 6

                        MaterialSymbol {
                            text: "search"
                            iconSize: 15
                            color: root.colSubtext
                        }

                        TextInput {
                            id: searchField
                            objectName: "musicSearch"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            clip: true
                            color: root.colText
                            selectionColor: root.accent
                            selectedTextColor: root.colOnAccent
                            font.family: root.uiFont
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.query
                            onTextEdited: root.query = text

                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: searchField.text.length === 0
                                text: Translation.tr("Search local tracks, albums, artists…")
                                font.family: root.uiFont
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        RippleButton {
                            visible: root.query.length > 0
                            implicitWidth: 20
                            implicitHeight: 20
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: root.colSurfaceHover
                            onClicked: {
                                root.query = "";
                                searchField.text = "";
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 13
                                color: root.colSubtext
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    visible: root.width >= 560 && root.sourceMode.length > 0
                    implicitHeight: 28
                    implicitWidth: sortBtnRow.implicitWidth + 14
                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                    colBackground: root.sortField !== "default" ? ColorUtils.applyAlpha(root.accent, 0.16) : root.colSurface
                    colBackgroundHover: root.colSurfaceHover
                    onClicked: {
                        const order = ["default", "title", "artist", "album", "duration"];
                        const next = order[(order.indexOf(root.sortField) + 1) % order.length];
                        root.sortField = next;
                        root.sortAscending = true;
                        root._saveBrowserState();
                    }
                    contentItem: RowLayout {
                        id: sortBtnRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "swap_vert"
                            iconSize: 15
                            color: root.sortField !== "default" ? root.accent : root.colSubtext
                        }
                        StyledText {
                            text: root.sortField === "default"
                                ? Translation.tr("Sort")
                                : root.sortField.charAt(0).toUpperCase() + root.sortField.slice(1) + (root.sortAscending ? " ↑" : " ↓")
                            font.family: root.uiFont
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.colText
                        }
                    }
                    StyledToolTip { text: Translation.tr("Cycle sort order") }
                }

                RippleButton {
                    objectName: "musicRightDrawerToggle"
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                    colBackground: root.rightDrawerOpen ? ColorUtils.applyAlpha(root.accent, 0.16) : "transparent"
                    colBackgroundHover: root.colSurfaceHover
                    onClicked: root.rightDrawerOpen = !root.rightDrawerOpen
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "right_panel_open"
                        iconSize: 17
                        color: root.rightDrawerOpen ? root.accent : root.colText
                    }
                    StyledToolTip { text: Translation.tr("Toggle queue, lyrics & EQ drawer") }
                }
            }
        }

        // 2. Center 3-Column Sonora Stage wrapped in musicColumnsViewport (horizontally pannable when narrow)
        Flickable {
            id: musicColumnsViewport
            objectName: "musicColumnsViewport"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width + 1

            readonly property real sidebarWidth: (!root.sidebarCollapsed)
                ? (width >= 1000 ? 220 : 204)
                : 0
            readonly property real rightDrawerWidth: root.rightDrawerOpen
                ? (width >= 1000 ? 286 : 254)
                : 0
            readonly property real centerMinWidth: width < 960 ? 480 : 340
            readonly property real computedContentWidth: {
                const gaps = (sidebarWidth > 0 ? 6 : 0) + (rightDrawerWidth > 0 ? 6 : 0);
                const needed = sidebarWidth + centerMinWidth + rightDrawerWidth + gaps;
                return width < 960 ? Math.max(width, needed) : width;
            }
            contentWidth: computedContentWidth
            contentHeight: height

            ScrollBar.horizontal: SonoraScrollBar { orientation: Qt.Horizontal }

            Row {
                id: columnsRow
                width: musicColumnsViewport.contentWidth
                height: musicColumnsViewport.height
                spacing: 6

                // 2A. LEFT SONORA SIDEBAR + LIBRARY BROWSER (objectName: "musicLibrary")
                Rectangle {
                    id: musicLibraryColumn
                    objectName: "musicLibrary"
                    visible: musicColumnsViewport.sidebarWidth > 0
                    width: musicColumnsViewport.sidebarWidth
                    height: columnsRow.height
                    radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
                    color: root.colBg
                    border.width: root.isWaffle ? 1 : 0
                    border.color: root.colBorder
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        SidebarNavItem {
                            iconName: "home"
                            labelText: Translation.tr("Home")
                            activeItem: root.activeSidebarKey === "home"
                            onClicked: root.navigateHome()
                        }

                        SidebarNavItem {
                            iconName: "search"
                            labelText: Translation.tr("Search")
                            activeItem: root.activeSidebarKey === "search"
                            onClicked: {
                                root.sourceMode = "search";
                                root.viewMode = "search";
                                searchField.forceActiveFocus();
                            }
                        }

                        // Collapsible Your Library Header
                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: root.colSurfaceHover
                            onClicked: root.libraryExpanded = !root.libraryExpanded
                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 7
                                MaterialSymbol {
                                    text: "library_music"
                                    iconSize: 16
                                    color: root.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Your Library")
                                    font.family: root.uiFont
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: root.colText
                                }
                                MaterialSymbol {
                                    text: root.libraryExpanded ? "expand_less" : "expand_more"
                                    iconSize: 16
                                    color: root.colSubtext
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            visible: root.libraryExpanded
                            columns: 2
                            uniformCellWidths: true
                            columnSpacing: 4
                            rowSpacing: 4

                            SidebarNavItem {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                iconName: "music_note"
                                labelText: Translation.tr("Songs")
                                activeItem: root.activeSidebarKey === "songs"
                                onClicked: root.openAllSongs()
                            }

                            SidebarNavItem {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                iconName: "album"
                                labelText: Translation.tr("Albums")
                                activeItem: root.activeSidebarKey === "albums"
                                onClicked: root.openAlbumsGrid()
                            }

                            SidebarNavItem {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                iconName: "person"
                                labelText: Translation.tr("Artists")
                                activeItem: root.activeSidebarKey === "artists"
                                onClicked: root.openArtistsGrid()
                            }

                            SidebarNavItem {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                objectName: "musicGenreTab"
                                iconName: "category"
                                labelText: Translation.tr("Genres")
                                activeItem: root.activeSidebarKey === "genre"
                                onClicked: root.switchLibraryTab("genre")
                            }

                            SidebarNavItem {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                objectName: "musicFolderTab"
                                iconName: "folder"
                                labelText: Translation.tr("Folders")
                                activeItem: root.activeSidebarKey === "folder"
                                onClicked: root.switchLibraryTab("folder")
                            }

                            SidebarNavItem {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                objectName: "musicQueue"
                                iconName: "playlist_play"
                                labelText: Translation.tr("Queue")
                                activeItem: root.activeSidebarKey === "queue"
                                onClicked: root.openQueueBrowser()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: ColorUtils.applyAlpha(root.colBorder, 0.35)
                        }

                        // Genre or Folder/Playlists Browser Stack (both lists stay mounted inside visible container)
                        Item {
                            id: musicGenresPane
                            objectName: "musicGenres"
                            visible: root.libraryTab === "genre"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 110

                            ListView {
                                id: genreList
                                objectName: "musicGenreList"
                                anchors.fill: parent
                                clip: true
                                model: root.genres
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                                delegate: Item {
                                    id: genreDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property bool isSelected: root.selectedGenres.includes(modelData.key)
                                    width: genreList.width - (root.showMusicScrollbars ? 8 : 0)
                                    height: 28

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: genreDelegate.isSelected
                                            ? ColorUtils.applyAlpha(root.accent, 0.2)
                                            : (genreMa.containsMouse ? root.colSurfaceHover : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6
                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: genreDelegate.modelData.key || Translation.tr("Unknown")
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: genreDelegate.isSelected ? Font.DemiBold : Font.Normal
                                                color: genreDelegate.isSelected ? root.accent : root.colText
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                text: String(genreDelegate.modelData.count ?? 0)
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                        }

                                        MouseArea {
                                            id: genreMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => root.chooseGenre(genreDelegate.modelData.key, mouse.modifiers)
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            id: musicFoldersPane
                            objectName: "musicFolders"
                            visible: root.libraryTab === "folder"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 110
                            spacing: 4

                            ListView {
                                id: folderList
                                objectName: "musicFolderList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredHeight: 1
                                clip: true
                                model: root.folders
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                                delegate: Item {
                                    id: folderDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property bool isSelected: root.selectedFolders.includes(modelData.path)
                                    width: folderList.width - (root.showMusicScrollbars ? 8 : 0)
                                    height: 28

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: folderDelegate.isSelected
                                            ? ColorUtils.applyAlpha(root.accent, 0.2)
                                            : (folderMa.containsMouse ? root.colSurfaceHover : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 6
                                            MaterialSymbol {
                                                text: "folder"
                                                iconSize: 14
                                                color: folderDelegate.isSelected ? root.accent : root.colSubtext
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: folderDelegate.modelData.name || Translation.tr("Music library")
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: folderDelegate.isSelected ? Font.DemiBold : Font.Normal
                                                color: folderDelegate.isSelected ? root.accent : root.colText
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                text: String(folderDelegate.modelData.count ?? 0)
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                        }

                                        MouseArea {
                                            id: folderMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => root.chooseFolder(folderDelegate.modelData.path, mouse.modifiers)
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                text: Translation.tr("PLAYLISTS")
                                font.family: root.uiFont
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: root.colSubtext
                            }

                            ListView {
                                id: playlistList
                                objectName: "musicPlaylistList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredHeight: 1
                                clip: true
                                model: root.playlists
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                                delegate: Item {
                                    id: plDelegate
                                    required property var modelData
                                    readonly property bool isSelected: root.sourceMode === "playlist" && root.selectedPlaylist === String(modelData?.name ?? "")
                                    width: playlistList.width - (root.showMusicScrollbars ? 8 : 0)
                                    height: 28

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: plDelegate.isSelected
                                            ? ColorUtils.applyAlpha(root.accent, 0.2)
                                            : (plMa.containsMouse ? root.colSurfaceHover : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 6
                                            MaterialSymbol {
                                                text: "queue_music"
                                                iconSize: 14
                                                color: plDelegate.isSelected ? root.accent : root.colSubtext
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: String(plDelegate.modelData?.name ?? "")
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: plDelegate.isSelected ? root.accent : root.colText
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                text: String((plDelegate.modelData?.tracks ?? []).length)
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                        }

                                        MouseArea {
                                            id: plMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openPlaylist(plDelegate.modelData?.name ?? "")
                                        }
                                    }
                                }
                            }
                        }

                        // Pinned section (shown when enough vertical space)
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.pinnedItems.length > 0 && musicLibraryColumn.height >= 480
                            spacing: 3

                            StyledText {
                                Layout.leftMargin: 4
                                text: Translation.tr("PINNED")
                                font.family: root.uiFont
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: root.colSubtext
                            }

                            Repeater {
                                model: root.pinnedItems.slice(0, 3)
                                delegate: RippleButton {
                                    id: pinnedRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    buttonRadius: 5
                                    colBackground: "transparent"
                                    colBackgroundHover: root.colSurfaceHover
                                    onClicked: {
                                        if (modelData.kind === "playlist") root.openPlaylist(modelData.key);
                                        else root.openAlbum(modelData.key);
                                    }
                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 7
                                        CoverArtBox {
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            artSource: pinnedRow.modelData.art
                                            fallbackIcon: pinnedRow.modelData.kind === "playlist" ? "queue_music" : "album"
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: pinnedRow.modelData.name
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Medium
                                                color: root.colText
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: pinnedRow.modelData.sublabel
                                                font.family: root.uiFont
                                                font.pixelSize: Math.max(9, Appearance.font.pixelSize.smallest - 1)
                                                color: root.colSubtext
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 2B. CENTER SONORA STAGE (objectName: "musicResults")
                Rectangle {
                    id: musicResultsColumn
                    objectName: "musicResults"
                    readonly property real fixedGaps: (musicColumnsViewport.sidebarWidth > 0 ? 6 : 0) + (musicColumnsViewport.rightDrawerWidth > 0 ? 6 : 0)
                    width: Math.max(280, musicColumnsViewport.contentWidth - musicColumnsViewport.sidebarWidth - musicColumnsViewport.rightDrawerWidth - fixedGaps)
                    height: columnsRow.height
                    radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
                    color: root.colBg
                    border.width: root.isWaffle ? 1 : 0
                    border.color: root.colBorder
                    clip: true

                    // Subtle Sonora ambient hero gradient wash at the top of the stage
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Math.min(200, parent.height * 0.42)
                        visible: root.sourceMode.length > 0
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.accent, 0.20) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // MPD / Backend Error Banner
                        Rectangle {
                            id: backendErrorBanner
                            objectName: "musicBackendError"
                            Layout.fillWidth: true
                            visible: root.showErrorBanner
                            implicitHeight: Math.max(32, errRow.implicitHeight + 12)
                            Layout.minimumHeight: 32
                            radius: 6
                            color: ColorUtils.applyAlpha(Appearance.colors.colError, 0.16)
                            border.width: 1
                            border.color: ColorUtils.applyAlpha(Appearance.colors.colError, 0.5)

                            RowLayout {
                                id: errRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 6
                                spacing: 8
                                MaterialSymbol {
                                    text: "error_outline"
                                    iconSize: 16
                                    color: Appearance.colors.colError
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: root.backendError.length > 0
                                        ? root.backendError
                                        : Translation.tr("Local music service is currently unavailable")
                                    font.family: root.uiFont
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colError
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // HOME / ALBUMS / ARTISTS CARD GRID (shown when no drilldown sourceMode is active)
                        Flickable {
                            id: homeGridFlickable
                            visible: root.sourceMode.length === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: homeGridContent.implicitHeight + 12
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                            ColumnLayout {
                                id: homeGridContent
                                width: homeGridFlickable.width - (root.showMusicScrollbars ? 8 : 0)
                                spacing: 14

                                // Welcome Hero strip in Home view
                                Rectangle {
                                    visible: root.viewMode === "home"
                                    Layout.fillWidth: true
                                    implicitHeight: homeHeroRow.implicitHeight + 20
                                    radius: 8
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.accent, 0.24) }
                                        GradientStop { position: 1.0; color: root.colSurface }
                                    }
                                    border.width: 1
                                    border.color: ColorUtils.applyAlpha(root.colBorder, 0.35)

                                    RowLayout {
                                        id: homeHeroRow
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 12

                                        CoverArtBox {
                                            implicitWidth: 58
                                            implicitHeight: 58
                                            artSource: root.currentTrackArt || (root.libraryTracks.length > 0 ? root.trackArt(root.libraryTracks[0]) : "")
                                            fallbackIcon: "library_music"
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 2
                                            StyledText {
                                                text: Translation.tr("LOCAL MUSIC LIBRARY")
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.DemiBold
                                                color: root.accent
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Translation.tr("%1 Songs · %2 Albums · %3 Artists")
                                                    .arg(root.libraryTracks.length)
                                                    .arg(root.albums.length)
                                                    .arg(root.artists.length)
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                font.weight: Font.DemiBold
                                                color: root.colText
                                                elide: Text.ElideRight
                                            }
                                            RowLayout {
                                                spacing: 6
                                                SonoraPillButton {
                                                    iconName: "play_arrow"
                                                    labelText: Translation.tr("Play All")
                                                    primaryFill: true
                                                    enabled: root.libraryTracks.length > 0
                                                    onClicked: root._safePlayQueue(root.libraryTracks, 0, Translation.tr("Library"))
                                                }
                                                SonoraPillButton {
                                                    iconName: "queue_music"
                                                    labelText: Translation.tr("Browse Songs")
                                                    onClicked: root.openAllSongs()
                                                }
                                            }
                                        }
                                    }
                                }

                                // Albums Section (Home or Albums tab)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: (root.viewMode === "home" || root.viewMode === "albums") && root.albums.length > 0
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.viewMode === "albums" ? Translation.tr("Albums") : Translation.tr("Local Albums")
                                            font.family: root.uiFont
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                        }
                                        RippleButton {
                                            visible: root.viewMode === "home" && root.albums.length > 6
                                            implicitHeight: 24
                                            implicitWidth: showAllAlbTxt.implicitWidth + 12
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: "transparent"
                                            colBackgroundHover: root.colSurfaceHover
                                            onClicked: root.openAlbumsGrid()
                                            contentItem: StyledText {
                                                id: showAllAlbTxt
                                                anchors.centerIn: parent
                                                text: Translation.tr("Show all")
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                        }
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        readonly property int cols: Math.max(2, Math.floor((width + 10) / 146))
                                        columns: cols
                                        uniformCellWidths: true
                                        columnSpacing: 10
                                        rowSpacing: 10

                                        Repeater {
                                            model: root.viewMode === "albums" ? root.albums : root.albums.slice(0, 8)
                                            delegate: Rectangle {
                                                id: albumCard
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                implicitHeight: albumCardCol.implicitHeight + 16
                                                radius: 8
                                                color: albumCardMa.containsMouse ? root.colSurfaceHover : root.colSurface
                                                border.width: root.isWaffle ? 1 : 0
                                                border.color: root.colBorder

                                                ColumnLayout {
                                                    id: albumCardCol
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 6
                                                    CoverArtBox {
                                                        Layout.fillWidth: true
                                                        implicitHeight: Math.max(88, Math.min(130, width))
                                                        artSource: root.resolveArt(albumCard.modelData.artUrl || albumCard.modelData.art || "")
                                                        fallbackIcon: "album"
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: albumCard.modelData.name
                                                        font.family: root.uiFont
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.DemiBold
                                                        color: root.colText
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: `${albumCard.modelData.artist} · ${albumCard.modelData.trackCount}`
                                                        font.family: root.uiFont
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: root.colSubtext
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                MouseArea {
                                                    id: albumCardMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.openAlbum(albumCard.modelData.key)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Artists Section (Home or Artists tab)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: (root.viewMode === "home" || root.viewMode === "artists") && root.artists.length > 0
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Artists")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: root.colText
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        readonly property int cols: Math.max(2, Math.floor((width + 10) / 138))
                                        columns: cols
                                        uniformCellWidths: true
                                        columnSpacing: 10
                                        rowSpacing: 10

                                        Repeater {
                                            model: root.viewMode === "artists" ? root.artists : root.artists.slice(0, 8)
                                            delegate: Rectangle {
                                                id: artistCard
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                implicitHeight: artistCardCol.implicitHeight + 16
                                                radius: 8
                                                color: artistCardMa.containsMouse ? root.colSurfaceHover : root.colSurface
                                                border.width: root.isWaffle ? 1 : 0
                                                border.color: root.colBorder

                                                ColumnLayout {
                                                    id: artistCardCol
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 6
                                                    CoverArtBox {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        implicitWidth: 82
                                                        implicitHeight: 82
                                                        circular: true
                                                        artSource: root.resolveArt(artistCard.modelData.artUrl || artistCard.modelData.art || "")
                                                        fallbackIcon: "person"
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: artistCard.modelData.name
                                                        font.family: root.uiFont
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.DemiBold
                                                        color: root.colText
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: Translation.tr("%1 songs").arg(artistCard.modelData.trackCount)
                                                        font.family: root.uiFont
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: root.colSubtext
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                MouseArea {
                                                    id: artistCardMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.openArtist(artistCard.modelData.key)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Empty Library Hint
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 28
                                    visible: root.libraryTracks.length === 0
                                    spacing: 6
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "music_off"
                                        iconSize: 36
                                        color: root.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Translation.tr("No local audio tracks indexed yet")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Medium
                                        color: root.colText
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Translation.tr("Configure your Music folder in Settings → Local Music or click Refresh.")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.colSubtext
                                    }
                                }
                            }
                        }

                        // DRILLDOWN SONORA HERO + ACTION BAR + TRACK TABLE
                        ColumnLayout {
                            visible: root.sourceMode.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            // Hero Header Banner (kept compact in short viewports so ListView keeps >260px height)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                CoverArtBox {
                                    implicitWidth: musicResultsColumn.height < 480 ? 72 : 96
                                    implicitHeight: implicitWidth
                                    circular: root.heroMeta.isCircular
                                    artSource: root.heroMeta.art
                                    fallbackIcon: root.heroMeta.icon
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 3

                                    RowLayout {
                                        spacing: 6
                                        RippleButton {
                                            visible: root.sourceMode === "folder" && root.resultFolder.length > 0
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: root.colSurface
                                            colBackgroundHover: root.colSurfaceHover
                                            onClicked: root.restoreBrowserColumns()
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "arrow_back"
                                                iconSize: 14
                                                color: root.colText
                                            }
                                        }
                                        StyledText {
                                            text: root.heroMeta.badge
                                            font.family: root.uiFont
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: root.accent
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.heroMeta.title
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.huge
                                        font.weight: Font.Bold
                                        color: root.colText
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.heroMeta.subtitle
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.colSubtext
                                        elide: Text.ElideRight
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 2
                                        spacing: 6

                                        SonoraPillButton {
                                            objectName: "musicPlayAll"
                                            primaryFill: true
                                            iconName: "play_arrow"
                                            labelText: Translation.tr("Play")
                                            enabled: root.allResultTracks.length > 0
                                            onClicked: root._safePlayQueue(root.allResultTracks, 0, root.heroMeta.title)
                                        }

                                        SonoraPillButton {
                                            objectName: "musicPlaySelection"
                                            visible: root.selectedTracks.length > 0
                                            iconName: "playlist_play"
                                            labelText: Translation.tr("Play Selected (%1)").arg(root.selectedTracks.length)
                                            onClicked: root._safePlayQueue(root.selectedTracks, 0, Translation.tr("Selection"))
                                        }

                                        SonoraPillButton {
                                            objectName: "musicEnqueueSelection"
                                            visible: root.selectedTracks.length > 0
                                            iconName: "queue_music"
                                            labelText: Translation.tr("+ Queue")
                                            onClicked: root._safeEnqueueTracks(root.selectedTracks)
                                        }

                                        SonoraPillButton {
                                            iconName: "playlist_add"
                                            labelText: musicResultsColumn.width >= 440 ? Translation.tr("Playlist") : ""
                                            enabled: (root.selectedTracks.length > 0 ? root.selectedTracks : root.allResultTracks).length > 0
                                            onClicked: root.openCreatePlaylist(root.selectedTracks.length > 0 ? root.selectedTracks : root.allResultTracks)
                                        }
                                    }
                                }
                            }

                            // Track Table Header
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                spacing: 8

                                StyledText {
                                    Layout.preferredWidth: 26
                                    text: "#"
                                    font.family: root.uiFont
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.colSubtext
                                }

                                MouseArea {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 3
                                    implicitHeight: 20
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSort("title")
                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Title") + (root.sortField === "title" ? (root.sortAscending ? " ↑" : " ↓") : "")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.sortField === "title" ? root.accent : root.colSubtext
                                    }
                                }

                                MouseArea {
                                    visible: musicResultsColumn.width >= 420
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 2
                                    implicitHeight: 20
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSort("artist")
                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Artist") + (root.sortField === "artist" ? (root.sortAscending ? " ↑" : " ↓") : "")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.sortField === "artist" ? root.accent : root.colSubtext
                                    }
                                }

                                MouseArea {
                                    Layout.preferredWidth: 52
                                    implicitHeight: 20
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSort("duration")
                                    StyledText {
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignRight
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Length") + (root.sortField === "duration" ? (root.sortAscending ? " ↑" : " ↓") : "")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.sortField === "duration" ? root.accent : root.colSubtext
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: ColorUtils.applyAlpha(root.colBorder, 0.4)
                            }

                            // Track & Folder ListView (objectName: "musicResultList")
                            ListView {
                                id: resultList
                                objectName: "musicResultList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: root.results
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                                delegate: Item {
                                    id: resultDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property bool isFolder: modelData?.kind === "folder"
                                    readonly property string entryKey: Library.key(modelData)
                                    readonly property bool isSelected: root.selectedKeys.includes(entryKey)
                                    readonly property bool isCurrentPlaying: !isFolder
                                        && root.currentTrackTitle.length > 0
                                        && String(modelData?.track?.title ?? "") === root.currentTrackTitle
                                        && String(modelData?.track?.artist ?? "") === root.currentTrackArtist
                                    width: resultList.width - (root.showMusicScrollbars ? 8 : 0)
                                    height: 40

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 6
                                        color: resultDelegate.isSelected
                                            ? ColorUtils.applyAlpha(root.accent, 0.22)
                                            : resultDelegate.isCurrentPlaying
                                                ? ColorUtils.applyAlpha(root.accent, 0.12)
                                                : (rowMa.containsMouse ? root.colSurfaceHover : "transparent")

                                        MouseArea {
                                            id: rowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    root.openContext(resultDelegate.modelData, resultDelegate.index, resultDelegate);
                                                    return;
                                                }
                                                root.selectResultRow(resultDelegate.index, mouse.modifiers);
                                            }
                                            onDoubleClicked: root.activateResultRow(resultDelegate.modelData, resultDelegate.index)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Item {
                                                Layout.preferredWidth: 26
                                                implicitHeight: 24
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: resultDelegate.isFolder || resultDelegate.isCurrentPlaying
                                                    text: resultDelegate.isFolder ? "folder" : (root.isPlaying ? "graphic_eq" : "pause")
                                                    iconSize: 16
                                                    color: resultDelegate.isCurrentPlaying ? root.accent : root.colSubtext
                                                }
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    visible: !resultDelegate.isFolder && !resultDelegate.isCurrentPlaying
                                                    text: String(resultDelegate.index + 1)
                                                    font.family: root.uiFont
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: root.colSubtext
                                                }
                                            }

                                            CoverArtBox {
                                                visible: !resultDelegate.isFolder
                                                implicitWidth: 28
                                                implicitHeight: 28
                                                artSource: root.trackArt(resultDelegate.modelData?.track)
                                                fallbackIcon: "music_note"
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: false
                                                Layout.preferredWidth: 3
                                                Layout.minimumWidth: 0
                                                spacing: 0
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: resultDelegate.modelData?.name ?? ""
                                                    font.family: root.uiFont
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: (resultDelegate.isCurrentPlaying || resultDelegate.isSelected) ? Font.DemiBold : Font.Normal
                                                    color: resultDelegate.isCurrentPlaying ? root.accent : root.colText
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    visible: !resultDelegate.isFolder && musicResultsColumn.width < 420
                                                    Layout.fillWidth: true
                                                    text: String(resultDelegate.modelData?.track?.artist ?? "")
                                                    font.family: root.uiFont
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            StyledText {
                                                visible: musicResultsColumn.width >= 420
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 2
                                                Layout.minimumWidth: 0
                                                text: resultDelegate.isFolder
                                                    ? Translation.tr("%1 tracks").arg(resultDelegate.modelData?.count ?? 0)
                                                    : String(resultDelegate.modelData?.track?.artist ?? resultDelegate.modelData?.track?.album ?? "")
                                                font.family: root.uiFont
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: root.colSubtext
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                Layout.preferredWidth: 52
                                                horizontalAlignment: Text.AlignRight
                                                text: resultDelegate.isFolder
                                                    ? "›"
                                                    : Library.formatDuration(resultDelegate.modelData?.track?.duration ?? 0)
                                                font.family: Appearance.font.family.numbers
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: root.colSubtext
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 2C. RIGHT SONORA DRAWER: QUEUE | LYRICS | EQ (objectName: "musicPlaybackAndQueue")
                Rectangle {
                    id: rightDrawerColumn
                    objectName: "musicPlaybackAndQueue"
                    visible: musicColumnsViewport.rightDrawerWidth > 0
                    width: musicColumnsViewport.rightDrawerWidth
                    height: columnsRow.height
                    radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
                    color: root.colBg
                    border.width: root.isWaffle ? 1 : 0
                    border.color: root.colBorder
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        // Segmented Switch Header: Queue | Lyrics & EQ (centered full-width equal tabs)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { id: "queue", label: Translation.tr("Queue") },
                                    { id: "lyrics", label: Translation.tr("Lyrics & EQ") }
                                ]
                                delegate: RippleButton {
                                    id: drawerTabBtn
                                    required property var modelData
                                    readonly property bool active: drawerTabBtn.modelData.id === "lyrics"
                                        ? root.lyricsEqTabActive
                                        : !root.lyricsEqTabActive
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 28
                                    buttonRadius: root.isWaffle ? Waffle.Looks.radius.small : Appearance.rounding.full
                                    colBackground: active ? ColorUtils.applyAlpha(root.accent, 0.20) : root.colSurface
                                    colBackgroundHover: root.colSurfaceHover
                                    onClicked: root.rightDrawerTab = drawerTabBtn.modelData.id
                                    contentItem: StyledText {
                                        id: tabLbl
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: drawerTabBtn.modelData.label
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: drawerTabBtn.active ? Font.DemiBold : Font.Normal
                                        color: drawerTabBtn.active ? root.accent : root.colText
                                    }
                                }
                            }
                        }

                        // QUEUE TAB (objectName: "musicQueuePanel" + "musicQueueList")
                        ColumnLayout {
                            objectName: "musicQueuePanel"
                            visible: !root.lyricsEqTabActive
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            StyledText {
                                visible: root.currentTrackTitle.length > 0
                                text: Translation.tr("NOW PLAYING")
                                font.family: root.uiFont
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: root.colSubtext
                            }

                            Rectangle {
                                visible: root.currentTrackTitle.length > 0
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: ColorUtils.applyAlpha(root.accent, 0.14)
                                border.width: 1
                                border.color: ColorUtils.applyAlpha(root.accent, 0.35)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8
                                    CoverArtBox {
                                        implicitWidth: 34
                                        implicitHeight: 34
                                        artSource: root.currentTrackArt
                                        fallbackIcon: "graphic_eq"
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.currentTrackTitle
                                            font.family: root.uiFont
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: root.accent
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.currentTrackArtist || Translation.tr("Local Track")
                                            font.family: root.uiFont
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("UP NEXT (%1)").arg(root.activeQueue.length)
                                    font.family: root.uiFont
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: root.colSubtext
                                }

                                RippleButton {
                                    visible: root.activeQueue.length > 0
                                    implicitHeight: 22
                                    implicitWidth: clrTxt.implicitWidth + 10
                                    buttonRadius: 4
                                    colBackground: "transparent"
                                    colBackgroundHover: root.colSurfaceHover
                                    onClicked: root._safeClearQueue()
                                    contentItem: StyledText {
                                        id: clrTxt
                                        anchors.centerIn: parent
                                        text: Translation.tr("Clear")
                                        font.family: root.uiFont
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                    }
                                }
                            }

                            ListView {
                                id: queueList
                                objectName: "musicQueueList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: root.activeQueue
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                                delegate: Item {
                                    id: qDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property bool isCurrent: index === root.currentQueueIndex
                                    width: queueList.width - (root.showMusicScrollbars ? 8 : 0)
                                    height: 38

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: qDelegate.isCurrent
                                            ? ColorUtils.applyAlpha(root.accent, 0.14)
                                            : (qMa.containsMouse ? root.colSurfaceHover : "transparent")

                                        MouseArea {
                                            id: qMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onDoubleClicked: root._safeJumpTo(qDelegate.index)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 4
                                            spacing: 7

                                            CoverArtBox {
                                                implicitWidth: 28
                                                implicitHeight: 28
                                                artSource: root.trackArt(qDelegate.modelData)
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(qDelegate.modelData?.title || qDelegate.modelData?.uri || "")
                                                    font.family: root.uiFont
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: qDelegate.isCurrent ? Font.DemiBold : Font.Normal
                                                    color: qDelegate.isCurrent ? root.accent : root.colText
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(qDelegate.modelData?.artist || "")
                                                    font.family: root.uiFont
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            RippleButton {
                                                visible: qMa.containsMouse
                                                implicitWidth: 22
                                                implicitHeight: 22
                                                buttonRadius: Appearance.rounding.full
                                                colBackground: "transparent"
                                                colBackgroundHover: root.colSurfaceHover
                                                onClicked: root._safeRemoveQueueTrack(qDelegate.index)
                                                contentItem: MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "close"
                                                    iconSize: 13
                                                    color: root.colSubtext
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // MERGED LYRICS + EQUALIZER TAB (Lyrics takes majority top space; compact EQ below)
                        ColumnLayout {
                            id: musicLyricsEqPanel
                            visible: root.lyricsEqTabActive
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            Item {
                                id: musicLyricsPane
                                objectName: "musicLyrics"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 96

                                ListView {
                                    id: lyricsList
                                    objectName: "musicLyricsList"
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 4
                                    model: root.lyricsLines
                                    currentIndex: root.lyricsActiveIndex
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                                    onCurrentIndexChanged: {
                                        if (currentIndex >= 0 && currentIndex < count)
                                            positionViewAtIndex(currentIndex, ListView.Center);
                                    }

                                    delegate: Item {
                                        id: lyrDelegate
                                        required property var modelData
                                        required property int index
                                        readonly property bool isCurrent: index === root.lyricsActiveIndex
                                        width: lyricsList.width - (root.showMusicScrollbars ? 8 : 0)
                                        height: lyrTxt.implicitHeight + 10

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: lyrMa.containsMouse ? root.colSurfaceHover : "transparent"
                                            StyledText {
                                                id: lyrTxt
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                text: String(lyrDelegate.modelData?.text ?? "")
                                                wrapMode: Text.WordWrap
                                                font.family: root.uiFont
                                                font.pixelSize: lyrDelegate.isCurrent ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.smaller
                                                font.weight: lyrDelegate.isCurrent ? Font.Bold : Font.Normal
                                                color: lyrDelegate.isCurrent ? root.colText : ColorUtils.applyAlpha(root.colSubtext, 0.72)
                                            }
                                            MouseArea {
                                                id: lyrMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (lyrDelegate.modelData?.time !== undefined)
                                                        root._safeSeek(Number(lyrDelegate.modelData.time));
                                                }
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    visible: root.lyricsLines.length === 0
                                    text: Translation.tr("No local lyrics found for this track")
                                    font.family: root.uiFont
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.colSubtext
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: ColorUtils.applyAlpha(root.colBorder, 0.35)
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.preferredHeight: musicEqPanel.implicitHeight
                                Layout.maximumHeight: musicEqPanel.implicitHeight

                                EqualizerPanel {
                                    id: musicEqPanel
                                    objectName: "musicEqualizer"
                                    anchors.fill: parent
                                    compactLayout: true
                                    active: root.presentationActive && root.rightDrawerOpen && root.lyricsEqTabActive
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Persistent Bottom Player Bar (objectName: "musicPlayer")
        Rectangle {
            id: musicPlayerBar
            objectName: "musicPlayer"
            Layout.fillWidth: true
            implicitHeight: 72
            radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
            color: root.colBg
            border.width: root.isWaffle ? 1 : 0
            border.color: root.colBorder

            Item {
                id: musicPlayerSurface
                objectName: "musicPlayerSurface"
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10

                RowLayout {
                    anchors.fill: parent
                    spacing: 12

                    // Left: Now Playing Cover + Metadata (click toggles Ambient Mode)
                    RowLayout {
                        Layout.preferredWidth: Math.min(220, Math.max(110, musicPlayerBar.width * 0.25))
                        Layout.minimumWidth: 96
                        spacing: 9

                        CoverArtBox {
                            implicitWidth: 46
                            implicitHeight: 46
                            artSource: root.currentTrackArt
                            fallbackIcon: "music_note"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.ambientOpen = !root.ambientOpen
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentTrackTitle || Translation.tr("Nothing playing")
                                font.family: root.uiFont
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: root.colText
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentTrackArtist || Translation.tr("Select a local track")
                                font.family: root.uiFont
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Center: Transport Controls + Progress Scrubber
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 160
                        spacing: 2

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8

                            RippleButton {
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.shuffleActive ? ColorUtils.applyAlpha(root.accent, 0.20) : "transparent"
                                colBackgroundHover: root.colSurfaceHover
                                onClicked: root._safeToggleShuffle()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "shuffle"
                                    iconSize: 16
                                    color: root.shuffleActive ? root.accent : root.colSubtext
                                }
                                StyledToolTip { text: Translation.tr("Shuffle") }
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: root.colSurfaceHover
                                onClicked: root._safePrevious()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "skip_previous"
                                    iconSize: 19
                                    color: root.colText
                                }
                            }

                            RippleButton {
                                objectName: "musicPlayPauseButton"
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.accent
                                colBackgroundHover: ColorUtils.applyAlpha(root.accent, 0.85)
                                onClicked: root._safeTogglePlaying()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.isPlaying ? "pause" : "play_arrow"
                                    iconSize: 19
                                    color: root.colOnAccent
                                }
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: root.colSurfaceHover
                                onClicked: root._safeNext()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "skip_next"
                                    iconSize: 19
                                    color: root.colText
                                }
                            }

                            RippleButton {
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.repeatModeValue > 0 ? ColorUtils.applyAlpha(root.accent, 0.20) : "transparent"
                                colBackgroundHover: root.colSurfaceHover
                                onClicked: root._safeCycleRepeat()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.repeatModeValue === 1 ? "repeat_one" : "repeat"
                                    iconSize: 16
                                    color: root.repeatModeValue > 0 ? root.accent : root.colSubtext
                                }
                                StyledToolTip { text: Translation.tr("Repeat") }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                                text: Library.formatDuration(root.currentPosition)
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                            }

                            StyledSlider {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 60
                                configuration: StyledSlider.Configuration.S
                                from: 0
                                to: Math.max(1, root.currentDuration)
                                value: Math.min(to, root.currentPosition)
                                onMoved: root._safeSeek(value)
                            }

                            StyledText {
                                Layout.preferredWidth: 36
                                text: Library.formatDuration(root.currentDuration)
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                            }
                        }
                    }

                    // Right: Drawer Switches + Volume + Fullscreen Ambient Toggle
                    RowLayout {
                        Layout.preferredWidth: Math.min(250, Math.max(130, musicPlayerBar.width * 0.28))
                        spacing: 4

                        RippleButton {
                            visible: musicPlayerBar.width >= 560
                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.small
                            colBackground: root.rightDrawerOpen && root.lyricsEqTabActive ? ColorUtils.applyAlpha(root.accent, 0.2) : "transparent"
                            colBackgroundHover: root.colSurfaceHover
                            onClicked: {
                                if (root.rightDrawerOpen && root.lyricsEqTabActive)
                                    root.rightDrawerOpen = false;
                                else {
                                    root.rightDrawerTab = "lyrics";
                                    root.rightDrawerOpen = true;
                                }
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "lyrics"
                                iconSize: 16
                                color: root.rightDrawerOpen && root.lyricsEqTabActive ? root.accent : root.colSubtext
                            }
                            StyledToolTip { text: Translation.tr("Lyrics & EQ") }
                        }

                        MaterialSymbol {
                            visible: musicPlayerBar.width >= 620
                            text: Number(root.backend?.volume ?? 0.5) <= 0.01 ? "volume_off" : "volume_up"
                            iconSize: 16
                            color: root.colSubtext
                        }

                        StyledSlider {
                            id: volumeSlider
                            objectName: "musicVolume"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 58
                            Layout.maximumWidth: 110
                            configuration: StyledSlider.Configuration.S
                            from: 0
                            to: 1
                            stepSize: 0.02
                            value: Number(root.backend?.volume ?? 0.5)
                            onMoved: root._safeSetVolume(value)
                        }

                        RippleButton {
                            objectName: "musicAmbientToggle"
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.small
                            colBackground: root.ambientOpen ? ColorUtils.applyAlpha(root.accent, 0.2) : "transparent"
                            colBackgroundHover: root.colSurfaceHover
                            onClicked: root.ambientOpen = !root.ambientOpen
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.ambientOpen ? "close_fullscreen" : "open_in_full"
                                iconSize: 16
                                color: root.ambientOpen ? root.accent : root.colSubtext
                            }
                            StyledToolTip { text: Translation.tr("Ambient karaoke view") }
                        }
                    }
                }
            }
        }
    }

    // 4. Fullscreen Ambient Karaoke Overlay (Sonora shot1.png look)
    Rectangle {
        id: ambientOverlay
        objectName: "musicAmbientView"
        anchors.fill: parent
        z: 30
        visible: root.ambientOpen
        radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
        color: "#111319"
        clip: true

        Image {
            id: ambientBgSource
            anchors.fill: parent
            source: root.ambientOpen ? root.currentTrackArt : ""
            fillMode: Image.PreserveAspectCrop
            visible: false
        }

        FastBlur {
            anchors.fill: parent
            source: ambientBgSource
            radius: 72
            visible: root.ambientOpen && root.currentTrackArt.length > 0 && Appearance.effectsEnabled
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.accent, 0.32) }
                GradientStop { position: 0.6; color: Qt.rgba(0.06, 0.07, 0.10, 0.82) }
                GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.08, 0.92) }
            }
        }

        RippleButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            z: 5
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: Qt.rgba(1, 1, 1, 0.12)
            colBackgroundHover: Qt.rgba(1, 1, 1, 0.22)
            onClicked: root.ambientOpen = false
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 18
                color: "#ffffff"
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 32

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                CoverArtBox {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Math.min(240, Math.max(140, root.height * 0.42))
                    implicitHeight: implicitWidth
                    artSource: root.currentTrackArt
                    fallbackIcon: "album"
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.currentTrackTitle || Translation.tr("Nothing playing")
                    font.family: root.uiFont
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Bold
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.currentTrackArtist || Translation.tr("Local MPD")
                    font.family: root.uiFont
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Qt.rgba(1, 1, 1, 0.72)
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Qt.rgba(1, 1, 1, 0.12)
                        colBackgroundHover: Qt.rgba(1, 1, 1, 0.22)
                        onClicked: root._safePrevious()
                        contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_previous"; iconSize: 22; color: "#ffffff" }
                    }
                    RippleButton {
                        implicitWidth: 44
                        implicitHeight: 44
                        buttonRadius: Appearance.rounding.full
                        colBackground: "#ffffff"
                        colBackgroundHover: Qt.rgba(1, 1, 1, 0.85)
                        onClicked: root._safeTogglePlaying()
                        contentItem: MaterialSymbol { anchors.centerIn: parent; text: root.isPlaying ? "pause" : "play_arrow"; iconSize: 24; color: "#111319" }
                    }
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Qt.rgba(1, 1, 1, 0.12)
                        colBackgroundHover: Qt.rgba(1, 1, 1, 0.22)
                        onClicked: root._safeNext()
                        contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_next"; iconSize: 22; color: "#ffffff" }
                    }
                }
            }

            ListView {
                id: ambientLyricsList
                objectName: "musicAmbientLyricsList"
                Layout.fillWidth: true
                Layout.preferredWidth: 1.25
                Layout.fillHeight: true
                clip: true
                spacing: 12
                model: root.lyricsLines
                currentIndex: root.lyricsActiveIndex
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SonoraScrollBar { orientation: Qt.Vertical }

                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < count)
                        positionViewAtIndex(currentIndex, ListView.Center);
                }

                delegate: Item {
                    id: ambLyrDel
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: index === root.lyricsActiveIndex
                    width: ambientLyricsList.width
                    height: ambLyrText.implicitHeight + 8

                    StyledText {
                        id: ambLyrText
                        anchors.fill: parent
                        text: String(ambLyrDel.modelData?.text ?? "")
                        wrapMode: Text.WordWrap
                        font.family: root.uiFont
                        font.pixelSize: ambLyrDel.isCurrent ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.larger
                        font.weight: ambLyrDel.isCurrent ? Font.Bold : Font.Medium
                        color: ambLyrDel.isCurrent ? "#ffffff" : Qt.rgba(1, 1, 1, 0.42)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (ambLyrDel.modelData?.time !== undefined)
                                root._safeSeek(Number(ambLyrDel.modelData.time));
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.lyricsLines.length === 0
                    text: Translation.tr("No synced lyrics available")
                    font.family: root.uiFont
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Qt.rgba(1, 1, 1, 0.55)
                }
            }
        }
    }

    // 5. Playlist Creation / Save Dialog
    Rectangle {
        anchors.fill: parent
        z: 40
        visible: root.playlistDialogVisible
        color: Qt.rgba(0, 0, 0, 0.52)

        MouseArea {
            anchors.fill: parent
            onClicked: root.playlistDialogVisible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(340, parent.width - 32)
            implicitHeight: plDialogCol.implicitHeight + 28
            radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.normal
            color: root.colBg
            border.width: 1
            border.color: root.colBorder

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: plDialogCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                StyledText {
                    text: Translation.tr("Save as Local Playlist")
                    font.family: root.uiFont
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.colText
                }

                MaterialTextField {
                    id: playlistNameInput
                    objectName: "musicPlaylistName"
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Playlist name…")
                    Keys.onEscapePressed: root.playlistDialogVisible = false
                    Keys.onReturnPressed: root.commitPlaylist()
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    SonoraPillButton {
                        labelText: Translation.tr("Cancel")
                        onClicked: root.playlistDialogVisible = false
                    }
                    SonoraPillButton {
                        primaryFill: true
                        labelText: Translation.tr("Save")
                        onClicked: root.commitPlaylist()
                    }
                }
            }
        }
    }

    // 6. Lightweight Row Context Menu
    Rectangle {
        anchors.fill: parent
        z: 35
        visible: root.contextMenuVisible
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: root.contextMenuVisible = false
        }

        Rectangle {
            x: root.contextMenuX
            y: root.contextMenuY
            width: 196
            implicitHeight: ctxCol.implicitHeight + 10
            radius: root.isWaffle ? Waffle.Looks.radius.medium : Appearance.rounding.small
            color: root.colBg
            border.width: 1
            border.color: root.colBorder

            ColumnLayout {
                id: ctxCol
                anchors.fill: parent
                anchors.margins: 5
                spacing: 2

                Repeater {
                    model: root.contextActions
                    delegate: SidebarNavItem {
                        required property var modelData
                        iconName: modelData.icon ?? ""
                        labelText: modelData.label ?? ""
                        onClicked: {
                            root.contextMenuVisible = false;
                            if (typeof modelData.action === "function")
                                modelData.action();
                        }
                    }
                }
            }
        }
    }
}
