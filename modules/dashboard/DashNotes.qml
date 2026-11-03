import QtQuick
import QtQuick.Layouts
import qs.modules.sidebarRight.notepad

/**
 * Dashboard Quick Notes card.
 *
 * The visual/editor implementation lives in QuickNotesView so Dashboard and
 * Sidebar Left cannot drift into separate Quick Notes design systems.
 */
DashCard {
    id: root
    title: ""
    icon: ""
    Layout.fillHeight: true

    function handleEscape(): bool {
        if (quickNotesView.editor.markdownEditing) {
            quickNotesView.releaseEditorFocus()
            return true
        }
        return false
    }

    QuickNotesView {
        id: quickNotesView
        objectName: "quickNotesSharedDashboardView"
        Layout.fillWidth: true
        Layout.fillHeight: true
        surfaceLocalTabSelection: true
        showZettelkastenActions: true
        // Reading by default; click into Source editing, Escape to Reading.
        // Weekly Planner inherits this same shared card/editor behavior.
        autoMarkdownReading: true
        margin: 0
    }
}
