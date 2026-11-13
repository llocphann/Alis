pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services

// One native screencopy session per process. In particular, Qt/Wayland capture
// teardown never runs inside the long-lived Alis shell process.
ShellRoot {
    id: root
    readonly property int ticket: Number(Quickshell.env("ALIS_COLOR_PICKER_TICKET"))
    property bool done: false
    property bool readyNotified: false
    readonly property var overlays: windows.instances
    function complete(status: string, value: string, message: string): void {
        if (done) return
        done = true
        console.info("ALIS_COLOR_PICKER_RESULT " + JSON.stringify({
            ticket: ticket, status: status, value: value, message: message }))
        quitTimer.restart()
    }
    function notifyReady(): void {
        if (done || readyNotified || overlays.length === 0 || !overlays.every(view => view.ready)) return
        readyNotified = true
        console.info("ALIS_COLOR_PICKER_RESULT " + JSON.stringify({ticket: ticket, status: "ready"}))
    }
    // Exit outside native input delivery, including keyboard release events.
    Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }
    Component.onCompleted: {
        Quickshell.watchFiles = false
        if (ticket <= 0 || Quickshell.screens.length === 0)
            complete("failed", "", "No screens available")
    }
    Variants {
        id: windows
        model: Quickshell.screens
        delegate: ColorPickerOverlay {
            required property var modelData
            screen: modelData
            requestId: root.ticket
            onReadyChanged: root.notifyReady()
            onPicked: (ticket, value) => root.complete("picked", value, "")
            onCancelled: ticket => root.complete("cancelled", "", "")
            onFailed: (ticket, message) => root.complete("failed", "", message)
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (Quickshell.screens.length === 0)
                root.complete("failed", "", "No screens available")
        }
    }
}
