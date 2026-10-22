pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Focused, non-destructive editor. The owning Dashboard validates names and
// performs the actual atomic Config update.
Item {
    id: root
    property string mode: "create"
    property string tabName: ""
    property string errorText: ""
    signal acceptRequested(string name)
    signal nameEdited(string name)
    signal dismissRequested()

    objectName: "dashboardCustomTabDialog"
    focus: visible
    onVisibleChanged: if (visible && mode !== "delete")
        Qt.callLater(() => {
            if (!root.visible) return
            tabNameInput.text = root.tabName
            tabNameInput.forceActiveFocus()
        })
    Keys.onEscapePressed: event => {
        root.dismissRequested()
        event.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#000000", 0.58)
        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissRequested()
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(390, parent.width - 32)
        height: dialogColumn.implicitHeight + 40
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            id: dialogColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 20
            spacing: 12

            StyledText {
                Layout.fillWidth: true
                text: root.mode === "delete"
                    ? Translation.tr("Delete custom tab?")
                    : root.mode === "rename" ? Translation.tr("Rename custom tab")
                        : Translation.tr("Create custom tab")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: root.mode === "delete"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("The tab layout will be deleted. Notes, tasks, events and music are not deleted.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            TextField {
                id: tabNameInput
                objectName: "dashboardCustomTabName"
                visible: root.mode !== "delete"
                Layout.fillWidth: true
                text: root.tabName
                placeholderText: Translation.tr("Tab name")
                maximumLength: 41
                onTextEdited: root.nameEdited(text)
                onAccepted: root.acceptRequested(text)
            }
            StyledText {
                visible: root.errorText.length > 0
                Layout.fillWidth: true
                text: root.errorText
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                RippleButton {
                    implicitWidth: 88
                    implicitHeight: 34
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.dismissRequested()
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        color: Appearance.colors.colOnLayer1
                    }
                }
                RippleButton {
                    implicitWidth: 88
                    implicitHeight: 34
                    buttonText: root.mode === "delete"
                        ? Translation.tr("Delete") : Translation.tr("Save")
                    onClicked: root.acceptRequested(tabNameInput.text)
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: root.mode === "delete"
                            ? Translation.tr("Delete")
                            : root.mode === "create"
                                ? Translation.tr("Create") : Translation.tr("Save")
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
