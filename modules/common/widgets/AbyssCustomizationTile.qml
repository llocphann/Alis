pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id: root
    objectName: "abyssCustomizationTile"

    property string tileId: ""
    property string title: ""
    property string subtitle: ""
    property string icon: "widgets"
    property color accentColor: Appearance.colors.colPrimary
    property bool active: false
    property bool selected: false
    property bool badgeVisible: true
    property string badgeIconOverride: ""
    property bool separateBadgeClick: false
    property string tooltipText: ""
    property real tileWidth: 128
    property real previewHeight: 66
    default property alias previewContent: customPreviewHost.data

    signal clicked()
    signal badgeClicked()

    readonly property bool abyssMode: (Config.options?.panelFamily ?? "abyss") === "abyss"
    readonly property bool hasCustomPreview: customPreviewHost.children.length > 0
    readonly property string resolvedBadgeIcon: root.badgeIconOverride.length > 0
        ? root.badgeIconOverride
        : (root.active ? "check" : "add")

    implicitWidth: root.tileWidth
    implicitHeight: root.previewHeight + 5 + titleLabel.implicitHeight
        + (subtitleLabel.visible ? (1 + subtitleLabel.implicitHeight) : 0)
    width: root.tileWidth
    height: implicitHeight

    // Miniature Preview Card
    Rectangle {
        id: previewCard
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        height: root.previewHeight
        radius: Math.min(14, Appearance.rounding.normal)
        scale: mainMouse.pressed ? 0.96 : 1.0
        color: root.selected
            ? Qt.alpha(Appearance.colors.colPrimary, 0.16)
            : (tileHover.hovered
                ? Qt.alpha(Appearance.colors.colLayer2Hover, 0.88)
                : Qt.alpha(root.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.72))
        border.width: root.selected ? 1.5 : 1
        border.color: root.selected
            ? Appearance.colors.colPrimary
            : (tileHover.hovered
                ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.52)
                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.26))
        clip: true

        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 130; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 130; easing.type: Easing.OutCubic }
        }

        // Built-in rich miniature card artwork when no custom previewContent is supplied
        Rectangle {
            id: defaultPreview
            visible: !root.hasCustomPreview
            anchors.fill: parent
            anchors.margins: 7
            radius: Math.max(6, previewCard.radius - 5)
            opacity: root.active ? 0.78 : 1.0
            color: Qt.alpha(root.accentColor, root.active ? 0.10 : 0.14)
            border.width: 1
            border.color: Qt.alpha(root.accentColor, 0.22)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 9
                anchors.rightMargin: 24
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: 8
                    color: Qt.alpha(root.accentColor, 0.22)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.icon.length > 0 ? root.icon : "widgets"
                        iconSize: 17
                        fill: 1
                        color: root.accentColor
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    width: Math.max(16, parent.width - 36)

                    Rectangle {
                        width: Math.min(parent.width, 44)
                        height: 5
                        radius: 2.5
                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.54)
                    }

                    Rectangle {
                        width: Math.min(parent.width, 30)
                        height: 4
                        radius: 2
                        color: Qt.alpha(Appearance.colors.colSubtext, 0.36)
                    }

                    Rectangle {
                        width: Math.min(parent.width, 36)
                        height: 4
                        radius: 2
                        color: Qt.alpha(root.accentColor, 0.52)
                    }
                }
            }
        }

        // Host for custom miniature QML widget/module previews
        Item {
            id: customPreviewHost
            visible: root.hasCustomPreview
            anchors.fill: parent
            anchors.margins: 6
            opacity: root.active ? 0.82 : 1.0
            clip: true

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        // Top-right status / action badge (+ to add, check when active)
        Rectangle {
            id: badgeRect
            visible: root.badgeVisible
            z: 5
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 5
            width: 20
            height: 20
            radius: 10
            scale: badgeMouse.pressed ? 0.90 : 1.0
            color: root.active
                ? (badgeMouse.containsMouse
                    ? Appearance.colors.colLayer3Hover
                    : Qt.alpha(Appearance.colors.colLayer3, 0.92))
                : (badgeMouse.containsMouse
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colPrimary)
            border.width: root.active ? 1 : 0
            border.color: root.active
                ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.48)
                : "transparent"

            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.resolvedBadgeIcon
                iconSize: root.active ? 13 : 14
                color: root.active
                    ? Appearance.colors.colOnLayer1
                    : Appearance.colors.colOnPrimary
            }
        }

        MouseArea {
            id: badgeMouse
            z: 6
            visible: root.badgeVisible && root.separateBadgeClick
            enabled: visible
            anchors.fill: badgeRect
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                mouse.accepted = true;
                root.badgeClicked();
            }
        }
    }

    // Tile Label & Optional Subtitle
    StyledText {
        id: titleLabel
        anchors.top: previewCard.bottom
        anchors.topMargin: 5
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: root.selected ? Font.DemiBold : Font.Medium
        color: root.selected
            ? Appearance.colors.colOnLayer1
            : (root.active ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1)
    }

    StyledText {
        id: subtitleLabel
        visible: root.subtitle.length > 0
        anchors.top: titleLabel.bottom
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.subtitle
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Qt.alpha(Appearance.colors.colSubtext, 0.82)
    }

    HoverHandler {
        id: tileHover
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        id: mainMouse
        anchors.fill: parent
        z: 1
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: root.title
        onClicked: root.clicked()
    }

    StyledToolTip {
        position: "top"
        extraVisibleCondition: tileHover.hovered && root.tooltipText.length > 0
        text: root.tooltipText
    }
}
