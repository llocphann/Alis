pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.services

/**
 * Media player widget for lock screen - reuses sidebar MediaPlayerWidget design
 */
Item {
    id: root
    implicitHeight: hasPlayer ? card.implicitHeight + Appearance.sizes.elevationMargin : 0
    visible: hasPlayer

    required property MprisPlayer player
    readonly property bool hasPlayer: player && player.trackTitle
    readonly property bool isMpdPlayer: player !== null && player === MprisController.mpdPlayer
    readonly property real _rawEffectiveLength: ((player?.lengthSupported ?? false) && (player?.length ?? 0) > 0)
        ? (player?.length ?? 0)
        : (isMpdPlayer
            ? LocalMusic.currentDuration
            : MprisController.effectiveLengthForPlayer(root.player))
    readonly property real effectiveLength: StringUtils.validMediaDuration(root._rawEffectiveLength)
    readonly property real _rawEffectivePosition: (isMpdPlayer && (player?.position ?? 0) <= 0 && LocalMusic.lyricsPosition > 0)
        ? LocalMusic.lyricsPosition
        : (player?.position ?? 0)
    readonly property real effectivePosition: StringUtils.boundedMediaPosition(
        root._rawEffectivePosition, root.effectiveLength)
    readonly property real effectiveDisplayedPosition: (seekLoader.item?.pressed ?? false)
        ? Math.max(0, Math.min(root.effectiveLength, (seekLoader.item?.value ?? 0) * root.effectiveLength))
        : root.effectivePosition
    readonly property bool presentationActive: GlobalStates.screenLocked
        && root.visible
        && (root.QsWindow.window?.visible ?? false)
    readonly property string artUrl: player?.trackArtUrl ?? ""
    property string artDownloadLocation: Directories.coverArt
    readonly property bool downloaded: MediaArtwork.ready
    property string displayedArtFilePath: MediaArtwork.displaySource

    function checkAndDownloadArt() {
        MediaArtwork.refresh()
    }

    onVisibleChanged: {
        if (visible && hasPlayer) {
            checkAndDownloadArt()
        }
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

    // Alis uses fixed colors instead of adaptive
    readonly property color jiraColText: Appearance.alis.colText
    readonly property color jiraColTextSecondary: Appearance.alis.colTextSecondary
    readonly property color jiraColPrimary: Appearance.alis.colPrimary
    readonly property color jiraColLayer1: Appearance.alis.colLayer1
    readonly property color jiraColLayer2: Appearance.alis.colLayer2

    StyledRectangularShadow { target: card; visible: Appearance.angelEverywhere || (!Appearance.alisEverywhere && !Appearance.auroraEverywhere) }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: parent.width - Appearance.sizes.elevationMargin
        implicitHeight: 130
        radius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
            : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.normal
        color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
             : Appearance.alisEverywhere ? Appearance.alis.colLayer1
             : Appearance.auroraEverywhere ? ColorUtils.transparentize(blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.7)
             : (blendedColors?.colLayer0 ?? Appearance.colors.colLayer0)
        border.width: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth
            : Appearance.zzzEverywhere ? 1
            : Appearance.alisEverywhere ? 1 : 0
        border.color: Appearance.angelEverywhere ? Appearance.angel.colCardBorder
            : Appearance.zzzEverywhere ? Appearance.zzz.hairline
            : Appearance.alisEverywhere ? Appearance.alis.colBorder : "transparent"
        Behavior on border.width {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        clip: true

        layer.enabled: Appearance.effectsEnabled
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle { width: card.width; height: card.height; radius: card.radius }
        }

        // Cover art background
        Image {
            id: bgArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            opacity: Appearance.alisEverywhere ? 0.2 : (Appearance.auroraEverywhere ? 0.3 : 0.6)
            visible: root.displayedArtFilePath !== ""

            layer.enabled: Appearance.effectsEnabled
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: Appearance.alisEverywhere ? 0.5 : 0.4
                blurMax: 32
                saturation: Appearance.alisEverywhere ? 0.1 : 0.4
            }
        }

        // Dark overlay for controls visibility
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: ColorUtils.transparentize(blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.7) }
                GradientStop { position: 0.3; color: ColorUtils.transparentize(blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.4) }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.2) }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            // Cover art thumbnail
            Rectangle {
                id: coverArtContainer
                Layout.preferredWidth: 110
                Layout.preferredHeight: 110
                Layout.alignment: Qt.AlignVCenter
                radius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                color: "transparent"
                clip: true

                layer.enabled: Appearance.effectsEnabled
                layer.effect: GE.OpacityMask {
                    maskSource: Rectangle {
                        width: 110
                        height: 110
                        radius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                    }
                }

                // Cover art with blur transition
                Image {
                    id: coverArt
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: coverArtContainer.transitioning ? 1 : 0
                        blurMax: 32
                        Behavior on blur {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                        }
                    }
                }

                property bool transitioning: false
                property string pendingSource: ""

                Component.onCompleted: {
                    if (root.displayedArtFilePath)
                        coverArt.source = root.displayedArtFilePath
                }

                Timer {
                    id: blurInTimer
                    interval: 150
                    onTriggered: {
                        coverArt.source = coverArtContainer.pendingSource
                        blurOutTimer.start()
                    }
                }

                Timer {
                    id: blurOutTimer
                    interval: 50
                    onTriggered: coverArtContainer.transitioning = false
                }

                Connections {
                    target: root
                    function onDisplayedArtFilePathChanged() {
                        if (!root.displayedArtFilePath) {
                            blurInTimer.stop()
                            blurOutTimer.stop()
                            coverArtContainer.pendingSource = ""
                            coverArtContainer.transitioning = false
                            coverArt.source = ""
                            return
                        }
                        if (!coverArt.source.toString()) {
                            coverArt.source = root.displayedArtFilePath
                            return
                        }
                        coverArtContainer.pendingSource = root.displayedArtFilePath
                        coverArtContainer.transitioning = true
                        blurInTimer.start()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Appearance.alisEverywhere ? root.jiraColLayer2 : (blendedColors?.colLayer1 ?? Appearance.colors.colLayer1)
                    visible: !root.downloaded || coverArt.status !== Image.Ready

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 32
                        color: Appearance.alisEverywhere ? root.jiraColTextSecondary : (blendedColors?.colSubtext ?? Appearance.colors.colSubtext)
                    }
                }
            }

            // Info & controls column
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                // Title
                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "—"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.alisEverywhere ? root.jiraColText : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                    elide: Text.ElideRight
                    animateChange: true
                    animationDistanceX: 6
                }

                // Artist
                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist || ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.alisEverywhere ? root.jiraColTextSecondary : (blendedColors?.colSubtext ?? Appearance.colors.colSubtext)
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                Item { Layout.fillHeight: true }

                // Progress bar
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 16

                    Loader {
                        id: seekLoader
                        anchors.fill: parent
                        active: root.player?.canSeek ?? false
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            wavy: root.player?.isPlaying ?? false
                            animateWave: root.player?.isPlaying ?? false
                            highlightColor: Appearance.alisEverywhere ? root.jiraColPrimary : (blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                            trackColor: Appearance.alisEverywhere ? Appearance.alis.colLayer2 : Appearance.zzzEverywhere ? Appearance.colors.colLayer2 : (blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                            handleColor: Appearance.alisEverywhere ? root.jiraColPrimary : (blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                            liveValue: root.effectiveLength > 0 ? root.effectivePosition / root.effectiveLength : 0
                            tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.effectiveLength)
                            onSeekCommitted: (val) => {
                                const target = val * root.effectiveLength
                                if (root.isMpdPlayer)
                                    LocalMusic.seek(target)
                                else if (root.player)
                                    root.player.position = target
                            }
                            scrollable: true
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: !(root.player?.canSeek ?? false)
                        sourceComponent: StyledProgressBar {
                            wavy: root.player?.isPlaying ?? false
                            animateWave: root.player?.isPlaying ?? false
                            highlightColor: Appearance.alisEverywhere ? root.jiraColPrimary : (blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                            trackColor: Appearance.alisEverywhere ? Appearance.alis.colLayer2 : Appearance.zzzEverywhere ? Appearance.colors.colLayer2 : (blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                            value: root.effectiveLength > 0 ? root.effectivePosition / root.effectiveLength : 0
                        }
                    }
                }

                // Time + controls row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.effectiveDisplayedPosition)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: Appearance.alisEverywhere ? root.jiraColText : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                    }

                    Item { Layout.fillWidth: true }

                    // Controls
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        enabled: MprisController.canGoPrevious
                        buttonRadius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover : ColorUtils.transparentize(blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: Appearance.alisEverywhere ? Appearance.alis.colLayer2Active : (blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active)
                        onClicked: MprisController.previous()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "skip_previous"
                                iconSize: 22
                                fill: 1
                                color: Appearance.alisEverywhere ? root.jiraColText : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                            }
                        }
                    }

                    RippleButton {
                        id: playPauseButton
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.alisEverywhere
                            ? Appearance.alis.roundingSmall
                            : (root.player?.isPlaying ? Appearance.rounding.normal : Appearance.rounding.full)
                        colBackground: Appearance.alisEverywhere
                            ? "transparent"
                            : Appearance.auroraEverywhere
                                ? "transparent"
                                : (root.player?.isPlaying
                                    ? (blendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer))
                        colBackgroundHover: Appearance.alisEverywhere
                            ? Appearance.alis.colLayer2Hover
                            : Appearance.auroraEverywhere
                                ? ColorUtils.transparentize(blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                                : (root.player?.isPlaying
                                    ? (blendedColors?.colPrimaryHover ?? Appearance.colors.colPrimaryHover)
                                    : (blendedColors?.colSecondaryContainerHover ?? Appearance.colors.colSecondaryContainerHover))
                        colRipple: Appearance.alisEverywhere
                            ? Appearance.alis.colLayer2Active
                            : Appearance.auroraEverywhere
                                ? (blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active)
                                : (root.player?.isPlaying
                                    ? (blendedColors?.colPrimaryActive ?? Appearance.colors.colPrimaryActive)
                                    : (blendedColors?.colSecondaryContainerActive ?? Appearance.colors.colSecondaryContainerActive))
                        onClicked: MprisController.togglePlaying()

                        Behavior on buttonRadius {
                            enabled: Appearance.animationsEnabled && !Appearance.alisEverywhere
                            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                        }

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.player?.isPlaying ? "pause" : "play_arrow"
                                iconSize: 24
                                fill: 1
                                color: Appearance.alisEverywhere
                                    ? root.jiraColPrimary
                                    : Appearance.auroraEverywhere
                                        ? (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                                        : (root.player?.isPlaying
                                            ? (blendedColors?.colOnPrimary ?? Appearance.colors.colOnPrimary)
                                            : (blendedColors?.colOnSecondaryContainer ?? Appearance.colors.colOnSecondaryContainer))

                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                }
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        enabled: MprisController.canGoNext
                        buttonRadius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover : ColorUtils.transparentize(blendedColors?.colLayer1 ?? Appearance.colors.colLayer1, 0.5)
                        colRipple: Appearance.alisEverywhere ? Appearance.alis.colLayer2Active : (blendedColors?.colLayer1Active ?? Appearance.colors.colLayer1Active)
                        onClicked: MprisController.next()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "skip_next"
                                iconSize: 22
                                fill: 1
                                color: Appearance.alisEverywhere ? root.jiraColText : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.effectiveLength)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: Appearance.alisEverywhere ? root.jiraColText : (blendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                    }
                }
            }
        }
    }

    Timer {
        running: root.presentationActive
            && root.player?.playbackState === MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }
}
