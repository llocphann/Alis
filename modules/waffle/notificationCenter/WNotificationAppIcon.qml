import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

Item {
    id: root

    property string icon: ""
    property real implicitSize: 16
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    ThemedIcon {
        anchors.fill: parent
        implicitWidth: root.implicitSize
        implicitHeight: root.implicitSize

        source: root.icon || fallback
        fallback: `${Looks.iconsPath}/apps.svg`
        roundToIconSize: true
        isMask: !root.icon
        color: Looks.colors.fg
    }
}
