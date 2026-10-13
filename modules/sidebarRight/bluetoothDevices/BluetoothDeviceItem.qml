import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property var device
    property bool expanded: false
    property bool actionPending: false
    property string pendingAction: ""
    pointingHandCursor: !expanded
    buttonText: root.device?.name || Translation.tr("Unknown device")

    function beginAction(action: string): bool {
        if (root.actionPending)
            return false
        root.actionPending = true
        root.pendingAction = action
        actionTimeout.restart()
        return true
    }

    function finishAction(): void {
        root.actionPending = false
        root.pendingAction = ""
        actionTimeout.stop()
    }

    onDeviceChanged: root.finishAction()
    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded

    Connections {
        target: root.device
        function onConnectedChanged() {
            if (root.pendingAction === "connect" || root.pendingAction === "disconnect")
                root.finishAction()
        }
        function onPairedChanged() {
            if (root.pendingAction === "forget" && !(root.device?.paired ?? false))
                root.finishAction()
        }
    }

    Timer {
        id: actionTimeout
        interval: 15000
        repeat: false
        onTriggered: root.finishAction()
    }
    
    component ActionButton: DialogButton {
        colBackground: Appearance.alisEverywhere ? Appearance.alis.colPrimary : Appearance.colors.colPrimary
        colBackgroundHover: Appearance.alisEverywhere ? Appearance.alis.colPrimaryHover : Appearance.colors.colPrimaryHover
        colRipple: Appearance.alisEverywhere ? Appearance.alis.colPrimaryActive : Appearance.colors.colPrimaryActive
        colText: Appearance.alisEverywhere ? Appearance.alis.colOnPrimary : Appearance.colors.colOnPrimary
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            // Name
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                color: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.device?.name || Translation.tr("Unknown device")
                }
                Revealer {
                    vertical: true
                    reveal: (root.device?.connected || root.device?.paired) ?? false
                    Layout.fillWidth: true
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        text: {
                            if (!root.device?.paired) return "";
                            let statusText = root.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                            if (!root.device?.batteryAvailable) return statusText;
                            statusText += ` • ${Math.round(root.device?.battery * 100)}%`;
                            return statusText;
                        }
                    }
                }
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    enabled: Appearance.animationsEnabled
                    animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            visible: implicitHeight > 0
            implicitHeight: root.expanded ? actionsRow.implicitHeight : 0
            Layout.topMargin: root.expanded ? 8 : 0
            clip: true

            Behavior on implicitHeight {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
            }
            Behavior on Layout.topMargin {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
            }

            RowLayout {
                id: actionsRow
                width: parent.width

                Item { Layout.fillWidth: true }
                ActionButton {
                    id: connectBtn
                    enabled: !root.actionPending
                    buttonText: {
                        if (root.pendingAction === "connect") return Translation.tr("Connecting…")
                        if (root.pendingAction === "disconnect") return Translation.tr("Disconnecting…")
                        return root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                    }

                    onClicked: {
                        const disconnecting = root.device?.connected ?? false
                        if (!root.beginAction(disconnecting ? "disconnect" : "connect"))
                            return
                        if (disconnecting) {
                            root.device.disconnect();
                        } else {
                            root.device.trusted = true;
                            root.device.connect();
                        }
                    }
                }
                Revealer {
                    reveal: root.device?.paired ?? false
                    ActionButton {
                        enabled: !root.actionPending
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colErrorHover
                        colRipple: Appearance.colors.colErrorActive
                        colText: Appearance.colors.colOnError
                        buttonText: root.pendingAction === "forget"
                            ? Translation.tr("Forgetting…") : Translation.tr("Forget")
                        onClicked: {
                            if (root.beginAction("forget"))
                                root.device?.forget()
                        }
                    }
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
