pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// Internal implementation - loaded dynamically by PolkitService.qml
// Do NOT use directly, use PolkitService singleton instead
Scope {
    id: root
    property alias agent: polkitAgent
    property alias active: polkitAgent.isActive
    property alias flow: polkitAgent.flow
    property bool authFailed: false
    property int failureCount: 0
    readonly property bool interactionAvailable: Boolean(root.flow?.isResponseRequired)

    onFlowChanged: {
        root.authFailed = false
        root.failureCount = 0
    }

    function cancel() {
        root.authFailed = false
        root.failureCount = 0
        if (!root.flow)
            return
        root.flow.cancelAuthenticationRequest()
    }

    function submit(string) {
        if (!root.flow)
            return
        root.authFailed = false
        root.flow.submit(string)
    }

    function selectIdentity(identity) {
        if (!root.flow || !identity)
            return
        root.authFailed = false
        root.failureCount = 0
        root.flow.selectedIdentity = identity
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed(): void {
            root.authFailed = true
            root.failureCount += 1
        }
        function onAuthenticationSucceeded(): void {
            root.authFailed = false
            root.failureCount = 0
        }
    }

    PolkitAgent {
        id: polkitAgent
        onAuthenticationRequestStarted: {
            root.authFailed = false
            root.failureCount = 0
        }
    }
}
