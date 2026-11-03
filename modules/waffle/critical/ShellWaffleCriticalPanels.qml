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
        readonly property bool enabledPanel: Config.ready
            && (Config.options?.enabledPanels ?? []).includes(identifier)
            && extraCondition
        active: enabledPanel
    }

    CriticalPanelLoader {
        identifier: "wBar"
        source: Qt.resolvedUrl("../bar/WaffleBar.qml")
    }

    CriticalPanelLoader {
        identifier: "wBackground"
        source: Qt.resolvedUrl("../background/WaffleBackground.qml")
    }

    CriticalPanelLoader {
        identifier: "wBackdrop"
        extraCondition: Config.options?.waffles?.background?.backdrop?.enable ?? true
        source: Qt.resolvedUrl("../backdrop/WaffleBackdrop.qml")
    }
}
