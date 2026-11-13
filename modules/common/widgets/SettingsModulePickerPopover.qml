pragma ComponentBehavior: Bound

import QtQuick

// Retired floating popover stub retained only for qmldir compatibility.
// Settings module management now lives natively inside the bottom-connected
// Abyss customization dock (SettingsEditToolbar).
Item {
    id: root
    objectName: "settingsModulePickerPopover"
    property Item targetPage: null
    visible: false
    enabled: false
}
