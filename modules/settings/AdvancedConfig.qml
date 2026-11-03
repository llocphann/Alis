import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    settingsPageIndex: 8
    settingsPageName: Translation.tr("Advanced")

    property bool cavaControlsReady: false
    property string activeSection: "color"
    readonly property string _legacyGpuMonitorHint: Translation.tr("On hybrid laptops, GPU polling can wake the dGPU; disabling pins Qt to iGPU after restart.")
    Component.onCompleted: Qt.callLater(() => root.cavaControlsReady = true)

    SettingsTaskNavigator {
        visible: !root.embedded
        showTabBar: false
        icon: "construction"
        title: Translation.tr("Advanced")
        description: Translation.tr("Color-generation controls and runtime diagnostics.")
        summary: Translation.tr("Color generation · Cava & spectrum")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Color"), icon: "colors", value: "color" }
        ]
    }

    function setCavaValue(path, value, regenerateStandalone): void {
        if (!root.cavaControlsReady)
            return
        Config.setNestedValue(path, value)
        if (regenerateStandalone)
            colorRegenTimer.restart()
    }

    function resetCavaDefaults(): void {
        if (!root.cavaControlsReady)
            return
        Config.setNestedValues({
            "appearance.cava.colorSource": "theme",
            "appearance.cava.gradientCount": 8,
            "appearance.cava.sensitivity": 100,
            "appearance.cava.bars": 0,
            "appearance.cava.framerate": 30,
            "appearance.cava.stereo": true,
            "appearance.cava.waveOpacity": 30,
        })
        colorRegenTimer.restart()
    }

    Timer {
        id: colorRegenTimer
        interval: 350  // Reduced for faster terminal and app color previews
        onTriggered: ThemeService.regenerateAutoTheme("live-config")
    }

    GridLayout {
        objectName: "advancedTwoColumnGrid"
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "color"
            visible: true
            expanded: true
            icon: "colors"
            title: Translation.tr("App Color Generation")

            SettingsGroup {
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 360 ? 2 : 1
                    columnSpacing: 10
                    rowSpacing: 4

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "hardware"
                        text: Translation.tr("Shell & utilities")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableAppsAndShell ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableAppsAndShell", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate colors for GTK apps, fuzzel, and other utilities from wallpaper")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "tv_options_input_settings"
                        text: Translation.tr("Qt apps")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableQtApps ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableQtApps", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate colors for Qt/KDE apps (requires Shell & utilities)")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "chat"
                        text: Translation.tr("Vesktop/Discord")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableVesktop ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableVesktop", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate Discord theme from wallpaper colors (requires Vesktop with system24 theme)")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "music_note"
                        text: Translation.tr("Spotify (Spicetify)")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableSpicetify ?? false
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableSpicetify", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate and apply a Spicetify theme from wallpaper colors")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "sports_esports"
                        text: Translation.tr("Steam (Millennium)")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableSteam ?? false
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableSteam", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Apply Material You colors to Steam via Millennium Material-Theme")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "music_note"
                        text: Translation.tr("Pear Desktop (YouTube Music)")
                        checked: Config.options?.appearance?.wallpaperTheming?.enablePearDesktop ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enablePearDesktop", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Apply Material You colors to YouTube Music Desktop App")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "code"
                        text: Translation.tr("Zed editor")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableZed ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableZed", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate Zed editor theme from wallpaper colors")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "code"
                        text: Translation.tr("VSCode")
                        checked: (Config.options?.appearance?.wallpaperTheming?.enableVSCode ?? true)
                            && (Config.options?.appearance?.wallpaperTheming?.vscodeEditors?.code ?? true)
                        onCheckedChanged: {
                            const codiumOn = (Config.options?.appearance?.wallpaperTheming?.enableVSCode ?? true)
                                && (Config.options?.appearance?.wallpaperTheming?.vscodeEditors?.codium ?? true);
                            Config.setNestedValues({
                                "appearance.wallpaperTheming.vscodeEditors.code": checked,
                                "appearance.wallpaperTheming.vscodeEditors.codium": codiumOn,
                                "appearance.wallpaperTheming.enableVSCode": checked || codiumOn
                            });
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate and auto-apply Material You theme for VSCode")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "code"
                        text: Translation.tr("VSCodium")
                        checked: (Config.options?.appearance?.wallpaperTheming?.enableVSCode ?? true)
                            && (Config.options?.appearance?.wallpaperTheming?.vscodeEditors?.codium ?? true)
                        onCheckedChanged: {
                            const codeOn = (Config.options?.appearance?.wallpaperTheming?.enableVSCode ?? true)
                                && (Config.options?.appearance?.wallpaperTheming?.vscodeEditors?.code ?? true);
                            Config.setNestedValues({
                                "appearance.wallpaperTheming.vscodeEditors.codium": checked,
                                "appearance.wallpaperTheming.vscodeEditors.code": codeOn,
                                "appearance.wallpaperTheming.enableVSCode": codeOn || checked
                            });
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate and auto-apply Material You theme for VSCodium")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "language"
                        text: Translation.tr("Chrome / Chromium")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableChrome ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableChrome", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Apply wallpaper-derived colors to Chrome and Chromium browser")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "code"
                        text: Translation.tr("OpenCode")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableOpenCode ?? false
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableOpenCode", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Apply wallpaper-derived theme to OpenCode AI editor")
                        }
                    }
                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "code"
                        text: Translation.tr("Neovim / LazyVim")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableNeovim ?? false
                        onCheckedChanged: {
                            Config.setNestedValue("appearance.wallpaperTheming.enableNeovim", checked);
                            colorRegenTimer.restart();
                        }
                        StyledToolTip {
                            text: Translation.tr("Generate Neovim/LazyVim theme at ~/.config/nvim/lua/plugins/neovim.lua.")
                        }
                    }
                }

                ContentSubsection {
                    visible: Config.options?.appearance?.wallpaperTheming?.enableSpicetify ?? false
                    title: Translation.tr("Spotify theme")
                    tooltip: Translation.tr("Choose the Spicetify layout while keeping Alis wallpaper colors")

                    ConfigSelectionArray {
                        currentValue: Config.options?.appearance?.wallpaperTheming?.spicetifyTheme ?? "Alis"
                        onSelected: newValue => {
                            Config.setNestedValue("appearance.wallpaperTheming.spicetifyTheme", newValue)
                            colorRegenTimer.restart()
                        }
                        options: [
                            { displayName: Translation.tr("Sleek"), value: "Alis" },
                            { displayName: Translation.tr("Text (TUI)"), value: "AlisTUI" }
                        ]
                    }
                }
            }
        }

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "color"
            visible: true
            expanded: true
            icon: "equalizer"
            title: Translation.tr("Cava & Spectrum Options")

            SettingsGroup {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SettingsSwitch {
                        id: cavaSwitch
                        Layout.fillWidth: true
                        buttonIcon: "equalizer"
                        text: Translation.tr("Theme standalone Cava")
                        checked: Config.options?.appearance?.wallpaperTheming?.enableCava ?? false
                        onCheckedChanged: root.setCavaValue(
                            "appearance.wallpaperTheming.enableCava", checked, true)
                        StyledToolTip {
                            text: Translation.tr("Manage ~/.config/cava/config; internal visualizers stay independent.")
                        }
                    }

                    RippleButton {
                        Layout.preferredHeight: 30
                        implicitWidth: resetCavaRow.implicitWidth + 20
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.resetCavaDefaults()
                        contentItem: Item {
                            Row {
                                id: resetCavaRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "restart_alt"
                                    iconSize: 15
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Reset to defaults")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }

                ConfigSelectionArray {
                    currentValue: Config.options?.appearance?.cava?.colorSource ?? "theme"
                    onSelected: newValue => root.setCavaValue(
                        "appearance.cava.colorSource", newValue, true)
                    options: [
                        { displayName: Translation.tr("Theme palette"), value: "theme" },
                        { displayName: Translation.tr("Vibrant (saturated)"), value: "vibrant" },
                        { displayName: Translation.tr("Album cover"), value: "cover" },
                    ]
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: CavaTheme.visualizerColors

                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            radius: height / 2
                            color: modelData
                        }
                    }
                }

                SettingsNote {
                    icon: (Config.options?.appearance?.cava?.colorSource ?? "theme") === "cover"
                        ? "album" : "palette"
                    text: {
                        const source = Config.options?.appearance?.cava?.colorSource ?? "theme"
                        if (source === "vibrant")
                            return Translation.tr("Internal visualizers use a higher-saturation palette with wider hue separation. Standalone cava is regenerated too.")
                        if (source === "cover")
                            return CavaTheme.coverPaletteAvailable
                                ? Translation.tr("Using colors extracted live from the active album artwork.")
                                : Translation.tr("Waiting for active album artwork; the theme palette is used as a safe fallback.")
                        return Translation.tr("Internal visualizers use the current primary, secondary and tertiary theme colors.")
                    }
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        icon: "gradient"
                        text: Translation.tr("Gradient colors")
                        value: Config.options?.appearance?.cava?.gradientCount ?? 8
                        from: 1
                        to: 8
                        onValueChanged: root.setCavaValue(
                            "appearance.cava.gradientCount", value, true)
                        StyledToolTip {
                            text: Translation.tr("Use one color for a solid spectrum, or up to eight gradient stops")
                        }
                    }

                    ConfigSpinBox {
                        icon: "hearing"
                        text: Translation.tr("Sensitivity")
                        value: Config.options?.appearance?.cava?.sensitivity ?? 100
                        from: 1
                        to: 500
                        stepSize: 10
                        onValueChanged: root.setCavaValue(
                            "appearance.cava.sensitivity", value, true)
                        StyledToolTip {
                            text: Translation.tr("Audio sensitivity (higher = more reactive)")
                        }
                    }
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        icon: "bar_chart"
                        text: Translation.tr("Bars")
                        value: Config.options?.appearance?.cava?.bars ?? 0
                        from: 0
                        to: 200
                        stepSize: 8
                        onValueChanged: root.setCavaValue(
                            "appearance.cava.bars", value, true)
                        StyledToolTip {
                            text: Translation.tr("Number of frequency data points (0 = auto)")
                        }
                    }

                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Framerate")
                        value: Config.options?.appearance?.cava?.framerate ?? 30
                        from: 30
                        to: 165
                        stepSize: 5
                        onValueChanged: root.setCavaValue(
                            "appearance.cava.framerate", value, true)
                        StyledToolTip {
                            text: Translation.tr("Target refresh rate for the visualizer")
                        }
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "headphones"
                        text: Translation.tr("Stereo")
                        checked: Config.options?.appearance?.cava?.stereo ?? true
                        onCheckedChanged: root.setCavaValue(
                            "appearance.cava.stereo", checked, true)
                        StyledToolTip {
                            text: Translation.tr("Split visualizer into left/right channels")
                        }
                    }

                    ConfigSpinBox {
                        icon: "opacity"
                        text: Translation.tr("Wave opacity")
                        value: Config.options?.appearance?.cava?.waveOpacity ?? 30
                        from: 5
                        to: 100
                        stepSize: 5
                        onValueChanged: root.setCavaValue(
                            "appearance.cava.waveOpacity", value, false)
                        StyledToolTip {
                            text: Translation.tr("Shared wave fill opacity; bar spectrum has its own setting.")
                        }
                    }
                }
            }
        }
    }
}
