pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: root

    readonly property string requestedOutput:
        String(Quickshell.env("ALIS_ABYSS_G2_OUTPUT") || "")
    readonly property var targetScreens: {
        const screens = Quickshell.screens
        if (root.requestedOutput.length === 0)
            return screens.length > 0 ? [screens[0]] : []
        return screens.filter(screen => (screen?.name ?? "") === root.requestedOutput)
    }

    Variants {
        model: root.targetScreens

        G2Scenario {
            required property var modelData
            targetScreen: modelData
        }
    }
}
