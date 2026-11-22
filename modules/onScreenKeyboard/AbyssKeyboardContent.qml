pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.services.deferred

Item {
    id: root
    property var participant: null
    property string outputName: ""
    property bool pinned: Config.options?.osk?.pinnedOnStartup ?? false
    property bool open: participant?.open ?? false

    readonly property color _railBase: Appearance.colors.colLayer1Base
    readonly property real _tonalDir: _railBase.hslLightness > 0.86 ? -1.0 : 1.0
    readonly property color _railHover: ColorUtils.tonalStep(_railBase, _tonalDir * 0.028, 1.05)

    // 36px slim control rail + 8px gap + 1px hairline + 8px gap = 53px
    implicitWidth: keyboard.implicitWidth + 53
    implicitHeight: Math.max(keyboard.implicitHeight, controls.implicitHeight)
    onOpenChanged: if (!open) Ydotool.releaseAllKeys()
    Component.onDestruction: if (open) Ydotool.releaseAllKeys()

    Item {
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight
        scale: Math.min(1, root.width / width, root.height / height)

        RowLayout {
            anchors.fill: parent
            spacing: 8

            // Keep exact 4-parent chain: oskPin -> controls -> RowLayout -> centered Item -> root
            ColumnLayout {
                id: controls
                Layout.preferredWidth: 36
                Layout.fillHeight: true
                spacing: 6

                RippleButton {
                    id: pinButton
                    objectName: "oskPin"
                    Layout.fillWidth: true
                    implicitHeight: 34
                    toggled: root.pinned
                    buttonRadius: Appearance.rounding.small
                    colBackground: root._railBase
                    colBackgroundHover: root._railHover
                    colBackgroundToggled: Appearance.colors.colPrimary
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    Accessible.name: Translation.tr("Pin position")
                    onClicked: root.pinned = !root.pinned
                    altAction: () => Config.setNestedValue("osk.keepOnTop", !(Config.options?.osk?.keepOnTop ?? false))

                    contentItem: Item {
                        anchors.fill: parent
                        Rectangle {
                            anchors.fill: parent
                            radius: pinButton.buttonEffectiveRadius
                            color: "transparent"
                            border.width: pinButton.toggled ? 0 : 1
                            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.pinned ? "lock" : "keep"
                            iconSize: 17
                            color: pinButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        Rectangle {
                            visible: Config.options?.osk?.keepOnTop ?? false
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 4
                            width: 4
                            height: 4
                            radius: 2
                            color: pinButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        }
                    }

                    StyledToolTip {
                        text: root.pinned
                            ? Translation.tr("Unlock position")
                            : Translation.tr("Pin position")
                    }
                }

                RippleButton {
                    id: closeButton
                    objectName: "oskClose"
                    Layout.fillWidth: true
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: root._railBase
                    colBackgroundHover: root._railHover
                    Accessible.name: Translation.tr("Hide keyboard")
                    onClicked: GlobalStates.oskOpen = false

                    contentItem: Item {
                        anchors.fill: parent
                        Rectangle {
                            anchors.fill: parent
                            radius: closeButton.buttonEffectiveRadius
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "keyboard_hide"
                            iconSize: 17
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Hide keyboard")
                    }
                }

                Item {
                    id: dragArea
                    objectName: "oskDrag"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 40
                    opacity: root.pinned ? 0.22 : (dragHover.hovered ? 0.92 : 0.52)

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    HoverHandler {
                        id: dragHover
                        cursorShape: root.pinned ? Qt.ArrowCursor : Qt.OpenHandCursor
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 4
                        height: Math.min(34, Math.max(18, parent.height * 0.42))
                        radius: 2
                        color: Appearance.colors.colSubtext
                    }

                    DragHandler {
                        enabled: !root.pinned
                        target: null
                        onActiveChanged: if (active) root.participant?.beginKeyboardDrag(); else root.participant?.finishKeyboardDrag()
                        onTranslationChanged: if (active) root.participant?.moveKeyboardDrag(translation.x, translation.y)
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                implicitWidth: 1
                color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)
            }

            OskContent {
                id: keyboard
                objectName: "abyssKeyboardKeys"
                Layout.fillWidth: true
            }
        }
    }
}
