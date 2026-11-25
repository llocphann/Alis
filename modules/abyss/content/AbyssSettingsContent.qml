import QtQuick
import QtQuick.Window
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.abyss
import qs.modules.abyss.looks

// The mature Settings card is reparented directly into the Abyss body host;
// Edit Layout and Edit Navigation are intentionally removed for a focused UI.
Item {
    id: root
    property var participant: null
    property string outputName: ""
    readonly property bool editMode: false
    readonly property real topControlReserve: 0
    readonly property real bottomControlReserve: 0
    readonly property Item currentPage: settings.pageHost?.currentItem ?? null
    property bool _firstPageSettled: false
    readonly property bool _rawPageReady: Boolean(settings.pageHost && !settings.pageHost.loading)
    on_RawPageReadyChanged: if (_rawPageReady) _firstPageSettled = true
    Component.onCompleted: if (_rawPageReady) _firstPageSettled = true
    readonly property bool contentReady: _firstPageSettled || _rawPageReady
    function handleEscape(): bool {
        return settings.handleEscape()
    }
    SettingsOverlay {
        id: settings
        embeddedHost: root
    }
}
