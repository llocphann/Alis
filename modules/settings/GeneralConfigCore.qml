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
    property bool showIntegrationSettings: false
    property string activeSection: "audio"

    readonly property bool _outputMuted: Boolean(Audio.sink?.audio?.muted)
    readonly property int _outputPercent: Math.round((Audio.osdSinkVolume ?? Audio.value ?? 0) * 100)
    readonly property int _inputPercent: Math.round((Audio.micVolume ?? 0) * 100)

    SettingsTaskNavigator {
        showTabBar: false
        showIntro: false
        icon: "browse"
        title: Translation.tr("System")
        description: Translation.tr("Audio, battery, time, window behavior and lock screen security.")
        summary: Translation.tr("Audio, Power & Time · Lock Screen & Security")
        currentValue: (root.activeSection === "input" || root.activeSection === "locale" || root.activeSection === "safety") ? root.activeSection : "audio"
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("System & Security"), icon: "browse", value: "audio" }
        ]
    }

    // ==================== 01: SOUND DEVICES & APP MIXER ====================
    SettingsCardSection {
        id: soundDevicesSection
        objectName: "systemSoundDevicesSection"
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: true
        expanded: true
        icon: "speaker"
        title: Translation.tr("Sound Devices & App Mixer")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    toggled: root._outputMuted
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Audio.toggleMute()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root._outputMuted ? "volume_off" : "volume_up"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root._outputMuted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }

                SettingsSliderRow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    icon: ""
                    text: Translation.tr("Output volume")
                    from: 0
                    to: (Config.options?.audio?.protection?.enable ?? false)
                        ? (Config.options?.audio?.protection?.maxAllowed ?? 100)
                        : 150
                    stepSize: 1
                    value: root._outputPercent
                    displayValue: root._outputMuted ? Translation.tr("Muted") : (root._outputPercent + "%")
                    onMoved: nextVal => Audio.setSinkVolume(nextVal / 100.0)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Audio.outputDevices.length > 0

                Repeater {
                    model: Audio.outputDevices

                    delegate: RippleButton {
                        id: sysSinkRow
                        required property var modelData
                        readonly property bool isDefault: (Audio.defaultSink?.id ?? -1) === (modelData?.id ?? -2)
                            || (Audio.sink?.id ?? -1) === (modelData?.id ?? -2)

                        Layout.fillWidth: true
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.small
                        colBackground: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                            : Appearance.colors.colLayer2
                        colBackgroundHover: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            : Appearance.colors.colLayer2Hover
                        onClicked: Audio.setDefaultSink(modelData)

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: sysSinkRow.isDefault ? "radio_button_checked" : "speaker"
                                iconSize: Appearance.font.pixelSize.normal
                                color: sysSinkRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Audio.friendlyDeviceName(sysSinkRow.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: sysSinkRow.isDefault ? Font.DemiBold : Font.Normal
                                color: sysSinkRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    toggled: Audio.micMuted
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Audio.toggleMicMute()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: Audio.micMuted ? "mic_off" : "mic"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Audio.micMuted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }

                SettingsSliderRow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    icon: ""
                    text: Translation.tr("Input volume")
                    from: 0
                    to: 150
                    stepSize: 1
                    value: root._inputPercent
                    displayValue: Audio.micMuted ? Translation.tr("Muted") : (root._inputPercent + "%")
                    onMoved: nextVal => Audio.setSourceVolume(nextVal / 100.0)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Audio.inputDevices.length > 0

                Repeater {
                    model: Audio.inputDevices

                    delegate: RippleButton {
                        id: sysSourceRow
                        required property var modelData
                        readonly property bool isDefault: (Audio.source?.id ?? -1) === (modelData?.id ?? -2)

                        Layout.fillWidth: true
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.small
                        colBackground: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                            : Appearance.colors.colLayer2
                        colBackgroundHover: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            : Appearance.colors.colLayer2Hover
                        onClicked: Audio.setDefaultSource(modelData)

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: sysSourceRow.isDefault ? "radio_button_checked" : "mic"
                                iconSize: Appearance.font.pixelSize.normal
                                color: sysSourceRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Audio.friendlyDeviceName(sysSourceRow.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: sysSourceRow.isDefault ? Font.DemiBold : Font.Normal
                                color: sysSourceRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            SettingsDivider {
                visible: Audio.outputAppNodes.length > 0
            }

            Repeater {
                model: Audio.outputAppNodes

                delegate: RowLayout {
                    id: sysAppStreamRow
                    required property var modelData
                    readonly property bool streamMuted: Boolean(modelData?.audio?.muted)
                    readonly property int streamPercent: Math.round((modelData?.audio?.volume ?? 0) * 100)

                    Layout.fillWidth: true
                    spacing: 10

                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        toggled: sysAppStreamRow.streamMuted
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            if (sysAppStreamRow.modelData?.audio)
                                sysAppStreamRow.modelData.audio.muted = !sysAppStreamRow.streamMuted
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: sysAppStreamRow.streamMuted ? "volume_off" : "graphic_eq"
                            iconSize: Appearance.font.pixelSize.small
                            color: sysAppStreamRow.streamMuted ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        }
                    }

                    SettingsSliderRow {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        icon: ""
                        text: Audio.appNodeDisplayName(sysAppStreamRow.modelData)
                        from: 0
                        to: 150
                        stepSize: 1
                        value: sysAppStreamRow.streamPercent
                        displayValue: sysAppStreamRow.streamMuted ? Translation.tr("Muted") : (sysAppStreamRow.streamPercent + "%")
                        onMoved: nextVal => {
                            if (sysAppStreamRow.modelData?.audio)
                                sysAppStreamRow.modelData.audio.volume = nextVal / 100.0
                        }
                    }
                }
            }
        }
    }

    // ==================== 02: AUDIO & SOUNDS ====================
    SettingsCardSection {
        id: batterySection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: true
        expanded: true
        icon: "battery_saver"
        title: Translation.tr("Battery & Power")

        SettingsGroup {
            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    objectName: "batteryLowWarningControl"
                    icon: "warning"
                    text: Translation.tr("Low battery (%)")
                    value: Config.options?.battery?.low ?? 20
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueModified: value => Config.setNestedValue("battery.low", value)
                }

                ConfigSpinBox {
                    objectName: "batteryCriticalWarningControl"
                    icon: "dangerous"
                    text: Translation.tr("Critical (%)")
                    value: Config.options?.battery?.critical ?? 10
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueModified: value => Config.setNestedValue("battery.critical", value)
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    objectName: "batteryFullWarningControl"
                    icon: "charger"
                    text: Translation.tr("Full alert (%)")
                    value: Config.options?.battery?.full ?? 101
                    from: 0
                    to: 101
                    stepSize: 5
                    onValueModified: value => Config.setNestedValue("battery.full", value)
                }

                SettingsSwitch {
                    buttonIcon: "battery_charging_full"
                    text: Translation.tr("Notify when full")
                    checked: Config.options?.battery?.notifyFull ?? true
                    onCheckedChanged: Config.setNestedValue("battery.notifyFull", checked)
                }
            }

            ConfigRow {
                uniform: false

                SettingsSwitch {
                    objectName: "batteryAutomaticSuspendControl"
                    buttonIcon: "pause"
                    text: Translation.tr("Auto-suspend on low battery")
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

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "power_input"
                text: Translation.tr("Restore power profile on login")
                checked: Config.options?.powerProfiles?.restoreOnStart ?? true
                onCheckedChanged: Config.setNestedValue("powerProfiles.restoreOnStart", checked)
            }

            SettingsDivider {}

            SettingsDrillDownRow {
                iconName: "bolt"
                title: Translation.tr("TLP & Charge Care")
                description: Translation.tr("Configure battery charge thresholds, CPU boost and TLP power profiles")
                statusText: AlisIntergration.tlpEnabled ? Translation.tr("Active") : ""
                onClicked: SettingsPageRegistry.navigateToKey("integrations", "TLP")
            }

            SettingsDivider {}

            SettingsDrillDownRow {
                iconName: "mode_fan"
                title: Translation.tr("ThinkFan Thermal Control")
                description: Translation.tr("Configure fan levels, sensor curves and per-profile cooling")
                statusText: AlisIntergration.thinkfanEnabled ? Translation.tr("Active") : ""
                onClicked: SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")
            }
        }
    }

    SettingsCardSection {
        id: audioSoundsSection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: true
        expanded: true
        icon: "volume_up"
        title: Translation.tr("Audio & Sounds")

        SettingsGroup {
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

            ConfigRow {
                uniform: true

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

                ConfigSpinBox {
                    enabled: Config.options?.audio?.protection?.enable ?? false
                    icon: "trending_up"
                    text: Translation.tr("Max step (%)")
                    value: Config.options?.audio?.protection?.maxAllowedIncrease ?? 10
                    from: 2
                    to: 50
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("audio.protection.maxAllowedIncrease", value)
                    StyledToolTip {
                        text: Translation.tr("Maximum volume jump allowed per step")
                    }
                }
            }

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

    SettingsCardSection {
        id: sessionActionsSection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "audio"
        visible: true
        expanded: true
        icon: "power_settings_new"
        title: Translation.tr("Session & Power Actions")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "help"
                    text: Translation.tr("Confirm window close")
                    checked: Config.options?.closeConfirm?.enabled ?? false
                    onCheckedChanged: Config.setNestedValue("closeConfirm.enabled", checked)
                    StyledToolTip {
                        text: Translation.tr("Show a confirmation dialog when pressing Super+Q")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "refresh"
                    text: Translation.tr("Shell reload notices")
                    checked: Config.options?.reloadToasts?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("reloadToasts.enable", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "waving_hand"
                    text: Translation.tr("Boot greeting")
                    checked: Config.options?.bootGreeting?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("bootGreeting.enable", checked)
                }

                SettingsSwitch {
                    buttonIcon: "layers_clear"
                    text: Translation.tr("Auto-clear tray conflicts")
                    checked: Config.options?.conflictKiller?.autoKillTrays ?? false
                    onCheckedChanged: Config.setNestedValue("conflictKiller.autoKillTrays", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "sports_esports"
                    text: Translation.tr("Auto-detect GameMode")
                    checked: Config.options?.gameMode?.autoDetect ?? true
                    onCheckedChanged: Config.setNestedValue("gameMode.autoDetect", checked)
                }

                SettingsSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("GameMode minimal shell")
                    checked: Config.options?.gameMode?.minimalMode ?? true
                    onCheckedChanged: Config.setNestedValue("gameMode.minimalMode", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "notifications_paused"
                    text: Translation.tr("Suppress GameMode alerts")
                    checked: Config.options?.gameMode?.suppressNotifications ?? true
                    onCheckedChanged: Config.setNestedValue("gameMode.suppressNotifications", checked)
                }

                SettingsSwitch {
                    buttonIcon: "notifications_off"
                    text: Translation.tr("Clear alert conflicts")
                    checked: Config.options?.conflictKiller?.autoKillNotificationDaemons ?? false
                    onCheckedChanged: Config.setNestedValue("conflictKiller.autoKillNotificationDaemons", checked)
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "safety"
        visible: true
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

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "account_circle"
                    text: Translation.tr("Lock on startup")
                    checked: Config.options?.lock?.launchOnStartup ?? false
                    onCheckedChanged: Config.setNestedValue("lock.launchOnStartup", checked)
                }

                SettingsSwitch {
                    buttonIcon: "settings_power"
                    text: Translation.tr("Password for power")
                    checked: Config.options?.lock?.security?.requirePasswordToPower ?? true
                    onCheckedChanged: Config.setNestedValue("lock.security.requirePasswordToPower", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "key_vertical"
                    text: Translation.tr("Also unlock keyring")
                    checked: Config.options?.lock?.security?.unlockKeyring ?? true
                    onCheckedChanged: Config.setNestedValue("lock.security.unlockKeyring", checked)
                }

                SettingsSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Lock animations")
                    checked: Config.options?.lock?.enableAnimation ?? true
                    onCheckedChanged: Config.setNestedValue("lock.enableAnimation", checked)
                }
            }

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
                    text: Translation.tr("Notification body")
                    checked: Config.options?.lock?.notifications?.showBody ?? true
                    onCheckedChanged: Config.setNestedValue("lock.notifications.showBody", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "shapes"
                    text: Translation.tr("Shape password glyphs")
                    checked: Config.options?.lock?.materialShapeChars ?? true
                    onCheckedChanged: Config.setNestedValue("lock.materialShapeChars", checked)
                }

                ConfigSpinBox {
                    enabled: Config.options?.lock?.notifications?.enable ?? false
                    icon: "format_list_numbered"
                    text: Translation.tr("Max lock alerts")
                    value: Config.options?.lock?.notifications?.maxCount ?? 3
                    from: 1
                    to: 10
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("lock.notifications.maxCount", value)
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "safety"
        visible: true
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

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "lightbulb"
                    text: Translation.tr("Unlock hint")
                    checked: Config.options?.lock?.widgets?.hintText ?? true
                    onCheckedChanged: Config.setNestedValue("lock.widgets.hintText", checked)
                }
                SettingsSwitch {
                    buttonIcon: "badge"
                    text: Translation.tr("Locked label")
                    checked: Config.options?.lock?.showLockedText ?? true
                    onCheckedChanged: Config.setNestedValue("lock.showLockedText", checked)
                }
            }
        }
    }

    SettingsCardSection {
        id: timeDateSection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "locale"
        visible: true
        expanded: true
        icon: "schedule"
        title: Translation.tr("Time, Date & Format")

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

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Pomodoro focus (m)")
                    value: Math.max(5, Math.round((Config.options?.time?.pomodoro?.focus ?? 1500) / 60))
                    from: 5
                    to: 120
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("time.pomodoro.focus", value * 60)
                }

                ConfigSpinBox {
                    icon: "free_breakfast"
                    text: Translation.tr("Short break (m)")
                    value: Math.max(1, Math.round((Config.options?.time?.pomodoro?.breakTime ?? 300) / 60))
                    from: 1
                    to: 60
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("time.pomodoro.breakTime", value * 60)
                }
            }
        }
    }
}
