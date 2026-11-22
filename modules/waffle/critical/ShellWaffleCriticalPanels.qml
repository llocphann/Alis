pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

Item {
    id: root

    component CriticalPanelLoader: LazyLoader {
        id: criticalPanelLoader
        required property string identifier
        property bool extraCondition: true
        property bool loadAsync: false
        readonly property bool enabledPanel: Config.ready
            && (Config.options?.enabledPanels ?? []).includes(identifier)
            && extraCondition
        active: !loadAsync && enabledPanel
        activeAsync: loadAsync && enabledPanel
    }

    CriticalPanelLoader {
        identifier: "wBar"
        source: Qt.resolvedUrl("../bar/WaffleBar.qml")
    }

    CriticalPanelLoader {
        identifier: "wBackground"
        loadAsync: true
        source: Qt.resolvedUrl("../background/WaffleBackground.qml")
    }

    CriticalPanelLoader {
        identifier: "wBackdrop"
        loadAsync: true
        extraCondition: Config.options?.waffles?.background?.backdrop?.enable ?? true
        source: Qt.resolvedUrl("../backdrop/WaffleBackdrop.qml")
    }
}
