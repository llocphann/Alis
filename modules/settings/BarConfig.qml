import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: embedded ? 2 : 2
    settingsPageName: Translation.tr("Bar")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    readonly property bool abyssContent: root.embedded && Config.options?.panelFamily === "abyss"
    property string activeSection: "appearance"
    property bool spectrumControlsReady: false

    Component.onCompleted: Qt.callLater(() => root.spectrumControlsReady = true)

    function activateSettingsSearchSection(section: string): bool {
        const parts = String(section || "").toLowerCase().split(/[·›]/)
        const label = parts[parts.length - 1].trim()
        const sections = {
            "appearance & layout": "appearance",
            "sizing & surface": "appearance",
            "audio spectrum": "spectrum",
            "behavior & clock": "behavior",
            "modules": "modules",
            "bar module layout": "modules",
            "resources": "modules",
            "media": "modules",
            "workspaces": "modules",
            "system tray": "modules",
            "utility buttons": "modules",
            "notifications": "modules"
        }
        const target = sections[label] ?? ""
        if (!target)
            return false
        root.activeSection = target
        return true
    }

    readonly property bool isVertical: Config.options?.bar?.vertical ?? false
    readonly property bool spectrumEnabled: Config.options?.bar?.visualizer?.enable ?? false
    readonly property color workspaceThemeIndicatorColor: Appearance.zzzEverywhere ? Appearance.zzz.accentSoft
        : Appearance.angelEverywhere ? Appearance.angel.colPrimary : Appearance.colors.colPrimary
    readonly property color workspaceIndicatorPreviewColor: {
        const saved = Config.options?.bar?.workspaces?.indicatorColor ?? ""
        if (saved.length === 0)
            return root.workspaceThemeIndicatorColor
        const parsed = Qt.color(saved)
        return parsed.valid ? parsed : root.workspaceThemeIndicatorColor
    }

    function setSpectrumValue(path, value): void {
        if (root.spectrumControlsReady)
            Config.setNestedValue(path, value)
    }

    SettingsTaskNavigator {
        icon: "toolbar"
        title: root.abyssContent ? Translation.tr("Module behavior") : Translation.tr("Classic Bar")
        description: Translation.tr("Position, surface, behavior, spectrum and modules for the Classic bar.")
        summary: Translation.tr("Appearance · Spectrum · Behavior · Modules")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: root.abyssContent ? [
            { displayName: Translation.tr("Modules"), icon: "widgets", value: "modules" },
            { displayName: Translation.tr("Behavior & clock"), icon: "visibility", value: "behavior" }
        ] : [
            { displayName: Translation.tr("Appearance"), icon: "style", value: "appearance" },
            { displayName: Translation.tr("Audio spectrum"), icon: "graphic_eq", value: "spectrum" },
            { displayName: Translation.tr("Behavior & clock"), icon: "visibility", value: "behavior" },
            { displayName: Translation.tr("Modules"), icon: "widgets", value: "modules" }
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
                text: Translation.tr("Classic Material settings; Waffle has separate taskbar controls.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "appearance"
        visible: root.isIiActive && root.activeSection === "appearance"
        expanded: true
        icon: "toolbar"
        title: Translation.tr("Appearance & Layout")

        SettingsGroup {
            SettingsNote {
                icon: "toolbar"
                text: Translation.tr("Classic Bar uses the Hug surface. Position only changes which screen edge it hugs.")
            }

            ContentSubsection {
                title: Translation.tr("Position")

                ConfigSelectionArray {
                    currentValue: ((Config.options?.bar?.bottom ?? false) ? 1 : 0)
                        | ((Config.options?.bar?.vertical ?? false) ? 2 : 0)
                    onSelected: newValue => {
                        Config.setNestedValue("bar.bottom", (newValue & 1) !== 0)
                        Config.setNestedValue("bar.vertical", (newValue & 2) !== 0)
                    }
                    options: [
                        { displayName: Translation.tr("Top"), icon: "arrow_upward", value: 0 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Left"), icon: "arrow_back", value: 2 },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward", value: 3 }
                    ]
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "height"
                    text: root.isVertical ? Translation.tr("Bar width (px)") : Translation.tr("Bar height (px)")
                    value: Config.options?.bar?.height ?? 40
                    from: 24
                    to: 80
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("bar.height", value)
                }

                ConfigSpinBox {
                    icon: "rounded_corner"
                    text: Translation.tr("Custom rounding (px)")
                    value: Config.options?.bar?.customRounding ?? -1
                    from: -1
                    to: 50
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("bar.customRounding", value)
                    StyledToolTip {
                        text: Translation.tr("-1 uses the active theme default; 0 is square.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Background opacity (%)")
                    value: Math.round((Config.options?.bar?.opacity ?? 1) * 100)
                    from: 20
                    to: 100
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("bar.opacity", value / 100)
                }

                SettingsSwitch {
                    buttonIcon: "border_clear"
                    text: Translation.tr("Borderless")
                    checked: Config.options?.bar?.borderless ?? true
                    onCheckedChanged: Config.setNestedValue("bar.borderless", checked)
                }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "appearance"
        visible: root.isIiActive && root.activeSection === "appearance"
        expanded: true
        icon: "border_outer"
        title: Translation.tr("Screen Edge")

        SettingsGroup {
            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "width"
                    text: Translation.tr("Screen edge width (px)")
                    value: Config.options?.appearance?.screenEdge?.width ?? 10
                    from: 1
                    to: 32
                    stepSize: 1
                    onValueChanged: Config.setNestedValue(
                        "appearance.screenEdge.width", value)
                }

                ConfigSpinBox {
                    icon: "rounded_corner"
                    text: Translation.tr("Corner radius (px)")
                    value: Config.options?.appearance?.screenEdge?.radius ?? 25
                    from: 0
                    to: 96
                    stepSize: 1
                    onValueChanged: Config.setNestedValue(
                        "appearance.screenEdge.radius", value)
                }
            }

            SettingsSwitch {
                buttonIcon: "shadow"
                text: Translation.tr("Screen edge shadow")
                checked: Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
                onCheckedChanged: Config.setNestedValue(
                    "appearance.screenEdge.physicalShadow.enabled", checked)
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "blur_on"
                    text: Translation.tr("Shadow size (px)")
                    value: Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15
                    from: 0
                    to: 32
                    stepSize: 1
                    enabled: Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
                    opacity: enabled ? 1 : 0.5
                    onValueChanged: Config.setNestedValue(
                        "appearance.screenEdge.physicalShadow.size", value)
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Shadow opacity (%)")
                    value: Math.round(
                        (Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70) * 100)
                    from: 0
                    to: 100
                    stepSize: 2
                    enabled: Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
                    opacity: enabled ? 1 : 0.5
                    onValueChanged: Config.setNestedValue(
                        "appearance.screenEdge.physicalShadow.opacity", value / 100)
                }
            }

            SettingsNote {
                icon: "info"
                text: Translation.tr("Shared shadow for Edge, popups, Dock, Sidebar and Dashboard; hidden in fullscreen/lock.")
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "spectrum"
        visible: root.isIiActive && root.activeSection === "spectrum"
        expanded: true
        icon: "graphic_eq"
        title: Translation.tr("Audio spectrum")

        SettingsGroup {
            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Show spectrum in the bar")
                checked: root.spectrumEnabled
                onCheckedChanged: root.setSpectrumValue("bar.visualizer.enable", checked)
            }

            ConfigSelectionArray {
                enabled: root.spectrumEnabled
                opacity: enabled ? 1 : 0.5
                currentValue: Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary"
                onSelected: newValue => root.setSpectrumValue("bar.visualizer.multiMonitorMode", newValue)
                options: [
                    { displayName: Translation.tr("Primary only"), icon: "filter_1", value: "primary" },
                    { displayName: Translation.tr("All monitors"), icon: "select_all", value: "all" }
                ]
            }

            ConfigSelectionArray {
                enabled: root.spectrumEnabled
                opacity: enabled ? 1 : 0.5
                currentValue: Config.options?.bar?.visualizer?.type ?? "bars"
                onSelected: newValue => root.setSpectrumValue("bar.visualizer.type", newValue)
                options: [
                    { displayName: Translation.tr("Bars"), icon: "equalizer", value: "bars" },
                    { displayName: Translation.tr("Wave"), icon: "waves", value: "wave" }
                ]
            }

            ConfigSelectionArray {
                visible: (Config.options?.bar?.visualizer?.type ?? "bars") === "bars"
                enabled: root.spectrumEnabled
                opacity: enabled ? 1 : 0.5
                currentValue: Config.options?.bar?.visualizer?.barsOrigin ?? "bottom"
                onSelected: newValue => root.setSpectrumValue("bar.visualizer.barsOrigin", newValue)
                options: [
                    { displayName: Translation.tr("Bottom"), icon: "vertical_align_bottom", value: "bottom" },
                    { displayName: Translation.tr("Top"), icon: "vertical_align_top", value: "top" },
                    { displayName: Translation.tr("Center rise"), icon: "center_focus_strong", value: "center" },
                    { displayName: Translation.tr("Mirrored"), icon: "unfold_more", value: "mirror" }
                ]
            }

            ConfigSelectionArray {
                visible: (Config.options?.bar?.visualizer?.type ?? "bars") === "wave"
                enabled: root.spectrumEnabled
                opacity: enabled ? 1 : 0.5
                currentValue: Config.options?.bar?.visualizer?.waveMode ?? "fill"
                onSelected: newValue => root.setSpectrumValue("bar.visualizer.waveMode", newValue)
                options: [
                    { displayName: Translation.tr("Fill"), icon: "waves", value: "fill" },
                    { displayName: Translation.tr("Line"), icon: "line_weight", value: "line" },
                    { displayName: Translation.tr("Ribbon"), icon: "unfold_more", value: "ribbon" }
                ]
            }

            ConfigSelectionArray {
                enabled: root.spectrumEnabled
                opacity: enabled ? 1 : 0.5
                currentValue: Config.options?.bar?.visualizer?.frequencyProfile ?? "flat"
                onSelected: newValue => root.setSpectrumValue("bar.visualizer.frequencyProfile", newValue)
                options: [
                    { displayName: Translation.tr("Flat"), icon: "horizontal_rule", value: "flat" },
                    { displayName: Translation.tr("Bass"), icon: "graphic_eq", value: "bass" },
                    { displayName: Translation.tr("Warm"), icon: "local_fire_department", value: "warm" },
                    { displayName: Translation.tr("Vocal"), icon: "record_voice_over", value: "vocal" },
                    { displayName: Translation.tr("Treble"), icon: "trending_up", value: "treble" },
                    { displayName: Translation.tr("Smile"), icon: "waves", value: "smile" }
                ]
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "view_column"
                    text: Translation.tr("Band density (px)")
                    value: Config.options?.bar?.visualizer?.density ?? 12
                    from: 4
                    to: 32
                    stepSize: 1
                    enabled: root.spectrumEnabled
                    onValueChanged: root.setSpectrumValue("bar.visualizer.density", value)
                }

                ConfigSpinBox {
                    icon: "space_bar"
                    text: Translation.tr("Band gap (px)")
                    value: Config.options?.bar?.visualizer?.gap ?? 2
                    from: 0
                    to: 12
                    stepSize: 1
                    enabled: root.spectrumEnabled
                    onValueChanged: root.setSpectrumValue("bar.visualizer.gap", value)
                }

                ConfigSpinBox {
                    icon: "blur_on"
                    text: Translation.tr("Smoothing")
                    value: Config.options?.bar?.visualizer?.smoothing ?? 2
                    from: 0
                    to: 8
                    stepSize: 1
                    enabled: root.spectrumEnabled
                    onValueChanged: root.setSpectrumValue("bar.visualizer.smoothing", value)
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Height (%)")
                    value: Math.round((Config.options?.bar?.visualizer?.height ?? 0.6) * 100)
                    from: 10
                    to: 100
                    stepSize: 5
                    enabled: root.spectrumEnabled
                    onValueChanged: root.setSpectrumValue("bar.visualizer.height", value / 100)
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Opacity (%)")
                    value: Math.round((Config.options?.bar?.visualizer?.opacity ?? 0.35) * 100)
                    from: 5
                    to: 100
                    stepSize: 5
                    enabled: root.spectrumEnabled
                    onValueChanged: root.setSpectrumValue("bar.visualizer.opacity", value / 100)
                }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "behavior"
        visible: root.isIiActive && root.activeSection === "behavior"
        expanded: true
        icon: "visibility"
        title: Translation.tr("Behavior & clock")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Auto hide")

                SettingsSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Auto hide")
                    checked: Config.options?.bar?.autoHide?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("bar.autoHide.enable", checked)
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        icon: "width_normal"
                        text: Translation.tr("Reveal region (px)")
                        value: Config.options?.bar?.autoHide?.hoverRegionWidth ?? 2
                        from: 1
                        to: 16
                        stepSize: 1
                        enabled: Config.options?.bar?.autoHide?.enable ?? false
                        opacity: enabled ? 1 : 0.5
                        onValueChanged: Config.setNestedValue("bar.autoHide.hoverRegionWidth", value)
                    }

                    SettingsSwitch {
                        buttonIcon: "vertical_align_center"
                        text: Translation.tr("Push windows")
                        checked: Config.options?.bar?.autoHide?.pushWindows ?? false
                        onCheckedChanged: Config.setNestedValue("bar.autoHide.pushWindows", checked)
                    }
                }

                SettingsSwitch {
                    buttonIcon: "keyboard_command_key"
                    text: Translation.tr("Reveal while Super is held")
                    checked: Config.options?.bar?.autoHide?.showWhenPressingSuper?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("bar.autoHide.showWhenPressingSuper.enable", checked)
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Super reveal delay (ms)")
                    value: Config.options?.bar?.autoHide?.showWhenPressingSuper?.delay ?? 140
                    from: 0
                    to: 1000
                    stepSize: 20
                    enabled: Config.options?.bar?.autoHide?.showWhenPressingSuper?.enable ?? true
                    opacity: enabled ? 1 : 0.5
                    onValueChanged: Config.setNestedValue("bar.autoHide.showWhenPressingSuper.delay", value)
                }
            }

            SettingsNote { visible:Config.options?.panelFamily==="abyss";text:Translation.tr("Clock follows Typography") }
            Loader {
                Layout.fillWidth:true
                active:Config.options?.panelFamily!=="abyss"
                sourceComponent:Component {
                    ContentSubsection {
                        title: Translation.tr("Clock")

                        ConfigRow {
                            uniform: true

                            FontSelector {
                                id: timeFontSelector
                                label: Translation.tr("Time font")
                                icon: "schedule"
                                selectedFont: Config.options?.bar?.clock?.timeFontFamily ?? ""
                                onSelectedFontChanged: Config.setNestedValue("bar.clock.timeFontFamily", selectedFont)
                            }

                            ConfigSpinBox {
                                icon: "format_size"
                                text: Translation.tr("Time size (px)")
                                value: Config.options?.bar?.clock?.timePixelSize ?? 0
                                from: 0
                                to: 64
                                stepSize: 1
                                onValueChanged: Config.setNestedValue("bar.clock.timePixelSize", value)
                            }
                        }

                        ConfigRow {
                            uniform: true

                            FontSelector {
                                id: dateFontSelector
                                label: Translation.tr("Date font")
                                icon: "font_download"
                                selectedFont: Config.options?.bar?.clock?.dateFontFamily ?? ""
                                onSelectedFontChanged: Config.setNestedValue("bar.clock.dateFontFamily", selectedFont)
                            }

                            ConfigSpinBox {
                                icon: "format_size"
                                text: Translation.tr("Date size (px)")
                                value: Config.options?.bar?.clock?.datePixelSize ?? 0
                                from: 0
                                to: 64
                                stepSize: 1
                                onValueChanged: Config.setNestedValue("bar.clock.datePixelSize", value)
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: root.isIiActive && root.activeSection === "modules"
        expanded: true
        icon: "widgets"
        title: Translation.tr("Modules")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Visible modules")
                visible: !root.abyssContent

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "left_panel_open"
                        text: Translation.tr("Left sidebar button")
                        checked: Config.options?.bar?.modules?.leftSidebarButton ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.leftSidebarButton", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "computer"
                        text: Translation.tr("Distro icon")
                        checked: Config.options?.bar?.modules?.distroIcon ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.distroIcon", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "window"
                        text: Translation.tr("Active window")
                        checked: Config.options?.bar?.modules?.activeWindow ?? true
                        enabled: !(Config.options?.bar?.modules?.taskbar ?? false)
                        opacity: enabled ? 1 : 0.5
                        onCheckedChanged: Config.setNestedValue("bar.modules.activeWindow", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "dock_to_bottom"
                        text: Translation.tr("Taskbar")
                        checked: Config.options?.bar?.modules?.taskbar ?? false
                        onCheckedChanged: Config.setNestedValue("bar.modules.taskbar", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "shelf_auto_hide"
                        text: Translation.tr("System tray")
                        checked: Config.options?.bar?.modules?.sysTray ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.sysTray", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "memory"
                        text: Translation.tr("Resources")
                        checked: Config.options?.bar?.modules?.resources ?? false
                        onCheckedChanged: Config.setNestedValue("bar.modules.resources", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "music_note"
                        text: Translation.tr("Media")
                        checked: Config.options?.bar?.modules?.media ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.media", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "workspaces"
                        text: Translation.tr("Workspaces")
                        checked: Config.options?.bar?.modules?.workspaces ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.workspaces", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "schedule"
                        text: Translation.tr("Clock")
                        checked: Config.options?.bar?.modules?.clock ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.clock", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "build"
                        text: Translation.tr("Utility buttons")
                        checked: Config.options?.bar?.modules?.utilButtons ?? false
                        onCheckedChanged: Config.setNestedValue("bar.modules.utilButtons", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "battery_full"
                        text: Translation.tr("Battery")
                        checked: Config.options?.bar?.modules?.battery ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.battery", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "cloud"
                        text: Translation.tr("Weather")
                        checked: Config.options?.bar?.modules?.weather ?? true
                        enabled: Config.options?.bar?.weather?.enable ?? false
                        opacity: enabled ? 1 : 0.5
                        onCheckedChanged: Config.setNestedValue("bar.modules.weather", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "right_panel_open"
                        text: Translation.tr("Right sidebar button")
                        checked: Config.options?.bar?.modules?.rightSidebarButton ?? true
                        onCheckedChanged: Config.setNestedValue("bar.modules.rightSidebarButton", checked)
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quick Action Settings")
                visible: root.abyssContent
                    || (Config.options?.bar?.modules?.utilButtons ?? false)

                QuickActionSettingsEditor {}
            }

            SettingsNote {
                visible: !root.abyssContent
                icon: root.isVertical ? "view_column" : "view_stream"
                text: Translation.tr("Horizontal and vertical module layouts are separate; visibility is shared.")
            }

            ContentSubsection {
                visible: !root.abyssContent
                title: root.isVertical
                    ? Translation.tr("Left/Right module layout")
                    : Translation.tr("Top/Bottom module layout")

                ConfigSpinBox {
                    icon: root.isVertical ? "height" : "space_bar"
                    text: root.isVertical
                        ? Translation.tr("Flexible spacer height")
                        : Translation.tr("Flexible spacer width")
                    value: root.isVertical
                        ? (Config.options?.bar?.verticalLayout?.spacerHeight ?? 0)
                        : (Config.options?.bar?.layout?.spacerWidth ?? 0)
                    from: 0
                    to: 480
                    stepSize: 8
                    onValueChanged: Config.setNestedValue(
                        root.isVertical
                            ? "bar.verticalLayout.spacerHeight"
                            : "bar.layout.spacerWidth",
                        value)
                }

                ConfigSelectionArray {
                    currentValue: root.isVertical
                        ? (Config.options?.bar?.verticalLayout?.spacerMode ?? "auto")
                        : (Config.options?.bar?.layout?.spacerMode ?? "auto")
                    onSelected: newValue => Config.setNestedValue(
                        root.isVertical
                            ? "bar.verticalLayout.spacerMode"
                            : "bar.layout.spacerMode",
                        newValue)
                    options: [
                        { displayName: Translation.tr("Smart"), icon: "auto_awesome", value: "auto" },
                        { displayName: Translation.tr("Always elastic"), icon: root.isVertical ? "height" : "width_full", value: "fill" },
                        { displayName: root.isVertical ? Translation.tr("Fixed height") : Translation.tr("Fixed width"),
                          icon: root.isVertical ? "height" : "width_normal", value: "fixed" }
                    ]
                }

                BarModuleOrderEditor {
                    verticalPreset: root.isVertical
                }
            }

            ContentSubsection {
                title: Translation.tr("Active window")
                visible: !root.isVertical

                ConfigSpinBox {
                    icon: "width_normal"
                    text: Translation.tr("Active window max width (px)")
                    value: Config.options?.bar?.activeWindow?.width ?? 220
                    from: 120
                    to: 420
                    stepSize: 10
                    enabled: root.abyssContent || (Config.options?.bar?.modules?.activeWindow ?? true)
                    opacity: enabled ? 1 : 0.5
                    onValueChanged: Config.setNestedValue("bar.activeWindow.width", value)
                }
            }

            ContentSubsection {
                title: Translation.tr("Media")
                visible: !root.isVertical

                ConfigSpinBox {
                    icon: "width_normal"
                    text: Translation.tr("Media width (px)")
                    value: Config.options?.bar?.media?.width ?? 180
                    from: 120
                    to: 320
                    stepSize: 10
                    enabled: root.abyssContent || (Config.options?.bar?.modules?.media ?? true)
                    opacity: enabled ? 1 : 0.5
                    onValueChanged: Config.setNestedValue("bar.media.width", value)
                }
            }

            ContentSubsection {
                title: Translation.tr("System tray")

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "colors"
                        text: Translation.tr("Monochrome icons")
                        checked: Config.options?.bar?.tray?.monochromeIcons ?? true
                        onCheckedChanged: Config.setNestedValue("bar.tray.monochromeIcons", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "visibility_off"
                        text: Translation.tr("Filter passive items")
                        checked: Config.options?.bar?.tray?.filterPassive ?? true
                        onCheckedChanged: Config.setNestedValue("bar.tray.filterPassive", checked)
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Workspaces")

                ConfigSelectionArray {
                    visible: CompositorService.isNiri
                    currentValue: Config.options?.bar?.workspaces?.scrollBehavior ?? "workspace"
                    onSelected: newValue => Config.setNestedValue("bar.workspaces.scrollBehavior", newValue)
                    options: [
                        { displayName: Translation.tr("Switch workspaces"), icon: "workspaces", value: "workspace" },
                        { displayName: Translation.tr("Cycle columns"), icon: "view_column", value: "column" }
                    ]
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "counter_1"
                        text: Translation.tr("Always show numbers")
                        checked: Config.options?.bar?.workspaces?.alwaysShowNumbers ?? false
                        onCheckedChanged: Config.setNestedValue("bar.workspaces.alwaysShowNumbers", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "award_star"
                        text: Translation.tr("Show app icons")
                        checked: Config.options?.bar?.workspaces?.showAppIcons ?? true
                        onCheckedChanged: Config.setNestedValue("bar.workspaces.showAppIcons", checked)
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "colors"
                        text: Translation.tr("Tint app icons")
                        checked: Config.options?.bar?.workspaces?.monochromeIcons ?? true
                        enabled: Config.options?.bar?.workspaces?.showAppIcons ?? true
                        opacity: enabled ? 1 : 0.5
                        onCheckedChanged: Config.setNestedValue("bar.workspaces.monochromeIcons", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "dynamic_feed"
                        text: Translation.tr("Dynamic count")
                        checked: Config.options?.bar?.workspaces?.dynamicCount ?? true
                        onCheckedChanged: Config.setNestedValue("bar.workspaces.dynamicCount", checked)
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Resources")

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "memory"
                        text: Translation.tr("RAM")
                        checked: Config.options?.bar?.resources?.showMemoryIndicator ?? true
                        onCheckedChanged: Config.setNestedValue("bar.resources.showMemoryIndicator", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "planner_review"
                        text: Translation.tr("CPU")
                        checked: Config.options?.bar?.resources?.showCpuIndicator ?? true
                        onCheckedChanged: Config.setNestedValue("bar.resources.showCpuIndicator", checked)
                    }
                    SettingsSwitch {
                        buttonIcon: "videocam"
                        text: Translation.tr("GPU")
                        checked: Config.options?.bar?.resources?.showGpuIndicator ?? true
                        onCheckedChanged: Config.setNestedValue("bar.resources.showGpuIndicator", checked)
                    }
                }
            }
        }
    }
}
