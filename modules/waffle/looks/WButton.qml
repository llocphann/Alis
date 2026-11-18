import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

// Generic button with background
Button {
    id: root

    property color colBackground: ColorUtils.transparentize(Looks.colors.bg1)
    property color colBackgroundHover: Looks.colors.interactiveSurfaceHover
    property color colBackgroundActive: Looks.colors.interactiveSurfaceActive
    property color colBackgroundToggled: Looks.colors.accent
    property color colBackgroundToggledHover: Looks.colors.accentHover
    property color colBackgroundToggledActive: Looks.colors.accentActive
    property color colForeground: Looks.colors.fg
    property color colForegroundToggled: Looks.colors.accentFg
    property color colForegroundDisabled: ColorUtils.transparentize(Looks.colors.subfg, 0.4)
    property bool animateStateChanges: true
    property alias backgroundOpacity: backgroundRect.opacity
    property color color: {
        if (!root.enabled) return colBackground;
        if (root.checked) {
            if (root.down) {
                return root.colBackgroundToggledActive;
            } else if (root.hovered) {
                return root.colBackgroundToggledHover;
            } else {
                return root.colBackgroundToggled;
            }
        }
        if (root.down) {
            return root.colBackgroundActive;
        } else if (root.hovered) {
            return root.colBackgroundHover;
        } else {
            return root.colBackground;
        }
    }
    property color fgColor: {
        if (root.checked) return root.colForegroundToggled
        if (root.enabled) return root.colForeground
        return root.colForegroundDisabled
    }
    property alias horizontalAlignment: buttonText.horizontalAlignment
    font {
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.large
        weight: Looks.font.weight.regular
    }

    // Hover stuff
    signal hoverTimedOut
    property bool shouldShowTooltip: false
    ToolTip.delay: 200
    property Timer hoverTimer: Timer {
        id: hoverTimer
        running: root.hovered
        interval: root.ToolTip.delay
        onTriggered: {
            root.hoverTimedOut();
        }
    }
    onHoverTimedOut: {
        root.shouldShowTooltip = true;
    }
    onHoveredChanged: {
        if (!root.hovered) {
            root.shouldShowTooltip = false;
            root.hoverTimer.stop();
        }
    }

    property alias monochromeIcon: buttonIcon.monochrome
    property alias buttonSpacing: contentLayout.spacing
    property bool forceShowIcon: false
    property real iconLeftMargin: 0
    property bool centerContent: false

    property var altAction: () => {}
    property var middleClickAction: () => {}

    property real inset: 0
    topInset: inset
    bottomInset: inset
    leftInset: inset
    rightInset: inset
    property alias radius: backgroundRect.radius
    property alias topLeftRadius: backgroundRect.topLeftRadius
    property alias topRightRadius: backgroundRect.topRightRadius
    property alias bottomLeftRadius: backgroundRect.bottomLeftRadius
    property alias bottomRightRadius: backgroundRect.bottomRightRadius
    property alias border: backgroundRect.border
    horizontalPadding: 10
    verticalPadding: 6
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2 + topInset + bottomInset
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2 + leftInset + rightInset

    background: Rectangle {
        id: backgroundRect
        color: root.color
        radius: Looks.radius.medium
        border.width: 0
        border.color: Looks.colors.tooltipBorder
        
        // Windows 11 style press feedback - subtle but noticeable
        scale: root.down ? 0.96 : 1.0
        opacity: root.down ? 0.9 : 1.0
        
        Behavior on color {
            enabled: root.animateStateChanges
            animation: ColorAnimation { duration: Looks.transition.enabled ? Looks.transition.duration.ultraFast : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Looks.transition.easing.bezierCurve.standard }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Looks.transition.enabled ? Looks.transition.duration.ultraFast : 0
                easing.type: Easing.OutQuad
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Looks.transition.enabled ? Looks.transition.duration.ultraFast : 0
                easing.type: Easing.OutQuad
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.LeftButton)
                root.clicked();
            if (event.button === Qt.RightButton)
                root.altAction();
            if (event.button === Qt.MiddleButton)
                root.middleClickAction();
        }
    }

    contentItem: Item {
        anchors {
            fill: parent
            margins: root.inset
        }
        implicitWidth: contentLayout.implicitWidth
        implicitHeight: contentLayout.implicitHeight
        RowLayout {
            id: contentLayout
            anchors {
                fill: root.centerContent ? undefined : parent
                centerIn: root.centerContent ? parent : undefined
                leftMargin: root.centerContent ? 0 : root.horizontalPadding
                rightMargin: root.centerContent ? 0 : root.horizontalPadding
            }
            spacing: root.centerContent ? 8 : 12
            Item {
                Layout.leftMargin: root.iconLeftMargin
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                visible: root.icon.name !== "" || root.forceShowIcon
                implicitWidth: 18
                implicitHeight: implicitWidth

                FluentIcon {
                    id: buttonIcon
                    visible: root.icon.name !== ""
                    anchors.centerIn: parent
                    monochrome: true
                    implicitSize: 18
                    icon: root.icon.name
                    color: root.fgColor
                }
            }
            WText {
                id: buttonText
                Layout.fillWidth: !root.centerContent
                Layout.alignment: Qt.AlignVCenter | (root.centerContent ? Qt.AlignHCenter : Qt.AlignLeft)
                verticalAlignment: Text.AlignVCenter
                text: root.text
                horizontalAlignment: root.centerContent ? Text.AlignHCenter : Text.AlignLeft
                font: root.font
                color: root.fgColor
            }
        }
    }
}
