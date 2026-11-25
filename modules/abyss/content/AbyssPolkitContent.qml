pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

FocusScope {
    id: root
    property string outputName: ""
    property bool previewMode: false
    property bool showPassword: false
    signal closeRequested()

    readonly property bool usePasswordChars: root.previewMode
        ? true
        : !(PolkitService.flow?.responseVisible ?? false)
    readonly property string effectiveActionLabel: root.previewMode
        ? Translation.tr("System authentication")
        : PolkitService.actionLabel
    readonly property string effectiveMessage: root.previewMode
        ? Translation.tr("Authentication is required to run system package management.")
        : (PolkitService.cleanMessage || Translation.tr("Authentication is required to perform this action"))
    readonly property string effectivePrompt: root.previewMode
        ? Translation.tr("Password")
        : PolkitService.cleanPrompt
    readonly property string effectiveSupplementaryMessage: root.previewMode
        ? ""
        : PolkitService.supplementaryMessage
    readonly property bool effectiveSupplementaryIsError: root.previewMode
        ? false
        : PolkitService.supplementaryIsError
    readonly property bool liveInteractionAvailable: !root.previewMode && PolkitService.interactionAvailable
    readonly property color primaryInk: Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000"
    readonly property color mutedInk: Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : "#3a3a3a"

    readonly property real desiredWidth: Math.round(400 * Appearance.fontSizeScale)
    readonly property real desiredHeight: Math.max(200, Math.ceil(contentColumn.implicitHeight) + 2)
    implicitWidth: desiredWidth
    implicitHeight: desiredHeight

    focus: true

    function submitAuth(): void {
        if (!root.liveInteractionAvailable)
            return
        PolkitService.submit(passwordField.text)
    }

    function focusPrimarySurface(): void {
        if (root.liveInteractionAvailable && passwordField.enabled)
            passwordField.forceActiveFocus()
        else
            root.forceActiveFocus()
    }

    function handleEscape(): bool {
        if (root.previewMode)
            return false
        if (PolkitService.active) {
            PolkitService.cancel()
            return true
        }
        return false
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && !root.previewMode) {
            PolkitService.cancel()
            event.accepted = true
        }
    }

    Connections {
        target: PolkitService
        enabled: !root.previewMode
        function onActiveChanged(): void {
            root.showPassword = false
            passwordField.text = ""
            if (PolkitService.active)
                Qt.callLater(root.focusPrimarySurface)
        }
        function onInteractionAvailableChanged(): void {
            if (!PolkitService.interactionAvailable) {
                root.forceActiveFocus()
                return
            }
            passwordField.text = ""
            Qt.callLater(root.focusPrimarySurface)
        }
        function onFailureCountChanged(): void {
            if (PolkitService.failureCount <= 0)
                return
            passwordField.text = ""
            if (PolkitService.interactionAvailable)
                Qt.callLater(root.focusPrimarySurface)
        }
    }

    Component.onCompleted: {
        if (!root.previewMode && PolkitService.active)
            Qt.callLater(root.focusPrimarySurface)
    }

    ColumnLayout {
        id: contentColumn
        x: 0
        y: 0
        width: root.width > 0 ? root.width : root.desiredWidth
        spacing: Math.round(12 * Appearance.fontSizeScale)

        RowLayout {
            Layout.fillWidth: true
            spacing: Math.round(12 * Appearance.fontSizeScale)

            Rectangle {
                Layout.preferredWidth: Math.round(44 * Appearance.fontSizeScale)
                Layout.preferredHeight: Math.round(44 * Appearance.fontSizeScale)
                Layout.alignment: Qt.AlignVCenter
                radius: Math.round(13 * Appearance.fontSizeScale)
                color: Qt.alpha(AbyssStyle.accent, 0.14)
                border.width: 1
                border.color: Qt.alpha(AbyssStyle.accent, 0.34)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Math.round(22 * Appearance.fontSizeScale)
                    text: !root.previewMode && PolkitService.batteryChargeLimitRequest
                        ? "battery_saver" : "security"
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                AbyssLabel {
                    Layout.fillWidth: true
                    text: Translation.tr("Authentication required")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                }

                AbyssLabel {
                    Layout.fillWidth: true
                    visible: root.effectiveActionLabel.length > 0
                    text: root.effectiveActionLabel
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: AbyssStyle.accent
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: messageRow.implicitHeight + Math.round(20 * Appearance.fontSizeScale)
            radius: Math.round(14 * Appearance.fontSizeScale)
            color: Qt.alpha(AbyssStyle.accent, 0.06)
            border.width: 1
            border.color: Qt.alpha(AbyssStyle.accent, 0.18)

            RowLayout {
                id: messageRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Math.round(12 * Appearance.fontSizeScale)
                anchors.rightMargin: Math.round(12 * Appearance.fontSizeScale)
                spacing: Math.round(10 * Appearance.fontSizeScale)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "admin_panel_settings"
                    iconSize: Math.round(18 * Appearance.fontSizeScale)
                    fill: 1
                    color: AbyssStyle.accent
                }

                AbyssLabel {
                    Layout.fillWidth: true
                    text: root.effectiveMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.primaryInk
                    wrapMode: Text.Wrap
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: !root.previewMode && (PolkitService.identities?.length ?? 0) > 1
            spacing: Math.round(6 * Appearance.fontSizeScale)

            Repeater {
                model: root.previewMode ? [] : (PolkitService.identities ?? [])
                delegate: AbyssButton {
                    required property var modelData
                    readonly property bool isSelected: PolkitService.selectedIdentity === modelData
                        || (String(PolkitService.selectedIdentity?.string ?? "") !== ""
                            && String(PolkitService.selectedIdentity?.string ?? "") === String(modelData?.string ?? ""))
                    text: String(modelData?.displayName || modelData?.string || "")
                    checked: isSelected
                    checkable: true
                    implicitHeight: Math.round(32 * Appearance.fontSizeScale)
                    onClicked: {
                        PolkitService.selectIdentity(modelData)
                        passwordField.text = ""
                        root.focusPrimarySurface()
                    }
                }
            }
        }

        Rectangle {
            id: errorBanner
            objectName: "abyssPolkitErrorBanner"
            Layout.fillWidth: true
            visible: root.effectiveSupplementaryMessage.length > 0
            implicitHeight: supplementaryRow.implicitHeight + Math.round(16 * Appearance.fontSizeScale)
            radius: Math.round(12 * Appearance.fontSizeScale)
            color: root.effectiveSupplementaryIsError
                ? Appearance.colors.colErrorContainer
                : Qt.alpha(AbyssStyle.accent, 0.08)
            border.width: 1
            border.color: root.effectiveSupplementaryIsError
                ? Appearance.colors.colError
                : Qt.alpha(AbyssStyle.accent, 0.25)

            RowLayout {
                id: supplementaryRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Math.round(10 * Appearance.fontSizeScale)
                anchors.rightMargin: Math.round(10 * Appearance.fontSizeScale)
                spacing: Math.round(8 * Appearance.fontSizeScale)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: root.effectiveSupplementaryIsError ? "error" : "info"
                    iconSize: Math.round(17 * Appearance.fontSizeScale)
                    fill: 1
                    color: root.effectiveSupplementaryIsError
                        ? Appearance.colors.colOnErrorContainer
                        : AbyssStyle.accent
                }

                AbyssLabel {
                    Layout.fillWidth: true
                    text: root.effectiveSupplementaryMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.effectiveSupplementaryIsError
                        ? Appearance.colors.colOnErrorContainer
                        : root.primaryInk
                    wrapMode: Text.Wrap
                }
            }
        }

        Rectangle {
            id: passwordBox
            Layout.fillWidth: true
            implicitHeight: Math.round(42 * Appearance.fontSizeScale)
            radius: Math.round(12 * Appearance.fontSizeScale)
            color: Qt.alpha(AbyssStyle.accent, passwordField.activeFocus ? 0.11 : 0.05)
            border.width: passwordField.activeFocus ? 1.5 : 1
            border.color: (root.effectiveSupplementaryIsError && passwordField.text.length === 0)
                ? Appearance.colors.colError
                : (passwordField.activeFocus ? AbyssStyle.accent : Qt.alpha(AbyssStyle.accent, 0.24))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(12 * Appearance.fontSizeScale)
                anchors.rightMargin: Math.round(6 * Appearance.fontSizeScale)
                spacing: Math.round(8 * Appearance.fontSizeScale)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.usePasswordChars ? "lock" : "key"
                    iconSize: Math.round(18 * Appearance.fontSizeScale)
                    color: passwordField.activeFocus ? AbyssStyle.accent : root.mutedInk
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: passwordField.text.length === 0
                        text: root.effectivePrompt
                        color: root.mutedInk
                        opacity: 0.78
                        font.family: AbyssStyle.fontFamily
                        font.pixelSize: Appearance.font.pixelSize.normal
                        elide: Text.ElideRight
                    }

                    TextInput {
                        id: passwordField
                        objectName: "abyssPolkitPasswordField"
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        focus: !root.previewMode
                        enabled: root.liveInteractionAvailable
                        selectByMouse: true
                        selectionColor: AbyssStyle.accent
                        selectedTextColor: AbyssStyle.surfaceDeep
                        color: root.primaryInk
                        font.family: AbyssStyle.fontFamily
                        font.pixelSize: Appearance.font.pixelSize.normal
                        echoMode: (!root.usePasswordChars || root.showPassword)
                            ? TextInput.Normal : TextInput.Password
                        onAccepted: root.submitAuth()
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape && !root.previewMode) {
                                PolkitService.cancel()
                                event.accepted = true
                            }
                        }
                    }
                }

                AbyssButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.usePasswordChars && !root.previewMode
                    compact: true
                    editorSquare: true
                    outlined: false
                    glyph: root.showPassword ? "visibility_off" : "visibility"
                    description: root.showPassword
                        ? Translation.tr("Hide password")
                        : Translation.tr("Show password")
                    onClicked: {
                        root.showPassword = !root.showPassword
                        root.focusPrimarySurface()
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Math.round(8 * Appearance.fontSizeScale)

            Item { Layout.fillWidth: true }

            AbyssButton {
                objectName: "abyssPolkitCancelButton"
                text: Translation.tr("Cancel")
                outlined: true
                enabled: !root.previewMode
                onClicked: PolkitService.cancel()
            }

            AbyssButton {
                objectName: "abyssPolkitSubmitButton"
                text: !root.previewMode && !PolkitService.interactionAvailable && PolkitService.active
                    ? Translation.tr("Verifying...")
                    : Translation.tr("Authenticate")
                glyph: "check"
                checked: true
                enabled: root.liveInteractionAvailable && passwordField.text.length > 0
                onClicked: root.submitAuth()
            }
        }
    }
}
