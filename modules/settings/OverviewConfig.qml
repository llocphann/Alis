import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    settingsPageIndex: 29
    settingsPageName: Translation.tr("Overview")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"

    SettingsTaskNavigator {
        visible: root.isIiActive
        showTabBar: false
        icon: "overview_key"
        title: Translation.tr("Overview")
        description: Translation.tr("Workspace hover and workspace preview layout.")
        summary: Translation.tr("Hover timing · layout · content · appearance")
    }

    SettingsCardSection {
        visible: !root.isIiActive
        expanded: true
        icon: "info"
        title: Translation.tr("Not Active")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Workspace Overview is available with the Material (ii) panel style.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

    GridLayout {
        objectName: "overviewTwoColumnGrid"
        Layout.fillWidth: true
        visible: root.isIiActive
        columns: width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

        SettingsCardSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            expanded: true
            icon: "overview_key"
            title: Translation.tr("Overview")

            SettingsGroup {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 12

                    SettingsSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable workspace Overview")
                        checked: Config.options?.overview?.workspaceHover?.enable ?? true
                        onCheckedChanged: Config.setNestedValue(
                            "overview.workspaceHover.enable", checked)
                        StyledToolTip {
                            text: Translation.tr("Show Overview when hovering workspace buttons on the Bar")
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Hover timing")

                        ConfigRow {
                            uniform: true

                            ConfigSpinBox {
                                icon: "timer"
                                text: Translation.tr("Open delay (ms)")
                                value: Config.options?.overview?.workspaceHover?.delayMs ?? 280
                                from: 0
                                to: 1200
                                stepSize: 20
                                enabled: Config.options?.overview?.workspaceHover?.enable ?? true
                                onValueChanged: Config.setNestedValue(
                                    "overview.workspaceHover.delayMs", value)
                            }

                            ConfigSpinBox {
                                icon: "timer_off"
                                text: Translation.tr("Close delay (ms)")
                                value: Config.options?.overview?.workspaceHover?.closeDelayMs ?? 220
                                from: 0
                                to: 1200
                                stepSize: 20
                                enabled: Config.options?.overview?.workspaceHover?.enable ?? true
                                onValueChanged: Config.setNestedValue(
                                    "overview.workspaceHover.closeDelayMs", value)
                            }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Layout")

                        ConfigSpinBox {
                            icon: "loupe"
                            text: Translation.tr("Scale (%)")
                            value: Math.round((Config.options?.overview?.scale ?? 0.17) * 100)
                            from: 5
                            to: 50
                            stepSize: 1
                            onValueChanged: Config.setNestedValue(
                                "overview.scale", value / 100)
                        }

                        ConfigRow {
                            uniform: true

                            ConfigSpinBox {
                                icon: "splitscreen_bottom"
                                text: Translation.tr("Rows")
                                value: Config.options?.overview?.rows ?? 1
                                from: 1
                                to: 6
                                stepSize: 1
                                onValueChanged: Config.setNestedValue(
                                    "overview.rows", value)
                            }

                            ConfigSpinBox {
                                icon: "splitscreen_right"
                                text: Translation.tr("Columns")
                                value: Config.options?.overview?.columns ?? 5
                                from: 1
                                to: 8
                                stepSize: 1
                                onValueChanged: Config.setNestedValue(
                                    "overview.columns", value)
                            }
                        }

                        ConfigSpinBox {
                            icon: "grid_3x3"
                            text: Translation.tr("Workspace gap (px)")
                            value: Config.options?.overview?.workspaceSpacing ?? 5
                            from: 0
                            to: 32
                            stepSize: 1
                            onValueChanged: Config.setNestedValue(
                                "overview.workspaceSpacing", value)
                        }
                    }
                }
            }
        }

        SettingsCardSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            expanded: true
            icon: "preview"
            title: Translation.tr("Content")

            SettingsGroup {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 12

                    ContentSubsection {
                        title: Translation.tr("Content")

                        SettingsSwitch {
                            buttonIcon: "preview"
                            text: Translation.tr("Show window previews")
                            checked: Config.options?.overview?.showPreviews !== false
                            onCheckedChanged: Config.setNestedValue(
                                "overview.showPreviews", checked)
                        }

                        SettingsSwitch {
                            buttonIcon: "looks_one"
                            text: Translation.tr("Show workspace numbers")
                            checked: Config.options?.overview?.showWorkspaceNumbers ?? false
                            onCheckedChanged: Config.setNestedValue(
                                "overview.showWorkspaceNumbers", checked)
                        }

                        SettingsSwitch {
                            buttonIcon: "center_focus_strong"
                            text: Translation.tr("Center app icons")
                            checked: Config.options?.overview?.centerIcons ?? true
                            onCheckedChanged: Config.setNestedValue(
                                "overview.centerIcons", checked)
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Workspace appearance")

                        SettingsSwitch {
                            buttonIcon: "blur_on"
                            text: Translation.tr("Blur workspace wallpaper")
                            checked: Config.options?.overview?.backgroundBlurEnable !== false
                            onCheckedChanged: Config.setNestedValue(
                                "overview.backgroundBlurEnable", checked)
                        }

                        ConfigSpinBox {
                            icon: "opacity"
                            text: Translation.tr("Workspace dim (%)")
                            value: Config.options?.overview?.backgroundDim ?? 35
                            from: 0
                            to: 80
                            stepSize: 5
                            onValueChanged: Config.setNestedValue(
                                "overview.backgroundDim", value)
                        }
                    }
                }
            }
        }
    }
}
