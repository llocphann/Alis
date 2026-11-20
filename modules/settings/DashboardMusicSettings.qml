import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

SettingsGroup {
    GridLayout {
        id: libraryGrid
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        columns: width >= 520 * Appearance.fontSizeScale ? 2 : 1
        columnSpacing: 12
        rowSpacing: 8

        ContentSubsection {
            Layout.fillWidth: true
            title: Translation.tr("Music library folder")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: Math.max(36, pathText.implicitHeight + 12)
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    StyledText {
                        id: pathText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        wrapMode: Text.Wrap
                        text: LocalMusic.libraryFolder
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
            Layout.minimumWidth: portControl.implicitWidth
            Layout.preferredWidth: portControl.implicitWidth
            Layout.maximumWidth: libraryGrid.columns === 2 ? portControl.implicitWidth : Infinity
            title: Translation.tr("MPD")

            ConfigSpinBox {
                id: portControl
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
