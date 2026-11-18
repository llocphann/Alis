pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services

GeneralConfigCore {
    id: root
    showIntegrationSettings: false

    function selectTlpCategory(categoryId: string): bool {
        return SettingsPageRegistry.navigateToKey("integrations", "TLP " + String(categoryId ?? ""))
    }

    function activateSettingsSearchSection(section: string): bool {
        const value = String(section ?? "").toLowerCase()
        if (value.includes("fan") || value.includes("thinkfan")
                || value.includes("thermal") || value.includes("cooling")) {
            SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")
            return true
        } else if (value.includes("tlp")) {
            SettingsPageRegistry.navigateToKey("integrations", "TLP")
            return true
        } else if (value.includes("audio") || value.includes("sound")
                || value.includes("power") || value.includes("battery") || value.includes("charge")
                || value.includes("session") || value.includes("close")) {
            root.activeSection = "audio"
            return true
        } else if (value.includes("language") || value.includes("locale")
                || value.includes("time") || value.includes("date") || value.includes("format")
                || value.includes("input") || value.includes("keyboard")) {
            root.activeSection = "locale"
            return true
        } else if (value.includes("safety") || value.includes("polic") || value.includes("lock") || value.includes("security")) {
            root.activeSection = "safety"
            return true
        }
        return false
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

    Loader {
        active: root.showIntegrationSettings
        visible: root.activeSection === "power"
        sourceComponent: TlpPowerSettings {
            showIntegrationSettings: root.showIntegrationSettings
        }
    }
}
