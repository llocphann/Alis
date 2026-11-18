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
    bentoEqualizeToTarget: !root.embedded
    property string activePlugin: "management"
    property string modalPluginId: ""
    readonly property bool modalOpen: root.modalPluginId.length > 0
    property string activeSection: "calendar"
    property var capabilitySelections: ({})
    readonly property bool gatewayReadyInUi: AlisIntergration.systemProvisionerAvailable
        || AlisIntergration.pluginDependencies("thinkfan").provisionerReady === true
        || AlisIntergration.pluginDependencies("tlp").provisionerReady === true
    readonly property bool helpersReadyInUi: AlisIntergration.systemHelpersInstalled
        || AlisIntergration.hardwareHelpersSatisfied
    readonly property var helperStatusItems: [
        {
            icon: "admin_panel_settings",
            label: Translation.tr("System Gateway"),
            ready: root.gatewayReadyInUi,
            optional: false
        },
        {
            icon: "bolt",
            label: Translation.tr("TLP Power Daemon"),
            ready: (AlisIntergration.runtimeTools?.tlp ?? AlisIntergration.pluginDependencies("tlp").binariesReady) === true,
            optional: false
        },
        {
            icon: "battery_charging_full",
            label: Translation.tr("TLP Charge Helper"),
            ready: AlisIntergration.pluginDependencies("tlp").helpersReady === true,
            optional: false
        },
        {
            icon: "airwave",
            label: Translation.tr("ThinkFan Daemon"),
            ready: (AlisIntergration.runtimeTools?.thinkfan ?? AlisIntergration.pluginDependencies("thinkfan").binariesReady) === true,
            optional: false
        },
        {
            icon: "mode_fan",
            label: Translation.tr("ThinkFan Helper"),
            ready: AlisIntergration.pluginDependencies("thinkfan").helpersReady === true,
            optional: false
        },
        {
            icon: "terminal",
            label: Translation.tr("Python 3 Runtime"),
            ready: (AlisIntergration.runtimeTools?.python3 ?? AlisIntergration.pluginDependencies("nexus").binariesReady) === true,
            optional: false
        },
        {
            icon: "cloud_download",
            label: Translation.tr("Curl Feed Fetcher"),
            ready: (AlisIntergration.runtimeTools?.curl ?? true) === true,
            optional: false
        },
        {
            icon: "calendar_today",
            label: Translation.tr("Khal Calendar CLI"),
            ready: (AlisIntergration.runtimeTools?.khal ?? false) === true,
            optional: true
        }
    ]
    readonly property var primaryTabs: [{
        displayName: Translation.tr("Management & Calendar"),
        icon: "extension",
        value: "management"
    }].concat(AlisIntergration.installedPlugins.map(plugin => ({
        displayName: plugin.id === "nexus" ? "Nexus" : plugin.name,
        icon: plugin.id === "nexus" ? "hub" : plugin.icon,
        value: plugin.id
    })))
    readonly property var catalog: {
        const order = ["nexus", "spaced_repetition", "exercises_tracker", "tlp", "thinkfan"]
        const merged = []
        const sources = AlisIntergration.pluginCatalog.concat(AlisIntergration.installedPlugins)
        for (const item of sources) {
            if (item && item.id && !merged.some(existing => existing.id === item.id))
                merged.push(item)
        }
        merged.sort((a, b) => {
            const ia = order.indexOf(a.id)
            const ib = order.indexOf(b.id)
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
        })
        return merged
    }
    readonly property var selectedPlugin: AlisIntergration.installedPlugins.find(plugin => plugin.id === root.activePlugin) ?? null
    readonly property var modalCatalogPlugin: root.catalog.find(plugin => plugin.id === root.modalPluginId)
        ?? root.selectedPlugin
        ?? null
    readonly property bool isModalPluginInstalled: root.modalPluginId.length > 0
        && AlisIntergration.isPluginInstalled(root.modalPluginId)
    readonly property var modalDependencies: root.modalPluginId.length > 0
        ? AlisIntergration.pluginDependencies(root.modalPluginId)
        : ({ userSpace: true, requiresSystemHelpers: false, satisfied: true, binariesReady: true, helpersReady: true, binaries: [], helpers: [], missing: [], setupCommand: "", helpersCommand: "", note: "" })
    readonly property var capabilityTabs: (selectedPlugin?.capabilities ?? []).map(capability => ({
        displayName: (selectedPlugin?.id === "nexus" && capability.id === "theming") ? "Nexus & Vault" : capability.name,
        value: capability.id
    }))
    readonly property var selectedCapability: selectedPlugin?.capabilities.find(capability =>
        capability.id === root.capabilitySelections[root.activePlugin]) ?? selectedPlugin?.capabilities[0] ?? null
    onVisibleChanged: {
        if (root.visible && !AlisIntergration.managerBusy && AlisIntergration.managerError.length > 0)
            AlisIntergration.clearFeedback()
    }
    onActivePluginChanged: {
        if (root.activePlugin === "management") {
            if (root.modalPluginId !== "")
                root.modalPluginId = ""
        } else if (root.modalPluginId !== root.activePlugin) {
            root.modalPluginId = root.activePlugin
        }
    }
    onPrimaryTabsChanged: {
        if (root.modalPluginId.length > 0) {
            if (!root.catalog.some(plugin => plugin.id === root.modalPluginId))
                root.closePluginModal()
            return
        }
        if (!primaryTabs.some(tab => tab.value === activePlugin))
            activePlugin = "management"
    }
    function openPluginModal(pluginId, capabilityId = ""): void {
        if (typeof pluginId !== "string" || pluginId.length === 0)
            return
        if (capabilityId && capabilityId.length > 0)
            root.selectCapability(capabilityId, pluginId)
        root.modalPluginId = pluginId
        root.activePlugin = pluginId
        Qt.callLater(() => {
            if (root.modalOpen)
                pluginModalCard.forceActiveFocus()
        })
    }
    function closePluginModal(): void {
        root.modalPluginId = ""
        root.activePlugin = "management"
    }
    function handleEscape(): bool {
        if (root.modalOpen) {
            root.closePluginModal()
            return true
        }
        return false
    }
    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        if (/calendar/.test(label)) {
            root.closePluginModal()
            root.activeSection = "calendar"
            return true
        }
        const wanted = /nexus|vault|outliner|graph|to-do|todo|quick note|zettelkasten/.test(label) ? "nexus"
            : /fan|cooling|thermal/.test(label) ? "thinkfan"
            : /spaced repetition|vocabulary|flashcard|cefr|sm-2/.test(label) ? "spaced_repetition"
            : /exercises?[\s_-]*tracker|workout|body tracker|fitness/.test(label) ? "exercises_tracker"
            : /\btlp\b|power|battery/.test(label) ? "tlp" : label
        const plugin = root.catalog.find(item => wanted === item.id || wanted.includes(item.id) || wanted.includes(item.name.toLowerCase()))
            ?? AlisIntergration.installedPlugins.find(item => wanted.includes(item.id) || wanted.includes(item.name.toLowerCase()))
        if (plugin) {
            const capability = /todo|to-do/.test(label) ? "todo"
                : /quick note|zettelkasten/.test(label) ? "quicknotes"
                : plugin.id === "nexus" ? "theming" : ""
            root.openPluginModal(plugin.id, capability)
            return true
        }
        root.closePluginModal()
        root.activeSection = "calendar"
        return true
    }
    function selectCapability(value, pluginId = ""): void {
        const target = (typeof pluginId === "string" && pluginId.length > 0) ? pluginId : root.activePlugin
        const next = Object.assign({}, capabilitySelections)
        next[target] = value
        capabilitySelections = next
    }
    function pluginDisplayName(plugin): string {
        if (!plugin) return ""
        if (plugin.id === "nexus") return Translation.tr("Alis Nexus")
        return String(plugin.name ?? plugin.id ?? "")
    }
    function pluginIconName(plugin): string {
        if (!plugin) return "extension"
        return plugin.id === "nexus" ? "hub" : String(plugin.icon ?? "extension")
    }
    function pluginState(plugin): string {
        if (!plugin) return Translation.tr("Unavailable")
        if (AlisIntergration.managerBusy && AlisIntergration.managerPluginId === plugin.id)
            return Translation.tr("Working…")
        const installed = AlisIntergration.isPluginInstalled(plugin.id)
        const deps = AlisIntergration.pluginDependencies(plugin.id)
        if (!installed) {
            if (deps.userSpace)
                return Translation.tr("Not installed · User-space")
            if (!deps.satisfied && Array.isArray(deps.missing) && deps.missing.length > 0)
                return Translation.tr("Not installed · Missing:") + " " + deps.missing.map(m => String(m).split("/").pop()).join(", ")
            return Translation.tr("Not installed · System helpers")
        }
        if (!deps.satisfied && Array.isArray(deps.missing) && deps.missing.length > 0)
            return Translation.tr("Installed · Missing:") + " " + deps.missing.map(m => String(m).split("/").pop()).join(", ")
        if (AlisIntergration.updateAvailable)
            return Translation.tr("Installed · Update available")
        return AlisIntergration.pluginEnabled(plugin.id) ? Translation.tr("Installed · Enabled") : Translation.tr("Installed · Disabled")
    }

    SettingsCardSection {
        id: packageSection
        objectName: "integrationOptionalPluginsCard"
        _consumesBentoExtraHeight: false
        visible: true
        title: Translation.tr("Optional Plugins")
        icon: "extension"
        expanded: true
        property bool confirmRemoval: false

        SettingsGroup {
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WordWrap
                text: AlisIntergration.managerBusy ? Translation.tr("Working…")
                    : AlisIntergration.available
                        ? "Alis-Intergration " + AlisIntergration.version + " · " + AlisIntergration.installedPlugins.length + " / " + Math.max(4, root.catalog.length) + " " + Translation.tr("installed")
                    : AlisIntergration.diagnostic === "not-installed"
                        ? Translation.tr("No plugins installed. Install individual plugins below.")
                        : Translation.tr("Integration package unavailable") + " · " + AlisIntergration.diagnostic
            }

            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8
                DialogButton {
                    buttonText: AlisIntergration.available ? Translation.tr("Reinstall all") : Translation.tr("Install all")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: AlisIntergration.manage("install-all")
                }
                DialogButton {
                    visible: AlisIntergration.available
                    buttonText: Translation.tr("Check updates")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: AlisIntergration.manage("check")
                }
                DialogButton {
                    visible: AlisIntergration.updateAvailable
                    buttonText: Translation.tr("Update")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: AlisIntergration.manage("install")
                }
                DialogButton {
                    buttonText: Translation.tr("Refresh")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: { AlisIntergration.clearFeedback(); AlisIntergration.refresh(); AlisIntergration.refreshSystemStatus() }
                }
                DialogButton {
                    objectName: "integrationHeaderDiagnosticsToggle"
                    buttonText: Translation.tr("Diagnostics")
                    onClicked: helpersSection.showDiagnostics = !helpersSection.showDiagnostics
                }
                DialogButton {
                    objectName: "integrationRestoreInternalTodos"
                    visible: Todo.backend === "nexus" && !AlisIntergration.nexusEnabled
                    enabled: !Todo.internalPersistenceBusy
                    buttonText: Translation.tr("Use Alis tasks")
                    onClicked: Todo.reactivateInternal()
                }
                DialogButton {
                    visible: AlisIntergration.available && !packageSection.confirmRemoval
                    buttonText: Translation.tr("Remove all")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: packageSection.confirmRemoval = true
                }
                DialogButton {
                    visible: packageSection.confirmRemoval
                    buttonText: Translation.tr("Confirm removal")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: { packageSection.confirmRemoval = false; AlisIntergration.manage("remove") }
                }
                DialogButton {
                    visible: packageSection.confirmRemoval
                    buttonText: Translation.tr("Cancel")
                    onClicked: packageSection.confirmRemoval = false
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8
                visible: AlisIntergration.managerError.length > 0 || AlisIntergration.managerMessage.length > 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    color: AlisIntergration.managerError.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: AlisIntergration.managerError || AlisIntergration.managerMessage
                }

                RippleButton {
                    objectName: "integrationDismissManagerFeedback"
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: 12
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: AlisIntergration.clearFeedback()

                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WordWrap
                visible: AlisIntergration.available && !AlisIntergration.pluginMetadataAvailable
                text: Translation.tr("Update the optional package to show plugin settings.")
            }

            SettingsDivider {}

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: pluginsListColumn.implicitHeight
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: SettingsMaterialPreset.groupBorderColor
                clip: true

                ColumnLayout {
                    id: pluginsListColumn
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.catalog
                        delegate: Rectangle {
                            id: pluginCard
                            required property var modelData
                            required property int index
                            readonly property bool isInstalled: AlisIntergration.isPluginInstalled(pluginCard.modelData.id)
                            readonly property bool isEnabled: AlisIntergration.pluginEnabled(pluginCard.modelData.id)
                            readonly property var deps: AlisIntergration.pluginDependencies(pluginCard.modelData.id)
                            readonly property bool isWorking: AlisIntergration.managerBusy && AlisIntergration.managerPluginId === pluginCard.modelData.id
                            objectName: "integrationPluginCard_" + pluginCard.modelData.id
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            clip: true
                            implicitHeight: Math.max(60, pluginCardRow.implicitHeight + 18)
                            color: pluginCardMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                visible: pluginCard.index > 0
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                height: 1
                                color: Appearance.colors.colOutlineVariant
                                opacity: 0.45
                            }

                            MouseArea {
                                id: pluginCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openPluginModal(pluginCard.modelData.id)
                            }

                            RowLayout {
                                id: pluginCardRow
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: Appearance.rounding.small
                                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                                    border.width: 1
                                    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65)
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: root.pluginIconName(pluginCard.modelData)
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: root.pluginDisplayName(pluginCard.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: root.pluginState(pluginCard.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: !pluginCard.deps.satisfied && !pluginCard.deps.userSpace
                                            ? Appearance.colors.colError
                                            : pluginCard.isEnabled
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                RowLayout {
                                    z: 2
                                    spacing: 8
                                    Layout.alignment: Qt.AlignVCenter

                                    RippleButton {
                                        visible: !pluginCard.isInstalled
                                        objectName: "integrationInstall_" + pluginCard.modelData.id
                                        enabled: !AlisIntergration.managerBusy
                                        implicitWidth: cardInstallRow.implicitWidth + 20
                                        implicitHeight: 30
                                        buttonRadius: 15
                                        colBackground: Appearance.colors.colPrimary
                                        colBackgroundHover: Appearance.colors.colPrimaryHover
                                        onClicked: {
                                            AlisIntergration.installPlugin(pluginCard.modelData.id)
                                            if (!pluginCard.deps.userSpace && !pluginCard.deps.satisfied)
                                                root.openPluginModal(pluginCard.modelData.id)
                                        }

                                        contentItem: Item {
                                            Row {
                                                id: cardInstallRow
                                                anchors.centerIn: parent
                                                spacing: 5

                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: pluginCard.isWorking ? "sync" : "download"
                                                    iconSize: 14
                                                    color: Appearance.colors.colOnPrimary
                                                }

                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: pluginCard.isWorking ? Translation.tr("Working…") : Translation.tr("Install")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.DemiBold
                                                    color: Appearance.colors.colOnPrimary
                                                }
                                            }
                                        }
                                    }

                                    StyledSwitch {
                                        visible: pluginCard.isInstalled
                                        objectName: "integrationToggle_" + pluginCard.modelData.id
                                        enabled: !AlisIntergration.managerBusy && pluginCard.isInstalled
                                        checked: AlisIntergration.options?.[pluginCard.modelData.id] === true
                                        onClicked: {
                                            const nextValue = !(AlisIntergration.options?.[pluginCard.modelData.id] === true)
                                            AlisIntergration.setPluginEnabled(pluginCard.modelData.id, nextValue)
                                            checked = Qt.binding(() => AlisIntergration.options?.[pluginCard.modelData.id] === true)
                                        }
                                    }

                                    RippleButton {
                                        visible: pluginCard.isInstalled
                                        objectName: "integrationOpenModal_" + pluginCard.modelData.id
                                        implicitWidth: cardSettingsRow.implicitWidth + 16
                                        implicitHeight: 28
                                        buttonRadius: 14
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        onClicked: root.openPluginModal(pluginCard.modelData.id)

                                        contentItem: Item {
                                            Row {
                                                id: cardSettingsRow
                                                anchors.centerIn: parent
                                                spacing: 4

                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: pluginCard.width >= 260
                                                    text: Translation.tr("Settings")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnSecondaryContainer
                                                }

                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "arrow_forward"
                                                    iconSize: 13
                                                    color: Appearance.colors.colOnSecondaryContainer
                                                }
                                            }
                                        }
                                    }

                                    MaterialSymbol {
                                        visible: !pluginCard.isInstalled
                                        text: "chevron_right"
                                        iconSize: 18
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: helpersSection
        objectName: "integrationSystemHelpersCard"
        _consumesBentoExtraHeight: false
        visible: true
        title: Translation.tr("System Helpers & Diagnostics")
        icon: "verified_user"
        expanded: true
        property bool showDiagnostics: false

        SettingsGroup {
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: "Gateway: " + (root.gatewayReadyInUi ? Translation.tr("Ready") : Translation.tr("Not installed"))
                    + " · Helpers: " + (root.helpersReadyInUi ? Translation.tr("Ready")
                        : AlisIntergration.systemHelpersDiagnostic === "unchecked" ? Translation.tr("Not checked")
                        : AlisIntergration.systemHelpersDiagnostic.includes("not-installed") ? Translation.tr("Not installed")
                        : Translation.tr("Needs attention"))
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                Repeater {
                    model: root.helperStatusItems
                    delegate: Rectangle {
                        id: helperItemCard
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 36
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: helperItemCard.modelData.icon
                                iconSize: 16
                                color: helperItemCard.modelData.ready
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: helperItemCard.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                implicitWidth: helperStateRow.implicitWidth + 14
                                implicitHeight: 22
                                radius: 11
                                color: helperItemCard.modelData.ready
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colLayer2

                                Row {
                                    id: helperStateRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: helperItemCard.modelData.ready ? "check" : (helperItemCard.modelData.optional ? "info" : "schedule")
                                        iconSize: 12
                                        color: helperItemCard.modelData.ready
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: helperItemCard.modelData.ready
                                            ? Translation.tr("Ready")
                                            : (helperItemCard.modelData.optional ? Translation.tr("Optional") : Translation.tr("Missing"))
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: helperItemCard.modelData.ready
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsGroup {
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("Manage system helpers with ./setup integrations.")
            }

            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8

                DialogButton {
                    id: copySetupBtn
                    property bool copied: false
                    buttonText: copySetupBtn.copied ? Translation.tr("Copied") : Translation.tr("Copy ./setup integrations")
                    onClicked: {
                        Quickshell.clipboardText = "./setup integrations"
                        copySetupBtn.copied = true
                        copySetupReset.restart()
                    }
                    Timer {
                        id: copySetupReset
                        interval: 1600
                        repeat: false
                        onTriggered: copySetupBtn.copied = false
                    }
                }

                DialogButton {
                    buttonText: Translation.tr("Refresh")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: { AlisIntergration.clearFeedback(); AlisIntergration.refresh(); AlisIntergration.refreshSystemStatus() }
                }

                DialogButton {
                    buttonText: Translation.tr("Diagnostics")
                    onClicked: helpersSection.showDiagnostics = !helpersSection.showDiagnostics
                }

                DialogButton {
                    visible: AlisIntergration.canRollback
                    buttonText: Translation.tr("Restore package")
                    enabled: !AlisIntergration.managerBusy
                    onClicked: AlisIntergration.manage("rollback")
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WrapAnywhere
                visible: helpersSection.showDiagnostics
                text: AlisIntergration.status()
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    Item {
        id: pluginModalLayer
        objectName: "integrationPluginModal"
        parent: root
        anchors.fill: parent
        z: 200
        visible: root.modalOpen || opacity > 0.001
        opacity: root.modalOpen ? 1 : 0
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.m3scrim ?? Qt.rgba(0, 0, 0, 0.55)
            opacity: 0.72

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                onClicked: root.closePluginModal()
                onWheel: wheel => { wheel.accepted = true }
            }
        }

        Rectangle {
            id: pluginModalCard
            objectName: "integrationPluginModalCard"
            anchors.centerIn: parent
            width: Math.max(260, Math.min(820, pluginModalLayer.width - (pluginModalLayer.width < 420 ? 16 : 40)))
            height: Math.max(300, Math.min(720, pluginModalLayer.height - (pluginModalLayer.height < 420 ? 16 : 40)))
            scale: root.modalOpen ? 1.0 : 0.96
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            focus: root.modalOpen

            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Keys.onShortcutOverride: event => {
                if (event.key === Qt.Key_Escape && root.modalOpen)
                    event.accepted = true
            }
            Keys.onEscapePressed: event => {
                if (root.modalOpen) {
                    root.closePluginModal()
                    event.accepted = true
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
                onWheel: wheel => { wheel.accepted = false }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 8
                        color: Appearance.colors.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.pluginIconName(root.modalCatalogPlugin)
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.pluginDisplayName(root.modalCatalogPlugin)
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.pluginState(root.modalCatalogPlugin)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    RippleButton {
                        objectName: "integrationModalInstallButton"
                        enabled: !AlisIntergration.managerBusy && root.modalPluginId.length > 0
                        implicitWidth: modalInstallRow.implicitWidth + 20
                        implicitHeight: 32
                        buttonRadius: 16
                        colBackground: root.isModalPluginInstalled
                            ? Appearance.colors.colLayer2
                            : Appearance.colors.colPrimary
                        colBackgroundHover: root.isModalPluginInstalled
                            ? Appearance.colors.colLayer2Hover
                            : ColorUtils.mix(Appearance.colors.colPrimary, "#ffffff", 0.14)
                        onClicked: {
                            if (root.isModalPluginInstalled)
                                AlisIntergration.removePlugin(root.modalPluginId)
                            else
                                AlisIntergration.installPlugin(root.modalPluginId)
                        }

                        contentItem: Item {
                            Row {
                                id: modalInstallRow
                                anchors.centerIn: parent
                                spacing: 5

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.isModalPluginInstalled ? "delete_outline" : "download"
                                    iconSize: 15
                                    color: root.isModalPluginInstalled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnPrimary
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (AlisIntergration.managerBusy && AlisIntergration.managerPluginId === root.modalPluginId)
                                        ? Translation.tr("Working…")
                                        : (root.isModalPluginInstalled ? Translation.tr("Uninstall") : Translation.tr("Install"))
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: root.isModalPluginInstalled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    StyledSwitch {
                        objectName: "integrationModalEnableSwitch"
                        visible: root.isModalPluginInstalled
                        enabled: !AlisIntergration.managerBusy && root.isModalPluginInstalled
                        checked: AlisIntergration.options?.[root.modalPluginId] === true
                        onClicked: {
                            const nextValue = !(AlisIntergration.options?.[root.modalPluginId] === true)
                            AlisIntergration.setPluginEnabled(root.modalPluginId, nextValue)
                            checked = Qt.binding(() => AlisIntergration.options?.[root.modalPluginId] === true)
                        }
                    }

                    RippleButton {
                        objectName: "integrationModalCloseButton"
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 16
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.closePluginModal()

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                SettingsDivider {}

                Flickable {
                    id: modalScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: modalBodyCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: modalBodyCol
                        width: modalScroll.width
                        spacing: SettingsMaterialPreset.pageSpacing

                        Rectangle {
                            id: dependencyCard
                            objectName: "integrationModalDependencies"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: depCol.implicitHeight + 20
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: root.modalDependencies.satisfied
                                ? Appearance.colors.colLayer0Border
                                : Appearance.colors.colError

                            ColumnLayout {
                                id: depCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 8

                                    MaterialSymbol {
                                        text: root.modalDependencies.satisfied ? "check_circle" : "warning"
                                        iconSize: 16
                                        color: root.modalDependencies.satisfied ? Appearance.colors.colPrimary : Appearance.colors.colError
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: root.modalDependencies.userSpace
                                            ? Translation.tr("User-space plugin · No root privileges required")
                                            : Translation.tr("System dependencies & helpers")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    wrapMode: Text.WordWrap
                                    visible: (root.modalDependencies.note ?? "").length > 0
                                    text: String(root.modalDependencies.note ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: (root.modalDependencies.binaries?.length ?? 0) > 0 || (root.modalDependencies.helpers?.length ?? 0) > 0

                                    Repeater {
                                        model: root.modalDependencies.binaries ?? []
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitWidth: binRow.implicitWidth + 14
                                            implicitHeight: 24
                                            radius: 12
                                            color: modelData.installed ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                                            Row {
                                                id: binRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.installed ? "check" : "close"
                                                    iconSize: 13
                                                    color: modelData.installed ? Appearance.colors.colPrimary : Appearance.colors.colError
                                                }
                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.name + (modelData.installed ? "" : " (missing)")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1
                                                }
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: root.modalDependencies.helpers ?? []
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitWidth: helperRow.implicitWidth + 14
                                            implicitHeight: 24
                                            radius: 12
                                            color: modelData.installed ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                                            Row {
                                                id: helperRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.installed ? "verified_user" : "admin_panel_settings"
                                                    iconSize: 13
                                                    color: modelData.installed ? Appearance.colors.colPrimary : Appearance.colors.colError
                                                }
                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: String(modelData.path).split("/").pop() + (modelData.installed ? "" : " (missing)")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1
                                                }
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    wrapMode: Text.WordWrap
                                    visible: !root.modalDependencies.userSpace && !root.modalDependencies.satisfied
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colError
                                    text: (!root.modalDependencies.binariesReady
                                            ? Translation.tr("Install packages with: ") + (root.modalDependencies.setupCommand || "./setup install-deps") + " (alis-deps)\n"
                                            : "")
                                        + (!root.modalDependencies.helpersReady
                                            ? Translation.tr("Install system helpers with: ") + (root.modalDependencies.helpersCommand || "./setup integrations")
                                            : "")
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: SettingsMaterialPreset.pageSpacing
                            visible: root.selectedPlugin !== null || !root.isModalPluginInstalled

                            Rectangle {
                                id: capabilityTabsRail
                                objectName: "integrationCapabilityTabs"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: root.selectedPlugin !== null && root.capabilityTabs.length > 1
                                readonly property real railPadding: Config.options?.panelFamily === "abyss" ? SettingsMaterialPreset.taskTabPadding : 0
                                implicitHeight: capabilityTabsArray.implicitHeight + railPadding * 2
                                color: Config.options?.panelFamily === "abyss" ? SettingsMaterialPreset.taskRailColor : "transparent"
                                radius: SettingsMaterialPreset.taskRailRadius

                                ConfigSelectionArray {
                                    id: capabilityTabsArray
                                    objectName: "settingsTaskOptions"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: capabilityTabsRail.railPadding
                                    y: capabilityTabsRail.railPadding
                                    enableSettingsSearch: false
                                    options: root.capabilityTabs
                                    currentValue: root.selectedCapability?.id ?? ""
                                    taskNavigation: true
                                    useAbyssPillShape: false
                                    onSelected: value => root.selectCapability(value)
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                wrapMode: Text.WordWrap
                                visible: !root.isModalPluginInstalled || !AlisIntergration.pluginEnabled(root.activePlugin)
                                color: Appearance.colors.colSubtext
                                text: !root.isModalPluginInstalled
                                    ? Translation.tr("Install this plugin above to unlock its settings.")
                                    : (!AlisIntergration.available || AlisIntergration.loadFailed)
                                        ? Translation.tr("Plugin unavailable. Refresh or update the optional package.")
                                        : Translation.tr("Enable this plugin above to configure it.")
                            }

                            Loader {
                                id: pluginSettings
                                objectName: "integrationPluginSettings"
                                Layout.fillWidth: true
                                Layout.preferredHeight: item?.implicitHeight ?? 0
                                active: root.visible && root.selectedPlugin !== null && AlisIntergration.pluginEnabled(root.activePlugin)
                                property string _loadedKey: ""
                                property string capabilitySource: root.selectedCapability
                                    ? AlisIntergration.settingsSource(Config.options?.panelFamily === "waffle"
                                        ? root.selectedCapability.waffleSettings ?? root.selectedCapability.settings
                                        : root.selectedCapability.settings) : ""
                                property string capabilityView: root.selectedCapability?.view ?? ""
                                function reload(): void {
                                    const isActive = root.visible && root.selectedPlugin !== null && AlisIntergration.pluginEnabled(root.activePlugin)
                                    const cap = root.selectedCapability
                                    const src = cap
                                        ? AlisIntergration.settingsSource(Config.options?.panelFamily === "waffle"
                                            ? cap.waffleSettings ?? cap.settings
                                            : cap.settings)
                                        : ""
                                    const view = String(cap?.view ?? "")
                                    const nextKey = (isActive && src.length > 0) ? (src + "|" + view) : ""
                                    if (nextKey === _loadedKey)
                                        return
                                    _loadedKey = nextKey
                                    source = ""
                                    if (nextKey.length > 0)
                                        setSource(src, view.length ? {settingsView: view} : {})
                                }
                                onActiveChanged: reload()
                                onCapabilitySourceChanged: reload()
                                onCapabilityViewChanged: reload()
                            }

                            Loader {
                                id: nexusCombinedTodoSettings
                                objectName: "integrationNexusTodoSettings"
                                Layout.fillWidth: true
                                Layout.preferredHeight: item?.implicitHeight ?? 0
                                visible: active
                                active: root.visible && root.activePlugin === "nexus"
                                    && AlisIntergration.pluginEnabled("nexus")
                                    && (root.selectedCapability?.id ?? "theming") === "theming"
                                source: active ? AlisIntergration.settingsSource("nexusTodo") : ""
                                onLoaded: {
                                    if (item && item.hasOwnProperty("settingsView"))
                                        item.settingsView = "all"
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                wrapMode: Text.WordWrap
                                visible: pluginSettings.status === Loader.Error
                                text: Translation.tr("Plugin settings could not be loaded. Refresh or update the optional package.")
                                color: Appearance.colors.colError
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: calendarSection
        objectName: "integrationCalendarSyncCard"
        settingsTaskSection: "calendar"
        _consumesBentoExtraHeight: false
        visible: true
        expanded: true
        icon: "calendar_month"
        title: Translation.tr("Calendar Sync")

        SettingsGroup {
            spacing: 8

            ConfigRow {
                uniform: true
                SettingsSwitch {
                    buttonIcon: "sync"
                    text: Translation.tr("Enable external calendar sync")
                    checked: Config.options?.calendar?.externalSync?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("calendar.externalSync.enable", checked)
                }

                SettingsSwitch {
                    buttonIcon: "event"
                    text: Translation.tr("Show upcoming events")
                    checked: Config.options?.calendar?.showUpcoming ?? true
                    onCheckedChanged: Config.setNestedValue("calendar.showUpcoming", checked)
                }
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "date_range"
                    text: Translation.tr("Upcoming days to show")
                    value: Config.options?.calendar?.upcomingDays ?? 3
                    from: 1
                    to: 14
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("calendar.upcomingDays", value)
                    enabled: Config.options?.calendar?.showUpcoming ?? true
                }

                ConfigSpinBox {
                    icon: "more_horiz"
                    text: Translation.tr("Maximum indicators per edge")
                    value: Config.options?.calendar?.maxEventDots ?? 3
                    from: 0
                    to: 3
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("calendar.maxEventDots", value)
                }
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
        }

        SettingsGroup {
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 34
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    MaterialSymbol {
                        text: CalendarSync.fetching ? "sync" : "event_available"
                        iconSize: 16
                        color: CalendarSync.enabled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: CalendarSync.fetching
                            ? Translation.tr("Syncing feeds…")
                            : (CalendarSync.sources.length + " " + Translation.tr("sources") + " · " + CalendarSync.events.length + " " + Translation.tr("events"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    RippleButton {
                        enabled: CalendarSync.enabled && CalendarSync.sources.length > 0 && !CalendarSync.fetching
                        implicitWidth: syncNowRow.implicitWidth + 14
                        implicitHeight: 24
                        buttonRadius: 12
                        opacity: enabled ? 1 : 0.55
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: CalendarSync.fetchAll()

                        contentItem: Item {
                            Row {
                                id: syncNowRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "refresh"
                                    iconSize: 12
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Sync now")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Translation.tr("Calendar Sources")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                RippleButton {
                    implicitWidth: addRow.implicitWidth + 16
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
                    onClicked: addSourceForm.expanded = !addSourceForm.expanded

                    contentItem: Item {
                        Row {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "add"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }

            Repeater {
                model: Config.options?.calendar?.externalSync?.sources ?? []

                delegate: Item {
                    id: sourceItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: sourceRow.implicitHeight + 12

                    Rectangle {
                        anchors.fill: parent
                        clip: true
                        radius: Appearance.rounding.small
                        color: sourceMA.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                        RowLayout {
                            id: sourceRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: sourceItem.modelData?.color ?? Appearance.colors.colPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                clip: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: sourceItem.modelData?.name ?? Translation.tr("Unnamed")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: sourceItem.modelData?.url ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                }
                            }

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

                            Switch {
                                checked: sourceItem.modelData?.enabled ?? true
                                onCheckedChanged: {
                                    if (checked !== (sourceItem.modelData?.enabled ?? true)) {
                                        CalendarSync.toggleSource(sourceItem.modelData.id, checked)
                                    }
                                }
                            }

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

            StyledText {
                visible: (Config.options?.calendar?.externalSync?.sources ?? []).length === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                text: Translation.tr("No calendar sources added yet")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                font.italic: true
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                text: Translation.tr("Paste a compatible ICS/iCal feed URL; no account sign-in within Alis.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                opacity: 0.75
            }

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
                    spacing: 10

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
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
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
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
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
        id: workflowsSection
        objectName: "integrationWorkflowsCard"
        _consumesBentoExtraHeight: false
        visible: true
        expanded: true
        icon: "hub"
        title: Translation.tr("Connected Workflows & Defaults")

        SettingsGroup {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Translation.tr("Tasks backend")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.minimumWidth: 0
                    text: Todo.sourceLabel
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            ConfigSelectionArray {
                objectName: "integrationTasksBackendSelector"
                Layout.fillWidth: true
                enableSettingsSearch: false
                currentValue: Todo.backend
                options: [
                    {
                        displayName: Translation.tr("Alis internal"),
                        icon: "checklist",
                        value: "internal"
                    },
                    {
                        displayName: Translation.tr("Alis Nexus"),
                        icon: "hub",
                        value: "nexus"
                    }
                ]
                onSelected: nextValue => {
                    if (nextValue === "internal") {
                        Todo.reactivateInternal()
                    } else if (AlisIntergration.nexusEnabled && Todo.nexusConfigured) {
                        Config.setNestedValue("todo.backend", "nexus")
                    } else {
                        root.openPluginModal("nexus", "todo")
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "school"
                    text: Translation.tr("Dashboard study tab")
                    checked: Config.options?.dashboard?.spacedRepetition?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.enable", checked)
                }

                SettingsSwitch {
                    objectName: "integrationExercisesTrackerTabSwitch"
                    buttonIcon: "fitness_center"
                    text: Translation.tr("Exercises Tracker tab")
                    enabled: AlisIntergration.available
                    checked: AlisIntergration.exercisesTrackerEnabled
                    onToggledByUser: nextChecked => {
                        AlisIntergration.setExercisesTrackerEnabled(nextChecked)
                        checked = Qt.binding(() => AlisIntergration.exercisesTrackerEnabled)
                    }
                }
            }

            SettingsSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Sync Nexus vault theme")
                checked: Config.options?.integrations?.nexus?.autoTheme ?? false
                onCheckedChanged: Config.setNestedValue("integrations.nexus.autoTheme", checked)
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "flag"
                    text: Translation.tr("Daily study goal")
                    value: Config.options?.dashboard?.spacedRepetition?.dailyGoalCards ?? 20
                    from: 5
                    to: 200
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.dailyGoalCards", value)
                    enabled: Config.options?.dashboard?.spacedRepetition?.enable ?? true
                }

                ConfigSpinBox {
                    icon: "library_add"
                    text: Translation.tr("New cards per day")
                    value: Config.options?.dashboard?.spacedRepetition?.dailyNewLimit ?? 20
                    from: 5
                    to: 100
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.dailyNewLimit", value)
                    enabled: Config.options?.dashboard?.spacedRepetition?.enable ?? true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 36
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    MaterialSymbol {
                        text: "task_alt"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: (Todo.list?.length ?? 0) + " " + Translation.tr("tasks") + " · " + Todo.sourceLabel
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    RippleButton {
                        implicitWidth: openStoreRow.implicitWidth + 14
                        implicitHeight: 24
                        buttonRadius: 12
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: Todo.openSource("")

                        contentItem: Item {
                            Row {
                                id: openStoreRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "open_in_new"
                                    iconSize: 12
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Open source")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsGroup {
            spacing: 8

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "package_2"
                    text: Translation.tr("Package actions in Search")
                    checked: Config.options?.search?.globalActions?.enablePackages ?? true
                    onCheckedChanged: Config.setNestedValue("search.globalActions.enablePackages", checked)
                }

                SettingsSwitch {
                    buttonIcon: "build"
                    text: Translation.tr("Setup actions in Search")
                    checked: Config.options?.search?.globalActions?.enableSetup ?? true
                    onCheckedChanged: Config.setNestedValue("search.globalActions.enableSetup", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    buttonIcon: "bolt"
                    text: Translation.tr("Default actions without prefix")
                    checked: Config.options?.search?.prefix?.showDefaultActionsWithoutPrefix ?? true
                    onCheckedChanged: Config.setNestedValue("search.prefix.showDefaultActionsWithoutPrefix", checked)
                }

                SettingsSwitch {
                    buttonIcon: "tune"
                    text: Translation.tr("Custom actions in Search")
                    checked: Config.options?.search?.globalActions?.enableCustom ?? true
                    onCheckedChanged: Config.setNestedValue("search.globalActions.enableCustom", checked)
                }
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Launcher result delay (ms)")
                value: Config.options?.search?.nonAppResultDelay ?? 30
                from: 0
                to: 250
                stepSize: 10
                onValueChanged: Config.setNestedValue("search.nonAppResultDelay", value)
            }

            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8

                DialogButton {
                    buttonText: Translation.tr("Open Alis Nexus")
                    onClicked: {
                        if (AlisIntergration.nexus)
                            AlisIntergration.nexus.open()
                        else
                            root.openPluginModal("nexus", "theming")
                    }
                }

                DialogButton {
                    buttonText: Translation.tr("Vault & Notes")
                    onClicked: root.openPluginModal("nexus", "theming")
                }

                DialogButton {
                    buttonText: Translation.tr("Tasks & Todo")
                    onClicked: root.openPluginModal("nexus", "todo")
                }
            }
        }
    }
}
