pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root
    objectName: "irisPrismNowPlaying"

    readonly property var player: MprisController.activePlayer
    readonly property bool hasPlayer: root.player !== null
    readonly property bool isPlaying: Boolean(root.player?.isPlaying)
    readonly property string trackTitle: {
        const t = String(root.player?.trackTitle ?? "").trim()
        return t.length > 0 ? t : Translation.tr("Nothing playing")
    }
    readonly property string trackArtist: {
        const a = String(root.player?.trackArtist ?? "").trim()
        if (a.length > 0)
            return a
        return root.hasPlayer
            ? String(root.player?.identity ?? Translation.tr("Media ready"))
            : Translation.tr("Start audio in any media app")
    }
    readonly property string artUrl: String(root.player?.trackArtUrl ?? "")

    implicitHeight: npCol.implicitHeight + 24
    radius: IrisTheme.radiusCard
    color: IrisTheme.plate
    border.width: 1
    border.color: IrisTheme.hairline

    ColumnLayout {
        id: npCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "music_note"
                iconSize: 15
                color: root.isPlaying ? IrisTheme.accent : IrisTheme.textDim
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: Translation.tr("NOW PLAYING")
                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: IrisTheme.textDim
            }

            Rectangle {
                visible: root.isPlaying
                width: 7
                height: 7
                radius: 3.5
                color: IrisTheme.accent
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Track cover plate
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: Math.round(46 * IrisTheme.scale)
                height: Math.round(46 * IrisTheme.scale)
                radius: Math.round(10 * IrisTheme.scale)
                color: IrisTheme.plateRaised
                border.width: 1
                border.color: IrisTheme.hairline
                clip: true

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: coverImg.status !== Image.Ready
                    text: root.hasPlayer ? "album" : "headphones"
                    iconSize: 22
                    color: IrisTheme.textDim
                }

                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: root.artUrl
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(96, 96)
                    visible: status === Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.trackTitle
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: IrisTheme.text
                    maximumLineCount: 1
                    marquee: root.isPlaying
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.trackArtist
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: IrisTheme.textMuted
                    maximumLineCount: 1
                }
            }
        }

        // Transport controls
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            Rectangle {
                width: Math.round(32 * IrisTheme.scale)
                height: Math.round(32 * IrisTheme.scale)
                radius: Math.round(height / 2)
                opacity: root.hasPlayer ? 1.0 : 0.4
                color: prevMouse.containsMouse && root.hasPlayer ? IrisTheme.plateHover : IrisTheme.plateRaised
                border.width: 1
                border.color: IrisTheme.hairline

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    iconSize: 18
                    color: IrisTheme.text
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    enabled: root.hasPlayer
                    hoverEnabled: true
                    cursorShape: root.hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.player)
                            MprisController.previousForPlayer(root.player)
                    }
                }
            }

            Rectangle {
                width: Math.round(38 * IrisTheme.scale)
                height: Math.round(38 * IrisTheme.scale)
                radius: Math.round(height / 2)
                opacity: root.hasPlayer ? 1.0 : 0.4
                color: root.isPlaying
                    ? (playMouse.containsMouse ? Qt.lighter(IrisTheme.accent, 1.08) : IrisTheme.accent)
                    : (playMouse.containsMouse && root.hasPlayer ? IrisTheme.accentTintHover : IrisTheme.accentTint)
                border.width: root.isPlaying ? 0 : 1
                border.color: IrisTheme.accentBorder

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: 20
                    color: root.isPlaying ? IrisTheme.onAccent : IrisTheme.accent
                }

                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    enabled: root.hasPlayer
                    hoverEnabled: true
                    cursorShape: root.hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.player)
                            root.player.togglePlaying()
                    }
                }
            }

            Rectangle {
                width: Math.round(32 * IrisTheme.scale)
                height: Math.round(32 * IrisTheme.scale)
                radius: Math.round(height / 2)
                opacity: root.hasPlayer ? 1.0 : 0.4
                color: nextMouse.containsMouse && root.hasPlayer ? IrisTheme.plateHover : IrisTheme.plateRaised
                border.width: 1
                border.color: IrisTheme.hairline

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_next"
                    iconSize: 18
                    color: IrisTheme.text
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    enabled: root.hasPlayer
                    hoverEnabled: true
                    cursorShape: root.hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.player)
                            MprisController.nextForPlayer(root.player)
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
