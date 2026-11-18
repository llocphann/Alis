pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common

Singleton {
    id: root

    function closeFlyouts(): void {
        GlobalStates.searchOpen = false
        GlobalStates.waffleActionCenterOpen = false
        GlobalStates.waffleNotificationCenterOpen = false
        GlobalStates.waffleWidgetsOpen = false
        GlobalStates.waffleClipboardOpen = false
    }

    function openSettings(pageKey = "", section = ""): void {
        root.closeFlyouts()
        const key = String(pageKey ?? "").trim()
        const sec = String(section ?? "").trim()
        if (key.length > 0) {
            const idx = SettingsPageRegistry.pageIndexForKey(key)
            if (idx >= 0) {
                GlobalStates.openSettingsSection(idx, sec)
                return
            }
        }
        if (Config.options?.settingsUi?.overlayMode ?? false) {
            GlobalStates.settingsOverlayTargetOutput = GlobalStates.resolveOutputName("", [])
            GlobalStates.settingsOverlayOpen = true
        } else {
            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings-window"])
        }
    }
}
