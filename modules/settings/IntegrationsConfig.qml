import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings

ContentPage {
    id: root
    objectName: "integrationSettings"
    settingsPageIndex: 38
    settingsPageName: Translation.tr("Integrations")
    property string activePlugin: "management"
    property string activeSection: "calendar"
    property var capabilitySelections: ({})
    readonly property var primaryTabs: Hadalird.installedPlugins.map(plugin => ({
        displayName: plugin.name, icon: plugin.icon, value: plugin.id
    })).concat([{displayName: Translation.tr("Management"), icon: "extension", value: "management"}])
    readonly property var selectedPlugin: Hadalird.installedPlugins.find(plugin => plugin.id === root.activePlugin) ?? null
    readonly property var capabilityTabs: (selectedPlugin?.capabilities ?? []).map(capability => ({
        displayName: capability.name, value: capability.id
    }))
    readonly property var selectedCapability: selectedPlugin?.capabilities.find(capability =>
        capability.id === root.capabilitySelections[root.activePlugin]) ?? selectedPlugin?.capabilities[0] ?? null
    readonly property var catalog: {
        const installed = Hadalird.installedPlugins
        return Hadalird.pluginCatalog.filter(plugin => !installed.some(item => item.id === plugin.id)).concat(installed)
    }
    onPrimaryTabsChanged: {
        if (!primaryTabs.some(tab => tab.value === activePlugin)) activePlugin = "management"
    }
    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        const wanted = /to-do|todo|quick note|zettelkasten/.test(label) ? "obsidian"
            : /fan|cooling|thermal/.test(label) ? "thinkfan" : label
        const plugin = Hadalird.installedPlugins.find(item => wanted.includes(item.id) || wanted.includes(item.name.toLowerCase()))
        if (plugin) {
            activePlugin = plugin.id
            const capability = /todo|to-do/.test(label) ? "todo"
                : /quick note|zettelkasten/.test(label) ? "quicknotes" : ""
            if (capability) selectCapability(capability)
            return true
        }
        activePlugin = "management"
        activeSection = label.includes("music") || label.includes("apps") ? "apps" : "calendar"
        return true
    }
    function selectCapability(value): void {
        const next = Object.assign({}, capabilitySelections)
        next[activePlugin] = value
        capabilitySelections = next
    }
    function pluginState(plugin): string {
        if (!Hadalird.available || Hadalird.loadFailed)
            return Hadalird.diagnostic === "not-installed" ? Translation.tr("Not installed") : Translation.tr("Unavailable")
        if (!Hadalird.installedPlugins.some(item => item.id === plugin.id)) return Translation.tr("Unavailable")
        if (Hadalird.updateAvailable) return Translation.tr("Update available")
        return Hadalird.pluginEnabled(plugin.id) ? Translation.tr("Enabled") : Translation.tr("Disabled")
    }

    SettingsTaskNavigator {
        objectName: "integrationPrimaryTabs"
        showIntro: false
        currentValue: root.activePlugin
        options: root.primaryTabs
        onSelected: value => root.activePlugin = value
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.activePlugin === "management"
        SettingsCardSection {
            id: packageSection
            title: Translation.tr("Management")
            icon: "extension"
            expanded: true
            property bool confirmRemoval: false
            property bool showDiagnostics: false
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Hadalird.managerBusy ? Translation.tr("Working…")
                    : Hadalird.available ? "Alis-Intergration " + Hadalird.version + " · " + Translation.tr("Installed")
                    : Hadalird.diagnostic === "not-installed" ? Translation.tr("No plugins installed. Install the optional package to get started.")
                    : Translation.tr("Integration package unavailable") + " · " + Hadalird.diagnostic
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                DialogButton {
                    buttonText: Hadalird.available ? Translation.tr("Reinstall") : Translation.tr("Install Alis-Intergration")
                    enabled: !Hadalird.managerBusy
                    onClicked: Hadalird.manage("install")
                }
                DialogButton {
                    visible: Hadalird.available
                    buttonText: Translation.tr("Check updates")
                    enabled: !Hadalird.managerBusy
                    onClicked: Hadalird.manage("check")
                }
                DialogButton {
                    visible: Hadalird.updateAvailable
                    buttonText: Translation.tr("Update")
                    enabled: !Hadalird.managerBusy
                    onClicked: Hadalird.manage("install")
                }
                DialogButton {
                    buttonText: Translation.tr("Refresh")
                    enabled: !Hadalird.managerBusy
                    onClicked: { Hadalird.refresh(); Hadalird.refreshSystemStatus() }
                }
                DialogButton {
                    buttonText: Translation.tr("Diagnostics")
                    onClicked: packageSection.showDiagnostics = !packageSection.showDiagnostics
                }
                DialogButton {
                    objectName: "integrationRestoreInternalTodos"
                    visible: Todo.backend === "obsidian" && !Hadalird.obsidianEnabled
                    enabled: !Todo.internalPersistenceBusy
                    buttonText: Translation.tr("Use Alis tasks")
                    onClicked: Todo.reactivateInternal()
                }
                DialogButton {
                    visible: Hadalird.canRollback
                    buttonText: Translation.tr("Restore Alis-Intergration")
                    enabled: !Hadalird.managerBusy
                    onClicked: Hadalird.manage("rollback")
                }
                DialogButton {
                    visible: Hadalird.available && !packageSection.confirmRemoval
                    buttonText: Translation.tr("Remove Alis-Intergration")
                    enabled: !Hadalird.managerBusy
                    onClicked: packageSection.confirmRemoval = true
                }
                DialogButton {
                    visible: packageSection.confirmRemoval
                    buttonText: Translation.tr("Confirm removal")
                    enabled: !Hadalird.managerBusy
                    onClicked: { packageSection.confirmRemoval = false; Hadalird.manage("remove") }
                }
                DialogButton {
                    visible: packageSection.confirmRemoval
                    buttonText: Translation.tr("Cancel")
                    onClicked: packageSection.confirmRemoval = false
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: Hadalird.managerError.length > 0 || Hadalird.managerMessage.length > 0
                color: Hadalird.managerError.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
                text: Hadalird.managerError || Hadalird.managerMessage
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                visible: packageSection.showDiagnostics
                text: Hadalird.status()
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: Hadalird.available && !Hadalird.pluginMetadataAvailable
                text: Translation.tr("Update the optional package to show plugin tabs.")
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: "Gateway: " + (Hadalird.systemProvisionerAvailable ? Translation.tr("Ready") : Translation.tr("Not installed"))
                    + " · Helpers: " + (Hadalird.systemHelpersInstalled ? Translation.tr("Ready")
                        : Hadalird.systemHelpersDiagnostic === "unchecked" ? Translation.tr("Not checked")
                        : Hadalird.systemHelpersDiagnostic.includes("not-installed") ? Translation.tr("Not installed")
                        : Translation.tr("Needs attention"))
                    + "\n" + Translation.tr("Manage system helpers with ./setup integrations.")
            }
        }
        Repeater {
            model: root.catalog
            delegate: SettingsCardSection {
                id: catalogCard
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                icon: modelData.icon
                expanded: true
                SettingsSwitch {
                    objectName: "integrationToggle_" + catalogCard.modelData.id
                    text: Translation.tr("Enable")
                    description: root.pluginState(catalogCard.modelData)
                    autoToggle: false
                    checked: Hadalird.options?.[catalogCard.modelData.id] === true
                    enabled: Hadalird.available && !Hadalird.managerBusy
                        && Hadalird.installedPlugins.some(plugin => plugin.id === catalogCard.modelData.id)
                    onToggledByUser: value => Hadalird.setPluginEnabled(catalogCard.modelData.id, value)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.selectedPlugin !== null
        SettingsTaskNavigator {
            objectName: "integrationCapabilityTabs"
            visible: root.capabilityTabs.length > 1
            showIntro: false
            options: root.capabilityTabs
            currentValue: root.selectedCapability?.id ?? ""
            onSelected: value => root.selectCapability(value)
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: !Hadalird.pluginEnabled(root.activePlugin)
            text: !Hadalird.available || Hadalird.loadFailed
                ? Translation.tr("Plugin unavailable. Refresh or update the optional package.")
                : Translation.tr("Enable this plugin in Management to configure it.")
        }
        Loader {
            id: pluginSettings
            objectName: "integrationPluginSettings"
            Layout.fillWidth: true
            Layout.preferredHeight: item?.implicitHeight ?? 0
            active: root.visible && root.selectedPlugin !== null && Hadalird.pluginEnabled(root.activePlugin)
            property string capabilitySource: root.selectedCapability
                ? Hadalird.settingsSource(Config.options?.panelFamily === "waffle"
                    ? root.selectedCapability.waffleSettings ?? root.selectedCapability.settings
                    : root.selectedCapability.settings) : ""
            property string capabilityView: root.selectedCapability?.view ?? ""
            function reload(): void {
                source = ""
                if (active && capabilitySource.length > 0)
                    setSource(capabilitySource, capabilityView.length ? {settingsView: capabilityView} : {})
            }
            onActiveChanged: reload()
            onCapabilitySourceChanged: reload()
            onCapabilityViewChanged: reload()
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: pluginSettings.status === Loader.Error
            text: Translation.tr("Plugin settings could not be loaded. Refresh or update the optional package.")
            color: Appearance.colors.colError
        }
    }
    SettingsTaskNavigator {
        visible: root.activePlugin === "management"
        showIntro: false
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [{displayName: "Calendar", icon: "calendar_month", value: "calendar"},
                  {displayName: "Applications", icon: "apps", value: "apps"}]
    }
    SettingsCardSection {
        settingsTaskSection: "calendar"
        visible: root.activePlugin === "management" && root.activeSection === "calendar"
        expanded: true
        icon: "calendar_month"
        title: Translation.tr("Calendar Sync")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Enable external calendar sync")
                checked: Config.options?.calendar?.externalSync?.enable ?? false
                onCheckedChanged: Config.setNestedValue("calendar.externalSync.enable", checked)
            }

            ConfigSpinBox {
                icon: "update"
                text: Translation.tr("Refresh interval (minutes)")
                value: Config.options?.calendar?.externalSync?.refreshMinutes ?? 15
                from: 5
                to: 120
                stepSize: 5
                onValueChanged: Config.setNestedValue("calendar.externalSync.refreshMinutes", value)
                enabled: Config.options?.calendar?.externalSync?.enable ?? false
            }

            SettingsSwitch {
                buttonIcon: "event"
                text: Translation.tr("Show upcoming events below calendar")
                checked: Config.options?.calendar?.showUpcoming ?? true
                onCheckedChanged: Config.setNestedValue("calendar.showUpcoming", checked)
            }

            ConfigSpinBox {
                icon: "event"
                text: Translation.tr("Maximum indicators per edge")
                description: Translation.tr("Calendar event dots (0 hides them; up to 3 per edge, 12 per day)")
                value: Math.max(0,Math.min(3,Config.options?.calendar?.maxEventDots ?? 3))
                from: 0
                to: 3
                stepSize: 1
                onValueChanged: Config.setNestedValue("calendar.maxEventDots", value)
            }

            ConfigSpinBox {
                icon: "date_range"
                text: Translation.tr("Upcoming days to show")
                value: Config.options?.calendar?.upcomingDays ?? 3
                from: 1
                to: 14
                stepSize: 1
                onValueChanged: Config.setNestedValue("calendar.upcomingDays", value)
            }
        }

        // Calendar source list
        SettingsGroup {
            visible: Config.options?.calendar?.externalSync?.enable ?? false

            // Section header for sources
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                Layout.bottomMargin: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Calendar Sources")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                RippleButton {
                    implicitWidth: addRow.implicitWidth + 16
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
                    onClicked: addSourceForm.expanded = true

                    contentItem: RowLayout {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: "add"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Add")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            // Source list
            Repeater {
                model: Config.options?.calendar?.externalSync?.sources ?? []

                delegate: Item {
                    id: sourceItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: sourceRow.implicitHeight + 12

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: sourceMA.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                        RowLayout {
                            id: sourceRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            // Color dot
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: sourceItem.modelData?.color ?? Appearance.colors.colPrimary
                            }

                            // Name and URL
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: sourceItem.modelData?.name ?? Translation.tr("Unnamed")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: sourceItem.modelData?.url ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                }
                            }

                            // Status indicator
                            MaterialSymbol {
                                visible: {
                                    const st = CalendarSync.sourceStatuses?.[sourceItem.modelData?.id]
                                    return st?.error && st.error !== ""
                                }
                                text: "error"
                                iconSize: 16
                                color: Appearance.colors.colError

                                StyledToolTip {
                                    text: CalendarSync.sourceStatuses?.[sourceItem.modelData?.id]?.error ?? ""
                                }
                            }

                            // Toggle enabled
                            Switch {
                                checked: sourceItem.modelData?.enabled ?? true
                                onCheckedChanged: {
                                    if (checked !== (sourceItem.modelData?.enabled ?? true)) {
                                        CalendarSync.toggleSource(sourceItem.modelData.id, checked)
                                    }
                                }
                            }

                            // Remove button
                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: 14
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: CalendarSync.removeSource(sourceItem.modelData.id)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    text: Translation.tr("Remove")
                                }
                            }
                        }

                        MouseArea {
                            id: sourceMA
                            anchors.fill: parent
                            z: -1
                            hoverEnabled: true
                        }
                    }
                }
            }

            // Empty state
            StyledText {
                visible: (Config.options?.calendar?.externalSync?.sources ?? []).length === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                text: Translation.tr("No calendar sources added yet")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                font.italic: true
            }

            // Help text for getting ICS URLs
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                text: Translation.tr("Paste a compatible ICS/iCal feed URL; no account sign-in within Alis.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                opacity: 0.7
            }

            // Inline add-source form (expands in place)
            Rectangle {
                id: addSourceForm
                Layout.fillWidth: true
                Layout.topMargin: 4

                property bool expanded: false

                implicitHeight: expanded ? addFormCol.implicitHeight + 24 : 0
                visible: expanded
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                Behavior on implicitHeight {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                ColumnLayout {
                    id: addFormCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    StyledText {
                        text: Translation.tr("Add Calendar Source")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("Name")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: sourceNameInput
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Work Calendar")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: sourceNameInput.activeFocus ? 2 : 1
                                border.color: sourceNameInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("ICS URL")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: sourceUrlInput
                            Layout.fillWidth: true
                            placeholderText: "https://calendar.google.com/calendar/ical/..."
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: sourceUrlInput.activeFocus ? 2 : 1
                                border.color: sourceUrlInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    // Color picker
                    ColumnLayout {
                        spacing: 4

                        StyledText {
                            text: Translation.tr("Color")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            id: colorPickerRow
                            spacing: 6
                            property string selectedColor: CalendarSync.presetColors[0]

                            Repeater {
                                model: CalendarSync.presetColors

                                delegate: Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: modelData
                                    border.width: colorPickerRow.selectedColor === modelData ? 2 : 0
                                    border.color: Appearance.colors.colOnLayer1
                                    opacity: colorPickMA.containsMouse ? 0.8 : 1

                                    MouseArea {
                                        id: colorPickMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: colorPickerRow.selectedColor = modelData
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitWidth: cancelLabel.implicitWidth + 24
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: {
                                addSourceForm.expanded = false
                                sourceNameInput.text = ""
                                sourceUrlInput.text = ""
                            }

                            contentItem: StyledText {
                                id: cancelLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Cancel")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        RippleButton {
                            implicitWidth: addLabel.implicitWidth + 24
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            enabled: sourceNameInput.text.trim() !== "" && sourceUrlInput.text.trim() !== ""
                            opacity: enabled ? 1 : 0.5
                            onClicked: {
                                CalendarSync.addSource(
                                    sourceNameInput.text.trim(),
                                    sourceUrlInput.text.trim(),
                                    colorPickerRow.selectedColor
                                )
                                sourceNameInput.text = ""
                                sourceUrlInput.text = ""
                                addSourceForm.expanded = false
                            }

                            contentItem: StyledText {
                                id: addLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }
    SettingsCardSection {
        settingsTaskSection: "apps"
        visible: root.activePlugin === "management" && root.activeSection === "apps"
        expanded: true
        icon: "music_cast"
        title: Translation.tr("Music Recognition")

        SettingsGroup {
            ConfigSpinBox {
                icon: "timer_off"
                text: Translation.tr("Total duration timeout (s)")
                value: Config.options?.musicRecognition?.timeout ?? 16
                from: 10
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.setNestedValue("musicRecognition.timeout", value)
                }
                StyledToolTip {
                    text: Translation.tr("Maximum time to wait for music recognition result")
                }
            }
            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Polling interval (s)")
                value: Config.options?.musicRecognition?.interval ?? 4
                from: 2
                to: 10
                stepSize: 1
                onValueChanged: {
                    Config.setNestedValue("musicRecognition.interval", value)
                }
                StyledToolTip {
                    text: Translation.tr("How often to check for recognition result")
                }
            }
        }
    }

}
