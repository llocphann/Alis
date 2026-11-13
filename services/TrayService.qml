pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.services.deferred
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland

Singleton {
    id: root

    property bool _xembedProxyStartRequested: false
    property bool _xembedProxyCheckedOnce: false

    property bool smartTray: Config.options?.tray?.filterPassive ?? true

    // Apps that don't implement DBus Activate properly (libappindicator issue)
    // These apps need workarounds: gtk-launch or window focus
    // matches: array of substrings to match in tray id/title OR window app_id/title
    // focusOnly: true = only focus, don't minimize (for apps that crash when minimized)
    readonly property var problematicApps: [
        { matches: ["spotify"], launch: "spotify-launcher" },
        { matches: ["discord canary", "canary"], launch: "discord-canary", focusOnly: true, fixedIcon: "discord-canary" },
        { matches: ["discord ptb", "ptb"], launch: "discord-ptb", focusOnly: true, fixedIcon: "discord-ptb" },
        { matches: ["discord", "com.discordapp.discord"], launch: "discord", focusOnly: true, fixedIcon: "discord" },
        { matches: ["vesktop", "Vesktop"], launch: "vesktop" },
        { matches: ["armcord", "ArmCord"], launch: "armcord" },
        { matches: ["slack", "Slack"], launch: "slack" },
        { matches: ["teams", "Teams"], launch: "teams-for-linux" },
        { matches: ["telegram", "Telegram", "org.telegram"], launch: "org.telegram.desktop" },
        { matches: ["signal", "Signal"], launch: "signal-desktop" },
        { matches: ["element", "Element"], launch: "element-desktop" },
        { matches: ["steam", "Steam"], launch: "steam" },
        { matches: ["skype", "Skype"], launch: "skypeforlinux" },
        { matches: ["viber", "Viber"], launch: "viber" },
        { matches: ["zoom", "Zoom"], launch: "zoom" },
        { matches: ["easyeffects", "EasyEffects", "com.github.wwmm.easyeffects"], launch: "easyeffects" },
    ]

    // Check if an item is a problematic app
    function getProblematicAppInfo(item): var {
        if (!item) return null;
        const id = (item.id ?? "").toLowerCase();
        const title = (item.title ?? "").toLowerCase();
        const tooltipTitle = (item.tooltipTitle ?? "").toLowerCase();

        // Console log for debugging
        root._log(`[TrayService] Checking problematic app: ID='${id}' Title='${title}' Tooltip='${tooltipTitle}'`);

        for (const app of problematicApps) {
            for (const pattern of app.matches) {
                const p = pattern.toLowerCase();
                if (id.includes(p) || title.includes(p) || tooltipTitle.includes(p)) {
                    return app;
                }
            }
        }
        return null;
    }

    // Check if a string matches any pattern from an app's matches array
    function matchesApp(str, app): bool {
        if (!str || !app?.matches) return false;
        const s = str.toLowerCase();
        for (const pattern of app.matches) {
            if (s.includes(pattern.toLowerCase())) return true;
        }
        return false;
    }

    // Smart activate: tries to focus existing window or launch app
    // Returns true if handled, false if should fall back to item.activate()
    function smartActivate(item): bool {
        if (!item) return false;

        const appInfo = getProblematicAppInfo(item);
        if (!appInfo) return false;  // Not a problematic app, use normal activate

        // Try to find and focus existing window using ToplevelManager
        let toplevel = null;
        for (const tl of ToplevelManager.toplevels.values) {
            const appId = (tl.appId ?? "").toLowerCase();
            const tlTitle = (tl.title ?? "").toLowerCase();
            if (matchesApp(appId, appInfo) || matchesApp(tlTitle, appInfo)) {
                toplevel = tl;
                break;
            }
        }

        if (toplevel) {
            toplevel.activate();
            return true;
        }

        // No window found - launch app (use login shell for proper PATH including ~/.local/bin)
        ShellExec.execCmd(appInfo.launch);
        return true;
    }

    // Smart toggle: click to focus existing window or launch app
    // Always focuses/activates, never closes (user expectation for tray click)
    function smartToggle(item): bool {
        if (!item) return false;

        const id = (item.id ?? "").toLowerCase();
        root._log(`[TrayService] smartToggle called for: ${id}`);
        const appInfo = getProblematicAppInfo(item);

        // Find window using ToplevelManager
        let toplevel = null;
        for (const tl of ToplevelManager.toplevels.values) {
            const appId = (tl.appId ?? "").toLowerCase();
            const tlTitle = (tl.title ?? "").toLowerCase();

            let isMatch = false;
            if (appInfo) {
                isMatch = matchesApp(appId, appInfo) || matchesApp(tlTitle, appInfo);
            } else {
                isMatch = appId.includes(id) || id.includes(appId) ||
                          tlTitle.includes(id) || appId === id;
            }

            if (isMatch) {
                root._log(`[TrayService] Match found for ${id}: ${appId} / ${tlTitle}`);
                toplevel = tl;
                break;
            }
        }

        if (toplevel) {
            toplevel.activate();
            return true;
        }

        // No window found
        if (appInfo) {
            if (appInfo.focusOnly) {
                root._log(`[TrayService] Window not found for ${id}, but focusOnly is true. Falling back to item.activate().`);
                return false; // Fallback to item.activate()
            }

            // For harmless apps (like Spotify usually), try launching to restore
            root._log(`[TrayService] Window not found for ${id}, executing launch: ${appInfo.launch}`);
            ShellExec.execCmd(appInfo.launch);
            return true;
        }

        return false;
    }

    // Filter out invalid items (null or missing id)
    function isValidItem(item) {
        return Boolean(item && String(item.id ?? "").trim().length > 0);
    }

    function _normalizeTrayMatchKey(value): string {
        const raw = String(value ?? "").trim().toLowerCase().replace(/\.desktop$/i, "")
        const stripped = /^chrome[_.-]?status[_.-]?icon/i.test(raw)
            ? raw
            : raw.replace(/^(.+?)(?:[_.-]+status[_.-]?icon[_.-]?\d+)$/i, "$1")
        return stripped.replace(/[^a-z0-9]+/g, "")
    }

    function _isGenericTrayId(idKey): bool {
        if (!idKey)
            return true
        return idKey.startsWith("chromestatusicon")
            || idKey.startsWith("statusicon")
            || idKey.startsWith("sniqt")
            || idKey.startsWith("xembed")
            || idKey.startsWith("statusnotifieritem")
            || idKey.startsWith("ayatana")
            || idKey === "systemtray"
            || idKey === "trayicon"
    }

    function getItemDedupKey(item): string {
        if (!isValidItem(item))
            return ""
        const appInfo = getProblematicAppInfo(item)
        if (appInfo && appInfo.launch)
            return "app:" + String(appInfo.launch).toLowerCase()

        const idKey = _normalizeTrayMatchKey(item.id)
        const titleKey = _normalizeTrayMatchKey(item.title)
        const tooltipKey = _normalizeTrayMatchKey(item.tooltipTitle)
        const rawIcon = String(item.icon ?? "").trim().toLowerCase()
        const iconKey = rawIcon.startsWith("image://") ? "" : rawIcon

        if (!_isGenericTrayId(idKey))
            return "id:" + idKey
        if (titleKey.length > 0)
            return "title:" + titleKey
        if (tooltipKey.length > 0)
            return "tooltip:" + tooltipKey
        if (iconKey.length > 0)
            return "icon:" + iconKey
        return "id:" + (idKey || String(item.id ?? "").trim().toLowerCase())
    }

    function _getItemAliasKeys(item): var {
        if (!isValidItem(item))
            return []
        const keys = []
        const pushUnique = key => {
            if (key.length > 0 && !keys.includes(key))
                keys.push(key)
        }

        const primary = getItemDedupKey(item)
        pushUnique(primary)

        const idKey = _normalizeTrayMatchKey(item.id)
        if (!_isGenericTrayId(idKey) && idKey.length >= 3) {
            pushUnique("id:" + idKey)
            pushUnique("key:" + idKey)
        }

        const titleKey = _normalizeTrayMatchKey(item.title)
        if (titleKey.length >= 3 && !_isGenericTrayId(titleKey)) {
            pushUnique("title:" + titleKey)
            pushUnique("key:" + titleKey)
        }

        const tooltipKey = _normalizeTrayMatchKey(item.tooltipTitle)
        if (tooltipKey.length >= 3 && !_isGenericTrayId(tooltipKey)) {
            pushUnique("tooltip:" + tooltipKey)
            pushUnique("key:" + tooltipKey)
        }

        const rawIcon = String(item.icon ?? "").trim().toLowerCase()
        const iconKey = rawIcon.startsWith("image://") ? "" : rawIcon
        const labelKey = titleKey || tooltipKey
        if (labelKey.length >= 3 && iconKey.length > 0)
            pushUnique("visual:" + labelKey + "|" + iconKey)

        return keys
    }

    function _getItemDedupRank(item): int {
        if (!isValidItem(item))
            return -1
        let rank = 0
        if (item.status !== undefined && item.status !== null && item.status !== Status.Passive)
            rank += 32
        const idKey = _normalizeTrayMatchKey(item.id)
        if (!_isGenericTrayId(idKey))
            rank += 16
        if (Array.isArray(root._pinnedItems) && root._pinnedItems.includes(item.id))
            rank += 8
        if (item.hasMenu)
            rank += 4
        if (String(item.icon ?? "").trim().length > 0)
            rank += 2
        if (String(item.tooltipTitle || item.title || "").trim().length > 0)
            rank += 1
        return rank
    }

    function _canMergeTrayEntries(existing, candidate): bool {
        if (!existing || !candidate)
            return false
        if (existing.primaryKey === candidate.primaryKey && existing.primaryKey.length > 0)
            return true
        if (existing.isGenericId || candidate.isGenericId)
            return true
        if (existing.idKey === candidate.idKey && existing.idKey.length > 0)
            return true
        if (existing.idKey.length >= 3 && candidate.idKey.length >= 3
                && (existing.idKey.endsWith(candidate.idKey) || candidate.idKey.endsWith(existing.idKey)))
            return true
        if (existing.idKey.length >= 3
                && (existing.idKey === candidate.titleKey || existing.idKey === candidate.tooltipKey))
            return true
        if (candidate.idKey.length >= 3
                && (candidate.idKey === existing.titleKey || candidate.idKey === existing.tooltipKey))
            return true
        return false
    }

    function deduplicateItems(items): var {
        if (!items || typeof items.length !== "number")
            return []
        const result = []
        const seenByKey = {}

        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (!isValidItem(item))
                continue

            const aliasKeys = _getItemAliasKeys(item)
            if (aliasKeys.length === 0)
                continue

            const idKey = _normalizeTrayMatchKey(item.id)
            const candidateMeta = {
                primaryKey: getItemDedupKey(item),
                idKey: idKey,
                isGenericId: _isGenericTrayId(idKey),
                titleKey: _normalizeTrayMatchKey(item.title),
                tooltipKey: _normalizeTrayMatchKey(item.tooltipTitle)
            }

            let existing = null
            for (let k = 0; k < aliasKeys.length; k++) {
                const found = seenByKey[aliasKeys[k]]
                if (found !== undefined && _canMergeTrayEntries(found, candidateMeta)) {
                    existing = found
                    break
                }
            }

            const candidateRank = _getItemDedupRank(item)
            if (!existing) {
                const entry = {
                    index: result.length,
                    rank: candidateRank,
                    item: item,
                    primaryKey: candidateMeta.primaryKey,
                    idKey: candidateMeta.idKey,
                    isGenericId: candidateMeta.isGenericId,
                    titleKey: candidateMeta.titleKey,
                    tooltipKey: candidateMeta.tooltipKey
                }
                result.push(item)
                for (let k = 0; k < aliasKeys.length; k++) {
                    if (seenByKey[aliasKeys[k]] === undefined)
                        seenByKey[aliasKeys[k]] = entry
                }
                continue
            }

            if (candidateRank >= existing.rank) {
                existing.item = item
                existing.rank = candidateRank
                result[existing.index] = item
                if (!candidateMeta.isGenericId) {
                    existing.idKey = candidateMeta.idKey
                    existing.isGenericId = false
                    existing.primaryKey = candidateMeta.primaryKey
                }
                if (candidateMeta.titleKey.length > 0)
                    existing.titleKey = candidateMeta.titleKey
                if (candidateMeta.tooltipKey.length > 0)
                    existing.tooltipKey = candidateMeta.tooltipKey
            }
            for (let k = 0; k < aliasKeys.length; k++) {
                if (seenByKey[aliasKeys[k]] === undefined || seenByKey[aliasKeys[k]] === existing)
                    seenByKey[aliasKeys[k]] = existing
            }
        }

        return result
    }

    function isAutostartTrayItem(item): bool {
        if (!item)
            return false
        const itemKeys = [
            _normalizeTrayMatchKey(item.id),
            _normalizeTrayMatchKey(item.title)
        ].filter(k => k.length >= 3)
        if (itemKeys.length === 0)
            return false

        const managed = Autostart.entries ?? []
        for (let i = 0; i < managed.length; i++) {
            const e = managed[i]
            if (!e || !e.enabled)
                continue
            const rawTarget = e.type === "app"
                ? String(e.desktopId ?? "")
                : String(e.command ?? "").trim().split(/\s+/)[0]
            const targetKey = _normalizeTrayMatchKey(rawTarget.split("/").pop())
            if (targetKey.length < 3)
                continue
            if (itemKeys.some(ik => ik === targetKey || ik.endsWith(targetKey) || targetKey.endsWith(ik)))
                return true
        }
        return false
    }

    property var _pinnedItems: {
        const value = Config.options?.bar?.tray?.pinnedItems ?? Config.options?.tray?.pinnedItems
        return Array.isArray(value) ? value : []
    }
    readonly property list<var> uniqueItems: deduplicateItems(SystemTray.items.values)
    property list<var> itemsInUserList: root.uniqueItems.filter(i =>
        isValidItem(i) && _pinnedItems.includes(i.id))
    property list<var> itemsNotInUserList: root.uniqueItems.filter(i =>
        isValidItem(i) && !_pinnedItems.includes(i.id)
        && (!smartTray || i.status !== Status.Passive || isAutostartTrayItem(i)))

    property bool invertPins: Config.options?.bar?.tray?.invertPinnedItems ?? Config.options?.tray?.invertPinnedItems ?? true
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getSafeIcon(item): string {
        if (!item) return "";
        const app = getProblematicAppInfo(item);
        if (app && app.fixedIcon) return Quickshell.iconPath(app.fixedIcon, "application-x-executable");
        const rawIcon = String(item.icon ?? "");
        if (rawIcon.length > 0) {
            if (rawIcon.startsWith("image://") || rawIcon.startsWith("file://") || rawIcon.startsWith("qrc:"))
                return rawIcon;
            if (rawIcon.startsWith("/"))
                return "file://" + rawIcon;
            const themed = Quickshell.iconPath(rawIcon, true);
            if (themed.length > 0)
                return themed;
        }
        const fallbackKey = String(item.id || item.title || item.tooltipTitle || "");
        if (fallbackKey.length > 0)
            return AppSearch.getIconSource(fallbackKey, "application-x-executable");
        return Quickshell.iconPath("application-x-executable", true);
    }

    function getTooltipForItem(item) {
        if (!item) return "";
        const tooltipTitle = item.tooltipTitle ?? "";
        const title = item.title ?? "";
        const id = item.id ?? "";
        const tooltipDescription = item.tooltipDescription ?? "";

        var result = tooltipTitle.length > 0 ? tooltipTitle
                : (title.length > 0 ? title : id);
        if (tooltipDescription.length > 0) result += " • " + tooltipDescription;
        if (Config.options?.tray?.showItemId) result += "\n[" + id + "]";
        return result;
    }

    // Pinning
    function pin(itemId) {
        if (!itemId) return;
        const pins = root._pinnedItems.slice();
        if (pins.includes(itemId)) return;
        pins.push(itemId);
        Config.setNestedValue("tray.pinnedItems", pins);
    }
    function unpin(itemId) {
        if (!itemId) return;
        const pins = root._pinnedItems.slice();
        Config.setNestedValue("tray.pinnedItems", pins.filter(id => id !== itemId));
    }
    function togglePin(itemId) {
        if (!itemId) return;
        const pins = root._pinnedItems;
        if (pins.includes(itemId)) {
            unpin(itemId)
        } else {
            pin(itemId)
        }
    }

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    function requestXembedProxyIfNeeded(): void {
        if (!CompositorService.isNiri)
            return;
        root.ensureXembedSniProxy();
    }

    function ensureXembedSniProxy(): void {
        if (!CompositorService.isNiri)
            return;
        if (root._xembedProxyStartRequested)
            return;
        root._xembedProxyStartRequested = true;
        xembedProxyDelayedStartTimer.restart();
    }

    Timer {
        id: xembedProxyDelayedStartTimer
        // Legacy XEmbed tray apps can publish before the proxy owns the tray
        // selection and do not necessarily register again. Keep this
        // asynchronous, but start on the next event-loop turn instead of
        // leaving a 600 ms race window.
        interval: 0
        repeat: false
        onTriggered: {
            xembedProxyCheckProc.running = false;
            xembedProxyCheckProc.running = true;
        }
    }

    Process {
        id: xembedProxyCheckProc
        property bool startObserved: false
        command: ["/usr/bin/pgrep", "-x", "xembedsniproxy"]

        onRunningChanged: {
            if (xembedProxyCheckProc.running) {
                xembedProxyCheckProc.startObserved = false;
                return;
            }
            if (xembedProxyCheckProc.startObserved)
                return;

            root._xembedProxyCheckedOnce = true;
            root._log("[xembedsniproxy] pgrep could not start; attempting proxy launch")
            xembedProxyStartProc.running = false;
            xembedProxyStartProc.running = true;
        }

        onStarted: xembedProxyCheckProc.startObserved = true

        onExited: (exitCode, exitStatus) => {
            root._xembedProxyCheckedOnce = true;
            if (exitCode !== 0) {
                xembedProxyStartProc.running = false;
                xembedProxyStartProc.running = true;
            }
        }
    }

    Process {
        id: xembedProxyStartProc
        property bool startObserved: false
        stdout: SplitParser {
            onRead: (line) => root._log("[xembedsniproxy]", line)
        }
        stderr: SplitParser {
            onRead: (line) => root._log("[xembedsniproxy]", line)
        }
        command: [
            "/usr/bin/systemd-run",
            "--user",
            "--quiet",
            "--unit=alis-xembedsniproxy",
            "--collect",
            "--service-type=exec",
            "--property=BindsTo=alis.service",
            "--property=After=alis.service",
            "--property=Restart=on-failure",
            "--property=RestartSec=1s",
            "--setenv=QT_NO_XDG_DESKTOP_PORTAL=1",
            "--setenv=QT_QPA_PLATFORM=xcb",
            "/usr/bin/xembedsniproxy"
        ]

        onRunningChanged: {
            if (xembedProxyStartProc.running) {
                xembedProxyStartProc.startObserved = false;
                return;
            }
            if (xembedProxyStartProc.startObserved)
                return;

            root._xembedProxyStartRequested = false;
            root._log("[xembedsniproxy] systemd-run could not start")
        }

        onStarted: xembedProxyStartProc.startObserved = true

        onExited: (exitCode, exitStatus) => {
            root._log("[xembedsniproxy] exited", exitCode, exitStatus)
            if (exitCode !== 0)
                root._xembedProxyStartRequested = false;
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                // Core behavior: start on Niri, but defer via timer to keep startup smooth.
                root.requestXembedProxyIfNeeded();
            }
        }
    }

    Connections {
        target: CompositorService
        function onIsNiriChanged() {
            root.requestXembedProxyIfNeeded();
        }
    }

}
