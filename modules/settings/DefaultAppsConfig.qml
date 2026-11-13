pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings

ContentPage {
    id: root
    objectName: "defaultAppsSettings"
    settingsPageIndex: 39
    settingsPageName: Translation.tr("Applications")

    property string activeSection: "primary"
    property string openPickerSlot: ""
    property string openCustomSlot: ""

    onActiveSectionChanged: {
        if (root.activeSection === "defaults" || root.activeSection === "portable") {
            root.activeSection = "primary"
        }
    }

    Component.onCompleted: {
        AppLauncher.refreshDiscovery()
    }

    function handleEscape(): bool {
        if (root.openPickerSlot.length > 0) {
            root.openPickerSlot = ""
            return true
        }
        return false
    }

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        if (label.includes("autostart") || label.includes("startup") || label.includes("command") || label.includes("service")) {
            root.activeSection = "autostart"
            return true
        }
        if (label.includes("utilit") || label.includes("network") || label.includes("bluetooth")
                || label.includes("volume") || label.includes("task") || label.includes("account")
                || label.includes("user")) {
            root.activeSection = "utilities"
            return true
        }
        root.activeSection = "primary"
        if (label.includes("terminal"))
            root.openPickerSlot = "terminal"
        else if (label.includes("browser"))
            root.openPickerSlot = "browser"
        else if (label.includes("editor"))
            root.openPickerSlot = "editor"
        else if (label.includes("file"))
            root.openPickerSlot = "fileManager"
        else if (label.includes("pdf"))
            root.openPickerSlot = "pdfViewer"
        else if (label.includes("office") || label.includes("docx") || label.includes("word"))
            root.openPickerSlot = "officeSuite"
        else if (label.includes("html"))
            root.openPickerSlot = "htmlViewer"
        else if (label.includes("image") || label.includes("photo") || label.includes("picture") || label.includes("png") || label.includes("jpg"))
            root.openPickerSlot = "imageViewer"
        else if (label.includes("video") || label.includes("movie") || label.includes("mp4") || label.includes("mkv"))
            root.openPickerSlot = "videoPlayer"
        else if (label.includes("audio") || label.includes("music") || label.includes("mp3") || label.includes("flac"))
            root.openPickerSlot = "audioPlayer"
        else if (label.includes("archive") || label.includes("zip") || label.includes("rar") || label.includes("7z"))
            root.openPickerSlot = "archiveManager"
        return true
    }

    component AppIconView: Item {
        id: iconRoot
        property string iconName: "apps"
        property string fallbackSymbol: "apps"
        property real iconSize: 22
        implicitWidth: iconSize
        implicitHeight: iconSize

        readonly property string resolvedPath: {
            const raw = String(iconRoot.iconName ?? "").trim()
            if (!raw)
                return ""
            if (raw.startsWith("file://"))
                return raw
            if (raw.startsWith("/"))
                return "file://" + raw
            return Quickshell.iconPath(raw, true) ?? ""
        }

        IconImage {
            id: sysIcon
            anchors.fill: parent
            visible: iconRoot.resolvedPath.length > 0 && status === Image.Ready
            source: iconRoot.resolvedPath
            implicitSize: iconRoot.iconSize
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: !sysIcon.visible
            text: iconRoot.fallbackSymbol || "apps"
            iconSize: iconRoot.iconSize - 2
            color: Appearance.colors.colPrimary
        }
    }

    component SourceBadgePill: Rectangle {
        id: badgeRoot
        property string badgeText: "Native"
        property bool available: true
        property bool isFlathub: badgeText.toLowerCase().includes("flathub")
        property bool isFlatpak: badgeRoot.badgeText.toLowerCase().includes("flatpak")
        readonly property real naturalWidth: badgeLabel.implicitWidth + 12
        implicitHeight: 20
        implicitWidth: naturalWidth
        Layout.fillWidth: false
        Layout.minimumWidth: Math.min(naturalWidth, 48)
        Layout.preferredWidth: naturalWidth
        Layout.maximumWidth: naturalWidth
        clip: true
        radius: Appearance.rounding.full
        color: !badgeRoot.available
            ? ColorUtils.transparentize(Appearance.colors.colError, 0.84)
            : badgeRoot.isFlathub
                ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                : badgeRoot.isFlatpak
                    ? ColorUtils.transparentize(Appearance.colors.colSecondary, 0.84)
                    : Appearance.colors.colLayer2

        StyledText {
            id: badgeLabel
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                right: parent.right
                leftMargin: 6
                rightMargin: 6
            }
            horizontalAlignment: Text.AlignHCenter
            text: badgeRoot.badgeText
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            color: !badgeRoot.available
                ? Appearance.colors.colError
                : badgeRoot.isFlathub
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer2
        }
    }

    component SlotIconButton: RippleButton {
        id: btnRoot
        property string iconName: "apps"
        property string tooltipText: ""
        property bool activeState: false
        implicitWidth: 30
        implicitHeight: 30
        Layout.fillWidth: false
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        buttonRadius: Appearance.rounding.full
        colBackground: btnRoot.activeState
            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
            : Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: btnRoot.iconName
            iconSize: 17
            color: !btnRoot.enabled
                ? Appearance.colors.colSubtext
                : btnRoot.activeState
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: btnRoot.tooltipText
        }
    }

    component DiscoveryHeaderBar: RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: AppLauncher.discovering
                ? Translation.tr("Scanning installed applications…")
                : Translation.tr("%1 installed applications").arg((AppLauncher.discoveredApps ?? []).length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        SlotIconButton {
            objectName: "defaultAppsRefreshButton"
            iconName: "refresh"
            tooltipText: Translation.tr("Refresh apps")
            enabled: !AppLauncher.discovering
            onClicked: AppLauncher.refreshDiscovery()
        }
    }

    component DefaultAppSlotCard: SettingsGroup {
        id: slotCard
        required property var slotData
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignTop
        clip: true
        readonly property string slotId: String(slotData?.id ?? "")
        readonly property int _rev: AppLauncher._configRevision
        readonly property var summary: {
            void(_rev)
            return AppLauncher.selectedAppSummary(slotId)
        }
        readonly property var xdgStatus: {
            void(_rev)
            return AppLauncher.xdgStatusFor(slotId)
        }
        property bool pickerOpen: root.openPickerSlot === slotId
        property bool customOpen: root.openCustomSlot === slotId || Boolean(summary?.isCustom)
        property string searchQuery: ""
        property bool showAllApps: false
        property int highlightedIndex: 0

        readonly property var candidates: {
            void(_rev)
            return AppLauncher.candidatesForSlot(slotId, searchQuery, showAllApps)
        }

        onCandidatesChanged: {
            if (highlightedIndex >= candidates.length)
                highlightedIndex = Math.max(0, candidates.length - 1)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8

            MaterialSymbol {
                Layout.fillWidth: false
                text: slotCard.slotData?.icon ?? "apps"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: slotCard.slotData?.label ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Rectangle {
            objectName: "defaultAppCurrent_" + slotCard.slotId
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: currentRow.implicitHeight + 14
            clip: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: (slotCard.summary?.installed ?? true)
                ? Appearance.colors.colLayer0Border
                : Appearance.colors.colError

            RowLayout {
                id: currentRow
                anchors {
                    fill: parent
                    margins: 7
                }
                spacing: 10

                AppIconView {
                    Layout.fillWidth: false
                    Layout.minimumWidth: 24
                    Layout.preferredWidth: 24
                    Layout.maximumWidth: 24
                    Layout.alignment: Qt.AlignVCenter
                    iconName: slotCard.summary?.icon ?? (slotCard.slotData?.icon ?? "apps")
                    fallbackSymbol: slotCard.slotData?.icon ?? "apps"
                    iconSize: 24
                }

                ColumnLayout {
                    id: currentInfoCol
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignVCenter
                    clip: true
                    spacing: 1

                    Row {
                        id: titleBadgeRow
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        clip: true
                        spacing: 6

                        readonly property real otherBadgesWidth: (portableBadge.visible ? portableBadge.width + 6 : 0)
                            + (autostartBadge.visible ? autostartBadge.width + 6 : 0)
                            + (xdgStatusIcon.visible ? xdgStatusIcon.width + 6 : 0)
                        readonly property real minNameReserved: Math.min(
                            appNameText.implicitWidth,
                            Math.max(48, Math.floor(width * 0.42))
                        )
                        readonly property real maxSourceBadgeWidth: width > 0
                            ? Math.max(36, Math.floor(width - minNameReserved - otherBadgesWidth - (sourceBadge.visible ? 6 : 0)))
                            : 96
                        readonly property real effectiveSourceBadgeWidth: sourceBadge.visible
                            ? (width > 0 ? Math.min(sourceBadge.naturalWidth, maxSourceBadgeWidth) : sourceBadge.naturalWidth)
                            : 0
                        readonly property real badgesReservedWidth: (sourceBadge.visible ? effectiveSourceBadgeWidth + 6 : 0)
                            + otherBadgesWidth
                        readonly property real availableNameWidth: width > 0
                            ? Math.max(0, width - badgesReservedWidth)
                            : appNameText.implicitWidth

                        StyledText {
                            id: appNameText
                            objectName: "defaultAppName_" + slotCard.slotId
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, titleBadgeRow.availableNameWidth)
                            text: slotCard.summary?.name ?? ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        SourceBadgePill {
                            id: sourceBadge
                            objectName: "defaultAppBadge_" + slotCard.slotId
                            anchors.verticalCenter: parent.verticalCenter
                            width: titleBadgeRow.effectiveSourceBadgeWidth
                            badgeText: slotCard.summary?.sourceBadge ?? "Native"
                            available: Boolean(slotCard.summary?.installed ?? true)
                        }

                        Rectangle {
                            id: portableBadge
                            anchors.verticalCenter: parent.verticalCenter
                            visible: String(slotCard.summary?.desktopId ?? "").startsWith("alis-app-")
                            implicitHeight: 20
                            implicitWidth: portableBadgeLabel.implicitWidth + 12
                            radius: Appearance.rounding.full
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                            StyledText {
                                id: portableBadgeLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Portable")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }

                        RippleButton {
                            id: autostartBadge
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property string cleanDesktopId: String(slotCard.summary?.desktopId ?? "").replace(/\.desktop$/i, "")
                            readonly property bool compactMode: (appNameText.implicitWidth + sourceBadge.naturalWidth) > 150
                            visible: CompositorService.isNiri && cleanDesktopId.length > 0 && Autostart.isAppEnabled(cleanDesktopId)
                            implicitHeight: 20
                            implicitWidth: autostartBadgeRow.implicitWidth + (compactMode ? 8 : 10)
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: root.activeSection = "autostart"
                            contentItem: Item {
                                implicitWidth: autostartBadgeRow.implicitWidth
                                implicitHeight: autostartBadgeRow.implicitHeight
                                RowLayout {
                                    id: autostartBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 3
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "rocket_launch"
                                        iconSize: 11
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        visible: !autostartBadge.compactMode
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: Translation.tr("Autostart")
                                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Enabled in Autostart — click to view Autostart settings")
                            }
                        }

                        MaterialSymbol {
                            id: xdgStatusIcon
                            objectName: "defaultAppXdgStatus_" + slotCard.slotId
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Boolean(slotCard.xdgStatus.supported && slotCard.xdgStatus.synced)
                            text: "verified"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: {
                            const cmd = String(slotCard.summary?.command ?? "")
                            if (!(slotCard.summary?.installed ?? true))
                                return Translation.tr("Unavailable: %1").arg(cmd)
                            return cmd
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: (slotCard.summary?.installed ?? true)
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colError
                        elide: Text.ElideMiddle
                        maximumLineCount: 1
                    }
                }

                RowLayout {
                    id: slotActionsRow
                    Layout.fillWidth: false
                    Layout.minimumWidth: implicitWidth
                    Layout.preferredWidth: implicitWidth
                    Layout.maximumWidth: implicitWidth
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    spacing: 5

                    SlotIconButton {
                        objectName: "defaultAppChooseBtn_" + slotCard.slotId
                        iconName: slotCard.pickerOpen ? "expand_less" : "apps"
                        activeState: slotCard.pickerOpen
                        tooltipText: slotCard.pickerOpen ? Translation.tr("Close list") : Translation.tr("Choose app")
                        onClicked: {
                            root.openPickerSlot = slotCard.pickerOpen ? "" : slotCard.slotId
                        }
                    }

                    SlotIconButton {
                        objectName: "defaultAppCustomBtn_" + slotCard.slotId
                        iconName: "edit"
                        activeState: slotCard.customOpen
                        tooltipText: Translation.tr("Custom command")
                        onClicked: {
                            root.openCustomSlot = (root.openCustomSlot === slotCard.slotId) ? "" : slotCard.slotId
                        }
                    }

                    SlotIconButton {
                        objectName: "defaultAppShortcutBtn_" + slotCard.slotId
                        visible: CompositorService.isNiri
                        iconName: "keyboard"
                        tooltipText: Translation.tr("Configure keyboard shortcut in Shortcuts tab")
                        onClicked: {
                            if (["terminal", "browser", "fileManager", "editor"].indexOf(slotCard.slotId) !== -1) {
                                AppLauncher.prepareShortcutForSlot(slotCard.slotId)
                            } else {
                                AppLauncher.prepareShortcutForCommand(
                                    String(slotCard.summary?.command ?? ""),
                                    String(slotCard.summary?.name ?? slotCard.slotData?.label ?? "")
                                )
                            }
                            SettingsPageRegistry.navigateToKey("shortcuts", "")
                        }
                    }

                    SlotIconButton {
                        objectName: "defaultAppSyncXdgBtn_" + slotCard.slotId
                        visible: Boolean(slotCard.xdgStatus.supported)
                        enabled: Boolean(slotCard.xdgStatus.canApply)
                        iconName: slotCard.xdgStatus.synced ? "published_with_changes" : "task_alt"
                        activeState: Boolean(slotCard.xdgStatus.synced)
                        tooltipText: slotCard.xdgStatus.synced
                            ? Translation.tr("Re-apply XDG default")
                            : Translation.tr("Apply as system default")
                        onClicked: AppLauncher.syncSystemDefault(slotCard.slotId)
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: String(slotCard.xdgStatus.errorText ?? "").length > 0
            text: slotCard.xdgStatus.errorText ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: slotCard.pickerOpen
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                MaterialTextField {
                    id: searchInput
                    objectName: "defaultAppSearch_" + slotCard.slotId
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    placeholderText: Translation.tr("Search installed applications…")
                    text: slotCard.searchQuery
                    onTextChanged: {
                        slotCard.searchQuery = text
                        slotCard.highlightedIndex = 0
                    }
                    Keys.onDownPressed: event => {
                        if (slotCard.candidates.length > 0) {
                            slotCard.highlightedIndex = Math.min(slotCard.candidates.length - 1, slotCard.highlightedIndex + 1)
                        }
                        event.accepted = true
                    }
                    Keys.onUpPressed: event => {
                        if (slotCard.candidates.length > 0) {
                            slotCard.highlightedIndex = Math.max(0, slotCard.highlightedIndex - 1)
                        }
                        event.accepted = true
                    }
                    Keys.onReturnPressed: event => {
                        if (slotCard.candidates.length > 0 && slotCard.highlightedIndex >= 0 && slotCard.highlightedIndex < slotCard.candidates.length) {
                            AppLauncher.selectDiscoveredApp(slotCard.slotId, slotCard.candidates[slotCard.highlightedIndex])
                            root.openPickerSlot = ""
                        }
                        event.accepted = true
                    }
                    Keys.onEscapePressed: event => {
                        root.openPickerSlot = ""
                        event.accepted = true
                    }
                }

                SlotIconButton {
                    objectName: "defaultAppShowAll_" + slotCard.slotId
                    iconName: slotCard.showAllApps ? "filter_alt_off" : "filter_alt"
                    activeState: slotCard.showAllApps
                    tooltipText: slotCard.showAllApps ? Translation.tr("Category only") : Translation.tr("Show all apps")
                    onClicked: slotCard.showAllApps = !slotCard.showAllApps
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: slotCard.candidates.length === 0
                text: AppLauncher.discovering
                    ? Translation.tr("Scanning installed applications…")
                    : Translation.tr("No matching applications found.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 4

                Repeater {
                    model: slotCard.candidates

                    delegate: RippleButton {
                        id: candidateRow
                        required property int index
                        required property var modelData
                        objectName: "defaultAppOption_" + slotCard.slotId + "_" + String(modelData.identityKey ?? index)
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 42
                        clip: true
                        buttonRadius: Appearance.rounding.small
                        readonly property bool isCurrent: String(slotCard.summary?.identityKey ?? "") === String(modelData.identityKey ?? "")
                            || (String(slotCard.summary?.identityKey ?? "").length === 0 && String(slotCard.summary?.desktopId ?? "") === String(modelData.desktopId ?? ""))
                        readonly property bool isHighlighted: index === slotCard.highlightedIndex
                        colBackground: isCurrent
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86)
                            : isHighlighted
                                ? Appearance.colors.colLayer1Hover
                                : Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: {
                            AppLauncher.selectDiscoveredApp(slotCard.slotId, modelData)
                            root.openPickerSlot = ""
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 10
                            }
                            spacing: 10

                            AppIconView {
                                Layout.fillWidth: false
                                Layout.minimumWidth: 20
                                Layout.preferredWidth: 20
                                Layout.maximumWidth: 20
                                Layout.alignment: Qt.AlignVCenter
                                iconName: candidateRow.modelData.icon || (slotCard.slotData?.icon ?? "apps")
                                fallbackSymbol: slotCard.slotData?.icon ?? "apps"
                                iconSize: 20
                            }

                            ColumnLayout {
                                id: candidateInfoCol
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignVCenter
                                clip: true
                                spacing: 1

                                Row {
                                    id: candidateTitleRow
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    clip: true
                                    spacing: 6

                                    readonly property real maxBadgeWidth: Math.max(48, Math.floor(width * 0.48))
                                    readonly property real effectiveBadgeWidth: width > 0
                                        ? Math.min(candidateSourceBadge.naturalWidth, maxBadgeWidth)
                                        : candidateSourceBadge.naturalWidth
                                    readonly property real availableNameWidth: width > 0
                                        ? Math.max(0, width - (effectiveBadgeWidth + 6))
                                        : candidateNameText.implicitWidth

                                    StyledText {
                                        id: candidateNameText
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, candidateTitleRow.availableNameWidth)
                                        text: candidateRow.modelData.name ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: candidateRow.isCurrent ? Font.DemiBold : Font.Normal
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    SourceBadgePill {
                                        id: candidateSourceBadge
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: candidateTitleRow.effectiveBadgeWidth
                                        badgeText: candidateRow.modelData.sourceBadge ?? "Native"
                                        available: true
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: candidateRow.modelData.exec ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                }
                            }

                            MaterialSymbol {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignVCenter
                                visible: candidateRow.isCurrent
                                text: "check_circle"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: slotCard.customOpen
            spacing: 6

            MaterialTextField {
                id: customCmdField
                objectName: "defaultAppCustomInput_" + slotCard.slotId
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: slotCard.slotData?.placeholder ?? ""
                text: slotCard.summary?.command ?? ""
                onAccepted: {
                    AppLauncher.setCustomCommand(slotCard.slotId, text)
                    root.openCustomSlot = ""
                }
            }

            SlotIconButton {
                objectName: "defaultAppCustomApply_" + slotCard.slotId
                iconName: "check"
                tooltipText: Translation.tr("Save command")
                onClicked: {
                    AppLauncher.setCustomCommand(slotCard.slotId, customCmdField.text)
                    root.openCustomSlot = ""
                }
            }
        }
    }

    SettingsTaskNavigator {
        objectName: "defaultAppsTaskTabs"
        showTabBar: true
        showIntro: false
        icon: "apps"
        title: Translation.tr("Applications")
        description: ""
        summary: Translation.tr("Core Applications · Portable · System Utilities · Autostart")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Default Apps"), icon: "apps", value: "primary" },
            { displayName: Translation.tr("System Utilities"), icon: "tune", value: "utilities" },
            { displayName: Translation.tr("Autostart"), icon: "rocket_launch", value: "autostart" }
        ]
    }

    GridLayout {
        objectName: "defaultAppsTwoColumnGrid"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: root.activeSection === "primary"
        columns: 2
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 14

        SettingsCardSection {
            _preventBentoReparent: true
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            visible: true
            expanded: true
            icon: "apps"
            title: Translation.tr("Core Applications")

            DiscoveryHeaderBar {
                objectName: "defaultAppsDiscoverySummary"
            }

            Repeater {
                model: AppLauncher.primarySlotDefinitions()
                delegate: DefaultAppSlotCard {
                    required property var modelData
                    slotData: modelData
                }
            }
        }

        ApplicationsConfig {
            id: portableAppsSection
            objectName: "defaultAppsPortableSection"
            embedded: true
            settingsPageIndex: root.settingsPageIndex
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
        }
    }

    SettingsCardSection {
        objectName: "defaultAppsUtilitiesCard"
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignTop
        visible: root.activeSection === "utilities"
        expanded: true
        icon: "tune"
        title: Translation.tr("System Utilities")

        DiscoveryHeaderBar {
            objectName: "defaultAppsUtilitiesDiscoverySummary"
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            columns: width >= 680 ? 2 : 1
            uniformCellWidths: columns === 2
            columnSpacing: 14
            rowSpacing: 10

            Repeater {
                model: AppLauncher.utilitySlotDefinitions()
                delegate: DefaultAppSlotCard {
                    required property var modelData
                    slotData: modelData
                }
            }
        }
    }

    AutostartConfig {
        id: autostartSection
        objectName: "defaultAppsAutostartSection"
        visible: root.activeSection === "autostart"
        embedded: true
        settingsPageIndex: root.settingsPageIndex
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
    }
}
