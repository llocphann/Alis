import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 25
    settingsPageName: Translation.tr("Effects")
    property string activeSection: "glass"

    SettingsTaskNavigator {
        showTabBar: false
        icon: "blur_on"
        title: Translation.tr("Effects")
        description: Translation.tr("Set rendering policy, then adjust specific effects.")
        summary: Translation.tr("Glass · per-area policy · motion")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Glass"), icon: "blur_on", value: "glass" },
            { displayName: Translation.tr("Areas"), icon: "tune", value: "areas" },
            { displayName: Translation.tr("Motion"), icon: "animation", value: "motion" }
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
        columnSpacing: 14
        rowSpacing: 14

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 14

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "glass"
                visible: true
                expanded: true
                icon: "blur_on"
                title: Translation.tr("Blur and glass")
                SettingsGroup {
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.spacingMedium
                        MaterialSymbol { text: "auto_awesome"; iconSize: Appearance.font.pixelSize.larger }
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Default blur backend") }
                        StyledComboBox {
                            Layout.preferredWidth: 210
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
                }
            }

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "motion"
                visible: true
                expanded: true
                icon: "animation"
                title: Translation.tr("Motion and power")
                SettingsGroup {
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
                    SettingsSwitch {
                        buttonIcon: "memory"
                        text: Translation.tr("Notify when a restart would free memory")
                        checked: Config.options?.performance?.memoryWarningNotification ?? false
                        onCheckedChanged: Config.setNestedValue("performance.memoryWarningNotification", checked)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 14

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "areas"
                visible: true
                expanded: true
                icon: "tune"
                title: Translation.tr("Per-area overrides")
                SettingsGroup {
                    Repeater {
                        model: root.areaDescriptors
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Appearance.sizes.spacingMedium
                            MaterialSymbol { text: modelData.icon; iconSize: Appearance.font.pixelSize.larger }
                            StyledText { Layout.fillWidth: true; text: modelData.label }
                            StyledComboBox {
                                Layout.preferredWidth: 210
                                readonly property var options: [{ displayName: Translation.tr("Inherit"), value: "inherit" }].concat(root.backendOptions)
                                model: options
                                textRole: "displayName"
                                currentIndex: Math.max(0, options.findIndex(o => o.value === (Config.options?.performance?.blurAreas?.[modelData.key] ?? "inherit")))
                                onActivated: index => Config.setNestedValue("performance.blurAreas." + modelData.key, options[index].value)
                            }
                        }
                    }
                }
            }

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "areas"
                visible: true
                expanded: true
                icon: "filter_b_and_w"
                title: Translation.tr("Visual Effects")

                SettingsGroup {
                    SettingsSwitch {
                        buttonIcon: "filter_b_and_w"
                        text: Translation.tr("Desaturation effect")
                        checked: Boolean(Config.options?.appearance?.desaturation?.enable)
                        onCheckedChanged: Config.setNestedValue("appearance.desaturation.enable", checked)
                        StyledToolTip {
                            text: Translation.tr("Apply a grayscale/dimmed effect to shell components")
                        }
                    }

                    SettingsDivider {}

                    ConfigRow {
                        enabled: Boolean(Config.options?.appearance?.desaturation?.enable)
                        uniform: true
                        ConfigSpinBox {
                            icon: "invert_colors"
                            text: Translation.tr("Saturation %")
                            value: Math.round((Config.options?.appearance?.desaturation?.saturation ?? -0.7) * -100)
                            from: 0
                            to: 100
                            stepSize: 10
                            onValueChanged: Config.setNestedValue("appearance.desaturation.saturation", -value / 100)
                            StyledToolTip {
                                text: Translation.tr("Amount of color to remove (0 = normal, 100 = grayscale)")
                            }
                        }
                        ConfigSpinBox {
                            icon: "brightness_6"
                            text: Translation.tr("Dim %")
                            value: Math.round((Config.options?.appearance?.desaturation?.brightness ?? -0.15) * -100)
                            from: 0
                            to: 50
                            stepSize: 5
                            onValueChanged: Config.setNestedValue("appearance.desaturation.brightness", -value / 100)
                            StyledToolTip {
                                text: Translation.tr("Amount of brightness reduction (0 = normal)")
                            }
                        }
                    }

                    SettingsDivider {}

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Apply to")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Boolean(Config.options?.appearance?.desaturation?.enable)
                                ? Appearance.colors.colOnSurface
                                : Appearance.colors.colSubtext
                        }

                        ButtonGroup {
                            enabled: Boolean(Config.options?.appearance?.desaturation?.enable)
                            uniformCellSizes: true
                            spacing: 0

                            SelectionGroupButton {
                                leftmost: true
                                buttonText: Translation.tr("All")
                                toggled: (Config.options?.appearance?.desaturation?.scope ?? "all") === "all"
                                onClicked: Config.setNestedValue("appearance.desaturation.scope", "all")
                            }
                            SelectionGroupButton {
                                buttonText: Translation.tr("Panels only")
                                toggled: (Config.options?.appearance?.desaturation?.scope ?? "all") === "panels"
                                onClicked: Config.setNestedValue("appearance.desaturation.scope", "panels")
                            }
                            SelectionGroupButton {
                                rightmost: true
                                buttonText: Translation.tr("Custom")
                                toggled: (Config.options?.appearance?.desaturation?.scope ?? "all") === "custom"
                                onClicked: Config.setNestedValue("appearance.desaturation.scope", "custom")
                            }
                        }
                    }

                    ColumnLayout {
                        visible: (Config.options?.appearance?.desaturation?.scope ?? "all") === "custom"
                        enabled: Boolean(Config.options?.appearance?.desaturation?.enable)
                        Layout.fillWidth: true
                        spacing: 0

                        SettingsSwitch {
                            buttonIcon: "toolbar"
                            text: Translation.tr("Bar")
                            checked: Config.options?.appearance?.desaturation?.bar ?? true
                            onCheckedChanged: Config.setNestedValue("appearance.desaturation.bar", checked)
                        }
                        SettingsSwitch {
                            buttonIcon: "dock_to_bottom"
                            text: Translation.tr("Dock")
                            checked: Config.options?.appearance?.desaturation?.dock ?? true
                            onCheckedChanged: Config.setNestedValue("appearance.desaturation.dock", checked)
                        }
                        SettingsSwitch {
                            buttonIcon: "view_sidebar"
                            text: Translation.tr("Sidebars")
                            checked: Config.options?.appearance?.desaturation?.sidebars ?? true
                            onCheckedChanged: Config.setNestedValue("appearance.desaturation.sidebars", checked)
                        }
                        SettingsSwitch {
                            buttonIcon: "layers"
                            text: Translation.tr("Overlays")
                            checked: Config.options?.appearance?.desaturation?.overlays ?? true
                            onCheckedChanged: Config.setNestedValue("appearance.desaturation.overlays", checked)
                        }
                        SettingsSwitch {
                            buttonIcon: "picture_in_picture"
                            text: Translation.tr("Popups")
                            checked: Config.options?.appearance?.desaturation?.popups ?? true
                            onCheckedChanged: Config.setNestedValue("appearance.desaturation.popups", checked)
                        }
                    }
                }
            }
        }
    }
}
