pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Canonical Quick Notes presentation used by Dashboard and Sidebar Left.
// NotepadWidget owns all tab/editor/autosave behavior; this component only owns
// the shared Material identity row and responsive surface composition.
Item {
    id: root

    signal editorActivated()

    property int margin: 0
    property real preferredHeight: 210
    property bool surfaceLocalTabSelection: true
    property bool showHeader: true
    property bool showZettelkastenActions: true
    property bool verticalDotNavigation: false
    property bool readingOnHover: false
    // Only Dashboard cards request the visible manual Markdown mode control.
    // Keep Sidebar Left and corner Quick Notes untouched by default.
    property bool showMarkdownModeSwitch: false
    readonly property bool markdownReading: notepad.markdownReading
    function toggleMarkdownMode(): void {
        if (!root.showMarkdownModeSwitch)
            return
        if (notepad.markdownReading)
            root.focusEditor()
        else
            notepad.enterMarkdownReading()
    }

    implicitHeight: root.preferredHeight

    readonly property bool constrainedHeight:
        root.height > 0 && root.height < 210
    readonly property bool narrowHeader:
        root.width > 0 && root.width < 300
    readonly property bool veryNarrowHeader:
        root.width > 0 && root.width < 230

    readonly property color colText: Appearance.colors.colOnSurface
    readonly property color colSubtext: Appearance.colors.colOnSurfaceVariant
    readonly property color colAccent: Appearance.colors.colPrimary

    readonly property bool canSaveZettel: notepad.canSaveZettel
    property alias editor: notepad

    readonly property string zettelStatusText: {
        if (Zettelkasten.errorMessage.length > 0)
            return Zettelkasten.errorMessage
        if (Zettelkasten.ready)
            return Translation.tr("%1 note · draft stays in Notepad")
                .arg(Zettelkasten.defaultType)
        return Translation.tr("Configure an Obsidian vault to capture notes")
    }

    function openZettelkastenSettings(): void {
        GlobalStates.openSettingsSection(7, "To-do & Quick Notes")
    }

    function focusEditor(): void {
        notepad.focus = true
        notepad.focusEditor()
    }

    function releaseEditorFocus(): void {
        notepad.releaseEditorFocus()
    }

    function flushPendingSave(): void {
        notepad.flushPendingSave()
    }

    function captureQuickNote(): bool {
        return notepad.captureQuickNote()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.margin
        spacing: 4

        RowLayout {
            visible: root.showHeader
            Layout.fillWidth: true
            spacing: root.veryNarrowHeader ? 4 : 6

            MaterialSymbol {
                text: "note_stack"
                iconSize: root.constrainedHeight || root.veryNarrowHeader
                    ? Appearance.font.pixelSize.normal
                    : Appearance.font.pixelSize.larger
                color: root.colAccent
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Quick Notes")
                font.pixelSize: root.constrainedHeight
                    ? Appearance.font.pixelSize.small
                    : Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: root.colText
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            RippleButton {
                id: markdownModeSwitch
                objectName: "quickNotesMarkdownModeSwitch"
                visible: root.showMarkdownModeSwitch
                implicitWidth: root.veryNarrowHeader ? 69 : 91
                implicitHeight: root.constrainedHeight ? 28 : 30
                buttonRadius: 9
                focusPolicy: Qt.StrongFocus
                colBackground: root.markdownReading
                    ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer2Hover
                Accessible.name: root.markdownReading
                    ? Translation.tr("Source Editing")
                    : Translation.tr("Markdown Reading")
                onClicked: root.toggleMarkdownMode()

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 3
                    MaterialSymbol {
                        text: root.markdownReading ? "edit_note" : "menu_book"
                        iconSize: 15
                        color: root.colText
                    }
                    StyledText {
                        text: root.markdownReading
                            ? Translation.tr("Source")
                            : Translation.tr("Reading")
                        color: root.colText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }

                StyledToolTip { text: markdownModeSwitch.Accessible.name }
            }

            RippleButton {
                visible: root.showZettelkastenActions
                    && !root.narrowHeader
                implicitWidth: root.constrainedHeight ? 28 : 30
                implicitHeight: implicitWidth
                buttonRadius: height / 2
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.openZettelkastenSettings()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: Zettelkasten.errorMessage.length > 0
                        ? "error"
                        : (Zettelkasten.ready ? "hub" : "link_off")
                    iconSize: 17
                    color: Zettelkasten.errorMessage.length > 0
                        ? Appearance.colors.colError
                        : (Zettelkasten.ready ? root.colAccent : root.colSubtext)
                }

                StyledToolTip {
                    text: Zettelkasten.errorMessage.length > 0
                        ? root.zettelStatusText
                        : (Zettelkasten.ready
                            ? Translation.tr("Zettelkasten capture") + " · "
                                + root.zettelStatusText
                            : root.zettelStatusText)
                }
            }

            RippleButton {
                visible: root.showZettelkastenActions
                implicitWidth: root.constrainedHeight || root.veryNarrowHeader
                    ? 28 : 32
                implicitHeight: implicitWidth
                buttonRadius: height / 2
                enabled: notepad.canSaveZettel
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                onClicked: notepad.captureQuickNote()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "note_add"
                    iconSize: 17
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledToolTip {
                    text: Zettelkasten.ready
                        ? Translation.tr("Create a %1 Zettelkasten note while keeping the Notepad draft unchanged.")
                            .arg(Zettelkasten.defaultType)
                        : Translation.tr("Configure an Obsidian vault to enable Zettelkasten")
                }
            }
        }

        NotepadWidget {
            id: notepad
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.constrainedHeight ? 76 : 130
            compactPresentation: true
            verticalDotNavigation: root.verticalDotNavigation
            readingOnHover: root.readingOnHover
            allowManualReading: root.showMarkdownModeSwitch
            surfaceLocalTabSelection: root.surfaceLocalTabSelection
            margin: 0
            onEditorActivated: root.editorActivated()
        }
    }
}
