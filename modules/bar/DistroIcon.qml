import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id: root
    readonly property bool abyssMode:
        (Config.options?.panelFamily ?? "ii") === "abyss"
    property bool showAbyssMark: false
    property real contentRotation: 0
    signal abyssControlsHoverChanged(bool hovered)
    readonly property real markSize:
        19.5 * Appearance.sizes.barModuleScale

    implicitWidth: markSize + 10 * Appearance.sizes.barModuleScale
    implicitHeight: markSize + 10 * Appearance.sizes.barModuleScale

    Item {
        id: markViewport
        anchors.centerIn: parent
        width: root.markSize
        height: root.markSize
        rotation: -root.contentRotation
        clip: true

        Item {
            id: distroHolder
            width: markViewport.width
            height: markViewport.height
            x: root.abyssMode && root.showAbyssMark ? -width : 0

            CustomIcon {
                anchors.fill: parent
                source: (Config.options?.bar?.topLeftIcon ?? "distro") === "distro"
                    ? SystemInfo.distroIcon
                    : `${Config.options?.bar?.topLeftIcon ?? "distro"}-symbolic`
                colorize: true
                color: Appearance.colors.colOnLayer0
            }

            Behavior on x {
                enabled: root.abyssMode && AbyssStyle.motionEnabled
                NumberAnimation {
                    duration: AbyssStyle.motionNormal
                    easing.type: Easing.InOutCubic
                }
            }
        }

        Item {
            id: abyssHolder
            width: markViewport.width
            height: markViewport.height
            x: root.abyssMode
                ? (root.showAbyssMark ? 0 : width)
                : width

            MaterialSymbol {
                anchors.centerIn: parent
                text: "waves"
                iconSize: root.markSize
                color: AbyssStyle.accent
            }

            Behavior on x {
                enabled: root.abyssMode && AbyssStyle.motionEnabled
                NumberAnimation {
                    duration: AbyssStyle.motionNormal
                    easing.type: Easing.InOutCubic
                }
            }
        }
    }

    Timer {
        interval: 2800
        repeat: true
        running: root.abyssMode && root.visible && AbyssStyle.motionEnabled
            && !GlobalStates.screenLocked && (root.QsWindow.window?.visible ?? true)
        onTriggered: root.showAbyssMark = !root.showAbyssMark
    }

    HoverHandler {
        id: statusHover
        onHoveredChanged: {
            if (root.abyssMode)
                root.abyssControlsHoverChanged(hovered)
        }
    }
    Component.onDestruction: root.abyssControlsHoverChanged(false)
}
