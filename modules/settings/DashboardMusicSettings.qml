import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

SettingsGroup {
    ConfigRow {
        uniform: true

        ContentSubsection {
            Layout.fillWidth: true
            title: Translation.tr("Music library folder")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    StyledText {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: LocalMusic.libraryFolder
                        elide: Text.ElideMiddle
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 36
                    onClicked: folder.open()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "folder_open"
                        iconSize: 20
                    }
                    StyledToolTip {
                        text: Translation.tr("Select music library folder")
                    }
                }
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            title: Translation.tr("MPD")

            ConfigSpinBox {
                Layout.fillWidth: true
                text: Translation.tr("Port")
                value: Config.options?.sidebar?.music?.mpdPort ?? 6600
                from: 1
                to: 65535
                onValueChanged: Config.setNestedValue("sidebar.music.mpdPort", value)
            }
        }
    }

    FolderDialog {
        id: folder
        title: Translation.tr("Select music library folder")
        onAccepted: LocalMusic.setLibraryFolder(String(selectedFolder))
    }
    SettingsNativeDialogGuard { dialog: folder; dialogKey: "dashboard-local-music-folder" }
}
