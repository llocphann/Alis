pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.settings

WSettingsPage {
    id: root
    settingsPageIndex: 10
    pageTitle: Translation.tr("About")
    pageIcon: "info"
    pageDescription: Translation.tr("Project information and links")

    // Hero card — project identity
    WSettingsCard {
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.topMargin: 8
            Layout.bottomMargin: 4
            spacing: 18

            // Shared offline Alis owner avatar. The file is kept in the repo,
            // so About never depends on an external image request.
            Rectangle {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84
                Layout.alignment: Qt.AlignVCenter
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Looks.colors.accent

                Image {
                    id: aboutAvatar
                    anchors.centerIn: parent
                    width: 76
                    height: 76
                    source: Quickshell.shellPath("assets/icons/alis-owner-avatar.jpg")
                    sourceSize.width: 76
                    sourceSize.height: 76
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: ShaderEffectSource {
                            sourceItem: Rectangle {
                                width: 76
                                height: 76
                                radius: 38
                            }
                        }
                    }
                }

                WText {
                    anchors.centerIn: parent
                    visible: aboutAvatar.status !== Image.Ready
                    text: "Al"
                    font.pixelSize: Looks.font.pixelSize.xlarger
                    font.weight: Looks.font.weight.stronger
                    color: Looks.colors.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                WText {
                    text: "Alis"
                    font.pixelSize: Looks.font.pixelSize.xlarger * 1.4
                    font.weight: Looks.font.weight.stronger
                }

                WText {
                    text: Translation.tr("Quickshell desktop shell for Niri")
                    font.pixelSize: Looks.font.pixelSize.normal
                    color: Looks.colors.subfg
                }

                RowLayout {
                    spacing: 8
                    Layout.topMargin: 4

                    // Version badge
                    Rectangle {
                        implicitWidth: versionLabel.implicitWidth + 16
                        implicitHeight: 24
                        radius: Looks.radius.small
                        color: Looks.colors.accent

                        WText {
                            id: versionLabel
                            anchors.centerIn: parent
                            text: "v" + (ShellUpdates.localVersion || "?")
                            font.pixelSize: Looks.font.pixelSize.small
                            font.weight: Looks.font.weight.strong
                            color: Looks.colors.accentFg
                        }
                    }

                    // Compositor badge
                    Rectangle {
                        implicitWidth: compLabel.implicitWidth + 16
                        implicitHeight: 24
                        radius: Looks.radius.small
                        color: Looks.colors.bg2

                        WText {
                            id: compLabel
                            anchors.centerIn: parent
                            text: CompositorService.isNiri ? "Niri" : (CompositorService.isHyprland ? "Hyprland" : "Unknown")
                            font.pixelSize: Looks.font.pixelSize.small
                            color: Looks.colors.subfg
                        }
                    }

                    // Framework badge
                    Rectangle {
                        implicitWidth: fwLabel.implicitWidth + 16
                        implicitHeight: 24
                        radius: Looks.radius.small
                        color: Looks.colors.bg2

                        WText {
                            id: fwLabel
                            anchors.centerIn: parent
                            text: "Qt 6"
                            font.pixelSize: Looks.font.pixelSize.small
                            color: Looks.colors.subfg
                        }
                    }
                }
            }
        }
    }

    // Links
    WSettingsCard {
        title: Translation.tr("Links")
        icon: "open"

        WSettingsButton {
            label: "Alis"
            description: "github.com/llocphann/Alis"
            icon: "globe-search"
            buttonText: Translation.tr("Open")
            onButtonClicked: Qt.openUrlExternally("https://github.com/llocphann/Alis")
        }

        WSettingsButton {
            label: "Alis-Companion"
            description: "github.com/llocphann/Alis-Companion"
            icon: "globe-search"
            buttonText: Translation.tr("Open")
            onButtonClicked: Qt.openUrlExternally("https://github.com/llocphann/Alis-Companion")
        }

        WSettingsButton {
            label: "Alis-Intergration"
            description: "github.com/llocphann/Alis-Intergration"
            icon: "globe-search"
            buttonText: Translation.tr("Open")
            onButtonClicked: Qt.openUrlExternally("https://github.com/llocphann/Alis-Intergration")
        }

        WSettingsButton {
            label: Translation.tr("Documentation")
            description: "github.com/llocphann/Alis/tree/dev/docs"
            icon: "library"
            buttonText: Translation.tr("Open")
            onButtonClicked: Qt.openUrlExternally("https://github.com/llocphann/Alis/tree/dev/docs")
        }

        WSettingsButton {
            label: Translation.tr("Quickshell Documentation")
            description: "quickshell.outfoxxed.me"
            icon: "globe-search"
            buttonText: Translation.tr("Open")
            onButtonClicked: Qt.openUrlExternally("https://quickshell.outfoxxed.me")
        }
    }

    // Explicit upstream credits: the main brand and links above remain Alis.
    WSettingsCard {
        title: Translation.tr("Based on")
        icon: "people"

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            WSettingsButton {
                Layout.fillWidth: true
                label: "Alis"
                description: "github.com/snowarch/Alis"
                icon: "open"
                buttonText: Translation.tr("Open")
                onButtonClicked: Qt.openUrlExternally("https://github.com/snowarch/Alis")
            }

            WSettingsButton {
                Layout.fillWidth: true
                label: "illogical-impulse"
                description: "github.com/end-4/dots-hyprland"
                icon: "open"
                buttonText: Translation.tr("Open")
                onButtonClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            Layout.bottomMargin: 6
            spacing: 12

            WText {
                Layout.fillWidth: true
                text: "Alis builds on Alis's Niri/Quickshell foundation and end-4's illogical-impulse."
                wrapMode: Text.WordWrap
                font.pixelSize: Looks.font.pixelSize.normal
                color: Looks.colors.subfg
                lineHeight: 1.3
            }

            WText {
                Layout.fillWidth: true
                text: Translation.tr("Special thanks to the Quickshell and Niri communities.")
                wrapMode: Text.WordWrap
                font.pixelSize: Looks.font.pixelSize.normal
                color: Looks.colors.subfg
                lineHeight: 1.3
            }
        }
    }

    // System Info
    WSettingsCard {
        title: Translation.tr("System Info")
        icon: "info"

        WSettingsRow {
            label: Translation.tr("Config path")
            description: FileUtils.trimFileProtocol(`${Directories.shellConfig}/`)
            icon: "folder"
        }

        WSettingsRow {
            label: Translation.tr("Shell path")
            description: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/alis/`)
            icon: "folder"
        }

        WSettingsRow {
            label: Translation.tr("Panel family")
            description: Config.options?.panelFamily === "waffle" ? "Waffle (Windows 11)" : "ii (Material)"
            icon: "app-generic"
        }
    }
}
