pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Compact tab control shared by corner popups. Its moving primary pill follows
// the Dashboard To-do tabs while the hit areas stay fixed during animation.
Item {
    id: root

    property var tabs: []
    property int currentIndex: 0
    property int pillHeight: 36
    signal tabSelected(int index)

    implicitHeight: root.pillHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer1
    }

    Rectangle {
        width: root.tabs.length > 0 ? root.width / root.tabs.length : 0
        height: parent.height
        x: width * Math.max(0, Math.min(root.currentIndex, root.tabs.length - 1))
        radius: height / 2
        color: Appearance.colors.colPrimaryContainer

        Behavior on x {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
            }
        }
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: root.tabs

            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool selected: root.currentIndex === index
                readonly property bool hasIcon:
                    String(tab.modelData.icon ?? "").length > 0
                readonly property bool hasBadge:
                    tab.modelData.count !== undefined
                width: root.tabs.length > 0 ? root.width / root.tabs.length : 0
                height: root.height
                clip: true

                readonly property bool tightTab:
                    tab.width > 0 && tab.width < 90
                readonly property real _badgeMinSize: root.pillHeight <= 30 ? 18 : 20
                readonly property real _badgeRightMargin: root.pillHeight <= 30 ? 6 : 8
                readonly property real _badgeWidth: tab.hasBadge
                    ? Math.max(_badgeMinSize, Math.ceil(badgeText.implicitWidth) + 8)
                    : 0
                readonly property real _badgeReservedRight: tab.hasBadge
                    ? (_badgeWidth + _badgeRightMargin + 4)
                    : 0
                readonly property real _sidePad: tab.tightTab ? 4 : (root.pillHeight <= 30 ? 5 : 8)
                readonly property real _iconSlot: tab.hasIcon
                    ? (tab.tightTab ? 17 : (root.pillHeight <= 30 ? 19 : 22))
                    : 0

                // Center icon + label as one visual unit inside the safe pill
                // inset (excluding any trailing badge width so labels never
                // crowd the curved capsule edge or collide with multi-digit counts).
                Row {
                    id: centeredTabLabel
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: tab.hasBadge
                        ? Math.round((tab._sidePad - tab._badgeReservedRight) / 2)
                        : 0
                    spacing: tab.tightTab ? 3 : (root.pillHeight <= 30 ? 4 : 5)

                    MaterialSymbol {
                        visible: tab.hasIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.icon ?? ""
                        iconSize: tab.tightTab ? 14 : (root.pillHeight <= 30 ? 15 : 17)
                        color: tab.selected
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        // Bound the label to its own slot. This keeps long timer
                        // labels from crossing into the adjacent active pill
                        // while preserving the centered icon+text unit.
                        width: Math.min(implicitWidth, Math.max(0,
                            tab.width
                                - tab._iconSlot
                                - tab._sidePad
                                - (tab.hasBadge ? tab._badgeReservedRight : tab._sidePad)))
                        text: tab.modelData.label ?? ""
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: tab.tightTab
                            ? Math.max(10, Appearance.font.pixelSize.smaller - 1)
                            : ((root.pillHeight <= 30 || root.tabs.length >= 3)
                                ? Appearance.font.pixelSize.smaller
                                : Appearance.font.pixelSize.small)
                        font.weight: tab.selected ? Font.DemiBold : Font.Normal
                        color: tab.selected
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }
                }

                Rectangle {
                    id: tabCountBadge
                    visible: tab.hasBadge
                    anchors.right: parent.right
                    anchors.rightMargin: tab._badgeRightMargin
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: tab._badgeWidth
                    width: implicitWidth
                    implicitHeight: tab._badgeMinSize
                    height: implicitHeight
                    radius: height / 2
                    color: tab.selected
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer2

                    StyledText {
                        id: badgeText
                        anchors.centerIn: parent
                        text: String(tab.modelData.count ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: tab.selected
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colSubtext
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tabSelected(tab.index)
                }
            }
        }
    }
}
