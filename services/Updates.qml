pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    function _nonNegativeInt(value, fallback: int): int {
        const parsed = Number(value)
        return Number.isFinite(parsed) && parsed >= 0
            ? Math.max(0, Math.round(parsed)) : fallback
    }

    property bool available: false
    property int count: 0
    readonly property int checkIntervalMinutes: {
        const configured = Number(Config.options?.updates?.checkInterval)
        return Number.isFinite(configured) && configured > 0
            ? Math.max(1, Math.round(configured)) : 120
    }
    readonly property int adviseUpdateThreshold: root._nonNegativeInt(
        Config.options?.updates?.adviseUpdateThreshold, 75)
    readonly property int stronglyAdviseUpdateThreshold: root._nonNegativeInt(
        Config.options?.updates?.stronglyAdviseUpdateThreshold, 200)
    
    readonly property bool updateAdvised: available && count > root.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > root.stronglyAdviseUpdateThreshold

    function load() {}
    function refresh() {
        // Starting the real checker is also the availability probe: a successful
        // spawn proves pacman-contrib/checkupdates exists, so a separate
        // command-v shell process would only duplicate startup work.
        if (checkUpdatesProc.running) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: root.checkIntervalMinutes * 60 * 1000
        repeat: true
        running: Config.ready
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Timer {
        id: availabilityDefer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) availabilityDefer.start()
        }
    }

    Component.onCompleted: {
        if (Config.ready) availabilityDefer.start()
    }

    Process {
        id: checkUpdatesProc
        property bool startObserved: false
        property bool timedOut: false
        command: [Quickshell.shellPath("scripts/native-dispatch"), "check-updates"]

        onRunningChanged: {
            if (checkUpdatesProc.running) {
                checkUpdatesProc.startObserved = false
                return
            }
            if (checkUpdatesProc.startObserved)
                return

            updateCheckTimeout.stop()
            root.count = 0
            root.available = false
            console.warn("[Updates] Failed to start checkupdates")
        }

        onStarted: {
            checkUpdatesProc.startObserved = true
            checkUpdatesProc.timedOut = false
            root.available = true
            updateCheckTimeout.restart()
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const t = (text ?? "").trim();
                root.count = t.length > 0 ? t.split("\n").length : 0;
            }
        }
        onExited: (exitCode, exitStatus) => {
            updateCheckTimeout.stop()
            if (checkUpdatesProc.timedOut) {
                root.count = 0
                console.warn("[Updates] Timed out checking for system updates")
                return
            }
            // pacman-contrib checkupdates uses exit 2 for the normal
            // "no updates available" state. Clear any stale previous count and
            // reserve error logging for genuine failures.
            if (exitCode === 2) {
                root.count = 0;
                return;
            }
            if (exitCode !== 0) {
                root.count = 0;
                console.error("[Updates] checkupdates failed", exitCode, exitStatus)
            }
        }
    }

    Timer {
        id: updateCheckTimeout
        interval: 120000
        repeat: false
        onTriggered: {
            if (!checkUpdatesProc.running)
                return
            checkUpdatesProc.timedOut = true
            checkUpdatesProc.running = false
        }
    }
}
