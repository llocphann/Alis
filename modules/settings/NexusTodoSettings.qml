import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property string settingsTaskSection: "nexus"
    Layout.fillWidth: true
    implicitHeight: content.item?.implicitHeight ?? fallback.implicitHeight
    Loader {
        id: content
        width: parent.width
        active: AlisIntergration.nexusEnabled && root.visible
        source: AlisIntergration.settingsSource("nexusTodo")
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
            text: Translation.tr("Install Alis-Intergration; enable Nexus in Settings → Integrations.")
        }
        DialogButton {
            objectName: "alisTodoFallbackRestore"
            visible: Todo.backend === "nexus"
            buttonText: Translation.tr("Use Alis")
            onClicked: Todo.reactivateInternal()
        }
    }
}
