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
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    property bool borderless: Config.options?.bar?.borderless ?? false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property string fullTrackText: `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
    property bool edgeHostedExpansion: false
    readonly property string popupMode: edgeHostedExpansion ? "bar" : Config.options?.media?.popupMode ?? "dock"
    readonly property bool showVerboseLabel: Config.options?.bar?.verbose ?? true
    readonly property bool hasTrackMetadata: (activePlayer?.trackTitle?.length ?? 0) > 0
        || (activePlayer?.trackArtist?.length ?? 0) > 0
    readonly property bool lockMediaWidth: showVerboseLabel && hasTrackMetadata
    readonly property real mediaInset: Math.max(2, Math.round(4 * Appearance.sizes.barModuleScale))
    readonly property real mediaTextGap: Math.max(4, Math.round(7 * Appearance.sizes.barModuleScale))
    // The title scroller owns its own HoverHandler to pause the marquee, so the
    // legacy MouseArea does not report containsMouse over that child. Expose one
    // module-wide hover state for the connected Media popup instead.
    readonly property bool containsMouse:
        mediaInput.containsMouse || titleHoverHandler.hovered
    property int pendingTrackDirection: 0
    readonly property int effectiveTrackAnimationDirection: pendingTrackDirection !== 0 ? pendingTrackDirection : 1

    Layout.fillHeight: true
    // Keep the media footprint compact and user-controlled. A stable width
    // prevents track-length changes from resizing the center pill while the
    // marquee handles titles that exceed the configured space.
    readonly property real maxMediaWidth: {
        const configured = Number(Config.options?.bar?.media?.width ?? 180)
        return isFinite(configured)
            ? Math.max(120, Math.min(320, configured))
            : 180
    }
    implicitWidth: lockMediaWidth
        ? maxMediaWidth
        : Math.min(rowLayout.implicitWidth + root.mediaInset * 2, maxMediaWidth)
    implicitHeight: Appearance.sizes.barHeight
    clip: true

    Timer {
        running: root.visible
            && (root.QsWindow.window?.visible ?? false)
            && activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options?.resources?.updateInterval ?? 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: activePlayer?.positionChanged()
    }

    property bool barMediaPopupVisible: false

    // Expanded media controls use the same morphing surface as the small bar
    // popouts. Internal player cards stay intact, but the outer shell deforms
    // directly from the media module instead of opening a floating window/card.
    StyledPopup {
        id: barMediaPopup
        hoverTarget: root
        hoverActivates: true
        alternativeVisibleCondition: root.barMediaPopupVisible && root.popupMode === "bar"
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
            presentationActive: barMediaPopup.presentationActive
            onCloseRequested: root.barMediaPopupVisible = false
        }
    }

    MouseArea {
        id: mediaInput
        anchors.fill: parent
        // Hover alone reveals the Media popup; pointer shortcuts still control playback.
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton
        hoverEnabled: true

        Accessible.role: Accessible.Button
        Accessible.name: Translation.tr("Media controls")
        Accessible.focusable: true

        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                MprisController.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                root.pendingTrackDirection = -1
                MprisController.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                root.pendingTrackDirection = 1
                MprisController.next();
            }
        }
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: root.mediaTextGap
        anchors.fill: parent
        anchors.leftMargin: root.mediaInset
        anchors.rightMargin: root.mediaInset

        Item {
            id: compactMediaGlyph
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.round(22 * Appearance.sizes.barModuleScale)
            implicitHeight: implicitWidth

            ClippedFilledCircularProgress {
                id: mediaCircProg
                anchors.centerIn: parent
                lineWidth: Math.round(Appearance.rounding.unsharpen * Appearance.sizes.barModuleScale)
                readonly property real effectiveLength: MprisController.effectiveLengthForPlayer(activePlayer)
                readonly property real effectivePosition: MprisController.effectivePositionForPlayer(activePlayer, effectiveLength)
                value: effectiveLength > 0 ? Math.max(0, Math.min(1, effectivePosition / effectiveLength)) : 0
                implicitSize: Math.round(22 * Appearance.sizes.barModuleScale)
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
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }
                }
            }
        }

        Item {
            id: titleScroller
            visible: root.showVerboseLabel
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitWidth: titleText.implicitWidth
            implicitHeight: titleText.implicitHeight
            clip: true

            readonly property string fullText: root.fullTrackText
            readonly property bool overflowing: titleText.implicitWidth > width + 1
            // Short labels sit centered in the reserved Media label area. Long
            // labels still start at the leading edge so the marquee keeps the
            // same readable entry point and scrolling distance.
            readonly property real restingX: overflowing
                ? 0 : Math.max(0, (width - titleText.implicitWidth) / 2)
            // Continuous wraparound: scroll one text width + gap, then loop. The
            // trailing copy enters from the right exactly as the first exits left,
            // so it reads as a single seamless ribbon with no fade-snap.
            readonly property real gap: Math.round(28 * Appearance.sizes.barModuleScale)
            readonly property real loopDistance: titleText.implicitWidth + gap

            Row {
                id: marqueeRow
                height: parent.height
                spacing: titleScroller.gap
                x: titleScroller.restingX

                StyledText {
                    id: titleText
                    height: marqueeRow.height
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: titleScroller.overflowing
                        ? Text.AlignLeft : Text.AlignHCenter
                    font.pixelSize: Math.max(11, Math.round(Appearance.font.pixelSize.small * Appearance.sizes.barModuleScale))
                    width: implicitWidth
                    elide: Text.ElideNone
                    animateChange: true
                    animationDistanceX: root.effectiveTrackAnimationDirection * 10
                    animationDistanceY: 0
                    color: Appearance.colors.colOnLayer1
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    text: titleScroller.fullText
                    onTextChanged: {
                        root.pendingTrackDirection = 0
                        titleScroller.resetMarquee()
                    }
                }

                // Trailing copy — only present while scrolling, enters from the right.
                StyledText {
                    height: marqueeRow.height
                    verticalAlignment: Text.AlignVCenter
                    visible: titleScroller.overflowing
                    elide: Text.ElideNone
                    color: titleText.color
                    font: titleText.font
                    text: titleScroller.fullText
                }
            }

            // Pausable marquee: hold at start, then glide left continuously.
            // Hover pauses mid-scroll; on exit it resumes from the paused position.
            readonly property bool shouldAnimateMarquee: titleScroller.visible
                && (root.QsWindow.window?.visible ?? false)
                && titleScroller.overflowing
                && Appearance.animationsEnabled
                && (root.activePlayer?.isPlaying ?? false)
            property bool _marqueeHolding: true
            property bool _marqueeHovered: false
            property bool _marqueeReady: false
            Component.onCompleted: {
                _marqueeReady = true
                resetMarquee()
            }

            // Track/width/font changes must never leave a clipped mid-scroll
            // fragment beside the media icon. Restart at the first glyph.
            function resetMarquee() {
                if (!_marqueeReady) return
                holdTimer.stop()
                scrollAnim.stop()
                marqueeRow.x = titleScroller.restingX
                _marqueeHolding = true
                _startHoldTimer()
            }

            function _startHoldTimer() {
                if (!titleScroller.shouldAnimateMarquee || _marqueeHovered) return
                holdTimer.start()
            }

            Timer {
                id: holdTimer
                interval: 1800
                onTriggered: {
                    titleScroller._marqueeHolding = false
                    marqueeRow.x = 0
                    scrollAnim.start()
                }
            }

            NumberAnimation {
                id: scrollAnim
                target: marqueeRow; property: "x"
                from: 0
                to: -titleScroller.loopDistance
                duration: Math.max(3500, titleScroller.loopDistance * 42)
                easing.type: Easing.Linear
                // Gate on running — binding setPaused() on a stopped animation warns.
                paused: titleScroller._marqueeHovered && scrollAnim.running
                onFinished: {
                    marqueeRow.x = titleScroller.restingX
                    titleScroller._marqueeHolding = true
                    titleScroller._startHoldTimer()
                }
            }

            // The reserved label area can resize without changing the boolean
            // overflow state (e.g. via the Media width or Bar height sliders).
            onWidthChanged: resetMarquee()
            onOverflowingChanged: resetMarquee()
            onShouldAnimateMarqueeChanged: resetMarquee()

            onVisibleChanged: {
                if (!visible) {
                    holdTimer.stop()
                    scrollAnim.stop()
                    marqueeRow.x = titleScroller.restingX
                    _marqueeHolding = true
                } else if (overflowing && !_marqueeHovered) {
                    _startHoldTimer()
                }
            }

            HoverHandler {
                id: titleHoverHandler
                onHoveredChanged: {
                    titleScroller._marqueeHovered = hovered
                    if (hovered) {
                        holdTimer.stop()
                    } else {
                        if (titleScroller.overflowing && Appearance.animationsEnabled) {
                            if (titleScroller._marqueeHolding) {
                                titleScroller._startHoldTimer()
                            }
                            // NumberAnimation.paused is already false, so it resumes
                        }
                    }
                }
            }
        }

    }

}
