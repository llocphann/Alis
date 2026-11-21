pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Context menu presentation for controls that live on the ii Bar.
//
// Generic ContextMenu remains appropriate for text fields, Dock/sidebar content,
// and arbitrary in-window anchors. Bar controls use this wrapper so their menu
// body participates in the same physical Bar/Screen Edge surface as StyledPopup.
Item {
    id: root

    property var model: []
    required property Item anchorItem
    property var anchorRect: null
    property bool anchorHovered: false
    property bool active: false
    property bool keyboardMode: true
    property bool closeOnHoverLost: true
    property bool closeOnHoverLostAfterEntered: false
    property int closeOnHoverLostDelay: 500
    property bool popupWasHovered: false
    readonly property bool hasIcons:
        model.some(item => item.iconName !== undefined && item.iconName !== "")

    function close(): void {
        root.active = false
    }

    function requestOpen(): void {
        if (GlobalStates.activeContextMenu
                && GlobalStates.activeContextMenu !== root)
            GlobalStates.activeContextMenu.close()
        root.active = true
    }

    onActiveChanged: {
        if (active) {
            GlobalStates.activeContextMenu = root
            GlobalStates.activeContextMenuCount++
            Qt.callLater(() => menuContent.forceActiveFocus())
        } else {
            if (GlobalStates.activeContextMenu === root)
                GlobalStates.activeContextMenu = null
            GlobalStates.activeContextMenuCount--
            root.popupWasHovered = false
        }
    }

    Timer {
        interval: root.closeOnHoverLostDelay
        running: root.active && root.closeOnHoverLost
            && !connectedPopup.popupHovered
            && !root.anchorHovered
            && (!root.closeOnHoverLostAfterEntered || root.popupWasHovered)
        onTriggered: root.close()
    }

    Connections {
        target: connectedPopup
        function onPopupHoveredChanged(): void {
            if (connectedPopup.popupHovered)
                root.popupWasHovered = true
        }
    }

    StyledPopup {
        id: connectedPopup

        hoverTarget: root.anchorItem
        anchorRect: root.anchorRect
        hoverActivates: false
        alternativeVisibleCondition: root.active
        closeOnOutsideClick: true
        keyboardFocus: root.keyboardMode
        popupBackgroundMargin: 0
        onRequestClose: root.close()

        Item {
            id: menuContent

            focus: true
            implicitWidth: menuColumn.implicitWidth + 8
            implicitHeight: menuColumn.implicitHeight + 8

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    root.close()
                }
            }

            ColumnLayout {
                id: menuColumn
                anchors.centerIn: parent
                spacing: 0

                Repeater {
                    model: root.model

                    delegate: DelegateChooser {
                        role: "type"

                        DelegateChoice {
                            roleValue: "separator"

                            Rectangle {
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Appearance.colors.colOutlineVariant
                            }
                        }

                        DelegateChoice {
                            roleValue: undefined

                            RippleButton {
                                id: menuBtn

                                required property var modelData

                                Layout.fillWidth: true
                                enabled: modelData.enabled !== false
                                opacity: enabled ? 1 : 0.45
                                buttonHovered: enabled && menuHover.hovered
                                implicitWidth: Math.max(
                                    140, menuRow.implicitWidth + 20)
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.small
                                colBackground: "transparent"
                                colBackgroundHover: ColorUtils.transparentize(
                                    Appearance.colors.colPrimary, 0.85)
                                colRipple: ColorUtils.transparentize(
                                    Appearance.colors.colPrimary, 0.7)

                                onClicked: {
                                    if (!enabled)
                                        return
                                    const action = modelData.action
                                    root.close()
                                    if (action)
                                        action()
                                }

                                HoverHandler {
                                    id: menuHover
                                }

                                contentItem: RowLayout {
                                    id: menuRow

                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: anchors.leftMargin
                                    spacing: 8

                                    Loader {
                                        active: root.hasIcons
                                        visible: active
                                        Layout.alignment: Qt.AlignVCenter
                                        sourceComponent:
                                            menuBtn.modelData.monochromeIcon === true
                                                ? materialIconComp : iconImageComp

                                        Component {
                                            id: materialIconComp

                                            MaterialSymbol {
                                                text: menuBtn.modelData.iconName ?? ""
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.colors.colOnSurface
                                            }
                                        }

                                        Component {
                                            id: iconImageComp

                                            IconImage {
                                                source: AppSearch.resolveIcon(
                                                    menuBtn.modelData.iconName ?? "",
                                                    "application-x-executable")
                                                implicitSize:
                                                    Appearance.font.pixelSize.normal
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: menuBtn.modelData.text ?? ""
                                        color: Appearance.colors.colOnSurface
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
