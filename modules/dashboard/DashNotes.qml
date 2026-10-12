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

    QuickNotesView {
        objectName: "quickNotesSharedDashboardView"
        Layout.fillWidth: true
        Layout.fillHeight: true
        surfaceLocalTabSelection: true
        showZettelkastenActions: true
        // A deliberate, Source-first Markdown Reading switch. The Weekly
        // Planner's notes column uses this same card/editor implementation.
        showMarkdownModeSwitch: true
        margin: 0
    }
}
