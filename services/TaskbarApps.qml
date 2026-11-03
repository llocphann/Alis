pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

Singleton {
    id: root

    readonly property bool sortingEnabled:
        (Config.options?.panelFamily ?? "ii") === "waffle"
    property int _identityRulesRevision: 0

    Connections {
        target: Config.options?.windows
        function onAppIdentityRulesChanged() {
            root._identityRulesRevision++
            refreshApps.restart()
        }
    }

    function syncSortingDemand(): void {
        CompositorService.setSortingConsumer("waffleTaskbar",
            root.sortingEnabled)
    }

    onSortingEnabledChanged: syncSortingDemand()
    Component.onCompleted: { syncSortingDemand(); refreshApps.restart() }
    Component.onDestruction:
        CompositorService.setSortingConsumer("waffleTaskbar", false)

    function _stringArray(value): var {
        // Config exposes QML list<string>, which is a sequence but not a JS Array.
        if (!value || typeof value === "string"
                || !Number.isInteger(value.length) || value.length < 0)
            return []
        const result = Array.from(value, item => String(item ?? "").trim())
        let writeCount = 0
        for (let i = 0; i < result.length; i++) {
            const item = result[i]
            if (item.length > 0)
                result[writeCount++] = item
        }
        result.length = writeCount
        return result
    }

    function _compileRegexes(patterns): var {
        const result = []
        for (const pattern of patterns) {
            try {
                result.push(new RegExp(pattern, "i"))
            } catch (error) {
                console.warn("[TaskbarApps] Ignoring invalid app regex:", pattern)
            }
        }
        return result
    }

    function togglePin(appId) {
        const normalized = String(appId ?? "").trim()
        if (normalized.length === 0)
            return

        const key = normalized.toLowerCase()
        const pinned = root._stringArray(Config.options?.dock?.pinnedApps)
        const exists = pinned.some(id => id.toLowerCase() === key)
        const next = exists
            ? pinned.filter(id => id.toLowerCase() !== key)
            : pinned.concat([normalized])
        Config.setNestedValue(["dock", "pinnedApps"], next)
    }

    property list<var> apps: []
    // Resolve identity/cache dependencies outside a property binding. Lazy
    // AppSearch and compositor enrichment may emit changes during resolution;
    // coalescing them avoids re-entering the public apps binding.
    Timer { id: refreshApps; interval: 16; repeat: false; onTriggered: root.apps = root.computeApps() }
    Connections { target: CompositorService; function onSortedToplevelsChanged(): void { refreshApps.restart() } }
    Connections { target: ToplevelManager.toplevels; function onValuesChanged(): void { refreshApps.restart() } }
    Connections { target: AppSearch; function onListChanged(): void { refreshApps.restart() } }
    Connections {
        target: Config.options?.dock
        function onPinnedAppsChanged(): void { refreshApps.restart() }
        function onIgnoredAppRegexesChanged(): void { refreshApps.restart() }
    }
    Connections { target: Config; function onOptionsChanged(): void { refreshApps.restart() }
        function onReadyChanged(): void { refreshApps.restart() } }
    function computeApps(): var {
        const identityRulesRevision = root._identityRulesRevision;
        var map = new Map();
        let hasResolvedPinnedApps = false;

        // Pinned apps
        const pinnedApps = root._stringArray(Config.options?.dock?.pinnedApps);
        for (const appId of pinnedApps) {
            // Skip pinned apps with no desktop entry installed
            if (!AppSearch.lookupDesktopEntry(appId))
                continue;
            hasResolvedPinnedApps = true;
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (hasResolvedPinnedApps) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

        // Ignored apps
        const ignoredRegexStrings = root._stringArray(Config.options?.dock?.ignoredAppRegexes);
        const systemIgnored = [
            "^$", "^portal$", "^x-run-dialog$", "^kdialog$",
            "^org.freedesktop.impl.portal.*"
        ];
        const ignoredRegexes = root._compileRegexes(ignoredRegexStrings.concat(systemIgnored));

        // Niri's event stream is authoritative. CompositorService enriches
        // live foreign-toplevel handles with exact Niri ids and drops stale
        // handles instead of letting ghost apps survive in the taskbar.
        const sorted = CompositorService.sortedToplevels ?? [];
        const sourceToplevels = CompositorService.isNiri
            ? sorted
            : (sorted.length > 0
                ? sorted
                : (ToplevelManager.toplevels?.values ?? []));

        // Open windows
        for (const toplevel of sourceToplevels) {
            const appId = AppSearch.resolveWindowIdentity(toplevel);
            if (appId.length === 0 || ignoredRegexes.some(re => re.test(appId)))
                continue;
            let lowerAppId = appId.toLowerCase();
            if (!map.has(lowerAppId)) {
                const winDesktopId = String(AppSearch.lookupDesktopEntry(appId)?.id ?? "").trim().toLowerCase();
                if (winDesktopId.length > 0) {
                    for (const [pinnedKey] of map) {
                        if (pinnedKey === "SEPARATOR") continue;
                        const pinnedDesktopId = String(AppSearch.lookupDesktopEntry(pinnedKey)?.id ?? "").trim().toLowerCase();
                        if (pinnedDesktopId.length > 0 && pinnedDesktopId === winDesktopId) {
                            lowerAppId = pinnedKey;
                            break;
                        }
                    }
                }
            }
            if (!map.has(lowerAppId)) map.set(lowerAppId, ({
                pinned: false,
                toplevels: []
            }));
            map.get(lowerAppId).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push({
                appId: key,
                toplevels: value.toplevels,
                pinned: value.pinned
            });
        }

        return values;
    }

}
