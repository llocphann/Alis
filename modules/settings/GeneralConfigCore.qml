import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 1
    settingsPageName: Translation.tr("System")
    property string activeSection: "audio"

    SettingsTaskNavigator {
        showTabBar: true
        showIntro: false
        icon: "browse"
        title: Translation.tr("System")
        description: Translation.tr("Audio, battery, time, window behavior and lock screen security.")
        summary: Translation.tr("Audio, Power & Time · Lock Screen & Security")
        currentValue: (root.activeSection === "input" || root.activeSection === "locale") ? "audio" : root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Audio, Power & Time"), icon: "volume_up", value: "audio" },
            { displayName: Translation.tr("Lock Screen & Security"), icon: "lock", value: "safety" }
        ]
    }

    // ==================== HUB LEFT: AUDIO & SOUNDS ====================
    SettingsCardSection {
        id: audioSoundsSection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: root.activeSection === "audio" || root.activeSection === "locale" || root.activeSection === "input"
        expanded: true
        icon: "volume_up"
        title: Translation.tr("Audio & Sounds")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "hearing"
                    text: Translation.tr("Earbang protection")
                    checked: Config.options?.audio?.protection?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("audio.protection.enable", checked)
                    StyledToolTip {
                        text: Translation.tr("Prevents abrupt volume spikes and enforces a safe maximum limit")
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options?.audio?.protection?.enable ?? false
                    icon: "vertical_align_top"
                    text: Translation.tr("Max volume (%)")
                    value: Config.options?.audio?.protection?.maxAllowed ?? 100
                    from: 20
                    to: 154
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("audio.protection.maxAllowed", value)
                    StyledToolTip {
                        text: Translation.tr("Maximum allowed volume percentage")
                    }
                }
            }

            SettingsDivider {}

            SettingsSliderRow {
                icon: "notification_sound"
                text: Translation.tr("System sound volume")
                from: 0
                to: 1
                stepSize: 0.05
                value: Config.options?.sounds?.volume ?? 0.5
                displayValue: Math.round((Config.options?.sounds?.volume ?? 0.5) * 100) + "%"
                settingsSearchLabel: Translation.tr("Sound volume")
                settingsSearchKeywords: ["sound", "volume", "audio", "event"]
                onMoved: nextVal => Config.setNestedValue("sounds.volume", nextVal)
            }

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notifications")
                    checked: Config.options?.sounds?.notifications ?? true
                    onCheckedChanged: Config.setNestedValue("sounds.notifications", checked)
                }
                SettingsSwitch {
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery alerts")
                    checked: Config.options?.sounds?.battery ?? false
                    onCheckedChanged: Config.setNestedValue("sounds.battery", checked)
                }
            }

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "hourglass_empty"
                    text: Translation.tr("Countdown timer")
                    checked: Config.options?.sounds?.timer ?? false
                    onCheckedChanged: Config.setNestedValue("sounds.timer", checked)
                }
                SettingsSwitch {
                    buttonIcon: "av_timer"
                    text: Translation.tr("Pomodoro timer")
                    checked: Config.options?.sounds?.pomodoro ?? false
                    onCheckedChanged: Config.setNestedValue("sounds.pomodoro", checked)
                }
            }
        }
    }

    // ==================== HUB RIGHT: BATTERY & POWER ====================
    SettingsCardSection {
        id: batterySection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: root.activeSection === "audio" || root.activeSection === "locale" || root.activeSection === "input"
        expanded: true
        icon: "battery_saver"
        title: Translation.tr("Battery & Power")

        SettingsGroup {
            ConfigSpinBox {
                objectName: "batteryLowWarningControl"
                icon: "warning"
                text: Translation.tr("Low battery warning (%)")
                value: Config.options?.battery?.low ?? 20
                from: 0
                to: 100
                stepSize: 5
                onValueModified: value => Config.setNestedValue("battery.low", value)
            }
            ConfigSpinBox {
                objectName: "batteryCriticalWarningControl"
                icon: "dangerous"
                text: Translation.tr("Critical battery warning (%)")
                value: Config.options?.battery?.critical ?? 10
                from: 0
                to: 100
                stepSize: 5
                onValueModified: value => Config.setNestedValue("battery.critical", value)
            }
            ConfigSpinBox {
                objectName: "batteryFullWarningControl"
                icon: "charger"
                text: Translation.tr("Full / Plugged alert (%)")
                value: Config.options?.battery?.full ?? 101
                from: 0
                to: 101
                stepSize: 5
                onValueModified: value => Config.setNestedValue("battery.full", value)
            }

            SettingsDivider {}

            ConfigRow {
                uniform: false

                SettingsSwitch {
                    objectName: "batteryAutomaticSuspendControl"
                    buttonIcon: "pause"
                    text: Translation.tr("Automatic suspend on low battery")
                    checked: Config.options?.battery?.automaticSuspend ?? false
                    autoToggle: false
                    onToggledByUser: checked => Config.setNestedValue("battery.automaticSuspend", checked)
                }
                ConfigSpinBox {
                    objectName: "batterySuspendThresholdControl"
                    enabled: Config.options?.battery?.automaticSuspend ?? false
                    text: Translation.tr("at (%)")
                    value: Config.options?.battery?.suspend ?? 5
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueModified: value => Config.setNestedValue("battery.suspend", value)
                }
            }

            SettingsDivider {}

            SettingsDrillDownRow {
                iconName: "bolt"
                title: Translation.tr("TLP & Charge Care")
                description: Translation.tr("Configure battery charge thresholds, CPU boost and TLP power profiles")
                statusText: AlisIntergration.tlpEnabled ? Translation.tr("Active") : ""
                onClicked: SettingsPageRegistry.navigateToKey("integrations", "TLP")
            }
        }
    }

    // ==================== HUB CARD 3: TIME, DATE & WINDOW BEHAVIOR ====================
    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: root.activeSection === "audio" || root.activeSection === "locale" || root.activeSection === "input"
        expanded: true
        icon: "schedule"
        title: Translation.tr("Time, Date & Window Behavior")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "pace"
                    text: Translation.tr("Show clock seconds")
                    checked: Config.options?.time?.secondPrecision ?? false
                    onCheckedChanged: Config.setNestedValue("time.secondPrecision", checked)
                    StyledToolTip {
                        text: Translation.tr("Show seconds on the bar and lock screen clock")
                    }
                }

                SettingsSwitch {
                    visible: CompositorService.isNiri
                    buttonIcon: "help"
                    text: Translation.tr("Confirm window close")
                    checked: Config.options?.closeConfirm?.enabled ?? false
                    onCheckedChanged: Config.setNestedValue("closeConfirm.enabled", checked)
                    StyledToolTip {
                        text: Translation.tr("Show a confirmation dialog when pressing Super+Q")
                    }
                }
            }

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Clock format")

                ConfigSelectionArray {
                    currentValue: Config.options?.time?.format ?? "hh:mm"
                    onSelected: newValue => Config.setNestedValue("time.format", newValue)
                    options: [
                        { displayName: Translation.tr("24h"), value: "hh:mm" },
                        { displayName: Translation.tr("12h am/pm"), value: "h:mm ap" },
                        { displayName: Translation.tr("12h AM/PM"), value: "h:mm AP" }
                    ]
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    ContentSubsectionLabel {
                        text: Translation.tr("Long date format")
                    }
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("e.g. dddd, MMMM dd")
                        text: Config.options?.time?.dateFormat ?? "ddd, dd/MM"
                        onEditingFinished: Config.setNestedValue("time.dateFormat", text)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    ContentSubsectionLabel {
                        text: Translation.tr("Short date format")
                    }
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("e.g. dd/MM")
                        text: Config.options?.time?.shortDateFormat ?? "dd/MM"
                        onEditingFinished: Config.setNestedValue("time.shortDateFormat", text)
                    }
                }
            }
        }
    }

    // ==================== DRILL-DOWN 2: LOCK SCREEN & SECURITY (2 BENTO CARDS) ====================
    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "safety"
        visible: root.activeSection === "safety"
        expanded: true
        icon: "shield_lock"
        title: Translation.tr("Security & Lock Behavior")

        SettingsGroup {
            SettingsSwitch {
                visible: CompositorService.isHyprland
                buttonIcon: "water_drop"
                text: Translation.tr("Use Hyprlock (instead of Quickshell)")
                checked: Config.options?.lock?.useHyprlock ?? false
                onCheckedChanged: Config.setNestedValue("lock.useHyprlock", checked)
            }

            SettingsSwitch {
                buttonIcon: "account_circle"
                text: Translation.tr("Lock on startup")
                checked: Config.options?.lock?.launchOnStartup ?? false
                onCheckedChanged: Config.setNestedValue("lock.launchOnStartup", checked)
            }

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "settings_power"
                    text: Translation.tr("Password for power actions")
                    checked: Config.options?.lock?.security?.requirePasswordToPower ?? true
                    onCheckedChanged: Config.setNestedValue("lock.security.requirePasswordToPower", checked)
                }

                SettingsSwitch {
                    buttonIcon: "key_vertical"
                    text: Translation.tr("Also unlock keyring")
                    checked: Config.options?.lock?.security?.unlockKeyring ?? true
                    onCheckedChanged: Config.setNestedValue("lock.security.unlockKeyring", checked)
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Show notifications")
                    checked: Config.options?.lock?.notifications?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("lock.notifications.enable", checked)
                }

                SettingsSwitch {
                    enabled: Config.options?.lock?.notifications?.enable ?? false
                    buttonIcon: "visibility"
                    text: Translation.tr("Show notification body")
                    checked: Config.options?.lock?.notifications?.showBody ?? true
                    onCheckedChanged: Config.setNestedValue("lock.notifications.showBody", checked)
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "safety"
        visible: root.activeSection === "safety"
        expanded: true
        icon: "lock"
        title: Translation.tr("Lock Screen Appearance")

        SettingsGroup {
            ConfigRow {
                uniform: true
                ContentSubsection {
                    title: Translation.tr("Clock style")

                    ConfigSelectionArray {
                        currentValue: Config.options?.lock?.clock?.style ?? "default"
                        options: [
                            { displayName: Translation.tr("Default"), value: "default" },
                            { displayName: Translation.tr("Minimal"), value: "minimal" },
                            { displayName: Translation.tr("Analog"), value: "analog" }
                        ]
                        onSelected: newValue => Config.setNestedValue("lock.clock.style", newValue)
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Clock position")

                    ConfigSelectionArray {
                        currentValue: Config.options?.lock?.clock?.position ?? "center"
                        options: [
                            { displayName: Translation.tr("Center"), value: "center" },
                            { displayName: Translation.tr("Top Left"), value: "topLeft" },
                            { displayName: Translation.tr("Bottom Left"), value: "bottomLeft" }
                        ]
                        onSelected: newValue => Config.setNestedValue("lock.clock.position", newValue)
                    }
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Background blur")
                    checked: Config.options?.lock?.blur?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("lock.blur.enable", checked)
                }

                ConfigSpinBox {
                    enabled: Config.options?.lock?.blur?.enable ?? true
                    icon: "blur_linear"
                    text: Translation.tr("Blur radius")
                    value: Config.options?.lock?.blur?.radius ?? 100
                    from: 0
                    to: 200
                    stepSize: 10
                    onValueChanged: Config.setNestedValue("lock.blur.radius", value)
                }
            }

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Dim wallpaper")
                    checked: Config.options?.lock?.dim?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("lock.dim.enable", checked)
                }

                ConfigSpinBox {
                    enabled: Config.options?.lock?.dim?.enable ?? false
                    text: Translation.tr("Dim (%)")
                    icon: "opacity"
                    value: Math.round((Config.options?.lock?.dim?.opacity ?? 0.3) * 100)
                    from: 10
                    to: 80
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("lock.dim.opacity", value / 100)
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "info"
                    text: Translation.tr("Status icons")
                    checked: Config.options?.lock?.status?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("lock.status.enable", checked)
                }
                SettingsSwitch {
                    buttonIcon: "thermostat"
                    text: Translation.tr("Weather")
                    checked: Config.options?.lock?.widgets?.weather ?? true
                    onCheckedChanged: Config.setNestedValue("lock.widgets.weather", checked)
                }
            }

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr("Media player")
                    checked: Config.options?.lock?.widgets?.media ?? true
                    onCheckedChanged: Config.setNestedValue("lock.widgets.media", checked)
                }
                SettingsSwitch {
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Power buttons")
                    checked: Config.options?.lock?.widgets?.powerButtons ?? true
                    onCheckedChanged: Config.setNestedValue("lock.widgets.powerButtons", checked)
                }
            }
        }
    }
}
