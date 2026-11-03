import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../dashboard/DashboardCustomTabPolicy.js" as TabPolicy

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    settingsPageIndex: embedded ? 2 : 22
    settingsPageName: Translation.tr("Dock & Dashboard")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
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
        visible: !root.embedded
        showTabBar: false
        showIntro: false
        icon: "call_to_action"
        title: Translation.tr("Dock & Dashboard")
        description: Translation.tr("Dock behavior, window indicators, dashboard hub, local music and Spaced Repetition.")
        summary: Translation.tr("Dock & Indicators · Dashboard · Spaced Repetition")
    }

    GridLayout {
        objectName: "dockTwoColumnGrid"
        Layout.fillWidth: true
        visible: root.isIiActive
        columns: 1
        uniformCellWidths: false
        columnSpacing: 14
        rowSpacing: 14

        SettingsCardSection {
            _declarationOrder: 0
            bentoColumn: "full"
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            expanded: true
            icon: "call_to_action"
            title: Translation.tr("Dock & Indicators")

            SettingsGroup {
                ConfigRow {
                    id: dockPrimaryToggles
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.dock.enable
                        onCheckedChanged: Config.setNestedValue("dock.enable", checked)
                        StyledToolTip { text: Translation.tr("Show the application dock") }
                    }

                    SettingsSwitch {
                        buttonIcon: "dashboard"
                        text: Translation.tr("Show Dashboard icon")
                        checked: Config.options?.dock?.showDashboardButton ?? true
                        onCheckedChanged: Config.setNestedValue("dock.showDashboardButton", checked)
                        StyledToolTip {
                            text: Translation.tr("Show the Dashboard / Overview launcher button in the Dock")
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "colors"
                        text: Translation.tr("Tint app icons")
                        checked: Config.options.dock.monochromeIcons
                        onCheckedChanged: Config.setNestedValue("dock.monochromeIcons", checked)
                        StyledToolTip {
                            text: Translation.tr("Apply accent color tint to dock app icons")
                        }
                    }
                }

                ConfigRow {
                    uniform: true
                    ContentSubsection {
                        title: Translation.tr("Dock position")

                        ConfigSelectionArray {
                            currentValue: Config.options?.dock?.position ?? "bottom"
                            onSelected: newValue => {
                                Config.setNestedValue('dock.position', newValue);
                            }
                            options: [
                                { displayName: Translation.tr("Left"), icon: "arrow_back", value: "left" },
                                { displayName: Translation.tr("Top"), icon: "arrow_upward", value: "top" },
                                { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: "bottom" },
                                { displayName: Translation.tr("Right"), icon: "arrow_forward", value: "right" }
                            ]
                        }
                    }
                    ContentSubsection {
                        title: Translation.tr("Reveal behavior")
                        tooltip: Translation.tr("Hover reveals the Dock at the edge; Empty workspace shows it on an empty desktop.")

                        ConfigSelectionArray {
                            currentValue: Config.options?.dock?.hoverToReveal ?? true
                            onSelected: newValue => {
                                Config.setNestedValue('dock.hoverToReveal', newValue);
                            }
                            options: [
                                { displayName: Translation.tr("Hover"), icon: "highlight_mouse_cursor", value: true },
                                { displayName: Translation.tr("Empty workspace"), icon: "desktop_windows", value: false }
                            ]
                        }
                        ConfigRow {
                            id: revealModeToggles
                            uniform: true

                            SettingsSwitch {
                                buttonIcon: "desktop_windows"
                                text: Translation.tr("Show on desktop")
                                enabled: !(Config.options?.dock?.hoverToReveal ?? true)
                                checked: Config.options?.dock?.showOnDesktop ?? true
                                onCheckedChanged: Config.setNestedValue("dock.showOnDesktop", checked)
                                StyledToolTip {
                                    text: Translation.tr("Show dock when no window is focused (Empty workspace mode only)")
                                }
                            }

                            SettingsSwitch {
                                buttonIcon: "keep"
                                text: Translation.tr("Pinned on startup")
                                enabled: !(Config.options?.dock?.hoverToReveal ?? true)
                                checked: Config.options.dock.pinnedOnStartup
                                onCheckedChanged: Config.setNestedValue("dock.pinnedOnStartup", checked)
                                StyledToolTip {
                                    text: Translation.tr("Keep dock visible at all times (Empty workspace mode only)")
                                }
                            }
                        }
                    }
                }

                ConfigRow {
                    id: dockSecondaryToggles
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "widgets"
                        visible: Config.options?.panelFamily !== "abyss"
                        text: Translation.tr("Show dock background")
                        checked: Config.options.dock.showBackground
                        onCheckedChanged: Config.setNestedValue("dock.showBackground", checked)
                        StyledToolTip {
                            text: Translation.tr("Show a background behind the dock")
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "splitscreen"
                        text: Translation.tr("Separate pinned from running")
                        checked: Config.options?.dock?.separatePinnedFromRunning ?? true
                        onCheckedChanged: Config.setNestedValue("dock.separatePinnedFromRunning", checked)
                        StyledToolTip {
                            text: Translation.tr("Show pinned-only apps on the left, running apps on the right with a separator")
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "notifications"
                        text: Translation.tr("Notification badges")
                        checked: Config.options?.dock?.notificationBadge ?? true
                        onCheckedChanged: Config.setNestedValue("dock.notificationBadge", checked)
                        StyledToolTip {
                            text: Translation.tr("Show the number of pending notifications on each app icon")
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Dimensions & Window Indicators")

                    ConfigRow {
                        uniform: true
                        ConfigSpinBox {
                            icon: "height"
                            text: Translation.tr("Dock height (px)")
                            value: Config.options.dock.height ?? 60
                            from: 40
                            to: 100
                            stepSize: 5
                            onValueChanged: {
                                Config.setNestedValue("dock.height", value);
                            }
                        }

                        ConfigSpinBox {
                            icon: "aspect_ratio"
                            text: Translation.tr("Icon size (px)")
                            value: Config.options.dock.iconSize ?? 35
                            from: 20
                            to: 60
                            stepSize: 5
                            onValueChanged: {
                                Config.setNestedValue("dock.iconSize", value);
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        SettingsSwitch {
                            buttonIcon: "my_location"
                            text: Translation.tr("Highlight focused window")
                            checked: Config.options.dock.smartIndicator !== false
                            onCheckedChanged: {
                                Config.setNestedValue("dock.smartIndicator", checked);
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "more_horiz"
                            text: Translation.tr("Dots for inactive apps")
                            checked: Config.options.dock.showAllWindowDots !== false
                            onCheckedChanged: {
                                Config.setNestedValue("dock.showAllWindowDots", checked);
                            }
                        }
                    }
                }
            }
        }

        SettingsCardSection {
            _declarationOrder: 1
            bentoColumn: "full"
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
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
            _declarationOrder: 2
            bentoColumn: "full"
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            expanded: true
            icon: "school"
            title: Translation.tr("Spaced Repetition")

            DashboardSpacedRepetitionSettings {
                Layout.fillWidth: true
            }
        }
    }
}
