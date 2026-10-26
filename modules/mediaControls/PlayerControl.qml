pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.services
import "root:"

Item {
    id: root
    required property MprisPlayer player
    required property list<real> visualizerPoints
    // Bar media already hosts the live analyzer inside EqualizerPanel. Owners
    // without that DSP surface keep the historical decorative wave by default.
    property bool showVisualizer: true
    // Optional backend adapter. LocalMusic uses this to keep the same media
    // surface usable even while mpd-mpris is temporarily absent.
    property var playbackAdapter: null
    readonly property bool usingPlaybackAdapter: playbackAdapter !== null
    // CAVA's shared service adapts this ceiling to the real signal. Keep a
    // conservative fallback for external/legacy callers, while active owners
    // pass the shared normalization ceiling so quiet-but-real audio stays visible.
    property real visualizerMaxValue: 1000
    property real radius: Appearance.rounding.large
    property bool compactLayout: false
    // Item.visible can stay true while a retained popup/sidebar window is
    // unmapped. Position polling is presentation work, so bind it to both the
    // effective item visibility and the actual Quickshell window lifecycle.
    readonly property bool presentationActive: root.visible
        && (root.QsWindow.window?.visible ?? false)
    // Compact media cards can be substantially narrower than the Sidebar/Popup
    // surface (notably Dashboard tiles). Adapt the same PlayerControl instead
    // of letting its fixed transport row push duration outside the card.
    readonly property bool narrowLayout: root.compactLayout && root.width < 340
    readonly property real contentMargin: root.narrowLayout
        ? 7 : (root.compactLayout ? 9 : 12)
    readonly property real contentSpacing: root.narrowLayout
        ? 6 : (root.compactLayout ? 8 : 12)
    readonly property real artworkExtent: root.compactLayout
        ? Math.max(72, Math.min(root.narrowLayout ? 82 : 96,
            root.height - Appearance.sizes.elevationMargin
                - root.contentMargin * 2))
        : Math.max(0,
            root.height - Appearance.sizes.elevationMargin - 24)
    // Track-change slide direction: +1 next/forward (new content enters from the
    // right), -1 previous (enters from the left). Set by the prev/next handlers
    // before the track advances so the cross-slide reads as directed.
    property int slideDirection: 1
    
    // Use centralized YtMusic detection from MprisController
    readonly property bool isYtMusicPlayer: {
        if (!player) return false
        // Direct match with YtMusic.mpvPlayer
        if (YtMusic.mpvPlayer && player === YtMusic.mpvPlayer) return true
        // Use MprisController's detection for consistency
        return MprisController._isYtMusicMpv(player)
    }
    
    function doTogglePlaying(): void {
        if (root.usingPlaybackAdapter) {
            root.playbackAdapter.togglePlaying()
        } else if (isYtMusicPlayer) {
            YtMusic.togglePlaying()
        } else {
            player?.togglePlaying()
        }
    }
    
    function doPrevious(): void {
        root.slideDirection = -1
        if (root.usingPlaybackAdapter)
            root.playbackAdapter.previous()
        else
            MprisController.previousForPlayer(root.player)
    }
    
    function doNext(): void {
        root.slideDirection = 1
        if (root.usingPlaybackAdapter)
            root.playbackAdapter.next()
        else
            MprisController.nextForPlayer(root.player)
    }

    function doSeek(seconds: real): void {
        if (root.usingPlaybackAdapter)
            root.playbackAdapter.seek(seconds)
        else if (root.isYtMusicPlayer)
            YtMusic.seek(seconds)
        else if (root.player)
            root.player.position = seconds
    }

    function doToggleShuffle(): void {
        if (root.usingPlaybackAdapter)
            root.playbackAdapter.toggleShuffle()
        else
            MprisController.toggleShuffleForPlayer(root.player)
    }

    function doCycleRepeat(): void {
        if (root.usingPlaybackAdapter)
            root.playbackAdapter.cycleRepeat()
        else
            MprisController.cycleLoopForPlayer(root.player)
    }

    function focusPrimaryControl(): void {
        playPauseButton.forceActiveFocus()
    }
    
    // Screen position for aurora glass effect
    property real screenX: 0
    property real screenY: 0
    readonly property var surfaceScreen: root.QsWindow.window?.screen ?? Quickshell.screens[0] ?? null
    readonly property string surfaceWallpaperUrl: {
        const _dep1 = WallpaperListener.multiMonitorEnabled
        const _dep2 = WallpaperListener.effectivePerMonitor
        const _dep3 = Wallpapers.effectiveWallpaperUrl
        return WallpaperListener.wallpaperUrlForScreen(root.surfaceScreen)
    }

    readonly property string effectiveArtUrl: root.usingPlaybackAdapter
        ? String(root.playbackAdapter.artUrl ?? "")
        : (isYtMusicPlayer ? YtMusic.currentThumbnail : MprisController.effectiveArtUrl(player))
    readonly property string effectiveTitle: root.usingPlaybackAdapter
        ? String(root.playbackAdapter.title ?? "")
        : (isYtMusicPlayer ? YtMusic.currentTitle : (player?.trackTitle ?? ""))
    readonly property string effectiveArtist: root.usingPlaybackAdapter
        ? String(root.playbackAdapter.artist ?? "")
        : (isYtMusicPlayer ? YtMusic.currentArtist : (player?.trackArtist ?? ""))
    // Only the artwork identity may trigger cover motion. Title/artist often
    // arrive before the real art URL and caused the same cover to slide twice.
    readonly property string mediaTransitionKey: (root.effectiveArtUrl ?? "").split("?")[0].split("#")[0]
    property string artDownloadLocation: Directories.coverArt
    readonly property string resolverDisplaySource: artworkResolver.displaySource
    readonly property bool downloaded: root.displayedArtFilePath !== ""
    property string displayedArtFilePath: ""
    readonly property real effectiveLength: root.usingPlaybackAdapter
        ? Number(root.playbackAdapter.length ?? 0)
        : (root.isYtMusicPlayer ? YtMusic.currentDuration : (root.player?.length ?? 0))
    readonly property real _rawEffectivePosition: root.usingPlaybackAdapter
        ? Number(root.playbackAdapter.position ?? 0)
        : (root.isYtMusicPlayer ? YtMusic.currentPosition : (root.player?.position ?? 0))
    readonly property real effectivePosition: StringUtils.boundedMediaPosition(
        root._rawEffectivePosition, root.effectiveLength)
    readonly property bool effectiveIsPlaying: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.isPlaying
        : (root.isYtMusicPlayer ? YtMusic.isPlaying : (root.player?.isPlaying ?? false))
    readonly property bool effectiveCanSeek: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.canSeek
        : (root.isYtMusicPlayer ? YtMusic.canSeek : (root.player?.canSeek ?? false))
    readonly property bool effectiveCanGoPrevious: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.canGoPrevious
        : (isYtMusicPlayer ? YtMusic.canGoPrevious : MprisController.canGoPreviousForPlayer(root.player))
    readonly property bool effectiveCanGoNext: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.canGoNext
        : (isYtMusicPlayer ? YtMusic.canGoNext : MprisController.canGoNextForPlayer(root.player))
    readonly property bool effectiveShuffleSupported: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.shuffleSupported
        : MprisController.shuffleSupportedForPlayer(root.player)
    readonly property bool effectiveShuffleEnabled: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.shuffle
        : MprisController.shuffleForPlayer(root.player)
    readonly property bool effectiveRepeatSupported: root.usingPlaybackAdapter
        ? !!root.playbackAdapter.repeatSupported
        : MprisController.loopSupportedForPlayer(root.player)
    readonly property bool effectiveRepeatActive: root.usingPlaybackAdapter
        ? Number(root.playbackAdapter.repeatMode ?? 0) !== 0
        : MprisController.loopActiveForPlayer(root.player)
    readonly property bool effectiveRepeatOne: root.usingPlaybackAdapter
        ? Number(root.playbackAdapter.repeatMode ?? 0) === 1
        : MprisController.loopTrackForPlayer(root.player)

    function checkAndDownloadArt() {
        artworkResolver.refresh()
    }

    Connections {
        target: root.usingPlaybackAdapter ? null : root.player
        function onTrackArtUrlChanged() {
            if (!root.isYtMusicPlayer)
                root.checkAndDownloadArt()
        }
        function onTrackTitleChanged() {
            Qt.callLater(root.checkAndDownloadArt)
        }
        function onTrackArtistChanged() {
            Qt.callLater(root.checkAndDownloadArt)
        }
        function onTrackAlbumChanged() {
            Qt.callLater(root.checkAndDownloadArt)
        }
    }

    onResolverDisplaySourceChanged: {
        const src = root.resolverDisplaySource
        if (src && src.length > 0) {
            clearArtTimer.stop()
            root.displayedArtFilePath = src
        } else {
            clearArtTimer.restart()
        }
    }

    MediaArtworkResolver {
        id: artworkResolver
        sourceUrl: root.effectiveArtUrl
        title: root.effectiveTitle
        artist: root.effectiveArtist
        album: root.usingPlaybackAdapter
            ? String(root.playbackAdapter.album ?? "")
            : (root.player?.trackAlbum ?? "")
        cacheDirectory: root.artDownloadLocation
    }

    Timer {
        id: clearArtTimer
        interval: 1600
        onTriggered: {
            if (!root.resolverDisplaySource || root.resolverDisplaySource.length === 0)
                root.displayedArtFilePath = ""
        }
    }

    property bool _lyricsSubscribed: false
    readonly property bool _wantOnlineLyrics: root.presentationActive
        && !root.usingPlaybackAdapter
        && root.player !== null
        && root.player === MprisController.activePlayer
    readonly property string effectiveOnlineLyricLine: {
        if (!root._wantOnlineLyrics || LyricsService.status !== "ok")
            return ""
        return String(LyricsService.currentLine ?? "").trim()
    }
    function _syncLyricsSubscription(): void {
        const want = root._wantOnlineLyrics
        if (want === root._lyricsSubscribed)
            return
        root._lyricsSubscribed = want
        if (want)
            LyricsService.subscribe()
        else
            LyricsService.unsubscribe()
    }
    on_WantOnlineLyricsChanged: root._syncLyricsSubscription()

    Component.onCompleted: {
        if (root.resolverDisplaySource && root.resolverDisplaySource.length > 0)
            root.displayedArtFilePath = root.resolverDisplaySource
        root._syncLyricsSubscription()
    }

    Component.onDestruction: {
        if (root._lyricsSubscribed) {
            root._lyricsSubscribed = false
            LyricsService.unsubscribe()
        }
    }

    Timer {
        running: root.presentationActive
            && !root.usingPlaybackAdapter
            && root.player?.playbackState === MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    property color artDominantColor: ColorUtils.mix(
        colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary,
        Appearance.colors.colPrimaryContainer, 0.7
    )

    property QtObject blendedColors: AdaptedMaterialScheme { color: root.artDominantColor }

    StyledRectangularShadow { target: card }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: parent.width - Appearance.sizes.elevationMargin
        height: parent.height - Appearance.sizes.elevationMargin
        radius: root.radius
        Behavior on radius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        color: blendedColors?.colLayer0 ?? Appearance.colors.colLayer0
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        border.width: 0
        Behavior on border.width {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        border.color: "transparent"
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        clip: true

        layer.enabled: true
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle { width: card.width; height: card.height; radius: card.radius }
        }

        // Card-level art wash follows the loaded art without sliding. Only the
        // visible cover moves, so a track change has one clear motion.
        MediaCrossSlideImage {
            id: bgArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            transitionKey: "player-card-wash"
            downloaded: root.downloaded
            slideDirection: root.slideDirection
            animateChanges: false
            artRadius: card.radius
            placeholderColor: blendedColors?.colLayer0 ?? Appearance.colors.colLayer0
            iconColor: "transparent"
            opacity: 0.5
            visible: root.displayedArtFilePath !== ""
            effectEnabled: Appearance.effectsEnabled
            blurEnabled: true
            blur: 0.15
            blurMax: 16
            saturation: 0.3
        }

        // Gradient overlay for Material only — a material-tinted wash that
        // clashes with the flat ZZZ console plate, so exclude it there.
        Rectangle {
            anchors.fill: parent
            visible: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.35; color: ColorUtils.transparentize(blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.3) }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.15) }
            }
        }

        // Visualizer at bottom
        WaveVisualizer {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 35
            visible: root.showVisualizer
            live: root.showVisualizer && root.effectiveIsPlaying
            points: root.visualizerPoints
            maxVisualizerValue: Math.max(1, root.visualizerMaxValue)
            smoothing: 2
            color: ColorUtils.transparentize(
                blendedColors?.colPrimary ?? Appearance.colors.colPrimary, 0.6)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.contentMargin
            spacing: root.contentSpacing

            // Cover art — direction-aware cross-slide (one leaves, one enters)
            MediaCrossSlideImage {
                id: coverArtContainer
                Layout.preferredWidth: root.artworkExtent
                Layout.preferredHeight: root.artworkExtent
                artRadius: Appearance.rounding.small
                source: root.displayedArtFilePath
                transitionKey: root.mediaTransitionKey
                downloaded: root.downloaded
                slideDirection: root.slideDirection
                placeholderColor: blendedColors?.colLayer1 ?? Appearance.colors.colLayer1
                iconColor: blendedColors?.colSubtext ?? Appearance.colors.colSubtext
                iconSize: 32
            }

            // Info & controls
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                spacing: root.compactLayout ? 3 : 4

                // Title
                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.effectiveTitle) || "—"
                    font.pixelSize: root.compactLayout
                        ? Appearance.font.pixelSize.normal
                        : Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    font.italic: false
                    color: blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    elide: Text.ElideRight
                    animateChange: true
                    animationDistanceX: root.slideDirection * 8
                    animationDistanceY: 0
                }

                // Artist
                StyledText {
                    Layout.fillWidth: true
                    text: root.effectiveArtist
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: blendedColors?.colSubtext ?? Appearance.colors.colSubtext
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    elide: Text.ElideRight
                    visible: text !== ""
                    animateChange: true
                    animationDistanceX: root.slideDirection * 8
                    animationDistanceY: 0
                }

                // Online synced lyric line (for streaming players without saving local .lrc)
                StyledText {
                    Layout.fillWidth: true
                    text: root.effectiveOnlineLyricLine
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.italic: true
                    color: blendedColors?.colPrimary ?? Appearance.colors.colPrimary
                    elide: Text.ElideRight
                    visible: text !== ""
                    animateChange: true
                    animationDistanceX: 0
                    animationDistanceY: 4
                }

                Item { Layout.fillHeight: true }

                // Progress bar
                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.compactLayout ? 12 : 16

                    Loader {
                        id: seekLoader
                        anchors.fill: parent
                        active: root.effectiveCanSeek
                        sourceComponent: StyledSlider {
                            Accessible.name: Translation.tr("Playback position")
                            configuration: StyledSlider.Configuration.Wavy
                            wavy: root.effectiveIsPlaying
                            animateWave: root.effectiveIsPlaying
                            highlightColor: blendedColors?.colPrimary ?? Appearance.colors.colPrimary
                            trackColor: blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                            handleColor: blendedColors?.colPrimary ?? Appearance.colors.colPrimary
                            value: root.effectiveLength > 0 ? root.effectivePosition / root.effectiveLength : 0
                            onMoved: root.doSeek(value * root.effectiveLength)
                            scrollable: true
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: !(root.effectiveCanSeek)
                        sourceComponent: StyledProgressBar {
                            wavy: root.effectiveIsPlaying
                            animateWave: root.effectiveIsPlaying
                            highlightColor: blendedColors?.colPrimary ?? Appearance.colors.colPrimary
                            trackColor: blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                            value: root.effectiveLength > 0 ? root.effectivePosition / root.effectiveLength : 0
                        }
                    }

                    KeyboardFocusRing {
                        anchors.fill: parent
                        focusVisible: seekLoader.item?.visualFocus ?? false
                    }
                }

                // Time + controls
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: root.narrowLayout ? 0 : (root.compactLayout ? 1 : 4)

                    StyledText {
                        Layout.minimumWidth: implicitWidth
                        text: StringUtils.friendlyTimeForSeconds(root.effectivePosition)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        implicitWidth: root.narrowLayout ? 22 : (root.compactLayout ? 26 : 30)
                        implicitHeight: implicitWidth
                        buttonText: Translation.tr("Shuffle")
                        enabled: root.effectiveShuffleSupported
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.effectiveShuffleEnabled
                            ? ColorUtils.transparentize(
                                blendedColors?.colPrimary ?? Appearance.colors.colPrimary, 0.78)
                            : "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active
                        onClicked: root.doToggleShuffle()
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "shuffle"
                                iconSize: root.narrowLayout ? 15 : (root.compactLayout ? 17 : 19)
                                fill: root.effectiveShuffleEnabled ? 1 : 0
                                color: root.effectiveShuffleEnabled
                                    ? (blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: root.narrowLayout ? 24 : (root.compactLayout ? 28 : 32)
                        implicitHeight: implicitWidth
                        buttonText: Translation.tr("Previous")
                        enabled: root.effectiveCanGoPrevious
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active
                        onClicked: root.doPrevious()
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "skip_previous"
                                iconSize: root.narrowLayout ? 17 : (root.compactLayout ? 19 : 22)
                                fill: 1
                                color: blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                }
                            }
                        }
                    }

                    RippleButton {
                        id: playPauseButton
                        implicitWidth: root.narrowLayout ? 30 : (root.compactLayout ? 34 : 40)
                        implicitHeight: implicitWidth
                        buttonText: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        onClicked: root.doTogglePlaying()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.player?.isPlaying ? "pause" : "play_arrow"
                                iconSize: root.narrowLayout ? 19 : (root.compactLayout ? 21 : 24)
                                fill: 1
                                color: Appearance.colors.colOnLayer1
                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                }
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: root.narrowLayout ? 24 : (root.compactLayout ? 28 : 32)
                        implicitHeight: implicitWidth
                        buttonText: Translation.tr("Next")
                        enabled: root.effectiveCanGoNext
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active
                        onClicked: root.doNext()
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "skip_next"
                                iconSize: root.narrowLayout ? 17 : (root.compactLayout ? 19 : 22)
                                fill: 1
                                color: blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                }
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: root.narrowLayout ? 22 : (root.compactLayout ? 26 : 30)
                        implicitHeight: implicitWidth
                        buttonText: Translation.tr("Repeat")
                        enabled: root.effectiveRepeatSupported
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.effectiveRepeatActive
                            ? ColorUtils.transparentize(
                                blendedColors?.colPrimary ?? Appearance.colors.colPrimary, 0.78)
                            : "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active
                        onClicked: root.doCycleRepeat()
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.effectiveRepeatOne ? "repeat_one" : "repeat"
                                iconSize: root.narrowLayout ? 15 : (root.compactLayout ? 17 : 19)
                                fill: root.effectiveRepeatActive ? 1 : 0
                                color: root.effectiveRepeatActive
                                    ? (blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        Layout.minimumWidth: implicitWidth
                        text: StringUtils.friendlyTimeForSeconds(root.effectiveLength)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }
                }
            }
        }
    }
}
