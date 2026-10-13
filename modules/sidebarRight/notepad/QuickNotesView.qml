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
    signal editorDeactivated()

    property int margin: 0
    property real preferredHeight: 210
    property bool surfaceLocalTabSelection: true
    property bool showHeader: true
    property bool showZettelkastenActions: true
    property bool verticalDotNavigation: false
    // Dashboard and corner opt in; Sidebar Left remains Source-first.
    property bool autoMarkdownReading: false
    property bool externalEscapeHandling: false
    readonly property bool markdownReading: notepad.markdownReading

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
            autoMarkdownReading: root.autoMarkdownReading
            externalEscapeHandling: root.externalEscapeHandling
            surfaceLocalTabSelection: root.surfaceLocalTabSelection
            margin: 0
            onEditorActivated: root.editorActivated()
            onEditorDeactivated: root.editorDeactivated()
        }
    }
}
