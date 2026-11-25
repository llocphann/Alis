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
    property string selectedPluginId: ""
    onActivePluginChanged: {
        if (root.activePlugin === "management" || root.activePlugin.length === 0) {
            if (root.selectedPluginId.length > 0)
                root.selectedPluginId = ""
            return
        }
        if (AlisIntergration.isPluginInstalled(root.activePlugin) && root.selectedPluginId !== root.activePlugin)
            root.selectedPluginId = root.activePlugin
    }
    readonly property bool detailOpen: root.selectedPluginId.length > 0
        && AlisIntergration.isPluginInstalled(root.selectedPluginId)
    property real slideProgress: root.detailOpen ? 1.0 : 0.0
    property string activeSection: "management"
    property var capabilitySelections: ({})
    property string copiedText: ""
    property bool showDiagnostics: false
    property bool helpersDrawerOpen: false

    Behavior on slideProgress {
        enabled: Appearance.animationsEnabled && !(Config.options?.performance?.reduceAnimations ?? false)
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    readonly property var primaryTabs: [{
        displayName: Translation.tr("Management"),
        icon: "extension",
        value: "management"
    }].concat(AlisIntergration.installedPlugins.map(plugin => ({
        displayName: plugin.id === "nexus" ? "Nexus" : plugin.name,
        icon: plugin.id === "nexus" ? "hub" : plugin.icon,
        value: plugin.id
    })))

    readonly property var catalog: {
        const order = ["alis_files", "nexus", "spaced_repetition", "exercises_tracker", "tlp", "thinkfan"]
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

    readonly property var selectedPlugin: AlisIntergration.installedPlugins.find(
        plugin => plugin.id === root.selectedPluginId
    ) ?? null
    readonly property var selectedCatalogPlugin: root.catalog.find(
        plugin => plugin.id === root.selectedPluginId
    ) ?? root.selectedPlugin ?? null
    readonly property var selectedDependencies: root.selectedPluginId.length > 0
        ? AlisIntergration.pluginDependencies(root.selectedPluginId)
        : ({ userSpace: true, requiresSystemHelpers: false, satisfied: true, binariesReady: true, helpersReady: true, binaries: [], helpers: [], missing: [], setupCommand: "", helpersCommand: "", removeHelpersCommand: "", note: "" })
    readonly property var selectedHelperStatus: root.selectedPluginId.length > 0
        ? AlisIntergration.pluginSystemHelpersStatus(root.selectedPluginId)
        : ({ managed: false, installed: false, diagnostic: "not-installed" })
    readonly property var capabilityTabs: selectedPlugin?.id === "nexus"
        ? []
        : (selectedPlugin?.capabilities ?? []).map(capability => ({
            displayName: capability.name,
            value: capability.id
        }))
    readonly property var selectedCapability: selectedPlugin?.id === "nexus"
        ? (selectedPlugin?.capabilities.find(capability => capability.settings === "nexus") ?? selectedPlugin?.capabilities[0] ?? null)
        : (selectedPlugin?.capabilities.find(capability =>
            capability.id === root.capabilitySelections[root.selectedPluginId]) ?? selectedPlugin?.capabilities[0] ?? null)

    Timer {
        id: copyResetTimer
        interval: 1800
        onTriggered: root.copiedText = ""
    }

    function copyCommand(cmd): void {
        const text = String(cmd ?? "").trim()
        if (!text) return
        Quickshell.clipboardText = text
        root.copiedText = text
        copyResetTimer.restart()
    }

    readonly property bool isSubViewActive: root.detailOpen
    readonly property string activeSubViewTitle: root.detailOpen
        ? root.pluginDisplayName(root.selectedCatalogPlugin)
        : ""

    function _demandActivePluginWorker(): void {
        if (root.selectedPluginId === "spaced_repetition" && AlisIntergration.spacedRepetitionEnabled)
            AlisIntergration.demandSpacedRepetition()
        else if (root.selectedPluginId === "exercises_tracker" && AlisIntergration.exercisesTrackerEnabled)
            AlisIntergration.demandExercisesTracker()
    }

    onSelectedPluginIdChanged: {
        root.helpersDrawerOpen = false
        root.showDiagnostics = false
        root._demandActivePluginWorker()
    }

    Connections {
        target: AlisIntergration
        function onSpacedRepetitionEnabledChanged(): void { root._demandActivePluginWorker() }
        function onExercisesTrackerEnabledChanged(): void { root._demandActivePluginWorker() }
    }

    Component.onCompleted: {
        if (root.visible)
            AlisIntergration.ensureSystemStatusLoaded()
    }
    onVisibleChanged: {
        if (root.visible) {
            AlisIntergration.ensureSystemStatusLoaded()
            if (!AlisIntergration.managerBusy && AlisIntergration.managerError.length > 0)
                AlisIntergration.clearFeedback()
        }
    }
    onPrimaryTabsChanged: {
        if (root.selectedPluginId.length > 0 && !AlisIntergration.isPluginInstalled(root.selectedPluginId)) {
            root.closePluginDetail()
            return
        }
        if (!primaryTabs.some(tab => tab.value === activePlugin))
            activePlugin = "management"
    }

    function openPluginSettings(pluginId, capabilityId = ""): void {
        if (typeof pluginId !== "string" || pluginId.length === 0)
            return
        // Uninstalled plugins must NOT slide into Settings.
        if (!AlisIntergration.isPluginInstalled(pluginId))
            return
        if (capabilityId && capabilityId.length > 0)
            root.selectCapability(capabilityId, pluginId)
        root.selectedPluginId = pluginId
        root.activePlugin = pluginId
        root.showDiagnostics = false
        root.helpersDrawerOpen = false
        root.contentY = 0
    }

    function closePluginDetail(): void {
        root.selectedPluginId = ""
        root.activePlugin = "management"
        root.showDiagnostics = false
        root.helpersDrawerOpen = false
        root.contentY = 0
    }

    function exitSubView(): void {
        root.closePluginDetail()
    }

    function handleEscape(): bool {
        if (root.detailOpen) {
            const item = pluginSettings.item
            if (item && typeof item.handleEscape === "function" && item.handleEscape())
                return true
            if (item && item.shortcutsTabOpen === true) {
                item.shortcutsTabOpen = false
                return true
            }
            root.closePluginDetail()
            return true
        }
        return false
    }

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        const wanted = /alis[\s_-]*files|file[\s_-]*manager|explorer/.test(label) ? "alis_files"
            : /nexus|vault|outliner|graph|to-do|todo|quick note|zettelkasten/.test(label) ? "nexus"
            : /fan|cooling|thermal/.test(label) ? "thinkfan"
            : /spaced repetition|vocabulary|flashcard|cefr|sm-2/.test(label) ? "spaced_repetition"
            : /exercises?[\s_-]*tracker|workout|body tracker|fitness/.test(label) ? "exercises_tracker"
            : /\btlp\b|power|battery/.test(label) ? "tlp" : label
        const plugin = root.catalog.find(item => wanted === item.id || wanted.includes(item.id) || wanted.includes(item.name.toLowerCase()))
            ?? AlisIntergration.installedPlugins.find(item => wanted.includes(item.id) || wanted.includes(item.name.toLowerCase()))
        if (plugin && AlisIntergration.isPluginInstalled(plugin.id)) {
            const capability = plugin.id === "nexus" ? ""
                : /todo|to-do/.test(label) ? "todo"
                : /quick note|zettelkasten/.test(label) ? "quicknotes"
                : ""
            root.openPluginSettings(plugin.id, capability)
            return true
        }
        root.closePluginDetail()
        root.activeSection = "management"
        return true
    }

    function selectCapability(value, pluginId = ""): void {
        const target = (typeof pluginId === "string" && pluginId.length > 0) ? pluginId : root.selectedPluginId
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

    function pluginSubtitle(plugin): string {
        if (!plugin) return ""
        if (plugin.id === "alis_files") return Translation.tr("Native GTK4 file manager synced with Alis themes and tools")
        if (plugin.id === "nexus") return Translation.tr("Vault workspace, To-do tasks, and Quick Notes")
        if (plugin.id === "spaced_repetition") return Translation.tr("Vocabulary flashcards, SM-2+ scheduling and CEFR study")
        if (plugin.id === "exercises_tracker") return Translation.tr("Workouts, set logs and body progress tracking")
        if (plugin.id === "tlp") return Translation.tr("Battery charge thresholds, CPU and power profile rules")
        if (plugin.id === "thinkfan") return Translation.tr("ThinkPad fan levels, thermal curves and ThinkFan service")
        return ""
    }

    function pluginState(plugin): string {
        if (!plugin) return Translation.tr("Unavailable")
        if (AlisIntergration.managerBusy && AlisIntergration.managerPluginId === plugin.id)
            return Translation.tr("Downloading & installing…")
        const installed = AlisIntergration.isPluginInstalled(plugin.id)
        if (!installed)
            return Translation.tr("Not installed")
        const deps = AlisIntergration.pluginDependencies(plugin.id)
        if (!deps.userSpace && !AlisIntergration.pluginHelpersReady(plugin.id)) {
            const missing = Array.isArray(deps.missing) ? deps.missing : []
            if (missing.length > 0)
                return Translation.tr("Installed · Setup needed:") + " " + missing.map(m => String(m).split("/").pop()).join(", ")
            return Translation.tr("Installed · Helper setup required")
        }
        if (AlisIntergration.updateAvailable)
            return Translation.tr("Installed · Update available")
        return AlisIntergration.pluginEnabled(plugin.id)
            ? Translation.tr("Installed · Enabled")
            : Translation.tr("Installed · Disabled")
    }

    function detailHelperStateText(): string {
        const st = root.selectedHelperStatus
        if (!root.selectedDependencies.requiresSystemHelpers)
            return Translation.tr("User-space plugin")
        if (!AlisIntergration.systemProvisionerAvailable && !AlisIntergration.gatewayPackageInstalled)
            return Translation.tr("Gateway & helper setup required")
        if (st?.installed === true || root.selectedDependencies.helpersReady === true)
            return Translation.tr("Ready")
        if (st?.diagnostic === "modified")
            return Translation.tr("Modified externally")
        if (st?.diagnostic === "partial")
            return Translation.tr("Partially installed")
        return Translation.tr("Not installed")
    }

    component IntegrationActionButton: RippleButton {
        id: actionBtn
        property string iconName: ""
        property bool destructive: false
        implicitHeight: Math.round(32 * Appearance.fontSizeScale)
        implicitWidth: actionBtnRow.implicitWidth + 20
        buttonRadius: 10
        colBackground: actionBtn.destructive
            ? Qt.alpha(Appearance.colors.colError, 0.12)
            : SettingsMaterialPreset.controlSurface
        colBackgroundHover: actionBtn.destructive
            ? Qt.alpha(Appearance.colors.colError, 0.20)
            : SettingsMaterialPreset.controlSurfaceHover

        Rectangle {
            anchors.fill: parent
            radius: actionBtn.buttonEffectiveRadius
            color: "transparent"
            border.width: 1
            border.color: actionBtn.destructive
                ? Qt.alpha(Appearance.colors.colError, 0.30)
                : SettingsMaterialPreset.controlBorderColor
            z: 1
        }

        contentItem: Item {
            implicitWidth: actionBtnRow.implicitWidth
            implicitHeight: actionBtnRow.implicitHeight

            Row {
                id: actionBtnRow
                anchors.centerIn: parent
                spacing: actionBtn.iconName.length > 0 ? 6 : 0

                MaterialSymbol {
                    visible: actionBtn.iconName.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: actionBtn.iconName
                    iconSize: 15
                    color: actionBtn.destructive
                        ? Appearance.colors.colError
                        : SettingsMaterialPreset.secondaryTextColor
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: actionBtn.buttonText
                    font.family: SettingsMaterialPreset.fontFamily
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: actionBtn.destructive
                        ? Appearance.colors.colError
                        : SettingsMaterialPreset.textColor
                }
            }
        }
    }

    Item {
        id: drillDownViewport
        objectName: "integrationDrillDownViewport"
        property bool _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        clip: true
        implicitHeight: Math.max(
            120,
            Math.round(listView.implicitHeight * (1 - root.slideProgress) + detailView.implicitHeight * root.slideProgress)
        )
        height: implicitHeight

        // Page 0: Integrations Plugin Catalog (slides left out on drill-down)
        Item {
            id: listView
            objectName: "integrationListView"
            width: drillDownViewport.width
            implicitHeight: listCol.implicitHeight
            height: implicitHeight
            x: -root.slideProgress * drillDownViewport.width
            opacity: 1 - root.slideProgress * 0.35
            visible: !root.detailOpen || root.slideProgress < 0.999
            enabled: !root.detailOpen

            ColumnLayout {
                id: listCol
                width: listView.width
                spacing: 12

                SettingsCardSection {
                    id: packageSection
                    objectName: "integrationOptionalPluginsCard"
                    property bool _preventBentoReparent: true
                    _consumesBentoExtraHeight: false
                    visible: true
                    expanded: true
                    icon: "extension"
                    title: Translation.tr("Optional Plugins")

                    SettingsGroup {
                        spacing: 10

                        GridLayout {
                            id: packageHeaderGrid
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            readonly property bool stacked: width < Math.round(540 * Appearance.fontSizeScale)
                            columns: stacked ? 1 : 2
                            columnSpacing: 12
                            rowSpacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 10

                                MaterialSymbol {
                                    text: AlisIntergration.available
                                        ? (AlisIntergration.loadFailed ? "error" : "check_circle")
                                        : "extension"
                                    iconSize: 20
                                    color: AlisIntergration.available
                                        ? (AlisIntergration.loadFailed ? Appearance.colors.colError : Appearance.colors.colPrimary)
                                        : Appearance.colors.colSubtext
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        text: AlisIntergration.available && AlisIntergration.version.length > 0 && !AlisIntergration.loadFailed
                                            ? ("Alis-Intergration " + AlisIntergration.version + " · "
                                                + AlisIntergration.installedPluginIds.length + " / " + root.catalog.length + " " + Translation.tr("installed"))
                                            : ((AlisIntergration.loadFailed || !AlisIntergration.available)
                                                ? (AlisIntergration.diagnostic === "not-installed"
                                                    ? Translation.tr("Alis-Intergration base package not installed")
                                                    : Translation.tr("Alis-Intergration package unavailable") + " (" + AlisIntergration.diagnostic + ")")
                                                : (AlisIntergration.installedPluginIds.length === 0
                                                    ? Translation.tr("Integrations ready — download individual plugins below.")
                                                    : (AlisIntergration.installedPluginIds.length + " / " + root.catalog.length + " " + Translation.tr("installed"))))
                                    }

                                    StyledText {
                                        visible: AlisIntergration.managerError.length > 0 || AlisIntergration.managerMessage.length > 0
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: AlisIntergration.managerError.length > 0
                                            ? Appearance.colors.colError
                                            : Appearance.colors.colSubtext
                                        text: AlisIntergration.managerError || AlisIntergration.managerMessage
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: packageHeaderGrid.stacked
                                Layout.alignment: packageHeaderGrid.stacked ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
                                spacing: 8

                                IntegrationActionButton {
                                    Layout.fillWidth: packageHeaderGrid.stacked
                                    visible: AlisIntergration.updateAvailable
                                    iconName: "system_update"
                                    buttonText: Translation.tr("Update base")
                                    enabled: !AlisIntergration.managerBusy
                                    onClicked: AlisIntergration.manage("install-base")
                                }

                                IntegrationActionButton {
                                    Layout.fillWidth: packageHeaderGrid.stacked
                                    visible: AlisIntergration.available
                                    iconName: "update"
                                    buttonText: Translation.tr("Check updates")
                                    enabled: !AlisIntergration.managerBusy
                                    onClicked: AlisIntergration.manage("check")
                                }

                                IntegrationActionButton {
                                    Layout.fillWidth: packageHeaderGrid.stacked
                                    visible: AlisIntergration.canRollback
                                    iconName: "undo"
                                    buttonText: Translation.tr("Undo")
                                    enabled: !AlisIntergration.managerBusy
                                    onClicked: AlisIntergration.manage("rollback")
                                }

                                IntegrationActionButton {
                                    Layout.fillWidth: packageHeaderGrid.stacked
                                    iconName: "refresh"
                                    buttonText: Translation.tr("Refresh")
                                    enabled: !AlisIntergration.managerBusy
                                    onClicked: {
                                        AlisIntergration.refresh()
                                        AlisIntergration.refreshSystemStatus()
                                    }
                                }
                            }
                        }

                        // Recovery banner: preserve user's option to restore Alis internal Todo
                        // whenever Nexus backend was selected but Nexus is uninstalled or disabled.
                        Rectangle {
                            visible: Todo.backend === "nexus" && !AlisIntergration.nexusEnabled
                            Layout.fillWidth: true
                            implicitHeight: recoveryRow.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            RowLayout {
                                id: recoveryRow
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                MaterialSymbol {
                                    text: "warning"
                                    iconSize: 18
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1
                                    text: Translation.tr("To-do backend is set to Nexus, but the Nexus plugin is not active.")
                                }

                                IntegrationActionButton {
                                    objectName: "integrationRestoreInternalTodos"
                                    iconName: "restore"
                                    buttonText: Translation.tr("Restore internal Todo")
                                    onClicked: Todo.reactivateInternal()
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: pluginsListColumn.implicitHeight
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
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
                                        readonly property bool helpersReady: AlisIntergration.pluginHelpersReady(pluginCard.modelData.id)
                                        readonly property bool isWorking: AlisIntergration.managerBusy && AlisIntergration.managerPluginId === pluginCard.modelData.id
                                        objectName: "integrationPluginCard_" + pluginCard.modelData.id
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        clip: true
                                        implicitHeight: Math.max(66, pluginCardRow.implicitHeight + 20)
                                        color: pluginCard.isInstalled && pluginCardMouse.containsMouse
                                            ? Appearance.colors.colLayer2Hover
                                            : "transparent"

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

                                        // Only installed rows may drill down into Settings.
                                        MouseArea {
                                            id: pluginCardMouse
                                            anchors.fill: parent
                                            enabled: pluginCard.isInstalled
                                            hoverEnabled: pluginCard.isInstalled
                                            cursorShape: pluginCard.isInstalled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (pluginCard.isInstalled)
                                                    root.openPluginSettings(pluginCard.modelData.id)
                                            }
                                        }

                                        RowLayout {
                                            id: pluginCardRow
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 12
                                            spacing: 12

                                            Rectangle {
                                                Layout.preferredWidth: 38
                                                Layout.preferredHeight: 38
                                                radius: Appearance.rounding.small
                                                color: pluginCard.isInstalled
                                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86)
                                                    : Appearance.colors.colLayer2
                                                border.width: 1
                                                border.color: pluginCard.isInstalled
                                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.62)
                                                    : Appearance.colors.colLayer0Border

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: root.pluginIconName(pluginCard.modelData)
                                                    iconSize: 19
                                                    color: pluginCard.isInstalled
                                                        ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colOnSurfaceVariant
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
                                                    text: root.pluginSubtitle(pluginCard.modelData)
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: root.pluginState(pluginCard.modelData)
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: pluginCard.isInstalled && !pluginCard.deps.userSpace && !pluginCard.helpersReady
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
                                                    implicitHeight: 32
                                                    buttonRadius: Appearance.rounding.small
                                                    colBackground: Appearance.colors.colPrimary
                                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                                    opacity: enabled ? 1 : 0.6
                                                    onClicked: AlisIntergration.installPlugin(pluginCard.modelData.id)

                                                    contentItem: Item {
                                                        Row {
                                                            id: cardInstallRow
                                                            anchors.centerIn: parent
                                                            spacing: 6

                                                            MaterialSymbol {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: pluginCard.isWorking ? "hourglass_top" : "download"
                                                                iconSize: 15
                                                                color: Appearance.colors.colOnPrimary
                                                            }

                                                            StyledText {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: pluginCard.isWorking
                                                                    ? Translation.tr("Working…")
                                                                    : Translation.tr("Download & Install")
                                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                                font.weight: Font.Medium
                                                                color: Appearance.colors.colOnPrimary
                                                            }
                                                        }
                                                    }
                                                }

                                                StyledSwitch {
                                                    visible: pluginCard.isInstalled
                                                    objectName: "integrationEnable_" + pluginCard.modelData.id
                                                    enabled: !AlisIntergration.managerBusy
                                                    checked: pluginCard.isEnabled
                                                    onToggled: {
                                                        AlisIntergration.setPluginEnabled(pluginCard.modelData.id, checked)
                                                        checked = Qt.binding(() => AlisIntergration.pluginEnabled(pluginCard.modelData.id))
                                                    }
                                                }

                                                RippleButton {
                                                    visible: pluginCard.isInstalled
                                                    objectName: "integrationOpenSettings_" + pluginCard.modelData.id
                                                    implicitWidth: cardSettingsRow.implicitWidth + 18
                                                    implicitHeight: 32
                                                    buttonRadius: Appearance.rounding.small
                                                    colBackground: Appearance.colors.colLayer2
                                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                                    onClicked: root.openPluginSettings(pluginCard.modelData.id)

                                                    contentItem: Item {
                                                        Row {
                                                            id: cardSettingsRow
                                                            anchors.centerIn: parent
                                                            spacing: 5

                                                            MaterialSymbol {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: "settings"
                                                                iconSize: 15
                                                                color: Appearance.colors.colOnLayer1
                                                            }

                                                            StyledText {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: Translation.tr("Settings")
                                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                                font.weight: Font.Medium
                                                                color: Appearance.colors.colOnLayer1
                                                            }

                                                            MaterialSymbol {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: "chevron_right"
                                                                iconSize: 16
                                                                color: Appearance.colors.colOnSurfaceVariant
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Page 1: Per-Plugin Drill-down Settings (slides in from right)
        Item {
            id: detailView
            objectName: "integrationDetailView"
            width: drillDownViewport.width
            implicitHeight: detailCol.implicitHeight
            height: implicitHeight
            x: (1 - root.slideProgress) * drillDownViewport.width
            opacity: root.detailOpen ? (0.45 + 0.55 * root.slideProgress) : root.slideProgress
            visible: root.detailOpen || root.slideProgress > 0.001
            enabled: root.detailOpen

            ColumnLayout {
                id: detailCol
                width: detailView.width
                spacing: 12

                // Drill-down header bar with Back, enable switch, and Uninstall
                SettingsCardSection {
                    id: detailHeaderCard
                    objectName: "integrationDetailHeaderCard"
                    property bool _preventBentoReparent: true
                    _consumesBentoExtraHeight: false
                    visible: true
                    expanded: true
                    showHeader: false

                    SettingsGroup {
                        spacing: 10

                        Item {
                            id: detailHeaderRowContainer
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            readonly property bool stackCenterPill: width > 0
                                && width < (detailLeftGroup.implicitWidth + headerCenterPill.width + detailRightGroup.implicitWidth + 28)
                            readonly property real topBarHeight: Math.max(
                                detailLeftGroup.implicitHeight,
                                detailRightGroup.implicitHeight,
                                stackCenterPill ? 0 : headerCenterPill.height
                            )
                            implicitHeight: stackCenterPill
                                ? (topBarHeight + 8 + headerCenterPill.height)
                                : topBarHeight

                            RowLayout {
                                id: detailLeftGroup
                                anchors.left: parent.left
                                y: Math.round((detailHeaderRowContainer.topBarHeight - height) / 2)
                                width: Math.min(
                                    implicitWidth,
                                    detailHeaderRowContainer.stackCenterPill
                                        ? Math.max(80, detailHeaderRowContainer.width - detailRightGroup.implicitWidth - 12)
                                        : Math.max(80, Math.round((detailHeaderRowContainer.width - headerCenterPill.width) / 2) - 10)
                                )
                                spacing: 8

                                RippleButton {
                                    objectName: "integrationBackButton"
                                    implicitWidth: backBtnRow.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: Appearance.colors.colLayer1
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    onClicked: root.closePluginDetail()

                                    contentItem: Item {
                                        Row {
                                            id: backBtnRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "arrow_back"
                                                iconSize: 16
                                                color: Appearance.colors.colOnLayer1
                                            }

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Translation.tr("Back")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer1
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: Appearance.rounding.small
                                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86)
                                    border.width: 1
                                    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.62)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: root.pluginIconName(root.selectedCatalogPlugin)
                                        iconSize: 17
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
                                        text: root.pluginDisplayName(root.selectedCatalogPlugin)
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: root.selectedCatalogPlugin ? root.pluginState(root.selectedCatalogPlugin) : ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Centered compact header pill: hosts TLP status buttons (when applicable) + compact Helpers/Diagnostics toggle
                            Rectangle {
                                id: headerCenterPill
                                objectName: "integrationHeaderCenterPill"
                                visible: root.detailOpen
                                readonly property bool depsHealthy: root.selectedDependencies.userSpace
                                    ? (root.selectedDependencies.binariesReady !== false)
                                    : AlisIntergration.pluginHelpersReady(root.selectedPluginId)
                                x: Math.round((detailHeaderRowContainer.width - width) / 2)
                                y: detailHeaderRowContainer.stackCenterPill
                                    ? (detailHeaderRowContainer.topBarHeight + 8)
                                    : Math.round((detailHeaderRowContainer.topBarHeight - height) / 2)
                                width: centerPillRow.implicitWidth + 12
                                height: 40
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colLayer1
                                border.width: 1
                                border.color: root.helpersDrawerOpen
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
                                    : Appearance.colors.colLayer0Border

                                RowLayout {
                                    id: centerPillRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Loader {
                                        id: pluginHeaderStatusLoader
                                        objectName: "integrationPluginHeaderStatusSlot"
                                        active: root.visible && root.detailOpen && pluginSettings.active
                                            && pluginSettings.status === Loader.Ready
                                            && Boolean(pluginSettings.item?.headerStatusBar)
                                        visible: active && item !== null
                                        sourceComponent: active ? (pluginSettings.item?.headerStatusBar ?? null) : null
                                    }

                                    Rectangle {
                                        visible: pluginHeaderStatusLoader.visible
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 18
                                        color: Appearance.colors.colOutlineVariant
                                        opacity: 0.6
                                    }

                                    RippleButton {
                                        id: pluginHelpersButton
                                        objectName: "integrationPluginHelpersButton"
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        buttonRadius: 16
                                        colBackground: !headerCenterPill.depsHealthy
                                            ? Appearance.colors.colErrorContainer
                                            : (root.helpersDrawerOpen
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colPrimaryContainer)
                                        colBackgroundHover: !headerCenterPill.depsHealthy
                                            ? Appearance.colors.colErrorContainer
                                            : (root.helpersDrawerOpen
                                                ? Appearance.colors.colPrimaryHover
                                                : Appearance.colors.colPrimaryContainerHover)
                                        onClicked: root.helpersDrawerOpen = !root.helpersDrawerOpen

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: !headerCenterPill.depsHealthy
                                                ? "warning"
                                                : (root.selectedDependencies.requiresSystemHelpers ? "verified_user" : "health_and_safety")
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: !headerCenterPill.depsHealthy
                                                ? Appearance.colors.colOnErrorContainer
                                                : (root.helpersDrawerOpen
                                                    ? Appearance.colors.colOnPrimary
                                                    : Appearance.colors.colOnPrimaryContainer)
                                        }

                                        StyledToolTip {
                                            text: (root.selectedDependencies.requiresSystemHelpers
                                                ? Translation.tr("System Helpers & Diagnostics")
                                                : Translation.tr("Dependencies & Diagnostics"))
                                                + " · " + root.detailHelperStateText()
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                id: detailRightGroup
                                anchors.right: parent.right
                                y: Math.round((detailHeaderRowContainer.topBarHeight - height) / 2)
                                spacing: 10

                                StyledSwitch {
                                    objectName: "integrationDetailEnableSwitch"
                                    enabled: !AlisIntergration.managerBusy && root.detailOpen
                                    checked: root.selectedPluginId.length > 0 && AlisIntergration.pluginEnabled(root.selectedPluginId)
                                    onToggled: {
                                        if (!root.selectedPluginId) return
                                        AlisIntergration.setPluginEnabled(root.selectedPluginId, checked)
                                        checked = Qt.binding(() => root.selectedPluginId.length > 0 && AlisIntergration.pluginEnabled(root.selectedPluginId))
                                    }
                                }

                                IntegrationActionButton {
                                    objectName: "integrationUninstallPluginButton"
                                    visible: root.detailOpen
                                    destructive: true
                                    iconName: "delete"
                                    buttonText: Translation.tr("Uninstall")
                                    enabled: !AlisIntergration.managerBusy
                                    onClicked: {
                                        const targetId = root.selectedPluginId
                                        if (!targetId) return
                                        root.closePluginDetail()
                                        AlisIntergration.removePlugin(targetId)
                                    }
                                }
                            }
                        }

                        // Capability switcher for multi-capability plugins (e.g. Nexus)
                        Item {
                            id: capabilityTabsWrapper
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: root.selectedPlugin !== null && root.capabilityTabs.length > 1
                            readonly property bool abyssStyle: Config.options?.panelFamily === "abyss"
                            readonly property real railPadding: abyssStyle ? SettingsMaterialPreset.taskTabPadding : 0
                            readonly property real naturalTabsWidth: {
                                let total = 0
                                let count = 0
                                for (let i = 0; i < capabilityTabsArray.children.length; ++i) {
                                    const child = capabilityTabsArray.children[i]
                                    if (child && child.visible && child.hasOwnProperty("modelData")) {
                                        total += Math.ceil(child.implicitWidth || child.width)
                                        count++
                                    }
                                }
                                return count > 0 ? total + Math.max(0, count - 1) * capabilityTabsArray.spacing : 0
                            }
                            implicitHeight: visible ? (capabilityTabsArray.implicitHeight + railPadding * 2) : 0

                            Rectangle {
                                id: capabilityTabsRail
                                objectName: "integrationCapabilityTabs"
                                x: capabilityTabsWrapper.abyssStyle ? Math.round((parent.width - width) / 2) : 0
                                y: 0
                                width: capabilityTabsWrapper.abyssStyle
                                    ? Math.min(parent.width, capabilityTabsWrapper.naturalTabsWidth + capabilityTabsWrapper.railPadding * 2)
                                    : parent.width
                                height: parent.height
                                color: capabilityTabsWrapper.abyssStyle ? SettingsMaterialPreset.taskRailColor : "transparent"
                                radius: SettingsMaterialPreset.taskRailRadius

                                ConfigSelectionArray {
                                    id: capabilityTabsArray
                                    objectName: "settingsTaskOptions"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: capabilityTabsWrapper.railPadding
                                    y: capabilityTabsWrapper.railPadding
                                    enableSettingsSearch: false
                                    options: root.capabilityTabs
                                    currentValue: root.selectedCapability?.id ?? ""
                                    taskNavigation: true
                                    useAbyssPillShape: false
                                    onSelected: value => root.selectCapability(value)
                                }
                            }
                        }

                        // Compact collapsible drawer for System Helpers, Dependencies & Diagnostics (toggled by header icon button)
                        Rectangle {
                            id: pluginDepsCard
                            objectName: "integrationPluginDependenciesCard"
                            visible: root.detailOpen && root.helpersDrawerOpen
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: pluginDepsCol.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            ColumnLayout {
                                id: pluginDepsCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 8

                                    MaterialSymbol {
                                        text: root.selectedDependencies.userSpace
                                            ? (root.selectedDependencies.binariesReady ? "check_circle" : "warning")
                                            : (AlisIntergration.pluginHelpersReady(root.selectedPluginId) ? "verified_user" : "warning")
                                        iconSize: 18
                                        color: (root.selectedDependencies.userSpace
                                            ? root.selectedDependencies.binariesReady
                                            : AlisIntergration.pluginHelpersReady(root.selectedPluginId))
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colError
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer1
                                            text: (root.selectedDependencies.requiresSystemHelpers
                                                ? Translation.tr("System Helpers & Diagnostics")
                                                : Translation.tr("Dependencies & Diagnostics"))
                                                + " · " + root.detailHelperStateText()
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            visible: (root.selectedDependencies.note ?? "").length > 0
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            text: root.selectedDependencies.note ?? ""
                                        }
                                    }

                                    IntegrationActionButton {
                                        objectName: "integrationPluginRefreshDiagnostics"
                                        iconName: "refresh"
                                        buttonText: Translation.tr("Refresh")
                                        enabled: !AlisIntergration.managerBusy
                                        onClicked: {
                                            AlisIntergration.refresh()
                                            AlisIntergration.refreshSystemStatus()
                                        }
                                    }

                                    IntegrationActionButton {
                                        objectName: "integrationPluginDiagnosticsToggle"
                                        iconName: root.showDiagnostics ? "visibility_off" : "bug_report"
                                        buttonText: root.showDiagnostics
                                            ? Translation.tr("Hide diagnostics")
                                            : Translation.tr("Diagnostics")
                                        onClicked: root.showDiagnostics = !root.showDiagnostics
                                    }
                                }

                                // Compact inline status chips (binaries, helpers, provisioner)
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: (root.selectedDependencies.binaries?.length ?? 0) > 0
                                        || root.selectedDependencies.requiresSystemHelpers

                                    Repeater {
                                        model: root.selectedDependencies.binaries ?? []
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitHeight: 24
                                            implicitWidth: binChipRow.implicitWidth + 14
                                            radius: Appearance.rounding.full
                                            color: Appearance.colors.colLayer2
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border

                                            RowLayout {
                                                id: binChipRow
                                                anchors.centerIn: parent
                                                spacing: 5
                                                MaterialSymbol {
                                                    text: modelData.installed ? "check_circle" : "error"
                                                    iconSize: 13
                                                    color: modelData.installed ? Appearance.colors.colPrimary : Appearance.colors.colError
                                                }
                                                StyledText {
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1
                                                    text: modelData.name + (modelData.installed ? (" · " + Translation.tr("Ready")) : (" · " + Translation.tr("Missing")))
                                                }
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: root.selectedDependencies.helpers ?? []
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitHeight: 24
                                            implicitWidth: helperChipRow.implicitWidth + 14
                                            radius: Appearance.rounding.full
                                            color: Appearance.colors.colLayer2
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border

                                            RowLayout {
                                                id: helperChipRow
                                                anchors.centerIn: parent
                                                spacing: 5
                                                MaterialSymbol {
                                                    text: modelData.installed ? "check_circle" : "error"
                                                    iconSize: 13
                                                    color: modelData.installed ? Appearance.colors.colPrimary : Appearance.colors.colError
                                                }
                                                StyledText {
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1
                                                    text: String(modelData.path || "").split("/").pop()
                                                        + (modelData.installed ? (" · " + Translation.tr("Installed")) : (" · " + Translation.tr("Not installed")))
                                                }
                                            }
                                            StyledToolTip { text: String(modelData.path || "") }
                                        }
                                    }

                                    Rectangle {
                                        visible: root.selectedDependencies.requiresSystemHelpers
                                        implicitHeight: 24
                                        implicitWidth: provChipRow.implicitWidth + 14
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colLayer2
                                        border.width: 1
                                        border.color: Appearance.colors.colLayer0Border

                                        RowLayout {
                                            id: provChipRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MaterialSymbol {
                                                text: AlisIntergration.systemProvisionerAvailable ? "verified" : "shield"
                                                iconSize: 13
                                                color: AlisIntergration.systemProvisionerAvailable
                                                    ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colOnSurfaceVariant
                                            }
                                            StyledText {
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1
                                                text: Translation.tr("Polkit Provisioner:") + " "
                                                    + (AlisIntergration.systemProvisionerAvailable
                                                        ? Translation.tr("Available")
                                                        : Translation.tr("Provisioned by ./setup integrations"))
                                            }
                                        }
                                    }
                                }

                                // Copyable terminal commands when helpers or binaries need provisioning
                                Rectangle {
                                    visible: (!root.selectedDependencies.satisfied || root.selectedDependencies.requiresSystemHelpers)
                                        && ((root.selectedDependencies.setupCommand ?? "").length > 0
                                            || (root.selectedDependencies.helpersCommand ?? "").length > 0)
                                    Layout.fillWidth: true
                                    implicitHeight: commandsCol.implicitHeight + 14
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colSurfaceContainerLow
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: commandsCol
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        spacing: 5

                                        RowLayout {
                                            visible: (root.selectedDependencies.setupCommand ?? "").length > 0
                                                && root.selectedDependencies.binariesReady !== true
                                            Layout.fillWidth: true
                                            spacing: 8

                                            StyledText {
                                                Layout.fillWidth: true
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1
                                                text: root.selectedDependencies.setupCommand ?? "./setup install-deps"
                                                elide: Text.ElideRight
                                            }

                                            IntegrationActionButton {
                                                iconName: root.copiedText === (root.selectedDependencies.setupCommand ?? "./setup install-deps")
                                                    ? "check"
                                                    : "content_copy"
                                                buttonText: root.copiedText === (root.selectedDependencies.setupCommand ?? "./setup install-deps")
                                                    ? Translation.tr("Copied")
                                                    : Translation.tr("Copy")
                                                onClicked: root.copyCommand(root.selectedDependencies.setupCommand || "./setup install-deps")
                                            }
                                        }

                                        RowLayout {
                                            visible: (root.selectedDependencies.helpersCommand ?? "").length > 0
                                            Layout.fillWidth: true
                                            spacing: 8

                                            StyledText {
                                                Layout.fillWidth: true
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1
                                                text: root.selectedDependencies.helpersCommand ?? ""
                                                elide: Text.ElideRight
                                            }

                                            IntegrationActionButton {
                                                objectName: "integrationCopyHelpersCommand"
                                                iconName: root.copiedText === (root.selectedDependencies.helpersCommand ?? "")
                                                    ? "check"
                                                    : "content_copy"
                                                buttonText: root.copiedText === (root.selectedDependencies.helpersCommand ?? "")
                                                    ? Translation.tr("Copied")
                                                    : Translation.tr("Copy")
                                                onClicked: root.copyCommand(root.selectedDependencies.helpersCommand)
                                            }
                                        }

                                        RowLayout {
                                            visible: (root.selectedDependencies.removeHelpersCommand ?? "").length > 0
                                                && (root.selectedHelperStatus?.managed === true || root.selectedHelperStatus?.installed === true)
                                            Layout.fillWidth: true
                                            spacing: 8

                                            StyledText {
                                                Layout.fillWidth: true
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                                text: root.selectedDependencies.removeHelpersCommand ?? ""
                                                elide: Text.ElideRight
                                            }

                                            IntegrationActionButton {
                                                iconName: root.copiedText === (root.selectedDependencies.removeHelpersCommand ?? "")
                                                    ? "check"
                                                    : "content_copy"
                                                buttonText: root.copiedText === (root.selectedDependencies.removeHelpersCommand ?? "")
                                                    ? Translation.tr("Copied")
                                                    : Translation.tr("Copy")
                                                onClicked: root.copyCommand(root.selectedDependencies.removeHelpersCommand)
                                            }
                                        }
                                    }
                                }

                                // Expandable diagnostics detail box
                                Rectangle {
                                    visible: root.showDiagnostics
                                    Layout.fillWidth: true
                                    implicitHeight: diagCol.implicitHeight + 14
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colSurfaceContainerLow
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: diagCol
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        spacing: 3

                                        StyledText {
                                            Layout.fillWidth: true
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer1
                                            wrapMode: Text.WrapAnywhere
                                            text: "plugin=" + root.selectedPluginId
                                                + " · layout=" + (AlisIntergration.packageLayout || "unknown")
                                                + " · sha=" + (AlisIntergration.sourceSha ? AlisIntergration.sourceSha.slice(0, 12) : "none")
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            wrapMode: Text.WrapAnywhere
                                            text: "path=" + (String(AlisIntergration.pluginRoots?.[root.selectedPluginId] ?? "") || AlisIntergration.packageRoot || "not-installed")
                                        }

                                        StyledText {
                                            visible: root.selectedDependencies.requiresSystemHelpers
                                            Layout.fillWidth: true
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            wrapMode: Text.WrapAnywhere
                                            text: "helperState=" + String(root.selectedHelperStatus?.diagnostic ?? AlisIntergration.systemHelpersDiagnostic ?? "unchecked")
                                                + " · provisioner=" + (AlisIntergration.systemProvisionerAvailable ? "ready" : "absent")
                                                + " · gatewayPkg=" + (AlisIntergration.gatewayPackageInstalled ? "installed" : "absent")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Disabled notice when installed plugin isn't enabled yet
                SettingsCardSection {
                    property bool _preventBentoReparent: true
                    _consumesBentoExtraHeight: false
                    visible: root.detailOpen && !AlisIntergration.pluginEnabled(root.selectedPluginId)
                    expanded: true
                    showHeader: false

                    SettingsGroup {
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colSubtext
                            text: (!AlisIntergration.available || AlisIntergration.loadFailed)
                                ? Translation.tr("Plugin unavailable. Refresh or update the optional package.")
                                : Translation.tr("Enable this plugin above to configure it.")
                        }
                    }
                }

                // Active plugin settings card(s)
                Loader {
                    id: pluginSettings
                    objectName: "integrationPluginSettings"
                    Layout.fillWidth: true
                    Layout.preferredHeight: item?.implicitHeight ?? 0
                    visible: active
                    active: root.visible && root.detailOpen && root.selectedPlugin !== null && AlisIntergration.pluginEnabled(root.activePlugin)
                    property string _loadedKey: ""
                    property string capabilitySource: root.selectedCapability
                        ? AlisIntergration.settingsSource(Config.options?.panelFamily === "waffle"
                            ? root.selectedCapability.waffleSettings ?? root.selectedCapability.settings
                            : root.selectedCapability.settings) : ""
                    property string capabilityView: root.selectedCapability?.view ?? ""
                    function reload(): void {
                        const isActive = root.visible && root.detailOpen && root.selectedPlugin !== null && AlisIntergration.pluginEnabled(root.activePlugin)
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
                        const props = view.length ? ({ settingsView: view }) : ({})
                        if (root.selectedPluginId === "tlp")
                            props.embeddedInIntegrationsHeader = true
                        if (nextKey.length > 0)
                            setSource(src, props)
                    }
                    onActiveChanged: reload()
                    onCapabilitySourceChanged: reload()
                    onCapabilityViewChanged: reload()
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    visible: pluginSettings.status === Loader.Error
                    text: Translation.tr("Plugin settings could not be loaded. Refresh or re-download this plugin.")
                    color: Appearance.colors.colError
                }
            }
        }
    }
}
