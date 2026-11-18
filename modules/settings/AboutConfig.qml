pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    objectName: "aboutSettings"
    settingsPageIndex: 40
    settingsPageName: Translation.tr("About")

    property string kernelRelease: ""
    property string cpuModel: ""
    property string totalMemoryGiB: ""

    Process {
        id: hardwareProbeProc
        command: ["/bin/sh", "-c", "uname -sr 2>/dev/null; awk -F: '/model name/{gsub(/^[ \\t]+/,\"\",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null; awk '/MemTotal/{printf \"%.1f GiB\\n\", $2/1048576}' /proc/meminfo 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text ?? "").trim().split("\n")
                root.kernelRelease = String(lines[0] ?? "").trim()
                root.cpuModel = String(lines[1] ?? "").trim()
                root.totalMemoryGiB = String(lines[2] ?? "").trim()
            }
        }
    }

    component InfoRow: ColumnLayout {
        required property string label
        required property string value
        property bool showTopDivider: true
        property bool monoValue: false

        Layout.fillWidth: true
        spacing: 8

        SettingsDivider {
            visible: parent.showTopDivider
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                Layout.preferredWidth: 150
                Layout.minimumWidth: 0
                text: parent.parent.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: parent.parent.value || "—"
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: parent.parent.monoValue ? Appearance.font.family.monospace : Appearance.font.family.main
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }
    }

    SettingsCardSection {
        objectName: "aboutHeroCard"
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "info"
        title: Translation.tr("Alis Desktop Shell")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: Appearance.rounding.normal
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86)
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.55)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "water_drop"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: "Alis"
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: branchBadgeText.implicitWidth + 16
                            radius: Appearance.rounding.full
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)

                            StyledText {
                                id: branchBadgeText
                                anchors.centerIn: parent
                                text: (ShellUpdates.currentBranch || "dev")
                                    + (ShellUpdates.localCommit.length > 0 ? (" · " + ShellUpdates.localCommit.slice(0, 7)) : "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Connected Quickshell desktop environment with Abyss & Waffle families")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }

                RippleButtonWithIcon {
                    implicitHeight: 34
                    materialIcon: "deployed_code_update"
                    mainText: ShellUpdates.hasUpdate ? Translation.tr("Update available") : Translation.tr("Check updates")
                    onClicked: SettingsPageRegistry.navigateToKey("services", "updates")
                }
            }
        }
    }

    SettingsCardSection {
        objectName: "aboutSystemInfoCard"
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "computer"
        title: Translation.tr("System & Session")

        SettingsGroup {
            InfoRow {
                showTopDivider: false
                label: Translation.tr("Distribution")
                value: SystemInfo.distroName || "Linux"
            }

            InfoRow {
                label: Translation.tr("Host & User")
                value: [SystemInfo.username, SystemInfo.hostname].filter(Boolean).join("@")
                monoValue: true
            }

            InfoRow {
                label: Translation.tr("Compositor")
                value: CompositorService.isNiri
                    ? "Niri (Wayland)"
                    : ([SystemInfo.desktopEnvironment, SystemInfo.windowingSystem].filter(Boolean).join(" · ") || "Wayland")
            }

            InfoRow {
                label: Translation.tr("Panel Family")
                value: Config.options?.panelFamily === "waffle"
                    ? Translation.tr("Waffle")
                    : Translation.tr("Abyss")
            }

            InfoRow {
                visible: root.kernelRelease.length > 0
                label: Translation.tr("Kernel")
                value: root.kernelRelease
                monoValue: true
            }

            InfoRow {
                visible: root.cpuModel.length > 0
                label: Translation.tr("Processor")
                value: root.cpuModel
            }

            InfoRow {
                visible: root.totalMemoryGiB.length > 0
                label: Translation.tr("Memory")
                value: root.totalMemoryGiB
                monoValue: true
            }
        }
    }

    SettingsCardSection {
        objectName: "aboutQuickLinksCard"
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "explore"
        title: Translation.tr("Quick Links")

        SettingsGroup {
            SettingsDrillDownRow {
                iconName: "extension"
                title: Translation.tr("Optional Integrations")
                description: Translation.tr("Manage Alis Nexus, Spaced Repetition, TLP and Thinkfan plugins")
                onClicked: SettingsPageRegistry.navigateToKey("integrations", "")
            }

            SettingsDivider {}

            SettingsDrillDownRow {
                iconName: "keyboard"
                title: Translation.tr("Keyboard Shortcuts")
                description: Translation.tr("Browse and customize Niri & shell keybindings")
                onClicked: SettingsPageRegistry.navigateToKey("shortcuts", "")
            }

            SettingsDivider {}

            SettingsDrillDownRow {
                iconName: "desktop_windows"
                title: Translation.tr("Display & Input")
                description: Translation.tr("Arrange monitors, resolution, scale, tiling and input devices")
                onClicked: SettingsPageRegistry.navigateToKey("compositor", "displays")
            }

            SettingsDivider {}

            SettingsDrillDownRow {
                iconName: "folder_open"
                title: Translation.tr("Open Shell Config Folder")
                description: Directories.configPath
                onClicked: Quickshell.execDetached(["xdg-open", Directories.configPath])
            }
        }
    }
}
