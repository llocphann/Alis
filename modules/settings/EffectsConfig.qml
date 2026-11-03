import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 25
    settingsPageName: Translation.tr("Effects & Visuals")
    property string activeSection: "glass"
    readonly property bool isIiActive: Config.options?.panelFamily !== "waffle"

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        if (label.includes("color") || label.includes("cava") || label.includes("spectrum") || label.includes("app"))
            root.activeSection = "color"
        else
            root.activeSection = "glass"
        return true
    }

    // Help contract marker: Translation.tr("Set rendering policy, then adjust specific effects.")
    SettingsTaskNavigator {
        showTabBar: false
        showIntro: false
        icon: "blur_on"
        title: Translation.tr("Effects & Visuals")
        description: Translation.tr("Blur backend, per-area glass policy, backdrop, app color generation and Cava spectrum.")
        summary: Translation.tr("Blur & Glass · Backdrop · App Color Generation & Cava")
        currentValue: (root.activeSection === "areas" || root.activeSection === "motion") ? "glass" : root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Blur, Glass & Areas"), icon: "blur_on", value: "glass" },
            { displayName: Translation.tr("App Color Generation & Cava"), icon: "colors", value: "color" }
        ]
    }

    readonly property var backendOptions: [
        { displayName: Translation.tr("Style default"), value: "auto" },
        { displayName: Translation.tr("Wallpaper glass"), value: "wallpaper" },
        { displayName: Translation.tr("Compositor blur"), value: "compositor" },
        { displayName: Translation.tr("Off"), value: "off" }
    ]
    readonly property var areaDescriptors: [
        { key: "bar", icon: "toast", label: Translation.tr("Bars") },
        { key: "dock", icon: "dock_to_bottom", label: Translation.tr("Dock") },
        { key: "panels", icon: "side_navigation", label: Translation.tr("Panels and popups") },
        { key: "islands", icon: "blur_on", label: Translation.tr("Islands and Ricelin") },
        { key: "widgets", icon: "widgets", label: Translation.tr("Desktop widgets") }
    ]

    GridLayout {
        objectName: "effectsTwoColumnGrid"
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
            visible: true
            expanded: true
            icon: "blur_on"
            title: Translation.tr("Blur, Glass & Power")

            SettingsGroup {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.spacingMedium
                    MaterialSymbol { text: "auto_awesome"; iconSize: Appearance.font.pixelSize.larger }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Default blur backend") }
                    StyledComboBox {
                        Layout.preferredWidth: 200
                        model: root.backendOptions
                        textRole: "displayName"
                        currentIndex: Math.max(0, root.backendOptions.findIndex(o => o.value === (Config.options?.performance?.blurBackend ?? "auto")))
                        onActivated: index => Config.setNestedValue("performance.blurBackend", root.backendOptions[index].value)
                    }
                }
                SettingsSwitch {
                    visible: Appearance.nativeBlurSupported
                    buttonIcon: "blur_on"
                    text: Translation.tr("Allow compositor blur")
                    checked: Config.options?.performance?.compositorBlur ?? true
                    onCheckedChanged: Config.setNestedValue("performance.compositorBlur", checked)
                }

                SettingsDivider {}

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "animation"
                        text: Translation.tr("Reduce animations")
                        checked: Config.options?.performance?.reduceAnimations ?? false
                        onCheckedChanged: Config.setNestedValue("performance.reduceAnimations", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "energy_savings_leaf"
                        text: Translation.tr("Low power effects")
                        checked: Config.options?.performance?.lowPower ?? false
                        onCheckedChanged: Config.setNestedValue("performance.lowPower", checked)
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
            visible: true
            expanded: true
            icon: "tune"
            title: Translation.tr("Per-area Overrides")

            SettingsGroup {
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    uniformCellWidths: true
                    columnSpacing: 12
                    rowSpacing: 8

                    Repeater {
                        model: root.areaDescriptors
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.columnSpan: index === 4 ? 2 : 1
                            spacing: Appearance.sizes.spacingSmall
                            MaterialSymbol { text: modelData.icon; iconSize: Appearance.font.pixelSize.normal }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.label
                                elide: Text.ElideRight
                            }
                            StyledComboBox {
                                Layout.preferredWidth: index === 4 ? 200 : 136
                                readonly property var options: [{ displayName: Translation.tr("Inherit"), value: "inherit" }].concat(root.backendOptions)
                                model: options
                                textRole: "displayName"
                                currentIndex: Math.max(0, options.findIndex(o => o.value === (Config.options?.performance?.blurAreas?.[modelData.key] ?? "inherit")))
                                onActivated: idx => Config.setNestedValue("performance.blurAreas." + modelData.key, options[idx].value)
                            }
                        }
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
            visible: root.isIiActive
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

                ConfigRow {
                    uniform: true

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
        }

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
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

                ConfigRow {
                    uniform: true
                    visible: Config.options?.background?.backdrop?.enable ?? true

                    SettingsSwitch {
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
                        visible: !(Config.options?.background?.backdrop?.hideWallpaper ?? false)
                        buttonIcon: "image"
                        text: Translation.tr("Use main wallpaper")
                        checked: Config.options?.background?.backdrop?.useMainWallpaper ?? true
                        onCheckedChanged: {
                            Config.setNestedValue("background.backdrop.useMainWallpaper", checked)
                            if (checked) {
                                Config.setNestedValue("background.backdrop.wallpaperPath", "")
                            }
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
                        Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "wallpaperSelector", "toggle"])
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

    AdvancedConfig {
        id: embeddedAdvancedSection
        objectName: "effectsAdvancedSection"
        visible: true
        embedded: true
        settingsPageIndex: root.settingsPageIndex
        Layout.fillWidth: true
        Layout.topMargin: 14
    }
}
