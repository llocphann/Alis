pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings

ContentPage {
    id: root
    objectName: "applicationsSettings"
    settingsPageIndex: 17
    settingsPageName: Translation.tr("Applications")

    property var managedApps: []
    property bool busy: false
    property bool pickerActive: false
    property string statusError: ""
    property string searchQuery: ""
    readonly property string helperScript: Quickshell.shellPath("scripts/apps/manage-portable-apps.py")

    readonly property var filteredApps: {
        const q = root.searchQuery.trim().toLowerCase()
        const list = root.managedApps ?? []
        if (!q)
            return list
        return list.filter(item => {
            const name = String(item?.name ?? "").toLowerCase()
            const kind = String(item?.kind ?? "").toLowerCase()
            return name.includes(q) || kind.includes(q)
        })
    }

    function _releaseNativeDialogLock(): void {
        if (root.pickerActive) {
            root.pickerActive = false
            GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", false)
        }
    }

    function _applyResult(rawText: string): void {
        const trimmed = String(rawText ?? "").trim()
        if (!trimmed)
            return
        try {
            const payload = JSON.parse(trimmed)
            if (Array.isArray(payload.apps))
                root.managedApps = payload.apps
            if (payload.ok === false && payload.error)
                root.statusError = String(payload.error)
            else
                root.statusError = ""
            if (payload.added || payload.removed) {
                AppLauncher.refreshDiscovery()
                Autostart.refresh()
            }
        } catch (e) {
            root.statusError = String(e)
        }
    }

    function refreshList(forceAppLauncherDiscovery = false): void {
        if (runner.running)
            return
        if (forceAppLauncherDiscovery)
            AppLauncher.refreshDiscovery()
        root.busy = true
        runner.command = ["python3", "-B", root.helperScript, "list"]
        runner.running = true
    }

    function pickAndAddApplications(): void {
        if (runner.running)
            return
        root.busy = true
        root.statusError = ""
        root.pickerActive = true
        GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", true)
        runner.command = ["python3", "-B", root.helperScript, "pick-and-add"]
        runner.running = true
    }

    function addApplicationPaths(paths: var): void {
        if (runner.running || !paths || paths.length === 0)
            return
        root.busy = true
        root.statusError = ""
        const cmd = ["python3", "-B", root.helperScript, "add"]
        for (let i = 0; i < paths.length; ++i)
            cmd.push(String(paths[i]))
        runner.command = cmd
        runner.running = true
    }

    function removeApplication(appId: string): void {
        const target = String(appId ?? "").trim()
        if (runner.running || !target)
            return
        root.busy = true
        root.statusError = ""
        runner.command = ["python3", "-B", root.helperScript, "remove", target]
        runner.running = true
    }

    Component.onCompleted: {
        root.refreshList()
    }

    Component.onDestruction: {
        root._releaseNativeDialogLock()
    }

    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                root._releaseNativeDialogLock()
                root._applyResult(this.text)
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = String(this.text ?? "").trim()
                if (err.length > 0 && root.statusError.length === 0)
                    root.statusError = err
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.busy = false
            root._releaseNativeDialogLock()
        }
    }

    component BadgePill: Rectangle {
        id: pillRoot
        property string badgeText: ""
        property bool accent: false
        property bool secondary: false
        implicitHeight: 20
        implicitWidth: pillLabel.implicitWidth + 12
        radius: Appearance.rounding.full
        color: pillRoot.accent
            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
            : pillRoot.secondary
                ? ColorUtils.transparentize(Appearance.colors.colSecondary, 0.84)
                : Appearance.colors.colLayer2

        StyledText {
            id: pillLabel
            anchors.centerIn: parent
            text: pillRoot.badgeText
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color: pillRoot.accent
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer2
        }
    }

    component ActionIconButton: RippleButton {
        id: btnRoot
        property string iconName: "apps"
        property string tooltipText: ""
        property bool danger: false
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: btnRoot.danger
            ? ColorUtils.transparentize(Appearance.colors.colError, 0.88)
            : Appearance.colors.colLayer2
        colBackgroundHover: btnRoot.danger
            ? ColorUtils.transparentize(Appearance.colors.colError, 0.76)
            : Appearance.colors.colLayer2Hover

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: btnRoot.iconName
            iconSize: 18
            color: !btnRoot.enabled
                ? Appearance.colors.colSubtext
                : btnRoot.danger
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: btnRoot.tooltipText
        }
    }

    SettingsTaskNavigator {
        visible: !root.embedded
        showTabBar: false
        icon: "inventory_2"
        title: Translation.tr("Applications")
        description: ""
        summary: Translation.tr("AppImage · zsync · tar.gz · pkg.tar.zst")
    }

    SettingsCardSection {
        _preventBentoReparent: true
        Layout.fillWidth: true
        expanded: true
        icon: "inventory_2"
        title: Translation.tr("Portable Applications")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialTextField {
                objectName: "applicationsSearchField"
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                placeholderText: Translation.tr("Search applications…")
                text: root.searchQuery
                onTextChanged: root.searchQuery = text
            }

            ActionIconButton {
                objectName: "refreshApplicationsButton"
                iconName: "refresh"
                tooltipText: Translation.tr("Refresh list")
                enabled: !root.busy
                onClicked: root.refreshList(true)
            }

            RippleButton {
                id: addBtn
                objectName: "addApplicationsButton"
                enabled: !root.busy
                implicitHeight: 36
                implicitWidth: addBtnRow.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: root.pickAndAddApplications()

                contentItem: Item {
                    Row {
                        id: addBtnRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "add"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Add Applications")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.statusError.length > 0
            text: root.statusError
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            visible: (root.managedApps ?? []).length === 0
            implicitHeight: 84
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "inventory_2"
                    iconSize: 26
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.busy
                        ? Translation.tr("Processing application package…")
                        : Translation.tr("No portable applications added yet")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.filteredApps.length > 0
            spacing: 6

            Repeater {
                model: root.filteredApps

                delegate: Rectangle {
                    id: appRow
                    required property var modelData
                    required property int index
                    objectName: "portableAppCard_" + String(modelData?.id ?? index)
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    readonly property string desktopBaseId: "alis-app-" + String(appRow.modelData?.id ?? "")
                    readonly property var linkedSlots: {
                        void(AppLauncher._configRevision)
                        void(AppLauncher.discoveredApps)
                        return AppLauncher.defaultSlotsForDesktopId(appRow.desktopBaseId)
                    }
                    readonly property bool isAutostarted: CompositorService.isNiri && Autostart.isAppEnabled(appRow.desktopBaseId)

                    readonly property string iconFileUrl: {
                        const p = String(appRow.modelData?.iconPath ?? "").trim()
                        if (!p)
                            return ""
                        return p.startsWith("file://") ? p : ("file://" + p)
                    }

                    RowLayout {
                        id: rowLayout
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 10
                        }
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                id: appIconImg
                                anchors.fill: parent
                                source: appRow.iconFileUrl
                                sourceSize.width: 56
                                sourceSize.height: 56
                                fillMode: Image.PreserveAspectFit
                                visible: appRow.iconFileUrl.length > 0 && status === Image.Ready
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !appIconImg.visible
                                text: String(appRow.modelData?.kind ?? "") === "appimage" ? "deployed_code" : "folder_zip"
                                iconSize: 22
                                color: Appearance.colors.colPrimary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            StyledText {
                                text: String(appRow.modelData?.name ?? "")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            BadgePill {
                                readonly property string kindStr: String(appRow.modelData?.kind ?? "appimage")
                                badgeText: kindStr === "appimage" ? "AppImage" : kindStr
                                accent: kindStr === "appimage"
                                secondary: kindStr !== "appimage"
                            }

                            BadgePill {
                                visible: Boolean(appRow.modelData?.hasZsync)
                                badgeText: "zsync"
                                accent: true
                            }

                            BadgePill {
                                visible: appRow.linkedSlots.length > 0
                                badgeText: Translation.tr("Default: ") + (appRow.linkedSlots[0]?.title ?? "")
                                accent: true
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            ActionIconButton {
                                objectName: "portableAutostartBtn_" + String(appRow.modelData?.id ?? "")
                                visible: CompositorService.isNiri
                                iconName: "rocket_launch"
                                colBackground: appRow.isAutostarted
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                                    : Appearance.colors.colLayer2
                                tooltipText: appRow.isAutostarted
                                    ? Translation.tr("Autostart enabled (click to disable)")
                                    : Translation.tr("Enable Autostart at login")
                                onClicked: Autostart.setAppEnabled(appRow.desktopBaseId, !appRow.isAutostarted)
                            }

                            ActionIconButton {
                                objectName: "portableShortcutBtn_" + String(appRow.modelData?.id ?? "")
                                visible: CompositorService.isNiri
                                iconName: "keyboard"
                                tooltipText: Translation.tr("Configure keyboard shortcut in Shortcuts tab")
                                onClicked: {
                                    AppLauncher.prepareShortcutForCommand(
                                        String(appRow.modelData?.execPath ?? ""),
                                        String(appRow.modelData?.name ?? "")
                                    )
                                    SettingsPageRegistry.navigateToKey("shortcuts", "")
                                }
                            }

                            ActionIconButton {
                                objectName: "launchApplicationBtn_" + String(appRow.modelData?.id ?? "")
                                iconName: "play_arrow"
                                tooltipText: Translation.tr("Launch application")
                                enabled: Boolean(appRow.modelData?.installed ?? true)
                                onClicked: {
                                    const execPath = String(appRow.modelData?.execPath ?? "").trim()
                                    if (execPath)
                                        Quickshell.execDetached([execPath])
                                }
                            }

                            ActionIconButton {
                                objectName: "removeApplicationBtn_" + String(appRow.modelData?.id ?? "")
                                iconName: "delete"
                                danger: true
                                enabled: !root.busy
                                tooltipText: Translation.tr("Remove application")
                                onClicked: root.removeApplication(String(appRow.modelData?.id ?? ""))
                            }
                        }
                    }
                }
            }
        }
    }
}
