import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    // Settings navigation metadata belongs to this Alis-side wrapper.
    // Without it IntegrationsConfig page 38 fails to instantiate before its
    // optional Alis-Intergration payload can be loaded or checked.
    property string settingsTaskSection: ""
    // The page content is a ColumnLayout. Without this hint the wrapper can
    // receive width=0, so the loaded Obsidian card paints into a zero-width
    // surface while still reserving its full implicit height.
    Layout.fillWidth: true
    implicitHeight: content.item ? content.item.implicitHeight : unavailable.implicitHeight
    Loader {
        id: content
        width: parent.width
        active: AlisIntergration.obsidianEnabled
        source: AlisIntergration.settingsSource("obsidian")
    }
    StyledText {
        id: unavailable
        width: parent.width
        visible: !content.active
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("Install Alis-Intergration; enable this integration in Settings → Integrations.")
    }
}
