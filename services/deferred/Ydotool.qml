pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root
    readonly property string _nativeDispatch: Quickshell.shellPath("scripts/native-dispatch")
    property int shiftMode: 0 // 0: off, 1: on, 2: lock
    property list<int> shiftKeys: [42, 54] // Keycodes for Shift keys (left and right)
    property list<int> altKeys: [56, 100] // Keycodes for Alt keys (left and right) 
    property list<int> ctrlKeys: [29, 97] // Keycodes for Ctrl keys (left and right)
    property var _pendingLines: []
    property bool _sessionStarted: false

    // Persistent Wayland zwp_virtual_keyboard_v1 session so held modifiers
    // (Shift / Caps / Ctrl / Alt / Super) persist across separate key taps.
    Process {
        id: vkSession
        running: false
        stdinEnabled: true
        command: [root._nativeDispatch, "input-session"]
        onStarted: {
            root._sessionStarted = true
            const queued = root._pendingLines
            root._pendingLines = []
            for (let i = 0; i < queued.length; ++i)
                vkSession.write(queued[i] + "\n")
        }
        onExited: {
            root._sessionStarted = false
            root._pendingLines = []
        }
    }

    Timer {
        id: idleCloseTimer
        interval: 100
        repeat: false
        onTriggered: vkSession.running = false
    }

    Timer {
        id: idleShutdown
        interval: 60000
        repeat: false
        onTriggered: {
            if (root._sessionStarted && vkSession.running) {
                vkSession.write("release_all\nquit\n")
                idleCloseTimer.restart()
            } else {
                vkSession.running = false
            }
        }
    }

    function _sendSessionLine(line: string): void {
        idleCloseTimer.stop()
        idleShutdown.restart()
        if (root._sessionStarted && vkSession.running) {
            vkSession.write(line + "\n")
        } else {
            root._pendingLines.push(line)
            vkSession.running = true
        }
    }

    function releaseAllKeys() {
        if (root._sessionStarted && vkSession.running) {
            vkSession.write("release_all\n")
        } else {
            root._pendingLines = []
        }
        root.shiftMode = 0; // Reset shift mode
    }

    function releaseShiftKeys() {
        if ((root._sessionStarted && vkSession.running) || root._pendingLines.length > 0) {
            for (let i = 0; i < root.shiftKeys.length; ++i)
                root._sendSessionLine(`release ${root.shiftKeys[i]}`)
        }
        root.shiftMode = 0; // Reset shift mode
    }

    Component.onDestruction: {
        idleShutdown.stop()
        idleCloseTimer.stop()
        if (root._sessionStarted && vkSession.running)
            vkSession.write("release_all\nquit\n")
        root._sessionStarted = false
        vkSession.running = false
    }

    function press(keycode) {
        root._sendSessionLine(`press ${keycode}`)
    }

    function release(keycode) {
        root._sendSessionLine(`release ${keycode}`)
    }
}
