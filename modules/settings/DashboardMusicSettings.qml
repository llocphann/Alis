import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

SettingsGroup {
    ConfigSwitch {
        text: Translation.tr("Music")
        checked: Config.options?.dashboard?.music?.enable ?? true
        onCheckedChanged: Config.setNestedValue("dashboard.music.enable",checked)
    }
    ConfigSwitch {
        text: Translation.tr("Show Music scrollbars")
        checked: Config.options?.dashboard?.music?.showScrollbars ?? true
        onCheckedChanged: Config.setNestedValue("dashboard.music.showScrollbars", checked)
    }
    ContentSubsection {
        title: Translation.tr("MPD")
        RowLayout {
            Layout.fillWidth: true
            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("MPD host")
                text: Config.options?.sidebar?.music?.mpdHost ?? "127.0.0.1"
                onEditingFinished: Config.setNestedValue("sidebar.music.mpdHost",text.trim() || "127.0.0.1")
            }
            ConfigSpinBox {
                text: Translation.tr("Port")
                value: Config.options?.sidebar?.music?.mpdPort ?? 6600
                from: 1; to: 65535
                onValueChanged: Config.setNestedValue("sidebar.music.mpdPort",value)
            }
        }
    }
    ContentSubsection {
        title: Translation.tr("Music library folder")
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: LocalMusic.libraryFolder
                elide: Text.ElideMiddle
                color: Appearance.colors.colSubtext
            }
            RippleButton {
                implicitWidth: 40; implicitHeight: 36
                onClicked: folder.open()
                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "folder_open"; iconSize: 20 }
                StyledToolTip { text: Translation.tr("Select music library folder") }
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
