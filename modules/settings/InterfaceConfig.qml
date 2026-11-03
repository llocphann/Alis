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
    property bool showAllIiSections: false
    property real notificationsCardMinHeight: 0
    readonly property real notificationsCardImplicitHeight: notificationsCard.naturalCardImplicitHeight
    property string activeSection: "tools"
    readonly property string _legacyTimezoneCopy: Translation.tr("No timezones yet; add or reorder regional suggestions.")

    SettingsTaskNavigator {
        visible: !root.embedded
        showTabBar: true
        showIntro: false
        icon: "bottom_app_bar"
        title: Translation.tr("Panels")
        description: Translation.tr("Panels, notifications and window switcher.")
        summary: Translation.tr("Notifications · Alt-Tab switcher")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Alt-Tab Window Switcher"), icon: "keyboard_tab", value: "tools" },
            { displayName: Translation.tr("Notifications & Center"), icon: "notifications", value: "notifications" }
        ].filter(option => option.value !== "notifications" || root.isIiActive)
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 14

    SettingsCardSection {
        id: notificationsCard
        _preventBentoReparent: true
        _bentoExtraHeight: expanded ? Math.max(0, root.notificationsCardMinHeight - naturalCardImplicitHeight) : 0
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "notifications"
        Layout.columnSpan: 2
        Layout.fillWidth: true
        visible: root.isIiActive && (root.activeSection === "notifications" || ((!root.embedded || root.showAllIiSections) && Config.options?.panelFamily !== "abyss"))
        expanded: true
        icon: "notifications"
        title: Translation.tr("Notifications")

        SettingsGroup {
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                uniformCellWidths: true
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
                visible: Config.options?.notifications?.quietHours?.enable ?? false

                StyledText {
                    text: Translation.tr("From")
                    color: Appearance.zzzEverywhere ? Appearance.zzz.ink
                        : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnSurface
                }
                MaterialTextField {
                    Layout.preferredWidth: 90
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
                buttonIcon: "notifications_off"
                text: Translation.tr("Hide wallpaper upscale notification")
                checked: Config.options?.background?.hideUpscaleNotification ?? false
                onCheckedChanged: Config.setNestedValue("background.hideUpscaleNotification", checked)
                StyledToolTip {
                    text: Translation.tr("Don't show notification when wallpaper resolution is lower than screen")
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
                Layout.topMargin: -8
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

            SettingsDivider {
                visible: parent.parent.columns === 1
            }

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
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "tools"
        visible: root.isIiActive && root.activeSection === "tools"
        expanded: true
        icon: "keyboard_tab"
        title: Translation.tr("Alt-Tab Behavior & Animation")

        SettingsGroup {
            SettingsSwitch {
                enabled: (Config.options?.altSwitcher?.preset ?? "default") !== "skew"
                buttonIcon: "visibility_off"
                text: Translation.tr("No visual UI (cycle windows only)")
                checked: (Config.options?.altSwitcher?.preset ?? "default") === "skew"
                    ? false
                    : (Config.options?.altSwitcher?.noVisualUi ?? false)
                onCheckedChanged: Config.setNestedValue("altSwitcher.noVisualUi", checked)
            }

            SettingsSwitch {
                buttonIcon: "history"
                text: Translation.tr("Most recently used first")
                checked: Config.options?.altSwitcher?.useMostRecentFirst ?? true
                onCheckedChanged: Config.setNestedValue("altSwitcher.useMostRecentFirst", checked)
            }

            SettingsSwitch {
                buttonIcon: "overview_key"
                text: Translation.tr("Show Niri overview while switching")
                checked: Config.options?.altSwitcher?.showOverviewWhileSwitching ?? false
                onCheckedChanged: Config.setNestedValue("altSwitcher.showOverviewWhileSwitching", checked)
            }

            SettingsSwitch {
                buttonIcon: "movie"
                text: Translation.tr("Enable slide animation")
                checked: Config.options?.altSwitcher?.enableAnimation ?? true
                onCheckedChanged: Config.setNestedValue("altSwitcher.enableAnimation", checked)
            }

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Animation duration (ms)")
                value: Config.options?.altSwitcher?.animationDurationMs ?? 200
                from: 0
                to: 1000
                stepSize: 25
                onValueChanged: Config.setNestedValue("altSwitcher.animationDurationMs", value)
            }

            ConfigSpinBox {
                icon: "hourglass_top"
                text: Translation.tr("Auto-hide delay (ms)")
                value: Config.options?.altSwitcher?.autoHideDelayMs ?? 500
                from: 50
                to: 2000
                stepSize: 50
                onValueChanged: Config.setNestedValue("altSwitcher.autoHideDelayMs", value)
            }
        }
    }

    SettingsCardSection {
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "tools"
        visible: root.isIiActive && root.activeSection === "tools"
        expanded: true
        icon: "styler"
        title: Translation.tr("Alt-Tab Appearance & Layout")

        SettingsGroup {
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

            SettingsSwitch {
                buttonIcon: "colors"
                text: Translation.tr("Tint app icons")
                checked: Config.options?.altSwitcher?.monochromeIcons ?? false
                onCheckedChanged: Config.setNestedValue("altSwitcher.monochromeIcons", checked)
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Background opacity (%)")
                value: Math.round((Config.options?.altSwitcher?.backgroundOpacity ?? 0.9) * 100)
                from: 10
                to: 100
                stepSize: 5
                onValueChanged: Config.setNestedValue("altSwitcher.backgroundOpacity", value / 100)
            }

            ConfigSpinBox {
                icon: "blur_on"
                text: Translation.tr("Blur amount (%)")
                value: Math.round((Config.options?.altSwitcher?.blurAmount ?? 0.4) * 100)
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: Config.setNestedValue("altSwitcher.blurAmount", value / 100)
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
            }
        }
    }
    }

}
