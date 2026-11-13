import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.settings
import "../abyss/looks/AbyssLayout.js" as ModuleLayout

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    // A launcher icon is a presentation MODE, not a paint-only toggle.
    // Turning it off unmounts the module and restores the legacy Edgebar.
    function unifiedLauncherIconShown(kind): bool {
        return ModuleLayout.unifiedLauncherMode(
            Config.options?.abyss?.modules,kind)==="module"
    }

    settingsPageIndex: embedded ? 2 : 23
    settingsPageName: Translation.tr("Sidebars & Overview")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"

    property string activeSection: "left_right"

    Component.onCompleted: {
        if (Config.options?.overview?.workspaceHover?.enable === false)
            Config.setNestedValue("overview.workspaceHover.enable", true)
    }

    SettingsTaskNavigator {
        showTabBar: false
        showIntro: false
        icon: "side_navigation"
        title: Translation.tr("Sidebars & Overview")
        description: Translation.tr("Sidebar layout, edgebars and workspace overview.")
        summary: Translation.tr("Sidebars · Edgebars · Overview")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Left & Right Sidebars"), icon: "side_navigation", value: "left_right" },
            { displayName: Translation.tr("Layout & Edge Trigger"), icon: "tune", value: "general" }
        ]
    }

    component SidebarSize: ContentSubsection {
        id:sizing
        required property string role
        readonly property var state:ShellLayoutController.currentState(role,"")
        WindowDialogSlider {
            text:"Width";Layout.fillWidth:true;from:320;to:900;stepSize:1
            value:sizing.state.width;valueText:Math.round(value)+" px"
            onMoved:ShellLayoutController.setProperty(sizing.role,"thickness",value,"")
        }
        WindowDialogSlider {
            text:"Height";Layout.fillWidth:true;from:320;to:2160;stepSize:1
            value:sizing.state.customHeight;valueText:Math.round(value)+" px"
            onMoved:{
                if (sizing.state.sizeMode !== "custom") {
                    ShellLayoutController.setProperty(sizing.role,"sizeMode","custom","")
                    if (sizing.role === "featureSidebar")
                        Config.setNestedValue("sidebar.collapseWidgetsTab", false)
                }
                ShellLayoutController.setProperty(sizing.role,"height",value,"")
            }
        }
    }

    GridLayout {
        id: sidebarsGrid
        Layout.fillWidth: true
        columns: 2
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 14
        visible: root.isIiActive && children.length > 0

        SettingsCardSection {
            id: leftSidebarCard
            _declarationOrder: 0
            bentoColumn: "left"
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
            expanded: true
            icon: "first_page"
            title: Translation.tr("Left sidebar")

            SettingsGroup {
                Layout.fillHeight: true
                SidebarSize { role:"featureSidebar";title:"Left Sidebar size" }

                ContentSubsection {
                    title: Translation.tr("Left Sidebar")
                    tooltip: Translation.tr("Choose which tabs appear in the left sidebar")

                    ConfigRow {
                        uniform: true
                        SettingsSwitch {
                            buttonIcon: "translate"
                            text: Translation.tr("Translator")
                            checked: Config.options.sidebar?.translator?.enable ?? false
                            onCheckedChanged: Config.setNestedValue("sidebar.translator.enable", checked)
                            StyledToolTip {
                                text: Translation.tr("Translate text between languages")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "newspaper"
                            text: Translation.tr("News")
                            checked: Config.options.sidebar?.news?.enable ?? true
                            onCheckedChanged: Config.setNestedValue("sidebar.news.enable", checked)
                            StyledToolTip {
                                text: Translation.tr("Local and topic headlines from Google News")
                            }
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "build"
                        text: Translation.tr("Tools")
                        checked: Config.options.sidebar?.tools?.enable ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.tools.enable", checked)
                        StyledToolTip {
                            text: Translation.tr("Niri debug options and quick actions")
                        }
                    }
                }
            }
        }

        SettingsCardSection {
            id: rightSidebarCard
            _declarationOrder: 1
            bentoColumn: "right"
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
            expanded: true
            icon: "last_page"
            title: Translation.tr("Right sidebar")

            SettingsGroup {
                Layout.fillHeight: true
                SidebarSize { role:"systemSidebar";title:"Right Sidebar size" }

                ContentSubsection {
                    title: Translation.tr("Sliders")
                    tooltip: Translation.tr("Choose which sliders appear in the right sidebar")

                    ConfigRow {
                        uniform: true
                        SettingsSwitch {
                            buttonIcon: "brightness_6"
                            text: Translation.tr("Brightness")
                            checked: Config.options.sidebar.quickSliders.showBrightness
                            onCheckedChanged: {
                                if (checked && !(Config.options?.sidebar?.quickSliders?.enable ?? true))
                                    Config.setNestedValue("sidebar.quickSliders.enable", true);
                                Config.setNestedValue("sidebar.quickSliders.showBrightness", checked);
                            }
                            StyledToolTip {
                                text: Translation.tr("Show brightness slider")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "volume_up"
                            text: Translation.tr("Volume")
                            checked: Config.options.sidebar.quickSliders.showVolume
                            onCheckedChanged: {
                                if (checked && !(Config.options?.sidebar?.quickSliders?.enable ?? true))
                                    Config.setNestedValue("sidebar.quickSliders.enable", true);
                                Config.setNestedValue("sidebar.quickSliders.showVolume", checked);
                            }
                            StyledToolTip {
                                text: Translation.tr("Show volume slider")
                            }
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "mic"
                        text: Translation.tr("Microphone")
                        checked: Config.options.sidebar.quickSliders.showMic
                        onCheckedChanged: {
                            if (checked && !(Config.options?.sidebar?.quickSliders?.enable ?? true))
                                Config.setNestedValue("sidebar.quickSliders.enable", true);
                            Config.setNestedValue("sidebar.quickSliders.showMic", checked);
                        }
                        StyledToolTip {
                            text: Translation.tr("Show microphone input level slider")
                        }
                    }
                }
            }
        }

        SettingsCardSection {
            id: leftEdgebarCard
            _declarationOrder: 2
            bentoColumn: "left"
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
            expanded: true
            icon: "dock_to_right"
            title: Translation.tr("Left edgebar")

            SettingsGroup {
                Layout.fillHeight: true
                SettingsSwitch {
                    id: quickNotesTimersIconToggle
                    objectName: "abyssSettingsQuickNotesTimersIcon"
                    buttonIcon: "sticky_note_2"
                    text: Translation.tr("Convert to Screen Edge module")
                    checked: root.unifiedLauncherIconShown("notesTimers")
                    // Supersedes legacy abyss.modules.iconVisibility.notesTimers
                    // Off: remove this module hover and use Corner Edgebar.
                    onCheckedChanged: {
                        if (checked !== root.unifiedLauncherIconShown("notesTimers"))
                            Config.setNestedValue("abyss.modules.notesTimersMode",checked ? "module" : "edgebar");
                    }
                    StyledToolTip {
                        text: Translation.tr("Show Quick Notes & Timers icon on Screen Edge instead of Left Edgebar hover")
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Left Edgebar size")
                    WindowDialogSlider {
                        text: "Width"
                        Layout.fillWidth: true
                        from: 280; to: 720; stepSize: 10
                        value: Config.options?.quickNotes?.popupWidth ?? 420
                        valueText: Math.round(value) + " px"
                        onMoved: Config.setNestedValue("quickNotes.popupWidth",value)
                    }
                    WindowDialogSlider {
                        text: "Height"
                        Layout.fillWidth: true
                        from: 300; to: 640; stepSize: 10
                        value: Config.options?.quickNotes?.popupHeight ?? 300
                        valueText: Math.round(value) + " px"
                        onMoved: Config.setNestedValue("quickNotes.popupHeight",value)
                    }
                }
            }
        }

        SettingsCardSection {
            id: rightEdgebarCard
            _declarationOrder: 3
            bentoColumn: "right"
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
            expanded: true
            icon: "dock_to_left"
            title: Translation.tr("Right edgebar")

            SettingsGroup {
                Layout.fillHeight: true
                SettingsSwitch {
                    id: notificationActivityIconToggle
                    objectName: "abyssSettingsNotificationActivityIcon"
                    buttonIcon: "notifications"
                    text: Translation.tr("Convert to Screen Edge module")
                    checked: root.unifiedLauncherIconShown("notificationActivity")
                    // Supersedes legacy abyss.modules.iconVisibility.notificationActivity
                    // Off: remove this module hover and use Corner Edgebar.
                    onCheckedChanged: {
                        if (checked !== root.unifiedLauncherIconShown("notificationActivity"))
                            Config.setNestedValue("abyss.modules.notificationActivityMode",checked ? "module" : "edgebar");
                    }
                    StyledToolTip {
                        text: Translation.tr("Show Notifications & Activities icon on Screen Edge instead of Right Edgebar hover")
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Right Edgebar size")
                    WindowDialogSlider {
                        text: "Width"
                        Layout.fillWidth: true
                        from: 320; to: 760; stepSize: 10
                        value: Config.options?.notificationCenter?.popupWidth ?? 420
                        valueText: Math.round(value) + " px"
                        onMoved: Config.setNestedValue("notificationCenter.popupWidth",value)
                    }
                    WindowDialogSlider {
                        text: "Height"
                        Layout.fillWidth: true
                        from: 260; to: 900; stepSize: 10
                        value: Config.options?.notificationCenter?.popupHeight ?? 560
                        valueText: Math.round(value) + " px"
                        onMoved: Config.setNestedValue("notificationCenter.popupHeight",value)
                    }
                }
            }
        }

        SettingsCardSection {
            id: overviewTriggerGridCard
            _declarationOrder: 4
            bentoColumn: "left"
            _consumesBentoExtraHeight: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
            expanded: true
            icon: "overview_key"
            title: Translation.tr("Overview Trigger & Grid")

            SettingsGroup {
                Layout.fillHeight: true
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
            id: overviewAppearanceCard
            _declarationOrder: 5
            bentoColumn: "right"
            _consumesBentoExtraHeight: true
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            visible: root.isIiActive
            expanded: true
            icon: "preview"
            title: Translation.tr("Overview Appearance")

            SettingsGroup {
                Layout.fillHeight: true
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
                        Layout.topMargin: 12

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

                    ConfigRow {
                        uniform: true
                        Layout.topMargin: 12

                        SettingsSwitch {
                            Layout.fillWidth: true
                            buttonIcon: "screen_share"
                            text: Translation.tr("Active screen only")
                            checked: Config.options?.overview?.activeScreenOnly ?? true
                            onCheckedChanged: Config.setNestedValue("overview.activeScreenOnly", checked)
                            StyledToolTip {
                                text: Translation.tr("Open the overview on the monitor where it was invoked")
                            }
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
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
                Item { Layout.fillHeight: true }
            }
        }
    }

}
