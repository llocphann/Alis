pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property var flickable: null
    property string edge: "top" // "top" | "bottom"
    property color fadeColor: IrisTheme.panelBg
    property int fadeExtent: 26

    readonly property bool isBottom: root.edge === "bottom"
    readonly property real distance: {
        const f = root.flickable
        if (!f || f.contentHeight === undefined || f.contentY === undefined || f.height <= 0 || f.contentHeight <= f.height + 2)
            return 0
        if (root.isBottom)
            return Math.max(0, f.contentHeight - f.height - f.contentY)
        return Math.max(0, f.contentY)
    }
    readonly property real strength: Math.max(0, Math.min(1, root.distance / 28))

    anchors.left: parent ? parent.left : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.top: (!root.isBottom && parent) ? parent.top : undefined
    anchors.bottom: (root.isBottom && parent) ? parent.bottom : undefined
    height: root.fadeExtent
    visible: root.opacity > 0.01
    opacity: root.strength
    enabled: false

    Behavior on opacity {
        enabled: IrisTheme.fastMs > 0
        NumberAnimation {
            duration: IrisTheme.fastMs
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.isBottom ? Qt.alpha(root.fadeColor, 0.0) : root.fadeColor
            }
            GradientStop {
                position: 1.0
                color: root.isBottom ? root.fadeColor : Qt.alpha(root.fadeColor, 0.0)
            }
        }
    }
}
