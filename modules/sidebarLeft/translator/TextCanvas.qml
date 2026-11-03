import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property bool isInput: true // true for input, false for output
    property string placeholderText
    property string text: ""
    property var inputTextArea: isInput ? inputLoader.item : undefined
    readonly property string displayedText: isInput ? inputLoader.item.text :
        root.text.length > 0 ? outputLoader.item.text : ""
    default property alias actionButtons: actions.contentData
    readonly property bool abyssMode: Config.options?.panelFamily === "abyss"
    Layout.fillWidth: true
    implicitHeight: Math.max(150, inputColumn.implicitHeight)
    color: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.04)
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colLayer2
    border.width: root.abyssMode ? 1 : 0
    border.color: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.08) : "transparent"
    radius: root.abyssMode ? 12 : Appearance.rounding.normal

    signal inputTextChanged(); // Signal emitted when text changes

    ColumnLayout {
        id: inputColumn
        anchors.fill: parent
        spacing: 0

        Loader {
            id: inputLoader
            active: root.isInput
            visible: root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledTextArea { // Input area
                id: inputTextArea
                placeholderText: root.placeholderText
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1
                placeholderTextColor: root.abyssMode ? AbyssStyle.textColorMuted : Appearance.colors.colSubtext
                padding: 15
                background: null
                onTextChanged: root.inputTextChanged()
            }
        }

        Loader {
            id: outputLoader
            active: !root.isInput
            visible: !root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledText { // Output area
                id: outputTextArea
                padding: 15
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.text.length > 0
                    ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                    : (root.abyssMode ? AbyssStyle.textColorMuted : Appearance.colors.colSubtext)
                text: root.text.length > 0 ? root.text : root.placeholderText
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout { // Status row
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 10

            Loader {
                active: root.isInput
                visible: root.isInput
                Layout.leftMargin: 10
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: StyledText {
                    text: Translation.tr("%1 characters").arg(inputLoader.item.text.length)
                    color: root.abyssMode ? AbyssStyle.textColorMuted : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            Item { Layout.fillWidth: true }
            ButtonGroup {
                id: actions
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
            }
        }
    }
}