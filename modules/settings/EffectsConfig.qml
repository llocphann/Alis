import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../common/widgets/SettingsLayoutPolicy.js" as LayoutPolicy

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
        { key: "panels", icon: "side_navigation", label: Translation.tr("Popups") },
        { key: "islands", icon: "blur_on", label: Translation.tr("Islands") },
        { key: "widgets", icon: "widgets", label: Translation.tr("Desktop widgets") }
    ]

    SettingsCardSection {
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "blur_on"
        title: Translation.tr("Blur, Glass & Power")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.spacingMedium
                MaterialSymbol {
                    text: "auto_awesome"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Default blur backend")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Global rendering policy for blurred shell surfaces"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                StyledComboBox {
                    Layout.preferredWidth: Math.min(220, Math.max(164, Math.round(parent.width * 0.34)))
                    model: root.backendOptions
                    textRole: "displayName"
                    currentIndex: Math.max(0, root.backendOptions.findIndex(o => o.value === (Config.options?.performance?.blurBackend ?? "auto")))
                    onActivated: index => Config.setNestedValue("performance.blurBackend", root.backendOptions[index].value)
                }
            }

            SettingsDivider {
                visible: Appearance.nativeBlurSupported
            }

            SettingsSwitch {
                visible: Appearance.nativeBlurSupported
                buttonIcon: "blur_on"
                text: Translation.tr("Allow compositor blur")
                checked: Config.options?.performance?.compositorBlur ?? true
                onCheckedChanged: Config.setNestedValue("performance.compositorBlur", checked)
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 460 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 14
                rowSpacing: 8

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "animation"
                    text: Translation.tr("Reduce animations")
                    checked: Config.options?.performance?.reduceAnimations ?? false
                    onCheckedChanged: Config.setNestedValue("performance.reduceAnimations", checked)
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "energy_savings_leaf"
                    text: Translation.tr("Low power effects")
                    checked: Config.options?.performance?.lowPower ?? false
                    onCheckedChanged: Config.setNestedValue("performance.lowPower", checked)
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "layers"
                    text: Translation.tr("Island glass")
                    checked: Config.options?.appearance?.island?.glass ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.island.glass", checked)
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "flare"
                    text: Translation.tr("Island edge sheen")
                    checked: Config.options?.appearance?.island?.sheen ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.island.sheen", checked)
                }
            }
        }
    }

    SettingsCardSection {
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "tune"
        title: Translation.tr("Per-area Overrides")

        SettingsGroup {
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 680 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 16
                rowSpacing: 8

                Repeater {
                    model: root.areaDescriptors
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 10

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                        }
                        StyledComboBox {
                            Layout.preferredWidth: Math.min(200, Math.max(148, Math.round(parent.width * 0.42)))
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
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "wallpaper"
        title: Translation.tr("Wallpaper Blur & Dim")

        SettingsGroup {
            GridLayout {
                id: wallpaperEffectFlags
                Layout.fillWidth: true
                columns: Config.options?.panelFamily === "abyss"
                    ? LayoutPolicy.fittedControlColumns(wallpaperEffectFlags, 3) : (width >= 460 ? 3 : 1)
                uniformCellWidths: Config.options?.panelFamily !== "abyss" && columns > 1
                columnSpacing: 12
                rowSpacing: 8

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Config.options?.panelFamily === "abyss" ? implicitWidth : 1
                    Layout.minimumWidth: 0
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur behind windows")
                    // contract: Translation.tr("Blur wallpaper behind windows")
                    checked: Config.options?.background?.effects?.enableBlur ?? false
                    onCheckedChanged: Config.setNestedValue("background.effects.enableBlur", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Config.options?.panelFamily === "abyss" ? implicitWidth : 1
                    Layout.minimumWidth: 0
                    buttonIcon: "water_drop"
                    text: Translation.tr("Wallpaper ripple")
                    checked: Config.options?.background?.effects?.ripple?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("background.effects.ripple.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Config.options?.panelFamily === "abyss" ? implicitWidth : 1
                    Layout.minimumWidth: 0
                    buttonIcon: "opacity"
                    text: Translation.tr("Transparency")
                    // contract: Translation.tr("Surface transparency")
                    checked: Config.options?.appearance?.transparency?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("appearance.transparency.enable", checked)
                }
            }

            SettingsDivider {}

            GridLayout {
                id: wallpaperEffectValues
                Layout.fillWidth: true
                columns: Config.options?.panelFamily === "abyss"
                    ? LayoutPolicy.fittedControlColumns(wallpaperEffectValues, 3) : (width >= 520 ? 3 : 1)
                uniformCellWidths: Config.options?.panelFamily !== "abyss" && columns > 1
                columnSpacing: 12
                rowSpacing: 8

                ConfigSpinBox {
                    enabled: Config.options?.background?.effects?.enableBlur ?? false
                    Layout.fillWidth: true
                    Layout.preferredWidth: Config.options?.panelFamily === "abyss" ? implicitWidth : 1
                    Layout.minimumWidth: 0
                    icon: "blur_medium"
                    text: Translation.tr("Blur radius")
                    value: Config.options?.background?.effects?.blurRadius ?? 32
                    from: 0
                    to: 100
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("background.effects.blurRadius", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Config.options?.panelFamily === "abyss" ? implicitWidth : 1
                    Layout.minimumWidth: 0
                    icon: "brightness_6"
                    text: Translation.tr("Dim (%)")
                    // contract: Translation.tr("Dim overlay (%)")
                    value: Config.options?.background?.effects?.dim ?? 0
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("background.effects.dim", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Config.options?.panelFamily === "abyss" ? implicitWidth : 1
                    Layout.minimumWidth: 0
                    icon: "brightness_low"
                    text: Translation.tr("Window dim (%)")
                    // contract: Translation.tr("Extra dim on windows (%)") Translation.tr("Extra dim when windows (%)")
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
        Layout.fillWidth: true
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

            GridLayout {
                Layout.fillWidth: true
                visible: Config.options?.background?.backdrop?.enable ?? true
                columns: width >= 440 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 12
                rowSpacing: 8

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "palette"
                    text: Translation.tr("Backdrop theme colors")
                    // contract: Translation.tr("Derive theme colors from backdrop")
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
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
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

            SettingsDivider {
                visible: Config.options?.background?.backdrop?.enable ?? true
            }

            GridLayout {
                Layout.fillWidth: true
                visible: Config.options?.background?.backdrop?.enable ?? true
                columns: width >= 440 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 12
                rowSpacing: 8

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    icon: "blur_on"
                    text: Translation.tr("Blur radius")
                    value: Config.options?.background?.backdrop?.blurRadius ?? 64
                    from: 0
                    to: 100
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("background.backdrop.blurRadius", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
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

    SettingsCardSection {
        id: surfaceContrastCard
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "contrast"
        title: Translation.tr("Surface Contrast & Tinting")

        SettingsGroup {
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 440 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 12
                rowSpacing: 8

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "tonality"
                    text: Translation.tr("Desaturate surfaces")
                    checked: Config.options?.appearance?.desaturation?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("appearance.desaturation.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "format_color_fill"
                    text: Translation.tr("Extra surface tint")
                    checked: Config.options?.appearance?.extraBackgroundTint ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.extraBackgroundTint", checked)
                }
            }
        }
    }

    Item {
        id: embeddedAdvancedHost
        Layout.fillWidth: true
        implicitHeight: embeddedAdvancedSection.implicitHeight
        height: implicitHeight

        AdvancedConfig {
            id: embeddedAdvancedSection
            objectName: "effectsAdvancedSection"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            visible: true
            embedded: true
            settingsPageIndex: root.settingsPageIndex
            extraBottomHeight: 0
        }
    }
}
