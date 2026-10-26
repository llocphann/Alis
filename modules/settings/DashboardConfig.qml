import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../dashboard/DashboardCustomTabPolicy.js" as TabPolicy

ContentPage {
    id: root
    settingsPageIndex: 16
    settingsPageName: Translation.tr("Dashboard")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    property string activeSection: "general"
    readonly property var tabChoices: {
        const choices = [
            {displayName:Translation.tr("Dashboard"),icon:"dashboard",value:"dashboard"},
            {displayName:Translation.tr("Weekly Planner"),icon:"calendar_month",value:"weeklyPlanner"}
        ]
        if (Config.options?.dashboard?.music?.enable ?? true)
            choices.splice(1,0,{displayName:Translation.tr("Music"),icon:"library_music",value:"music"})
        for (const tab of TabPolicy.tabs(Config.options?.dashboard?.customTabs))
            choices.push({displayName:tab.name,icon:"tab",value:tab.id})
        return choices
    }

    SettingsTaskNavigator {
        visible: root.isIiActive
        showTabBar: false
        icon: "space_dashboard"
        title: Translation.tr("Dashboard")
        description: Translation.tr("Tune the Dashboard surface, then arrange and resize modules directly on its canvas.")
        summary: Translation.tr("Behavior · appearance · canvas · music")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("General"), icon: "tune", value: "general" },
            { displayName: Translation.tr("Appearance"), icon: "palette", value: "appearance" },
            { displayName: Translation.tr("Canvas"), icon: "dashboard_customize", value: "layout" },
            { displayName: Translation.tr("Music"), icon: "library_music", value: "music" }
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

    GridLayout {
        objectName: "dashboardTwoColumnGrid"
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 14
        visible: root.isIiActive

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 14

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "general"
                visible: root.isIiActive
                expanded: true
                icon: "space_dashboard"
                title: Translation.tr("General")

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
                    ConfigSpinBox {
                        text: Translation.tr("Return to default tab after (minutes)")
                        description: Translation.tr("Only on the next Dashboard open. Zero disables automatic tab return.")
                        value: Config.options?.dashboard?.inactiveMinutes ?? 0
                        from: 0
                        to: 240
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("dashboard.inactiveMinutes",value)
                    }
                    ConfigSpinBox {
                        text: Translation.tr("Panel width (% of screen)")
                        description: Translation.tr("Shared width for the Dashboard and launcher Dashboard")
                        value: Math.round((Config.options?.dashboard?.widthRatio ?? 0.72) * 100)
                        from: 40
                        to: 90
                        stepSize: 2
                        onValueChanged: Config.setNestedValue("dashboard.widthRatio", value / 100)
                    }
                    ConfigSpinBox {
                        text: Translation.tr("Panel height (% of screen)")
                        description: Translation.tr("Maximum Dashboard height; widgets never add Dashboard scrolling")
                        value: Math.round((Config.options?.dashboard?.heightRatio ?? 0.72) * 100)
                        from: 45
                        to: 90
                        stepSize: 2
                        onValueChanged: Config.setNestedValue("dashboard.heightRatio", value / 100)
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Welcome subtitle")
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Custom phrase under the greeting (optional)")
                        text: Config.options?.dashboard?.subtitle ?? ""
                        onTextChanged: {
                            Qt.callLater(() => {
                                Config.setNestedValue("dashboard.subtitle", text)
                            });
                        }
                    }
                }

                ContentSubsection {
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
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Powers the “GitHub activity” widget above. Leave empty to disable the contribution graph.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }
                }

                SettingsGroup {
                    RowLayout {
                        spacing: 6
                        Layout.fillWidth: true
                        MaterialSymbol {
                            text: "keyboard_command_key"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Toggle with a keybinding running: %1").arg("alis ipc dashboard toggle")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "appearance"
                visible: root.isIiActive
                expanded: true
                icon: "palette"
                title: Translation.tr("Appearance")

                SettingsGroup {
                    ConfigSpinBox {
                        text: Translation.tr("Card opacity (%)")
                        value: Math.round((Config.options?.dashboard?.appearance?.cardOpacity ?? 1) * 100)
                        from: 30
                        to: 100
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("dashboard.appearance.cardOpacity", value / 100)
                    }
                    ConfigSwitch {
                        text: Translation.tr("Show card titles")
                        description: Translation.tr("Icon and name header on each widget card")
                        checked: Config.options?.dashboard?.appearance?.showCardTitles ?? true
                        onCheckedChanged: Config.setNestedValue("dashboard.appearance.showCardTitles", checked)
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
                settingsTaskSection: "layout"
                visible: root.isIiActive
                expanded: true
                icon: "dashboard_customize"
                title: Translation.tr("Canvas & grid")

                SettingsGroup {
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Dashboard → Edit widgets lets you move or resize modules; outside Edit mode, layout is locked.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.WordWrap
                    }

                    ConfigSwitch {
                        text: Translation.tr("Snap modules to grid")
                        description: Translation.tr("Snap moved or resized modules to the grid on release.")
                        checked: Config.options?.dashboard?.canvas?.snap ?? true
                        onCheckedChanged:
                            Config.setNestedValue("dashboard.canvas.snap", checked)
                    }

                    ConfigSwitch {
                        text: Translation.tr("Auto-adjust affected module sizes")
                        description: Translation.tr("Resizing can adjust neighbors; moving modules never changes their sizes.")
                        checked:
                            Config.options?.dashboard?.canvas?.autoAdjustSize ?? true
                        onCheckedChanged:
                            Config.setNestedValue(
                        "dashboard.canvas.autoAdjustSize", checked)
                    }

                    ContentSubsection {
                        title: Translation.tr("Grid style")
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
                        description: Translation.tr("Smaller cells allow finer placement; larger cells produce stronger alignment")
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
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "music"
                visible: root.isIiActive
                expanded: true
                icon: "library_music"
                title: Translation.tr("Local Music")
                DashboardMusicSettings { Layout.fillWidth: true }
            }
        }
    }
}
