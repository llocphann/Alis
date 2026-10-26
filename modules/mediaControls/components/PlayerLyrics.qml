pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Item {
    id: root

    property color textColor: Appearance.zzzEverywhere ? Appearance.zzz.inkMuted : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colSubtext
    property color activeColor: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer0
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property int textAlignment: Text.AlignHCenter
    property int lineSpacing: 8

    property int baseSize: Appearance.font.pixelSize.normal
    property real activeScale: 1.18
    property int falloff: 4
    property bool showPlaceholder: true

    implicitWidth: 160
    implicitHeight: 72

    readonly property int activeIndex: LyricsService.activeIndex
    readonly property bool hasLyrics: LyricsService.status === "ok" && LyricsService.lyricsLines.length > 0

    property QtObject _lyricsLease: ServiceLease {
        active: root.visible
        acquire: () => {
            LyricsService.subscribe()
            return true
        }
        release: () => LyricsService.unsubscribe()
    }

    Item {
        id: placeholder
        anchors.fill: parent
        opacity: (root.hasLyrics || !root.showPlaceholder) ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        readonly property bool isLoading: LyricsService.status === "loading" || LyricsService.status === "idle"
        readonly property bool isNoTrack: LyricsService.status === "no_info"

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width, 260)
            spacing: 10

            LoadingText {
                Layout.alignment: Qt.AlignHCenter
                visible: placeholder.isLoading
                color: ColorUtils.applyAlpha(root.textColor, 0.85)
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                visible: !placeholder.isLoading
                text: placeholder.isNoTrack ? "music_off" : "lyrics"
                iconSize: 28
                color: ColorUtils.applyAlpha(root.textColor, 0.55)
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: ColorUtils.applyAlpha(root.textColor, 0.85)
                visible: !placeholder.isLoading
                text: placeholder.isNoTrack ? Translation.tr("Nothing playing")
                    : Translation.tr("No synced lyrics for this track")
            }
        }
    }

    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        opacity: root.hasLyrics ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Column {
            id: lyricColumn
            width: Math.floor(viewport.width / Math.max(1, root.activeScale))
            x: root.textAlignment === Text.AlignHCenter
                ? Math.round((viewport.width - width) / 2)
                : root.textAlignment === Text.AlignRight
                    ? viewport.width - width
                    : 0
            spacing: root.lineSpacing

            readonly property real targetY: {
                const count = lyricRepeater.count;
                if (count === 0)
                    return 0;
                const item = lyricRepeater.itemAt(Math.max(0, Math.min(root.activeIndex, count - 1)));
                if (!item)
                    return 0;
                return Math.round(viewport.height / 2 - (item.y + item.height / 2));
            }

            y: lyricColumn.targetY

            Behavior on y {
                enabled: Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Repeater {
                id: lyricRepeater
                model: LyricsService.lyricsLines

                delegate: WordSyncedLyricLine {
                    id: lyricLine
                    required property int index
                    required property var modelData

                    readonly property int distance: Math.abs(index - root.activeIndex)
                    readonly property bool isActive: index === root.activeIndex

                    width: lyricColumn.width
                    horizontalAlignment: root.textAlignment
                    lineData: modelData
                    nextLineTime: (index + 1 < LyricsService.lyricsLines.length)
                        ? Number(LyricsService.lyricsLines[index + 1]?.time ?? -1)
                        : -1
                    active: lyricLine.isActive
                    playing: root.visible && LyricsService.isPlaying
                    synced: true
                    position: Number(LyricsService.activePlayer?.position ?? LyricsService.anchorPos ?? 0)

                    fontPixelSize: root.baseSize
                    activeFontWeight: Font.DemiBold
                    inactiveFontWeight: Font.Medium
                    activeColor: root.activeColor
                    inactiveColor: root.textColor
                    accentColor: Appearance.colors.colPrimary

                    opacity: {
                        if (lyricLine.distance === 0)
                            return 1.0;
                        if (lyricLine.distance > root.falloff)
                            return 0.0;
                        return Math.max(0.06, 0.55 - (lyricLine.distance - 1) * 0.16);
                    }

                    transformOrigin: root.textAlignment === Text.AlignHCenter ? Item.Center
                        : root.textAlignment === Text.AlignRight ? Item.Right : Item.Left
                    scale: lyricLine.isActive ? root.activeScale : 1.0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        }
                    }
                }
            }
        }
    }
}
