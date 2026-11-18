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
            Config.options?.abyss?.modules, kind) === "module";
    }

    settingsPageIndex: embedded ? 2 : 23
    settingsPageName: Translation.tr("Sidebars & Overview")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    property string activeSection: "left_right"

    Component.onCompleted: {
        if (Config.options?.overview?.workspaceHover?.enable === false)
            Config.setNestedValue("overview.workspaceHover.enable", true);
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
        id: sizing
        required property string role
        readonly property var state: ShellLayoutController.currentState(role, "")
        WindowDialogSlider {
            text: "Width"
            Layout.fillWidth: true
            from: 320
            to: 900
            stepSize: 1
            value: sizing.state.width
            valueText: Math.round(value) + " px"
            onMoved: ShellLayoutController.setProperty(sizing.role, "thickness", value, "")
        }
        WindowDialogSlider {
            text: "Height"
            Layout.fillWidth: true
            from: 320
            to: 2160
            stepSize: 1
            value: sizing.state.customHeight
            valueText: Math.round(value) + " px"
            onMoved: {
                if (sizing.state.sizeMode !== "custom") {
                    ShellLayoutController.setProperty(sizing.role, "sizeMode", "custom", "");
                    if (sizing.role === "featureSidebar")
                        Config.setNestedValue("sidebar.collapseWidgetsTab", false);
                }
                ShellLayoutController.setProperty(sizing.role, "height", value, "");
            }
        }
    }

    SettingsCardSection {
        id: leftSidebarCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "first_page"
        title: Translation.tr("Left sidebar")

        SettingsGroup {
            SidebarSize { role: "featureSidebar"; title: "Left Sidebar size" }

            SettingsDivider {}

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

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "build"
                        text: Translation.tr("Tools")
                        checked: Config.options.sidebar?.tools?.enable ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.tools.enable", checked)
                        StyledToolTip {
                            text: Translation.tr("Niri debug options and quick actions")
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "bolt"
                        text: Translation.tr("Keep loaded")
                        checked: Config.options?.sidebar?.keepLeftSidebarLoaded ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.keepLeftSidebarLoaded", checked)
                        StyledToolTip {
                            text: Translation.tr("Keep left sidebar loaded in memory for instant opening")
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: rightSidebarCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "last_page"
        title: Translation.tr("Right sidebar")

        SettingsGroup {
            SidebarSize { role: "systemSidebar"; title: "Right Sidebar size" }

            SettingsDivider {}

            ContentSubsection {
                id: rightSidebarWidgets
                title: Translation.tr("Widgets")
                tooltip: Translation.tr("Toggle which widgets appear in the right sidebar")

                readonly property var defaults: ["calculator", "sysmon"]

                function isEnabled(widgetId) {
                    return (Config.options?.sidebar?.right?.enabledWidgets ?? defaults).includes(widgetId)
                }

                function setWidget(widgetId, active) {
                    _log(`[RightSidebar] setWidget(${widgetId}, ${active})`)
                    let current = [...(Config.options?.sidebar?.right?.enabledWidgets ?? defaults)]
                    _log(`[RightSidebar] Current widgets:`, JSON.stringify(current))

                    const index = current.indexOf(widgetId)
                    // includes() uses SameValueZero while indexOf() uses strict
                    // equality. Preserve the old malformed NaN behavior without
                    // repeating a full membership scan for normal widget ids.
                    const included = index !== -1
                        || (widgetId !== widgetId && current.includes(widgetId))

                    if (active && !included) {
                        current.push(widgetId)
                        Config.setNestedValue("sidebar.right.enabledWidgets", current)
                    } else if (!active && included) {
                        current.splice(index, 1)
                        Config.setNestedValue("sidebar.right.enabledWidgets", current)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "calculate"
                        text: Translation.tr("Calculator")
                        Component.onCompleted: checked = rightSidebarWidgets.isEnabled("calculator")
                        onClicked: {
                            rightSidebarWidgets.setWidget("calculator", checked)
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "monitor_heart"
                        text: Translation.tr("System Monitor")
                        Component.onCompleted: checked = rightSidebarWidgets.isEnabled("sysmon")
                        onClicked: {
                            rightSidebarWidgets.setWidget("sysmon", checked)
                        }
                    }
                }
            }

            SettingsDivider {}

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

                ConfigRow {
                    uniform: true
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

                    SettingsSwitch {
                        buttonIcon: "bolt"
                        text: Translation.tr("Keep loaded")
                        checked: Config.options?.sidebar?.keepRightSidebarLoaded ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.keepRightSidebarLoaded", checked)
                        StyledToolTip {
                            text: Translation.tr("Keep right sidebar loaded in memory for instant opening")
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: leftEdgebarCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "dock_to_right"
        title: Translation.tr("Left edgebar")

        SettingsGroup {
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

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Left Edgebar size")
                WindowDialogSlider {
                    text: "Width"
                    Layout.fillWidth: true
                    from: 280
                    to: 720
                    stepSize: 10
                    value: Config.options?.quickNotes?.popupWidth ?? 420
                    valueText: Math.round(value) + " px"
                    onMoved: Config.setNestedValue("quickNotes.popupWidth", value)
                }
                WindowDialogSlider {
                    text: "Height"
                    Layout.fillWidth: true
                    from: 300
                    to: 640
                    stepSize: 10
                    value: Config.options?.quickNotes?.popupHeight ?? 300
                    valueText: Math.round(value) + " px"
                    onMoved: Config.setNestedValue("quickNotes.popupHeight", value)
                }
                // contract: Config.setNestedValue("quickNotes.popupWidth",value) Config.setNestedValue("quickNotes.popupHeight",value)
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "timer"
                    text: Translation.tr("Hover delay (ms)")
                    value: Config.options?.quickNotes?.hoverDelayMs ?? 220
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("quickNotes.hoverDelayMs", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "rounded_corner"
                    text: Translation.tr("Corner zone (px)")
                    value: Config.options?.quickNotes?.cornerSize ?? 14
                    from: 4
                    to: 48
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("quickNotes.cornerSize", value)
                }
            }
        }
    }

    SettingsCardSection {
        id: rightEdgebarCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "dock_to_left"
        title: Translation.tr("Right edgebar")

        SettingsGroup {
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

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Right Edgebar size")
                WindowDialogSlider {
                    text: "Width"
                    Layout.fillWidth: true
                    from: 320
                    to: 760
                    stepSize: 10
                    value: Config.options?.notificationCenter?.popupWidth ?? 420
                    valueText: Math.round(value) + " px"
                    onMoved: Config.setNestedValue("notificationCenter.popupWidth", value)
                }
                WindowDialogSlider {
                    text: "Height"
                    Layout.fillWidth: true
                    from: 260
                    to: 900
                    stepSize: 10
                    value: Config.options?.notificationCenter?.popupHeight ?? 560
                    valueText: Math.round(value) + " px"
                    onMoved: Config.setNestedValue("notificationCenter.popupHeight", value)
                }
                // contract: Config.setNestedValue("notificationCenter.popupWidth",value) Config.setNestedValue("notificationCenter.popupHeight",value)
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "timer"
                    text: Translation.tr("Hover delay (ms)")
                    value: Config.options?.notificationCenter?.hoverDelayMs ?? 220
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("notificationCenter.hoverDelayMs", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "timer_off"
                    text: Translation.tr("Close grace (ms)")
                    value: Config.options?.notificationCenter?.closeGraceMs ?? 280
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("notificationCenter.closeGraceMs", value)
                }
            }
        }
    }

    SettingsCardSection {
        id: edgeAndCornerTriggersCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "rounded_corner"
        title: Translation.tr("Edge & Corner Triggers")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Side edge open")
                tooltip: Config.options?.panelFamily === "abyss"
                    ? "Hover a side Screen Edge; enter the sidebar to keep it open."
                    : Translation.tr("Open the left or right sidebar by touching that screen edge")

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "dock_to_left"
                        text: Translation.tr("Hover screen edges")
                        checked: Config.options?.panelFamily === "abyss"
                            ? (Config.options?.abyss?.sidebars?.hoverEnabled ?? true)
                            : (Config.options?.sidebar?.edgeOpen?.enable ?? false)
                        onCheckedChanged: Config.setNestedValue(
                            Config.options?.panelFamily === "abyss"
                                ? "abyss.sidebars.hoverEnabled"
                                : "sidebar.edgeOpen.enable",
                            checked)
                    }

                    ConfigSpinBox {
                        icon: "width"
                        text: Translation.tr("Trigger width (px)")
                        value: Config.options?.sidebar?.edgeOpen?.regionWidth ?? 2
                        from: 1
                        to: 12
                        stepSize: 1
                        enabled: Config.options?.panelFamily === "abyss"
                            ? (Config.options?.abyss?.sidebars?.hoverEnabled ?? true)
                            : (Config.options?.sidebar?.edgeOpen?.enable ?? false)
                        opacity: enabled ? 1 : 0.5
                        onValueChanged: Config.setNestedValue("sidebar.edgeOpen.regionWidth", value)
                    }
                }
            }

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Corner open")
                tooltip: Translation.tr("Open sidebars from screen corners.")

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options?.sidebar?.cornerOpen?.enable ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.cornerOpen.enable", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "ads_click"
                        text: Translation.tr("Hover without click")
                        checked: Config.options?.sidebar?.cornerOpen?.clickless ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.cornerOpen.clickless", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "vertical_align_bottom"
                        text: Translation.tr("Place at bottom")
                        checked: Config.options?.sidebar?.cornerOpen?.bottom ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.cornerOpen.bottom", checked)
                        StyledToolTip {
                            text: Translation.tr("Place the corners to trigger at the bottom")
                        }
                    }

                    SettingsSwitch {
                        buttonIcon: "unfold_more_double"
                        text: Translation.tr("Value scroll")
                        checked: Config.options?.sidebar?.cornerOpen?.valueScroll ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.cornerOpen.valueScroll", checked)
                        StyledToolTip {
                            text: Translation.tr("Brightness and volume")
                        }
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "rounded_corner"
                        text: Translation.tr("Corner-end trigger")
                        enabled: !(Config.options?.sidebar?.cornerOpen?.clickless ?? false)
                        checked: Config.options?.sidebar?.cornerOpen?.clicklessCornerEnd ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.cornerOpen.clicklessCornerEnd", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "visibility"
                        text: Translation.tr("Visualize region")
                        checked: Config.options?.sidebar?.cornerOpen?.visualize ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.cornerOpen.visualize", checked)
                        StyledToolTip {
                            text: Translation.tr("Show a colored overlay indicating the corner trigger areas (debug)")
                        }
                    }
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        icon: "arrow_range"
                        text: Translation.tr("Region width")
                        value: Config.options?.sidebar?.cornerOpen?.cornerRegionWidth ?? 250
                        from: 1
                        to: 300
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("sidebar.cornerOpen.cornerRegionWidth", value)
                    }

                    ConfigSpinBox {
                        icon: "height"
                        text: Translation.tr("Region height")
                        value: Config.options?.sidebar?.cornerOpen?.cornerRegionHeight ?? 5
                        from: 1
                        to: 300
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("sidebar.cornerOpen.cornerRegionHeight", value)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: overviewTriggerGridCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: root.isIiActive
        expanded: true
        icon: "overview_key"
        title: Translation.tr("Overview Trigger & Grid")

        SettingsGroup {
            // contract: Translation.tr("Hover timing (ms)") Translation.tr("Grid layout")
            ContentSubsection {
                title: Translation.tr("Grid & hover timing")

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "timer"
                        text: Translation.tr("Open (ms)")
                        // contract: Translation.tr("Open")
                        value: Config.options?.overview?.workspaceHover?.delayMs ?? 280
                        from: 0
                        to: 1200
                        stepSize: 20
                        onValueChanged: Config.setNestedValue("overview.workspaceHover.delayMs", value)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "timer_off"
                        text: Translation.tr("Close (ms)")
                        // contract: Translation.tr("Close")
                        value: Config.options?.overview?.workspaceHover?.closeDelayMs ?? 220
                        from: 0
                        to: 1200
                        stepSize: 20
                        onValueChanged: Config.setNestedValue("overview.workspaceHover.closeDelayMs", value)
                    }
                }

                SettingsDivider {}

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
                        onValueChanged: Config.setNestedValue("overview.rows", value)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "splitscreen_right"
                        text: Translation.tr("Columns")
                        value: Config.options?.overview?.columns ?? 5
                        from: 1
                        to: 8
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("overview.columns", value)
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
                        onValueChanged: Config.setNestedValue("overview.scale", value / 100)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "grid_3x3"
                        text: Translation.tr("Gap (px)")
                        value: Config.options?.overview?.workspaceSpacing ?? 5
                        from: 0
                        to: 32
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("overview.workspaceSpacing", value)
                    }
                }

                SettingsDivider {}

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "ads_click"
                        text: Translation.tr("Keep open on click")
                        checked: Config.options?.overview?.keepOverviewOpenOnWindowClick ?? true
                        onCheckedChanged: Config.setNestedValue("overview.keepOverviewOpenOnWindowClick", checked)
                    }

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "move_up"
                        text: Translation.tr("Close after move")
                        checked: Config.options?.overview?.closeAfterWindowMove ?? true
                        onCheckedChanged: Config.setNestedValue("overview.closeAfterWindowMove", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "highlight_mouse_cursor"
                        text: Translation.tr("Hover popup")
                        // contract: Translation.tr("Workspace hover popup")
                        checked: Config.options?.overview?.workspaceHover?.enable ?? true
                        onCheckedChanged: Config.setNestedValue("overview.workspaceHover.enable", checked)
                    }

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "apps"
                        text: Translation.tr("All-apps grid")
                        // contract: Translation.tr("All-apps launcher grid")
                        checked: Config.options?.overview?.allAppsGrid ?? false
                        onCheckedChanged: Config.setNestedValue("overview.allAppsGrid", checked)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: overviewAppearanceCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
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
                        onCheckedChanged: Config.setNestedValue("overview.showPreviews", checked)
                    }

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "looks_one"
                        text: Translation.tr("Workspace numbers")
                        checked: Config.options?.overview?.showWorkspaceNumbers ?? false
                        onCheckedChanged: Config.setNestedValue("overview.showWorkspaceNumbers", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "center_focus_strong"
                        text: Translation.tr("Center app icons")
                        checked: Config.options?.overview?.centerIcons ?? true
                        onCheckedChanged: Config.setNestedValue("overview.centerIcons", checked)
                    }

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "blur_on"
                        text: Translation.tr("Blur wallpaper")
                        checked: Config.options?.overview?.backgroundBlurEnable !== false
                        onCheckedChanged: Config.setNestedValue("overview.backgroundBlurEnable", checked)
                    }
                }

                ConfigRow {
                    uniform: true

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

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "web_asset"
                        text: Translation.tr("Respect bar margin")
                        checked: Config.options?.overview?.respectBar ?? true
                        onCheckedChanged: Config.setNestedValue("overview.respectBar", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "animation"
                        text: Translation.tr("Focus animations")
                        checked: Config.options?.overview?.focusAnimationEnable ?? true
                        onCheckedChanged: Config.setNestedValue("overview.focusAnimationEnable", checked)
                    }

                    SettingsSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "open_in_new"
                        text: Translation.tr("Jump on open")
                        checked: Config.options?.overview?.switchToWorkspaceOnOpen ?? false
                        onCheckedChanged: Config.setNestedValue("overview.switchToWorkspaceOnOpen", checked)
                    }
                }

                SettingsDivider {}

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "opacity"
                        text: Translation.tr("Dim (%)")
                        // contract: Translation.tr("Workspace dim (%)")
                        value: Config.options?.overview?.backgroundDim ?? 35
                        from: 0
                        to: 80
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("overview.backgroundDim", value)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "padding"
                        text: Translation.tr("Tile gap (px)")
                        // contract: Translation.tr("Window margin (px)")
                        value: Config.options?.overview?.windowTileMargin ?? 6
                        from: 0
                        to: 24
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("overview.windowTileMargin", value)
                    }
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "mouse"
                        text: Translation.tr("Scroll steps")
                        value: Config.options?.overview?.scrollWorkspaceSteps ?? 2
                        from: 1
                        to: 10
                        stepSize: 1
                        onValueChanged: Config.setNestedValue("overview.scrollWorkspaceSteps", value)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "motion_photos_on"
                        text: Translation.tr("Focus (ms)")
                        // contract: Translation.tr("Focus motion (ms)")
                        value: Config.options?.overview?.focusAnimationDurationMs ?? 180
                        from: 60
                        to: 400
                        stepSize: 20
                        onValueChanged: Config.setNestedValue("overview.focusAnimationDurationMs", value)
                    }
                }
            }
        }
    }
}
