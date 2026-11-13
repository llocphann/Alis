pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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

    property bool _syncingManagedAppsFromService: false
    property var managedApps: AppLauncher.apps
    onManagedAppsChanged: {
        if (!root._syncingManagedAppsFromService && root.managedApps !== AppLauncher.apps) {
            AppLauncher.setManagedAppsManual(root.managedApps)
        }
    }

    property bool _localPickerLockHeld: false

    Connections {
        target: AppLauncher
        function onAppsChanged(): void {
            root._syncingManagedAppsFromService = true
            root.managedApps = AppLauncher.apps
            root._syncingManagedAppsFromService = false
        }
        function onBusyChanged(): void {
            if (!AppLauncher.busy && root._localPickerLockHeld) {
                root._localPickerLockHeld = false
                GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", false)
            }
        }
        function onProgressStageChanged(): void {
            if (AppLauncher.progressStage === "installing" && root._localPickerLockHeld) {
                root._localPickerLockHeld = false
                GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", false)
            }
        }
    }

    readonly property var apps: root.managedApps
    readonly property bool busy: AppLauncher.busy && (typeof AppLauncher.portableProcessRunning !== "boolean" || AppLauncher.portableProcessRunning)
    readonly property string busyAction: AppLauncher.busyAction
    readonly property string busyAppId: AppLauncher.busyAppId
    readonly property bool checkingUpdates: AppLauncher.checkingUpdates
    readonly property string updatingAppId: AppLauncher.updatingAppId
    readonly property int progressPercent: AppLauncher.progressPercent
    readonly property string progressDetail: AppLauncher.progressDetail
    readonly property string progressStage: AppLauncher.progressStage
    readonly property bool pickerActive: AppLauncher.pickerActive || root._localPickerLockHeld
    readonly property string statusError: AppLauncher.statusError
    readonly property string statusMessage: AppLauncher.statusMessage
    property string searchQuery: ""
    readonly property string helperScript: AppLauncher.portableManageScript
    readonly property int supportedAppsCount: (root.managedApps ?? []).filter(item => Boolean(item?.updateSupported || item?.hasZsync)).length
    readonly property int updatableAppsCount: (root.managedApps ?? []).filter(item => Boolean(item?.updateAvailable)).length

    readonly property var filteredApps: {
        const q = root.searchQuery.trim().toLowerCase()
        const list = root.managedApps ?? []
        if (!q)
            return list
        return list.filter(item => {
            const name = String(item?.name ?? "").toLowerCase()
            const kind = String(item?.kind ?? "").toLowerCase()
            const proto = String(item?.updateProtocol ?? "").toLowerCase()
            const ver = String(item?.version ?? "").toLowerCase()
            return name.includes(q) || kind.includes(q) || proto.includes(q) || ver.includes(q) || (q === "zsync" && Boolean(item?.hasZsync))
        })
    }

    function _recoverLegacyStalePickerBusy(): void {
        if (typeof AppLauncher._recoverStalePortableBusyIfIdle === "function") {
            AppLauncher._recoverStalePortableBusyIfIdle()
            return
        }
        if (AppLauncher.busy && AppLauncher.busyAction === "pick-and-add" && AppLauncher.pickerActive) {
            AppLauncher.pickerActive = false
            AppLauncher.busy = false
            AppLauncher.busyAction = ""
            AppLauncher.busyAppId = ""
            GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", false)
        }
    }

    function refreshList(forceAppLauncherDiscovery = false): void {
        root._recoverLegacyStalePickerBusy()
        AppLauncher.refreshList(forceAppLauncherDiscovery)
    }

    function checkForUpdates(appId = ""): void {
        root._recoverLegacyStalePickerBusy()
        AppLauncher.checkForUpdates(appId)
    }

    function updateApplication(appId: string): void {
        root._recoverLegacyStalePickerBusy()
        AppLauncher.updateApplication(appId)
    }

    function updateAllApplications(): void {
        root._recoverLegacyStalePickerBusy()
        AppLauncher.updateAllApplications()
    }

    function pickAndAddApplications(): void {
        root._recoverLegacyStalePickerBusy()
        if (typeof AppLauncher._setNativePickerDialogVisible === "function") {
            AppLauncher.pickAndAddApplications()
            return
        }
        if (AppLauncher.busy)
            return
        AppLauncher._manualAppsOverride = false
        root._localPickerLockHeld = true
        GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", true)
        AppLauncher._startPortableCommand(["pick-and-add"], "add")
    }

    function pickAndAddPortableApplications(): void {
        root.pickAndAddApplications()
    }

    function addApplicationPaths(paths: var): void {
        AppLauncher.addApplicationPaths(paths)
    }

    function removeApplication(appId: string): void {
        AppLauncher.removeApplication(appId)
    }

    function setUpdateSource(appId: string, source: string): void {
        AppLauncher.setUpdateSource(appId, source)
    }

    Component.onCompleted: {
        root._recoverLegacyStalePickerBusy()
        if (!AppLauncher.busy && !AppLauncher.portableAppsLoaded)
            root.refreshList()
    }

    Component.onDestruction: {
        if (root._localPickerLockHeld) {
            root._localPickerLockHeld = false
            GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", false)
        }
    }

    component BadgePill: Rectangle {
        id: pillRoot
        property string badgeText: ""
        property bool accent: false
        property bool secondary: false
        property real maxPillWidth: 0
        readonly property real naturalWidth: pillLabel.implicitWidth + 12
        implicitHeight: 20
        implicitWidth: pillRoot.maxPillWidth > 0
            ? Math.min(pillRoot.maxPillWidth, pillRoot.naturalWidth)
            : pillRoot.naturalWidth
        Layout.minimumWidth: pillRoot.maxPillWidth > 0 ? Math.min(48, pillRoot.naturalWidth) : pillRoot.naturalWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: pillRoot.maxPillWidth > 0 ? pillRoot.maxPillWidth : pillRoot.naturalWidth
        radius: Appearance.rounding.full
        clip: true
        color: pillRoot.accent
            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
            : pillRoot.secondary
                ? ColorUtils.transparentize(Appearance.colors.colSecondary, 0.84)
                : Appearance.colors.colLayer2

        HoverHandler {
            id: pillHover
        }

        StyledText {
            id: pillLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: pillRoot.badgeText
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            color: pillRoot.accent
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: pillHover.hovered && pillLabel.truncated
            text: pillRoot.badgeText
        }
    }

    component ActionIconButton: RippleButton {
        id: btnRoot
        property string iconName: "apps"
        property string tooltipText: ""
        property bool danger: false
        implicitWidth: 34
        implicitHeight: 34
        Layout.fillWidth: false
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
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
        summary: Translation.tr("AppImage · zsync · rsync · tar.gz · pkg.tar.zst")
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

            ActionIconButton {
                objectName: "checkPortableUpdatesButton"
                iconName: "sync"
                tooltipText: Translation.tr("Check for updates (zsync / rsync / portable)")
                enabled: !root.busy && (root.managedApps ?? []).length > 0
                onClicked: root.checkForUpdates()
            }

            RippleButton {
                id: updateAllBtn
                objectName: "updateAllApplicationsButton"
                visible: root.updatableAppsCount > 0
                enabled: !root.busy
                implicitHeight: 36
                implicitWidth: updateAllBtnRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.small
                colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                onClicked: root.updateAllApplications()

                contentItem: Item {
                    Row {
                        id: updateAllBtnRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "system_update_alt"
                            iconSize: 17
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Update (%1)").arg(root.updatableAppsCount)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
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

        Rectangle {
            id: progressCard
            objectName: "portableAppsProgressContainer"
            Layout.fillWidth: true
            visible: root.busy && (root.busyAction === "update" || root.busyAction === "check-updates" || root.progressStage === "installing")
            implicitHeight: progressCol.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65)

            ColumnLayout {
                id: progressCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                }
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: root.busyAction === "update" ? "downloading" : "sync"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        id: progressDetailLabel
                        objectName: "portableAppsProgressDetail"
                        Layout.fillWidth: true
                        text: root.progressDetail.length > 0
                            ? root.progressDetail
                            : (root.busyAction === "update"
                                ? Translation.tr("Updating portable application…")
                                : Translation.tr("Checking for updates…"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    StyledText {
                        id: progressPercentLabel
                        objectName: "portableAppsProgressPercentText"
                        visible: root.progressPercent >= 0
                        text: `${Math.max(0, Math.min(100, root.progressPercent))}%`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }

                Rectangle {
                    id: progressTrack
                    objectName: "portableAppsProgressBar"
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    clip: true

                    Rectangle {
                        id: progressFill
                        objectName: "portableAppsProgressFill"
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: {
                            const pct = root.progressPercent >= 0 ? Math.max(4, Math.min(100, root.progressPercent)) : 18
                            return Math.round(parent.width * (pct / 100.0))
                        }
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary

                        Behavior on width {
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            objectName: "portableAppsStatusMessage"
            Layout.fillWidth: true
            visible: !progressCard.visible && root.statusMessage.length > 0
            text: root.statusMessage
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        StyledText {
            objectName: "portableAppsStatusError"
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
                    readonly property string appIdStr: String(modelData?.id ?? "")
                    objectName: "portableAppCard_" + (appIdStr.length > 0 ? appIdStr : String(index))
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 48
                    clip: true
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: appRow.isThisAppUpdating
                        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.55)
                        : Appearance.colors.colLayer0Border

                    readonly property string desktopBaseId: "alis-app-" + appRow.appIdStr
                    readonly property var linkedSlots: {
                        void(AppLauncher._configRevision)
                        void(AppLauncher.discoveredApps)
                        return AppLauncher.defaultSlotsForDesktopId(appRow.desktopBaseId)
                    }
                    readonly property bool isAutostarted: CompositorService.isNiri && Autostart.isAppEnabled(appRow.desktopBaseId)
                    readonly property bool isUpdateSupported: Boolean(appRow.modelData?.hasZsync) || Boolean(appRow.modelData?.updateSupported) || Boolean(appRow.modelData?.updateAvailable)
                    readonly property bool hasUpdateAvailable: Boolean(appRow.modelData?.updateAvailable)
                    readonly property bool isThisAppUpdating: root.busy && root.busyAction === "update"
                        && (root.updatingAppId === appRow.appIdStr
                            || root.busyAppId === appRow.appIdStr
                            || (root.updatingAppId === "__all__" && appRow.hasUpdateAvailable))
                    readonly property string protocolLabel: {
                        const p = String(appRow.modelData?.updateProtocol ?? "").trim()
                        if (p === "rsync")
                            return "rsync"
                        if (p === "zsync" || Boolean(appRow.modelData?.hasZsync))
                            return "zsync"
                        if (p.length > 0)
                            return "update"
                        return "zsync"
                    }
                    readonly property real rowBtnSize: 28

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

                        Row {
                            id: titleTagsRow
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6
                            clip: true

                            readonly property real fixedPillsWidth: (kindPill.visible ? kindPill.naturalWidth + 6 : 0)
                                + (zsyncPill.visible ? zsyncPill.naturalWidth + 6 : 0)
                            readonly property real minNameReserved: Math.min(
                                appNameLabel.implicitWidth,
                                Math.max(68, Math.floor(width * 0.42))
                            )
                            readonly property real maxDefaultSlotPillWidth: width > 0
                                ? Math.max(48, Math.floor(width - minNameReserved - fixedPillsWidth - (defaultSlotPill.visible ? 6 : 0)))
                                : 120
                            readonly property real effectiveDefaultSlotPillWidth: defaultSlotPill.visible
                                ? (width > 0 ? Math.min(defaultSlotPill.naturalWidth, maxDefaultSlotPillWidth) : defaultSlotPill.naturalWidth)
                                : 0
                            readonly property real totalBadgesReserved: fixedPillsWidth
                                + (defaultSlotPill.visible ? effectiveDefaultSlotPillWidth + 6 : 0)
                            readonly property real availableNameWidth: width > 0
                                ? Math.max(0, width - totalBadgesReserved)
                                : appNameLabel.implicitWidth

                            StyledText {
                                id: appNameLabel
                                objectName: "portableAppName_" + String(appRow.modelData?.id ?? appRow.index)
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, titleTagsRow.availableNameWidth)
                                verticalAlignment: Text.AlignVCenter
                                text: String(appRow.modelData?.name ?? "")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            BadgePill {
                                id: kindPill
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property string kindStr: String(appRow.modelData?.kind ?? "appimage")
                                badgeText: kindStr === "appimage" ? "AppImage" : kindStr
                                accent: kindStr === "appimage"
                                secondary: kindStr !== "appimage"
                            }

                            BadgePill {
                                id: zsyncPill
                                objectName: "portableUpdateBadge_" + String(appRow.modelData?.id ?? appRow.index)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: appRow.isUpdateSupported || appRow.isThisAppUpdating
                                badgeText: {
                                    if (appRow.isThisAppUpdating) {
                                        const pct = root.progressPercent >= 0 ? `${Math.max(0, Math.min(100, root.progressPercent))}%` : "…"
                                        return `${appRow.protocolLabel} · ${pct}`
                                    }
                                    if (appRow.hasUpdateAvailable) {
                                        const lv = String(appRow.modelData?.latestVersion ?? "").trim()
                                        return lv.length > 0 ? `${appRow.protocolLabel} · ↑${lv}` : `${appRow.protocolLabel} · ↑`
                                    }
                                    return appRow.protocolLabel
                                }
                                accent: true
                            }

                            BadgePill {
                                id: defaultSlotPill
                                objectName: "portableDefaultBadge_" + String(appRow.modelData?.id ?? appRow.index)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: appRow.linkedSlots.length > 0
                                badgeText: Translation.tr("Default: ") + (appRow.linkedSlots[0]?.title ?? "")
                                accent: true
                                maxPillWidth: titleTagsRow.maxDefaultSlotPillWidth
                                width: titleTagsRow.effectiveDefaultSlotPillWidth
                            }
                        }

                        RowLayout {
                            id: actionsRow
                            readonly property int buttonCount: CompositorService.isNiri ? 3 : 2
                            implicitWidth: (appRow.rowBtnSize * buttonCount) + (actionsRow.spacing * (buttonCount - 1))
                            Layout.fillWidth: false
                            Layout.minimumWidth: implicitWidth
                            Layout.preferredWidth: implicitWidth
                            Layout.maximumWidth: implicitWidth
                            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                            spacing: 4

                            Item {
                                width: appRow.rowBtnSize
                                height: appRow.rowBtnSize
                                implicitWidth: appRow.rowBtnSize
                                implicitHeight: appRow.rowBtnSize
                                Layout.preferredWidth: appRow.rowBtnSize
                                Layout.preferredHeight: appRow.rowBtnSize
                                Layout.minimumWidth: appRow.rowBtnSize
                                Layout.maximumWidth: appRow.rowBtnSize
                                Layout.fillWidth: false
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter

                                ActionIconButton {
                                    objectName: "portableUpdateBtn_" + appRow.appIdStr
                                    anchors.fill: parent
                                    visible: appRow.isUpdateSupported
                                    implicitWidth: appRow.rowBtnSize
                                    implicitHeight: appRow.rowBtnSize
                                    enabled: !root.busy && appRow.isUpdateSupported
                                    iconName: appRow.hasUpdateAvailable ? "download" : "sync"
                                    colBackground: appRow.hasUpdateAvailable
                                        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
                                        : Appearance.colors.colLayer2
                                    tooltipText: {
                                        const curVer = String(appRow.modelData?.version ?? "").trim()
                                        const latVer = String(appRow.modelData?.latestVersion ?? "").trim()
                                        const errStr = String(appRow.modelData?.updateError ?? "").trim()
                                        if (errStr.length > 0)
                                            return Translation.tr("Update check error: %1").arg(errStr)
                                        if (appRow.hasUpdateAvailable)
                                            return Translation.tr("Update available (%1 → %2) — click to update").arg(curVer || "?").arg(latVer || "latest")
                                        if (curVer.length > 0)
                                            return Translation.tr("Check or apply update (%1 · v%2)").arg(appRow.protocolLabel).arg(curVer)
                                        return Translation.tr("Check or apply update (%1)").arg(appRow.protocolLabel)
                                    }
                                    onClicked: root.updateApplication(appRow.appIdStr)
                                }
                            }

                            Item {
                                visible: CompositorService.isNiri
                                width: appRow.rowBtnSize
                                height: appRow.rowBtnSize
                                implicitWidth: appRow.rowBtnSize
                                implicitHeight: appRow.rowBtnSize
                                Layout.preferredWidth: appRow.rowBtnSize
                                Layout.preferredHeight: appRow.rowBtnSize
                                Layout.minimumWidth: appRow.rowBtnSize
                                Layout.maximumWidth: appRow.rowBtnSize
                                Layout.fillWidth: false
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter

                                ActionIconButton {
                                    objectName: "portableAutostartBtn_" + appRow.appIdStr
                                    anchors.fill: parent
                                    visible: CompositorService.isNiri
                                    implicitWidth: appRow.rowBtnSize
                                    implicitHeight: appRow.rowBtnSize
                                    iconName: "rocket_launch"
                                    colBackground: appRow.isAutostarted
                                        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                                        : Appearance.colors.colLayer2
                                    tooltipText: appRow.isAutostarted
                                        ? Translation.tr("Autostart enabled (click to disable)")
                                        : Translation.tr("Enable Autostart at login")
                                    onClicked: Autostart.setAppEnabled(appRow.desktopBaseId, !appRow.isAutostarted)
                                }
                            }

                            Item {
                                width: appRow.rowBtnSize
                                height: appRow.rowBtnSize
                                implicitWidth: appRow.rowBtnSize
                                implicitHeight: appRow.rowBtnSize
                                Layout.preferredWidth: appRow.rowBtnSize
                                Layout.preferredHeight: appRow.rowBtnSize
                                Layout.minimumWidth: appRow.rowBtnSize
                                Layout.maximumWidth: appRow.rowBtnSize
                                Layout.fillWidth: false
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter

                                ActionIconButton {
                                    objectName: "removeApplicationBtn_" + appRow.appIdStr
                                    anchors.fill: parent
                                    implicitWidth: appRow.rowBtnSize
                                    implicitHeight: appRow.rowBtnSize
                                    iconName: "delete"
                                    danger: true
                                    enabled: !root.busy
                                    tooltipText: Translation.tr("Remove application")
                                    onClicked: root.removeApplication(appRow.appIdStr)
                                }
                            }
                        }
                    }

                    Rectangle {
                        objectName: "portableAppRowProgressBar_" + appRow.appIdStr
                        visible: appRow.isThisAppUpdating
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 3
                        color: Appearance.colors.colLayer2

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: {
                                const pct = root.progressPercent >= 0 ? Math.max(4, Math.min(100, root.progressPercent)) : 18
                                return Math.round(parent.width * (pct / 100.0))
                            }
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
