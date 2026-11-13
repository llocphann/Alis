import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 7
    settingsPageName: Translation.tr("Services")
    property string activeSection: "system"

    function activateSettingsSearchSection(section: string): bool {
        const parts = String(section ?? "").toLowerCase().split(/[·›]/)
        const label = parts[parts.length - 1].trim()
        if (label.includes("todo") || label.includes("to-do") || label.includes("nexus")
                || label.includes("zettelkasten") || label.includes("quick note")
                || label.includes("calendar") || label === "data") {
            if(label === "data")root.activeSection="data"
            else SettingsPageRegistry.navigateToKey("integrations",section)
            return true
        }
        for (const value of ["system", "network", "search", "updates"]) {
            if (label.includes(value)) {
                root.activeSection = value
                return true
            }
        }
        return false
    }

    SettingsTaskNavigator {
        showTabBar: false
        showIntro: false
        icon: "settings"
        title: Translation.tr("Services")
        description: Translation.tr("Idle, weather, search and update services.")
        summary: Translation.tr("Idle & Weather · System & Shell Updates")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Idle, Weather & Search"), icon: "cloud", value: "system" },
            { displayName: Translation.tr("System & Shell Updates"), icon: "system_update_alt", value: "updates" }
        ]
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 14

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "system"
        visible: true
        expanded: true
        icon: "bedtime"
        title: Translation.tr("Idle, Sleep & GPU")

        SettingsGroup {
            ConfigSpinBox {
                icon: "monitor"
                text: Translation.tr("Screen off") + ` (${value > 0 ? Math.floor(value/60) + "m " + (value%60) + "s" : Translation.tr("disabled")})`
                value: Config.options?.idle?.screenOffTimeout ?? 300
                from: 0
                to: 3600
                stepSize: 30
                onValueChanged: Config.setNestedValue("idle.screenOffTimeout", value)
                StyledToolTip {
                    text: Translation.tr("Turn off display after this many seconds of inactivity (0 = never)")
                }
            }

            ConfigSpinBox {
                icon: "lock"
                text: Translation.tr("Lock screen") + ` (${value > 0 ? Math.floor(value/60) + "m" : Translation.tr("disabled")})`
                value: Config.options?.idle?.lockTimeout ?? 600
                from: 0
                to: 3600
                stepSize: 60
                onValueChanged: Config.setNestedValue("idle.lockTimeout", value)
                StyledToolTip {
                    text: Translation.tr("Lock screen after this many seconds of inactivity (0 = never)")
                }
            }

            ConfigSpinBox {
                icon: "dark_mode"
                text: Translation.tr("Suspend") + ` (${value > 0 ? Math.floor(value/60) + "m" : Translation.tr("disabled")})`
                value: Config.options?.idle?.suspendTimeout ?? 0
                from: 0
                to: 7200
                stepSize: 60
                onValueChanged: Config.setNestedValue("idle.suspendTimeout", value)
                StyledToolTip {
                    text: Translation.tr("Suspend system after this many seconds of inactivity (0 = never)")
                }
            }

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Lock before sleep")
                    checked: Config.options?.idle?.lockBeforeSleep ?? true
                    onCheckedChanged: Config.setNestedValue("idle.lockBeforeSleep", checked)
                }

                SettingsSwitch {
                    buttonIcon: "coffee"
                    text: Translation.tr("Keep awake (caffeine)")
                    checked: Idle.inhibit
                    onCheckedChanged: {
                        if (checked !== Idle.inhibit) Idle.toggleInhibit()
                    }
                }
            }

            SettingsSwitch {
                visible: Battery.available
                buttonIcon: "battery_saver"
                text: Translation.tr("Separate timeouts on battery")
                checked: Config.options?.idle?.onBattery?.enable ?? false
                onCheckedChanged: Config.setNestedValue("idle.onBattery.enable", checked)
            }

            ConfigSpinBox {
                visible: Battery.available && (Config.options?.idle?.onBattery?.enable ?? false)
                icon: "lock_clock"
                text: Translation.tr("Battery: screen off") + ` (${value > 0 ? Math.floor(value/60) + "m" : Translation.tr("disabled")})`
                value: Config.options?.idle?.onBattery?.screenOffTimeout ?? 120
                from: 0
                to: 3600
                stepSize: 30
                onValueChanged: Config.setNestedValue("idle.onBattery.screenOffTimeout", value)
            }

            ConfigSpinBox {
                visible: Battery.available && (Config.options?.idle?.onBattery?.enable ?? false)
                icon: "lock"
                text: Translation.tr("Battery: lock") + ` (${value > 0 ? Math.floor(value/60) + "m" : Translation.tr("disabled")})`
                value: Config.options?.idle?.onBattery?.lockTimeout ?? 300
                from: 0
                to: 7200
                stepSize: 30
                onValueChanged: Config.setNestedValue("idle.onBattery.lockTimeout", value)
            }

            ConfigSpinBox {
                visible: Battery.available && (Config.options?.idle?.onBattery?.enable ?? false)
                icon: "dark_mode"
                text: Translation.tr("Battery: suspend") + ` (${value > 0 ? Math.floor(value/60) + "m" : Translation.tr("disabled")})`
                value: Config.options?.idle?.onBattery?.suspendTimeout ?? 600
                from: 0
                to: 7200
                stepSize: 60
                onValueChanged: Config.setNestedValue("idle.onBattery.suspendTimeout", value)
            }

            SettingsDivider {}

            SettingsSwitch {
                buttonIcon: "memory_alt"
                text: Translation.tr("GPU usage monitoring")
                checked: Config.options?.resources?.monitorGpu ?? true
                onCheckedChanged: {
                    Config.setNestedValue("resources.monitorGpu", checked)
                }
                StyledToolTip {
                    text: Translation.tr("On hybrid laptops, GPU polling can wake the dGPU; disabling pins Qt to iGPU after restart.")
                }
            }
        }
    }

    SettingsCardSection {
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "updates"
        visible: true
        expanded: true
        icon: "system_update_alt"
        title: Translation.tr("Updates")

        SettingsGroup {
            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Check interval") + ` (${value}m)`
                value: Config.options?.updates?.checkInterval ?? 120
                from: 15
                to: 1440
                stepSize: 15
                onValueChanged: Config.setNestedValue("updates.checkInterval", value)
                StyledToolTip {
                    text: Translation.tr("How often to check for system updates (in minutes)")
                }
            }

            ConfigSpinBox {
                icon: "notifications"
                text: Translation.tr("Show icon threshold")
                value: Config.options?.updates?.adviseUpdateThreshold ?? 10
                from: 1
                to: 200
                stepSize: 5
                onValueChanged: Config.setNestedValue("updates.adviseUpdateThreshold", value)
                StyledToolTip {
                    text: Translation.tr("Show update icon in bar when available updates exceed this number")
                }
            }

            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Warning threshold")
                value: Config.options?.updates?.stronglyAdviseUpdateThreshold ?? 50
                from: 10
                to: 500
                stepSize: 10
                onValueChanged: Config.setNestedValue("updates.stronglyAdviseUpdateThreshold", value)
                StyledToolTip {
                    text: Translation.tr("Show warning color when available updates exceed this number")
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Update command")
                text: Config.options?.apps?.update ?? ""
                wrapMode: TextEdit.Wrap
                onTextChanged: Config.setNestedValue("apps.update", text)
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "updates"
        visible: true
        expanded: true
        icon: "deployed_code_update"
        title: Translation.tr("Alis Shell Updates")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Check for shell updates and notify on the bar.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }

            SettingsSwitch {
                buttonIcon: "toggle_on"
                text: Translation.tr("Enable shell update checker")
                checked: Config.options?.shellUpdates?.enabled ?? true
                onCheckedChanged: Config.setNestedValue("shellUpdates.enabled", checked)
            }

            ConfigSpinBox {
                icon: "schedule"
                text: Translation.tr("Check interval") + ` (${value}m)`
                value: Config.options?.shellUpdates?.checkIntervalMinutes ?? 360
                from: 30
                to: 1440
                stepSize: 30
                onValueChanged: Config.setNestedValue("shellUpdates.checkIntervalMinutes", value)
                enabled: Config.options?.shellUpdates?.enabled ?? true
                StyledToolTip {
                    text: Translation.tr("How often to check for Alis updates (in minutes). Default: 360 (6 hours)")
                }
            }

            SettingsSwitch {
                buttonIcon: "terminal"
                text: Translation.tr("Open terminal during update")
                checked: Config.options?.shellUpdates?.openTerminalOnUpdate ?? true
                enabled: Config.options?.shellUpdates?.enabled ?? true
                onCheckedChanged: Config.setNestedValue("shellUpdates.openTerminalOnUpdate", checked)
                StyledToolTip {
                    text: Translation.tr("Run setup in a terminal for full output; off updates silently with bar status.")
                }
            }

            // Status card with visual states
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: statusCardCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                visible: Config.options?.shellUpdates?.enabled ?? true

                color: {
                    if (ShellUpdates.hasUpdate) return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.92)
                    if (ShellUpdates.lastError.length > 0) return ColorUtils.transparentize(Appearance.colors.colError, 0.92)
                    return Appearance.colors.colSurfaceContainerLow
                }
                border.width: 1
                border.color: {
                    if (ShellUpdates.hasUpdate) return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
                    if (ShellUpdates.lastError.length > 0) return ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                    return Appearance.colors.colLayer0Border
                }

                Behavior on color { animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on border.color { animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                ColumnLayout {
                    id: statusCardCol
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 10

                    // Status header with icon
                    RowLayout {
                        spacing: 10
                        Layout.fillWidth: true

                        Rectangle {
                            width: 40
                            height: 40
                            radius: Appearance.rounding.small
                            color: {
                                if (ShellUpdates.hasUpdate) return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                                if (ShellUpdates.isChecking || ShellUpdates.isUpdating) return ColorUtils.transparentize(Appearance.colors.colSubtext, 0.85)
                                if (ShellUpdates.lastError.length > 0) return ColorUtils.transparentize(Appearance.colors.colError, 0.8)
                                return ColorUtils.transparentize(Appearance.colors.colTertiary, 0.85)
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: {
                                    if (ShellUpdates.isUpdating) return "hourglass_top"
                                    if (ShellUpdates.isChecking) return "sync"
                                    if (ShellUpdates.hasUpdate) return "upgrade"
                                    if (ShellUpdates.lastError.length > 0) return "error"
                                    if (ShellUpdates.available) return "check_circle"
                                    return "cloud_off"
                                }
                                iconSize: Appearance.font.pixelSize.huge
                                color: {
                                    if (ShellUpdates.hasUpdate) return Appearance.colors.colPrimary
                                    if (ShellUpdates.lastError.length > 0) return Appearance.colors.colError
                                    if (ShellUpdates.available) return Appearance.colors.colTertiary
                                    return Appearance.colors.colSubtext
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            StyledText {
                                text: {
                                    if (ShellUpdates.isUpdating) {
                                        if (ShellUpdates.updateStepMessage.length > 0) {
                                            return Translation.tr(ShellUpdates.updateStepMessage) + (ShellUpdates.updateStep > 0 ? " (" + ShellUpdates.updateStep + "/" + ShellUpdates.updateTotalSteps + ")" : "")
                                        }
                                        return Translation.tr("Updating…")
                                    }
                                    if (ShellUpdates.isChecking) return Translation.tr("Checking for updates…")
                                    if (ShellUpdates.hasUpdate) return Translation.tr("Update available")
                                    if (ShellUpdates.managedExternally) return "Managed externally"
                                    if (ShellUpdates.lastError.length > 0) return Translation.tr("Error")
                                    if (ShellUpdates.available) return Translation.tr("Up to date")
                                    return Translation.tr("Not available")
                                }
                                font {
                                    pixelSize: Appearance.font.pixelSize.normal
                                    weight: Font.DemiBold
                                }
                                color: {
                                    if (ShellUpdates.hasUpdate) return Appearance.colors.colPrimary
                                    if (ShellUpdates.lastError.length > 0) return Appearance.colors.colError
                                    return Appearance.colors.colOnSurface
                                }
                            }

                            StyledText {
                                visible: ShellUpdates.hasUpdate
                                text: Translation.tr("%1 commit(s) behind on %2").arg(ShellUpdates.commitsBehind).arg(ShellUpdates.currentBranch || "main")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                visible: !ShellUpdates.hasUpdate && !ShellUpdates.isChecking && !ShellUpdates.isUpdating && ShellUpdates.lastError.length === 0 && ShellUpdates.available
                                text: ShellUpdates.currentBranch.length > 0
                                    ? Translation.tr("Branch: %1").arg(ShellUpdates.currentBranch)
                                    : ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: ShellUpdates.isNonMainBranch
                                    ? Appearance.colors.colTertiary
                                    : Appearance.colors.colSubtext
                            }

                            StyledText {
                                visible: ShellUpdates.isNonMainBranch && !ShellUpdates.isChecking && !ShellUpdates.isUpdating
                                text: Translation.tr("Non-release branch — updates track %1").arg(ShellUpdates.currentBranch)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colTertiary
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                visible: ShellUpdates.managedExternally
                                text: ShellUpdates.unavailableHint
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // Version comparison row
                    RowLayout {
                        visible: ShellUpdates.localCommit.length > 0
                        spacing: 8
                        Layout.fillWidth: true

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: localCommitCol.implicitHeight + 12
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            ColumnLayout {
                                id: localCommitCol
                                anchors {
                                    fill: parent
                                    margins: 6
                                }
                                spacing: 2

                                StyledText {
                                    text: Translation.tr("Current")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: ShellUpdates.localCommit || "—"
                                    font {
                                        pixelSize: Appearance.font.pixelSize.smaller
                                        family: Appearance.font.family.monospace
                                        weight: Font.Medium
                                    }
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }

                        MaterialSymbol {
                            visible: ShellUpdates.hasUpdate && ShellUpdates.remoteCommit.length > 0
                            text: "arrow_forward"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }

                        Rectangle {
                            visible: ShellUpdates.hasUpdate && ShellUpdates.remoteCommit.length > 0
                            Layout.fillWidth: true
                            implicitHeight: remoteCommitCol.implicitHeight + 12
                            radius: Appearance.rounding.small
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                            border.width: 1
                            border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)

                            ColumnLayout {
                                id: remoteCommitCol
                                anchors {
                                    fill: parent
                                    margins: 6
                                }
                                spacing: 2

                                StyledText {
                                    text: Translation.tr("Available")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colPrimary
                                    opacity: 0.8
                                }
                                StyledText {
                                    text: ShellUpdates.remoteCommit || "—"
                                    font {
                                        pixelSize: Appearance.font.pixelSize.smaller
                                        family: Appearance.font.family.monospace
                                        weight: Font.DemiBold
                                    }
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }

                    // Latest commit message
                    RowLayout {
                        visible: ShellUpdates.latestMessage.length > 0 && ShellUpdates.hasUpdate
                        spacing: 6
                        Layout.fillWidth: true

                        MaterialSymbol {
                            text: "notes"
                            iconSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            Layout.alignment: Qt.AlignTop
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: ShellUpdates.latestMessage
                            font {
                                pixelSize: Appearance.font.pixelSize.smallest
                                family: Appearance.font.family.monospace
                            }
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    // Error display
                    RowLayout {
                        visible: ShellUpdates.lastError.length > 0
                        spacing: 6
                        Layout.fillWidth: true

                        MaterialSymbol {
                            text: "warning"
                            iconSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colError
                            Layout.alignment: Qt.AlignTop
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: ShellUpdates.lastError
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colError
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // Action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: Config.options?.shellUpdates?.enabled ?? true

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSurfaceContainerLow
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    enabled: !ShellUpdates.isChecking && !ShellUpdates.isUpdating && !ShellUpdates.managedExternally
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: ShellUpdates.check()

                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdates.isChecking ? Translation.tr("Checking…") : Translation.tr("Check Now")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSurfaceContainerLow
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: {
                        if (Config.options?.settingsUi?.overlayMode ?? false) {
                            // Overlay mode: settings runs inside the main shell process — direct call works
                            ShellUpdates.openOverlay()
                        } else {
                            // Separate window mode (default): settings.qml is a separate qs process.
                            // Singletons are isolated per-process, so we must use IPC to reach
                            // the main shell's ShellUpdates.openOverlay() instead.
                            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "shellUpdate", "open"])
                        }
                    }

                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "open_in_new"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Open Details")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    visible: ShellUpdates.hasUpdate && ShellUpdates.selfUpdateSupported
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: !ShellUpdates.isUpdating
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: ShellUpdates.performUpdate()

                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdates.isUpdating ? "hourglass_top" : "upgrade"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdates.isUpdating
                                    ? (ShellUpdates.updateStepMessage.length > 0
                                        ? Translation.tr(ShellUpdates.updateStepMessage) + "…"
                                        : Translation.tr("Updating…"))
                                    : Translation.tr("Update Now")
                                font {
                                    pixelSize: Appearance.font.pixelSize.smaller
                                    weight: Font.DemiBold
                                }
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    visible: ShellUpdates.hasUpdate && !ShellUpdates.isDismissed
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSurfaceContainerLow
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: ShellUpdates.dismiss()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "notifications_off"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }

                    StyledToolTip {
                        text: Translation.tr("Dismiss update (hide bar indicator)")
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    visible: ShellUpdates.isDismissed
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSurfaceContainerLow
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: ShellUpdates.undismiss()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "notifications_active"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                    }

                    StyledToolTip {
                        text: Translation.tr("Show bar indicator again")
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "system"
        visible: true
        expanded: true
        icon: "cloud"
        title: Translation.tr("Weather & Search")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "toggle_on"
                    text: Translation.tr("Enable weather")
                    checked: Config.options?.bar?.weather?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("bar.weather.enable", checked)
                }

                SettingsSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Hide location")
                    checked: Config.options?.waffles?.widgetsPanel?.weatherHideLocation ?? false
                    onCheckedChanged: Config.setNestedValue("waffles.widgetsPanel.weatherHideLocation", checked)
                    enabled: Config.options?.bar?.weather?.enable ?? false
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                enabled: Config.options?.bar?.weather?.enable ?? false

                StyledText {
                    text: Translation.tr("City (leave empty to auto-detect)")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                MaterialTextField {
                    id: weatherCityInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("e.g. Buenos Aires, London, Tokyo")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    placeholderTextColor: Appearance.colors.colSubtext
                    text: Config.options?.bar?.weather?.city ?? ""
                    background: Rectangle {
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.small
                        border.width: weatherCityInput.activeFocus ? 2 : 1
                        border.color: weatherCityInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                    }
                    onTextEdited: Config.setNestedValue("bar.weather.city", text)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "my_location"
                    text: Translation.tr("Use GPS location")
                    checked: Config.options?.bar?.weather?.enableGPS ?? false
                    onCheckedChanged: Config.setNestedValue("bar.weather.enableGPS", checked)
                    enabled: Config.options?.bar?.weather?.enable ?? false
                }

                SettingsSwitch {
                    buttonIcon: "thermometer"
                    text: Translation.tr("Use Fahrenheit (°F)")
                    checked: Config.options?.bar?.weather?.useUSCS ?? false
                    onCheckedChanged: Config.setNestedValue("bar.weather.useUSCS", checked)
                    enabled: Config.options?.bar?.weather?.enable ?? false
                }
            }

            ConfigSpinBox {
                icon: "update"
                text: Translation.tr("Weather update interval (min)")
                value: Config.options?.bar?.weather?.fetchInterval ?? 10
                from: 5
                to: 60
                stepSize: 5
                onValueChanged: Config.setNestedValue("bar.weather.fetchInterval", value)
                enabled: Config.options?.bar?.weather?.enable ?? false
            }

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Search surface & Web engine")

                ConfigSelectionArray {
                    currentValue: Config.options?.search?.style ?? "default"
                    onSelected: newValue => {
                        Config.setNestedValue("search.style", newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Default"), icon: "search", value: "default" },
                        { displayName: Translation.tr("Island"), icon: "blur_on", value: "island" }
                    ]
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search base URL")
                    text: Config.options?.search?.engineBaseUrl ?? "https://www.google.com/search?q="
                    onEditingFinished: {
                        Config.setNestedValue("search.engineBaseUrl", text)
                    }
                }
            }
        }
    }
    }

}
