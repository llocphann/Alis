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
    settingsPageName: Translation.tr("Default Applications")

    property string activeSection: "primary"
    property string openPickerSlot: ""
    property string openCustomSlot: ""

    Component.onCompleted: {
        AppLauncher.refreshDiscovery()
    }

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
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
        implicitHeight: 20
        implicitWidth: badgeLabel.implicitWidth + 12
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
            anchors.centerIn: parent
            text: badgeRoot.badgeText
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
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
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: btnRoot.activeState
            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
            : Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: btnRoot.iconName
            iconSize: 18
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
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: AppLauncher.discovering
                ? Translation.tr("Scanning installed applications…")
                : Translation.tr("%1 installed applications").arg((AppLauncher.discoveredApps ?? []).length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
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
            spacing: 8

            MaterialSymbol {
                text: slotCard.slotData?.icon ?? "apps"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: slotCard.slotData?.label ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }

        Rectangle {
            objectName: "defaultAppCurrent_" + slotCard.slotId
            Layout.fillWidth: true
            implicitHeight: currentRow.implicitHeight + 14
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
                    iconName: slotCard.summary?.icon ?? (slotCard.slotData?.icon ?? "apps")
                    fallbackSymbol: slotCard.slotData?.icon ?? "apps"
                    iconSize: 24
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StyledText {
                            objectName: "defaultAppName_" + slotCard.slotId
                            text: slotCard.summary?.name ?? ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        SourceBadgePill {
                            objectName: "defaultAppBadge_" + slotCard.slotId
                            badgeText: slotCard.summary?.sourceBadge ?? "Native"
                            available: Boolean(slotCard.summary?.installed ?? true)
                        }

                        MaterialSymbol {
                            objectName: "defaultAppXdgStatus_" + slotCard.slotId
                            visible: Boolean(slotCard.xdgStatus.supported && slotCard.xdgStatus.synced)
                            text: "verified"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }

                        Item { Layout.fillWidth: true }
                    }

                    StyledText {
                        Layout.fillWidth: true
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
                    }
                }

                RowLayout {
                    spacing: 6

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
            visible: String(slotCard.xdgStatus.errorText ?? "").length > 0
            text: slotCard.xdgStatus.errorText ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: slotCard.pickerOpen
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialTextField {
                    id: searchInput
                    objectName: "defaultAppSearch_" + slotCard.slotId
                    Layout.fillWidth: true
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
                spacing: 4

                Repeater {
                    model: slotCard.candidates

                    delegate: RippleButton {
                        id: candidateRow
                        required property int index
                        required property var modelData
                        objectName: "defaultAppOption_" + slotCard.slotId + "_" + String(modelData.identityKey ?? index)
                        Layout.fillWidth: true
                        implicitHeight: 42
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
                                iconName: candidateRow.modelData.icon || (slotCard.slotData?.icon ?? "apps")
                                fallbackSymbol: slotCard.slotData?.icon ?? "apps"
                                iconSize: 20
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        text: candidateRow.modelData.name ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: candidateRow.isCurrent ? Font.DemiBold : Font.Normal
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    SourceBadgePill {
                                        badgeText: candidateRow.modelData.sourceBadge ?? "Native"
                                        available: true
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: candidateRow.modelData.exec ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                }
                            }

                            MaterialSymbol {
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
            visible: slotCard.customOpen
            spacing: 6

            MaterialTextField {
                id: customCmdField
                objectName: "defaultAppCustomInput_" + slotCard.slotId
                Layout.fillWidth: true
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
        icon: "apps"
        title: Translation.tr("Default Applications")
        description: ""
        summary: Translation.tr("Core Applications · System Utilities")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Core Applications"), icon: "apps", value: "primary" },
            { displayName: Translation.tr("System Utilities"), icon: "tune", value: "utilities" }
        ]
    }

    SettingsCardSection {
        settingsTaskSection: "primary"
        visible: root.activeSection === "primary"
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

    SettingsCardSection {
        settingsTaskSection: "utilities"
        visible: root.activeSection === "utilities"
        expanded: true
        icon: "tune"
        title: Translation.tr("System Utilities")

        DiscoveryHeaderBar {
            objectName: "defaultAppsUtilitiesDiscoverySummary"
        }

        Repeater {
            model: AppLauncher.utilitySlotDefinitions()
            delegate: DefaultAppSlotCard {
                required property var modelData
                slotData: modelData
            }
        }
    }
}
