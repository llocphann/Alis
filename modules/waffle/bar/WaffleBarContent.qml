pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.bar.tasks
import qs.modules.waffle.bar.tray

Rectangle {
    id: root

    readonly property var panelScreen: root.QsWindow?.window?.screen ?? null
    readonly property real panelScale: Looks.barScale(panelScreen)
    readonly property bool barAtBottom: Config.options?.waffles?.bar?.bottom ?? false
    color: Looks.colors.bg0
    clip: true
    implicitHeight: Looks.scaledBar(48, panelScreen)

    property Item contextMenuSource: null
    property rect contextMenuRect: Qt.rect(0, 0, 1, 1)

    // Right-click context menu. Keep the full Bar MouseArea as the output/source
    // authority and pass only the click point as tangent placement geometry.
    MouseArea {
        id: barContextArea
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        hoverEnabled: true
        z: -1  // Below other elements so they can handle their own right-clicks
        onClicked: (mouse) => {
            root.contextMenuSource = barContextArea
            root.contextMenuRect = Qt.rect(mouse.x, mouse.y, 1, 1)
            taskbarContextMenu.active = true
        }
    }

    BarMenu {
        id: taskbarContextMenu
        anchorItem: root.contextMenuSource ?? root
        anchorRect: root.contextMenuRect
        anchorHovered: root.contextMenuSource?.containsMouse ?? false
        closeOnHoverLostDelay: 500  // Slower close to give time to click

        model: [
            {
                iconName: "pulse",
                text: Translation.tr("Task Manager"),
                action: () => {
                    Session.launchTaskManager()
                }
            },
            { type: "separator" },
            {
                iconName: "settings",
                text: Translation.tr("Taskbar settings"),
                action: () => {
                    Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"])
                }
            }
        ]
    }

    Rectangle {
        id: border
        anchors {
            left: parent.left
            right: parent.right
            top: root.barAtBottom ? parent.top : undefined
            bottom: root.barAtBottom ? undefined : parent.bottom
        }
        color: Looks.colors.bg0Border
        implicitHeight: 1
    }

    BarGroupRow {
        id: bloatRow
        anchors.left: parent.left
        opacity: (Config.options?.waffles?.bar?.leftAlignApps ?? false) ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            animation: NumberAnimation { duration: Looks.transition.enabled ? Looks.transition.duration.normal : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Looks.transition.easing.bezierCurve.standard }
        }

        WeatherButton {}
    }

    BarGroupRow {
        id: appsRow
        anchors.left: undefined
        anchors.horizontalCenter: parent.horizontalCenter

        states: State {
            name: "left"
            when: Config.options?.waffles?.bar?.leftAlignApps ?? false
            AnchorChanges {
                target: appsRow
                anchors.left: parent.left
                anchors.horizontalCenter: undefined
            }
        }

        transitions: Transition {
            AnchorAnimation { duration: Looks.transition.enabled ? Looks.transition.duration.medium : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Looks.transition.easing.bezierCurve.standard }
        }

        StartButton {}
        SearchButton {}
        TaskViewButton {}
        WTaskbarSeparator { }
        Tasks {}
    }

    BarGroupRow {
        id: systemRow
        anchors.right: parent.right
        FadeLoader {
            Layout.fillHeight: true
            shown: Config.options?.waffles?.bar?.leftAlignApps ?? false
            sourceComponent: WeatherButton {}
        }
        Tray {}
        TimerButton {}
        UpdatesButton {}
        SystemButton {}
        TimeButton {}
        DesktopPeekButton {}
    }

    component BarGroupRow: RowLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0
    }
}
