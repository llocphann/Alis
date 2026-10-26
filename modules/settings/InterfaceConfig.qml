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
    property string activeSection: "tools"
    readonly property string _legacyTimezoneCopy: Translation.tr("No timezones yet; add or reorder regional suggestions.")

    SettingsTaskNavigator {
        visible: !root.embedded
        showTabBar: false
        icon: "bottom_app_bar"
        title: Translation.tr("Panels")
        description: Translation.tr("Panels, notifications, widgets and floating tools.")
        summary: Translation.tr("Floating tools · visual effects · Alt-Tab switcher")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Tools"), icon: "dashboard_customize", value: "tools" },
            { displayName: Translation.tr("Notifications"), icon: "notifications", value: "notifications" }
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
        visible: root.activeSection === "tools"

    SettingsCardSection {
        Layout.fillWidth: true
        settingsTaskSection: "tools"
        visible: root.activeSection === "tools"
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
        visible: root.activeSection === "tools"
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
        settingsTaskSection: "notifications"
        Layout.columnSpan: parent.columns
        Layout.fillWidth: true
        visible: root.isIiActive && root.activeSection === "notifications"
        expanded: true
        icon: "notifications"
        title: Translation.tr("Notifications")

        SettingsGroup {
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 620 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 16
                rowSpacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

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
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

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
                visible: Config.options?.panelFamily !== "abyss"

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
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        settingsTaskSection: "tools"
        visible: root.isIiActive && root.activeSection === "tools"
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
    }

}
