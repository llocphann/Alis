import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.settings

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    settingsPageIndex: 5
    settingsPageName: Translation.tr("Panels")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    property string activeSection: "control"

    SettingsTaskNavigator {
        showTabBar: false
        icon: "bottom_app_bar"
        title: Translation.tr("Panels")
        description: Translation.tr("Panels, notifications, widgets and floating tools.")
        summary: Translation.tr("Control panel · notifications · widgets · tools")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Control"), icon: "tune", value: "control" },
            { displayName: Translation.tr("Notifications"), icon: "notifications", value: "notifications" },
            { displayName: Translation.tr("Widgets"), icon: "widgets", value: "widgets" },
            { displayName: Translation.tr("Tools"), icon: "dashboard_customize", value: "tools" }
        ]
    }

    function floatingToolsEnabled(): bool {
        return (Config.options?.enabledPanels ?? []).includes("iiOverlay")
    }

    function openFloatingTools(): void {
        GlobalStates.settingsOverlayOpen = false
        GlobalStates.overlayOpen = true
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        spacing: 14

    SettingsCardSection {
        Layout.fillWidth: true
        settingsTaskSection: "tools"
        visible: true
        expanded: true
        icon: "dashboard_customize"
        title: Translation.tr("Floating tools (Super+G)")

        SettingsGroup {
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Floating image and widgets panel (Super+G)")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: root.floatingToolsEnabled()
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open")
                onClicked: root.openFloatingTools()
            }

            ContentSubsection {
                title: Translation.tr("Background & dim")

                SettingsSwitch {
                    buttonIcon: "water"
                    text: Translation.tr("Darken screen behind overlay")
                    checked: Config.options?.overlay?.darkenScreen ?? false
                    onCheckedChanged: Config.setNestedValue("overlay.darkenScreen", checked)
                    StyledToolTip {
                        text: Translation.tr("Add a dark scrim behind overlay panels for better visibility")
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Overlay scrim dim (%)")
                    value: Config.options?.overlay?.scrimDim ?? 30
                    from: 0
                    to: 100
                    stepSize: 5
                    enabled: Config.options?.overlay?.darkenScreen ?? false
                    onValueChanged: Config.setNestedValue("overlay.scrimDim", value)
                    StyledToolTip {
                        text: Translation.tr("How dark the background scrim should be")
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Overlay background opacity (%)")
                    value: Math.round((Config.options?.overlay?.backgroundOpacity ?? 0.9) * 100)
                    from: 20
                    to: 100
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("overlay.backgroundOpacity", value / 100)
                    StyledToolTip {
                        text: Translation.tr("Opacity of the overlay panel background")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Animations")

                SettingsSwitch {
                    buttonIcon: "movie"
                    text: Translation.tr("Enable opening zoom animation")
                    checked: Config.options?.overlay?.openingZoomAnimation ?? true
                    onCheckedChanged: Config.setNestedValue("overlay.openingZoomAnimation", checked)
                    StyledToolTip {
                        text: Translation.tr("Animate overlay panels with a zoom effect when opening")
                    }
                }

                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Overlay animation duration (ms)")
                    value: Config.options?.overlay?.animationDurationMs ?? 180
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("overlay.animationDurationMs", value)
                    StyledToolTip {
                        text: Translation.tr("Duration of overlay open/close animations")
                    }
                }

                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Background dim animation (ms)")
                    value: Config.options?.overlay?.scrimAnimationDurationMs ?? 140
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("overlay.scrimAnimationDurationMs", value)
                    StyledToolTip {
                        text: Translation.tr("Duration of the background scrim fade animation")
                    }
                }
            }
        }
    }

    // ── Shell Desaturation Effect ───────────────────────────────────────
    SettingsCardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        settingsTaskSection: "tools"
        visible: true
        expanded: true
        icon: "filter_b_and_w"
        title: Translation.tr("Visual Effects")

        readonly property var _desat: Config.options?.appearance?.desaturation ?? ({})
        function _setDesat(key: string, val): void {
            Config.setNestedValue("appearance.desaturation." + key, val)
        }

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

            // Scope selector
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

            // Custom scope toggles
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

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        settingsTaskSection: "tools"
        visible: root.isIiActive
        expanded: true
        icon: "keyboard_tab"
        title: Translation.tr("Alt-Tab switcher (Material ii)")

        SettingsGroup {
            SettingsSwitch {
                enabled: (Config.options?.altSwitcher?.preset ?? "default") !== "skew"
                buttonIcon: "visibility_off"
                text: Translation.tr("No visual UI (cycle windows only)")
                checked: (Config.options?.altSwitcher?.preset ?? "default") === "skew"
                    ? false
                    : (Config.options?.altSwitcher?.noVisualUi ?? false)
                onCheckedChanged: Config.setNestedValue("altSwitcher.noVisualUi", checked)
                StyledToolTip {
                    text: Translation.tr("Use Alt+Tab to switch windows without showing the switcher overlay")
                }
            }

            SettingsSwitch {
                buttonIcon: "colors"
                text: Translation.tr("Tint app icons")
                checked: Config.options?.altSwitcher?.monochromeIcons ?? false
                onCheckedChanged: Config.setNestedValue("altSwitcher.monochromeIcons", checked)
                StyledToolTip {
                    text: Translation.tr("Apply accent color tint to app icons in the switcher")
                }
            }

            SettingsSwitch {
                buttonIcon: "movie"
                text: Translation.tr("Enable slide animation")
                checked: Config.options?.altSwitcher?.enableAnimation ?? true
                onCheckedChanged: Config.setNestedValue("altSwitcher.enableAnimation", checked)
                StyledToolTip {
                    text: Translation.tr("Animate window selection with a slide effect")
                }
            }

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Animation duration (ms)")
                value: Config.options?.altSwitcher?.animationDurationMs ?? 200
                from: 0
                to: 1000
                stepSize: 25
                onValueChanged: Config.setNestedValue("altSwitcher.animationDurationMs", value)
                StyledToolTip {
                    text: Translation.tr("Duration of the slide animation between windows")
                }
            }

            SettingsSwitch {
                buttonIcon: "history"
                text: Translation.tr("Most recently used first")
                checked: Config.options?.altSwitcher?.useMostRecentFirst ?? true
                onCheckedChanged: Config.setNestedValue("altSwitcher.useMostRecentFirst", checked)
                StyledToolTip {
                    text: Translation.tr("Order windows by most recently focused instead of position")
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Background opacity (%)")
                value: Math.round((Config.options?.altSwitcher?.backgroundOpacity ?? 0.9) * 100)
                from: 10
                to: 100
                stepSize: 5
                onValueChanged: Config.setNestedValue("altSwitcher.backgroundOpacity", value / 100)
                StyledToolTip {
                    text: Translation.tr("Opacity of the switcher panel background")
                }
            }

            ConfigSpinBox {
                icon: "blur_on"
                text: Translation.tr("Blur amount (%)")
                value: Math.round((Config.options?.altSwitcher?.blurAmount ?? 0.4) * 100)
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: Config.setNestedValue("altSwitcher.blurAmount", value / 100)
                StyledToolTip {
                    text: Translation.tr("Amount of blur applied to the switcher background")
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Scrim dim (%)")
                value: Config.options?.altSwitcher?.scrimDim ?? 35
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: Config.setNestedValue("altSwitcher.scrimDim", value)
                StyledToolTip {
                    text: Translation.tr("How dark the screen behind the switcher should be")
                }
            }

            ConfigSpinBox {
                icon: "hourglass_top"
                text: Translation.tr("Auto-hide delay after selection (ms)")
                value: Config.options?.altSwitcher?.autoHideDelayMs ?? 500
                from: 50
                to: 2000
                stepSize: 50
                onValueChanged: Config.setNestedValue("altSwitcher.autoHideDelayMs", value)
                StyledToolTip {
                    text: Translation.tr("How long to wait before hiding the switcher after releasing Alt")
                }
            }

            SettingsSwitch {
                buttonIcon: "overview_key"
                text: Translation.tr("Show Niri overview while switching")
                checked: Config.options?.altSwitcher?.showOverviewWhileSwitching ?? false
                onCheckedChanged: Config.setNestedValue("altSwitcher.showOverviewWhileSwitching", checked)
                StyledToolTip {
                    text: Translation.tr("Open Niri's native overview alongside the window switcher")
                }
            }

            ConfigSelectionArray {
                options: [
                    { displayName: Translation.tr("Default (sidebar)"), icon: "side_navigation", value: "default" },
                    { displayName: Translation.tr("List (centered)"), icon: "list", value: "list" },
                    { displayName: Translation.tr("Skew previews"), icon: "view_in_ar", value: "skew" }
                ]
                currentValue: Config.options?.altSwitcher?.preset ?? "default"
                onSelected: (newValue) => {
                    Config.setNestedValue("altSwitcher.preset", newValue)
                    Config.setNestedValue("altSwitcher.noVisualUi", false)
                }
            }

            ContentSubsection {
                title: Translation.tr("Layout & alignment")

                SettingsSwitch {
                    enabled: (Config.options?.altSwitcher?.preset ?? "default") !== "list"
                        && (Config.options?.altSwitcher?.preset ?? "default") !== "skew"
                    buttonIcon: "view_compact"
                    text: Translation.tr("Compact horizontal style (icons only)")
                    checked: Config.options?.altSwitcher?.compactStyle ?? false
                    onCheckedChanged: Config.setNestedValue("altSwitcher.compactStyle", checked)
                    StyledToolTip {
                        text: Translation.tr("Show only app icons in a horizontal row, similar to macOS Spotlight")
                    }
                }

                ConfigSelectionArray {
                    enabled: !(Config.options?.altSwitcher?.compactStyle ?? false)
                        && (Config.options?.altSwitcher?.preset ?? "default") !== "list"
                        && (Config.options?.altSwitcher?.preset ?? "default") !== "skew"
                    currentValue: Config.options?.altSwitcher?.panelAlignment ?? "right"
                    onSelected: newValue => Config.setNestedValue("altSwitcher.panelAlignment", newValue)
                    options: [
                        { displayName: Translation.tr("Align to right edge"), icon: "align_horizontal_right", value: "right" },
                        { displayName: Translation.tr("Center on screen"), icon: "align_horizontal_center", value: "center" }
                    ]
                }

                SettingsSwitch {
                    enabled: !(Config.options?.altSwitcher?.compactStyle ?? false)
                        && (Config.options?.altSwitcher?.preset ?? "default") !== "list"
                        && (Config.options?.altSwitcher?.preset ?? "default") !== "skew"
                    buttonIcon: "styler"
                    text: Translation.tr("Use Material 3 card layout")
                    checked: Config.options?.altSwitcher?.useM3Layout ?? false
                    onCheckedChanged: Config.setNestedValue("altSwitcher.useM3Layout", checked)
                    StyledToolTip {
                        text: Translation.tr("Use Material Design 3 style for the switching panel")
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        spacing: 14
        visible: root.isIiActive

    SettingsCardSection {
        settingsTaskSection: "notifications"
        Layout.fillWidth: true
        visible: root.isIiActive
        expanded: true
        icon: "notifications"
        title: Translation.tr("Notifications")

        SettingsGroup {
            ContentSubsectionLabel {
                text: Translation.tr("Transient notifications")
            }

            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Timeout (ms)")
                value: Config.options?.notifications?.timeoutNormal ?? 7000
                from: 1000
                to: 30000
                stepSize: 500
                onValueChanged: {
                    Config.setNestedValue("notifications.timeoutNormal", value)
                }
                StyledToolTip {
                    text: Translation.tr("Duration in milliseconds before a notification automatically closes")
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "timer"
                    text: Translation.tr("Ignore app timeout")
                    checked: Config.options?.notifications?.ignoreAppTimeout ?? false
                    onCheckedChanged: Config.setNestedValue("notifications.ignoreAppTimeout", checked)
                    StyledToolTip {
                        text: Translation.tr("Always use your timeout settings instead of app-defined ones")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "pinch"
                    text: Translation.tr("Scale on hover")
                    checked: Config.options?.notifications?.scaleOnHover ?? false
                    onCheckedChanged: {
                        Config.setNestedValue("notifications.scaleOnHover", checked)
                    }
                    StyledToolTip {
                        text: Translation.tr("Slightly enlarge notifications when the mouse hovers over them")
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "bedtime"
                text: Translation.tr("Quiet hours")
                checked: Config.options?.notifications?.quietHours?.enable ?? false
                onCheckedChanged: {
                    Config.setNestedValue("notifications.quietHours.enable", checked)
                }
                StyledToolTip {
                    text: Translation.tr("Silence daily popups; notifications remain in history.")
                }
            }

            RowLayout {
                spacing: 8
                enabled: Config.options?.notifications?.quietHours?.enable ?? false
                opacity: enabled ? 1 : 0.5

                StyledText {
                    text: Translation.tr("From")
                    color: Appearance.zzzEverywhere ? Appearance.zzz.ink
                        : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnSurface
                }
                MaterialTextField {
                    Layout.preferredWidth: 90
                    placeholderText: "22:00"
                    text: Config.options?.notifications?.quietHours?.start ?? "22:00"
                    // Reject anything that isn't HH:MM instead of persisting junk.
                    onEditingFinished: {
                        if (/^([01]?\d|2[0-3]):[0-5]\d$/.test(text))
                            Config.setNestedValue("notifications.quietHours.start", text)
                        else
                            text = Config.options?.notifications?.quietHours?.start ?? "22:00"
                    }
                }
                StyledText {
                    text: Translation.tr("to")
                    color: Appearance.zzzEverywhere ? Appearance.zzz.ink
                        : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnSurface
                }
                MaterialTextField {
                    Layout.preferredWidth: 90
                    placeholderText: "08:00"
                    text: Config.options?.notifications?.quietHours?.end ?? "08:00"
                    onEditingFinished: {
                        if (/^([01]?\d|2[0-3]):[0-5]\d$/.test(text))
                            Config.setNestedValue("notifications.quietHours.end", text)
                        else
                            text = Config.options?.notifications?.quietHours?.end ?? "08:00"
                    }
                }
                Item { Layout.fillWidth: true }
            }
            ConfigSpinBox {
                icon: "vertical_align_top"
                visible: Config.options?.panelFamily !== "abyss"
                text: Translation.tr("Margin (px)")
                value: Config.options?.notifications?.edgeMargin ?? 4
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.setNestedValue("notifications.edgeMargin", value)
                }
                StyledToolTip {
                    text: Translation.tr("Spacing between notifications and the screen edge/anchor")
                }
            }

            ConfigSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Auto-sync badge with popup list")
                checked: !(Config.options?.notifications?.useLegacyCounter ?? true)
                onCheckedChanged: {
                    Config.setNestedValue("notifications.useLegacyCounter", !checked)
                }
                StyledToolTip {
                    text: Translation.tr("Sync badges with live popup count, including externally cleared alerts; off uses manual count.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Anchor")
                visible: Config.options?.panelFamily !== "abyss"

                ConfigSelectionArray {
                    currentValue: Config.options?.notifications?.position ?? "topRight"
                    onSelected: newValue => {
                        Config.setNestedValue("notifications.position", newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Top Right"), icon: "north_east", value: "topRight" },
                        { displayName: Translation.tr("Top Left"), icon: "north_west", value: "topLeft" },
                        { displayName: Translation.tr("Bottom Right"), icon: "south_east", value: "bottomRight" },
                        { displayName: Translation.tr("Bottom Left"), icon: "south_west", value: "bottomLeft" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Notification position")
                visible: Config.options?.panelFamily === "abyss"
                Layout.preferredHeight: 0
                Layout.maximumHeight: 0
                implicitHeight: 0
                opacity: 0
                clip: true
                enabled: false
                AbyssPositionSettings {
                    kind: "notifications"
                    allowedKinds: ["notifications"]
                }
            }

            SettingsDivider {}

            ContentSubsectionLabel {
                text: Translation.tr("Notification center")
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options?.panelFamily !== "abyss"
                materialIcon: "south_east"
                text: Translation.tr("Hover bottom-right for history; assigned compositor hot corners take priority.")
            }

            ConfigSwitch {
                visible: Config.options?.panelFamily !== "abyss"
                buttonIcon: "notifications"
                text: Translation.tr("Enable notification center")
                checked: Config.options?.notificationCenter?.enable ?? true
                onCheckedChanged:
                    Config.setNestedValue("notificationCenter.enable", checked)
            }

            ConfigSwitch {
                visible: Config.options?.panelFamily !== "abyss"
                buttonIcon: "south_east"
                text: Translation.tr("Open on bottom-right hover")
                checked: Config.options?.notificationCenter?.hoverEnable ?? true
                enabled: Config.options?.notificationCenter?.enable ?? true
                opacity: enabled ? 1 : 0.5
                onCheckedChanged:
                    Config.setNestedValue("notificationCenter.hoverEnable", checked)
            }

            ConfigRow {
                uniform: true
                visible: Config.options?.panelFamily !== "abyss"

                ConfigSpinBox {
                    icon: "hourglass"
                    text: Translation.tr("Hover delay (ms)")
                    value: Config.options?.notificationCenter?.hoverDelayMs ?? 220
                    from: 0
                    to: 1200
                    stepSize: 20
                    enabled: (Config.options?.notificationCenter?.enable ?? true)
                        && (Config.options?.notificationCenter?.hoverEnable ?? true)
                    opacity: enabled ? 1 : 0.5
                    onValueChanged:
                        Config.setNestedValue("notificationCenter.hoverDelayMs", value)
                }

                ConfigSpinBox {
                    icon: "select"
                    text: Translation.tr("Corner hit size (px)")
                    value: Config.options?.notificationCenter?.cornerSize ?? 14
                    from: 4
                    to: 48
                    stepSize: 1
                    enabled: (Config.options?.notificationCenter?.enable ?? true)
                        && (Config.options?.notificationCenter?.hoverEnable ?? true)
                    opacity: enabled ? 1 : 0.5
                    onValueChanged:
                        Config.setNestedValue("notificationCenter.cornerSize", value)
                }
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Close grace (ms)")
                value: Config.options?.notificationCenter?.closeGraceMs ?? 280
                from: 0
                to: 1200
                stepSize: 20
                enabled: (Config.options?.notificationCenter?.enable ?? true)
                    && (Config.options?.notificationCenter?.hoverEnable ?? true)
                opacity: enabled ? 1 : 0.5
                onValueChanged:
                    Config.setNestedValue("notificationCenter.closeGraceMs", value)
                StyledToolTip {
                    text: Translation.tr("Keeps the center open briefly while the pointer moves between the corner and popup.")
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "width"
                    text: Translation.tr("Popup width (px)")
                    value: Config.options?.notificationCenter?.popupWidth ?? 420
                    from: 320
                    to: 760
                    stepSize: 20
                    enabled: Config.options?.notificationCenter?.enable ?? true
                    opacity: enabled ? 1 : 0.5
                    onValueChanged:
                        Config.setNestedValue("notificationCenter.popupWidth", value)
                }

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Popup height (px)")
                    value: Config.options?.notificationCenter?.popupHeight ?? 560
                    from: 260
                    to: 900
                    stepSize: 20
                    enabled: Config.options?.notificationCenter?.enable ?? true
                    opacity: enabled ? 1 : 0.5
                    onValueChanged:
                        Config.setNestedValue("notificationCenter.popupHeight", value)
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "done_all"
                    text: Translation.tr("Mark read when opened")
                    checked: Config.options?.notificationCenter?.markReadOnOpen ?? true
                    enabled: Config.options?.notificationCenter?.enable ?? true
                    opacity: enabled ? 1 : 0.5
                    onCheckedChanged:
                        Config.setNestedValue("notificationCenter.markReadOnOpen", checked)
                    StyledToolTip {
                        text: Translation.tr("Mark history read and retract matching toasts (shared read flag).")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Allow over fullscreen apps")
                    checked: Config.options?.notificationCenter?.allowInFullscreen ?? false
                    enabled: Config.options?.notificationCenter?.enable ?? true
                    opacity: enabled ? 1 : 0.5
                    onCheckedChanged:
                        Config.setNestedValue("notificationCenter.allowInFullscreen", checked)
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: Config.options?.panelFamily !== "abyss"
                materialIcon: "preview"
                mainText: GlobalStates.notificationCenterExplicitOpen
                    ? Translation.tr("Close notification center")
                    : Translation.tr("Preview notification center")
                enabled: GlobalStates.notificationCenterAvailable
                onClicked: GlobalStates.toggleNotificationCenter("")
                StyledToolTip {
                    text: GlobalStates.notificationCenterAvailable
                        ? Translation.tr("Open the center on its resolved output without moving the pointer to the corner.")
                        : Translation.tr("Enable the Material Screen Corners panel to preview this surface.")
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        settingsTaskSection: "control"
        visible: root.isIiActive
        expanded: true
        icon: "tune"
        title: Translation.tr("Control panel")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "density_medium"
                    text: Translation.tr("Compact cards")
                    checked: Config.options?.controlPanel?.compactMode ?? true
                    onCheckedChanged: Config.setNestedValue("controlPanel.compactMode", checked)
                    StyledToolTip {
                        text: Translation.tr("Use tighter spacing and shorter cards in the quick settings panel")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("Keep control panel loaded")
                    checked: Config.options?.controlPanel?.keepLoaded ?? false
                    onCheckedChanged: Config.setNestedValue("controlPanel.keepLoaded", checked)
                    StyledToolTip {
                        text: Translation.tr("Keep the quick settings panel in memory to reduce opening delay")
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Show wallpaper card")
                    checked: Config.options?.controlPanel?.showWallpaperSection ?? true
                    onCheckedChanged: Config.setNestedValue("controlPanel.showWallpaperSection", checked)
                    StyledToolTip {
                        text: Translation.tr("Show the wallpaper preview card in the quick settings panel")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Show wallpaper scheme buttons")
                    enabled: Config.options?.controlPanel?.showWallpaperSection ?? true
                    checked: Config.options?.controlPanel?.showWallpaperSchemeChips ?? false
                    onCheckedChanged: Config.setNestedValue("controlPanel.showWallpaperSchemeChips", checked)
                    StyledToolTip {
                        text: Translation.tr("Show the scheme variant buttons under the wallpaper preview")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Visible sections")

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "music_note"
                        text: Translation.tr("Media")
                        checked: Config.options?.controlPanel?.showMediaSection ?? true
                        onCheckedChanged: Config.setNestedValue("controlPanel.showMediaSection", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "partly_cloudy_day"
                        text: Translation.tr("Weather")
                        checked: Config.options?.controlPanel?.showWeatherSection ?? true
                        onCheckedChanged: Config.setNestedValue("controlPanel.showWeatherSection", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "monitoring"
                        text: Translation.tr("System status")
                        checked: Config.options?.controlPanel?.showSystemSection ?? true
                        onCheckedChanged: Config.setNestedValue("controlPanel.showSystemSection", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "tune"
                        text: Translation.tr("Sliders")
                        checked: Config.options?.controlPanel?.showSlidersSection ?? true
                        onCheckedChanged: Config.setNestedValue("controlPanel.showSlidersSection", checked)
                    }
                }

                SettingsSwitch {
                    buttonIcon: "apps"
                    text: Translation.tr("Quick actions")
                    checked: Config.options?.controlPanel?.showQuickActionsSection ?? true
                    onCheckedChanged: Config.setNestedValue("controlPanel.showQuickActionsSection", checked)
                }
            }
        }
    }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        settingsTaskSection: "widgets"
        visible: root.isIiActive
        expanded: true
        icon: "widgets"
        title: Translation.tr("Widgets")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Visibility")
                tooltip: Translation.tr("Toggle which widgets appear in the sidebar")

                SettingsSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr("Media player")
                    checked: Config.options?.sidebar?.widgets?.media ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.media", checked)
                }

                SettingsSwitch {
                    buttonIcon: "calendar_today"
                    text: Translation.tr("Week strip")
                    checked: Config.options?.sidebar?.widgets?.week ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.week", checked)
                }

                SettingsSwitch {
                    buttonIcon: "partly_cloudy_day"
                    text: Translation.tr("Context card (Weather/Timer)")
                    checked: Config.options?.sidebar?.widgets?.context ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.context", checked)
                }

                SettingsSwitch {
                    buttonIcon: "cloud"
                    text: Translation.tr("Show weather in context card")
                    checked: Config.options?.sidebar?.widgets?.contextShowWeather ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.contextShowWeather", checked)
                    enabled: Config.options?.sidebar?.widgets?.context ?? true
                }

                SettingsSwitch {
                    buttonIcon: "edit_note"
                    text: Translation.tr("Quick note")
                    checked: Config.options?.sidebar?.widgets?.note ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.note", checked)
                }

                SettingsSwitch {
                    buttonIcon: "apps"
                    text: Translation.tr("Quick launch")
                    checked: Config.options?.sidebar?.widgets?.launch ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.launch", checked)
                }

                // Quick launch apps editor
                ColumnLayout {
                    id: quickLaunchEditor
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.topMargin: 2
                    spacing: 2
                    visible: Config.options?.sidebar?.widgets?.launch ?? true

                    property var shortcuts: Config.options?.sidebar?.widgets?.quickLaunch ?? [
                        { icon: "folder", name: "Files", cmd: "/usr/bin/nautilus" },
                        { icon: "terminal", name: "Terminal", cmd: "/usr/bin/kitty" },
                        { icon: "web", name: "Browser", cmd: "/usr/bin/firefox" },
                        { icon: "code", name: "Code", cmd: "/usr/bin/code" }
                    ]

                    property int pendingIndex: -1
                    property string pendingKey: ""
                    property string pendingValue: ""

                    Timer {
                        id: saveTimer
                        interval: 500
                        onTriggered: {
                            const idx = quickLaunchEditor.pendingIndex
                            const key = quickLaunchEditor.pendingKey
                            const val = quickLaunchEditor.pendingValue
                            if (idx >= 0 && idx < quickLaunchEditor.shortcuts.length) {
                                const newShortcuts = JSON.parse(JSON.stringify(quickLaunchEditor.shortcuts))
                                newShortcuts[idx][key] = val
                                Config.setNestedValue("sidebar.widgets.quickLaunch", newShortcuts)
                            }
                        }
                    }

                    function queueUpdate(index, key, value) {
                        pendingIndex = index
                        pendingKey = key
                        pendingValue = value
                        saveTimer.restart()
                    }

                    function removeShortcut(index) {
                        const newShortcuts = shortcuts.filter((_, i) => i !== index)
                        Config.setNestedValue("sidebar.widgets.quickLaunch", newShortcuts)
                    }

                    function addShortcut() {
                        const newShortcuts = [...shortcuts, { icon: "apps", name: "", cmd: "" }]
                        Config.setNestedValue("sidebar.widgets.quickLaunch", newShortcuts)
                    }

                    Repeater {
                        model: quickLaunchEditor.shortcuts.length

                        delegate: Item {
                            id: launchItem
                            required property int index
                            readonly property var itemData: quickLaunchEditor.shortcuts[index] ?? {}
                            Layout.fillWidth: true
                            implicitHeight: itemRow.implicitHeight + 8

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: itemHover.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                }
                            }

                            MouseArea {
                                id: itemHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            RowLayout {
                                id: itemRow
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 8; rightMargin: 4
                                }
                                spacing: 8

                                // Icon preview
                                Rectangle {
                                    implicitWidth: 32; implicitHeight: 32
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colSecondaryContainer
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: launchItem.itemData.icon ?? "apps"
                                        iconSize: 18
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }

                                // Icon name
                                ToolbarTextField {
                                    Layout.preferredWidth: 70
                                    implicitHeight: 30
                                    padding: 6
                                    text: launchItem.itemData.icon ?? ""
                                    placeholderText: Translation.tr("Icon")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    selectByMouse: true
                                    onTextEdited: quickLaunchEditor.queueUpdate(launchItem.index, "icon", text)
                                }

                                // Display name
                                ToolbarTextField {
                                    Layout.preferredWidth: 100
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 140
                                    implicitHeight: 30
                                    padding: 6
                                    text: launchItem.itemData.name ?? ""
                                    placeholderText: Translation.tr("Name")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    selectByMouse: true
                                    onTextEdited: quickLaunchEditor.queueUpdate(launchItem.index, "name", text)
                                }

                                // Command
                                ToolbarTextField {
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    padding: 6
                                    text: launchItem.itemData.cmd ?? ""
                                    placeholderText: Translation.tr("Command")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colSubtext
                                    selectByMouse: true
                                    onTextEdited: quickLaunchEditor.queueUpdate(launchItem.index, "cmd", text)
                                }

                                // Delete
                                RippleButton {
                                    implicitWidth: 24; implicitHeight: 24
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colErrorContainer
                                    colRipple: Appearance.colors.colError
                                    opacity: itemHover.containsMouse ? 1 : 0.3
                                    onClicked: quickLaunchEditor.removeShortcut(launchItem.index)

                                    Behavior on opacity {
                                        enabled: Appearance.animationsEnabled
                                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                    }

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 14
                                        color: Appearance.colors.colError
                                    }

                                    StyledToolTip { text: Translation.tr("Remove") }
                                }
                            }
                        }
                    }

                    // Add button
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colPrimaryContainer
                        onClicked: quickLaunchEditor.addShortcut()

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "add"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("Add shortcut")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "toggle_on"
                        text: Translation.tr("Controls")
                        checked: Config.options?.sidebar?.widgets?.controls ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controls", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "monitoring"
                        text: Translation.tr("System status")
                        checked: Config.options?.sidebar?.widgets?.status ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.status", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "currency_bitcoin"
                        text: Translation.tr("Crypto prices")
                        checked: Config.options?.sidebar?.widgets?.crypto ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.crypto", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "wallpaper"
                        text: Translation.tr("Wallpaper picker")
                        checked: Config.options?.sidebar?.widgets?.wallpaper ?? false
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.wallpaper", checked)
                    }
                }

                SettingsSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("World Clock")
                    checked: Config.options?.sidebar?.widgets?.worldClock ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.worldClock", checked)
                }
            }

            ContentSubsection {
                title: Translation.tr("Layout")

                ConfigSpinBox {
                    icon: "format_line_spacing"
                    text: Translation.tr("Widget spacing")
                    value: Config.options?.sidebar?.widgets?.spacing ?? 8
                    from: 0
                    to: 24
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("sidebar.widgets.spacing", value)
                    StyledToolTip {
                        text: Translation.tr("Space between widgets in pixels")
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "drag_indicator"
                    text: Translation.tr("Hold click on any widget to reorder")
                }
            }

            ContentSubsection {
                id: cryptoSection
                title: Translation.tr("Crypto Widget")
                tooltip: Translation.tr("Configure cryptocurrencies to track")
                visible: Config.options?.sidebar?.widgets?.crypto ?? false

                readonly property var popularCoins: [
                    "bitcoin", "ethereum", "solana", "cardano", "dogecoin", "ripple",
                    "polkadot", "litecoin", "monero", "toncoin", "avalanche-2", "chainlink",
                    "uniswap", "stellar", "binancecoin", "tron", "shiba-inu", "pepe"
                ]

                function addCoin(coinId) {
                    const id = coinId.toLowerCase().trim()
                    if (!id) return
                    const current = Config.options?.sidebar?.widgets?.crypto_settings?.coins ?? []
                    if (current.includes(id)) return
                    Config.setNestedValue("sidebar.widgets.crypto_settings.coins", [...current, id])
                    coinInput.text = ""
                    coinPopup.close()
                }

                function removeCoin(coinId) {
                    const current = Config.options?.sidebar?.widgets?.crypto_settings?.coins ?? []
                    Config.setNestedValue("sidebar.widgets.crypto_settings.coins", current.filter(c => c !== coinId))
                }

                function filteredCoins() {
                    const q = coinInput.text.toLowerCase().trim()
                    const current = Config.options?.sidebar?.widgets?.crypto_settings?.coins ?? []
                    return popularCoins.filter(c => !current.includes(c) && c.includes(q))
                }

                ConfigSpinBox {
                    icon: "schedule"
                    text: Translation.tr("Refresh interval (seconds)")
                    value: Config.options?.sidebar?.widgets?.crypto_settings?.refreshInterval ?? 60
                    from: 30
                    to: 300
                    stepSize: 30
                    onValueChanged: Config.setNestedValue("sidebar.widgets.crypto_settings.refreshInterval", value)
                }

                // Coin input with autocomplete
                ConfigRow {
                    Layout.fillWidth: true
                    implicitHeight: coinInput.implicitHeight

                    MaterialTextField {
                        id: coinInput
                        width: parent.width
                        placeholderText: Translation.tr("Type to search coins...")
                        text: ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                        placeholderTextColor: Appearance.colors.colSubtext
                        background: Rectangle {
                            color: Appearance.colors.colLayer1
                            radius: Appearance.rounding.small
                            border.width: coinInput.activeFocus ? 2 : 1
                            border.color: coinInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                        }
                        onTextChanged: {
                            if (text.length > 0) coinPopup.open()
                            else coinPopup.close()
                        }
                        onAccepted: {
                            const filtered = cryptoSection.filteredCoins()
                            if (filtered.length > 0) cryptoSection.addCoin(filtered[0])
                            else if (text.trim()) cryptoSection.addCoin(text)
                        }
                        Keys.onDownPressed: coinList.incrementCurrentIndex()
                        Keys.onUpPressed: coinList.decrementCurrentIndex()
                    }

                    Popup {
                        id: coinPopup
                        y: coinInput.height + 4
                        width: coinInput.width
                        height: Math.min(200, coinList.contentHeight + 16)
                        padding: 8
                        visible: coinInput.text.length > 0 && cryptoSection.filteredCoins().length > 0

                        background: Rectangle {
                            color: Appearance.alisEverywhere ? Appearance.alis.colLayer2
                                 : Appearance.colors.colLayer2Base
                            radius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                            border.width: 1
                            border.color: Appearance.alisEverywhere ? Appearance.alis.colBorder
                                        : Appearance.colors.colLayer0Border
                        }

                        ListView {
                            id: coinList
                            anchors.fill: parent
                            model: cryptoSection.filteredCoins()
                            clip: true
                            currentIndex: 0

                            delegate: RippleButton {
                                id: coinDelegate
                                required property string modelData
                                required property int index
                                readonly property bool isCurrent: coinList.currentIndex === index
                                width: coinList.width
                                implicitHeight: 32
                                buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.small
                                colBackground: isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.sticker : (isCurrent ? Appearance.colors.colLayer1Hover : "transparent")
                                colBackgroundHover: isCurrent && Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                                colRipple: isCurrent && Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
                                onClicked: cryptoSection.addCoin(modelData)

                                contentItem: StyledText {
                                    text: coinDelegate.modelData
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.monospace
                                    color: coinDelegate.isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnLayer1
                                    leftPadding: 8
                                    verticalAlignment: Text.AlignVCenter
                                    Behavior on color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                    }
                                }
                            }
                        }
                    }
                }

                // Coin chips
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: (Config.options?.sidebar?.widgets?.crypto_settings?.coins ?? []).length > 0

                    Repeater {
                        model: Config.options?.sidebar?.widgets?.crypto_settings?.coins ?? []

                        InputChip {
                            required property string modelData
                            text: modelData
                            monospace: true
                            onRemoved: cryptoSection.removeCoin(modelData)
                        }
                    }
                }
            }

            ContentSubsection {
                id: worldClockSection
                title: Translation.tr("World Clock Widget")
                tooltip: Translation.tr("Configure timezones and display options")
                visible: Config.options?.sidebar?.widgets?.worldClock ?? true

                // Curated IANA timezone list with approximate standard GMT offset (minutes).
                // Offsets are for sorting/preview hints in the picker — the widget itself
                // resolves exact DST-aware times via the system tz database.
                readonly property var timezoneCatalog: [
                    { tz: "Pacific/Honolulu",                  off: -600 },
                    { tz: "America/Los_Angeles",               off: -480 },
                    { tz: "America/Vancouver",                 off: -480 },
                    { tz: "America/Denver",                    off: -420 },
                    { tz: "America/Chicago",                   off: -360 },
                    { tz: "America/Mexico_City",               off: -360 },
                    { tz: "America/Bogota",                    off: -300 },
                    { tz: "America/Lima",                      off: -300 },
                    { tz: "America/New_York",                  off: -300 },
                    { tz: "America/Toronto",                   off: -300 },
                    { tz: "America/Santiago",                  off: -240 },
                    { tz: "America/Argentina/Buenos_Aires",    off: -180 },
                    { tz: "America/Sao_Paulo",                 off: -180 },
                    { tz: "UTC",                               off: 0 },
                    { tz: "Europe/London",                     off: 0 },
                    { tz: "Europe/Dublin",                     off: 0 },
                    { tz: "Europe/Lisbon",                     off: 0 },
                    { tz: "Africa/Casablanca",                 off: 60 },
                    { tz: "Africa/Lagos",                      off: 60 },
                    { tz: "Europe/Madrid",                     off: 60 },
                    { tz: "Europe/Paris",                      off: 60 },
                    { tz: "Europe/Brussels",                   off: 60 },
                    { tz: "Europe/Amsterdam",                  off: 60 },
                    { tz: "Europe/Berlin",                     off: 60 },
                    { tz: "Europe/Zurich",                     off: 60 },
                    { tz: "Europe/Rome",                       off: 60 },
                    { tz: "Europe/Vienna",                     off: 60 },
                    { tz: "Europe/Prague",                     off: 60 },
                    { tz: "Europe/Warsaw",                     off: 60 },
                    { tz: "Europe/Stockholm",                  off: 60 },
                    { tz: "Africa/Cairo",                      off: 120 },
                    { tz: "Africa/Johannesburg",               off: 120 },
                    { tz: "Europe/Helsinki",                   off: 120 },
                    { tz: "Europe/Athens",                     off: 120 },
                    { tz: "Europe/Istanbul",                   off: 180 },
                    { tz: "Europe/Moscow",                     off: 180 },
                    { tz: "Europe/Kyiv",                       off: 120 },
                    { tz: "Africa/Nairobi",                    off: 180 },
                    { tz: "Asia/Jerusalem",                    off: 120 },
                    { tz: "Asia/Tehran",                       off: 210 },
                    { tz: "Asia/Dubai",                        off: 240 },
                    { tz: "Asia/Karachi",                      off: 300 },
                    { tz: "Asia/Kolkata",                      off: 330 },
                    { tz: "Asia/Dhaka",                        off: 360 },
                    { tz: "Asia/Bangkok",                      off: 420 },
                    { tz: "Asia/Jakarta",                      off: 420 },
                    { tz: "Asia/Singapore",                    off: 480 },
                    { tz: "Asia/Hong_Kong",                    off: 480 },
                    { tz: "Asia/Shanghai",                     off: 480 },
                    { tz: "Asia/Taipei",                       off: 480 },
                    { tz: "Asia/Manila",                       off: 480 },
                    { tz: "Australia/Perth",                   off: 480 },
                    { tz: "Asia/Seoul",                        off: 540 },
                    { tz: "Asia/Tokyo",                        off: 540 },
                    { tz: "Australia/Adelaide",                off: 570 },
                    { tz: "Australia/Brisbane",                off: 600 },
                    { tz: "Australia/Sydney",                  off: 600 },
                    { tz: "Pacific/Auckland",                  off: 720 }
                ]

                function offsetLabel(minutes) {
                    const sign = minutes < 0 ? "-" : "+"
                    const abs = Math.abs(minutes)
                    const h = Math.floor(abs / 60)
                    const m = abs % 60
                    return "GMT" + sign + String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0")
                }

                function cityLabel(tz) {
                    return tz.split("/").pop().replace(/_/g, " ")
                }

                function regionIcon(tz) {
                    const r = tz.split("/")[0]
                    switch (r) {
                    case "America": return "public"
                    case "Europe": return "castle"
                    case "Asia": return "temple_buddhist"
                    case "Africa": return "savings"
                    case "Australia":
                    case "Pacific": return "sailing"
                    default: return "schedule"
                    }
                }

                function addTimezone(tz) {
                    const id = tz.trim()
                    if (!id) return
                    const current = Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []
                    if (current.includes(id)) return
                    Config.setNestedValue("sidebar.widgets.worldClock_settings.timezones", [...current, id])
                    tzInput.text = ""
                    tzPopup.close()
                }

                function removeTimezone(tz) {
                    const current = Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []
                    Config.setNestedValue("sidebar.widgets.worldClock_settings.timezones", current.filter(t => t !== tz))
                }

                function moveTimezone(index, direction) {
                    const current = (Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []).slice()
                    const target = index + direction
                    if (target < 0 || target >= current.length) return
                    const tmp = current[index]
                    current[index] = current[target]
                    current[target] = tmp
                    Config.setNestedValue("sidebar.widgets.worldClock_settings.timezones", current)
                }

                function filteredTimezones() {
                    const q = tzInput.text.toLowerCase().trim().replace(/ /g, "_")
                    const current = Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []
                    const result = []
                    for (const e of timezoneCatalog) {
                        if (!current.includes(e.tz) && e.tz.toLowerCase().includes(q)) {
                            result.push(e)
                            if (result.length >= 10)
                                break
                        }
                    }
                    return result
                }

                // ── System timezone + suggestion materialization ──────────
                // Mirrors WorldClockWidget._suggestedTimezones so "Add suggestions"
                // seeds the same list the widget would show automatically.
                property string systemTz: ""

                Process {
                    id: sysTzProc
                    command: ["/usr/bin/readlink", "/etc/localtime"]
                    running: worldClockSection.visible
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const raw = text.trim()
                            const parts = raw.split("/zoneinfo/")
                            worldClockSection.systemTz = parts.length === 2 ? parts[1] : raw
                        }
                    }
                }

                function suggestedTimezones() {
                    const region = systemTz.split("/")[0] || ""
                    const base = systemTz ? [systemTz] : []
                    const global = ["America/New_York", "Europe/London", "Asia/Tokyo"]
                    let regional = []
                    switch (region) {
                    case "America": regional = ["America/Los_Angeles", "Europe/London"]; break
                    case "Europe": regional = ["America/New_York", "Asia/Tokyo"]; break
                    case "Asia": regional = ["Europe/London", "America/New_York"]; break
                    case "Australia":
                    case "Pacific": regional = ["Asia/Tokyo", "Europe/London"]; break
                    case "Africa": regional = ["Europe/London", "Asia/Dubai"]; break
                    }
                    const seen = new Set(base)
                    const result = base.slice()
                    for (const tz of [...regional, ...global]) {
                        if (!seen.has(tz)) { seen.add(tz); result.push(tz) }
                    }
                    return result.slice(0, 4)
                }

                function adoptSuggestions() {
                    const sugg = suggestedTimezones()
                    if (sugg.length > 0)
                        Config.setNestedValue("sidebar.widgets.worldClock_settings.timezones", sugg)
                }

                // ── Live time fetch for added timezones (chips/rows) ──────
                property var liveTimes: ({})

                function refreshLiveTimes() {
                    const tzs = Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []
                    if (tzs.length === 0) { liveTimes = ({}); return }
                    const fmt = (Config.options?.sidebar?.widgets?.worldClock_settings?.use24Hour ?? true) ? "%H:%M" : "%I:%M %p"
                    let script = ""
                    for (let i = 0; i < tzs.length; i++)
                        script += `printf '%s|%s\\n' "${tzs[i]}" "$(TZ='${tzs[i]}' date '+${fmt}|%:z')"\n`
                    liveTimeProc.command = ["/usr/bin/bash", "-c", script]
                    liveTimeProc.running = true
                }

                Process {
                    id: liveTimeProc
                    stdout: SplitParser {
                        splitMarker: "\n"
                        onRead: data => {
                            const sep = data.indexOf("|")
                            if (sep < 0) return
                            const tz = data.slice(0, sep)
                            const rest = data.slice(sep + 1).split("|")
                            const copy = Object.assign({}, worldClockSection.liveTimes)
                            copy[tz] = { time: rest[0] ?? "", offset: rest[1] ?? "" }
                            worldClockSection.liveTimes = copy
                        }
                    }
                }

                Timer {
                    interval: 20000
                    running: worldClockSection.visible
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: worldClockSection.refreshLiveTimes()
                }

                Connections {
                    target: Config
                    function onConfigChanged() {
                        if (worldClockSection.visible)
                            worldClockSection.refreshLiveTimes()
                    }
                }

                // ═══════════════════════════════════════════════════════
                // DISPLAY OPTIONS
                // ═══════════════════════════════════════════════════════
                ContentSubsectionLabel {
                    text: Translation.tr("Display")
                }

                SettingsSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("24-hour format")
                    checked: Config.options?.sidebar?.widgets?.worldClock_settings?.use24Hour ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.worldClock_settings.use24Hour", checked)
                    StyledToolTip {
                        text: Translation.tr("Toggle between 24-hour and 12-hour AM/PM time")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "timer"
                    text: Translation.tr("Show seconds")
                    checked: Config.options?.sidebar?.widgets?.worldClock_settings?.showSeconds ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.worldClock_settings.showSeconds", checked)
                    StyledToolTip {
                        text: Translation.tr("Updates every second while the sidebar is open (slightly higher CPU)")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "today"
                    text: Translation.tr("Show date & GMT offset")
                    checked: Config.options?.sidebar?.widgets?.worldClock_settings?.showDate ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.worldClock_settings.showDate", checked)
                    StyledToolTip {
                        text: Translation.tr("Display the weekday, date and UTC offset under each city")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "my_location"
                    text: Translation.tr("Highlight local timezone")
                    checked: Config.options?.sidebar?.widgets?.worldClock_settings?.highlightLocal ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.worldClock_settings.highlightLocal", checked)
                    StyledToolTip {
                        text: Translation.tr("Pin your local timezone to the top and accent it")
                    }
                }

                // ═══════════════════════════════════════════════════════
                // TIMEZONES
                // ═══════════════════════════════════════════════════════
                ContentSubsectionLabel {
                    text: Translation.tr("Timezones")
                }

                // Search input with rich autocomplete (city + GMT offset)
                ConfigRow {
                    Layout.fillWidth: true
                    implicitHeight: tzInput.implicitHeight

                    MaterialTextField {
                        id: tzInput
                        width: parent.width
                        placeholderText: Translation.tr("Search a city or region…")
                        text: ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                        placeholderTextColor: Appearance.colors.colSubtext
                        background: Rectangle {
                            color: Appearance.colors.colLayer1
                            radius: Appearance.rounding.small
                            border.width: tzInput.activeFocus ? 2 : 1
                            border.color: tzInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                        }
                        onTextChanged: {
                            if (text.length > 0) tzPopup.open()
                            else tzPopup.close()
                        }
                        onAccepted: {
                            const filtered = worldClockSection.filteredTimezones()
                            if (filtered.length > 0) worldClockSection.addTimezone(filtered[0].tz)
                            else if (text.trim()) worldClockSection.addTimezone(text.trim().replace(/ /g, "_"))
                        }
                        Keys.onDownPressed: tzList.incrementCurrentIndex()
                        Keys.onUpPressed: tzList.decrementCurrentIndex()
                    }

                    Popup {
                        id: tzPopup
                        y: tzInput.height + 4
                        width: tzInput.width
                        height: Math.min(280, tzList.contentHeight + 16)
                        padding: 8
                        visible: tzInput.text.length > 0 && worldClockSection.filteredTimezones().length > 0

                        background: Rectangle {
                            color: Appearance.alisEverywhere ? Appearance.alis.colLayer2
                                 : Appearance.colors.colLayer2Base
                            radius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                            border.width: 1
                            border.color: Appearance.alisEverywhere ? Appearance.alis.colBorder
                                        : Appearance.colors.colLayer0Border
                        }

                        ListView {
                            id: tzList
                            anchors.fill: parent
                            model: worldClockSection.filteredTimezones()
                            clip: true
                            currentIndex: 0

                            delegate: RippleButton {
                                id: tzDelegate
                                required property var modelData
                                required property int index
                                readonly property bool isCurrent: tzList.currentIndex === index
                                width: tzList.width
                                implicitHeight: 38
                                buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.small
                                colBackground: isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.sticker : (isCurrent ? Appearance.colors.colLayer1Hover : "transparent")
                                colBackgroundHover: isCurrent && Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                                colRipple: isCurrent && Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
                                onClicked: worldClockSection.addTimezone(tzDelegate.modelData.tz)

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: worldClockSection.regionIcon(tzDelegate.modelData.tz)
                                        iconSize: 16
                                        color: tzDelegate.isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colSubtext
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            text: worldClockSection.cityLabel(tzDelegate.modelData.tz)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: tzDelegate.isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnLayer1
                                            Behavior on color {
                                                enabled: Appearance.animationsEnabled
                                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                            }
                                        }
                                        StyledText {
                                            text: tzDelegate.modelData.tz.split("/").slice(0, -1).join(" / ").replace(/_/g, " ")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: tzDelegate.isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colSubtext
                                            Behavior on color {
                                                enabled: Appearance.animationsEnabled
                                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                            }
                                        }
                                    }
                                    StyledText {
                                        text: worldClockSection.offsetLabel(tzDelegate.modelData.off)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.monospace
                                        color: tzDelegate.isCurrent && Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colSubtext
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Added timezones — reorderable rows with live time
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 4
                    visible: (Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []).length > 0

                    Repeater {
                        model: Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []

                        delegate: Rectangle {
                            id: tzRowItem
                            required property string modelData
                            required property int index
                            readonly property var live: worldClockSection.liveTimes[modelData] ?? null
                            readonly property int total: (Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []).length

                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                            color: tzRowHover.containsMouse
                                ? (Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover : Appearance.colors.colLayer2Hover)
                                : (Appearance.alisEverywhere ? Appearance.alis.colLayer2 : Appearance.colors.colLayer2)

                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                            }

                            MouseArea {
                                id: tzRowHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 8

                                // Order index badge
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 20; implicitHeight: 20
                                    radius: height / 2
                                    color: Appearance.colors.colPrimaryContainer
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: tzRowItem.index + 1
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }

                                // City + region
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        text: worldClockSection.cityLabel(tzRowItem.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    StyledText {
                                        text: (tzRowItem.live?.offset ? "GMT" + tzRowItem.live.offset : tzRowItem.modelData.split("/")[0]).replace(/_/g, " ")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: tzRowItem.live?.offset ? Appearance.font.family.monospace : Appearance.font.family.main
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                // Live time
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: tzRowItem.live?.time ?? "··:··"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    font.family: Appearance.font.family.numbers
                                    color: Appearance.colors.colPrimary
                                }

                                // Reorder + remove controls
                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 0

                                    RippleButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer1Hover
                                        enabled: tzRowItem.index > 0
                                        opacity: enabled ? 1 : 0.25
                                        onClicked: worldClockSection.moveTimezone(tzRowItem.index, -1)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "keyboard_arrow_up"; iconSize: 18
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledToolTip { text: Translation.tr("Move up") }
                                    }

                                    RippleButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer1Hover
                                        enabled: tzRowItem.index < tzRowItem.total - 1
                                        opacity: enabled ? 1 : 0.25
                                        onClicked: worldClockSection.moveTimezone(tzRowItem.index, 1)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "keyboard_arrow_down"; iconSize: 18
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledToolTip { text: Translation.tr("Move down") }
                                    }

                                    RippleButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colErrorContainer
                                        colRipple: Appearance.colors.colError
                                        onClicked: worldClockSection.removeTimezone(tzRowItem.modelData)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"; iconSize: 15
                                            color: Appearance.colors.colError
                                        }
                                        StyledToolTip { text: Translation.tr("Remove") }
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state — explain auto mode + offer to materialize suggestions
                // so they can be individually removed/reordered/edited.
                Rectangle {
                    Layout.fillWidth: true
                    visible: (Config.options?.sidebar?.widgets?.worldClock_settings?.timezones ?? []).length === 0
                    implicitHeight: emptyCol.implicitHeight + 20
                    radius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                    color: Appearance.alisEverywhere ? Appearance.alis.colLayer2 : Appearance.colors.colLayer2

                    ColumnLayout {
                        id: emptyCol
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12; rightMargin: 12
                        }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol {
                                text: "my_location"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                                Layout.alignment: Qt.AlignTop
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("No timezones yet; add or reorder regional suggestions.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.small
                            colBackground: Appearance.zzzEverywhere ? Appearance.zzz.sticker : Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
                            colRipple: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimary
                            onClicked: worldClockSection.adoptSuggestions()

                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: "playlist_add"
                                    iconSize: 16
                                    color: Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnPrimaryContainer
                                    Behavior on color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                    }
                                }
                                StyledText {
                                    text: Translation.tr("Add suggested timezones")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnPrimaryContainer
                                    Behavior on color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Wallpaper Picker")
                tooltip: Translation.tr("Quick wallpaper selection widget")
                visible: Config.options?.sidebar?.widgets?.wallpaper ?? false

                ConfigSpinBox {
                    icon: "photo_size_select_large"
                    text: Translation.tr("Thumbnail size")
                    value: Config.options?.sidebar?.widgets?.quickWallpaper?.itemSize ?? 56
                    from: 40
                    to: 80
                    stepSize: 4
                    onValueChanged: Config.setNestedValue("sidebar.widgets.quickWallpaper.itemSize", value)
                }

                SettingsSwitch {
                    buttonIcon: "title"
                    text: Translation.tr("Show header")
                    checked: Config.options?.sidebar?.widgets?.quickWallpaper?.showHeader ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.quickWallpaper.showHeader", checked)
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "swipe"
                    text: Translation.tr("Scroll horizontally to browse wallpapers")
                }
            }

            ContentSubsection {
                title: Translation.tr("Glance Header")
                tooltip: Translation.tr("Configure the header with time and quick indicators")

                SettingsSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Volume button")
                    checked: Config.options?.sidebar?.widgets?.glance?.showVolume ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.glance.showVolume", checked)
                }

                SettingsSwitch {
                    buttonIcon: "sports_esports"
                    text: Translation.tr("Game mode indicator")
                    checked: Config.options?.sidebar?.widgets?.glance?.showGameMode ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.glance.showGameMode", checked)
                }

                SettingsSwitch {
                    buttonIcon: "do_not_disturb_on"
                    text: Translation.tr("Do not disturb indicator")
                    checked: Config.options?.sidebar?.widgets?.glance?.showDnd ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.glance.showDnd", checked)
                }
            }

            ContentSubsection {
                title: Translation.tr("Status Rings")
                tooltip: Translation.tr("Configure which system metrics to show")

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "memory"
                        text: Translation.tr("CPU usage")
                        checked: Config.options?.sidebar?.widgets?.statusRings?.showCpu ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.statusRings.showCpu", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "memory_alt"
                        text: Translation.tr("RAM usage")
                        checked: Config.options?.sidebar?.widgets?.statusRings?.showRam ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.statusRings.showRam", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "hard_drive"
                        text: Translation.tr("Disk usage")
                        checked: Config.options?.sidebar?.widgets?.statusRings?.showDisk ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.statusRings.showDisk", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "thermostat"
                        text: Translation.tr("Temperature")
                        checked: Config.options?.sidebar?.widgets?.statusRings?.showTemp ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.statusRings.showTemp", checked)
                    }
                }

                SettingsSwitch {
                    buttonIcon: "battery_full"
                    text: Translation.tr("Battery")
                    checked: Config.options?.sidebar?.widgets?.statusRings?.showBattery ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.statusRings.showBattery", checked)
                }
            }

            ContentSubsection {
                title: Translation.tr("Controls Card")
                tooltip: Translation.tr("Configure which toggles and actions to show")

                ContentSubsectionLabel { text: Translation.tr("Toggles") }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "dark_mode"
                        text: Translation.tr("Dark mode")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showDarkMode ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showDarkMode", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "do_not_disturb_on"
                        text: Translation.tr("Do not disturb")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showDnd ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showDnd", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "nightlight"
                        text: Translation.tr("Night light")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showNightLight ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showNightLight", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "sports_esports"
                        text: Translation.tr("Game mode")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showGameMode ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showGameMode", checked)
                    }
                }

                ContentSubsectionLabel { text: Translation.tr("Actions") }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "wifi"
                        text: Translation.tr("Network")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showNetwork ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showNetwork", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "bluetooth"
                        text: Translation.tr("Bluetooth")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showBluetooth ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showBluetooth", checked)
                    }
                }

                ConfigRow {
                    uniform: true

                    SettingsSwitch {
                        buttonIcon: "settings"
                        text: Translation.tr("Settings")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showSettings ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showSettings", checked)
                    }

                    SettingsSwitch {
                        buttonIcon: "lock"
                        text: Translation.tr("Lock")
                        checked: Config.options?.sidebar?.widgets?.controlsCard?.showLock ?? true
                        onCheckedChanged: Config.setNestedValue("sidebar.widgets.controlsCard.showLock", checked)
                    }
                }
            }
        }
    }
    }

}
