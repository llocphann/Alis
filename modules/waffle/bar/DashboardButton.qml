pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

BarButton {
    id: root
    objectName: "waffleDashboardButton"

    visible: Config.options?.dock?.showDashboardIcon ?? true
    readonly property var panelScreen: root.QsWindow?.window?.screen ?? null
    leftInset: 2
    rightInset: 2
    implicitWidth: height - topInset - bottomInset + leftInset + rightInset

    checked: GlobalStates.dashboardOpen
    onClicked: WaffleNavigation.toggleDashboard()

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: iconItem.implicitWidth
        implicitHeight: iconItem.implicitHeight
        scale: root.down ? (root.checked ? 5 / 6 : 0.9) : 1

        Behavior on scale {
            enabled: Looks.transition.enabled
            NumberAnimation {
                duration: root.down ? Looks.transition.duration.chromePress : Looks.transition.duration.chromeRelease
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.down ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut
            }
        }

        FluentIcon {
            id: iconItem
            anchors.centerIn: parent
            icon: root.checked ? "apps-filled" : "apps"
            implicitSize: Looks.scaledBar(20, root.panelScreen)
            monochrome: true
            color: root.checked ? Looks.colors.accent : Looks.colors.fg
        }
    }

    BarToolTip {
        barExtraVisibleCondition: root.shouldShowTooltip
        text: Translation.tr("Dashboard")
    }
}
