pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services

GeneralConfigCore {
    id: root

    function selectTlpCategory(categoryId: string): bool {
        return SettingsPageRegistry.navigateToKey("integrations", "TLP " + String(categoryId ?? ""))
    }

    function activateSettingsSearchSection(section: string): void {
        const value = String(section ?? "").toLowerCase()
        if (value.includes("fan") || value.includes("thinkfan")
                || value.includes("thermal") || value.includes("cooling")) {
            SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")
        } else if (value.includes("tlp")) {
            SettingsPageRegistry.navigateToKey("integrations", "TLP")
        } else if (value.includes("audio") || value.includes("sound")
                || value.includes("power") || value.includes("battery") || value.includes("charge")) {
            root.activeSection = "audio"
        } else if (value.includes("language") || value.includes("locale")
                || value.includes("time") || value.includes("input") || value.includes("keyboard")) {
            root.activeSection = "locale"
        } else if (value.includes("safety") || value.includes("polic") || value.includes("lock")) {
            root.activeSection = "safety"
        }
    }

    function _consumeLegacyTlpPowerRedirect(): void {
        if (SettingsPageRegistry.consumeLegacyTlpPowerRedirect())
            SettingsPageRegistry.navigateToKey("integrations", "TLP")
    }

    Component.onCompleted: root._consumeLegacyTlpPowerRedirect()

    Connections {
        target: Persistent

        function onReadyChanged(): void {
            if (Persistent.ready)
                Qt.callLater(root._consumeLegacyTlpPowerRedirect)
        }
    }
}
