pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

Item {
    id: root
    objectName: "irisPrismHome"

    property var screen: null
    property bool railOpen: false
    property bool editingTiles: false

    signal areaSelected(int pageIndex)
    signal railToggleClicked()

    readonly property var brightnessMonitor: {
        void(Brightness.monitors)
        if (root.screen) {
            const matched = Brightness.getMonitorForScreen(root.screen)
            if (matched)
                return matched
        }
        return (Brightness.monitors?.length ?? 0) > 0 ? Brightness.monitors[0] : null
    }

    readonly property string greetingText: {
        const h = Number(DateTime.clock?.hours ?? 12)
        const base = h < 12
            ? Translation.tr("Good morning")
            : (h < 18 ? Translation.tr("Good afternoon") : Translation.tr("Good evening"))
        const user = String(SystemInfo.displayName || SystemInfo.username || "").trim()
        return user.length > 0 ? (base + ", " + user) : base
    }

    readonly property string wallpaperUrl: {
        const raw = String(Wallpapers.effectiveWallpaperUrl ?? "")
        if (!raw)
            return ""
        return raw.startsWith("/") ? ("file://" + raw) : raw
    }

    readonly property string wallpaperLabel: {
        const raw = String(Wallpapers.effectiveWallpaperPath ?? Wallpapers.effectiveWallpaperUrl ?? "")
        if (!raw)
            return Translation.tr("Active wallpaper")
        const parts = raw.split("/")
        return decodeURIComponent(parts[parts.length - 1] || raw)
    }

    readonly property var displayedTileIds: root.editingTiles
        ? IrisState.tileCatalogIds
        : IrisState.pinnedTileIds

    Flickable {
        id: homeFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentWrap.implicitHeight + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

        ColumnLayout {
            id: contentWrap
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Math.max(320, homeFlick.width - 40), IrisTheme.pageMaxWidth)
            spacing: 16

            // ── Top Greeting & Context Rail Toggle ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.greetingText
                        font.pixelSize: Appearance.font.pixelSize.larger + 2
                        font.weight: Font.Bold
                        color: IrisTheme.text
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: String(DateTime.time ?? "") + (DateTime.date ? (" · " + String(DateTime.date)) : "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.features: ({ "tnum": 1 })
                        color: IrisTheme.textMuted
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 30
                    height: 28
                    radius: 8
                    color: root.railOpen
                        ? IrisTheme.accentTint
                        : (homeRailBtnMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plate)
                    border.width: 1
                    border.color: root.railOpen ? IrisTheme.accentBorder : IrisTheme.hairline

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "dock_to_left"
                        iconSize: 16
                        color: root.railOpen ? IrisTheme.accent : IrisTheme.textMuted
                    }

                    MouseArea {
                        id: homeRailBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.railToggleClicked()
                    }

                    StyledToolTip {
                        extraVisibleCondition: homeRailBtnMouse.containsMouse
                        text: root.railOpen ? Translation.tr("Hide context rail") : Translation.tr("Show context rail")
                    }
                }
            }

            // ── 01 / 03 · Live Wallpaper Hero Card ──
            Rectangle {
                id: wpHeroCard
                objectName: "irisWallpaperHeroCard"
                Layout.fillWidth: true
                implicitHeight: Math.round(188 * IrisTheme.scale)
                radius: IrisTheme.radiusLarge
                color: IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline
                clip: true

                // Accent wash fallback when wallpaper image isn't loaded or uses solid color
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: IrisTheme.heroWashStart }
                        GradientStop { position: 0.55; color: IrisTheme.heroWashMid }
                        GradientStop { position: 1.0; color: IrisTheme.plate }
                    }
                }

                Image {
                    id: wpImage
                    anchors.fill: parent
                    source: root.wallpaperUrl
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(900, 320)
                    visible: status === Image.Ready
                }

                // Bottom readability scrim derived strictly from Appearance.colors.colLayer0
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.round(parent.height * 0.68)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(IrisTheme.panelBg, 0.0) }
                        GradientStop { position: 0.55; color: Qt.alpha(IrisTheme.panelBg, 0.62) }
                        GradientStop { position: 1.0; color: Qt.alpha(IrisTheme.panelBg, 0.92) }
                    }
                }

                // Top-left numbered badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 14
                    implicitWidth: wpBadgeRow.implicitWidth + 14
                    implicitHeight: Math.round(22 * IrisTheme.scale)
                    radius: Math.round(implicitHeight / 2)
                    color: Qt.alpha(IrisTheme.panelBg, 0.76)
                    border.width: 1
                    border.color: IrisTheme.hairline

                    Row {
                        id: wpBadgeRow
                        anchors.centerIn: parent
                        spacing: 6

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "01 / 03"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                            color: IrisTheme.accent
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Wallpaper")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: IrisTheme.text
                        }
                    }
                }

                // Bottom info + Change / Random action capsules
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 16
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.wallpaperLabel
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: IrisTheme.text
                            maximumLineCount: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: ((Appearance.m3colors?.darkmode ?? true) ? Translation.tr("Dark palette") : Translation.tr("Light palette"))
                                + " · " + String(Config.options?.appearance?.palette?.type ?? "auto")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: IrisTheme.textMuted
                        }
                    }

                    // Change Wallpaper primary pill
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: changeWpRow.implicitWidth + 20
                        implicitHeight: Math.round(34 * IrisTheme.scale)
                        radius: Math.round(implicitHeight / 2)
                        color: changeWpMouse.containsMouse ? Qt.lighter(IrisTheme.accent, 1.08) : IrisTheme.accent

                        Row {
                            id: changeWpRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "wallpaper"
                                iconSize: 16
                                color: IrisTheme.onAccent
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Change wallpaper")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: IrisTheme.onAccent
                            }
                        }

                        MouseArea {
                            id: changeWpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "ipc", "call", "wallpaperSelector", "toggle"])
                            }
                        }
                    }

                    // Random Wallpaper pill
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: randomWpRow.implicitWidth + 18
                        implicitHeight: Math.round(34 * IrisTheme.scale)
                        radius: Math.round(implicitHeight / 2)
                        color: randomWpMouse.containsMouse ? IrisTheme.plateHover : Qt.alpha(IrisTheme.panelBg, 0.82)
                        border.width: 1
                        border.color: IrisTheme.hairlineStrong

                        Row {
                            id: randomWpRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "shuffle"
                                iconSize: 16
                                color: IrisTheme.text
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Random")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: IrisTheme.text
                            }
                        }

                        MouseArea {
                            id: randomWpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpapers.randomFromCurrentFolder()
                        }
                    }
                }
            }

            // ── 02 / 03 · Sound & Light Inline Capsule Sliders ──
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: soundLightCol.implicitHeight + 28
                radius: IrisTheme.radiusCard
                color: IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                ColumnLayout {
                    id: soundLightCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    // Plate Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: slNum.implicitWidth + 12
                            implicitHeight: Math.round(20 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: IrisTheme.accentTint
                            border.width: 1
                            border.color: IrisTheme.accentBorder

                            StyledText {
                                id: slNum
                                anchors.centerIn: parent
                                text: "02 / 03"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                                color: IrisTheme.accent
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: Translation.tr("Sound & Light")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: IrisTheme.text
                        }

                        StyledText {
                            visible: Audio.sink !== null
                            Layout.maximumWidth: 220
                            text: Audio.friendlyDeviceName(Audio.sink)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: IrisTheme.textMuted
                            maximumLineCount: 1
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: IrisTheme.hairline
                    }

                    // Audio Output Capsule Slider Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: Math.round(34 * IrisTheme.scale)
                            height: Math.round(34 * IrisTheme.scale)
                            radius: Math.round(height / 2)
                            readonly property bool muted: Boolean(Audio.sink?.audio?.muted ?? false)
                            color: muted ? Qt.alpha(Appearance.colors.colError, 0.14) : IrisTheme.accentTint
                            border.width: 1
                            border.color: muted ? Qt.alpha(Appearance.colors.colError, 0.35) : IrisTheme.accentBorder

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: parent.muted
                                    ? "volume_off"
                                    : ((Audio.value ?? 0) > 0.5 ? "volume_up" : ((Audio.value ?? 0) > 0.01 ? "volume_down" : "volume_mute"))
                                iconSize: 18
                                color: parent.muted ? Appearance.colors.colError : IrisTheme.accent
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Audio.toggleMute()
                            }
                        }

                        // Capsule Track
                        Rectangle {
                            id: volTrack
                            Layout.fillWidth: true
                            height: Math.round(28 * IrisTheme.scale)
                            radius: Math.round(height / 2)
                            color: IrisTheme.plateRaised
                            border.width: 1
                            border.color: IrisTheme.hairline
                            clip: true

                            readonly property real ratio: Math.max(0, Math.min(1, Number(Audio.value ?? 0)))

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.round(parent.width * volTrack.ratio)
                                radius: parent.radius
                                color: Boolean(Audio.sink?.audio?.muted ?? false)
                                    ? Qt.alpha(IrisTheme.textMuted, 0.32)
                                    : Qt.alpha(IrisTheme.accent, 0.38)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function applyAt(mx: real): void {
                                    if (volTrack.width <= 0)
                                        return
                                    const next = Math.max(0, Math.min(1, mx / volTrack.width))
                                    Audio.setSinkVolume(next)
                                }
                                onPressed: mouse => applyAt(mouse.x)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        applyAt(mouse.x)
                                }
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: Math.round((Audio.value ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            font.features: ({ "tnum": 1 })
                            color: IrisTheme.text
                        }
                    }

                    // Display Brightness Capsule Slider Row (when monitor available)
                    RowLayout {
                        visible: root.brightnessMonitor !== null
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: Math.round(34 * IrisTheme.scale)
                            height: Math.round(34 * IrisTheme.scale)
                            radius: Math.round(height / 2)
                            color: IrisTheme.accentTint
                            border.width: 1
                            border.color: IrisTheme.accentBorder

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "brightness_medium"
                                iconSize: 18
                                color: IrisTheme.accent
                            }
                        }

                        Rectangle {
                            id: brightTrack
                            Layout.fillWidth: true
                            height: Math.round(28 * IrisTheme.scale)
                            radius: Math.round(height / 2)
                            color: IrisTheme.plateRaised
                            border.width: 1
                            border.color: IrisTheme.hairline
                            clip: true

                            readonly property real ratio: Math.max(0.02, Math.min(1, Number(root.brightnessMonitor?.brightness ?? 0.5)))

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.round(parent.width * brightTrack.ratio)
                                radius: parent.radius
                                color: Qt.alpha(IrisTheme.accent, 0.38)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function applyBrightness(mx: real): void {
                                    if (!root.brightnessMonitor || brightTrack.width <= 0)
                                        return
                                    const next = Math.max(0.05, Math.min(1, mx / brightTrack.width))
                                    root.brightnessMonitor.setBrightness(next)
                                }
                                onPressed: mouse => applyBrightness(mouse.x)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        applyBrightness(mouse.x)
                                }
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(Number(root.brightnessMonitor?.brightness ?? 0.5) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            font.features: ({ "tnum": 1 })
                            color: IrisTheme.text
                        }
                    }
                }
            }

            // ── 03 / 03 · Every Day Quick-Settings Tile Grid ──
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: everyDayCol.implicitHeight + 28
                radius: IrisTheme.radiusCard
                color: IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                ColumnLayout {
                    id: everyDayCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: edNum.implicitWidth + 12
                            implicitHeight: Math.round(20 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: IrisTheme.accentTint
                            border.width: 1
                            border.color: IrisTheme.accentBorder

                            StyledText {
                                id: edNum
                                anchors.centerIn: parent
                                text: "03 / 03"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                                color: IrisTheme.accent
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: Translation.tr("Every day")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: IrisTheme.text
                        }

                        // Reset button when editing tiles
                        Rectangle {
                            visible: root.editingTiles
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: resetTilesLbl.implicitWidth + 16
                            implicitHeight: Math.round(26 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: resetTilesMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plateRaised
                            border.width: 1
                            border.color: IrisTheme.hairline

                            StyledText {
                                id: resetTilesLbl
                                anchors.centerIn: parent
                                text: Translation.tr("Reset")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: IrisTheme.textSecondary
                            }

                            MouseArea {
                                id: resetTilesMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: IrisState.resetPinnedTiles()
                            }
                        }

                        // Edit / Done toggle button
                        Rectangle {
                            objectName: "irisEditQuickTilesButton"
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: editTilesRow.implicitWidth + 18
                            implicitHeight: Math.round(26 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: root.editingTiles
                                ? IrisTheme.accent
                                : (editTilesMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plateRaised)
                            border.width: 1
                            border.color: root.editingTiles ? IrisTheme.accent : IrisTheme.hairline

                            Row {
                                id: editTilesRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.editingTiles ? "check" : "edit"
                                    iconSize: 14
                                    color: root.editingTiles ? IrisTheme.onAccent : IrisTheme.textSecondary
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.editingTiles ? Translation.tr("Done") : Translation.tr("Edit")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    color: root.editingTiles ? IrisTheme.onAccent : IrisTheme.textSecondary
                                }
                            }

                            MouseArea {
                                id: editTilesMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editingTiles = !root.editingTiles
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: IrisTheme.hairline
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: contentWrap.width >= 600 ? 3 : 2
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: root.displayedTileIds

                            delegate: Rectangle {
                                id: quickTile
                                required property var modelData
                                readonly property string tileId: String(modelData)
                                readonly property var spec: IrisState.tileSpec(tileId)
                                readonly property bool pinned: IrisState.isTilePinned(tileId)
                                readonly property bool activeState: Boolean(spec?.active)

                                Layout.fillWidth: true
                                implicitHeight: Math.round(58 * IrisTheme.scale)
                                radius: IrisTheme.radiusSmall
                                opacity: root.editingTiles && !pinned ? 0.55 : 1.0
                                color: activeState
                                    ? (tileMouse.containsMouse ? IrisTheme.accentTintHover : IrisTheme.accentTint)
                                    : (tileMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plateRaised)
                                border.width: 1
                                border.color: activeState ? IrisTheme.accentBorder : IrisTheme.hairline

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        width: Math.round(34 * IrisTheme.scale)
                                        height: Math.round(34 * IrisTheme.scale)
                                        radius: Math.round(10 * IrisTheme.scale)
                                        color: quickTile.activeState ? IrisTheme.accent : IrisTheme.plate
                                        border.width: quickTile.activeState ? 0 : 1
                                        border.color: IrisTheme.hairline

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: String(quickTile.spec?.icon ?? "tune")
                                            fill: quickTile.activeState ? 1 : 0
                                            iconSize: 18
                                            color: quickTile.activeState ? IrisTheme.onAccent : IrisTheme.textMuted
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: String(quickTile.spec?.label ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: IrisTheme.text
                                            maximumLineCount: 1
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: root.editingTiles
                                                ? (quickTile.pinned ? Translation.tr("Pinned") : Translation.tr("Tap to pin"))
                                                : String(quickTile.spec?.subtitle ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: quickTile.activeState ? IrisTheme.accent : IrisTheme.textMuted
                                            maximumLineCount: 1
                                        }
                                    }

                                    MaterialSymbol {
                                        visible: root.editingTiles
                                        Layout.alignment: Qt.AlignVCenter
                                        text: quickTile.pinned ? "keep" : "add_circle"
                                        fill: quickTile.pinned ? 1 : 0
                                        iconSize: 16
                                        color: quickTile.pinned ? IrisTheme.accent : IrisTheme.textDim
                                    }
                                }

                                MouseArea {
                                    id: tileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.editingTiles)
                                            IrisState.togglePinTile(quickTile.tileId)
                                        else
                                            IrisState.triggerTile(quickTile.tileId)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Quick Area Jump Strip ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { key: Config.options?.panelFamily === "abyss" ? "abyss" : "bar", icon: "water" },
                        { key: "themes", icon: "palette" },
                        { key: "compositor", icon: "desktop_windows" },
                        { key: "system", icon: "browse" }
                    ]

                    delegate: Rectangle {
                        id: jumpChip
                        required property var modelData
                        readonly property int idx: SettingsPageRegistry.pageIndexForKey(String(modelData.key))
                        readonly property var pageObj: idx >= 0 ? SettingsPageRegistry.pages[idx] : null
                        visible: idx >= 0 && pageObj !== null
                        Layout.fillWidth: true
                        implicitHeight: Math.round(38 * IrisTheme.scale)
                        radius: IrisTheme.radiusSmall
                        color: jumpMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plate
                        border.width: 1
                        border.color: IrisTheme.hairline

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(jumpChip.pageObj?.icon ?? jumpChip.modelData.icon)
                                iconSize: 16
                                color: IrisTheme.accent
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(jumpChip.pageObj?.name ?? "")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: IrisTheme.text
                            }
                        }

                        MouseArea {
                            id: jumpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (jumpChip.idx >= 0)
                                    root.areaSelected(jumpChip.idx)
                            }
                        }
                    }
                }
            }
        }
    }

    IrisScrollEdge {
        flickable: homeFlick
        edge: "top"
        fadeColor: IrisTheme.panelBg
    }

    IrisScrollEdge {
        flickable: homeFlick
        edge: "bottom"
        fadeColor: IrisTheme.panelBg
    }
}
