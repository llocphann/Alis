import QtQuick
import qs.modules.settings

// The mature rail/card is reparented here; no second settings page tree.
Item {
    id: root
    property string outputName: ""
    readonly property Item currentPage: settings.pageHost?.currentItem ?? null
    function handleEscape(): bool {
        return settings.handleEscape()
    }
    SettingsOverlay {
        id: settings
        embeddedHost: root
    }
}
