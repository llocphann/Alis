pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell

PanelSurface {
    id: root
    islandSkin: (Config.options?.controlPanel?.style ?? "panel") === "island"
    Layout.fillWidth: true
    implicitHeight: wallpaperLayout.implicitHeight + 16
    readonly property bool showSchemeChips: Config.options?.controlPanel?.showWallpaperSchemeChips ?? false
    readonly property var surfaceScreen: root.QsWindow.window?.screen ?? null
    readonly property string previewWallpaperUrl: {
        const _multiMonitor = WallpaperListener.multiMonitorEnabled
        const _perMonitor = WallpaperListener.effectivePerMonitor
        const _global = Wallpapers.effectiveWallpaperUrl
        return WallpaperListener.wallpaperUrlForScreen(root.surfaceScreen)
    }

    elevation: 1
    radiusOverride: islandSkin ? -1 : Appearance.rounding.normal

    ColumnLayout {
        id: wallpaperLayout
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "wallpaper"
                iconSize: 16
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: Translation.tr("Wallpaper")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                implicitWidth: 26
                implicitHeight: 26
                buttonText: Translation.tr("Random")
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: Wallpapers.randomFromCurrentFolder()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "shuffle"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Random") }
            }

            RippleButton {
                implicitWidth: 26
                implicitHeight: 26
                buttonText: Translation.tr("Browse")
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: GlobalActions.runLauncher(["wallpaperSelector", "toggle"])
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "folder_open"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Browse") }
            }
        }

        // Preview
        Item {
            id: previewContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 100

            Rectangle {
                id: previewMask
                anchors.fill: parent
                radius: Appearance.rounding.small
                visible: false
            }

            Image {
                id: wallpaperPreview
                anchors.fill: parent
                source: root.previewWallpaperUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: false
                sourceSize.width: previewContainer.width * 2
                sourceSize.height: previewContainer.height * 2
                layer.enabled: root.visible && GlobalStates.controlPanelOpen
                layer.effect: GE.OpacityMask {
                    maskSource: previewMask
                }
            }

            // Dark fade at bottom (masked to match preview corners)
            Item {
                id: fadeContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 32

                Rectangle {
                    id: fadeMask
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    visible: false
                }

                Rectangle {
                    id: fadeRect
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.4) }
                    }
                    visible: false
                }

                GE.OpacityMask {
                    anchors.fill: parent
                    source: fadeRect
                    maskSource: fadeMask
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.showSchemeChips
            sourceComponent: ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: Config.options?.appearance?.palette?.type ?? "auto"
                onSelected: newValue => {
                    Config.setNestedValue("appearance.palette.type", newValue)
                    if (ThemeService.isAutoTheme) {
                        Quickshell.execDetached(["/usr/bin/bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch --type ${newValue}`]);
                    } else {
                        const hex = MaterialThemeLoader.colorToHex(Appearance.m3colors.m3primary)
                        const mode = Appearance.m3colors.darkmode ? "dark" : "light"
                        MaterialThemeLoader.applySchemeVariant(hex, newValue, mode)
                    }
                }
                options: [
                    { "value": "auto", "displayName": Translation.tr("Auto"), "icon": "auto_awesome" },
                    { "value": "scheme-content", "displayName": Translation.tr("Content"), "icon": "image" },
                    { "value": "scheme-expressive", "displayName": Translation.tr("Expressive"), "icon": "flare" },
                    { "value": "scheme-fidelity", "displayName": Translation.tr("Fidelity"), "icon": "verified" },
                    { "value": "scheme-fruit-salad", "displayName": Translation.tr("Fruit Salad"), "icon": "local_florist" },
                    { "value": "scheme-monochrome", "displayName": Translation.tr("Monochrome"), "icon": "filter_b_and_w" },
                    { "value": "scheme-neutral", "displayName": Translation.tr("Neutral"), "icon": "tonality" },
                    { "value": "scheme-rainbow", "displayName": Translation.tr("Rainbow"), "icon": "gradient" },
                    { "value": "scheme-tonal-spot", "displayName": Translation.tr("Tonal Spot"), "icon": "palette" }
                ]
            }
        }
    }
}
