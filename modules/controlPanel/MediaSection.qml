pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import "root:"

Item {
    id: root
    Layout.fillWidth: true
    implicitHeight: hasPlayer ? card.implicitHeight : 0
    visible: implicitHeight > 0

    Behavior on implicitHeight {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Appearance.animation.elementResize.type
            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
        }
    }

    readonly property bool compactMode: Config.options?.controlPanel?.compactMode ?? true
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isYtMusicActive: MprisController.isYtMusicActive
    readonly property bool hasPlayer:
        (player && player.trackTitle) || (isYtMusicActive && YtMusic.currentVideoId)

    readonly property bool isMpdPlayer: !isYtMusicActive && player !== null && player === MprisController.mpdPlayer
    readonly property string effectiveArtUrl: isYtMusicActive && YtMusic.currentThumbnail
        ? YtMusic.currentThumbnail : (player?.trackArtUrl ?? "")
    readonly property string effectiveTitle: isYtMusicActive && YtMusic.currentTitle
        ? YtMusic.currentTitle : (player?.trackTitle ?? "")
    readonly property string effectiveArtist: isYtMusicActive && YtMusic.currentArtist
        ? YtMusic.currentArtist : (player?.trackArtist ?? "")
    readonly property bool effectiveIsPlaying: isYtMusicActive
        ? YtMusic.isPlaying : (player?.isPlaying ?? false)
    readonly property bool effectiveCanSeek: isYtMusicActive
        ? YtMusic.canSeek : (player?.canSeek ?? false)
    readonly property real _rawEffectiveLength: isYtMusicActive
        ? YtMusic.currentDuration
        : (((player?.lengthSupported ?? false) && (player?.length ?? 0) > 0)
            ? (player?.length ?? 0)
            : (isMpdPlayer
                ? LocalMusic.currentDuration
                : MprisController.effectiveLengthForPlayer(root.player)))
    readonly property real effectiveLength: StringUtils.validMediaDuration(root._rawEffectiveLength)
    readonly property real _rawEffectivePosition: isYtMusicActive
        ? YtMusic.currentPosition
        : ((isMpdPlayer && (player?.position ?? 0) <= 0 && LocalMusic.lyricsPosition > 0)
            ? LocalMusic.lyricsPosition
            : (player?.position ?? 0))
    readonly property real effectivePosition: StringUtils.boundedMediaPosition(
        root._rawEffectivePosition, root.effectiveLength)
    readonly property real effectiveDisplayedPosition: (seekLoader.item?.pressed ?? false)
        ? Math.max(0, Math.min(root.effectiveLength, (seekLoader.item?.value ?? 0) * root.effectiveLength))
        : root.effectivePosition
    readonly property bool positionTickerActive:
        root.player?.playbackState === MprisPlaybackState.Playing
        && GlobalStates.controlPanelOpen

    property string artDownloadLocation: Directories.coverArt
    readonly property bool downloaded: MediaArtwork.ready
    property string displayedArtFilePath: MediaArtwork.displaySource

    function checkAndDownloadArt() {
        MediaArtwork.refresh()
    }

    CavaProcess {
        id: cavaProcess
        active: root.visible && root.hasPlayer && root.effectiveIsPlaying && GlobalStates.controlPanelOpen
    }

    property list<real> visualizerPoints: cavaProcess.points

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
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property int cardHeight: root.compactMode ? 128 : 160
    readonly property int coverArtSize: root.compactMode ? 104 : 136
    readonly property int outerMargin: root.compactMode ? 10 : 12
    readonly property int controlButtonSize: root.compactMode ? 28 : 32
    readonly property int primaryControlButtonSize: root.compactMode ? 38 : 44
    readonly property int controlIconSize: root.compactMode ? 20 : 22
    readonly property int primaryControlIconSize: root.compactMode ? 22 : 26
    readonly property real _dpr: root.window ? root.window.devicePixelRatio : 1

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: root.cardHeight
        radius: Appearance.rounding.normal
        color: root.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0
        border.width: 0
        border.color: "transparent"
        clip: true

        layer.enabled: root.visible && GlobalStates.controlPanelOpen
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                radius: card.radius
            }
        }

        Image {
            id: bgArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            mipmap: false
            sourceSize.width: Math.max(1, Math.ceil(card.width * root._dpr))
            sourceSize.height: Math.max(1, Math.ceil(card.height * root._dpr))
            opacity: root.displayedArtFilePath !== "" ? 0.5 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            layer.enabled: root.visible && GlobalStates.controlPanelOpen && Appearance.effectsEnabled
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.15
                blurMax: 16
                saturation: 0.3
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.35
                    color: ColorUtils.transparentize(
                        root.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.3)
                }
                GradientStop {
                    position: 1.0
                    color: ColorUtils.transparentize(
                        root.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.15)
                }
            }
        }

        WaveVisualizer {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.compactMode ? 28 : 40
            live: root.player?.isPlaying ?? false
            points: root.visualizerPoints
            maxVisualizerValue: 1000
            smoothing: 2
            color: ColorUtils.transparentize(
                root.blendedColors?.colPrimary ?? Appearance.colors.colPrimary, 0.6)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.outerMargin
            spacing: root.compactMode ? 10 : 12

            Rectangle {
                id: coverArtContainer
                Layout.preferredWidth: root.coverArtSize
                Layout.preferredHeight: root.coverArtSize
                radius: Appearance.rounding.small
                color: "transparent"
                clip: true

                layer.enabled: root.visible && GlobalStates.controlPanelOpen
                layer.effect: GE.OpacityMask {
                    maskSource: Rectangle {
                        width: root.coverArtSize
                        height: root.coverArtSize
                        radius: Appearance.rounding.small
                    }
                }

                Image {
                    id: coverArt
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    mipmap: false
                    sourceSize.width: root.coverArtSize * 2
                    sourceSize.height: root.coverArtSize * 2
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.blendedColors?.colLayer1 ?? Appearance.colors.colLayer1
                    opacity: !root.downloaded ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: root.compactMode ? 36 : 48
                        color: root.blendedColors?.colSubtext ?? Appearance.colors.colSubtext
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.effectiveTitle) || "—"
                    font.pixelSize: root.compactMode
                        ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: root.blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.effectiveArtist || ""
                    font.pixelSize: root.compactMode
                        ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
                    color: root.blendedColors?.colSubtext ?? Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    opacity: text !== "" ? 0.7 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.compactMode ? 12 : 16

                    Loader {
                        id: seekLoader
                        anchors.fill: parent
                        active: root.effectiveCanSeek
                        sourceComponent: StyledSlider {
                            Accessible.name: Translation.tr("Playback position")
                            configuration: StyledSlider.Configuration.Wavy
                            wavy: root.effectiveIsPlaying
                            animateWave: root.effectiveIsPlaying
                            highlightColor: root.blendedColors?.colPrimary
                                ?? Appearance.colors.colPrimary
                            trackColor: root.blendedColors?.colSecondaryContainer
                                ?? Appearance.colors.colSecondaryContainer
                            handleColor: root.blendedColors?.colPrimary
                                ?? Appearance.colors.colPrimary
                            liveValue: root.effectiveLength > 0
                                ? root.effectivePosition / root.effectiveLength : 0
                            tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.effectiveLength)
                            onMoved: root.player.position = value * root.player.length
                            onSeekCommitted: (val) => {
                                const target = val * root.effectiveLength
                                if (root.isYtMusicActive)
                                    YtMusic.seek(target)
                                else if (root.isMpdPlayer)
                                    LocalMusic.seek(target)
                                else if (root.player)
                                    root.player.position = target
                            }
                            scrollable: true
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: !root.effectiveCanSeek
                        sourceComponent: StyledProgressBar {
                            wavy: root.effectiveIsPlaying
                            animateWave: root.effectiveIsPlaying
                            highlightColor: root.blendedColors?.colPrimary
                                ?? Appearance.colors.colPrimary
                            trackColor: root.blendedColors?.colSecondaryContainer
                                ?? Appearance.colors.colSecondaryContainer
                            value: root.effectiveLength > 0
                                ? root.effectivePosition / root.effectiveLength : 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.effectiveDisplayedPosition)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: root.blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    RippleButton {
                        implicitWidth: root.controlButtonSize
                        implicitHeight: root.controlButtonSize
                        buttonText: Translation.tr("Shuffle")
                        enabled: MprisController.shuffleSupported
                        buttonRadius: Appearance.rounding.full
                        colBackground: MprisController.hasShuffle
                            ? ColorUtils.transparentize(root.blendedColors?.colPrimary
                                ?? Appearance.colors.colPrimary, 0.78)
                            : "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            root.blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: root.blendedColors?.colLayer1Active
                            ?? Appearance.colors.colLayer1Active
                        onClicked: MprisController.toggleShuffleForPlayer(root.player)
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "shuffle"
                                iconSize: root.controlIconSize
                                fill: MprisController.hasShuffle ? 1 : 0
                                color: MprisController.hasShuffle
                                    ? (root.blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (root.blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                            }
                        }
                        StyledToolTip { text: Translation.tr("Shuffle") }
                    }

                    RippleButton {
                        implicitWidth: root.controlButtonSize
                        implicitHeight: root.controlButtonSize
                        buttonText: Translation.tr("Previous")
                        enabled: MprisController.canGoPrevious
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            root.blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: root.blendedColors?.colLayer1Active
                            ?? Appearance.colors.colLayer1Active
                        onClicked: MprisController.previous()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "skip_previous"
                                iconSize: root.controlIconSize
                                fill: 1
                                color: root.blendedColors?.colOnLayer0
                                    ?? Appearance.colors.colOnLayer0
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Previous")
                        }
                    }

                    RippleButton {
                        id: playPauseButton
                        implicitWidth: root.primaryControlButtonSize
                        implicitHeight: root.primaryControlButtonSize
                        buttonText: root.player?.isPlaying
                            ? Translation.tr("Pause") : Translation.tr("Play")
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        onClicked: MprisController.togglePlaying()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.player?.isPlaying ? "pause" : "play_arrow"
                                iconSize: root.primaryControlIconSize
                                fill: 1
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        StyledToolTip {
                            text: root.player?.isPlaying
                                ? Translation.tr("Pause") : Translation.tr("Play")
                        }
                    }

                    RippleButton {
                        implicitWidth: root.controlButtonSize
                        implicitHeight: root.controlButtonSize
                        buttonText: Translation.tr("Next")
                        enabled: MprisController.canGoNext
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            root.blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: root.blendedColors?.colLayer1Active
                            ?? Appearance.colors.colLayer1Active
                        onClicked: MprisController.next()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "skip_next"
                                iconSize: root.controlIconSize
                                fill: 1
                                color: root.blendedColors?.colOnLayer0
                                    ?? Appearance.colors.colOnLayer0
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Next")
                        }
                    }

                    RippleButton {
                        implicitWidth: root.controlButtonSize
                        implicitHeight: root.controlButtonSize
                        buttonText: Translation.tr("Repeat")
                        enabled: MprisController.loopSupported
                        buttonRadius: Appearance.rounding.full
                        colBackground: MprisController.loopActive
                            ? ColorUtils.transparentize(root.blendedColors?.colPrimary
                                ?? Appearance.colors.colPrimary, 0.78)
                            : "transparent"
                        colBackgroundHover: ColorUtils.transparentize(
                            root.blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: root.blendedColors?.colLayer1Active
                            ?? Appearance.colors.colLayer1Active
                        onClicked: MprisController.cycleLoopForPlayer(root.player)
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: MprisController.loopTrack ? "repeat_one" : "repeat"
                                iconSize: root.controlIconSize
                                fill: MprisController.loopActive ? 1 : 0
                                color: MprisController.loopActive
                                    ? (root.blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (root.blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                            }
                        }
                        StyledToolTip { text: Translation.tr("Repeat") }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.effectiveLength)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: root.blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }

    Timer {
        running: root.positionTickerActive
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }
}
