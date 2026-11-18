pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.settings

Singleton {
    id: root

    function closeFlyouts(): void {
        GlobalStates.searchOpen = false
        GlobalStates.waffleActionCenterOpen = false
        GlobalStates.waffleNotificationCenterOpen = false
        GlobalStates.waffleWidgetsOpen = false
        GlobalStates.waffleClipboardOpen = false
        GlobalStates.waffleTaskViewOpen = false
        GlobalStates.dashboardOpen = false
    }

    function toggleDashboard(pageId = ""): void {
        const nextOpen = !GlobalStates.dashboardOpen
        if (nextOpen) {
            GlobalStates.searchOpen = false
            GlobalStates.waffleActionCenterOpen = false
            GlobalStates.waffleNotificationCenterOpen = false
            GlobalStates.waffleWidgetsOpen = false
            GlobalStates.waffleClipboardOpen = false
            GlobalStates.waffleTaskViewOpen = false
            GlobalStates.settingsOverlayOpen = false
            if (String(pageId ?? "").trim().length > 0)
                GlobalStates.dashboardPageId = String(pageId).trim()
        }
        GlobalStates.dashboardOpen = nextOpen
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
        if (GlobalStates.useSettingsOverlay()) {
            GlobalStates.settingsOverlayTargetOutput = GlobalStates.resolveOutputName("", [])
            GlobalStates.settingsOverlayOpen = true
        } else {
            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings-window"])
        }
    }
}
