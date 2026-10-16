pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.services

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property bool _initialized: false
    property bool _historyReady: false
    property var _pendingIngress: []
    // Guard against re-entrant discardNotification calls (server dismiss → onNotificationChanged → discard again)
    property var _discardingIds: new Set()

    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        if (!notif) {
            console.warn("[Notifications] notifToJSON called with null notification")
            return null
        }
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        const json = notifToJSON(notif)
        return json ? JSON.stringify(json, null, 2) : "{}"
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        property double deadline: Date.now() + interval
        property real remainingMs: interval
        property var hoverOwners: []
        onRunningChanged: if (running) deadline = Date.now() + interval
        function pauseFor(owner): void {
            if (!owner || hoverOwners.includes(owner)) return
            if (hoverOwners.length === 0) {
                remainingMs = Math.min(interval, Math.max(1, deadline - Date.now()))
                stop()
            }
            hoverOwners = hoverOwners.concat([owner])
        }
        function resumeFor(owner): void {
            if (!hoverOwners.includes(owner)) return
            hoverOwners = hoverOwners.filter(candidate => candidate !== owner)
            if (hoverOwners.length === 0) {
                interval = Math.max(1, remainingMs)
                start()
            }
        }
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            if (index === -1) {
                console.warn("[Notifications] Timer triggered for non-existent notification ID: " + notificationId);
                destroy()
                return
            }
            const notifObject = root.list[index];
            root._log("[Notifications] Timer triggered for ID: " + notificationId + ", transient: " + notifObject.isTransient);
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
        }
    }

    // Estado de silencio / "No molestar" - synced with config
    property bool silent: false

    function toggleSilent(): void {
        silent = !silent
    }

    function _syncSilentFromConfig(): void {
        const configSilent = Config.options?.notifications?.silent ?? false
        if (root.silent !== configSilent)
            root.silent = configSilent
    }

    Connections {
        target: Config
        function onOptionsChanged() {
            root._syncSilentFromConfig()
        }
        function onReadyChanged() {
            if (Config.ready)
                root._syncSilentFromConfig()
        }
    }

    onSilentChanged: {
        if (Config.ready) {
            const configSilent = Config.options?.notifications?.silent ?? false
            if (configSilent !== silent) {
                Config.setNestedValue("notifications.silent", silent)
            }
        }
    }

    // Unread count: computed from popupList (new) or manual counter (legacy)
    property int _manualUnreadCounter: 0
    readonly property int unread: (Config.options?.notifications?.useLegacyCounter ?? false)
                                    ? _manualUnreadCounter
                                    : popupList.length

    property var filePath: Directories.notificationsPath
    // Use the stable QtObject base type here. Inline component type identities
    // are regenerated by QML hot reload; list<Notif> can reject otherwise valid
    // wrappers that survive across the handoff between engine generations.
    property list<QtObject> list: []
    // Cached lists - updated via debounce timer
    property var popupList: []
    property var _cachedGroupsByAppName: ({})
    property var _cachedPopupGroupsByAppName: ({})
    property var _cachedAppNameList: []
    property var _cachedPopupAppNameList: []
    property bool _groupsDirty: true

    // Quiet hours: suppress popups inside a daily window. Notifications still
    // arrive and land in the history, they just don't pop up.
    function _parseHourMinute(value): int {
        const parts = String(value ?? "").match(/^(\d{1,2}):(\d{2})$/)
        if (!parts) return -1
        const hours = parseInt(parts[1], 10)
        const minutes = parseInt(parts[2], 10)
        if (hours > 23 || minutes > 59) return -1
        return hours * 60 + minutes
    }

    readonly property bool quietHoursActive: {
        if (!(Config.options?.notifications?.quietHours?.enable ?? false)) return false
        const start = root._parseHourMinute(Config.options?.notifications?.quietHours?.start ?? "22:00")
        const end = root._parseHourMinute(Config.options?.notifications?.quietHours?.end ?? "08:00")
        if (start < 0 || end < 0 || start === end) return false
        const now = DateTime.clock.date
        const minutes = now.getHours() * 60 + now.getMinutes()
        // A window whose end is before its start wraps past midnight.
        return start < end
            ? (minutes >= start && minutes < end)
            : (minutes >= start || minutes < end)
    }

    // Keep the reasons separate. Manual DND is persisted user intent; quiet
    // hours and GameMode are derived policy; an open notification surface is
    // presentation state. Callers can explain the real cause without making a
    // temporary game suppression look like DND was switched on.
    readonly property bool manualDndActive: silent
    readonly property bool gameModeSuppressionActive:
        (GameMode?.active ?? false) && (GameMode?.suppressNotifications ?? false)
    readonly property bool notificationSurfaceOpen:
        (GlobalStates?.notificationCenterOpen ?? false)
        || (GlobalStates?.waffleNotificationCenterOpen ?? false)
    readonly property bool notificationPolicyActive:
        manualDndActive || quietHoursActive || gameModeSuppressionActive
    readonly property string notificationPolicyReason: manualDndActive ? "dnd"
        : quietHoursActive ? "quietHours"
        : gameModeSuppressionActive ? "gameMode"
        : ""
    readonly property bool popupInhibited:
        notificationSurfaceOpen || notificationPolicyActive
    property var latestTimeForApp: ({})

    // Entering any quiet policy dismisses popups already on screen. The
    // notifications stay in history; opening the history itself is deliberately
    // excluded because it is presentation state, not a policy change.
    onNotificationPolicyActiveChanged: {
        if (notificationPolicyActive)
            root.timeoutAll()
    }
    // Debounce timer for group updates - 100ms is sufficient for responsive UI
    Timer {
        id: groupUpdateTimer
        interval: 100
        onTriggered: root._updateGroups()
    }
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        const records = []
        list.forEach((notif) => {
            const json = notifToJSON(notif)
            if (json !== null)
                records.push(json)
        })
        return JSON.stringify(records, null, 2)
    }

    onListChanged: {
        root._groupsDirty = true
        groupUpdateTimer.restart()
    }

    function _updateGroups() {
        if (!_groupsDirty) return
        _groupsDirty = false

        // Update popupList
        root.popupList = root.list.filter((notif) => notif.popup)

        // Update latest time for each app
        const newLatestTime = Object.create(null)
        root.list.forEach((notif) => {
            if (!newLatestTime[notif.appName] || notif.time > newLatestTime[notif.appName]) {
                newLatestTime[notif.appName] = notif.time
            }
        })
        root.latestTimeForApp = newLatestTime

        // Update groups
        root._cachedGroupsByAppName = _groupsForListOptimized(root.list)
        root._cachedPopupGroupsByAppName = _groupsForListOptimized(root.popupList)
        root._cachedAppNameList = _appNameListForGroups(root._cachedGroupsByAppName)
        root._cachedPopupAppNameList = _appNameListForGroups(root._cachedPopupGroupsByAppName)
    }

    function _groupsForListOptimized(list) {
        // DBus appName is an untrusted free-form string. Plain object maps
        // inherit constructor/toString/__proto__, causing an invalid group
        // lookup and TypeError when a legitimate app uses one of those names.
        // Null-prototype maps retain the existing dictionary API and sorting.
        const groups = Object.create(null)
        for (let i = 0; i < list.length; i++) {
            const notif = list[i]
            const appName = notif.appName
            if (!groups[appName]) {
                groups[appName] = {
                    appName: appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0,
                    hasCritical: false  // Pre-calculate hasCritical
                }
            }
            groups[appName].notifications.push(notif)
            groups[appName].time = root.latestTimeForApp[appName] || notif.time
            // Wrappers store urgency as a string, while real notifications
            // can expose the enum. Accept both forms consistently with
            // NotificationItem, including the common lowercase "critical".
            const urgency = notif.urgency
            if (urgency === NotificationUrgency.Critical
                    || String(urgency ?? "").toLowerCase() === "critical") {
                groups[appName].hasCritical = true
            }
        }
        return groups
    }

    function _appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => groups[b].time - groups[a].time)
    }

    // Notification appName ("Spotify") and compositor appId ("spotify-launcher")
    // rarely match verbatim; compare on alphanumerics only.
    function _normalizeAppKey(name): string {
        return String(name ?? "").toLowerCase().replace(/[^a-z0-9]/g, "")
    }

    // App names whose group has at least one notification matching the query,
    // in the same order as appNameList. Empty query returns everything.
    function appNamesMatching(query): var {
        const needle = String(query ?? "").trim().toLowerCase()
        if (needle.length === 0) return root.appNameList
        const groups = root.groupsByAppName
        return root.appNameList.filter(appName => {
            if (appName.toLowerCase().includes(needle)) return true
            const notifications = groups[appName]?.notifications ?? []
            return notifications.some(notif =>
                (notif.summary ?? "").toLowerCase().includes(needle)
                || (notif.body ?? "").toLowerCase().includes(needle))
        })
    }

    // Unread notifications held for an app. Counts only popup (unread)
    // notifications, so the dock badge clears when the popup expires or
    // when the user activates the app via markReadForApp.
    function countForApp(identifiers): int {
        const keys = (identifiers ?? []).map(root._normalizeAppKey).filter(k => k.length > 0)
        if (keys.length === 0) return 0
        const groups = root.popupGroupsByAppName
        // The Dock passes both the compositor appId and desktop-entry name.
        // Notifications from the same app may have arrived under *either*
        // identity, so stopping at the first matching app-name group makes
        // its unread badge smaller than the entries markReadForApp clears.
        let total = 0
        for (const appName in groups) {
            if (keys.indexOf(root._normalizeAppKey(appName)) !== -1)
                total += (groups[appName].notifications?.length ?? 0)
        }
        return total
    }

    function markReadForApp(identifiers) {
        const keys = (identifiers ?? []).map(root._normalizeAppKey).filter(k => k.length > 0)
        if (keys.length === 0) return
        let changed = false
        root.list.forEach((notif) => {
            if (notif.popup && keys.indexOf(root._normalizeAppKey(notif.appName)) !== -1) {
                cancelTimeout(notif.notificationId)
                notif.popup = false
                changed = true
            }
        })
        if (changed) triggerListChange()
    }

    // Public API - use cached values
    property var groupsByAppName: _cachedGroupsByAppName
    property var popupGroupsByAppName: _cachedPopupGroupsByAppName
    property var appNameList: _cachedAppNameList
    property var popupAppNameList: _cachedPopupAppNameList

    // Rate limiting sencillo para evitar spam de notificaciones
    property double _lastIngressSec: 0
    property int _ingressCountThisSec: 0
    property int maxIngressPerSecond: 20

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

    function _nowSec() {
        return Date.now() / 1000.0;
    }

    function _ingressAllowed(notification) {
        const t = _nowSec();
        if (t - _lastIngressSec >= 1.0) {
            _lastIngressSec = t;
            _ingressCountThisSec = 0;
        }
        _ingressCountThisSec += 1;

        if (notification.urgency === NotificationUrgency.Critical)
            return true;

        return _ingressCountThisSec <= maxIngressPerSecond;
    }

    function _timeoutForNotification(notification) {
        const ignoreApp = Config.options?.notifications?.ignoreAppTimeout ?? false;
        // Max popup lifetime: even "persistent" notifications leave the popup after this.
        // 0 = no cap (honor app's request to stay forever). Default 30s.
        const maxLifetime = Config.options?.notifications?.maxPopupLifetime ?? 30000;

        // 1) App defines an explicit timeout (> 0): respect it unless ignoring
        if (!ignoreApp && notification.expireTimeout > 0) {
            return notification.expireTimeout;
        }

        // 2) expireTimeout == 0 => "never expire" per freedesktop spec
        if (!ignoreApp && notification.expireTimeout === 0) {
            return maxLifetime;
        }

        // 3) Defaults by urgency (use enum comparison, not fragile toString)
        if (notification.urgency === NotificationUrgency.Low) {
            return Config.options?.notifications?.timeoutLow ?? 5000;
        } else if (notification.urgency === NotificationUrgency.Critical) {
            const critTimeout = Config.options?.notifications?.timeoutCritical ?? 0;
            return (critTimeout === 0 && maxLifetime > 0) ? maxLifetime : critTimeout;
        }

        // Normal / unknown
        return Config.options?.notifications?.timeoutNormal ?? 7000;
    }

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            // Filter out niri screenshot notifications (TaskView preview captures)
            if (notification.appName === "niri" &&
                (notification.summary?.toLowerCase().includes("screenshot") ||
                 notification.body?.toLowerCase().includes("screenshot"))) {
                return;
            }

            if (!_ingressAllowed(notification)) {
                return;
            }

            notification.tracked = true
            const receivedAt = Date.now()
            if (!root._historyReady) {
                // Keep the tracked native object alive while its persisted ID
                // offset is resolved. No popup may be replaced by hydration.
                root._pendingIngress = root._pendingIngress.concat([{notification, receivedAt}])
                root.ensureInitialized()
                return
            }
            root._publishNotification(notification, receivedAt)
        }
    }

    function _finishHistory(maxId): void {
        if (root._historyReady) return
        root.idOffset = maxId
        root._historyReady = true
        const pending = root._pendingIngress
        root._pendingIngress = []
        for (const entry of pending)
            if (entry.notification) root._publishNotification(entry.notification, entry.receivedAt)
        root.initDone()
    }

    function _publishNotification(notification, receivedAt): void {
        const newNotifObject = notifComponent.createObject(root, {
            "notificationId": notification.id + root.idOffset,
            "notification": notification,
            "time": receivedAt,
        });
        if (!newNotifObject) {
            console.warn("[Notifications] Failed to create notification wrapper")
            return
        }
        root.list = [...root.list, newNotifObject];

        // Optional notification sound
        if ((Config.options?.sounds?.notifications ?? true) && !root.silent
                && notification.hints?.["suppress-sound"] !== true) {
            Audio.playEvent(notification.urgency === NotificationUrgency.Critical
                ? "notificationCritical" : "notification");
        }

        // Popup
        if (!root.popupInhibited) {
            newNotifObject.popup = true;

            const timeout = _timeoutForNotification(notification);
            if (timeout !== 0) {
                newNotifObject.timer = notifTimerComponent.createObject(root, {
                    "notificationId": newNotifObject.notificationId,
                    "interval": timeout,
                });
            }

            // Legacy mode: increment manual counter
            if (Config.options?.notifications?.useLegacyCounter ?? false) {
                root._manualUnreadCounter++;
            }
        }
        root.notify(newNotifObject);
        // console.log(notifToString(newNotifObject));
        notifFileView.setText(stringifyList(root.list));
    }

    function markAllRead() {
        // The legacy switch changes how unread is counted, not which
        // notifications are marked read. Previously it cleared only the
        // numeric counter and left old popups + active timers on-screen.
        if (Config.options?.notifications?.useLegacyCounter ?? false)
            root._manualUnreadCounter = 0;

        let changed = false;
        // The live list is authoritative; popupList is a delayed group cache.
        root.list.forEach((notif) => {
            if (notif && notif.popup) {
                root.cancelTimeout(notif.notificationId);
                notif.popup = false;
                changed = true;
            }
        });
        if (changed)
            triggerListChange();
    }

    function discardNotification(id) {
        // Guard against re-entrant calls (server dismiss → onNotificationChanged → discard again)
        if (root._discardingIds.has(id)) return;
        root._discardingIds.add(id);

        root._log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (index !== -1) {
            const notif = root.list[index];
            // Cancel and destroy the timer to prevent orphaned timer fires
            if (notif.timer) {
                notif.timer.stop();
                notif.timer.destroy();
                notif.timer = null;
            }
            root.list.splice(index, 1);
            notifFileView.setText(stringifyList(root.list));
            triggerListChange();
            // Destroy the Notif QML object to prevent memory leak
            notif.destroy();
        }
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal

        // Remove from re-entrancy guard after dismiss chain completes
        Qt.callLater(() => root._discardingIds.delete(id));
    }

    function discardAllNotifications() {
        // Cancel and destroy all active timers before clearing the list
        for (const notif of root.list) {
            if (notif.timer) {
                notif.timer.stop();
                notif.timer.destroy();
                notif.timer = null;
            }
            notif.destroy();
        }
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (index !== -1 && root.list[index] != null && root.list[index].timer != null) {
            root.list[index].timer.stop();
            root.list[index].timer.destroy();
            root.list[index].timer = null;
        }
    }

    function pauseTimeout(id, owner): void {
        root.list.find(notif => notif.notificationId === id)?.timer?.pauseFor(owner)
    }

    function resumeTimeout(id, owner): void {
        root.list.find(notif => notif.notificationId === id)?.timer?.resumeFor(owner)
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        root.cancelTimeout(id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        triggerListChange();
        root.timeout(id);
    }

    function timeoutAll() {
        // popupList is debounced for group rendering and may be 100 ms behind
        // the actual list. A quiet-policy/center transition in that window
        // must still dismiss freshly arrived popups without deleting history.
        // Snapshot the live wrappers so signal observers cannot change the
        // set while we process the existing timeout/hover lifecycle.
        const livePopups = root.list.filter(notif => notif && notif.popup);
        livePopups.forEach(notif => {
            root.cancelTimeout(notif.notificationId);
            root.timeout(notif.notificationId);
        });
        livePopups.forEach(notif => {
            notif.popup = false;
        });
        if (livePopups.length > 0)
            triggerListChange();
    }

    function _isViewLikeAction(text): bool {
        const t = String(text ?? "").toLowerCase();
        return t === "view" || t === "open" || t === "show" || t === "go" ||
               t === "ver" || t === "abrir" || t === "mostrar" || t === "ir" ||
               t.includes("view") || t.includes("open") || t.includes("show") ||
               t.includes("abrir") || t.includes("ver") || t.includes("mostrar");
    }

    function _focusOrLaunchFromNotifServerNotif(notifServerNotif): void {
        if (!notifServerNotif) return;

        const appName = String(notifServerNotif.appName ?? "");
        const appIcon = String(notifServerNotif.appIcon ?? "");
        const summary = String(notifServerNotif.summary ?? "");

        const patterns = [appIcon, appName, summary]
            .filter(s => s && s.length > 0)
            .map(s => s.toLowerCase());

        if (CompositorService.isNiri) {
            for (const w of (NiriService.windows ?? [])) {
                const wAppId = String(w.app_id ?? "").toLowerCase();
                const wTitle = String(w.title ?? "").toLowerCase();
                if (patterns.some(p => wAppId.includes(p) || wTitle.includes(p))) {
                    NiriService.focusWindow(w.id);
                    return;
                }
            }
        }

        for (const tl of (ToplevelManager.toplevels?.values ?? [])) {
            const tlAppId = String(tl.appId ?? "").toLowerCase();
            const tlTitle = String(tl.title ?? "").toLowerCase();
            if (patterns.some(p => tlAppId.includes(p) || tlTitle.includes(p))) {
                if (tl.activate) tl.activate();
                return;
            }
        }

        const lookupKeys = [appIcon, appName]
            .filter(s => s && s.length > 0);
        for (const key of lookupKeys) {
            const de = DesktopEntries.heuristicLookup(key);
            if (de) {
                AppSearch.launchEntry(de);
                return;
            }
        }

        if (appIcon && appIcon.length > 0) {
            const cmd = "/usr/bin/gtk-launch \"" + appIcon + "\" || \"" + appIcon + "\"";
            ShellExec.execCmd(cmd);
        }
    }

    function attemptInvokeAction(id, notifIdentifier) {
        _log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        _log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif?.actions?.find((action) => action.identifier === notifIdentifier);

            if (action) {
                action.invoke()
                if (root._isViewLikeAction(action.text)) {
                    root._focusOrLaunchFromNotifServerNotif(notifServerNotif)
                }
            } else {
                console.warn("[Notifications] Action not found: " + notifIdentifier)
            }
        }
        else {
            _log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root._groupsDirty = true
        root._updateGroups()
    }

    function refresh() {
        notifFileView.reload()
    }

    function ensureInitialized(): void {
        if (root._initialized)
            return;
        root._initialized = true;
        root.refresh()
    }

    // Enviar algunas notificaciones de prueba para previsualizar posición/sonido
    function sendTestNotifications() {
        const tests = [
            {
                summary: "Notification Position Test",
                body: "ii test notification 1 of 3 ~ Hi there!",
                icon: "preferences-system"
            },
            {
                summary: "Second Test",
                body: "ii notification 2 of 3 ~ Check it out!",
                icon: "applications-graphics"
            },
            {
                summary: "Third Test",
                body: "ii notification 3 of 3 ~ Enjoy!",
                icon: "face-smile"
            }
        ];

        for (let i = 0; i < tests.length; ++i) {
            const t = tests[i];
            Quickshell.execDetached([
                "/usr/bin/notify-send",
                "-h", "int:transient:1",
                "-a", "Quickshell ii",
                "-i", t.icon,
                t.summary,
                t.body,
            ]);
        }
    }

    IpcHandler {
        target: "notifications"

        function test(): void {
            root.sendTestNotifications()
        }

        function clearAll(): void {
            root.discardAllNotifications()
        }

        function toggleSilent(): void {
            root.silent = !root.silent
        }
    }

    Component.onCompleted: {
        // Lazy: load persistent notifications only when a UI needs them.
        // Initialize silent from config when Config is already available.
        if (Config.ready)
            root._syncSilentFromConfig()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            // FileView also emits loaded after our own setText writes. History
            // is hydrated once; those completions must preserve live wrappers,
            // timer identities, hover holds and the session's native ID offset.
            if (root._historyReady) return
            const fileContents = notifFileView.text()
            let records
            try {
                records = JSON.parse(fileContents)
                if (!Array.isArray(records)) throw new Error("Expected a notification array")
            } catch (error) {
                console.warn("[Notifications] Invalid history: " + error)
                root._finishHistory(0)
                return
            }
            root.list = records.map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": notif.image,
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            }).filter(notif => notif !== null);
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            _log("[Notifications] File loaded")
            root._finishHistory(maxId)
        }
        onLoadFailed: (error) => {
            if (root._historyReady) return
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                // Ensure parent directory exists
                const parentDir = root.filePath.substring(0, root.filePath.lastIndexOf('/'))
                Quickshell.execDetached(["/usr/bin/mkdir", "-p", parentDir])
                root.list = []
                notifFileView.setText(stringifyList(root.list));
                root._finishHistory(0)
            } else {
                console.log("[Notifications] Error loading file: " + error)
                root._finishHistory(0)
            }
        }
    }
}
