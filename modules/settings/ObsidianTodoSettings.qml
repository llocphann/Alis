import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property string settingsTaskSection: "obsidian"
    Layout.fillWidth: true
    implicitHeight: content.item?.implicitHeight ?? fallback.implicitHeight
    Loader {
        id: content
        width: parent.width
        active: Hadalird.obsidianEnabled && root.visible
        source: Hadalird.settingsSource("obsidianTodo")
    }
    SettingsCardSection {
        id: fallback
        width: parent.width
        visible: !content.item
        title: Translation.tr("To-do & Quick Notes")
        icon: "checklist"
        expanded: true
        enableSettingsSearch: false
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Install Alis-Intergration; enable Obsidian in Settings → Integrations.")
        }
        DialogButton {
            objectName: "hadalisTodoFallbackRestore"
            visible: Todo.backend === "obsidian"
            buttonText: Translation.tr("Use Alis")
            onClicked: Todo.reactivateInternal()
        }
    }
}
