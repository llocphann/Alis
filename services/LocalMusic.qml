pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property bool enabled: Config.ready && (Config.options?.dashboard?.music?.enable ?? true)
    readonly property bool uiDemand:
        (GlobalStates.dashboardOpen || (GlobalStates.overviewOpen && GlobalStates.overviewMode === "dashboard"))
            && GlobalStates.dashboardPage === 1
    readonly property int fallbackPollIntervalMs: root.uiDemand ? 900 : 30000
    onUiDemandChanged: {
        if (root.uiDemand)
            Qt.callLater(root._refreshPresentedStatus)
    }

    function _refreshPresentedStatus(): void {
        if (root.uiDemand && root.enabled && !root._mpdSubscriptionActive)
            root.refreshStatus()
    }
    readonly property string configuredLibraryFolder:
        Config.options?.sidebar?.music?.libraryFolder ?? ""
    readonly property string configuredHost:
        Config.options?.sidebar?.music?.mpdHost ?? ""
    readonly property int configuredPort:
        Number(Config.options?.sidebar?.music?.mpdPort ?? 6600)
    readonly property string mpdHost: configuredHost.length > 0
        ? configuredHost
        : ((Quickshell.env("MPD_HOST") ?? "").length > 0
            ? Quickshell.env("MPD_HOST") : "127.0.0.1")
    readonly property int mpdPort: {
        const envPort = Number(Quickshell.env("MPD_PORT") ?? 0)
        if (configuredPort > 0) return configuredPort
        return envPort > 0 ? envPort : 6600
    }

    property string detectedLibraryFolder: ""
    readonly property string defaultLibraryFolder:
        FileUtils.trimFileProtocol(Directories.music)
    readonly property string libraryFolder: configuredLibraryFolder.length > 0
        ? configuredLibraryFolder
        : (detectedLibraryFolder.length > 0
            ? detectedLibraryFolder : defaultLibraryFolder)

    readonly property var mprisPlayer: MprisController.mpdPlayer
    readonly property bool mprisAvailable: mprisPlayer !== null
    property bool mpdConnected: false
    readonly property bool available: mpdConnected

    property bool scanning: false
    property string error: ""
    property string mpdState: "stop"

    property var libraryTracks: []
    property var playlists: []
    // "Playlists" is semantically reserved for MPD saved playlists. Folder
    // navigation is handled independently by the Songs browser.
    readonly property var collections: playlists

    property var activeQueue: []
    property string activeQueueName: ""
    property int currentIndex: -1
    property int resumeIndex: -1
    property string currentPath: ""
    property string currentUri: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentAlbum: ""
    property string currentArt: ""
    property real currentDuration: 0
    property real currentPosition: 0
    property real volume: 1
    property bool shuffleMode: false
    property int repeatMode: 0
    property var _queueRequests: []
    property var _enqueueRequests: []
    property var _bulkEnqueueRequests: []
    property var _playlistRequests: []
    property var _commandRequests: []
    property var _mpdMutationKinds: []
    property string _activeMpdMutation: ""
    readonly property bool mpdMutationPending:
        _activeMpdMutation.length > 0 || _mpdMutationKinds.length > 0
    property bool _queuePayloadWriting: false
    property bool _bulkEnqueuePayloadWriting: false
    property bool _playlistPayloadWriting: false
    property bool _nativeMpdEligible: false
    property bool _nativeBackendChecked: false
    property bool _mpdSubscriptionActive: false

    // Bulk music actions can easily exceed Linux's per-argument exec limit
    // when thousands of MPD URIs are serialized into one JSON argv entry.
    // File-backed payloads keep Process command lines small and deterministic.
    readonly property string _queuePayloadPath:
        `${Directories.stateUserPath}/local-music-queue-payload.json`
    readonly property string _bulkEnqueuePayloadPath:
        `${Directories.stateUserPath}/local-music-enqueue-payload.json`
    readonly property string _playlistPayloadPath:
        `${Directories.stateUserPath}/local-music-playlist-payload.json`

    // Local-only lyric state. MPD/MPRIS still own playback; this only reads
    // sidecar .lrc/.txt files next to the resolved local track path.
    property var localLyricsLines: []
    property string localLyricsStatus: "idle"
    property string localLyricsPath: ""
    property bool localLyricsSynced: false
    property string _pendingLyricsPath: ""
    property real _lyricsAnchorPos: 0
    property real _lyricsAnchorMs: 0
    property real _lyricsLivePos: 0
    property real _lastMprisNudgeMs: 0

    readonly property real _baseLyricsPosition: {
        const mprisPosition = Number(mprisPlayer?.position)
        if (mprisAvailable && Number.isFinite(mprisPosition) && mprisPosition > 0)
            return Math.max(0, mprisPosition)
        return Math.max(0, currentPosition)
    }

    function _reanchorLyricsPosition(pos: real): void {
        const cleanPos = Math.max(0, Number(pos) || 0)
        root._lyricsAnchorPos = cleanPos
        root._lyricsAnchorMs = Date.now()
        root._lyricsLivePos = cleanPos
    }

    on_BaseLyricsPositionChanged: root._reanchorLyricsPosition(root._baseLyricsPosition)
    onCurrentPositionChanged: root._reanchorLyricsPosition(root._baseLyricsPosition)
    onPlayingChanged: root._reanchorLyricsPosition(root._baseLyricsPosition)

    readonly property real lyricsPosition: {
        if (root.playing && root._lyricsAnchorMs > 0) {
            const dur = root.currentDuration
            return dur > 0
                ? Math.min(dur, Math.max(0, root._lyricsLivePos))
                : Math.max(0, root._lyricsLivePos)
        }
        return root._baseLyricsPosition
    }
    readonly property bool hasLocalLyrics: localLyricsLines.length > 0
    readonly property int localLyricsActiveIndex: {
        if (!localLyricsSynced || localLyricsLines.length === 0)
            return -1
        const position = lyricsPosition
        let index = -1
        for (let i = 0; i < localLyricsLines.length; i++) {
            const time = Number(localLyricsLines[i]?.time ?? -1)
            if (!Number.isFinite(time) || time < 0)
                continue
            if (time <= position)
                index = i
            else
                break
        }
        return index
    }

    readonly property bool playing: mprisAvailable
        ? (mprisPlayer?.isPlaying ?? false)
        : mpdState === "play"
    readonly property bool paused: !playing
    readonly property bool hasQueue: activeQueue.length > 0
    readonly property bool hasCurrentTrack:
        currentIndex >= 0 && currentIndex < activeQueue.length
    readonly property bool canGoPrevious:
        hasCurrentTrack && (currentIndex > 0 || repeatMode === 2 || currentPosition > 3)
    readonly property bool canGoNext:
        hasCurrentTrack && (currentIndex < activeQueue.length - 1 || repeatMode === 2)

    readonly property string nativeDispatchPath: Directories.scriptsPath + "/native-dispatch"

    function _trackForIdentity(uri: string, path: string): var {
        const wantedUri = String(uri ?? "")
        const wantedPath = String(path ?? "")
        for (const track of activeQueue) {
            if ((wantedUri && String(track?.uri ?? "") === wantedUri)
                    || (wantedPath && String(track?.path ?? "") === wantedPath))
                return track
        }
        for (const track of libraryTracks) {
            if ((wantedUri && String(track?.uri ?? "") === wantedUri)
                    || (wantedPath && String(track?.path ?? "") === wantedPath))
                return track
        }
        return null
    }

    function _applyCurrentTrack(track): void {
        if (!track) {
            currentTitle = currentPath.length > 0
                ? currentPath.substring(currentPath.lastIndexOf("/") + 1) : ""
            currentArtist = ""
            currentAlbum = ""
            currentArt = ""
            return
        }
        currentUri = String(track.uri ?? "")
        currentPath = String(track.path ?? track.uri ?? "")
        currentTitle = String(track.title ?? "")
        currentArtist = String(track.artist ?? "")
        currentAlbum = String(track.album ?? "")
        currentArt = String(track.art ?? "")
        currentDuration = Math.max(0, Number(track.duration ?? currentDuration) || 0)
    }

    function _applyPayload(payload, includeLibrary = false): void {
        if (!payload || payload.connected === false) {
            mpdConnected = false
            if (payload?.error) error = String(payload.error)
            return
        }

        mpdConnected = true
        MprisController.ensureMpdMprisBridge(mpdHost, mpdPort)
        if (String(payload.musicRoot ?? "").length > 0)
            detectedLibraryFolder = String(payload.musicRoot)

        if (includeLibrary) {
            libraryTracks = payload.tracks ?? []
            playlists = payload.playlists ?? []
        }

        if (Array.isArray(payload.queue))
            activeQueue = payload.queue

        const status = payload.status ?? {}
        // MPD can remain connected while its decoder reports a failure.
        // Keep the server's status error visible instead of treating a
        // successful socket poll as successful audio decoding.
        error = String(status.error ?? "").trim()
        mpdState = String(status.state ?? "stop")
        currentIndex = Number(status.song ?? -1)
        if (currentIndex >= 0)
            resumeIndex = currentIndex
        currentPosition = Math.max(0, Number(status.elapsed ?? 0) || 0)
        currentDuration = Math.max(0, Number(status.duration ?? 0) || 0)
        const mpdVolume = Number(status.volume)
        if (Number.isFinite(mpdVolume) && mpdVolume >= 0)
            volume = Math.max(0, Math.min(1, mpdVolume / 100))
        shuffleMode = String(status.random ?? "0") === "1"
        repeatMode = String(status.single ?? "0") === "1"
            ? 1
            : (String(status.repeat ?? "0") === "1" ? 2 : 0)

        const current = payload.current ?? (
            currentIndex >= 0 && currentIndex < activeQueue.length
                ? activeQueue[currentIndex] : null
        )
        if (current) {
            _applyCurrentTrack(current)
        } else {
            const resumable = mpdState === "stop"
                && resumeIndex >= 0 && resumeIndex < activeQueue.length
                ? activeQueue[resumeIndex] : null
            if (resumable) {
                currentIndex = resumeIndex
                currentPosition = 0
                _applyCurrentTrack(resumable)
            } else {
                currentIndex = -1
                currentUri = ""
                currentPath = ""
                currentTitle = ""
                currentArtist = ""
                currentAlbum = ""
                currentArt = ""
                currentDuration = 0
                currentPosition = 0
                if (activeQueue.length === 0)
                    resumeIndex = -1
            }
        }
    }

    function _clearLocalLyrics(status = "idle"): void {
        localLyricsLines = []
        localLyricsPath = ""
        localLyricsSynced = false
        localLyricsStatus = status
    }

    function refreshLocalLyrics(): void {
        const path = String(currentPath ?? "").trim()
        _pendingLyricsPath = path
        if (_lyricsDownloadProc.running)
            _lyricsDownloadProc.running = false
        if (path.length === 0 || path.includes("://")) {
            if (_lyricsProc.running)
                _lyricsProc.running = false
            _pendingLyricsPath = ""
            _clearLocalLyrics(path.length === 0 ? "idle" : "not_found")
            return
        }
        localLyricsStatus = "loading"
        if (_lyricsProc.running) {
            _lyricsProc.running = false
            return
        }
        _startPendingLyrics()
    }

    function _startPendingLyrics(): void {
        if (_lyricsProc.running || _pendingLyricsPath.length === 0)
            return
        const path = _pendingLyricsPath
        _pendingLyricsPath = ""
        _lyricsProc.requestedPath = path
        _lyricsProc.output = ""
        _lyricsProc.command = [root.nativeDispatchPath, "lyrics", path]
        _lyricsProc.running = true
    }

    function _probeNativeMpd(): void {
        if (!enabled || _nativeBackendInfoProc.running)
            return
        _nativeBackendInfoProc.output = ""
        _nativeBackendInfoProc.running = true
    }

    function _startNativeMpdBridge(): void {
        if (!enabled || !_nativeMpdEligible)
            return

        if (!_mpdDaemonProc.running) {
            const command = [
                root.nativeDispatchPath, "mpd-daemon",
                "--host", mpdHost,
                "--port", String(mpdPort)
            ]
            if (configuredLibraryFolder.length > 0)
                command.push("--music-root", configuredLibraryFolder)
            _mpdDaemonProc.command = command
            _mpdDaemonProc.running = true
        }

        mpdSubscribeRetryTimer.restart()
    }

    function _stopNativeMpdBridge(): void {
        _mpdSubscriptionActive = false
        mpdSubscribeRetryTimer.stop()
        mpdDaemonRetryTimer.stop()
        if (_mpdSubscriptionProc.running)
            _mpdSubscriptionProc.running = false
        if (_mpdDaemonProc.running)
            _mpdDaemonProc.running = false
    }

    function _restartNativeMpdBridge(): void {
        if (!_nativeMpdEligible || !enabled)
            return
        _stopNativeMpdBridge()
        Qt.callLater(root._startNativeMpdBridge)
    }

    function _handleMpdEvent(line): void {
        let event
        try {
            event = JSON.parse(String(line ?? ""))
        } catch (e) {
            return
        }

        const type = String(event?.type ?? "")
        if (type === "subscribed") {
            _mpdSubscriptionActive = true
            statusRefreshTimer.restart()
            return
        }

        if (type === "connection") {
            if (event.connected === false)
                mpdConnected = false
            else
                statusRefreshTimer.restart()
            return
        }

        if (type !== "changed")
            return

        const subsystems = Array.isArray(event.subsystems)
            ? event.subsystems.map(value => String(value)) : []
        if (subsystems.includes("database") || subsystems.includes("stored_playlist")) {
            playlistRescanTimer.restart()
            return
        }

        if (event.payload && typeof event.payload === "object") {
            if (root.mpdMutationPending) {
                statusRefreshTimer.restart()
                return
            }
            root._applyPayload(event.payload, false)
            return
        }

        // Transport/state payload generation is fail-soft in the daemon.
        // Keep the compatibility refresh only when an event arrived without it.
        statusRefreshTimer.restart()
    }

    function _configurationChanged(): void {
        if (!enabled)
            return
        if (_nativeMpdEligible)
            _restartNativeMpdBridge()
        Qt.callLater(root.rescan)
    }

    function setLibraryFolder(path: string): void {
        const normalized = FileUtils.trimFileProtocol(String(path ?? "")).trim()
        Config.setNestedValue("sidebar.music.libraryFolder", normalized)
        if (enabled) Qt.callLater(root.rescan)
    }

    function rescan(): void {
        if (!enabled || _scanProc.running) return
        scanning = true
        error = ""
        MprisController.ensureMpdMprisBridge(mpdHost, mpdPort)
        _scanProc.command = [
            root.nativeDispatchPath, "mpd", "snapshot",
            mpdHost, String(mpdPort), configuredLibraryFolder, "--lean"
        ]
        _scanProc.running = true
    }

    function refreshStatus(): void {
        if (!enabled || _statusProc.running || _scanProc.running) return
        _statusProc.command = [
            root.nativeDispatchPath, "mpd", "status",
            mpdHost, String(mpdPort), configuredLibraryFolder
        ]
        _statusProc.running = true
    }

    function updateDatabase(): void {
        _sendMpd("update", [])
        updateRescanTimer.restart()
    }

    function playLibrary(index: int): void {
        playQueue(libraryTracks, index, Translation.tr("Library"))
    }

    function playCollection(collection, index = 0): void {
        if (!collection) return
        playQueue(collection.tracks ?? [], index, String(collection.name ?? "Playlist"))
    }

    function playPath(path: string): void {
        const normalized = FileUtils.trimFileProtocol(String(path ?? "")).trim()
        if (normalized.length === 0) return
        const index = libraryTracks.findIndex(track =>
            String(track?.path ?? "") === normalized
                || String(track?.uri ?? "") === normalized)
        if (index < 0) {
            error = "not_in_mpd_library"
            return
        }
        playLibrary(index)
    }

    function enqueueTrack(track, playNow = true): void {
        if (!available || !track) return
        const uri = String(track?.uri ?? track?.path ?? "").trim()
        if (uri.length === 0) return

        _enqueueRequests = [..._enqueueRequests, {
            uri: uri,
            playNow: playNow === true
        }]
        _scheduleMpdMutation("enqueue")
    }

    function _drainEnqueueRequests(): void {
        if (_activeMpdMutation !== "enqueue") return
        if (_enqueueProc.running || _enqueueRequests.length === 0) return
        const request = _enqueueRequests[0]
        _enqueueRequests = _enqueueRequests.slice(1)
        _enqueueProc.output = ""
        _enqueueProc.command = [
            root.nativeDispatchPath, "mpd", "enqueue",
            mpdHost, String(mpdPort), configuredLibraryFolder,
            request.playNow ? "1" : "0", String(request.uri)
        ]
        _enqueueProc.running = true
    }

    function _trackUris(tracks): var {
        if (!Array.isArray(tracks)) return []
        const seen = new Set()
        const uris = []
        for (const track of tracks) {
            const uri = String(track?.uri ?? track?.path ?? "").trim()
            if (!uri || seen.has(uri)) continue
            seen.add(uri)
            uris.push(uri)
        }
        return uris
    }

    function enqueueTracks(tracks): void {
        if (!available) return
        const uris = _trackUris(tracks)
        if (uris.length === 0) return
        _bulkEnqueueRequests = [..._bulkEnqueueRequests, uris]
        _scheduleMpdMutation("bulk")
    }

    function _drainBulkEnqueueRequests(): void {
        if (_activeMpdMutation !== "bulk") return
        if (_bulkEnqueueProc.running || _bulkEnqueuePayloadWriting
                || _bulkEnqueueRequests.length === 0) return
        _bulkEnqueuePayloadWriting = true
        _saveMpdPayload(bulkEnqueuePayloadFile, JSON.stringify(_bulkEnqueueRequests[0]), root._startBulkEnqueuePayloadProcess)
    }

    function _startBulkEnqueuePayloadProcess(): void {
        if (!_bulkEnqueuePayloadWriting) return
        _bulkEnqueuePayloadWriting = false
        if (_bulkEnqueueRequests.length === 0) return

        _bulkEnqueueRequests = _bulkEnqueueRequests.slice(1)
        _bulkEnqueueProc.output = ""
        _bulkEnqueueProc.command = [
            root.nativeDispatchPath, "mpd", "enqueue-many",
            mpdHost, String(mpdPort), configuredLibraryFolder,
            "@" + _bulkEnqueuePayloadPath
        ]
        _bulkEnqueueProc.running = true
    }

    function _failBulkEnqueuePayloadWrite(_error): void {
        _bulkEnqueuePayloadWriting = false
        if (_bulkEnqueueRequests.length > 0)
            _bulkEnqueueRequests = _bulkEnqueueRequests.slice(1)
        error = "mpd_bulk_enqueue_payload_failed"
        _finishMpdMutation()
    }

    function createPlaylist(name: string, tracks): void {
        _queuePlaylistRequest("playlist-create", name, tracks)
    }

    function addTracksToPlaylist(name: string, tracks): void {
        _queuePlaylistRequest("playlist-add", name, tracks)
    }

    function _queuePlaylistRequest(mode: string, name: string, tracks): void {
        if (!available) return
        const playlistName = String(name ?? "").trim()
        const uris = _trackUris(tracks)
        if (!playlistName || uris.length === 0) return
        _playlistRequests = [..._playlistRequests, {
            mode: mode,
            name: playlistName,
            uris: uris
        }]
        _scheduleMpdMutation("playlist")
    }

    function _drainPlaylistRequests(): void {
        if (_activeMpdMutation !== "playlist") return
        if (_playlistProc.running || _playlistPayloadWriting
                || _playlistRequests.length === 0) return
        _playlistPayloadWriting = true
        _saveMpdPayload(playlistPayloadFile, JSON.stringify(_playlistRequests[0].uris), root._startPlaylistPayloadProcess)
    }

    function _startPlaylistPayloadProcess(): void {
        if (!_playlistPayloadWriting) return
        _playlistPayloadWriting = false
        if (_playlistRequests.length === 0) return

        const request = _playlistRequests[0]
        _playlistRequests = _playlistRequests.slice(1)
        _playlistProc.output = ""
        _playlistProc.command = [
            root.nativeDispatchPath, "mpd", request.mode,
            mpdHost, String(mpdPort), request.name,
            "@" + _playlistPayloadPath
        ]
        _playlistProc.running = true
    }

    function _failPlaylistPayloadWrite(_error): void {
        _playlistPayloadWriting = false
        if (_playlistRequests.length > 0)
            _playlistRequests = _playlistRequests.slice(1)
        error = "mpd_playlist_payload_failed"
        _finishMpdMutation()
    }

    function playQueue(queue, index = 0, name = ""): void {
        if (!available || !Array.isArray(queue) || queue.length === 0) return
        const valid = queue.filter(track =>
            String(track?.uri ?? track?.path ?? "").length > 0)
        if (valid.length === 0) return

        index = Math.max(0, Math.min(valid.length - 1, Number(index) || 0))
        activeQueue = valid
        activeQueueName = String(name ?? "")
        currentIndex = index
        resumeIndex = index
        _applyCurrentTrack(valid[index])
        currentPosition = 0
        error = ""

        _queueRequests = [..._queueRequests, {
            index: index,
            uris: valid.map(track => String(track.uri ?? track.path))
        }]
        _scheduleMpdMutation("queue")
    }

    function _drainQueueRequests(): void {
        if (_activeMpdMutation !== "queue") return
        if (_queueProc.running || _queuePayloadWriting
                || _queueRequests.length === 0) return
        _queuePayloadWriting = true
        _saveMpdPayload(queuePayloadFile, JSON.stringify(_queueRequests[0].uris), root._startQueuePayloadProcess)
    }

    function _saveMpdPayload(file, serialized: string, start): void {
        // An unchanged FileView write emits no saved() signal, including a
        // newly created file whose loaded flag is still false. Only reuse a
        // confirmed write: failed writes can leave new bytes in its cache.
        if (file.committedPayload === serialized) Qt.callLater(start)
        else file.setText(serialized)
    }

    function _resetFailedMpdPayload(file): void {
        file.committedPayload = ""
        // Reset the failed write's cached bytes so an identical retry writes
        // them again instead of silently becoming a FileView no-op.
        const path = file.path
        file.path = ""
        file.path = path
    }

    function _startQueuePayloadProcess(): void {
        if (!_queuePayloadWriting) return
        _queuePayloadWriting = false
        if (_queueRequests.length === 0) return

        const request = _queueRequests[0]
        _queueRequests = _queueRequests.slice(1)
        _queueProc.output = ""
        _queueProc.command = [
            root.nativeDispatchPath, "mpd", "queue",
            mpdHost, String(mpdPort), String(request.index),
            "@" + _queuePayloadPath
        ]
        _queueProc.running = true
    }

    function _failQueuePayloadWrite(_error): void {
        _queuePayloadWriting = false
        if (_queueRequests.length > 0)
            _queueRequests = _queueRequests.slice(1)
        error = "mpd_queue_payload_failed"
        _finishMpdMutation()
    }

    function _scheduleStatusFallback(): void {
        if (!root._mpdSubscriptionActive)
            statusRefreshTimer.restart()
    }

    // Serialize intent before payload writes, not merely after Process starts.
    // A Play/Delete/Enqueue must never overtake Clear/Add from a pending queue.
    function _scheduleMpdMutation(kind: string): void {
        _mpdMutationKinds = [..._mpdMutationKinds, kind]
        _drainMpdMutations()
    }

    function _drainMpdMutations(): void {
        if (_activeMpdMutation.length > 0 || _mpdMutationKinds.length === 0) return
        _activeMpdMutation = _mpdMutationKinds[0]
        _mpdMutationKinds = _mpdMutationKinds.slice(1)
        if (_activeMpdMutation === "queue") _drainQueueRequests()
        else if (_activeMpdMutation === "enqueue") _drainEnqueueRequests()
        else if (_activeMpdMutation === "bulk") _drainBulkEnqueueRequests()
        else if (_activeMpdMutation === "playlist") _drainPlaylistRequests()
        else if (_activeMpdMutation === "command") _drainCommandRequests()
    }

    function _finishMpdMutation(): void {
        _activeMpdMutation = ""
        Qt.callLater(root._drainMpdMutations)
    }

    function _mutationFailure(output: string, fallback: string): void {
        try {
            error = String(JSON.parse(output || "{}").error ?? fallback)
        } catch (e) { error = fallback }
    }

    function _sendMpd(command: string, args): void {
        _commandRequests = [..._commandRequests, {
            command: command, args: Array.isArray(args) ? args.slice() : []
        }]
        _scheduleMpdMutation("command")
    }

    function _drainCommandRequests(): void {
        if (_activeMpdMutation !== "command" || _commandRequests.length === 0) return
        const request = _commandRequests[0]
        _commandRequests = _commandRequests.slice(1)
        _commandProc.output = ""
        _commandProc.command = [
            root.nativeDispatchPath, "mpd", "command",
            mpdHost, String(mpdPort), request.command, JSON.stringify(request.args)
        ]
        _commandProc.running = true
    }

    function togglePlaying(): void {
        // MPD remains authoritative while stopped. mpd-mpris may disappear
        // after an idle stop, so Play must wake the queue without the bridge.
        if (!playing && mpdState === "stop") {
            const index = currentIndex >= 0 && currentIndex < activeQueue.length
                ? currentIndex
                : (resumeIndex >= 0 && resumeIndex < activeQueue.length
                    ? resumeIndex : (activeQueue.length > 0 ? 0 : -1))
            if (index >= 0) {
                resumeIndex = index
                _sendMpd("play", [index])
                return
            }
        }

        const player = mprisPlayer
        if (!mpdMutationPending && player && (player.canTogglePlaying ?? false)) {
            player.togglePlaying()
            root._scheduleStatusFallback()
            return
        }
        _sendMpd("pause", [playing ? 1 : 0])
    }

    function next(): void {
        const player = mprisPlayer
        if (!mpdMutationPending && player && MprisController.canGoNextForPlayer(player)) {
            MprisController.nextForPlayer(player, false)
            root._scheduleStatusFallback()
            return
        }
        _sendMpd("next", [])
    }

    function previous(): void {
        if (currentPosition > 3) {
            seek(0)
            return
        }
        const player = mprisPlayer
        if (!mpdMutationPending && player && MprisController.canGoPreviousForPlayer(player)) {
            MprisController.previousForPlayer(player, false)
            root._scheduleStatusFallback()
            return
        }
        _sendMpd("previous", [])
    }

    function jumpTo(index: int): void {
        if (index >= 0 && index < activeQueue.length) {
            resumeIndex = index
            _sendMpd("play", [index])
        }
    }

    function removeQueueTrack(index: int): void {
        if (index < 0 || index >= activeQueue.length) return
        const track = activeQueue[index]
        const queueId = Number(track?.queueId ?? -1)
        if (Number.isFinite(queueId) && queueId >= 0)
            _sendMpd("deleteid", [Math.trunc(queueId)])
        else
            _sendMpd("delete", [index])
    }

    function clearQueue(): void {
        if (activeQueue.length === 0) return
        _sendMpd("clear", [])
    }

    function seek(seconds: real): void {
        const target = Math.max(0, Number(seconds) || 0)
        const player = mprisPlayer
        if (!mpdMutationPending && player && (player.canSeek ?? false)
                && (player.positionSupported ?? true)) {
            player.position = target
            root._scheduleStatusFallback()
            return
        }
        _sendMpd("seekcur", [target])
    }

    function setVolume(value: real): void {
        const clamped = Math.max(0, Math.min(1, Number(value) || 0))
        volume = clamped
        const player = mprisPlayer
        if (!mpdMutationPending && player && (player.volumeSupported ?? false) && (player.canControl ?? false)) {
            player.volume = clamped
            root._scheduleStatusFallback()
            return
        }
        _sendMpd("setvol", [Math.round(clamped * 100)])
    }

    function toggleShuffle(): void {
        const target = !shuffleMode
        shuffleMode = target
        _sendMpd("random", [target ? 1 : 0])
    }

    function setRepeatMode(mode: int): void {
        const target = ((Number(mode) || 0) % 3 + 3) % 3
        repeatMode = target
        // MPD expresses track repeat as repeat+single and queue repeat as repeat.
        _sendMpd("repeat", [target === 0 ? 0 : 1, target === 1 ? 1 : 0])
    }

    function cycleRepeatMode(): void {
        setRepeatMode((repeatMode + 1) % 3)
    }

    function stop(): void {
        // Keep resume state in the MPD backend even if the MPRIS bridge is
        // reaped while idle.
        if (currentIndex >= 0 && currentIndex < activeQueue.length)
            resumeIndex = currentIndex
        _sendMpd("stop", [])
    }

    Component.onCompleted: {
        if (enabled) {
            MprisController.ensureMpdMprisBridge(mpdHost, mpdPort)
            _probeNativeMpd()
            Qt.callLater(root.rescan)
        }
    }

    onEnabledChanged: {
        if (enabled) {
            MprisController.ensureMpdMprisBridge(mpdHost, mpdPort)
            _probeNativeMpd()
            Qt.callLater(root.rescan)
        } else {
            _stopNativeMpdBridge()
        }
    }

    onConfiguredLibraryFolderChanged: root._configurationChanged()
    onConfiguredHostChanged: root._configurationChanged()
    onConfiguredPortChanged: root._configurationChanged()
    onCurrentPathChanged: Qt.callLater(root.refreshLocalLyrics)

    Process {
        id: _nativeBackendInfoProc
        property string output: ""
        command: [root.nativeDispatchPath, "backend-info"]

        stdout: StdioCollector {
            onStreamFinished: _nativeBackendInfoProc.output = text ?? ""
        }

        onExited: (code, _status) => {
            root._nativeBackendChecked = true
            let mode = ""
            let mpdReady = false
            if (code === 0) {
                const lines = String(_nativeBackendInfoProc.output ?? "").split("\n")
                for (const rawLine of lines) {
                    const line = rawLine.trim()
                    const separator = line.indexOf("=")
                    if (separator <= 0)
                        continue
                    const key = line.substring(0, separator)
                    const value = line.substring(separator + 1)
                    if (key === "mode")
                        mode = value
                    else if (key === "alis-mpdd")
                        mpdReady = value === "ready"
                }
            }

            root._nativeMpdEligible = mpdReady && (mode === "rust" || mode === "auto")
            if (root._nativeMpdEligible && root.enabled)
                root._startNativeMpdBridge()
            else
                root._stopNativeMpdBridge()
        }
    }

    Process {
        id: _mpdDaemonProc
        onExited: (_code, _status) => {
            root._mpdSubscriptionActive = false
            if (_mpdSubscriptionProc.running)
                _mpdSubscriptionProc.running = false
            if (root.enabled && root._nativeMpdEligible)
                mpdDaemonRetryTimer.restart()
        }
    }

    Process {
        id: _mpdSubscriptionProc
        command: [root.nativeDispatchPath, "mpd-subscribe"]

        stdout: SplitParser {
            onRead: line => root._handleMpdEvent(line)
        }

        onExited: (_code, _status) => {
            root._mpdSubscriptionActive = false
            if (root.enabled && root._nativeMpdEligible)
                mpdSubscribeRetryTimer.restart()
        }
    }

    Timer {
        id: mpdDaemonRetryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.enabled && root._nativeMpdEligible && !_mpdDaemonProc.running)
                root._startNativeMpdBridge()
        }
    }

    Timer {
        id: mpdSubscribeRetryTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.enabled && root._nativeMpdEligible && !_mpdSubscriptionProc.running)
                _mpdSubscriptionProc.running = true
        }
    }

    Timer {
        id: pollTimer
        interval: root.fallbackPollIntervalMs
        repeat: true
        running: root.enabled && !root._mpdSubscriptionActive
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: lyricsLiveTimer
        interval: 45
        repeat: true
        running: root.enabled && root.playing
        onTriggered: {
            const now = Date.now()
            if (root.mprisAvailable && (now - root._lastMprisNudgeMs) >= 480) {
                root._lastMprisNudgeMs = now
                root.mprisPlayer?.positionChanged()
            }
            if (root._lyricsAnchorMs <= 0) {
                root._reanchorLyricsPosition(root._baseLyricsPosition)
                return
            }
            const elapsed = Math.max(0, (now - root._lyricsAnchorMs) / 1000)
            const nextPos = root._lyricsAnchorPos + elapsed
            root._lyricsLivePos = root.currentDuration > 0
                ? Math.min(root.currentDuration, nextPos)
                : nextPos
        }
    }

    Timer {
        id: statusRefreshTimer
        interval: 180
        repeat: false
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: updateRescanTimer
        interval: 2200
        repeat: false
        onTriggered: root.rescan()
    }

    Timer {
        id: playlistRescanTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (_scanProc.running) {
                restart()
                return
            }
            root.rescan()
        }
    }

    FileView {
        id: queuePayloadFile
        property string committedPayload: ""
        path: Qt.resolvedUrl(root._queuePayloadPath)
        watchChanges: false
        printErrors: false
        onLoaded: committedPayload = text()
        onSaved: { committedPayload = text(); root._startQueuePayloadProcess() }
        onSaveFailed: error => { root._resetFailedMpdPayload(queuePayloadFile); root._failQueuePayloadWrite(error) }
    }

    FileView {
        id: bulkEnqueuePayloadFile
        property string committedPayload: ""
        path: Qt.resolvedUrl(root._bulkEnqueuePayloadPath)
        watchChanges: false
        printErrors: false
        onLoaded: committedPayload = text()
        onSaved: { committedPayload = text(); root._startBulkEnqueuePayloadProcess() }
        onSaveFailed: error => { root._resetFailedMpdPayload(bulkEnqueuePayloadFile); root._failBulkEnqueuePayloadWrite(error) }
    }

    FileView {
        id: playlistPayloadFile
        property string committedPayload: ""
        path: Qt.resolvedUrl(root._playlistPayloadPath)
        watchChanges: false
        printErrors: false
        onLoaded: committedPayload = text()
        onSaved: { committedPayload = text(); root._startPlaylistPayloadProcess() }
        onSaveFailed: error => { root._resetFailedMpdPayload(playlistPayloadFile); root._failPlaylistPayloadWrite(error) }
    }

    Process {
        id: _lyricsProc
        property string requestedPath: ""
        property string output: ""

        stdout: StdioCollector {
            onStreamFinished: _lyricsProc.output = text ?? ""
        }

        onStarted: _lyricsProc.output = ""

        onExited: (code, _status) => {
            const requestedPath = _lyricsProc.requestedPath
            if (requestedPath === root.currentPath) {
                if (code !== 0) {
                    root._clearLocalLyrics("error")
                } else {
                    try {
                        const payload = JSON.parse(_lyricsProc.output || "{}")
                        root.localLyricsStatus = String(payload.status ?? "not_found")
                        root.localLyricsPath = String(payload.path ?? "")
                        root.localLyricsSynced = payload.synced === true
                        root.localLyricsLines = payload.lines ?? []
                        if (root.localLyricsStatus === "not_found"
                                && !requestedPath.includes("://")
                                && root.currentTitle.trim().length > 0
                                && (Quickshell.env("FIXTURE_PORT") ?? "").length === 0) {
                            root.localLyricsStatus = "loading"
                            if (_lyricsDownloadProc.running)
                                _lyricsDownloadProc.running = false
                            _lyricsDownloadProc.requestedPath = requestedPath
                            _lyricsDownloadProc.output = ""
                            _lyricsDownloadProc.command = [
                                "/usr/bin/python3",
                                `${Directories.scriptsPath}/lyrics/lyrics.py`,
                                "--save-lrc",
                                requestedPath,
                                root.currentTitle,
                                root.currentArtist,
                                String(Math.round(root.currentDuration || 0)),
                                root.currentAlbum
                            ]
                            _lyricsDownloadProc.running = true
                        }
                    } catch (e) {
                        root._clearLocalLyrics("error")
                    }
                }
            }
            if (root._pendingLyricsPath.length > 0)
                Qt.callLater(root._startPendingLyrics)
        }
    }

    Process {
        id: _lyricsDownloadProc
        property string requestedPath: ""
        property string output: ""

        stdout: StdioCollector {
            onStreamFinished: _lyricsDownloadProc.output = text ?? ""
        }

        onStarted: _lyricsDownloadProc.output = ""

        onExited: (code, _status) => {
            const requestedPath = _lyricsDownloadProc.requestedPath
            if (requestedPath !== root.currentPath)
                return
            if (code !== 0) {
                root._clearLocalLyrics("not_found")
                return
            }
            try {
                const payload = JSON.parse(_lyricsDownloadProc.output || "{}")
                root.localLyricsStatus = String(payload.status ?? "not_found")
                root.localLyricsPath = String(payload.path ?? "")
                root.localLyricsSynced = payload.synced === true
                root.localLyricsLines = payload.lines ?? []
            } catch (e) {
                root._clearLocalLyrics("not_found")
            }
        }
    }

    Process {
        id: _scanProc
        property string output: ""
        stdout: StdioCollector {
            onStreamFinished: _scanProc.output = text ?? ""
        }
        onStarted: _scanProc.output = ""
        onExited: (code, _status) => {
            root.scanning = false
            if (code !== 0) {
                root.mpdConnected = false
                try {
                    const payload = JSON.parse(_scanProc.output || "{}")
                    root.error = String(payload.error ?? "mpd_unavailable")
                } catch (e) {
                    root.error = "mpd_unavailable"
                }
                return
            }
            try {
                root._applyPayload(JSON.parse(_scanProc.output || "{}"), true)
            } catch (e) {
                root.error = "mpd_snapshot_parse_failed"
            }
        }
    }

    Process {
        id: _statusProc
        property string output: ""
        stdout: StdioCollector {
            onStreamFinished: _statusProc.output = text ?? ""
        }
        onStarted: _statusProc.output = ""
        onExited: (code, _status) => {
            if (code !== 0) {
                root.mpdConnected = false
                return
            }
            try {
                root._applyPayload(JSON.parse(_statusProc.output || "{}"), false)
            } catch (e) {
                root.error = "mpd_status_parse_failed"
            }
        }
    }

    Process {
        id: _commandProc
        property string output: ""
        stdout: StdioCollector { onStreamFinished: _commandProc.output = text ?? "" }
        onStarted: _commandProc.output = ""
        onExited: (code, _status) => {
            if (code !== 0) root._mutationFailure(_commandProc.output, "mpd_command_failed")
            else root._scheduleStatusFallback()
            root._finishMpdMutation()
        }
    }

    Process {
        id: _queueProc
        property string output: ""
        stdout: StdioCollector {
            onStreamFinished: _queueProc.output = text ?? ""
        }
        onStarted: _queueProc.output = ""
        onExited: (code, _status) => {
            if (code !== 0)
                root._mutationFailure(_queueProc.output, "mpd_queue_failed")
            else
                root._scheduleStatusFallback()

            root._finishMpdMutation()
        }
    }

    Process {
        id: _enqueueProc
        property string output: ""
        stdout: StdioCollector {
            onStreamFinished: _enqueueProc.output = text ?? ""
        }
        onStarted: _enqueueProc.output = ""
        onExited: (code, _status) => {
            if (code !== 0) {
                root._mutationFailure(_enqueueProc.output, "mpd_enqueue_failed")
            } else {
                try {
                    root._applyPayload(JSON.parse(_enqueueProc.output || "{}"), false)
                } catch (e) {
                    root.error = "mpd_enqueue_parse_failed"
                }
            }
            root._finishMpdMutation()
        }
    }

    Process {
        id: _bulkEnqueueProc
        property string output: ""
        stdout: StdioCollector {
            onStreamFinished: _bulkEnqueueProc.output = text ?? ""
        }
        onStarted: _bulkEnqueueProc.output = ""
        onExited: (code, _status) => {
            if (code !== 0) {
                root._mutationFailure(_bulkEnqueueProc.output, "mpd_bulk_enqueue_failed")
            } else {
                try {
                    root._applyPayload(JSON.parse(_bulkEnqueueProc.output || "{}"), false)
                } catch (e) {
                    root.error = "mpd_bulk_enqueue_parse_failed"
                }
            }
            root._finishMpdMutation()
        }
    }

    Process {
        id: _playlistProc
        property string output: ""
        stdout: StdioCollector {
            onStreamFinished: _playlistProc.output = text ?? ""
        }
        onStarted: _playlistProc.output = ""
        onExited: (code, _status) => {
            if (code !== 0) {
                try {
                    const payload = JSON.parse(_playlistProc.output || "{}")
                    root.error = String(payload.error ?? "mpd_playlist_failed")
                } catch (e) {
                    root.error = "mpd_playlist_failed"
                }
            } else {
                root.error = ""
                playlistRescanTimer.restart()
            }
            root._finishMpdMutation()
        }
    }
}
