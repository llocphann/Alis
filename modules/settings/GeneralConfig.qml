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

    // Static search entries use human-facing section names while the System
    // navigator uses stable lowercase task ids. Keep the translation here so
    // search can land on the correct tab before it scrolls to a control.
    function activateSettingsSearchSection(section: string): void {
        const value = String(section ?? "").toLowerCase()
        if (value.includes("fan") || value.includes("thinkfan")
                || value.includes("thermal") || value.includes("cooling")) {
            SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")
            root.activeSection = "power"
        } else if (value.includes("power") || value.includes("battery")
                || value.includes("charge") || value.includes("tlp")) {
            root.activeSection = "power"
            // Battery care now lives in the primary Battery/TLP card, so the
            // Power task itself is the deep-link destination.
        } else if (value.includes("audio") || value.includes("sound")) {
            root.activeSection = "audio"
        } else if (value.includes("language") || value.includes("locale")
                || value.includes("time")) {
            root.activeSection = "locale"
        } else if (value.includes("input") || value.includes("keyboard")) {
            root.activeSection = "input"
        } else if (value.includes("safety") || value.includes("polic")) {
            root.activeSection = "safety"
        }
    }

    function _consumeLegacyTlpPowerRedirect(): void {
        if (SettingsPageRegistry.consumeLegacyTlpPowerRedirect())
            root.activeSection = "power"
    }

    Component.onCompleted: root._consumeLegacyTlpPowerRedirect()

    Connections {
        target: Persistent

        function onReadyChanged(): void {
            if (Persistent.ready)
                Qt.callLater(root._consumeLegacyTlpPowerRedirect)
        }
    }

    // Core battery warnings/suspend remain independent of optional plugins.
    TlpPowerSettings {
        id: tlpPowerSettings
        showIntegrationSettings: false
        Layout.fillWidth: true
        visible: root.activeSection === "power"
    }
}
