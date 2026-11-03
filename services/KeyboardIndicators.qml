pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import qs.services.deferred

Singleton {
    id: root

    property list<string> capsLockPaths: []
    property list<string> numLockPaths: []
    property var _capsLockStates: ({})
    property var _numLockStates: ({})
    property string _knownLayoutName: ""
    property string _lockSource: "unknown"
    property bool _destroying: false
    property bool _numLockReliable: false
    property var _lastRawNumLockState: null
    property string lockStateDaemonPath: Quickshell.shellPath("scripts/daemon/keyboard_lock_state_daemon.py")
    readonly property string nativeDispatchPath: Quickshell.shellPath("scripts/native-dispatch")

    property bool capsLock: false
    property bool numLock: false
    property bool ready: false
    property bool touchpadOff: false
    property bool _touchpadStateKnown: false
    readonly property string touchpadConfigPath:
        Quickshell.env("HOME") + "/.config/niri/config.d/10-input-and-cursor.kdl"
    property string popupKind: ""
    property bool popupActive: false
    property string popupText: ""
    property int popupSequence: 0

    readonly property bool showPopup: Config.options?.keyboardIndicators?.showPopup ?? true
    readonly property bool showPanel: Config.options?.keyboardIndicators?.showPanel ?? true
    readonly property bool showLayoutPopup: root.showPopup && (Config.options?.keyboardIndicators?.popup?.layout ?? true)
    readonly property bool showCapsPopup: root.showPopup && (Config.options?.keyboardIndicators?.popup?.caps ?? true)
    readonly property bool showNumPopup: root.showPopup && (Config.options?.keyboardIndicators?.popup?.num ?? false)
    readonly property bool showLayoutPanel: root.showPanel && (Config.options?.keyboardIndicators?.panel?.layout ?? true)
    readonly property bool showCapsPanel: root.showPanel && (Config.options?.keyboardIndicators?.panel?.caps ?? true)
    readonly property bool showNumPanel: root.showPanel && (Config.options?.keyboardIndicators?.panel?.num ?? false)
    readonly property bool hasMultipleLayouts: (HyprlandXkb.layoutCodes?.length ?? 0) > 1
    readonly property string currentLayoutName: HyprlandXkb.currentLayoutName ?? ""
    readonly property string currentLayoutCode: HyprlandXkb.currentLayoutCode ?? ""
    readonly property string capsMaterialIcon: "keyboard_capslock"
    readonly property string touchpadMaterialIcon: "touchpad_mouse"
    readonly property string numMaterialIcon: "dialpad"
    readonly property string capsFluentIcon: "key"
    readonly property string numFluentIcon: "keyboard-dock"
    readonly property string touchpadFluentIcon: "touchpad"
    readonly property string popupMaterialIcon:
        root.popupKind === "layout" ? "language"
        : root.popupKind === "caps" ? root.capsMaterialIcon
        : root.popupKind === "touchpad" ? root.touchpadMaterialIcon
        : root.numMaterialIcon
    readonly property string popupFluentIcon:
        root.popupKind === "layout" ? "keyboard"
        : root.popupKind === "caps" ? root.capsFluentIcon
        : root.popupKind === "touchpad" ? root.touchpadFluentIcon
        : root.numFluentIcon
    readonly property string currentLayoutCodeMultiline: root.abbreviateLayoutCode(root.currentLayoutCode, "\n")
    readonly property string currentLayoutCodeInline: root.abbreviateLayoutCode(root.currentLayoutCode, " ").toUpperCase()
    readonly property bool usingEvdev: root._lockSource === "evdev"
    readonly property bool hasKnownLedPaths:
        root.capsLockPaths.length > 0 || root.numLockPaths.length > 0
    readonly property int ledDiscoveryIntervalMs: root.hasKnownLedPaths
        ? ((Config.options?.performance?.lowPower ?? false) ? 600000 : 300000)
        : ((Config.options?.performance?.lowPower ?? false) ? 120000 : 30000)
    readonly property bool layoutVisible:
        root.showLayoutPanel &&
        root.hasMultipleLayouts &&
        root.currentLayoutCode.length > 0
    readonly property bool capsLockVisible:
        root.showCapsPanel && root.capsLock
    readonly property bool numLockVisible:
        root.showNumPanel && root.numLock
    readonly property bool touchpadVisible:
        root.showPanel && root.touchpadOff
    readonly property bool hasPanelIndicators:
        root.layoutVisible ||
        root.capsLockVisible ||
        root.numLockVisible ||
        root.touchpadVisible

    function _log(...args) {
        if (Quickshell.env("QS_DEBUG") === "1")
            console.log("[KeyboardIndicators]", ...args);
    }

    function abbreviateLayoutCode(fullCode, separator) {
        if (!fullCode || !fullCode.length)
            return "";

        return fullCode.split(":").map(layout => {
            const baseLayout = layout.split("-")[0];
            return baseLayout.slice(0, 4);
        }).join(separator);
    }

    function _parseTouchpadOff(configText): bool {
        const match = String(configText).match(
            /(?:^|\n)[ \t]*touchpad[ \t]*\{([\s\S]*?)[ \t]*\}/
        );

        if (!match)
            return false;

        return /(?:^|\n)[ \t]*off[ \t]*(?=\n|$)/.test(match[1]);
    }

    function _setTouchpadState(nextOff: bool, allowPopup: bool): void {
        const previousOff = root.touchpadOff;

        root.touchpadOff = nextOff;

        if (!root._touchpadStateKnown) {
            root._touchpadStateKnown = true;
            return;
        }

        if (allowPopup && previousOff !== nextOff)
            root.showTouchpadPopup(!nextOff);
    }

    function refreshLedPaths() {
        if (root.usingEvdev)
            return;
        if (!ledDiscoveryProc.running)
            ledDiscoveryProc.running = true;
    }

    function _setCapsLockValue(nextValue, allowPopup) {
        const previousValue = root.capsLock;
        root.capsLock = nextValue;
        if (allowPopup && previousValue !== nextValue)
            root._emitLockPopup("caps", nextValue);
    }

    function _setNumLockValue(nextValue, allowPopup) {
        const previousValue = root.numLock;
        root.numLock = nextValue;
        if (allowPopup && previousValue !== nextValue)
            root._emitLockPopup("num", nextValue);
    }

    function _setEvdevState(nextCapsValue, nextNumValue, allowPopup) {
        root._lockSource = "evdev";
        root._setCapsLockValue(nextCapsValue, allowPopup);
        root._setNumLockRawValue(nextNumValue, allowPopup);
    }

    function _handleEvdevOutput(rawLine) {
        const trimmed = String(rawLine).trim();
        if (!trimmed.length)
            return;

        try {
            const payload = JSON.parse(trimmed);
            if (payload.type !== "state")
                return;

            root._setEvdevState(Boolean(payload.caps), Boolean(payload.num), true);
        } catch (error) {
            root._log("Failed to parse evdev output", trimmed, error);
        }
    }

    function _enableSysfsFallback() {
        if (root.usingEvdev)
            return;

        root._lockSource = "sysfs";
        root.refreshLedPaths();
    }

    function _setPopup(kind, active, text) {
        if (!root.ready)
            return;

        if (kind === "layout" && !root.showLayoutPopup)
            return;

        if (kind === "caps" && !root.showCapsPopup)
            return;

        if (kind === "num" && !root.showNumPopup)
            return;

        root.popupKind = kind;
        root.popupActive = active;
        root.popupText = text;
        root.popupSequence += 1;
    }

    function _emitLockPopup(kind, active) {
        if (kind === "caps") {
            root._setPopup(kind, active, active ? Translation.tr("Caps Lock on") : Translation.tr("Caps Lock off"));
            return;
        }

        root._setPopup(kind, active, active ? Translation.tr("Num Lock on") : Translation.tr("Num Lock off"));
    }

    function showTouchpadPopup(enabled: bool): void {
        root._setPopup(
            "touchpad",
            enabled,
            enabled
                ? Translation.tr("Touchpad on")
                : Translation.tr("Touchpad off")
        );
    }

    function syncTouchpadFromIpc(state: string): void {
        const normalized = state.trim().toLowerCase();
        if (normalized !== "on" && normalized !== "off")
            return;
        touchpadConfigView.reload();
        const nextOff = normalized === "off";
        if (!root._touchpadStateKnown || root.touchpadOff !== nextOff) {
            root._touchpadStateKnown = true;
            root.touchpadOff = nextOff;
            root.showTouchpadPopup(!nextOff);
        }
    }

    function _emitLayoutPopup() {
        if (!root.hasMultipleLayouts || !root.currentLayoutName.length)
            return;

        root._setPopup("layout", true, root.currentLayoutName);
    }

    function _hasKnownState(paths, states) {
        return paths.some(path => states[path] !== null && states[path] !== undefined);
    }

    function _setLockPaths(kind, paths) {
        if (root.usingEvdev)
            return;

        const uniquePaths = [...new Set(paths)].sort();
        const previousStates = kind === "caps" ? root._capsLockStates : root._numLockStates;
        const nextStates = {};

        for (const path of uniquePaths)
            nextStates[path] = previousStates.hasOwnProperty(path) ? previousStates[path] : null;

        if (kind === "caps") {
            root.capsLockPaths = uniquePaths;
            root._capsLockStates = nextStates;
            if (!uniquePaths.length)
                root.capsLock = false;
            root._recomputeLockState(kind, false);
            return;
        }

        root.numLockPaths = uniquePaths;
        root._numLockStates = nextStates;
        if (!uniquePaths.length) {
            root._numLockReliable = false;
            root._lastRawNumLockState = null;
            root.numLock = false;
        }
        root._recomputeLockState(kind, false);
    }

    function _setLockState(kind, path, rawValue) {
        if (root.usingEvdev)
            return;

        const nextValue = Number(String(rawValue).trim()) > 0;

        if (kind === "caps") {
            root._capsLockStates = Object.assign({}, root._capsLockStates, { [path]: nextValue });
            root._recomputeLockState(kind, true);
            return;
        }

        root._numLockStates = Object.assign({}, root._numLockStates, { [path]: nextValue });
        root._recomputeLockState(kind, true);
    }

    function _clearLockState(kind, path) {
        if (root.usingEvdev)
            return;

        if (kind === "caps") {
            root._capsLockStates = Object.assign({}, root._capsLockStates, { [path]: null });
            root._recomputeLockState(kind, false);
            return;
        }

        root._numLockStates = Object.assign({}, root._numLockStates, { [path]: null });
        root._recomputeLockState(kind, false);
    }

    function _setNumLockRawValue(nextValue, allowPopup) {
        const previousVisibleValue = root._numLockReliable ? root.numLock : root._lastRawNumLockState;

        if (root._lastRawNumLockState === null) {
            root._lastRawNumLockState = nextValue;
            root._numLockReliable = !nextValue;
        } else if (nextValue !== root._lastRawNumLockState) {
            root._lastRawNumLockState = nextValue;
            root._numLockReliable = true;
        }

        root._setNumLockValue(root._numLockReliable ? nextValue : false, false);
        if (root._numLockReliable && allowPopup && previousVisibleValue !== null && previousVisibleValue !== root.numLock)
            root._emitLockPopup("num", root.numLock);
    }

    function _recomputeLockState(kind, allowPopup) {
        const paths = kind === "caps" ? root.capsLockPaths : root.numLockPaths;
        const states = kind === "caps" ? root._capsLockStates : root._numLockStates;

        let hasKnownState = paths.length === 0;
        let nextValue = false;
        for (let i = 0; i < paths.length; i++) {
            const value = states[paths[i]];
            if (value !== null && value !== undefined)
                hasKnownState = true;
            if (value === true) {
                nextValue = true;
                break;
            }
        }
        if (!hasKnownState)
            return;

        if (kind === "caps") {
            root._setCapsLockValue(nextValue, allowPopup);
            return;
        }

        if (!paths.length) {
            root._numLockReliable = false;
            root._lastRawNumLockState = null;
            root.numLock = false;
            return;
        }

        root._setNumLockRawValue(nextValue, allowPopup);
    }

    Process {
        id: evdevProbeProc
        property bool startObserved: false
        running: false
        command: [root.nativeDispatchPath, "input-lock", "--once"]

        stdout: SplitParser {
            onRead: line => root._handleEvdevOutput(line)
        }

        stderr: SplitParser {
            onRead: line => root._log("evdev probe", line)
        }

        onRunningChanged: {
            if (evdevProbeProc.running) {
                evdevProbeProc.startObserved = false;
                return;
            }
            if (evdevProbeProc.startObserved || root._destroying)
                return;

            root._log("evdev probe failed to start");
            root._enableSysfsFallback();
        }
        onStarted: evdevProbeProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                if (!evdevMonitorProc.running)
                    evdevMonitorProc.running = true;
                return;
            }

            root._log("evdev probe exited", exitCode, exitStatus);
            root._enableSysfsFallback();
        }
    }

    Timer {
        id: evdevRestartTimer
        interval: 1000
        running: false
        repeat: false
        onTriggered: {
            if (!root._destroying && root.usingEvdev && !evdevMonitorProc.running)
                evdevMonitorProc.running = true;
        }
    }

    Process {
        id: evdevMonitorProc
        property bool startObserved: false
        running: false
        command: [root.nativeDispatchPath, "input-lock"]

        stdout: SplitParser {
            onRead: line => root._handleEvdevOutput(line)
        }

        stderr: SplitParser {
            onRead: line => root._log("evdev monitor", line)
        }

        onRunningChanged: {
            if (evdevMonitorProc.running) {
                evdevMonitorProc.startObserved = false;
                return;
            }
            if (evdevMonitorProc.startObserved || root._destroying)
                return;

            root._log("evdev monitor failed to start");
            if (root.usingEvdev) {
                evdevRestartTimer.restart();
                return;
            }
            root._enableSysfsFallback();
        }
        onStarted: evdevMonitorProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            if (root._destroying)
                return;

            root._log("evdev monitor exited", exitCode, exitStatus);
            if (root.usingEvdev) {
                evdevRestartTimer.restart();
                return;
            }

            root._enableSysfsFallback();
        }
    }

    Process {
        id: ledDiscoveryProc
        running: false
        command: ["/usr/bin/bash", "-lc", "printf 'capslock\\n'; for f in /sys/class/leds/*::capslock/brightness; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done; printf 'numlock\\n'; for f in /sys/class/leds/*::numlock/brightness; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done"]

        stdout: StdioCollector {
            id: ledCollector

            onStreamFinished: {
                let section = "";
                const nextCapsPaths = [];
                const nextNumPaths = [];

                for (const rawLine of ledCollector.text.split("\n")) {
                    const line = rawLine.trim();
                    if (!line.length)
                        continue;
                    if (line === "capslock" || line === "numlock") {
                        section = line;
                        continue;
                    }
                    if (section === "capslock")
                        nextCapsPaths.push(line);
                    else if (section === "numlock")
                        nextNumPaths.push(line);
                }

                root._setLockPaths("caps", nextCapsPaths);
                root._setLockPaths("num", nextNumPaths);
            }
        }
    }

    Timer {
        id: readyTimer
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
            root.ready = true;
            root._knownLayoutName = root.currentLayoutName;
        }
    }

    Timer {
        // FileView watches known LED values directly. Keep discovery responsive
        // while no path is known, then back off once the path set is stable.
        // A watched-path load failure below triggers an immediate rescan.
        interval: root.ledDiscoveryIntervalMs
        running: !root.usingEvdev
        repeat: true
        onTriggered: root.refreshLedPaths()
    }

    Instantiator {
        model: root.capsLockPaths

        FileView {
            required property string modelData
            path: modelData
            watchChanges: true
            onFileChanged: reload()
            onLoaded: root._setLockState("caps", modelData, text())
            onLoadFailed: {
                root._clearLockState("caps", modelData)
                Qt.callLater(() => root.refreshLedPaths())
            }
        }
    }

    Instantiator {
        model: root.numLockPaths

        FileView {
            required property string modelData
            path: modelData
            watchChanges: true
            onFileChanged: reload()
            onLoaded: root._setLockState("num", modelData, text())
            onLoadFailed: {
                root._clearLockState("num", modelData)
                Qt.callLater(() => root.refreshLedPaths())
            }
        }
    }

    Connections {
        target: HyprlandXkb

        function onCurrentLayoutNameChanged() {
            if (!root.currentLayoutName.length)
                return;
            if (!root._knownLayoutName.length) {
                root._knownLayoutName = root.currentLayoutName;
                return;
            }
            if (root._knownLayoutName === root.currentLayoutName)
                return;

            root._knownLayoutName = root.currentLayoutName;
            root._emitLayoutPopup();
        }
    }

    FileView {
        id: touchpadConfigView
        path: root.touchpadConfigPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root._setTouchpadState(
                root._parseTouchpadOff(text()),
                true
            );
        }
        onLoadFailed: {
            root._log("Failed to read touchpad config:", root.touchpadConfigPath);
        }
    }

    Component.onCompleted: {
        root._knownLayoutName = root.currentLayoutName;
        evdevProbeProc.running = true;
    }

    Component.onDestruction: root._destroying = true
}
