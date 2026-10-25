import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.mediaControls

/**
 * Dashboard Media reuses the canonical PlayerControl transport/artwork/seek
 * surface and the shared EqualizerPanel. The media card intentionally does not
 * run a CAVA visualizer: DSP visualization already belongs to EqualizerPanel,
 * so the player surface stays quiet and avoids duplicate audio analysis.
 */
DashCard {
    id: root

    // Lifecycle is owned by DashboardContent/DashboardCanvas because this card
    // is hosted both by the standalone Dashboard and the embedded Overview.
    // Keep this writable: DashboardCanvas binds its host-specific presentation
    // state into every DashMedia instance.
    property bool presentationActive:
        GlobalStates.dashboardOpen || GlobalStates.overviewOpen

    // Both Dashboard pages use this exact card. The standard Dashboard binds
    // to the current MPRIS player; the Music page supplies LocalMusic plus its
    // existing adapter, so no second transport or DSP implementation is created.
    property var mediaBackend: null
    property var playbackAdapter: null
    property bool showEqualizer: true
    readonly property MprisPlayer player: mediaBackend
        ? (mediaBackend.mprisPlayer ?? null) : MprisController.activePlayer
    readonly property bool hasPlayer: playbackAdapter
        ? (Boolean(playbackAdapter.canSeek) || String(playbackAdapter.title ?? "").length > 0)
        : root.player !== null
    readonly property bool isPlaying: playbackAdapter
        ? Boolean(playbackAdapter.isPlaying) : (root.player?.isPlaying ?? false)

    implicitHeight: root.pad * 2
        + (root.hasPlayer ? Appearance.sizes.mediaControlsHeight : 112)
        + (volumeRow.visible ? mediaColumn.spacing + volumeRow.implicitHeight : 0)
        + (equalizer.visible ? mediaColumn.spacing + equalizer.implicitHeight : 0)

    ColumnLayout {
        id: mediaColumn
        Layout.fillWidth: true
        spacing: root.compact ? 4 : 6

        Item {
            id: playerSurface
            Layout.fillWidth: true
            Layout.minimumHeight: root.hasPlayer ? 120 : 104
            Layout.preferredHeight: root.hasPlayer
                ? Appearance.sizes.mediaControlsHeight : 112

            Loader {
                id: sharedPlayerLoader
                anchors.fill: parent
                // Keep the shared PlayerControl resident for the lifetime of
                // this Dashboard media card once a player exists. Recreating it
                // at every presentation resets ColorQuantizer/artwork masks
                // during the parent slide, which produced the cyan/blank flash.
                // Expensive CAVA/EasyEffects activity remains presentation-gated
                // below, so hidden residency does not keep those backends hot.
                active: root.hasPlayer
                sourceComponent: PlayerControl {
                    player: root.player
                    playbackAdapter: root.playbackAdapter
                    visualizerPoints: []
                    showVisualizer: false
                    compactLayout: true
                    radius: Appearance.rounding.normal
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 4
                visible: !root.hasPlayer

                MaterialShapeWrappedMaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 52
                    height: 52
                    text: "music_note"
                    shape: MaterialShape.Shape.Cookie4Sided
                    padding: 7
                    iconSize: 26
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Translation.tr("Nothing playing")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root.colText
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Translation.tr("No music is currently playing")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.colSubtext
                }
            }
        }

        // MPD volume is needed only in the Music-page instance; the Dashboard
        // card's original playback surface remains unchanged.
        RowLayout {
            id: volumeRow
            visible: root.mediaBackend !== null
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            spacing: 6
            MaterialSymbol {
                text: "volume_up"
                color: root.colSubtext
                iconSize: 18
            }
            StyledSlider {
                objectName: "musicVolume"
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.XS
                value: root.mediaBackend?.volume ?? 1
                onMoved: root.mediaBackend?.setVolume(value)
            }
        }

        EqualizerPanel {
            id: equalizer
            objectName: root.mediaBackend ? "musicEqualizer" : "dashboardMediaEqualizer"
            visible: root.showEqualizer
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            compactLayout: true
            active: root.showEqualizer && root.presentationActive && root.visible
        }
    }
}
