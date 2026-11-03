import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false
    property real contentRotation: 0
    property color contentColor: Appearance.colors.colOnLayer0
    property string pendingConnectivityKind: ""
    signal hoverPopupRequested(string kind)
    signal connectivityHoverChanged(string kind, bool hovered)
    implicitWidth: indicators.implicitWidth
    implicitHeight: indicators.implicitHeight

    Timer {
        id: connectivityHoverDelay
        interval: 300
        repeat: false
        onTriggered: {
            if (root.pendingConnectivityKind.length > 0
                    && Config.options?.panelFamily === "abyss")
                root.hoverPopupRequested(root.pendingConnectivityKind)
        }
    }

    function scheduleConnectivityPopup(kind: string, hovered: bool): void {
        root.connectivityHoverChanged(kind, hovered)
        if (!hovered) {
            if (root.pendingConnectivityKind === kind) {
                root.pendingConnectivityKind = ""
                connectivityHoverDelay.stop()
            }
            return
        }
        root.pendingConnectivityKind = kind
        connectivityHoverDelay.restart()
    }

    GridLayout {
        id: indicators
        anchors.centerIn: parent
        columns: root.vertical ? 1 : -1
        columnSpacing: 8 * Appearance.sizes.barModuleScale
        rowSpacing: 6 * Appearance.sizes.barModuleScale

        Revealer {
            vertical: root.vertical
            reveal: Audio.sink?.audio?.muted ?? false
            MaterialSymbol {
                text: "volume_off"
                iconSize: Math.round(Appearance.font.pixelSize.larger * Appearance.sizes.barModuleScale)
                rotation: -root.contentRotation
                color: root.contentColor
            }
        }
        Revealer {
            vertical: root.vertical
            reveal: Audio.micMuted
            MaterialSymbol {
                text: "mic_off"
                iconSize: Math.round(Appearance.font.pixelSize.larger * Appearance.sizes.barModuleScale)
                rotation: -root.contentRotation
                color: root.contentColor
            }
        }
        HyprlandXkbIndicator {
            vertical: root.vertical
            rotation: -root.contentRotation
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            color: root.contentColor
        }
        Revealer {
            vertical: root.vertical
            reveal: Notifications.silent || Notifications.unread > 0
            NotificationUnreadCount {
                rotation: -root.contentRotation
                indicatorColor: root.contentColor
            }
        }
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: Math.round(Appearance.font.pixelSize.larger * Appearance.sizes.barModuleScale)
            rotation: -root.contentRotation
            color: root.contentColor

            HoverHandler {
                id: wifiHover
                onHoveredChanged: {
                    if (hovered) Network.refreshActiveNetworkDetails()
                    root.scheduleConnectivityPopup("wifi", hovered)
                }
            }
            StyledToolTip {
                extraVisibleCondition: wifiHover.hovered
                    && Config.options?.panelFamily !== "abyss"
                text: {
                    if (!Network.wifiEnabled)
                        return Translation.tr("Wi-Fi is disabled")
                    if (Network.ethernet)
                        return Translation.tr("Ethernet connected")
                    if (!Network.networkName)
                        return Translation.tr("Not connected")
                    const connected = Translation.tr("Connected to %1").arg(Network.networkName)
                    const details = Network.accessPointDetails(Network.active, true)
                    return details.length > 0 ? `${connected} | ${details}` : connected
                }
            }
        }
        MaterialSymbol {
            visible: BluetoothStatus.available
            text: BluetoothStatus.activeIcon
            iconSize: Math.round(Appearance.font.pixelSize.larger * Appearance.sizes.barModuleScale)
            rotation: -root.contentRotation
            color: root.contentColor

            HoverHandler {
                id: btHover
                onHoveredChanged: root.scheduleConnectivityPopup("bluetooth", hovered)
            }
            StyledToolTip {
                extraVisibleCondition: btHover.hovered
                    && Config.options?.panelFamily !== "abyss"
                text: BluetoothStatus.connectionTooltip()
            }
        }
    }
}
