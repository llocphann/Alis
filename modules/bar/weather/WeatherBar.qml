pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    // A pointer click can retain activeFocus after hover ends. Keep popup
    // keyboard focus affordance without treating pointer focus as hover.
    property bool _pointerFocused: false
    onPressed: root._pointerFocused = true
    onActiveFocusChanged: {
        if (!root.activeFocus)
            root._pointerFocused = false
    }
    property bool vertical: false
    property real contentRotation: 0
    readonly property bool verticalContent: Math.abs(root.contentRotation) === 90
    property color foregroundColor: root.vertical
        ? Appearance.colors.colOnLayer0
        : Appearance.colors.colOnLayer1

    implicitWidth: root.vertical ? 34 * Appearance.sizes.barModuleScale
        : (root.verticalContent
            ? Math.max(38, verticalContentLayout.implicitHeight + 12 * Appearance.sizes.barModuleScale)
            : rowLayout.implicitWidth + 20 * Appearance.sizes.barModuleScale)
    implicitHeight: root.vertical ? 34 * Appearance.sizes.barModuleScale : Appearance.sizes.barHeight

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr("Weather")
    Accessible.focusable: true

    // Keyboard activation opens the existing connected Weather popup; left
    // click is hover-owned and must never route to Sidebar Right.
    function activatePrimary(): void {
        root._pointerFocused = false
        root.forceActiveFocus()
    }

    Keys.onPressed: event => {
        if (event.isAutoRepeat
                || (event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter
                    && event.key !== Qt.Key_Space))
            return
        root.activatePrimary()
        event.accepted = true
    }

    // Hover opens WeatherPopup. A left click simply keeps that same popup,
    // while the existing explicit right-click refresh remains available.
    onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            Weather.forceRefresh();
            Quickshell.execDetached(["/usr/bin/notify-send",
                Translation.tr("Weather"),
                Translation.tr("Refreshing (manually triggered)")
                , "-a", "Shell"
            ])
            return
        }
        // No sidebar or separate popup action on mouse click.
    }

    KeyboardFocusRing {
        anchors.fill: parent
        focusVisible: root.activeFocus
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        visible: !root.verticalContent
        rotation: root.verticalContent ? 0 : -root.contentRotation

        MaterialSymbol {
            fill: 0
            text: Icons.getWeatherIcon(Weather.data?.wCode, Weather.isNightNow()) ?? "cloud"
            iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
            color: root.foregroundColor
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            visible: !root.vertical
            font.pixelSize: Math.round(Appearance.font.pixelSize.small * Appearance.sizes.barModuleScale)
            color: root.foregroundColor
            text: Weather.data?.temp ?? "--°"
            Layout.alignment: Qt.AlignVCenter
        }
    }

    ColumnLayout {
        id: verticalContentLayout
        anchors.centerIn: parent
        visible: !root.vertical && root.verticalContent
        rotation: -root.contentRotation
        spacing: 2 * Appearance.sizes.barModuleScale

        MaterialSymbol {
            fill: 0
            text: Icons.getWeatherIcon(Weather.data?.wCode, Weather.isNightNow()) ?? "cloud"
            iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
            color: root.foregroundColor
            Layout.alignment: Qt.AlignHCenter
        }

        StyledText {
            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * Appearance.sizes.barModuleScale)
            color: root.foregroundColor
            text: Weather.data?.temp ?? "--°"
            Layout.alignment: Qt.AlignHCenter
        }
    }

    WeatherPopup {
        id: weatherPopup
        hoverTarget: root
        alternativeVisibleCondition: root.activeFocus && !root._pointerFocused
    }
}
