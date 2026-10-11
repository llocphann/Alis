pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common.functions
import qs.modules.abyss.looks
import "../../common/functions/PopupFocus.js" as PopupFocus
import qs.modules.sidebarRight.wifiNetworks
import qs.modules.sidebarRight.bluetoothDevices

// Keep the mature connection forms inside the existing Screen Edge host.
FocusScope {
    id: root
    property string kind: "wifi"
    property bool autoDismissOnIdle: true
    property bool triggerHovered: false
    property int idleDismissDelay: 650
    // The connection lists already scroll; keep their usable controls while
    // shortening the attached tray popup to ~2/3 of its previous size.
    implicitWidth: 260
    implicitHeight: 330
    property alias dialog: form.item
    readonly property bool editorFocusHeld: root.activeFocus && root.Window.active
        && PopupFocus.editableDescendant(root.Window.window?.activeFocusItem, root)
    signal closeRequested()

    function refreshIdleDismiss(): void {
        if (!root.autoDismissOnIdle || !root.enabled) {
            idleDismiss.stop()
            return
        }
        if (root.triggerHovered || popupHover.hovered || root.editorFocusHeld)
            idleDismiss.stop()
        else
            idleDismiss.restart()
    }

    function openDetails(): void {
        if (root.kind === "wifi")
            AppLauncher.launchNetworkSettings(Network.ethernet)
        else
            AppLauncher.launch("bluetooth")
        root.closeRequested()
    }

    Component.onCompleted: Qt.callLater(refreshIdleDismiss)
    onEnabledChanged: refreshIdleDismiss()
    onTriggerHoveredChanged: refreshIdleDismiss()
    onEditorFocusHeldChanged: refreshIdleDismiss()

    HoverHandler {
        id: popupHover
        onHoveredChanged: root.refreshIdleDismiss()
    }

    Timer {
        id: idleDismiss
        interval: root.idleDismissDelay
        repeat: false
        onTriggered: {
            if (root.autoDismissOnIdle && root.enabled
                    && !root.triggerHovered && !popupHover.hovered && !root.editorFocusHeld)
                root.closeRequested()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            AbyssButton {
                compact: true
                glyph: root.kind === "wifi" ? Network.materialSymbol : BluetoothStatus.activeIcon
                description: root.kind === "wifi"
                    ? (Network.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on")
                    : (BluetoothStatus.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on")
                enabled: root.kind === "wifi" || BluetoothStatus.available
                checked: root.kind === "wifi" ? Network.wifiEnabled : BluetoothStatus.enabled
                onClicked: root.kind === "wifi" ? Network.toggleWifi() : BluetoothStatus.toggle()
            }

            Item { Layout.fillWidth: true }

            AbyssButton {
                compact: true
                glyph: "refresh"
                description: root.kind === "wifi"
                    ? (Network.wifiScanning ? "Scanning Wi-Fi" : "Scan Wi-Fi")
                    : (Bluetooth.defaultAdapter?.discovering ?? false)
                        ? "Stop Bluetooth scan" : "Scan Bluetooth"
                enabled: root.kind === "wifi"
                    ? Network.wifiEnabled && !Network.wifiScanning
                    : BluetoothStatus.enabled
                onClicked: {
                    if (root.kind === "wifi") Network.rescanWifi()
                    else if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                }
            }

            AbyssButton {
                compact: true
                glyph: "settings"
                description: root.kind === "wifi" ? "Network settings" : "Bluetooth settings"
                onClicked: root.openDetails()
            }
        }

        Loader {
            id: form
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.kind === "wifi" ? wifi : bluetooth
        }
    }

    Component {
        id: wifi
        WifiDialog {
            embeddedPresentation: true
            showEmbeddedFooter: false
            show: true
            onDismiss: root.closeRequested()
        }
    }

    Component {
        id: bluetooth
        BluetoothDialog {
            embeddedPresentation: true
            showEmbeddedFooter: false
            show: true
            onDismiss: root.closeRequested()
        }
    }
}
