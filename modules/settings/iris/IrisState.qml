pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root

    readonly property var defaultPinnedTiles: [
        "darkMode",
        "blur",
        "companion",
        "dnd",
        "wifi",
        "bluetooth"
    ]

    readonly property var defaultPinnedAreas: [
        "wallpaper",
        "themes",
        "companion"
    ]

    property var recentPageIndices: []

    function _readSavedChromeObject(): var {
        const raw = String(Config.options?.settingsUi?.chromeLayout ?? "")
        if (!raw || raw.length === 0)
            return ({ version: 1 })
        try {
            const parsed = JSON.parse(raw)
            if (Array.isArray(parsed))
                return ({ version: 1, header: parsed })
            if (parsed && typeof parsed === "object")
                return Object.assign({ version: 1 }, parsed)
        } catch (e) {}
        return ({ version: 1 })
    }

    function _writeSavedField(fieldName: string, value: var): void {
        const next = root._readSavedChromeObject()
        next[fieldName] = value
        Config.setNestedValue("settingsUi.chromeLayout", JSON.stringify(next))
    }

    readonly property var _savedObj: root._readSavedChromeObject()

    readonly property var pinnedTileIds: {
        const saved = root._savedObj?.irisPinnedTiles
        if (!Array.isArray(saved))
            return root.defaultPinnedTiles.slice()
        const validIds = root.tileCatalogIds
        const seen = ({})
        const out = []
        for (let i = 0; i < saved.length; i++) {
            const id = String(saved[i] ?? "")
            if (validIds.indexOf(id) >= 0 && !seen[id]) {
                seen[id] = true
                out.push(id)
            }
        }
        return out.length > 0 ? out : root.defaultPinnedTiles.slice()
    }

    readonly property var pinnedAreaKeys: {
        const saved = root._savedObj?.irisPinnedAreas
        if (!Array.isArray(saved))
            return root.defaultPinnedAreas.slice()
        const seen = ({})
        const out = []
        for (let i = 0; i < saved.length; i++) {
            const k = String(saved[i] ?? "").trim()
            if (k.length > 0 && !seen[k]) {
                seen[k] = true
                out.push(k)
            }
        }
        return out
    }

    // 0 = auto (shown on Home and when panel width >= 1220), 1 = shown, -1 = hidden
    readonly property int railMode: {
        const raw = Number(root._savedObj?.irisRailMode ?? 0)
        if (raw === 1 || raw === -1)
            return raw
        return 0
    }

    function effectiveRailOpen(panelWidth: real, showingHome: bool): bool {
        if (panelWidth > 0 && panelWidth < 920)
            return false
        if (root.railMode === 1)
            return true
        if (root.railMode === -1)
            return false
        return showingHome || panelWidth >= IrisTheme.railAutoBreakpoint
    }

    function toggleRail(panelWidth: real, showingHome: bool): void {
        const currentlyOpen = root.effectiveRailOpen(panelWidth, showingHome)
        const autoWouldOpen = showingHome || panelWidth >= IrisTheme.railAutoBreakpoint
        const nextOpen = !currentlyOpen
        if (nextOpen === autoWouldOpen)
            root._writeSavedField("irisRailMode", 0)
        else
            root._writeSavedField("irisRailMode", nextOpen ? 1 : -1)
    }

    function isTilePinned(tileId: string): bool {
        return root.pinnedTileIds.indexOf(tileId) >= 0
    }

    function togglePinTile(tileId: string): void {
        const cur = root.pinnedTileIds.slice()
        const idx = cur.indexOf(tileId)
        if (idx >= 0) {
            if (cur.length <= 1)
                return
            cur.splice(idx, 1)
        } else {
            cur.push(tileId)
        }
        root._writeSavedField("irisPinnedTiles", cur)
    }

    function resetPinnedTiles(): void {
        root._writeSavedField("irisPinnedTiles", root.defaultPinnedTiles.slice())
    }

    function isAreaPinned(areaKey: string): bool {
        return root.pinnedAreaKeys.indexOf(areaKey) >= 0
    }

    function togglePinArea(areaKey: string): void {
        const k = String(areaKey ?? "").trim()
        if (!k)
            return
        const cur = root.pinnedAreaKeys.slice()
        const idx = cur.indexOf(k)
        if (idx >= 0)
            cur.splice(idx, 1)
        else
            cur.push(k)
        root._writeSavedField("irisPinnedAreas", cur)
    }

    function recordVisit(pageIndex: int): void {
        if (pageIndex < 0)
            return
        const next = [pageIndex]
        const prev = root.recentPageIndices ?? []
        for (let i = 0; i < prev.length && next.length < 5; i++) {
            if (prev[i] !== pageIndex)
                next.push(prev[i])
        }
        root.recentPageIndices = next
    }

    readonly property var tileCatalogIds: [
        "darkMode",
        "blur",
        "companion",
        "dnd",
        "wifi",
        "bluetooth",
        "keepAwake",
        "gameMode",
        "dockAutoHide"
    ]

    function tileSpec(tileId: string): var {
        switch (tileId) {
        case "darkMode": {
            const dark = Boolean(Appearance.m3colors?.darkmode ?? true)
            return {
                id: "darkMode",
                icon: dark ? "dark_mode" : "light_mode",
                label: Translation.tr("Dark mode"),
                subtitle: dark ? Translation.tr("Dark") : Translation.tr("Light"),
                active: dark,
                available: true
            }
        }
        case "blur": {
            const on = Boolean(Config.options?.background?.effects?.enableBlur ?? false)
            return {
                id: "blur",
                icon: "blur_on",
                label: Translation.tr("Wallpaper blur"),
                subtitle: on ? Translation.tr("On") : Translation.tr("Off"),
                active: on,
                available: true
            }
        }
        case "companion": {
            const on = Boolean(Config.options?.abyss?.companion?.enabled ?? false)
            return {
                id: "companion",
                icon: "water_drop",
                label: Translation.tr("Companion"),
                subtitle: on ? Translation.tr("Active") : Translation.tr("Off"),
                active: on,
                available: true
            }
        }
        case "dnd": {
            const on = Boolean(Notifications.silent)
            return {
                id: "dnd",
                icon: on ? "notifications_off" : "notifications",
                label: Translation.tr("Do not disturb"),
                subtitle: on ? Translation.tr("Silent") : Translation.tr("Alerts on"),
                active: on,
                available: true
            }
        }
        case "wifi": {
            const on = Boolean(Network.wifiEnabled)
            const ssid = String(Network.networkName ?? "").trim()
            return {
                id: "wifi",
                icon: on ? "wifi" : "wifi_off",
                label: Translation.tr("Wi-Fi"),
                subtitle: on ? (ssid.length > 0 ? ssid : Translation.tr("On")) : Translation.tr("Off"),
                active: on,
                available: true
            }
        }
        case "bluetooth": {
            const avail = Boolean(BluetoothStatus.available)
            const on = avail && Boolean(BluetoothStatus.enabled)
            return {
                id: "bluetooth",
                icon: on ? "bluetooth" : "bluetooth_disabled",
                label: Translation.tr("Bluetooth"),
                subtitle: !avail ? Translation.tr("Unavailable") : (on ? Translation.tr("On") : Translation.tr("Off")),
                active: on,
                available: avail
            }
        }
        case "keepAwake": {
            const on = Boolean(Idle.inhibit)
            return {
                id: "keepAwake",
                icon: on ? "coffee" : "bedtime",
                label: Translation.tr("Keep awake"),
                subtitle: on ? Translation.tr("Inhibited") : Translation.tr("Normal"),
                active: on,
                available: true
            }
        }
        case "gameMode": {
            const on = Boolean(GameMode.active)
            return {
                id: "gameMode",
                icon: "sports_esports",
                label: Translation.tr("Game mode"),
                subtitle: on ? Translation.tr("Active") : Translation.tr("Off"),
                active: on,
                available: true
            }
        }
        case "dockAutoHide": {
            const pinned = Boolean(Config.options?.dock?.pinnedOnStartup ?? false)
            const autoHide = !pinned
            return {
                id: "dockAutoHide",
                icon: "call_to_action",
                label: Translation.tr("Dock auto-hide"),
                subtitle: autoHide ? Translation.tr("Auto-hide") : Translation.tr("Pinned"),
                active: autoHide,
                available: true
            }
        }
        default:
            return {
                id: tileId,
                icon: "tune",
                label: tileId,
                subtitle: "",
                active: false,
                available: true
            }
        }
    }

    function triggerTile(tileId: string): void {
        switch (tileId) {
        case "darkMode": {
            const nextDark = !(Appearance.m3colors?.darkmode ?? true)
            Quickshell.execDetached([
                Directories.wallpaperSwitchScriptPath,
                "--mode", nextDark ? "dark" : "light",
                "--noswitch"
            ])
            break
        }
        case "blur":
            Config.setNestedValue("background.effects.enableBlur", !(Config.options?.background?.effects?.enableBlur ?? false))
            break
        case "companion":
            Config.setNestedValue("abyss.companion.enabled", !(Config.options?.abyss?.companion?.enabled ?? false))
            break
        case "dnd":
            Notifications.silent = !Notifications.silent
            break
        case "wifi":
            Network.toggleWifi()
            break
        case "bluetooth":
            if (BluetoothStatus.available)
                BluetoothStatus.toggle()
            break
        case "keepAwake":
            Idle.toggleInhibit()
            break
        case "gameMode":
            GameMode.toggle()
            break
        case "dockAutoHide":
            Config.setNestedValue("dock.pinnedOnStartup", Boolean(Config.options?.dock?.pinnedOnStartup ?? false) ? false : true)
            break
        }
    }
}
