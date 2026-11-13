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

                // Center icon + label as one visual unit. Optional badges are
                // anchored independently so their width can never push the tab
                // title off-center.
                Row {
                    id: centeredTabLabel
                    anchors.centerIn: parent
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
                                - (tab.hasIcon ? (tab.tightTab ? 17 : (root.pillHeight <= 30 ? 19 : 22)) : 0)
                                - (tab.hasBadge ? (root.pillHeight <= 30 ? 28 : 34) : (tab.tightTab ? 6 : 8))))
                        text: tab.modelData.label ?? ""
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: (root.pillHeight <= 30 || root.tabs.length >= 3 || tab.tightTab)
                            ? Appearance.font.pixelSize.smaller
                            : Appearance.font.pixelSize.small
                        font.weight: tab.selected ? Font.DemiBold : Font.Normal
                        color: tab.selected
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }
                }

                Rectangle {
                    visible: tab.hasBadge
                    anchors.right: parent.right
                    anchors.rightMargin: root.pillHeight <= 30 ? 6 : 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: root.pillHeight <= 30 ? 18 : 20
                    implicitHeight: root.pillHeight <= 30 ? 18 : 20
                    radius: height / 2
                    color: tab.selected
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer2

                    StyledText {
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
