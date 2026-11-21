pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// No independent timer or minimum duration. The host reports whether the
// requested page is not yet Ready, even while the previous page remains onscreen.
// Replaces the retired floating gear indicator with the shared AlisLoadingScreen.
Item {
    id: root
    property bool loading: false
    property string title: ""
    property string icon: "tune"
    visible: root.loading

    AlisLoadingScreen {
        anchors.fill: parent
        loading: root.loading
        title: root.title
        icon: (root.icon.length > 0 && root.icon !== "settings") ? root.icon : "tune"
        accentColor: SettingsMaterialPreset.accentColor
        fillSurface: true
        backdropOpacity: 0.86
    }
}
