pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.statePath
    property string fileName: "states.json"
    property string filePath: Directories.persistentStatesPath

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature
    readonly property string currentSessionSignature: {
        const niri = Quickshell.env("NIRI_SOCKET") || ""
        if (niri.length > 0)
            return "niri:" + niri
        const hypr = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        if (hypr.length > 0)
            return "hypr:" + hypr
        const xdg = Quickshell.env("XDG_SESSION_ID") || ""
        const wl = Quickshell.env("WAYLAND_DISPLAY") || ""
        if (xdg.length > 0 || wl.length > 0)
            return "wl:" + xdg + ":" + wl
        return ""
    }

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    }

    // writeAdapter() is async; suppress reloads triggered by our own write
    // so reload() doesn't drop the in-flight write operation.
    property bool _writeInFlight: false
    property bool _pendingReload: false
    property double _suppressSelfReloadUntilMs: 0

    function _completeWrite(): void {
        root._writeInFlight = false;
        if (root.ready) {
            root._suppressSelfReloadUntilMs = Date.now() + 250;
        }
        if (root._pendingReload) {
            root._pendingReload = false;
            fileReloadTimer.restart();
        }
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root._writeInFlight || (root.ready && fileWriteTimer.running)) {
                root._pendingReload = true;
                return;
            }
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            root._writeInFlight = true;
            if (root.ready) {
                root._suppressSelfReloadUntilMs = Date.now() + 500;
            }
            fileReloadTimer.stop();
            persistentStatesFileView.writeAdapter()
        }
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        onFileChanged: {
            if (root.ready && (root._writeInFlight || fileWriteTimer.running || Date.now() < root._suppressSelfReloadUntilMs)) {
                return;
            }
            fileReloadTimer.restart();
        }
        onAdapterUpdated: fileWriteTimer.restart()
        onSaved: {
            // FileView starts without a watched inode on a fresh installation.
            // Read back the first successful write to publish readiness and
            // establish the ordinary watch before Settings waits on it.
            if (!root.ready) root._pendingReload = true
            root._completeWrite()
        }
        onSaveFailed: error => {
            console.warn("[Persistent] Save failed:", error);
            root._completeWrite();
        }
        onLoaded: root.ready = true
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                console.log("[Persistent] File not found, creating new file.")
                // Ensure parent directory exists
                const parentDir = root.filePath.substring(0, root.filePath.lastIndexOf('/'))
                Quickshell.execDetached(["/usr/bin/mkdir", "-p", parentDir])
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""
            property string unlockedSessionSignature: ""

            property JsonObject ai: JsonObject {
                property string model: "gemini-2.5-flash"
                property real temperature: 0.5
                property string promptName: ""
                property string modelAliasesJson: "{}"
                property string companionSystemPrompt: ""
                property string companionRulesText: ""
            }

            property JsonObject aquaCheckIn: JsonObject {
                property string date: ""
                property string mood: ""
                property string energy: ""
            }

            // No task titles or note content. Updated only after a consented offer.
            property JsonObject aquaProactive: JsonObject {
                property string day: ""
                property int dailyCount: 0
                property int reminder: 0
                property int checkin: 0
                property int playful: 0
                property int unanswered: 0
                property int dismissals: 0
                property double lastNudgeMs: 0
                property list<string> reminderKeys: []
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
                property JsonObject compactGroup: JsonObject {
                    // Stable section id is authoritative. Keep tab for one-way
                    // migration from older installs whose widget indices shifted
                    // when Notifications left the compact right sidebar.
                    property string sectionId: ""
                    property int tab: 0
                }
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
            }

            property JsonObject gameMode: JsonObject {
                property bool manualActive: false
            }

            // Last observed hardware/privacy state. "Known" flags deliberately
            // separate an existing preference from schema defaults so upgrading
            // Alis never powers radios or changes mic mute on the first run.
            property JsonObject deviceState: JsonObject {
                property bool wifiKnown: false
                property bool wifiEnabled: true
                property bool bluetoothKnown: false
                property bool bluetoothEnabled: true
                property bool micKnown: false
                property bool micMuted: false
            }

            property JsonObject orbit: JsonObject {
                property list<string> stashEntries: []
            }

            property JsonObject timer: JsonObject {
                property bool pinnedToBar: false
                property int tab: 0
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property bool paused: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                    property string activeTag: "Study"
                    property list<string> tags: ["General", "Study", "Coding", "Reading"]
                    property list<string> archivedTags: []
                    property string tagColorsJson: "{}"
                    property string todayDate: ""
                    property int todayFocusSeconds: 0
                    property int todaySessions: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property bool paused: false
                    property int start: 0
                    property list<var> laps: []
                }
                property JsonObject countdown: JsonObject {
                    property bool running: false
                    property bool paused: false
                    property int start: 0
                    property int duration: 60
                }
            }

            // Settings workspace state is not user configuration. Keeping it
            // here lets page delegates unload while navigation and active editor
            // context survive page switches and standalone-window recreation.
            property JsonObject settings: JsonObject {
                property int iiPage: 0
                property int wafflePage: 0
                property string pageSections: "{}"
                property string categoryPages: "{}"
                property int themeTab: 0
                property string themeTag: ""
                property string gowallFormat: "png"
                property string gowallTheme: ""
                property string gowallEffect: "grayscale"

            }

            // Desktop-widget editor workspace state. This is transient UI
            // continuity, not user widget configuration: reopening the manager
            // should restore the tool where the user left it without adding
            // editor geometry to config.json.
            property JsonObject desktopWidgets: JsonObject {
                property real managerXRatio: 0.76
                property real managerYRatio: 0.42
                property int managerWidth: 420
                property int managerHeight: 520
                property string managerFilter: "all"
            }

            property JsonObject screenCast: JsonObject {
                property bool active: false
            }
        }
    }
}
