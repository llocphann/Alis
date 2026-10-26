import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
Item {
    id: root
    property string settingsTaskSection: "fan"
    Layout.fillWidth: true
    implicitHeight: content.item?.implicitHeight ?? fallback.implicitHeight
    Loader {
        id: content
        width: parent.width
        active: AlisIntergration.thinkfanEnabled && root.visible
        source: AlisIntergration.settingsSource("thinkfan")
    }
    SettingsCardSection {
        id: fallback
        width: parent.width
        visible: !content.item
        enableSettingsSearch: false
        title: Translation.tr("Fan Control")
        icon: "mode_fan"
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Install Alis-Intergration; enable Thinkfan in Settings → Integrations.")
        }
    }
}
