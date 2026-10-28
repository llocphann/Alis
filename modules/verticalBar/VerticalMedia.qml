import qs.modules.common
import qs.modules.common.widgets
import qs.modules.mediaControls
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

import qs.modules.bar as Bar

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    property bool edgeHostedExpansion: false
    readonly property string popupMode: edgeHostedExpansion ? "bar" : Config.options?.media?.popupMode ?? "dock"
    property bool barMediaPopupVisible: false

    Layout.fillHeight: true
    implicitHeight: mediaCircProg.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    Timer {
        running: root.visible
            && (root.QsWindow.window?.visible ?? false)
            && activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options?.resources?.updateInterval ?? 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: activePlayer?.positionChanged()
    }

    acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
    hoverEnabled: true
    onPressed: (event) => {
        if (event.button === Qt.MiddleButton) {
            MprisController.togglePlaying();
        } else if (event.button === Qt.BackButton) {
            MprisController.previous();
        } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
            MprisController.next();
        } else if (event.button === Qt.LeftButton) {
            if (root.popupMode === "bar") {
                root.barMediaPopupVisible = !root.barMediaPopupVisible
            } else {
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
    }

    ClippedFilledCircularProgress {
        id: mediaCircProg
        anchors.centerIn: parent
        implicitSize: Math.round(20 * Appearance.sizes.barModuleScale)

        lineWidth: Math.round(Appearance.rounding.unsharpen * Appearance.sizes.barModuleScale)
        readonly property real effectiveLength: MprisController.effectiveLengthForPlayer(activePlayer)
        readonly property real effectivePosition: MprisController.effectivePositionForPlayer(activePlayer, effectiveLength)
        value: effectiveLength > 0 ? Math.max(0, Math.min(1, effectivePosition / effectiveLength)) : 0
        colPrimary: Appearance.colors.colOnLayer0
        enableAnimation: false

        Item {
            anchors.centerIn: parent
            width: mediaCircProg.implicitSize
            height: mediaCircProg.implicitSize

            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: activePlayer?.isPlaying ? "pause" : "music_note"
                iconSize: Math.round(Appearance.font.pixelSize.normal * Appearance.sizes.barModuleScale)
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    // Expanded media controls use the same connected surface as Horizontal Bar.
    // StyledPopup owns output routing, outside-click catcher and keyboard focus.
    Bar.StyledPopup {
        id: barMediaPopup

        hoverTarget: root
        hoverActivates: true
        alternativeVisibleCondition:
            root.barMediaPopupVisible && root.popupMode === "bar"
        closeOnOutsideClick: root.barMediaPopupVisible
        keyboardFocus: root.barMediaPopupVisible
        // BarMediaPopup owns the tab rail inside playerViewport and reserves
        // horizontal space only when more than one media source is visible.
        // Do not add StyledPopup's legacy trailing background inset here: on a
        // single source it becomes an unnecessary right-side gap.
        popupBackgroundMargin: 0
        onRequestClose: root.barMediaPopupVisible = false

        function restoreInitialFocus(): void {
            Qt.callLater(() => {
                if (root.barMediaPopupVisible
                        && barMediaPopup.requestedVisible
                        && barMediaPopup.presentationWindow)
                    mediaPopupContent.focusInitialControl()
            })
        }

        onRequestedVisibleChanged: {
            if (requestedVisible)
                restoreInitialFocus()
        }
        onPresentationWindowChanged: {
            if (requestedVisible && presentationWindow)
                restoreInitialFocus()
        }

        BarMediaPopup {
            id: mediaPopupContent
            focus: true
            onCloseRequested: root.barMediaPopupVisible = false
        }
    }
}
