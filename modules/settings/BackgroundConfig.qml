import qs
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    settingsPageIndex: 3
    settingsPageName: Translation.tr("Background")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    property string activeSection: "source"
    readonly property bool screensTaskActive: root.isIiActive
    readonly property real bottomBentoHeight: {
        const gap = SettingsMaterialPreset.pageSpacing
        const leftH = transitionsCard.naturalCardImplicitHeight + (multiMonCard.visible ? (gap + multiMonCard.naturalCardImplicitHeight) : 0)
        const rightH = sourceShuffleCard.naturalCardImplicitHeight
        return Math.max(leftH, rightH)
    }
    readonly property real targetScalingCardHeight: Math.max(
        420,
        SettingsMaterialPreset.standardBentoHeight - SettingsMaterialPreset.pageSpacing - root.bottomBentoHeight
    )

    onActiveSectionChanged: {
        if (activeSection === "effects" || activeSection === "motion" || activeSection === "screens")
            activeSection = "source"
    }

    SettingsTaskNavigator {
        visible: root.isIiActive
        showTabBar: false
        showIntro: false
        icon: "texture"
        title: Translation.tr("Wallpaper")
        description: Translation.tr("Wallpaper source, rotation, motion and effects.")
        summary: Translation.tr("Source & Transitions · Screens & Scaling · Effects & Backdrop")
        currentValue: "source"
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Wallpaper"), icon: "texture", value: "source" }
        ]
    }

    SettingsCardSection {
        visible: !root.isIiActive
        expanded: true
        icon: "info"
        title: Translation.tr("Waffle Mode")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Waffle: use Waffle Style for backgrounds. Backdrop applies to both.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

    GridLayout {
        id: wallpaperGrid
        Layout.fillWidth: true
        visible: children.length > 0
        columns: 1
        uniformCellWidths: false
        columnSpacing: 14
        rowSpacing: 14

SettingsCardSection {
    id: multiMonCard
    _declarationOrder: 2
    bentoColumn: "left"
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "source"
    visible: root.isIiActive
    expanded: true
    icon: "devices"
    title: Translation.tr("Multi-Monitor & Fullscreen")

    SettingsGroup {
        ConfigRow {
            uniform: true
            Layout.fillWidth: true

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                buttonIcon: "visibility_off"
                text: Translation.tr("Hide main wallpaper in fullscreen")
                checked: Config.options?.background?.hideWhenFullscreen ?? true
                onCheckedChanged: Config.setNestedValue("background.hideWhenFullscreen", checked)
                StyledToolTip {
                    text: Translation.tr("Hide the main wallpaper on monitors covered by a fullscreen window. The overview backdrop stays available.")
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                buttonIcon: "monitor"
                text: Translation.tr("Per-monitor wallpapers")
                checked: Config.options?.background?.multiMonitor?.enable ?? false
                onCheckedChanged: {
                    Config.setNestedValue("background.multiMonitor.enable", checked)
                    if (!checked) {
                        const globalPath = Config.options?.background?.wallpaperPath ?? ""
                        if (globalPath) {
                            Wallpapers.apply(globalPath, Appearance.m3colors.darkmode)
                        }
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Set a different wallpaper for each connected monitor")
                }
            }
        }
    }

    // Full multi-monitor management panel
    SettingsGroup {
        id: bgMultiMonPanel
        visible: Config.options?.background?.multiMonitor?.enable ?? false
        Layout.fillWidth: true

            property string selectedMonitor: {
                const primary = GlobalStates.primaryScreen
                const primaryName = primary ? (WallpaperListener.getMonitorName(primary) ?? "") : ""
                if (primaryName) return primaryName
                const focused = WallpaperListener.getFocusedMonitor()
                if (focused) return focused
                const screens = Quickshell.screens
                if (!screens || screens.length === 0) return ""
                return WallpaperListener.getMonitorName(screens[0]) ?? ""
            }

            readonly property var selMonData: WallpaperListener.effectivePerMonitor[selectedMonitor] ?? { path: "", isVideo: false, isGif: false, isAnimated: false, hasCustomWallpaper: false }
            readonly property string selMonPath: selMonData.path || (Config.options?.background?.wallpaperPath ?? "")
            property bool showBackdropView: false

            readonly property string backdropPath: {
                const bd = Config.options?.background?.backdrop ?? {}
                if (!(bd.useMainWallpaper ?? true) && bd.wallpaperPath) return bd.wallpaperPath
                return selMonPath
            }

            // Visual monitor layout
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                radius: Appearance.rounding.normal
                color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                     : Appearance.alisEverywhere ? Appearance.alis.colLayer0
                     : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                     : Appearance.colors.colLayer0
                border.width: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth
                    : Appearance.alisEverywhere ? 1 : (Appearance.auroraEverywhere ? 0 : 1)
                border.color: Appearance.angelEverywhere ? Appearance.angel.colCardBorder
                           : Appearance.alisEverywhere ? Appearance.alis.colBorder
                           : Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.centerIn: parent
                    anchors.margins: Appearance.sizes.spacingSmall
                    spacing: Appearance.sizes.spacingSmall
                    height: parent.height - 28

                    Repeater {
                        model: root.screensTaskActive ? Quickshell.screens : []

                        Item {
                            id: bgMonDelegate
                            required property var modelData
                            required property int index

                            readonly property string monName: WallpaperListener.getMonitorName(modelData) ?? ""
                            readonly property var wpData: WallpaperListener.effectivePerMonitor[monName] ?? { path: "" }
                            readonly property string wpPath: wpData.path || (Config.options?.background?.wallpaperPath ?? "")
                            readonly property bool isSelected: monName === bgMultiMonPanel.selectedMonitor
                            readonly property real aspectRatio: modelData.width / Math.max(1, modelData.height)
                            readonly property real cardHeight: parent.height - 16
                            readonly property real cardWidth: cardHeight * aspectRatio
                            readonly property real backdropOffset: 14

                            readonly property string backdropWpPath: {
                                const bd = Config.options?.background?.backdrop ?? {}
                                if (!(bd.useMainWallpaper ?? true) && bd.wallpaperPath) return bd.wallpaperPath
                                return wpPath
                            }

                            onWpPathChanged: if (root.screensTaskActive && WallpaperListener.isVideoPath(wpPath)) Wallpapers.ensureVideoFirstFrame(wpPath)
                            onBackdropWpPathChanged: if (root.screensTaskActive && WallpaperListener.isVideoPath(backdropWpPath)) Wallpapers.ensureVideoFirstFrame(backdropWpPath)

                            Layout.preferredWidth: cardWidth + backdropOffset + 4
                            Layout.preferredHeight: parent.height - 8
                            Layout.alignment: Qt.AlignVCenter

                            // --- Backdrop card (behind, offset to side) ---
                            Rectangle {
                                id: bgBackdropCard
                                x: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    ? 0 : bgMonDelegate.backdropOffset
                                y: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    ? 0 : 4
                                z: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected ? 2 : 0
                                width: bgMonDelegate.cardWidth
                                height: bgMonDelegate.cardHeight
                                radius: Appearance.rounding.small
                                color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                                     : Appearance.alisEverywhere ? Appearance.alis.colLayer1
                                     : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                                     : Appearance.colors.colLayer1
                                border.width: bgMonDelegate.isSelected && bgMultiMonPanel.showBackdropView
                                    ? (Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : Appearance.alisEverywhere ? 1 : 2) : (Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : Appearance.alisEverywhere ? 1 : 0)
                                border.color: bgMonDelegate.isSelected && bgMultiMonPanel.showBackdropView
                                    ? (Appearance.angelEverywhere ? Appearance.angel.colPrimary : Appearance.alisEverywhere ? Appearance.alis.colAccent : Appearance.colors.colPrimary)
                                    : (Appearance.angelEverywhere ? Appearance.angel.colCardBorder : Appearance.alisEverywhere ? Appearance.alis.colBorder : "transparent")
                                clip: true

                                layer.enabled: true
                                layer.smooth: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: bgBackdropCard.width
                                        height: bgBackdropCard.height
                                        radius: bgBackdropCard.radius
                                    }
                                }

                                opacity: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    ? 1.0
                                    : (bgBackdropMa.containsMouse ? 0.7 : 0.5)

                                Behavior on x { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                Behavior on y { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                Behavior on opacity { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                                StyledImage {
                                    visible: !WallpaperListener.isVideoPath(bgMonDelegate.backdropWpPath) && !WallpaperListener.isGifPath(bgMonDelegate.backdropWpPath)
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    fillMode: Image.PreserveAspectCrop
                                    source: root.screensTaskActive && !WallpaperListener.isVideoPath(bgMonDelegate.backdropWpPath) && !WallpaperListener.isGifPath(bgMonDelegate.backdropWpPath) ? (bgMonDelegate.backdropWpPath || "") : ""
                                    sourceSize.width: 200
                                    sourceSize.height: 200
                                    cache: true
                                }
                                AnimatedImage {
                                    visible: WallpaperListener.isGifPath(bgMonDelegate.backdropWpPath)
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    fillMode: Image.PreserveAspectCrop
                                    source: {
                                        if (!root.screensTaskActive) return ""
                                        if (!WallpaperListener.isGifPath(bgMonDelegate.backdropWpPath)) return ""
                                        const p = bgMonDelegate.backdropWpPath
                                        return p.startsWith("file://") ? p : "file://" + p
                                    }
                                    asynchronous: true
                                    cache: true
                                    playing: false
                                }
                                StyledImage {
                                    visible: WallpaperListener.isVideoPath(bgMonDelegate.backdropWpPath)
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    fillMode: Image.PreserveAspectCrop
                                    source: {
                                        if (!root.screensTaskActive) return ""
                                        const ff = Wallpapers.videoFirstFrames[bgMonDelegate.backdropWpPath]
                                        return ff ? (ff.startsWith("file://") ? ff : "file://" + ff) : ""
                                    }
                                    cache: true
                                    Component.onCompleted: {
                                        if (root.screensTaskActive && WallpaperListener.isVideoPath(bgMonDelegate.backdropWpPath))
                                            Wallpapers.ensureVideoFirstFrame(bgMonDelegate.backdropWpPath)
                                    }
                                }

                                // Dim overlay for back position
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: Qt.rgba(0, 0, 0, bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected ? 0 : 0.45)
                                    Behavior on color { enabled: Appearance.animationsEnabled; animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                }

                                // "Backdrop" label
                                Rectangle {
                                    visible: !(bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected)
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottomMargin: 3
                                    width: bgBackdropLabel.implicitWidth + 8
                                    height: 16
                                    radius: 8
                                    color: Qt.rgba(0, 0, 0, 0.7)
                                    StyledText {
                                        id: bgBackdropLabel
                                        anchors.centerIn: parent
                                        text: Translation.tr("Backdrop")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: "white"
                                    }
                                }

                                MouseArea {
                                    id: bgBackdropMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: {
                                        bgMultiMonPanel.selectedMonitor = bgMonDelegate.monName
                                        bgMultiMonPanel.showBackdropView = !bgMultiMonPanel.showBackdropView
                                    }
                                }

                                // Selection border overlay
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    visible: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    border.width: 2
                                    border.color: Appearance.alisEverywhere ? Appearance.alis.colAccent : Appearance.colors.colPrimary
                                }
                            }

                            // --- Main wallpaper card (front) ---
                            Rectangle {
                                id: bgMonCard
                                x: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    ? bgMonDelegate.backdropOffset : 0
                                y: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    ? 4 : 0
                                z: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected ? 0 : 2
                                width: bgMonDelegate.cardWidth
                                height: bgMonDelegate.cardHeight
                                radius: Appearance.rounding.small
                                color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                                     : Appearance.alisEverywhere ? Appearance.alis.colLayer1
                                     : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                                     : Appearance.colors.colLayer1
                                border.width: bgMonDelegate.isSelected && !bgMultiMonPanel.showBackdropView
                                    ? (Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : Appearance.alisEverywhere ? 1 : 2) : (Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : Appearance.alisEverywhere ? 1 : 0)
                                border.color: bgMonDelegate.isSelected && !bgMultiMonPanel.showBackdropView
                                    ? (Appearance.angelEverywhere ? Appearance.angel.colPrimary : Appearance.alisEverywhere ? Appearance.alis.colAccent : Appearance.colors.colPrimary)
                                    : (Appearance.angelEverywhere ? Appearance.angel.colCardBorder : Appearance.alisEverywhere ? Appearance.alis.colBorder : "transparent")
                                clip: true

                                layer.enabled: true
                                layer.smooth: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: bgMonCard.width
                                        height: bgMonCard.height
                                        radius: bgMonCard.radius
                                    }
                                }

                                opacity: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    ? (bgMonCardMa.containsMouse ? 0.7 : 0.5)
                                    : (bgMonDelegate.isSelected ? 1.0 : (bgMonCardMa.containsMouse ? 0.95 : 0.8))
                                scale: bgMonDelegate.isSelected && !bgMultiMonPanel.showBackdropView
                                    ? 1.0 : (bgMonCardMa.containsMouse ? 0.97 : 0.93)

                                Behavior on x { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                Behavior on y { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                Behavior on scale { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                Behavior on opacity { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                Behavior on border.width { enabled: Appearance.animationsEnabled; animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                                MouseArea {
                                    id: bgMonCardMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        bgMultiMonPanel.selectedMonitor = bgMonDelegate.monName
                                        if (mouse.button === Qt.RightButton) {
                                            bgMultiMonPanel.showBackdropView = !bgMultiMonPanel.showBackdropView
                                        } else {
                                            bgMultiMonPanel.showBackdropView = false
                                        }
                                    }
                                }

                                StyledImage {
                                    visible: !WallpaperListener.isVideoPath(bgMonDelegate.wpPath) && !WallpaperListener.isGifPath(bgMonDelegate.wpPath)
                                    anchors.fill: parent
                                    anchors.margins: bgMonCard.border.width
                                    fillMode: Image.PreserveAspectCrop
                                    source: root.screensTaskActive && !WallpaperListener.isVideoPath(bgMonDelegate.wpPath) && !WallpaperListener.isGifPath(bgMonDelegate.wpPath) ? (bgMonDelegate.wpPath || "") : ""
                                    sourceSize.width: 240
                                    sourceSize.height: 240
                                    cache: true
                                }
                                AnimatedImage {
                                    visible: WallpaperListener.isGifPath(bgMonDelegate.wpPath)
                                    anchors.fill: parent
                                    anchors.margins: bgMonCard.border.width
                                    fillMode: Image.PreserveAspectCrop
                                    source: {
                                        if (!root.screensTaskActive) return ""
                                        if (!WallpaperListener.isGifPath(bgMonDelegate.wpPath)) return ""
                                        const p = bgMonDelegate.wpPath
                                        return p.startsWith("file://") ? p : "file://" + p
                                    }
                                    asynchronous: true
                                    cache: true
                                    playing: false
                                }
                                StyledImage {
                                    visible: WallpaperListener.isVideoPath(bgMonDelegate.wpPath)
                                    anchors.fill: parent
                                    anchors.margins: bgMonCard.border.width
                                    fillMode: Image.PreserveAspectCrop
                                    source: {
                                        if (!root.screensTaskActive) return ""
                                        const ff = Wallpapers.videoFirstFrames[bgMonDelegate.wpPath]
                                        return ff ? (ff.startsWith("file://") ? ff : "file://" + ff) : ""
                                    }
                                    cache: true
                                    Component.onCompleted: {
                                        if (root.screensTaskActive && WallpaperListener.isVideoPath(bgMonDelegate.wpPath))
                                            Wallpapers.ensureVideoFirstFrame(bgMonDelegate.wpPath)
                                    }
                                }

                                // Dim overlay when in back position
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    visible: bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                }

                                // Label gradient overlay
                                Rectangle {
                                    visible: !(bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected)
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: Math.max(bgMonLabelCol.implicitHeight + 14, parent.height * 0.45)
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.35) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
                                    }

                                    ColumnLayout {
                                        id: bgMonLabelCol
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottomMargin: 5
                                        spacing: 1

                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: bgMonDelegate.monName || ("Monitor " + (bgMonDelegate.index + 1))
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: bgMonDelegate.modelData.width + "×" + bgMonDelegate.modelData.height
                                            font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                            color: Qt.rgba(1, 1, 1, 0.7)
                                        }
                                    }
                                }

                                // Media type badge
                                Rectangle {
                                    visible: WallpaperListener.isAnimatedPath(bgMonDelegate.wpPath)
                                        && !(bgMultiMonPanel.showBackdropView && bgMonDelegate.isSelected)
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 4
                                    width: bgMediaBadge.implicitWidth + 8
                                    height: 18
                                    radius: 9
                                    color: Qt.rgba(0, 0, 0, 0.75)
                                    Row {
                                        id: bgMediaBadge
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            text: WallpaperListener.isVideoPath(bgMonDelegate.wpPath) ? "movie" : "gif"
                                            font.pixelSize: 11
                                            color: Appearance.colors.colOnLayer0
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: WallpaperListener.mediaTypeLabel(bgMonDelegate.wpPath)
                                            font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                            color: Appearance.colors.colOnLayer0
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // Selected badge
                                Rectangle {
                                    visible: bgMonDelegate.isSelected && !bgMultiMonPanel.showBackdropView
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 5
                                    width: 20; height: 20
                                    radius: 10
                                    color: Appearance.colors.colPrimary
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "check"
                                        font.pixelSize: 13
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }

                                // Custom wallpaper indicator dot
                                Rectangle {
                                    visible: (bgMonDelegate.wpData.hasCustomWallpaper ?? false)
                                        && !bgMonDelegate.isSelected
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 7
                                    width: 8; height: 8
                                    radius: 4
                                    color: Appearance.colors.colTertiary
                                }
                            }
                        }
                    }
                }
            }

            // Unified preview + controls card
            Rectangle {
                id: bgMonPreviewCard
                Layout.fillWidth: true
                implicitHeight: bgMonPreviewCol.implicitHeight
                radius: Appearance.rounding.small
                color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                     : Appearance.alisEverywhere ? Appearance.alis.colLayer1
                     : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                     : Appearance.colors.colLayer1
                border.width: Appearance.angelEverywhere ? (Appearance.angel?.cardBorderWidth ?? 1) : 1
                border.color: Appearance.angelEverywhere ? (Appearance.angel?.colCardBorder ?? Appearance.colors.colLayer0Border)
                           : Appearance.alisEverywhere ? (Appearance.alis?.colBorder ?? Appearance.colors.colLayer0Border)
                           : Appearance.colors.colLayer0Border
                clip: true

                readonly property string _activePath: bgMultiMonPanel.showBackdropView
                    ? bgMultiMonPanel.backdropPath : bgMultiMonPanel.selMonPath
                readonly property string wpUrl: {
                    const path = _activePath
                    if (!path) return ""
                    return path.startsWith("file://") ? path : "file://" + path
                }
                readonly property bool isVideo: WallpaperListener.isVideoPath(_activePath)
                readonly property bool isGif: WallpaperListener.isGifPath(_activePath)

                on_ActivePathChanged: if (root.screensTaskActive && isVideo) Wallpapers.ensureVideoFirstFrame(_activePath)

                ColumnLayout {
                    id: bgMonPreviewCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 0

                    // Hero preview area — frozen first frame for videos/GIFs to save resources
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        clip: true

                        StyledImage {
                            id: bgMonPreviewImage
                            visible: !bgMonPreviewCard.isGif && !bgMonPreviewCard.isVideo
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: root.screensTaskActive && visible ? bgMonPreviewCard.wpUrl : ""
                            sourceSize.width: 600
                            sourceSize.height: 340
                            cache: false
                        }

                        AnimatedImage {
                            id: bgMonPreviewGif
                            visible: bgMonPreviewCard.isGif
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: root.screensTaskActive && visible ? bgMonPreviewCard.wpUrl : ""
                            asynchronous: true
                            cache: false
                            playing: false
                        }

                        StyledImage {
                            id: bgMonPreviewVideo
                            visible: bgMonPreviewCard.isVideo
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: {
                                if (!root.screensTaskActive) return ""
                                const ff = Wallpapers.videoFirstFrames[bgMonPreviewCard._activePath]
                                return ff ? (ff.startsWith("file://") ? ff : "file://" + ff) : ""
                            }
                            cache: false
                            Component.onCompleted: {
                                if (root.screensTaskActive && bgMonPreviewCard.isVideo)
                                    Wallpapers.ensureVideoFirstFrame(bgMonPreviewCard._activePath)
                            }
                        }

                        // Bottom gradient overlay with monitor info
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: parent.height * 0.55
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.4) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
                            }

                            RowLayout {
                                anchors {
                                    bottom: parent.bottom; left: parent.left; right: parent.right
                                    margins: 12; bottomMargin: 10
                                }
                                spacing: Appearance.sizes.spacingSmall

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    StyledText {
                                        text: bgMultiMonPanel.selectedMonitor || Translation.tr("No monitor selected")
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer0
                                    }
                                    StyledText {
                                        text: {
                                            if (bgMultiMonPanel.showBackdropView) return Translation.tr("Backdrop wallpaper")
                                            const custom = bgMultiMonPanel.selMonData.hasCustomWallpaper ?? false
                                            const animated = bgMultiMonPanel.selMonData.isAnimated ?? false
                                            let label = custom ? Translation.tr("Custom wallpaper") : Translation.tr("Global wallpaper")
                                            if (animated) label += " · " + WallpaperListener.mediaTypeLabel(bgMultiMonPanel.selMonPath)
                                            return label
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                        color: Qt.rgba(1, 1, 1, 0.7)
                                    }
                                }

                                // View mode pill
                                Rectangle {
                                    visible: bgMultiMonPanel.showBackdropView
                                    width: bgViewModePill.implicitWidth + 10
                                    height: 20
                                    radius: 10
                                    color: Appearance.colors.colSecondaryContainer
                                    Row {
                                        id: bgViewModePill
                                        anchors.centerIn: parent
                                        spacing: 3
                                        MaterialSymbol {
                                            text: "blur_on"
                                            font.pixelSize: 12
                                            color: Appearance.colors.colOnSecondaryContainer
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: Translation.tr("Backdrop")
                                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                            color: Appearance.colors.colOnSecondaryContainer
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: bgMultiMonPanel.showBackdropView = false
                                    }
                                }

                                // Media type badge
                                Rectangle {
                                    visible: !bgMultiMonPanel.showBackdropView && (bgMonPreviewCard.isVideo || bgMonPreviewCard.isGif)
                                    width: bgPreviewBadgeRow.implicitWidth + 10
                                    height: 20
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.15)
                                    Row {
                                        id: bgPreviewBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 3
                                        MaterialSymbol {
                                            text: WallpaperListener.mediaTypeIcon(bgMonPreviewCard._activePath)
                                            font.pixelSize: 12
                                            color: Appearance.colors.colOnLayer0
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: WallpaperListener.mediaTypeLabel(bgMonPreviewCard._activePath)
                                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                            color: Appearance.colors.colOnLayer0
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.alisEverywhere
                            ? (Appearance.alis?.colBorder
                                ?? Appearance.colors?.colLayer0Border
                                ?? Appearance.colors?.colLayer0Border
                                ?? Appearance.colors.colOutlineVariant)
                            : (Appearance.colors?.colLayer0Border
                                ?? Appearance.colors?.colLayer0Border
                                ?? Appearance.colors.colOutlineVariant)
                        opacity: 0.5
                    }

                    // Controls section
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: 12
                        Layout.topMargin: 10
                        Layout.bottomMargin: 12
                        spacing: Appearance.sizes.spacingSmall

                        // Wallpaper path
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            opacity: 0.7
                            text: {
                                const p = bgMultiMonPanel.showBackdropView
                                    ? bgMultiMonPanel.backdropPath : bgMultiMonPanel.selMonPath
                                return p ? FileUtils.trimFileProtocol(p) : Translation.tr("No wallpaper set")
                            }
                        }

                        // Primary actions: Change + Random (wallpaper mode)
                        RowLayout {
                            visible: !bgMultiMonPanel.showBackdropView
                            Layout.fillWidth: true
                            spacing: Appearance.sizes.spacingSmall

                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.small
                                materialIcon: "wallpaper"
                                mainText: Translation.tr("Change wallpaper")
                                colBackground: Appearance.zzzEverywhere ? Appearance.zzz.sticker : Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
                                colRipple: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainerActive
                                mainContentComponent: Component {
                                    StyledText {
                                        text: Translation.tr("Change wallpaper")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnPrimaryContainer
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                        }
                                    }
                                }
                                onClicked: {
                                    const mon = bgMultiMonPanel.selectedMonitor
                                    if (mon) {
                                        Config.setNestedValue("wallpaperSelector.selectionTarget", "main")
                                        Config.setNestedValue("wallpaperSelector.targetMonitor", mon)
                                        Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "wallpaperSelector", "toggle"])
                                    }
                                }
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.small
                                materialIcon: "shuffle"
                                mainText: Translation.tr("Random")
                                onClicked: {
                                    const mon = bgMultiMonPanel.selectedMonitor
                                    if (mon) {
                                        Wallpapers.randomFromCurrentFolder(Appearance.m3colors.darkmode, mon)
                                    }
                                }
                                StyledToolTip {
                                    text: Translation.tr("Set a random wallpaper from the current folder for this monitor")
                                }
                            }
                        }

                        // Primary actions: Change backdrop (backdrop mode)
                        RowLayout {
                            visible: bgMultiMonPanel.showBackdropView
                            Layout.fillWidth: true
                            spacing: Appearance.sizes.spacingSmall

                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.rounding.small
                                materialIcon: "blur_on"
                                mainText: Translation.tr("Change backdrop")
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.15)
                                colRipple: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.3)
                                mainContentComponent: Component {
                                    StyledText {
                                        text: Translation.tr("Change backdrop")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                                onClicked: {
                                    Config.setNestedValue("wallpaperSelector.selectionTarget", "backdrop")
                                    Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "wallpaperSelector", "toggle"])
                                }
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.rounding.small
                                materialIcon: "arrow_back"
                                mainText: Translation.tr("Back to wallpaper")
                                onClicked: bgMultiMonPanel.showBackdropView = false
                            }
                        }

                        // Secondary actions: Reset + Apply all (wallpaper mode only)
                        RowLayout {
                            visible: !bgMultiMonPanel.showBackdropView
                            Layout.fillWidth: true
                            spacing: Appearance.sizes.spacingSmall

                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.rounding.small
                                materialIcon: "restart_alt"
                                mainText: Translation.tr("Reset to global")
                                onClicked: {
                                    const mon = bgMultiMonPanel.selectedMonitor
                                    if (!mon) return
                                    const globalPath = Config.options?.background?.wallpaperPath ?? ""
                                    if (globalPath) {
                                        Wallpapers.select(globalPath, Appearance.m3colors.darkmode, mon)
                                    }
                                }
                                StyledToolTip {
                                    text: Translation.tr("Reset this monitor to use the global wallpaper")
                                }
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.rounding.small
                                materialIcon: "select_all"
                                mainText: Translation.tr("Apply to all")
                                onClicked: {
                                    const globalPath = Config.options?.background?.wallpaperPath ?? ""
                                    if (globalPath) {
                                        Wallpapers.apply(globalPath, Appearance.m3colors.darkmode)
                                    }
                                }
                                StyledToolTip {
                                    text: Translation.tr("Apply the global wallpaper to all monitors")
                                }
                            }
                        }

                        // Backdrop shortcut (wallpaper mode only)
                        RippleButtonWithIcon {
                            Layout.fillWidth: true
                            buttonRadius: Appearance.rounding.small
                            materialIcon: "blur_on"
                            mainText: Translation.tr("View backdrop")
                            visible: !bgMultiMonPanel.showBackdropView && (Config.options?.background?.backdrop?.enable ?? true)
                            onClicked: bgMultiMonPanel.showBackdropView = true
                            StyledToolTip {
                                text: Translation.tr("Change the backdrop wallpaper (used for overview/blur)")
                            }
                        }

                        // Derive theme colors from backdrop
                        ConfigSwitch {
                            visible: Config.options?.background?.backdrop?.enable ?? true
                            buttonIcon: "palette"
                            text: Translation.tr("Derive theme colors from backdrop")
                            checked: Config.options?.appearance?.wallpaperTheming?.useBackdropForColors ?? false
                            onCheckedChanged: {
                                Config.setNestedValue("appearance.wallpaperTheming.useBackdropForColors", checked)
                                // Regenerate on both ON and OFF when backdrop has a custom wallpaper
                                if (!(Config.options?.background?.backdrop?.useMainWallpaper ?? true)) {
                                    Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"])
                                }
                            }
                        }
                    }
                }
            }

            // Info bar
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 4
                MaterialSymbol {
                    text: "info"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.6
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    color: Appearance.colors.colSubtext
                    opacity: 0.6
                    text: Translation.tr("%1 monitors detected").arg(WallpaperListener.screenCount) + "  ·  " + Translation.tr("Ctrl+Alt+T targets focused output")
                    wrapMode: Text.WordWrap
                }
            }
    }
}

SettingsCardSection {
    id: sourceShuffleCard
    _declarationOrder: 3
    bentoColumn: "right"
    _consumesBentoExtraHeight: !bgMultiMonPanel.visible
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "source"
    visible: true
    expanded: true
    icon: "folder"
    title: Translation.tr("Wallpaper Source & Shuffle")

    SettingsGroup {
        Layout.fillHeight: true
        ContentSubsection {
            Layout.topMargin: 0
            title: Translation.tr("Custom wallpapers directory")
            tooltip: Translation.tr("Leave empty for default ~/Pictures/Wallpapers")

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: "~/Pictures/Wallpapers"
                text: Config.options?.wallpapers?.directory ?? ""
                onEditingFinished: Config.setNestedValue("wallpapers.directory", text)
            }
        }

        SettingsSwitch {
            buttonIcon: "autorenew"
            text: Translation.tr("Shuffle wallpapers automatically")
            checked: Config.options?.background?.autoWallpaper?.enable ?? false
            onCheckedChanged: Config.setNestedValue("background.autoWallpaper.enable", checked)
        }

        ConfigSpinBox {
            enabled: Config.options?.background?.autoWallpaper?.enable ?? false
            icon: "timer"
            text: Translation.tr("Change every (min)")
            value: Config.options?.background?.autoWallpaper?.intervalMinutes ?? 30
            from: 1
            to: 1440
            stepSize: 1
            onValueChanged: Config.setNestedValue("background.autoWallpaper.intervalMinutes", value)
        }

        SettingsSwitch {
            enabled: Config.options?.background?.autoWallpaper?.enable ?? false
            buttonIcon: "palette"
            text: Translation.tr("Regenerate theme colors on shuffle")
            checked: Config.options?.background?.autoWallpaper?.generateColors ?? true
            onCheckedChanged: Config.setNestedValue("background.autoWallpaper.generateColors", checked)
        }

        ContentSubsection {
            Layout.topMargin: 0
            title: Translation.tr("Shuffle folder (optional)")

            MaterialTextField {
                Layout.fillWidth: true
                enabled: Config.options?.background?.autoWallpaper?.enable ?? false
                placeholderText: Translation.tr("Use current wallpapers folder")
                text: Config.options?.background?.autoWallpaper?.folder ?? ""
                onEditingFinished: Config.setNestedValue("background.autoWallpaper.folder", text)
            }
        }
    }
}

SettingsCardSection {
    id: transitionsCard
    _declarationOrder: 1
    bentoColumn: "left"
    _consumesBentoExtraHeight: !bgMultiMonPanel.visible
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "source"
    visible: root.isIiActive
    expanded: true
    icon: "transition_fade"
    title: Translation.tr("Wallpaper Transitions")

    SettingsGroup {
        Layout.fillHeight: true
        ConfigRow {
            uniform: true
            Layout.fillWidth: true

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                buttonIcon: "animation"
                text: Translation.tr("Enable wallpaper transitions")
                checked: Config.options?.background?.transition?.enable ?? true
                onCheckedChanged: {
                    Config.setNestedValue("background.transition.enable", checked);
                }
                StyledToolTip {
                    text: Translation.tr("Smoothly transition between wallpapers when changing them")
                }
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                enabled: {
                    if (!(Config.options?.background?.transition?.enable ?? true))
                        return false
                    const t = AwwwBackend.normalizedAwwwTransitionType(
                        Config.options?.background?.transition?.type ?? "crossfade",
                        Config.options?.background?.transition?.direction ?? "right"
                    )
                    return t !== "simple" && t !== "none"
                }
                icon: "timer"
                text: Translation.tr("Transition duration (ms)")
                value: Config.options?.background?.transition?.duration ?? 800
                from: 200
                to: 3000
                stepSize: 100
                onValueChanged: {
                    Config.setNestedValue("background.transition.duration", value);
                }
                StyledToolTip {
                    text: Translation.tr("How long the transition takes in milliseconds. Ignored for 'Simple' and 'None' modes.")
                }
            }
        }

        ContentSubsection {
            visible: Config.options?.background?.transition?.enable ?? true
            title: Translation.tr("Transition style")

            ConfigSelectionArray {
                currentValue: ["alisMelt"].includes(Config.options?.background?.transition?.type) ? "alisMelt"
                    : AwwwBackend.normalizedAwwwTransitionType(Config.options?.background?.transition?.type ?? "alisMelt",Config.options?.background?.transition?.direction ?? "right")
                onSelected: newValue => {
                    Config.setNestedValue("background.transition.type", newValue);
                }
                options: [
                    { displayName:Translation.tr("Liquid"),icon:"water",value:"alisMelt" },
                    { displayName: Translation.tr("Fade"), icon: "motion_photos_on", value: "fade" },
                    { displayName: Translation.tr("From left"), icon: "west", value: "left" },
                    { displayName: Translation.tr("From right"), icon: "east", value: "right" },
                    { displayName: Translation.tr("From top"), icon: "north", value: "top" },
                    { displayName: Translation.tr("From bottom"), icon: "south", value: "bottom" },
                    { displayName: Translation.tr("Wipe"), icon: "left_panel_open", value: "wipe" },
                    { displayName: Translation.tr("Grow"), icon: "filter_center_focus", value: "grow" },
                    { displayName: Translation.tr("Center"), icon: "center_focus_strong", value: "center" },
                    { displayName: Translation.tr("Any"), icon: "shuffle", value: "any" },
                    { displayName: Translation.tr("Outer"), icon: "blur_circular", value: "outer" },
                    { displayName: Translation.tr("Random"), icon: "casino", value: "random" }
                ]
            }
        }

        ContentSubsection {
            visible: {
                if (!(Config.options?.background?.transition?.enable ?? true))
                    return false
                const t = AwwwBackend.normalizedAwwwTransitionType(
                    Config.options?.background?.transition?.type ?? "crossfade",
                    Config.options?.background?.transition?.direction ?? "right"
                )
                return ["wipe", "wave"].indexOf(t) >= 0
            }
            title: Translation.tr("Transition direction")

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                text: Translation.tr("Choose wallpaper reveal direction.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                opacity: 0.8
                wrapMode: Text.WordWrap
            }

            ConfigSelectionArray {
                currentValue: Config.options?.background?.transition?.direction ?? "right"
                onSelected: newValue => {
                    Config.setNestedValue("background.transition.direction", newValue);
                }
                options: [
                    { displayName: Translation.tr("From left"), icon: "west", value: "left" },
                    { displayName: Translation.tr("From right"), icon: "east", value: "right" },
                    { displayName: Translation.tr("From top"), icon: "north", value: "top" },
                    { displayName: Translation.tr("From bottom"), icon: "south", value: "bottom" }
                ]
            }
        }
    }
}

SettingsCardSection {
    id: scalingCard
    _declarationOrder: 0
    bentoColumn: "full"
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "source"
    visible: root.isIiActive
    expanded: true
    icon: "aspect_ratio"
    title: Translation.tr("Wallpaper scaling")

    SettingsGroup {
        id: scalingGroup

        RowLayout {
            id: scalingSplitRow
            Layout.fillWidth: true
            spacing: 14

            // Left column: Settings controls
            ColumnLayout {
                id: scalingSettingsColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 32
                Layout.maximumWidth: 340
                Layout.alignment: Qt.AlignTop
                spacing: SettingsMaterialPreset.groupSpacing

                ContentSubsection {
                    title: Translation.tr("Fill crops, Fit shows bars")
                    ConfigSelectionArray {
                        currentValue: Config.options?.background?.fillMode ?? "fill"
                        onSelected: newValue => {
                            Config.setNestedValue("background.fillMode", newValue);
                        }
                        options: [
                            { displayName: Translation.tr("Fill"), icon: "crop", value: "fill" },
                            { displayName: Translation.tr("Fit"), icon: "fit_screen", value: "fit" },
                            { displayName: Translation.tr("Center"), icon: "center_focus_strong", value: "center" }
                        ]
                    }
                }

                SettingsDivider {}

                SettingsSwitch {
                    buttonIcon: "play_circle"
                    text: Translation.tr("Enable animated wallpapers (videos/GIFs)")
                    checked: Config.options?.background?.enableAnimation ?? true
                    onCheckedChanged: {
                        Config.setNestedValue("background.enableAnimation", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Play videos and GIFs as wallpaper. When disabled, shows a frozen frame (better performance)")
                    }
                }

                SettingsSwitch {
                    visible: Config.options?.background?.enableAnimation ?? true
                    buttonIcon: "battery_saver"
                    text: Translation.tr("Pause animated wallpapers on battery")
                    checked: Config.options?.background?.pauseAnimationOnBattery ?? true
                    onCheckedChanged: {
                        Config.setNestedValue("background.pauseAnimationOnBattery", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Freeze videos and GIFs while on battery power to save energy")
                    }
                }

                SettingsSwitch {
                    visible: Config.options?.background?.enableAnimation ?? true
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur animated wallpapers (videos/GIFs)")
                    checked: Config.options?.background?.effects?.enableAnimatedBlur ?? false
                    onCheckedChanged: {
                        Config.setNestedValue("background.effects.enableAnimatedBlur", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Blur video/GIF wallpapers; may increase GPU load.")
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // Right column: Pan + Zoom preview card
            Rectangle {
                id: panCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 68
                Layout.alignment: Qt.AlignTop
                visible: true

                readonly property var _screen: GlobalStates.primaryScreen ?? Quickshell.screens[0] ?? null
                readonly property real screenAspect: _screen ? (_screen.width / Math.max(1, _screen.height)) : (16 / 9)
                readonly property bool isFillMode: (Config.options?.background?.fillMode ?? "fill") === "fill"
                readonly property real currentPanX: Config.options?.background?.pan?.x ?? 0.0
                readonly property real currentPanY: Config.options?.background?.pan?.y ?? 0.0
                readonly property real currentPanZoom: Math.max(1.0, Math.min(3.0, Config.options?.background?.pan?.zoom ?? 1.0))
                readonly property bool hasPan: currentPanX !== 0.0 || currentPanY !== 0.0 || currentPanZoom !== 1.0
                readonly property real targetInnerHeight: Math.max(
                    scalingSettingsColumn.implicitHeight,
                    root.targetScalingCardHeight - scalingCard.chromeImplicitHeight - SettingsMaterialPreset.groupPadding * 2
                )
                readonly property real targetViewportHeight: Math.max(
                    76,
                    targetInnerHeight - panHeaderRow.implicitHeight - panZoomRow.implicitHeight - panCardContent.spacing * 2 - 16
                )

                implicitHeight: targetInnerHeight
                Layout.minimumHeight: targetInnerHeight
                Layout.preferredHeight: targetInnerHeight
                Layout.maximumHeight: targetInnerHeight
                radius: SettingsMaterialPreset.cardRadius
                color: SettingsMaterialPreset.cardColor
                border.width: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : 1
                border.color: SettingsMaterialPreset.cardBorderColor
                clip: true

                ColumnLayout {
                    id: panCardContent
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Header row
                    RowLayout {
                        id: panHeaderRow
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "open_with"
                            iconSize: 16
                            color: Appearance.alisEverywhere ? Appearance.alis.colPrimary
                                 : Appearance.auroraEverywhere ? Appearance.colors.colPrimary
                                 : Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("Wallpaper position")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.alisEverywhere ? Appearance.alis.colText
                                 : Appearance.auroraEverywhere ? Appearance.colors.colOnSurface
                                 : Appearance.colors.colOnLayer1
                        }

                        MaterialSymbol {
                            text: "info"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                            MouseArea {
                                id: panInfoMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.WhatsThisCursor
                                StyledToolTip {
                                    extraVisibleCondition: false
                                    alternativeVisibleCondition: panInfoMouseArea.containsMouse
                                    text: Translation.tr("Drag to reposition, scroll to zoom.\nWhen repositioned or zoomed, the shell renders the wallpaper internally.")
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: {
                                if (!panCard.hasPan) return Translation.tr("Centered, no zoom")
                                const parts = []
                                const x = Math.round(panCard.currentPanX * 100)
                                const y = Math.round(panCard.currentPanY * 100)
                                if (panCard.currentPanX !== 0.0 || panCard.currentPanY !== 0.0)
                                    parts.push(Translation.tr("%1%, %2%").arg(x).arg(y))
                                if (panCard.currentPanZoom !== 1.0)
                                    parts.push(panCard.currentPanZoom.toFixed(1) + "×")
                                return parts.join(" · ")
                            }
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        RippleButton {
                            visible: panCard.hasPan
                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                                : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover
                                : Appearance.colors.colLayer2Hover
                            onClicked: {
                                Config.setNestedValue("background.pan.x", 0)
                                Config.setNestedValue("background.pan.y", 0)
                                Config.setNestedValue("background.pan.zoom", 1.0)
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "restart_alt"
                                iconSize: 14
                                color: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
                                     : Appearance.auroraEverywhere ? Appearance.colors.colOnSurfaceVariant
                                     : Appearance.colors.colSubtext
                            }
                            StyledToolTip { text: Translation.tr("Reset position and zoom") }
                        }
                    }

                    // Wallpaper preview viewport — compact height so page matches Themes & Style / Custom Theme
                    Rectangle {
                        id: panViewport
                        Layout.fillWidth: true
                        implicitHeight: panCard.targetViewportHeight
                        Layout.minimumHeight: implicitHeight
                        Layout.preferredHeight: implicitHeight
                        Layout.maximumHeight: implicitHeight
                        radius: SettingsMaterialPreset.groupRadius
                        color: Appearance.colors.colLayer0
                        clip: true
                        border.width: panDragArea.drag.active ? 2 : 0
                        border.color: Appearance.colors.colPrimary

                        Behavior on border.width {
                            enabled: Appearance.animationsEnabled
                            animation: NumberAnimation { duration: 120 }
                        }

                        // Wallpaper image — Image.Stretch so zoom actually scales pixels
                        StyledImage {
                            id: panWallpaperImage
                            readonly property string wpPath: {
                                if (WallpaperListener.multiMonitorEnabled && panCard._screen) {
                                    const _monName = WallpaperListener.getMonitorName(panCard._screen)
                                    const _monData = WallpaperListener.effectivePerMonitor[_monName]
                                    if (_monData && _monData.path) return _monData.path
                                }
                                return Config.options?.background?.wallpaperPath ?? ""
                            }
                            readonly property bool isVideo: WallpaperListener.isVideoPath(wpPath)
                            readonly property string previewPath: isVideo
                                ? Wallpapers.getVideoFirstFramePath(wpPath) : wpPath
                            source: root.screensTaskActive && previewPath
                                ? (previewPath.startsWith("file://") ? previewPath : "file://" + previewPath)
                                : ""
                            sourceSize.width: 1200
                            cache: false
                            fillMode: Image.Stretch
                            visible: status === Image.Ready

                            Component.onCompleted: {
                                if (root.screensTaskActive && isVideo)
                                    Wallpapers.ensureVideoFirstFrame(wpPath)
                            }
                            onWpPathChanged: {
                                if (root.screensTaskActive && isVideo)
                                    Wallpapers.ensureVideoFirstFrame(wpPath)
                            }

                            readonly property real imgNatW: implicitWidth > 0 ? implicitWidth : 1
                            readonly property real imgNatH: implicitHeight > 0 ? implicitHeight : 1
                            readonly property real scaleToFill: Math.max(
                                panViewport.width / imgNatW,
                                panViewport.height / imgNatH
                            ) * panCard.currentPanZoom
                            readonly property real scaledW: imgNatW * scaleToFill
                            readonly property real scaledH: imgNatH * scaleToFill
                            readonly property real excessX: Math.max(0, scaledW - panViewport.width)
                            readonly property real excessY: Math.max(0, scaledH - panViewport.height)

                            width: scaledW
                            height: scaledH

                            readonly property real restX: -(excessX / 2) + (panCard.currentPanX * excessX / 2)
                            readonly property real restY: -(excessY / 2) + (panCard.currentPanY * excessY / 2)

                            x: panDragArea.drag.active ? x : restX
                            y: panDragArea.drag.active ? y : restY

                            Behavior on x {
                                enabled: Appearance.animationsEnabled && !panDragArea.drag.active
                                animation: NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                enabled: Appearance.animationsEnabled && !panDragArea.drag.active
                                animation: NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on width {
                                enabled: Appearance.animationsEnabled && !panDragArea.drag.active
                                animation: NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }
                            Behavior on height {
                                enabled: Appearance.animationsEnabled && !panDragArea.drag.active
                                animation: NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: !panWallpaperImage.visible
                            text: Translation.tr("No wallpaper")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        MouseArea {
                            id: panDragArea
                            anchors.fill: parent
                            drag.target: panWallpaperImage
                            drag.axis: Drag.XAndYAxis
                            drag.minimumX: -(panWallpaperImage.excessX)
                            drag.maximumX: 0
                            drag.minimumY: -(panWallpaperImage.excessY)
                            drag.maximumY: 0
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            enabled: panWallpaperImage.visible && panCard.isFillMode
                            scrollGestureEnabled: false

                            onReleased: {
                                if (!panWallpaperImage.visible) return
                                const ex = panWallpaperImage.excessX
                                const ey = panWallpaperImage.excessY
                                const newPanX = ex > 0 ? Math.max(-1, Math.min(1, (panWallpaperImage.x + ex / 2) / (ex / 2))) : 0
                                const newPanY = ey > 0 ? Math.max(-1, Math.min(1, (panWallpaperImage.y + ey / 2) / (ey / 2))) : 0
                                Config.setNestedValue("background.pan.x", Math.round(newPanX * 100) / 100)
                                Config.setNestedValue("background.pan.y", Math.round(newPanY * 100) / 100)
                            }

                            onWheel: wheel => {
                                if (!panCard.isFillMode) return
                                const delta = wheel.angleDelta.y / 120
                                const newZoom = Math.max(1.0, Math.min(3.0, Math.round((panCard.currentPanZoom + delta * 0.1) * 100) / 100))
                                Config.setNestedValue("background.pan.zoom", newZoom)
                            }
                        }

                        // Zoom badge (top-right corner)
                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 8 }
                            width: zoomBadgeLabel.implicitWidth + 12
                            height: zoomBadgeLabel.implicitHeight + 6
                            radius: SettingsMaterialPreset.groupRadius
                            color: Qt.rgba(0, 0, 0, 0.6)
                            visible: panCard.currentPanZoom !== 1.0

                            StyledText {
                                id: zoomBadgeLabel
                                anchors.centerIn: parent
                                text: panCard.currentPanZoom.toFixed(1) + "×"
                                color: "white"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }
                        }

                        // Crosshairs (visible while dragging)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 1; height: parent.height
                            color: Qt.rgba(1, 1, 1, 0.25)
                            visible: panDragArea.drag.active
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width; height: 1
                            color: Qt.rgba(1, 1, 1, 0.25)
                            visible: panDragArea.drag.active
                        }
                    }

                    // Zoom slider row
                    RowLayout {
                        id: panZoomRow
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.spacingSmall
                        enabled: panCard.isFillMode

                        MaterialSymbol {
                            text: "zoom_out"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }

                        StyledSlider {
                            id: panZoomSlider
                            Layout.fillWidth: true
                            Layout.preferredWidth: -1
                            Layout.maximumWidth: 16777215
                            from: 1.0
                            to: 3.0
                            stepSize: 0.1
                            stopIndicatorValues: []
                            value: panCard.currentPanZoom
                            tooltipContent: panCard.currentPanZoom.toFixed(1) + "×"
                            enableSettingsSearch: false

                            onMoved: {
                                Config.setNestedValue("background.pan.zoom", Math.round(value * 10) / 10)
                            }
                        }

                        MaterialSymbol {
                            text: "zoom_in"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}

SettingsCardSection {
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "effects"
    visible: false
    expanded: true
    icon: "wallpaper"
    title: Translation.tr("Wallpaper Blur & Dim")

    SettingsGroup {
        SettingsSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Enable wallpaper blur when windows are present")
            checked: Config.options?.background?.effects?.enableBlur ?? false
            onCheckedChanged: Config.setNestedValue("background.effects.enableBlur", checked)
        }

        ConfigSpinBox {
            visible: Config.options?.background?.effects?.enableBlur ?? false
            icon: "blur_medium"
            text: Translation.tr("Blur radius")
            value: Config.options?.background?.effects?.blurRadius ?? 32
            from: 0
            to: 100
            stepSize: 2
            onValueChanged: Config.setNestedValue("background.effects.blurRadius", value)
        }

        SettingsDivider {}

        ConfigSpinBox {
            icon: "brightness_6"
            text: Translation.tr("Dim overlay (%)")
            value: Config.options?.background?.effects?.dim ?? 0
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: Config.setNestedValue("background.effects.dim", value)
        }

        ConfigSpinBox {
            icon: "brightness_low"
            text: Translation.tr("Extra dim when windows (%)")
            value: Config.options?.background?.effects?.dynamicDim ?? 0
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: Config.setNestedValue("background.effects.dynamicDim", value)
        }
    }
}

SettingsCardSection {
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "effects"
    visible: false
    expanded: true
    icon: "texture"
    title: Translation.tr("Overview Backdrop")

    SettingsGroup {
        SettingsSwitch {
            buttonIcon: "texture"
            text: Translation.tr("Enable backdrop layer for overview")
            checked: Config.options?.background?.backdrop?.enable ?? true
            onCheckedChanged: Config.setNestedValue("background.backdrop.enable", checked)
        }

        SettingsSwitch {
            visible: Config.options?.background?.backdrop?.enable ?? true
            buttonIcon: "palette"
            text: Translation.tr("Derive theme colors from backdrop")
            checked: Config.options?.appearance?.wallpaperTheming?.useBackdropForColors ?? false
            onCheckedChanged: {
                Config.setNestedValue("appearance.wallpaperTheming.useBackdropForColors", checked)
                if (!(Config.options?.background?.backdrop?.useMainWallpaper ?? true)) {
                    Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"])
                }
            }
        }

        SettingsSwitch {
            visible: (Config.options?.background?.backdrop?.enable ?? true) && !(Config.options?.background?.backdrop?.hideWallpaper ?? false)
            buttonIcon: "image"
            text: Translation.tr("Use main wallpaper")
            checked: Config.options?.background?.backdrop?.useMainWallpaper ?? true
            onCheckedChanged: {
                Config.setNestedValue("background.backdrop.useMainWallpaper", checked);
                if (checked) {
                    Config.setNestedValue("background.backdrop.wallpaperPath", "");
                }
            }
        }

        RippleButtonWithIcon {
            visible: !(Config.options?.background?.backdrop?.useMainWallpaper ?? true)
            Layout.fillWidth: true
            buttonRadius: Appearance.rounding.small
            materialIcon: "wallpaper"
            mainText: Translation.tr("Pick backdrop wallpaper")
            onClicked: {
                Config.setNestedValue("wallpaperSelector.selectionTarget", "backdrop")
                Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "wallpaperSelector", "toggle"]);
            }
        }

        ConfigRow {
            uniform: true
            visible: Config.options?.background?.backdrop?.enable ?? true

            ConfigSpinBox {
                icon: "blur_on"
                text: Translation.tr("Blur radius")
                value: Config.options?.background?.backdrop?.blurRadius ?? 64
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: Config.setNestedValue("background.backdrop.blurRadius", value)
            }

            ConfigSpinBox {
                icon: "brightness_5"
                text: Translation.tr("Dim (%)")
                value: Config.options?.background?.backdrop?.dim ?? 20
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: Config.setNestedValue("background.backdrop.dim", value)
            }
        }
    }
}
    }
}
