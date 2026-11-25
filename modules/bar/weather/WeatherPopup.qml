import QtQuick
import qs.modules.bar

StyledPopup {
    id: root

    Item {
        id: popupContent
        implicitWidth: weatherContent.implicitWidth
        implicitHeight: weatherContent.implicitHeight
        width: parent ? Math.max(implicitWidth, parent.width) : implicitWidth
        height: parent ? Math.max(implicitHeight, parent.height) : implicitHeight

        WeatherPopupContent {
            id: weatherContent
            anchors.fill: parent
            verticalLayout: root._attachmentVertical
            // The presentation window spans the owning output. Responsive sizing
            // stays on the active StyledPopup path instead of a retired perimeter
            // weather surface.
            compact: (root.presentationWindow?.width ?? 1920) < weatherContent.compactBreakpoint
        }
    }
}
