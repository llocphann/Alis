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

    // Persistent Wayland zwp_virtual_keyboard_v1 session so held modifiers
    // (Shift / Caps / Ctrl / Alt / Super) persist across separate key taps.
    Process {
        id: vkSession
        running: false
        stdinEnabled: true
        command: [root._nativeDispatch, "input-session"]
        onStarted: {
            const queued = root._pendingLines
            root._pendingLines = []
            for (let i = 0; i < queued.length; ++i)
                vkSession.write(queued[i] + "\n")
        }
        onExited: {
            root._pendingLines = []
        }
    }

    Timer {
        id: idleShutdown
        interval: 60000
        repeat: false
        onTriggered: {
            if (vkSession.running) {
                vkSession.write("release_all\nquit\n")
                vkSession.running = false
            }
        }
    }

    function _sendSessionLine(line: string): void {
        idleShutdown.restart()
        if (vkSession.running) {
            vkSession.write(line + "\n")
        } else {
            root._pendingLines.push(line)
            vkSession.running = true
        }
    }

    function releaseAllKeys() {
        if (vkSession.running) {
            vkSession.write("release_all\n")
        } else {
            root._pendingLines = []
        }
        root.shiftMode = 0; // Reset shift mode
    }

    function releaseShiftKeys() {
        if (vkSession.running || root._pendingLines.length > 0) {
            for (let i = 0; i < root.shiftKeys.length; ++i)
                root._sendSessionLine(`release ${root.shiftKeys[i]}`)
        }
        root.shiftMode = 0; // Reset shift mode
    }

    function press(keycode) {
        root._sendSessionLine(`press ${keycode}`)
    }

    function release(keycode) {
        root._sendSessionLine(`release ${keycode}`)
    }
}
