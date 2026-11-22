pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    focus: true
    readonly property bool usePasswordChars: !(PolkitService.flow?.responseVisible ?? false)
    readonly property color authSurface: Appearance.colors.colLayer2
    readonly property color authBorder: Appearance.colors.colOutlineVariant
    readonly property int authRadius: Appearance.rounding.small

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            PolkitService.cancel()
            event.accepted = true
        }
    }

    function submit(): void {
        PolkitService.submit(inputField.text)
    }

    function focusAuthTarget(): void {
        if (PolkitService.interactionAvailable && inputField.visible)
            inputField.forceActiveFocus()
        else
            root.forceActiveFocus()
    }

    Connections {
        target: PolkitService
        function onInteractionAvailableChanged(): void {
            if (!PolkitService.interactionAvailable) {
                root.forceActiveFocus()
                return
            }
            inputField.text = ""
            Qt.callLater(root.focusAuthTarget)
        }
        function onFailureCountChanged(): void {
            if (PolkitService.failureCount <= 0)
                return
            inputField.text = ""
            if (PolkitService.interactionAvailable)
                Qt.callLater(root.focusAuthTarget)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            animation: NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    WindowDialog {
        id: dialog
        anchors.centerIn: parent
        backgroundWidth: 460
        show: false
        onDismiss: PolkitService.cancel()
        onShowChanged: {
            if (show)
                Qt.callLater(root.focusAuthTarget)
        }
        Component.onCompleted: {
            show = true
            Qt.callLater(root.focusAuthTarget)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.spacingLarge

            Rectangle {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 58
                Layout.alignment: Qt.AlignTop
                radius: root.authRadius
                color: root.authSurface
                border.width: 1
                border.color: root.authBorder

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 28
                    text: PolkitService.batteryChargeLimitRequest ? "battery_saver" : "security"
                    fill: 1
                    color: Appearance.colors.colSecondary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                WindowDialogTitle {
                    Layout.fillWidth: true
                    text: Translation.tr("Authentication")
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: PolkitService.actionLabel !== Translation.tr("Authentication")
                    text: PolkitService.actionLabel
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSecondary
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: messageText.implicitHeight + Appearance.sizes.spacingLarge * 2
            radius: root.authRadius
            color: root.authSurface
            border.width: 1
            border.color: root.authBorder

            RowLayout {
                id: messageRow
                anchors.fill: parent
                anchors.margins: Appearance.sizes.spacingLarge
                spacing: Appearance.sizes.spacingMedium

                MaterialSymbol {
                    text: "admin_panel_settings"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: 1
                    color: Appearance.colors.colSecondary
                    Layout.alignment: Qt.AlignTop
                }

                WindowDialogParagraph {
                    id: messageText
                    Layout.fillWidth: true
                    text: PolkitService.cleanMessage
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: (PolkitService.identities?.length ?? 0) > 1
            spacing: Appearance.sizes.spacingSmall

            Repeater {
                model: PolkitService.identities ?? []
                delegate: DialogButton {
                    required property var modelData
                    readonly property bool isSelected: PolkitService.selectedIdentity === modelData
                        || (String(PolkitService.selectedIdentity?.string ?? "") !== ""
                            && String(PolkitService.selectedIdentity?.string ?? "") === String(modelData?.string ?? ""))
                    buttonText: String(modelData?.displayName || modelData?.string || "")
                    colBackground: isSelected ? Appearance.colors.colPrimary : root.authSurface
                    colBackgroundHover: isSelected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    colText: isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    onClicked: {
                        PolkitService.selectIdentity(modelData)
                        inputField.text = ""
                        inputField.forceActiveFocus()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: PolkitService.supplementaryMessage.length > 0
            implicitHeight: supplementaryText.implicitHeight + Appearance.sizes.spacingMedium * 2
            radius: root.authRadius
            color: PolkitService.supplementaryIsError
                ? Appearance.colors.colErrorContainer
                : root.authSurface
            border.width: 1
            border.color: PolkitService.supplementaryIsError
                ? Appearance.colors.colError
                : root.authBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: Appearance.sizes.spacingMedium
                spacing: Appearance.sizes.spacingSmall

                MaterialSymbol {
                    text: PolkitService.supplementaryIsError ? "error" : "info"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: PolkitService.supplementaryIsError
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colSecondary
                    Layout.alignment: Qt.AlignTop
                }

                StyledText {
                    id: supplementaryText
                    Layout.fillWidth: true
                    text: PolkitService.supplementaryMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: PolkitService.supplementaryIsError
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnLayer2
                    wrapMode: Text.WordWrap
                }
            }
        }

        MaterialTextField {
            id: inputField
            Layout.fillWidth: true
            focus: true
            enabled: PolkitService.interactionAvailable
            placeholderText: PolkitService.cleanPrompt
            echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
            onAccepted: root.submit()
            onVisibleChanged: if (visible && enabled) forceActiveFocus()
            Component.onCompleted: inputField.forceActiveFocus()

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    PolkitService.cancel()
                    event.accepted = true
                }
            }
        }

        WindowDialogButtonRow {
            spacing: Appearance.sizes.spacingSmall

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: PolkitService.cancel()
            }

            DialogButton {
                enabled: PolkitService.interactionAvailable
                buttonText: Translation.tr("OK")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: root.submit()
            }
        }
    }
}
