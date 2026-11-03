import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../dashboard/DashboardCustomTabPolicy.js" as TabPolicy

ContentPage {
    id: root
    settingsPageIndex: 16
    settingsPageName: Translation.tr("Dashboard & Overview")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    property string activeSection: "general"
    readonly property var tabChoices: {
        const choices = [
            {displayName:Translation.tr("Dashboard"),icon:"dashboard",value:"dashboard"},
            {displayName:Translation.tr("Weekly Planner"),icon:"calendar_month",value:"weeklyPlanner"}
        ]
        if (Config.options?.dashboard?.music?.enable ?? true)
            choices.splice(1,0,{displayName:Translation.tr("Music"),icon:"library_music",value:"music"})
        if (Config.options?.dashboard?.spacedRepetition?.enable ?? true)
            choices.push({displayName:Translation.tr("Spaced Repetition"),icon:"school",value:"spacedRepetition"})
        for (const tab of TabPolicy.tabs(Config.options?.dashboard?.customTabs))
            choices.push({displayName:tab.name,icon:"tab",value:tab.id})
        return choices
    }

    SettingsTaskNavigator {
        visible: root.isIiActive
        showTabBar: false
        showIntro: false
        icon: "space_dashboard"
        title: Translation.tr("Dashboard & Overview")
        description: Translation.tr("Tune the Dashboard surface, then arrange and resize modules directly on its canvas.")
        summary: Translation.tr("Dashboard · Music · Overview")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Dashboard & Music"), icon: "space_dashboard", value: "general" },
            { displayName: Translation.tr("Workspace Overview"), icon: "overview_key", value: "overview" }
        ]
    }

    SettingsCardSection {
        visible: !root.isIiActive
        expanded: true
        icon: "info"
        title: Translation.tr("Not Active")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Dashboard requires Material (ii). Select it under Modules → Panel Style.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

    Component.onCompleted: {
        if (Config.options?.overview?.workspaceHover?.enable === false)
            Config.setNestedValue("overview.workspaceHover.enable", true)
    }

    GridLayout {
        objectName: "dashboardTwoColumnGrid"
        Layout.fillWidth: true
        columns: 2
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 14
        visible: root.isIiActive

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "general"
            visible: root.isIiActive
            expanded: true
            icon: "space_dashboard"
            title: Translation.tr("Dashboard")

            SettingsGroup {
                ContentSubsection {
                    title: Translation.tr("Default tab after inactivity")
                    ConfigSelectionArray {
                        currentValue: root.tabChoices.some(item =>
                            item.value === (Config.options?.dashboard?.defaultTabId ?? "dashboard"))
                            ? (Config.options?.dashboard?.defaultTabId || "dashboard") : "dashboard"
                        options: root.tabChoices
                        onSelected: id => Config.setNestedValue("dashboard.defaultTabId",id)
                    }
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Return after (min)")
                        value: Config.options?.dashboard?.inactiveMinutes ?? 0
                        from: 0
                        to: 240
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("dashboard.inactiveMinutes",value)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Card opacity (%)")
                        value: Math.round((Config.options?.dashboard?.appearance?.cardOpacity ?? 1) * 100)
                        from: 30
                        to: 100
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("dashboard.appearance.cardOpacity", value / 100)
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Panel")

                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            text: Translation.tr("% width")
                            value: Math.round((Config.options?.dashboard?.widthRatio ?? 0.72) * 100)
                            from: 40
                            to: 90
                            stepSize: 2
                            onValueChanged: Config.setNestedValue("dashboard.widthRatio", value / 100)
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            text: Translation.tr("% height")
                            value: Math.round((Config.options?.dashboard?.heightRatio ?? 0.72) * 100)
                            from: 45
                            to: 90
                            stepSize: 2
                            onValueChanged: Config.setNestedValue("dashboard.heightRatio", value / 100)
                        }
                    }
                }

                ConfigRow {
                    uniform: true
                    ContentSubsection {
                        Layout.fillWidth: true
                        title: Translation.tr("Welcome subtitle")
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Custom phrase (optional)")
                            text: Config.options?.dashboard?.subtitle ?? ""
                            onTextChanged: {
                                Qt.callLater(() => {
                                    Config.setNestedValue("dashboard.subtitle", text)
                                });
                            }
                        }
                    }

                    ContentSubsection {
                        Layout.fillWidth: true
                        title: Translation.tr("GitHub username")
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("e.g. octocat")
                            text: Config.options?.dashboard?.github?.username ?? ""
                            onTextChanged: {
                                Qt.callLater(() => {
                                    Config.setNestedValue("dashboard.github.username", text)
                                });
                            }
                        }
                    }
                }

                DashboardMusicSettings {
                    Layout.fillWidth: true
                }
            }
        }

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "general"
            visible: root.isIiActive
            expanded: true
            icon: "dashboard_customize"
            title: Translation.tr("Canvas & grid")

            SettingsGroup {
                ConfigSwitch {
                    text: Translation.tr("Snap modules to grid")
                    checked: Config.options?.dashboard?.canvas?.snap ?? true
                    onCheckedChanged:
                        Config.setNestedValue("dashboard.canvas.snap", checked)
                    StyledToolTip {
                        text: Translation.tr("Snap moved or resized modules to the grid on release.")
                    }
                }

                ConfigSwitch {
                    text: Translation.tr("Auto-adjust affected module sizes")
                    checked:
                        Config.options?.dashboard?.canvas?.autoAdjustSize ?? true
                    onCheckedChanged:
                        Config.setNestedValue(
                        "dashboard.canvas.autoAdjustSize", checked)
                    StyledToolTip {
                        text: Translation.tr("Resizing can adjust neighbors; moving modules never changes their sizes.")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Grid style")
                    StyledToolTip {
                        text: Translation.tr("Dashboard → Edit widgets lets you move or resize modules; outside Edit mode, layout is locked.")
                    }
                    ConfigSelectionArray {
                        currentValue:
                            Config.options?.dashboard?.canvas?.gridStyle ?? "dots"
                        onSelected: value =>
                            Config.setNestedValue("dashboard.canvas.gridStyle", value)
                        options: [
                            { displayName: Translation.tr("Dots"), icon: "drag_indicator", value: "dots" },
                            { displayName: Translation.tr("Lines"), icon: "grid_4x4", value: "lines" },
                            { displayName: Translation.tr("Crosshair"), icon: "add", value: "cross" }
                        ]
                    }
                }

                ConfigSpinBox {
                    text: Translation.tr("Grid cell size (px)")
                    value: Config.options?.dashboard?.canvas?.gridSize ?? 24
                    from: 8
                    to: 96
                    stepSize: 8
                    onValueChanged:
                        Config.setNestedValue("dashboard.canvas.gridSize", value)
                }
            }
        }

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "general"
            visible: root.isIiActive
            expanded: true
            icon: "school"
            title: Translation.tr("Spaced Repetition")

            DashboardSpacedRepetitionSettings {
                Layout.fillWidth: true
            }
        }

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "overview"
            visible: root.isIiActive
            expanded: true
            icon: "overview_key"
            title: Translation.tr("Overview Trigger & Grid")

            SettingsGroup {
                ContentSubsection {
                    title: Translation.tr("Hover timing (ms)")

                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "timer"
                            text: Translation.tr("Open")
                            value: Config.options?.overview?.workspaceHover?.delayMs ?? 280
                            from: 0
                            to: 1200
                            stepSize: 20
                            onValueChanged: Config.setNestedValue(
                                "overview.workspaceHover.delayMs", value)
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "timer_off"
                            text: Translation.tr("Close")
                            value: Config.options?.overview?.workspaceHover?.closeDelayMs ?? 220
                            from: 0
                            to: 1200
                            stepSize: 20
                            onValueChanged: Config.setNestedValue(
                                "overview.workspaceHover.closeDelayMs", value)
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Grid layout")

                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            Layout.fillWidth: true
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
                            Layout.fillWidth: true
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

                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "loupe"
                            text: Translation.tr("% scale")
                            value: Math.round((Config.options?.overview?.scale ?? 0.17) * 100)
                            from: 5
                            to: 50
                            stepSize: 1
                            onValueChanged: Config.setNestedValue(
                                "overview.scale", value / 100)
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "grid_3x3"
                            text: Translation.tr("Gap (px)")
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
            _preventBentoReparent: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            settingsTaskSection: "overview"
            visible: root.isIiActive
            expanded: true
            icon: "preview"
            title: Translation.tr("Overview Appearance")

            SettingsGroup {
                ContentSubsection {
                    title: Translation.tr("Content & appearance")

                    ConfigRow {
                        uniform: true

                        SettingsSwitch {
                            Layout.fillWidth: true
                            buttonIcon: "preview"
                            text: Translation.tr("Window previews")
                            checked: Config.options?.overview?.showPreviews !== false
                            onCheckedChanged: Config.setNestedValue(
                                "overview.showPreviews", checked)
                        }

                        SettingsSwitch {
                            Layout.fillWidth: true
                            buttonIcon: "looks_one"
                            text: Translation.tr("Workspace numbers")
                            checked: Config.options?.overview?.showWorkspaceNumbers ?? false
                            onCheckedChanged: Config.setNestedValue(
                                "overview.showWorkspaceNumbers", checked)
                        }
                    }

                    ConfigRow {
                        uniform: true

                        SettingsSwitch {
                            Layout.fillWidth: true
                            buttonIcon: "center_focus_strong"
                            text: Translation.tr("Center app icons")
                            checked: Config.options?.overview?.centerIcons ?? true
                            onCheckedChanged: Config.setNestedValue(
                                "overview.centerIcons", checked)
                        }

                        SettingsSwitch {
                            Layout.fillWidth: true
                            buttonIcon: "blur_on"
                            text: Translation.tr("Blur wallpaper")
                            checked: Config.options?.overview?.backgroundBlurEnable !== false
                            onCheckedChanged: Config.setNestedValue(
                                "overview.backgroundBlurEnable", checked)
                        }
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
