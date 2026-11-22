pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../common/functions/CodeHighlighter.js" as CodeHighlighter

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var segmentLang: "txt"
    property var messageData: {}
    property bool isCommandRequest: segmentLang === "command" || segmentLang === "approval"
    property var displayLang: segmentLang === "command" ? "bash"
        : segmentLang === "approval" ? "json" : segmentLang

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    spacing: codeBlockComponentSpacing

    Rectangle { // Code background
        Layout.fillWidth: true
        topLeftRadius: codeBlockBackgroundRounding
        topRightRadius: codeBlockBackgroundRounding
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.angelEverywhere ? Appearance.angel.colGlassElevated
            : Appearance.alisEverywhere ? Appearance.alis.colLayer2
            : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colSurfaceContainerHighest
        implicitHeight: codeBlockTitleBarRowLayout.implicitHeight + codeBlockHeaderPadding * 2

        RowLayout { // Language and buttons
            id: codeBlockTitleBarRowLayout
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: codeBlockHeaderPadding
            anchors.rightMargin: codeBlockHeaderPadding
            spacing: 5

            StyledText {
                id: codeBlockLanguage
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: 10
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: CodeHighlighter.languageDisplayName(root.displayLang)
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"

                    onClicked: {
                        Quickshell.clipboardText = segmentContent
                        copyCodeButton.activated = true
                        copyIconTimer.restart()
                    }

                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy code")
                    }
                }
                AiMessageControlButton {
                    id: saveCodeButton
                    buttonIcon: activated ? "check" : "save"

                    onClicked: {
                        const downloadPath = FileUtils.trimFileProtocol(Directories.downloads)
                        Quickshell.execDetached(["/usr/bin/bash", "-c",
                            `echo '${StringUtils.shellSingleQuoteEscape(segmentContent)}' > '${downloadPath}/code.${segmentLang || "txt"}'`
                        ])
                        Quickshell.execDetached(["/usr/bin/notify-send",
                            Translation.tr("Code saved to file"),
                            Translation.tr("Saved to %1").arg(`${downloadPath}/code.${segmentLang || "txt"}`),
                            "-a", "Shell"
                        ])
                        saveCodeButton.activated = true
                        saveIconTimer.restart()
                    }

                    Timer {
                        id: saveIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            saveCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Save to Downloads")
                    }
                }
            }
        }
    }

    RowLayout { // Line numbers and code
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: codeBlockComponentSpacing

        Rectangle { // Line numbers
            implicitWidth: 40
            implicitHeight: lineNumberColumnLayout.implicitHeight
            Layout.fillHeight: true
            Layout.fillWidth: false
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: codeBlockBackgroundRounding
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen
            color: Appearance.alisEverywhere ? Appearance.alis.colLayer1
                : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colLayer2

            ColumnLayout {
                id: lineNumberColumnLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    rightMargin: 5
                    top: parent.top
                    topMargin: 6
                }
                spacing: 0

                Repeater {
                    model: String(root.segmentContent ?? "").split("\n").length
                    Text {
                        required property int index
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                    }
                }
            }
        }

        Rectangle { // Code background
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: Appearance.rounding.unsharpen
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: codeBlockBackgroundRounding
            color: Appearance.alisEverywhere ? Appearance.alis.colLayer1
                : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colLayer2
            implicitHeight: codeColumnLayout.implicitHeight

            ColumnLayout {
                id: codeColumnLayout
                anchors.fill: parent
                spacing: 0
                ScrollView {
                    id: codeScrollView
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    // Layout.fillHeight: true
                    implicitHeight: codeTextArea.implicitHeight + 1
                    contentWidth: codeTextArea.width - 1
                    // contentHeight: codeTextArea.contentHeight
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                    ScrollBar.horizontal: ScrollBar {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        padding: 5
                        policy: ScrollBar.AsNeeded
                        opacity: visualSize == 1 ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }

                        contentItem: Rectangle {
                            implicitHeight: 6
                            radius: Appearance.rounding.small
                            color: Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive : Appearance.colors.colLayer2Active
                        }
                    }

                    TextArea { // Code
                        id: codeTextArea
                        Layout.fillWidth: true
                        readOnly: !editing
                        selectByMouse: enableMouseSelection || editing
                        renderType: Text.NativeRendering
                        textFormat: root.editing ? TextEdit.PlainText : TextEdit.RichText
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        // wrapMode: TextEdit.Wrap
                        color: messageData.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1

                        readonly property var highlightPalette: ({
                            keyword: String(Appearance.colors.colPrimary),
                            string: String(Appearance.colors.colTertiary),
                            number: String(Appearance.colors.colSecondary),
                            comment: String(Appearance.colors.colSubtext),
                            type: String(Appearance.colors.colSecondary),
                            error: String(Appearance.colors.colError),
                            normal: String(messageData.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1)
                        })

                        text: root.editing
                            ? String(root.segmentContent ?? "")
                            : CodeHighlighter.highlightCode(String(root.segmentContent ?? ""), root.displayLang, highlightPalette)
                        onTextChanged: {
                            if (root.editing)
                                segmentContent = text
                        }

                        Keys.onPressed: (event) => {
                            if (root.editing && event.key === Qt.Key_Tab) {
                                // Insert 4 spaces at cursor
                                const cursor = codeTextArea.cursorPosition;
                                codeTextArea.insert(cursor, "    ");
                                codeTextArea.cursorPosition = cursor + 4;
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_C) && event.modifiers == Qt.ControlModifier) {
                                codeTextArea.copy();
                                event.accepted = true;
                            }
                        }
                    }
                }
                Loader {
                    active: root.isCommandRequest && root.messageData.functionPending
                    visible: active
                    Layout.fillWidth: true
                    Layout.margins: 6
                    Layout.topMargin: 0
                    sourceComponent: RowLayout {
                        Item { Layout.fillWidth: true }
                        ButtonGroup {
                            GroupButton {
                                contentItem: StyledText {
                                    text: Translation.tr("Reject")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                }
                                onClicked: Ai.rejectCommand(root.messageData)
                            }
                            GroupButton {
                                toggled: true
                                contentItem: StyledText {
                                    text: Translation.tr("Approve")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnPrimary
                                }
                                onClicked: Ai.approveCommand(root.messageData)
                            }
                        }
                    }
                }
            }

            // MouseArea to block scrolling
            // MouseArea {
            //     id: codeBlockMouseArea
            //     anchors.fill: parent
            //     acceptedButtons: editing ? Qt.NoButton : Qt.LeftButton
            //     cursorShape: (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            //     onWheel: (event) => {
            //         event.accepted = false
            //     }
            // }
        }
    }
}