import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings

ContentPage {
    id: root
    settingsPageIndex: 8
    settingsPageName: Translation.tr("Autostart")

    property string appSearchText: ""
    property string serviceSearchText: ""
    property string _effectiveAppSearch: ""
    property string _effectiveServiceSearch: ""
    onAppSearchTextChanged: {
        if (appSearchText.trim().length === 0) {
            appSearchDebounce.stop()
            _effectiveAppSearch = ""
        } else {
            appSearchDebounce.restart()
        }
    }
    onServiceSearchTextChanged: {
        if (serviceSearchText.trim().length === 0) {
            serviceSearchDebounce.stop()
            _effectiveServiceSearch = ""
        } else {
            serviceSearchDebounce.restart()
        }
    }

    Timer {
        id: appSearchDebounce
        interval: 80
        repeat: false
        onTriggered: root._effectiveAppSearch = root.appSearchText
    }

    Timer {
        id: serviceSearchDebounce
        interval: 80
        repeat: false
        onTriggered: root._effectiveServiceSearch = root.serviceSearchText
    }
    property bool showAllServices: false
    property string newServiceInput: ""
    property var userServices: []
    property bool loadingServices: false
    property string serviceStatusMessage: ""
    property string serviceErrorMessage: ""
    property string _servicesStdout: ""
    property real targetContainerHeight: 0
    readonly property real _effectiveTargetHeight: root.targetContainerHeight > 0 ? root.targetContainerHeight : 480
    readonly property real _targetGridHeight: _effectiveTargetHeight
    property var cachedServicesState: null
    signal servicesStateUpdated(var state)

    readonly property string _servicesHelper: Quickshell.shellPath("scripts/apps/manage-autostart-services.py")
    readonly property string _legacySubtext: Translation.tr("Manage startup apps and commands written to niri.")
    readonly property string _legacyNotice: Translation.tr("Niri launches these at login; they keep running after shell restarts.")
    readonly property string _legacyShellHint: Translation.tr("Niri shell commands support pipes, environment variables and &&.")

    component HoverMarqueeText: Item {
        id: mqRoot
        property string text: ""
        property bool hovered: false
        property color color: Appearance.colors.colSubtext
        property int pixelSize: Appearance.font.pixelSize.smaller
        property string fontFamily: Appearance.font.family.main
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        implicitHeight: mqText.implicitHeight
        clip: true

        readonly property real overflowDistance: Math.max(0, Math.ceil(mqText.implicitWidth - mqRoot.width))
        property real scrollOffset: 0

        onHoveredChanged: {
            if (!hovered)
                scrollOffset = 0
        }
        onTextChanged: scrollOffset = 0
        onWidthChanged: {
            if (overflowDistance <= 0)
                scrollOffset = 0
        }

        SequentialAnimation on scrollOffset {
            running: mqRoot.hovered && mqRoot.overflowDistance > 2 && (Appearance?.animationsEnabled ?? true)
            loops: Animation.Infinite
            PauseAnimation { duration: 250 }
            NumberAnimation {
                from: 0
                to: mqRoot.overflowDistance
                duration: Math.max(900, mqRoot.overflowDistance * 22)
                easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: 700 }
            NumberAnimation {
                from: mqRoot.overflowDistance
                to: 0
                duration: Math.max(900, mqRoot.overflowDistance * 22)
                easing.type: Easing.InOutSine
            }
        }

        StyledText {
            id: mqText
            x: (mqRoot.hovered && mqRoot.overflowDistance > 2) ? -mqRoot.scrollOffset : 0
            width: (mqRoot.hovered && mqRoot.overflowDistance > 2) ? mqText.implicitWidth : mqRoot.width
            anchors.verticalCenter: parent.verticalCenter
            text: mqRoot.text
            font.pixelSize: mqRoot.pixelSize
            font.family: mqRoot.fontFamily
            color: mqRoot.color
            elide: (mqRoot.hovered && mqRoot.overflowDistance > 2) ? Text.ElideNone : Text.ElideRight
            maximumLineCount: 1
            wrapMode: Text.NoWrap
        }
    }

    Component.onCompleted: {
        if (Array.isArray(root.cachedServicesState) && root.cachedServicesState.length > 0) {
            root.userServices = root.cachedServicesState
        }
        Autostart.reload()
        root.refreshServices()
    }

    function refreshServices(): void {
        if (servicesListProc.running)
            return
        root.loadingServices = true
        root._servicesStdout = ""
        servicesListProc.command = ["/usr/bin/python3", root._servicesHelper, "list"]
        servicesListProc.running = true
    }

    function setServiceAutostart(unitName: string, enableFlag: bool): void {
        if (servicesActionProc.running)
            return
        root.serviceErrorMessage = ""
        root.serviceStatusMessage = ""
        root._servicesStdout = ""
        servicesActionProc.command = [
            "/usr/bin/python3",
            root._servicesHelper,
            "set-enabled",
            unitName,
            enableFlag ? "true" : "false"
        ]
        servicesActionProc.running = true
    }

    function runServiceAction(unitName: string, actionName: string): void {
        if (servicesActionProc.running)
            return
        root.serviceErrorMessage = ""
        root.serviceStatusMessage = ""
        root._servicesStdout = ""
        servicesActionProc.command = [
            "/usr/bin/python3",
            root._servicesHelper,
            "action",
            unitName,
            actionName
        ]
        servicesActionProc.running = true
    }

    function addAutostartServiceOrDaemon(): void {
        const raw = root.newServiceInput.trim()
        if (raw.length === 0)
            return
        const normalized = raw.endsWith(".service") ? raw : `${raw}.service`
        const matchesSystemd = raw.endsWith(".service")
            || (!raw.includes(" ") && root.userServices.some(s => s.unit === normalized || s.name === raw))
        if (matchesSystemd) {
            root.setServiceAutostart(normalized, true)
            root.newServiceInput = ""
            serviceAddField.text = ""
            return
        }
        if (Autostart.ready) {
            Autostart.addCommand(raw)
            root.newServiceInput = ""
            serviceAddField.text = ""
            root.serviceStatusMessage = Translation.tr("Added startup daemon command")
            root.serviceErrorMessage = ""
        }
    }

    function _applyServicesPayload(rawJson: string): void {
        try {
            const data = JSON.parse(rawJson)
            if (Array.isArray(data.services)) {
                root.userServices = data.services
                root.servicesStateUpdated(data.services)
            }
            if (data.ok === false && data.error) {
                root.serviceErrorMessage = String(data.error)
            } else if (data.message) {
                root.serviceStatusMessage = String(data.message)
                root.serviceErrorMessage = ""
            }
        } catch (e) {
            console.warn("[AutostartConfig] Failed to parse services JSON:", e)
        }
    }

    Process {
        id: servicesListProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._servicesStdout = this.text ?? ""
        }
        onExited: (exitCode, exitStatus) => {
            root.loadingServices = false
            if (root._servicesStdout.trim().length > 0) {
                root._applyServicesPayload(root._servicesStdout)
            }
        }
    }

    Process {
        id: servicesActionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._servicesStdout = this.text ?? ""
        }
        onExited: (exitCode, exitStatus) => {
            if (root._servicesStdout.trim().length > 0) {
                root._applyServicesPayload(root._servicesStdout)
            } else {
                root.refreshServices()
            }
        }
    }

    readonly property var filteredDesktopApps: {
        const all = AppSearch.list
        const q = root._effectiveAppSearch.trim().toLowerCase()
        const filtered = q.length === 0 ? all.slice() : all.filter(e =>
            (e.name && e.name.toLowerCase().includes(q)) ||
            (e.id && e.id.toLowerCase().includes(q)) ||
            (e.genericName && e.genericName.toLowerCase().includes(q)) ||
            (e.comment && e.comment.toLowerCase().includes(q))
        )
        const checkEnabled = (Autostart.entries?.length ?? 0) > 0 || (Autostart.externalLines?.length ?? 0) > 0
        const paired = filtered.map(app => {
            const label = String(app.name || app.id || "")
            return {
                app: app,
                on: checkEnabled && Autostart.isAppOn(app),
                sortKey: label.toLowerCase(),
                rawLabel: label
            }
        })
        paired.sort((a, b) => {
            if (a.on !== b.on)
                return a.on ? -1 : 1
            if (a.sortKey < b.sortKey) return -1
            if (a.sortKey > b.sortKey) return 1
            if (a.rawLabel < b.rawLabel) return -1
            if (a.rawLabel > b.rawLabel) return 1
            return 0
        })
        const out = new Array(paired.length)
        for (let i = 0; i < paired.length; ++i)
            out[i] = paired[i].app
        return out
    }

    function isBuiltInSystemStartupLine(lineObj): bool {
        const raw = String(lineObj?.raw ?? "")
        if (raw.length === 0)
            return true
        if (raw.includes("kbuildsycoca6") && raw.includes("XDG_MENU_PREFIX"))
            return true
        if (raw.includes("wl-paste") && (raw.includes("clipboard-store") || raw.includes("cliphist")))
            return true
        if (/polkit-(mate|gnome|kde)-authentication-agent|lxqt-policykit-agent|lxpolkit/.test(raw))
            return true
        return false
    }

    readonly property var externalStartupLines: {
        const rawLines = Autostart.externalLines ?? []
        return rawLines.filter(item => !root.isBuiltInSystemStartupLine(item))
    }

    readonly property var customServiceEntries: {
        const list = []
        const entries = Autostart.entries ?? []
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i]
            if (e && (e.type === "command" || e.type === "shell")) {
                list.push({
                    entryIndex: i,
                    command: String(e.command ?? e.raw ?? ""),
                    enabled: Boolean(e.enabled)
                })
            }
        }
        return list
    }

    readonly property var filteredUserServices: {
        const all = root.userServices ?? []
        const q = root._effectiveServiceSearch.trim().toLowerCase()
        return all.filter(svc => {
            if (!svc)
                return false
            if (!root.showAllServices && q.length === 0) {
                if (!svc.enabled && !svc.running && !svc.canToggle)
                    return false
            }
            if (q.length === 0)
                return true
            return String(svc.name ?? "").toLowerCase().includes(q)
                || String(svc.unit ?? "").toLowerCase().includes(q)
                || String(svc.description ?? "").toLowerCase().includes(q)
                || String(svc.unitFileState ?? "").toLowerCase().includes(q)
                || String(svc.activeState ?? "").toLowerCase().includes(q)
        })
    }

    readonly property var combinedServiceEntries: {
        const list = []
        const daemons = root.customServiceEntries ?? []
        for (let i = 0; i < daemons.length; i++) {
            list.push({ kind: "daemon", data: daemons[i] })
        }
        const svcs = root.filteredUserServices ?? []
        for (let j = 0; j < svcs.length; j++) {
            list.push({ kind: "systemd", data: svcs[j] })
        }
        return list
    }

    readonly property var slotLabelsByDesktopId: {
        void(AppLauncher._configRevision)
        void(AppLauncher.discoveredApps)
        const map = {}
        const defs = AppLauncher.primarySlotDefinitions()
        for (let i = 0; i < defs.length; i++) {
            const slot = defs[i]
            const sum = AppLauncher.selectedAppSummary(slot.id)
            const did = String(sum?.desktopId ?? "").trim()
            if (!did)
                continue
            const norm = did.endsWith(".desktop") ? did : `${did}.desktop`
            if (!map[norm])
                map[norm] = []
            map[norm].push({ id: slot.id, label: slot.label, title: slot.label, icon: slot.icon })
        }
        return map
    }

    SettingsCardSection {
        id: niriOnlyCard
        visible: !CompositorService.isNiri
        _preventBentoReparent: true
        expanded: true
        icon: "warning"
        title: Translation.tr("Niri only")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("App autostart works only while niri is the active compositor.")
            }
        }
    }

    GridLayout {
        id: autostartTwoColumnGrid
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        columns: 1
        columnSpacing: 14
        rowSpacing: SettingsMaterialPreset.pageSpacing
        uniformCellWidths: true

        SettingsCardSection {
            id: appsCard
            objectName: "autostartAppsCard"
            _preventBentoReparent: true
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            expanded: true
            icon: "apps"
            title: Translation.tr("Autostart Applications")

            SettingsGroup {
                ColumnLayout {
                    id: appsTopControls
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Toggle niri login apps. External entries must be edited in the startup file below.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "search"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: appSearchField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.maximumHeight: 44
                            wrapMode: TextEdit.NoWrap
                            placeholderText: Translation.tr("Filter installed applications...")
                            text: root.appSearchText
                            onTextChanged: root.appSearchText = text
                        }

                        RippleButton {
                            visible: root.appSearchText.length > 0
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                root.appSearchText = ""
                                appSearchField.text = ""
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                        }

                        Rectangle {
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSecondaryContainer
                            implicitHeight: 24
                            implicitWidth: activeAppsLabel.implicitWidth + 16
                            StyledText {
                                id: activeAppsLabel
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                                text: Translation.tr("%1 active").arg(
                                    Autostart.entries.filter(e => e.type === "app" && e.enabled).length
                                )
                            }
                        }
                    }
                }

                Rectangle {
                    id: appsListContainer
                    Layout.fillWidth: true
                    implicitHeight: (root._targetGridHeight > 0 && appsCard._effectiveCustomHeight <= 0)
                        ? Math.max(
                            180,
                            Math.round(
                                root._targetGridHeight
                                - appsCard.chromeImplicitHeight
                                - appsTopControls.implicitHeight
                                - SettingsMaterialPreset.groupPadding * 2
                                - SettingsMaterialPreset.groupSpacing
                            )
                        )
                        : 320
                    Layout.preferredHeight: implicitHeight
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    clip: true

                    ListView {
                        id: appsListView
                        objectName: "autostartAppsListView"
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.filteredDesktopApps

                        ScrollBar.vertical: ScrollBar {
                            objectName: "autostartAppsScrollBar"
                            policy: ScrollBar.AlwaysOff
                        }

                        delegate: Rectangle {
                            id: appRow
                            required property var modelData
                            readonly property string appId: modelData.id ?? ""
                            readonly property bool isEnabled: Autostart.isAppOn(modelData)
                            readonly property bool isExternal: Autostart.isAppExternal(modelData)
                            readonly property bool isPortable: appRow.appId.startsWith("alis-app-")
                            readonly property var linkedSlots: {
                                const target = String(appRow.appId ?? "").trim()
                                if (!target)
                                    return []
                                const norm = target.endsWith(".desktop") ? target : `${target}.desktop`
                                return root.slotLabelsByDesktopId[norm] ?? []
                            }
                            readonly property string resolvedIconPath: {
                                const raw = String(appRow.modelData.icon ?? "").trim()
                                if (!raw)
                                    return Quickshell.iconPath("application-x-executable", "image-missing")
                                if (raw.startsWith("file://"))
                                    return raw
                                if (raw.startsWith("/"))
                                    return "file://" + raw
                                return Quickshell.iconPath(raw, "image-missing")
                            }

                            width: appsListView.width
                            implicitHeight: 50
                            clip: true
                            radius: Appearance.rounding.small
                            color: isEnabled
                                ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.55)
                                : (rowHover.hovered ? Appearance.colors.colLayer2Hover : "transparent")

                            HoverHandler { id: rowHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                IconImage {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    source: appRow.resolvedIconPath
                                    implicitSize: 28
                                }

                                ColumnLayout {
                                    id: appInfoColumn
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.minimumWidth: 0
                                    clip: true
                                    spacing: 1

                                    RowLayout {
                                        id: appTitleBadgeRow
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        clip: true
                                        spacing: 6

                                        readonly property real fixedTagsWidth: (portableTagRect.visible ? portableTagRect.width + 6 : 0)
                                            + (extTagRect.visible ? extTagRect.width + 6 : 0)
                                        readonly property real minAppNameReserved: Math.min(
                                            autostartAppNameText.implicitWidth,
                                            Math.max(68, Math.floor(width * 0.45))
                                        )
                                        readonly property real maxRoleBadgeWidth: width > 0
                                            ? Math.max(48, Math.floor(width - minAppNameReserved - fixedTagsWidth - (defRoleBtn.visible ? 6 : 0)))
                                            : 120
                                        readonly property real effectiveRoleBadgeWidth: defRoleBtn.visible
                                            ? (width > 0 ? Math.min(defRoleBtn.naturalWidth, maxRoleBadgeWidth) : defRoleBtn.naturalWidth)
                                            : 0
                                        readonly property real totalBadgesReserved: fixedTagsWidth
                                            + (defRoleBtn.visible ? effectiveRoleBadgeWidth + 6 : 0)
                                        readonly property real availableAppNameWidth: width > 0
                                            ? Math.max(0, width - totalBadgesReserved)
                                            : autostartAppNameText.implicitWidth

                                        StyledText {
                                            id: autostartAppNameText
                                            objectName: "autostartAppName_" + appRow.appId
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.fillWidth: false
                                            Layout.minimumWidth: 0
                                            Layout.maximumWidth: appTitleBadgeRow.availableAppNameWidth
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.weight: appRow.isEnabled ? Font.DemiBold : Font.Normal
                                            text: appRow.modelData.name || appRow.appId
                                        }

                                        Rectangle {
                                            id: portableTagRect
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: appRow.isPortable
                                            radius: Appearance.rounding.full
                                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                                            implicitHeight: 18
                                            implicitWidth: portableTag.implicitWidth + 10
                                            StyledText {
                                                id: portableTag
                                                anchors.centerIn: parent
                                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                                color: Appearance.colors.colPrimary
                                                text: Translation.tr("Portable")
                                            }
                                        }

                                        RippleButton {
                                            id: defRoleBtn
                                            objectName: "autostartDefaultBadge_" + appRow.appId
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: appRow.linkedSlots.length > 0
                                            readonly property real naturalWidth: defRoleTag.implicitWidth + 10
                                            implicitHeight: 18
                                            implicitWidth: appTitleBadgeRow.effectiveRoleBadgeWidth
                                            width: appTitleBadgeRow.effectiveRoleBadgeWidth
                                            clip: true
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            onClicked: SettingsPageRegistry.navigateToKey("default-apps", "primary")
                                            contentItem: StyledText {
                                                id: defRoleTag
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 5
                                                anchors.rightMargin: 5
                                                anchors.verticalCenter: parent.verticalCenter
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                                color: Appearance.colors.colOnSecondaryContainer
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                                text: Translation.tr("Default: ") + (appRow.linkedSlots[0]?.title ?? "")
                                            }
                                            StyledToolTip {
                                                text: Translation.tr("Used as Default Application — click to open Default Apps")
                                            }
                                        }

                                        Rectangle {
                                            id: extTagRect
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: appRow.isExternal
                                            radius: Appearance.rounding.full
                                            color: Appearance.colors.colTertiaryContainer
                                            implicitHeight: 18
                                            implicitWidth: extTag.implicitWidth + 10
                                            StyledText {
                                                id: extTag
                                                anchors.centerIn: parent
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnTertiaryContainer
                                                text: Translation.tr("External")
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                        }
                                    }

                                    HoverMarqueeText {
                                        Layout.preferredWidth: appInfoColumn.width
                                        hovered: rowHover.hovered
                                        text: appRow.modelData.comment || appRow.modelData.genericName || appRow.appId
                                    }
                                }

                                RippleButton {
                                    visible: CompositorService.isNiri
                                    opacity: rowHover.hovered ? 1.0 : 0.0
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    Layout.fillWidth: false
                                    Layout.minimumWidth: implicitWidth
                                    Layout.preferredWidth: implicitWidth
                                    Layout.maximumWidth: implicitWidth
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer2
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    onClicked: {
                                        AppLauncher.prepareShortcutForApp(appRow.modelData)
                                        SettingsPageRegistry.navigateToKey("shortcuts", "")
                                    }
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "keyboard"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Configure keyboard shortcut in Shortcuts tab")
                                    }
                                }

                                StyledSwitch {
                                    Layout.fillWidth: false
                                    Layout.minimumWidth: implicitWidth
                                    Layout.preferredWidth: implicitWidth
                                    Layout.maximumWidth: implicitWidth
                                    checked: appRow.isEnabled
                                    enabled: !appRow.isExternal && Autostart.ready && !Autostart.busy
                                    onToggled: Autostart.setAppEnabled(appRow.appId, checked)
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsCardSection {
            id: servicesCard
            objectName: "autostartServicesCard"
            _preventBentoReparent: true
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            expanded: true
            icon: "rocket_launch"
            title: Translation.tr("Autostart Services")

            SettingsGroup {
                ColumnLayout {
                    id: servicesTopControls
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Monitor background user services and daemons, toggle autostart at login, or add a service.")
                    }

                    // Search & Filter Bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "search"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: serviceSearchField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.maximumHeight: 44
                            wrapMode: TextEdit.NoWrap
                            placeholderText: Translation.tr("Search services…")
                            text: root.serviceSearchText
                            onTextChanged: root.serviceSearchText = text
                        }

                        RippleButton {
                            implicitHeight: 28
                            implicitWidth: filterModeRow.implicitWidth + 16
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.showAllServices
                                ? Appearance.colors.colSecondaryContainer
                                : Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: root.showAllServices = !root.showAllServices

                            contentItem: Item {
                                implicitWidth: filterModeRow.implicitWidth
                                implicitHeight: filterModeRow.implicitHeight
                                RowLayout {
                                    id: filterModeRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: root.showAllServices ? "visibility" : "filter_list"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: root.showAllServices
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.showAllServices
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnLayer2
                                        text: root.showAllServices ? Translation.tr("All units") : Translation.tr("Manageable")
                                    }
                                }
                            }

                            StyledToolTip {
                                text: Translation.tr("Toggle between manageable user services and all static system units")
                            }
                        }

                        RippleButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            enabled: !root.loadingServices
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                Autostart.reload()
                                root.refreshServices()
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledToolTip {
                                text: Translation.tr("Refresh service states")
                            }
                        }
                    }

                    // Add Service or Startup Daemon Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialTextField {
                            id: serviceAddField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.maximumHeight: 44
                            wrapMode: TextEdit.NoWrap
                            placeholderText: Translation.tr("Add unit or command…")
                            font.family: Appearance.font.family.monospace
                            text: root.newServiceInput
                            onTextChanged: root.newServiceInput = text
                            Keys.onReturnPressed: root.addAutostartServiceOrDaemon()
                        }

                        RippleButton {
                            id: addSvcBtn
                            implicitHeight: 34
                            implicitWidth: addSvcRow.implicitWidth + 20
                            buttonRadius: Appearance.rounding.small
                            enabled: root.newServiceInput.trim().length > 0 && !servicesActionProc.running
                            colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: root.addAutostartServiceOrDaemon()

                            contentItem: Item {
                                implicitWidth: addSvcRow.implicitWidth
                                implicitHeight: addSvcRow.implicitHeight
                                RowLayout {
                                    id: addSvcRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "add"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: addSvcBtn.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        color: addSvcBtn.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                        font.weight: Font.Medium
                                        text: Translation.tr("Add")
                                    }
                                }
                            }
                        }
                    }

                    // Status / Error Banner
                    StyledText {
                        visible: root.serviceErrorMessage.length > 0 || root.serviceStatusMessage.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.serviceErrorMessage.length > 0
                            ? Appearance.colors.colError
                            : Appearance.colors.colPrimary
                        text: root.serviceErrorMessage.length > 0 ? root.serviceErrorMessage : root.serviceStatusMessage
                    }
                }

                // Services & Daemons List
                Rectangle {
                    id: servicesListContainer
                    Layout.fillWidth: true
                    implicitHeight: (root._targetGridHeight > 0 && servicesCard._effectiveCustomHeight <= 0)
                        ? Math.max(
                            180,
                            Math.round(
                                root._targetGridHeight
                                - servicesCard.chromeImplicitHeight
                                - servicesTopControls.implicitHeight
                                - SettingsMaterialPreset.groupPadding * 2
                                - SettingsMaterialPreset.groupSpacing
                            )
                        )
                        : 320
                    Layout.preferredHeight: implicitHeight
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    clip: true

                    ListView {
                        id: servicesListView
                        objectName: "autostartServicesListView"
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4
                        clip: true
                        cacheBuffer: 160
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.combinedServiceEntries

                        ScrollBar.vertical: ScrollBar {
                            objectName: "autostartServicesScrollBar"
                            policy: ScrollBar.AlwaysOff
                        }

                        delegate: Item {
                            id: combinedRow
                            required property var modelData
                            readonly property bool isDaemon: modelData?.kind === "daemon"
                            readonly property var itemData: modelData?.data ?? ({})
                            width: servicesListView.width
                            height: isDaemon ? 50 : 52

                            Rectangle {
                                id: daemonRow
                                visible: combinedRow.isDaemon
                                anchors.fill: parent
                                clip: true
                                radius: Appearance.rounding.small
                                color: Boolean(combinedRow.itemData.enabled)
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.55)
                                    : (daemonHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

                                HoverHandler { id: daemonHover; enabled: combinedRow.isDaemon }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    MaterialSymbol {
                                        text: "terminal"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Boolean(combinedRow.itemData.enabled)
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.minimumWidth: 0
                                        clip: true
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            text: String(combinedRow.itemData.command ?? "")
                                        }

                                        HoverMarqueeText {
                                            hovered: daemonHover.hovered
                                            text: Translation.tr("Startup command in niri 50-startup.kdl")
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 66
                                        Layout.minimumWidth: 66
                                        Layout.maximumWidth: 66
                                        implicitHeight: 20
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colSecondaryContainer
                                        StyledText {
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnSecondaryContainer
                                            text: Translation.tr("Daemon")
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        Layout.fillWidth: false
                                        Layout.minimumWidth: implicitWidth
                                        Layout.preferredWidth: implicitWidth
                                        Layout.maximumWidth: implicitWidth
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colErrorContainer
                                        onClicked: Autostart.removeEntry(combinedRow.itemData.entryIndex)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "delete"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colError
                                        }
                                    }

                                    StyledSwitch {
                                        Layout.fillWidth: false
                                        Layout.minimumWidth: implicitWidth
                                        Layout.preferredWidth: implicitWidth
                                        Layout.maximumWidth: implicitWidth
                                        checked: Boolean(combinedRow.itemData.enabled)
                                        enabled: Autostart.ready && !Autostart.busy
                                        onToggled: Autostart.setEntryEnabled(combinedRow.itemData.entryIndex, checked)
                                    }
                                }
                            }

                            Rectangle {
                                id: svcRow
                                visible: !combinedRow.isDaemon
                                readonly property bool isEnabled: Boolean(combinedRow.itemData.enabled)
                                readonly property bool isRunning: Boolean(combinedRow.itemData.running)
                                readonly property bool canToggle: Boolean(combinedRow.itemData.canToggle)

                                anchors.fill: parent
                                clip: true
                                radius: Appearance.rounding.small
                                color: isEnabled
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.55)
                                    : (svcHover.hovered ? Appearance.colors.colLayer2Hover : "transparent")

                                HoverHandler { id: svcHover; enabled: !combinedRow.isDaemon }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 10
                                        Layout.preferredHeight: 10
                                        radius: 5
                                        color: svcRow.isRunning
                                            ? Appearance.colors.colPrimary
                                            : (combinedRow.itemData.activeState === "failed"
                                                ? Appearance.colors.colError
                                                : Appearance.colors.colOutline)
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.minimumWidth: 0
                                        clip: true
                                        spacing: 1

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            clip: true
                                            spacing: 6

                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                                font.weight: (svcRow.isEnabled || svcRow.isRunning) ? Font.DemiBold : Font.Normal
                                                text: String(combinedRow.itemData.name || combinedRow.itemData.unit || "")
                                            }

                                            Rectangle {
                                                visible: !svcRow.canToggle
                                                radius: Appearance.rounding.full
                                                color: Appearance.colors.colLayer2
                                                implicitHeight: 18
                                                implicitWidth: staticBadge.implicitWidth + 10
                                                StyledText {
                                                    id: staticBadge
                                                    anchors.centerIn: parent
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colSubtext
                                                    text: String(combinedRow.itemData.unitFileState || "static")
                                                }
                                            }
                                        }

                                        HoverMarqueeText {
                                            hovered: svcHover.hovered
                                            text: `${combinedRow.itemData.description ?? ""} · ${combinedRow.itemData.unit ?? ""}`
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 66
                                        Layout.minimumWidth: 66
                                        Layout.maximumWidth: 66
                                        implicitHeight: 20
                                        radius: Appearance.rounding.full
                                        color: svcRow.isRunning
                                            ? Appearance.colors.colPrimaryContainer
                                            : (combinedRow.itemData.activeState === "failed"
                                                ? Appearance.colors.colErrorContainer
                                                : Appearance.colors.colLayer2)
                                        StyledText {
                                            id: stateBadgeText
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Medium
                                            color: svcRow.isRunning
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : (combinedRow.itemData.activeState === "failed"
                                                    ? Appearance.colors.colOnErrorContainer
                                                    : Appearance.colors.colSubtext)
                                            text: svcRow.isRunning
                                                ? Translation.tr("Running")
                                                : (combinedRow.itemData.activeState === "failed"
                                                    ? Translation.tr("Failed")
                                                    : Translation.tr("Stopped"))
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        Layout.fillWidth: false
                                        Layout.minimumWidth: implicitWidth
                                        Layout.preferredWidth: implicitWidth
                                        Layout.maximumWidth: implicitWidth
                                        buttonRadius: Appearance.rounding.full
                                        enabled: !servicesActionProc.running
                                        colBackground: Appearance.colors.colLayer2
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        onClicked: root.runServiceAction(
                                            combinedRow.itemData.unit,
                                            svcRow.isRunning ? "stop" : "start"
                                        )
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: svcRow.isRunning ? "stop" : "play_arrow"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: svcRow.isRunning
                                                ? Appearance.colors.colError
                                                : Appearance.colors.colPrimary
                                        }
                                        StyledToolTip {
                                            text: svcRow.isRunning
                                                ? Translation.tr("Stop service now")
                                                : Translation.tr("Start service now")
                                        }
                                    }

                                    StyledSwitch {
                                        Layout.fillWidth: false
                                        Layout.minimumWidth: implicitWidth
                                        Layout.preferredWidth: implicitWidth
                                        Layout.maximumWidth: implicitWidth
                                        checked: svcRow.isEnabled
                                        enabled: svcRow.canToggle && !servicesActionProc.running
                                        onToggled: root.setServiceAutostart(combinedRow.itemData.unit, checked)
                                        StyledToolTip {
                                            text: svcRow.canToggle
                                                ? (svcRow.isEnabled
                                                    ? Translation.tr("Enabled at login (click to disable autostart)")
                                                    : Translation.tr("Disabled at login (click to enable autostart)"))
                                                : Translation.tr("Managed automatically by systemd socket/target (%1)").arg(combinedRow.itemData.unitFileState)
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

    // Bottom helper bar: shown only when user has custom external startup entries in 50-startup.kdl
    SettingsCardSection {
        id: startupFileCard
        objectName: "autostartStartupFileCard"
        visible: CompositorService.isNiri && root.externalStartupLines.length > 0
        _preventBentoReparent: true
        expanded: true
        icon: "description"
        title: Translation.tr("Startup file")

        SettingsGroup {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideMiddle
                        maximumLineCount: 1
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Autostart.startupFilePath
                    }

                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: openFileRow.implicitWidth + 20
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: if (Autostart.startupFilePath.length > 0) Qt.openUrlExternally("file://" + Autostart.startupFilePath)

                        contentItem: Item {
                            implicitWidth: openFileRow.implicitWidth
                            implicitHeight: openFileRow.implicitHeight
                            RowLayout {
                                id: openFileRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "open_in_new"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Open file")
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: externalLinesFlickable
                    Layout.fillWidth: true
                    implicitHeight: Math.min(130, externalLinesColumn.implicitHeight)
                    Layout.preferredHeight: implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: externalLinesColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                        id: externalLinesColumn
                        width: externalLinesFlickable.width
                        spacing: 6

                        Repeater {
                            model: root.externalStartupLines
                            delegate: Rectangle {
                                id: extRow
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant

                                HoverHandler {
                                    id: extHover
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "terminal"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                    }

                                    HoverMarqueeText {
                                        hovered: extHover.hovered
                                        fontFamily: Appearance.font.family.monospace
                                        color: Appearance.colors.colOnLayer1
                                        text: String(extRow.modelData.raw ?? "")
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 66
                                        Layout.minimumWidth: 66
                                        Layout.maximumWidth: 66
                                        implicitHeight: 20
                                        radius: Appearance.rounding.full
                                        color: extRow.modelData.enabled
                                            ? Appearance.colors.colSecondaryContainer
                                            : Appearance.colors.colLayer1
                                        StyledText {
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Medium
                                            color: extRow.modelData.enabled
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colSubtext
                                            text: extRow.modelData.enabled
                                                ? Translation.tr("External")
                                                : Translation.tr("Disabled")
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
