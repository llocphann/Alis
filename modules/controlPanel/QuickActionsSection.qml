pragma ComponentBehavior: Bound
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

PanelSurface {
    id: root
    islandSkin: (Config.options?.controlPanel?.style ?? "panel") === "island"
    Layout.fillWidth: true
    implicitHeight: actionsGrid.implicitHeight + 16
    readonly property bool compactMode: Config.options?.controlPanel?.compactMode ?? true

    elevation: 1
    radiusOverride: islandSkin ? -1 : Appearance.rounding.normal

    GridLayout {
        id: actionsGrid
        anchors.fill: parent
        anchors.margins: root.compactMode ? 6 : 8
        columns: 4
        rowSpacing: root.compactMode ? 4 : 6
        columnSpacing: rowSpacing

        ActionTile {
            icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            accessibleName: Audio.sink?.audio?.muted
                ? Translation.tr("Unmute audio") : Translation.tr("Mute audio")
            active: !(Audio.sink?.audio?.muted ?? false)
            onClicked: Audio.toggleMute()
        }

        ActionTile {
            icon: Audio.micMuted ? "mic_off" : "mic"
            accessibleName: Audio.micMuted
                ? Translation.tr("Unmute microphone") : Translation.tr("Mute microphone")
            active: !Audio.micMuted
            onClicked: Audio.toggleMicMute()
        }

        ActionTile {
            icon: "notifications"
            accessibleName: Notifications.silent
                ? Translation.tr("Unmute notifications") : Translation.tr("Mute notifications")
            active: !Notifications.silent
            onClicked: Notifications.silent = !Notifications.silent
        }

        ActionTile {
            icon: "dark_mode"
            accessibleName: Appearance.m3colors.darkmode
                ? Translation.tr("Switch to light mode") : Translation.tr("Switch to dark mode")
            active: Appearance.m3colors.darkmode
            onClicked: Appearance.toggleDarkMode()
        }

        ActionTile {
            icon: Network.wifiEnabled ? "wifi" : "wifi_off"
            accessibleName: Network.wifiEnabled
                ? Translation.tr("Disable Wi-Fi") : Translation.tr("Enable Wi-Fi")
            active: Network.wifiEnabled
            onClicked: Network.toggleWifi()
        }

        ActionTile {
            visible: BluetoothStatus.available
            icon: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            accessibleName: BluetoothStatus.enabled
                ? Translation.tr("Disable Bluetooth") : Translation.tr("Enable Bluetooth")
            active: BluetoothStatus.enabled
            onClicked: BluetoothStatus.toggle()
        }

        ActionTile {
            icon: "coffee"
            accessibleName: Idle.inhibit ? Translation.tr("Allow sleep") : Translation.tr("Keep awake")
            active: Idle.inhibit
            onClicked: Idle.toggleInhibit()
        }

        ActionTile {
            icon: "sports_esports"
            accessibleName: GameMode.active
                ? Translation.tr("Disable game mode") : Translation.tr("Enable game mode")
            active: GameMode.active
            onClicked: GameMode.toggle()
        }

        ActionTile {
            icon: "screenshot_monitor"
            accessibleName: Translation.tr("Take screenshot")
            onClicked: {
                GlobalStates.controlPanelOpen = false
                GlobalStates.openRegionScreenshot()
            }
        }

        ActionTile {
            icon: "settings"
            accessibleName: Translation.tr("Open settings")
            onClicked: {
                GlobalStates.controlPanelOpen = false
                Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"])
            }
        }

        ActionTile {
            icon: "lock"
            accessibleName: Translation.tr("Lock screen")
            onClicked: {
                GlobalStates.controlPanelOpen = false
                Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "lock", "activate"])
            }
        }

        ActionTile {
            icon: "power_settings_new"
            accessibleName: Translation.tr("Open power menu")
            iconColor: Appearance.colors.colError
            onClicked: {
                GlobalStates.controlPanelOpen = false
                GlobalStates.sessionOpen = true
            }
        }
    }

    component ActionTile: Rectangle {
        id: tile

        property string icon
        required property string accessibleName
        property bool active: false
        property color iconColor: active
            ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: root.compactMode ? 30 : 36
        radius: Appearance.rounding.small
        color: tileMouseArea.containsMouse
            ? (active ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover)
            : (active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2)
        border.width: 0
        border.color: "transparent"

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        MaterialSymbol {
            z: 1
            anchors.centerIn: parent
            text: tile.icon
            iconSize: root.compactMode ? 16 : 18
            color: tile.iconColor

            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: tileMouseArea.activeFocus
            color: "transparent"
            radius: tile.radius
            border.width: 2
            border.color: Appearance.colors.colPrimary
            z: 2
        }

        MouseArea {
            id: tileMouseArea
            anchors.fill: parent
            hoverEnabled: true
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: tile.accessibleName
            Accessible.focusable: true
            Accessible.onPressAction: tile.clicked()
            Keys.onPressed: event => {
                if (event.isAutoRepeat
                        || (event.key !== Qt.Key_Return
                            && event.key !== Qt.Key_Enter
                            && event.key !== Qt.Key_Space))
                    return
                tile.clicked()
                event.accepted = true
            }
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }
}
