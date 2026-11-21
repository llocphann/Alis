pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common.functions
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    // False until nmcli has returned a real radio state. Persistence must never
    // treat the declaration default as a boot-time observation.
    property bool wifiStateKnown: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    // Gated on being *connected*, not on the radio being powered. wifiStatus is
    // only ever "connecting"/"disconnected" while the radio is on — i.e. while
    // wifiEnabled is true — so keying the strength icons off wifiEnabled both
    // rendered a stale full-strength icon after disconnecting and left the
    // "not_connected"/"wifi_find" branches permanently unreachable.
    property string materialSymbol: root.ethernet
        ? "lan"
        : !root.wifiEnabled
            ? "signal_wifi_off"
            : (root.wifiStatus === "connected" || root.wifiStatus === "limited")
                ? (
                    Network.networkStrength > 83 ? "signal_wifi_4_bar" :
                    Network.networkStrength > 67 ? "network_wifi" :
                    Network.networkStrength > 50 ? "network_wifi_3_bar" :
                    Network.networkStrength > 33 ? "network_wifi_2_bar" :
                    Network.networkStrength > 17 ? "network_wifi_1_bar" :
                    "signal_wifi_0_bar"
                )
                : (root.wifiStatus === "connecting")
                    ? "signal_wifi_statusbar_not_connected"
                    : (root.wifiStatus === "disconnected")
                        ? "wifi_find"
                        : (root.wifiStatus === "disabled")
                            ? "signal_wifi_off"
                            : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.attempted = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function refreshActiveNetworkDetails(): void {
        if (!getNetworks.running) {
            getNetworks.running = true;
        }
    }

    function openPublicWifiPortal() {
        ShellExec.execDetachedArgs(["xdg-open", "https://nmcheck.gnome.org/"], "Open network check") // From some StackExchange thread, seems to work
    }

    function accessPointDetails(accessPoint, includeBssid = false): string {
        if (!accessPoint) return "";
        const details = [];
        if (accessPoint.strength >= 0)
            details.push(`${accessPoint.strength}%`);
        if (accessPoint.bandLabel.length > 0) {
            details.push(accessPoint.frequency > 0
                ? `${accessPoint.bandLabel} (${accessPoint.frequency} MHz)`
                : accessPoint.bandLabel);
        }
        if (accessPoint.rate.length > 0)
            details.push(accessPoint.rate);
        if (includeBssid && accessPoint.bssid.length > 0)
            details.push(accessPoint.bssid);
        return details.join(" | ");
    }

    function connectionTooltip(includeBssid = false): string {
        if (!root.wifiEnabled) return Translation.tr("Wi-Fi is disabled");
        if (root.ethernet) return Translation.tr("Ethernet connected");
        if (!root.networkName) return Translation.tr("Not connected");
        const details = root.accessPointDetails(root.active, includeBssid);
        return details.length > 0 ? `${root.networkName} | ${details}` : root.networkName;
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        // changePasswordProc.onExited re-runs connectProc, whose own onExited has
        // already nulled the target — restore it so the retry can report back.
        root.wifiConnectTarget = network;
        changePasswordProc.exec({
            "command": ["nmcli", "connection", "modify", network.ssid, "wifi-sec.psk", password]
        })
    }

    Process {
        id: enableWifiProc
        onExited: root.update()
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required") && root.wifiConnectTarget) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Guarded: this handler nulls the target, and changePasswordProc re-runs
            // connectProc, so a password retry lands here a second time.
            if (!root.wifiConnectTarget) return;
            root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    Process {
        id: rescanProcess
        property bool attempted: false
        property bool startObserved: false
        property bool timedOut: false
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        onRunningChanged: {
            if (rescanProcess.running) {
                rescanProcess.startObserved = false
                return
            }
            if (!rescanProcess.attempted || rescanProcess.startObserved)
                return
            rescanTimeout.stop()
            rescanProcess.attempted = false
            root.wifiScanning = false
            console.warn("[Network] Failed to start Wi-Fi rescan")
        }
        onStarted: {
            rescanProcess.startObserved = true
            rescanProcess.timedOut = false
            rescanTimeout.restart()
        }
        onExited: (exitCode) => {
            rescanTimeout.stop()
            rescanProcess.attempted = false
            root.wifiScanning = false
            if (rescanProcess.timedOut) {
                console.warn("[Network] Timed out while rescanning Wi-Fi")
                return
            }
            if (exitCode === 0)
                getNetworks.running = true
        }
    }

    Timer {
        id: rescanTimeout
        interval: 30000
        repeat: false
        onTriggered: {
            if (!rescanProcess.running)
                return
            rescanProcess.timedOut = true
            rescanProcess.running = false
        }
    }

    // Debounce timer for network status updates
    Timer {
        id: _updateDebounce
        interval: 450
        repeat: false
        onTriggered: root._doUpdate()
    }

    // Status update (debounced — nmcli monitor can emit rapid bursts)
    function update() {
        _updateDebounce.restart();
    }

    // Actual update logic
    function _doUpdate() {
        updateConnectionType.startCheck()
    }

    property bool _destroying: false
    property double _subscriberStartedMs: 0
    property int _subscriberBackoffMs: 2000

    function _wifiNetworkKey(network): string {
        if (!network)
            return ""
        return String(network.frequency ?? "") + "\u0000"
            + String(network.ssid ?? "") + "\u0000"
            + String(network.bssid ?? "")
    }

    function _startSubscriber(): void {
        if (!root._destroying && !subscriber.running)
            subscriber.running = true
    }

    function _scheduleSubscriberRestart(): void {
        if (root._subscriberStartedMs > 0 && (Date.now() - root._subscriberStartedMs) > 10000)
            root._subscriberBackoffMs = 2000
        else
            root._subscriberBackoffMs = Math.min(60000, root._subscriberBackoffMs * 2)
        if (!root._destroying)
            subscriberRestart.restart()
    }

    Component.onCompleted: {
        root._startSubscriber()
        // Prime initial state once; subsequent updates come from nmcli monitor.
        Qt.callLater(() => root.update())
    }

    Component.onDestruction: {
        root._destroying = true;
        subscriberRestart.stop()
        subscriber.running = false;
    }

    Timer {
        id: subscriberRestart
        interval: root._subscriberBackoffMs
        repeat: false
        onTriggered: root._startSubscriber()
    }

    Process {
        id: subscriber
        property bool startObserved: false
        running: false
        command: ["nmcli", "monitor"]
        // Restart through a delay rather than directly from runningChanged. If
        // nmcli cannot start or NetworkManager makes the monitor exit instantly,
        // an inline restart would otherwise turn into a process-spawn loop.
        onRunningChanged: {
            if (subscriber.running) {
                subscriber.startObserved = false
                return
            }
            if (root._destroying || subscriber.startObserved)
                return
            console.warn("[Network] Failed to start nmcli monitor; retrying")
            root._scheduleSubscriberRestart()
        }
        onStarted: {
            subscriber.startObserved = true
            root._subscriberStartedMs = Date.now()
        }
        onExited: root._scheduleSubscriberRestart()
        stdout: SplitParser {
            onRead: line => {
                const s = String(line ?? "").trim().toLowerCase()
                if (!s)
                    return
                if (s.includes("connected") || s.includes("connecting")
                        || s.includes("unavailable") || s.includes("connectivity")
                        || s.includes("primary") || s.includes("enabled")
                        || s.includes("disabled") || s.includes("removed")
                        || s.includes("using connection")) {
                    root.update()
                }
            }
        }
    }

    Process {
        id: updateConnectionType
        property string buffer
        // LANG=C: nmcli localizes device STATE ("connected" → "conectado" etc.), and the
        // parser below matches English keywords. Without this, wifi state detection silently
        // fails on non-English desktops — indicator shows disconnected while actually connected.
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g && nmcli radio wifi"]
        running: false
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // Keep radio state available even if the combined status query
                // fails part-way through.
                if (!wifiStatusProcess.running)
                    wifiStatusProcess.running = true
                return
            }

            const lines = updateConnectionType.buffer.trim().split('\n');
            const radioState = lines.pop()
            const connectivity = lines.pop() // none, limited, full
            if (radioState === "enabled" || radioState === "disabled") {
                root.wifiEnabled = radioState === "enabled"
                root.wifiStateKnown = true
            }

            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                const separator = line.indexOf(":");
                if (separator < 0)
                    return;

                const type = line.slice(0, separator);
                const state = line.slice(separator + 1);
                const connected = state === "connected" || state.startsWith("connected ");

                if (type === "ethernet" && connected)
                    hasEthernet = true;
                else if (type === "wifi") {
                    if (state === "disconnected") {
                        wifiStatus = "disconnected"
                    }
                    else if (connected) {
                        hasWifi = true;
                        wifiStatus = "connected"

                        if (connectivity === "limited") {
                            hasWifi = false;
                            wifiStatus = "limited"
                        }
                    }
                    else if (state.startsWith("connecting")) {
                        wifiStatus = "connecting"
                    }
                    else if (state === "unavailable") {
                        wifiStatus = "disabled"
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;
            // updateNetworkStrength's awk prints nothing when no AP is in use, so
            // its SplitParser never fires and networkStrength would keep the value
            // from the last connected AP. Clear it here instead.
            const hasActiveLink = hasEthernet || wifiStatus === "connected" || wifiStatus === "limited"
            if (hasActiveLink) {
                if (!updateNetworkName.running)
                    updateNetworkName.running = true
            } else {
                root.networkName = ""
            }

            if (wifiStatus === "connected" || wifiStatus === "limited") {
                if (!updateNetworkStrength.running)
                    updateNetworkStrength.running = true
            } else {
                root.networkStrength = 0
            }
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.networkName = text.trim()
        }
    }

    Process {
        id: updateNetworkStrength
        running: false
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser {
            onRead: data => {
                root.networkStrength = parseInt(data);
            }
        }
    }

    Process {
        id: wifiStatusProcess
        // Failure-only fallback. Normal status updates include radio state in
        // updateConnectionType so they do not spawn this extra process.
        command: ["nmcli", "radio", "wifi"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim()
                if (state !== "enabled" && state !== "disabled")
                    return
                root.wifiEnabled = state === "enabled"
                root.wifiStateKnown = true
            }
        }
    }

    Process {
        id: getNetworks
        running: false
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY,RATE", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || "",
                        rate: net[6] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;
                const existingByKey = new Map()
                for (let i = 0; i < rNetworks.length; ++i)
                    existingByKey.set(root._wifiNetworkKey(rNetworks[i]), rNetworks[i])

                const nextKeys = new Set()
                for (let i = 0; i < wifiNetworks.length; ++i)
                    nextKeys.add(root._wifiNetworkKey(wifiNetworks[i]))

                // Remove stale QObject rows in one reverse pass. This avoids the
                // old filter(find()) + indexOf reconciliation, which became O(n²)
                // in dense Wi-Fi environments.
                for (let i = rNetworks.length - 1; i >= 0; --i) {
                    const existing = rNetworks[i]
                    const key = root._wifiNetworkKey(existing)
                    if (nextKeys.has(key))
                        continue
                    rNetworks.splice(i, 1)
                    existingByKey.delete(key)
                    existing.destroy()
                }

                for (let i = 0; i < wifiNetworks.length; ++i) {
                    const network = wifiNetworks[i]
                    const key = root._wifiNetworkKey(network)
                    const match = existingByKey.get(key)
                    if (match) {
                        match.lastIpcObject = network
                    } else {
                        const created = apComp.createObject(root, {
                            lastIpcObject: network
                        })
                        rNetworks.push(created)
                        existingByKey.set(key, created)
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
