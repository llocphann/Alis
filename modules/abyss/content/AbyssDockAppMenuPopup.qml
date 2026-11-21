pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

ColumnLayout {
    id: root
    // Match the mature Bar context-menu sizing rule: the popup follows the
    // widest action instead of reserving a Dock-wide fixed width. The 140 px
    // floor only keeps very short labels comfortably clickable.
    implicitWidth: menuColumn.implicitWidth
    implicitHeight: menuColumn.implicitHeight
    spacing: 0

    function invoke(item): void {
        const action = item?.action
        GlobalStates.abyssPopupKind = ""
        GlobalStates.abyssDockMenuModel = []
        GlobalStates.abyssDockMenuOwnerId = ""
        GlobalStates.abyssDockMenuTriggerHovered = false
        if (action)
            Qt.callLater(action)
    }

    ColumnLayout {
        id: menuColumn
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: GlobalStates.abyssDockMenuModel ?? []

            delegate: Loader {
                id: rowLoader
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: modelData?.type === "separator"
                    ? separatorComponent : actionComponent

                Component {
                    id: separatorComponent
                    Rectangle {
                        implicitHeight: 7
                        Layout.fillWidth: true
                        color: "transparent"
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 1
                            color: Qt.alpha(AbyssStyle.accent, .18)
                        }
                    }
                }

                Component {
                    id: actionComponent
                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: Math.max(
                            140, actionRow.implicitWidth + 20)
                        horizontalPadding: 0
                        buttonRadius: Math.max(10,
                            Appearance.rounding.large - 3)
                        colBackground: "transparent"
                        colBackgroundHover:
                            Qt.alpha(AbyssStyle.accent, .12)
                        colRipple:
                            Qt.alpha(AbyssStyle.accent, .22)
                        onClicked: root.invoke(rowLoader.modelData)

                        contentItem: RowLayout {
                            id: actionRow
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Loader {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                active: String(rowLoader.modelData?.iconName ?? "").length > 0
                                sourceComponent: rowLoader.modelData?.monochromeIcon === true
                                    ? materialIcon : appIcon

                                Component {
                                    id: materialIcon
                                    MaterialSymbol {
                                        text: rowLoader.modelData?.iconName ?? ""
                                        iconSize: 16
                                        color: Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000"
                                    }
                                }
                                Component {
                                    id: appIcon
                                    IconImage {
                                        source: AppSearch.resolveIcon(
                                            rowLoader.modelData?.iconName ?? "",
                                            "application-x-executable")
                                        implicitSize: 16
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: rowLoader.modelData?.text ?? ""
                                color: Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000"
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
