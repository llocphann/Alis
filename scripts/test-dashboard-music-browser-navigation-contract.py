#!/usr/bin/env python3
"""Static guards for dashboard navigation, music queue and Screen Edge source ownership.

Native Niri/Quickshell gesture, audio and focus acceptance remains separate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
read = lambda path: (ROOT / path).read_text(encoding="utf-8")
music = read("modules/dashboard/DashboardMusic.qml")
pages = read("modules/dashboard/DashboardContent.qml")
dashboard = read("modules/dashboard/Dashboard.qml")
header = read("modules/dashboard/DashboardHeader.qml")
weather = read("modules/bar/weather/WeatherBar.qml")
module = read("modules/abyss/bar/AbyssBarModule.qml")
popup = read("modules/bar/StyledPopup.qml")

def expect(source, *tokens):
    for token in tokens:
        assert token in source, f"missing contract token: {token}"

expect(music, 'objectName: "musicLibrary"', 'objectName: "musicGenreTab"',
       'objectName: "musicFolderTab"', 'function switchLibraryTab(tab): void',
       'function restoreBrowserColumns(): bool', 'sourceMode = ""',
       'visible: root.libraryTab === "genre"', 'visible: root.libraryTab === "folder"',
       'function panHorizontally(',
       'objectName: "musicPlayAll"', 'objectName: "musicPlaySelection"',
       'root.backend.playQueue(root.allResultTracks, 0',
       'root.backend.playQueue(root.selectedTracks, 0',
       'objectName: "musicPlaybackAndQueue"', 'objectName: "musicQueuePanel"',
       'objectName: "musicQueueList"', 'onDoubleClicked: root.backend.jumpTo(index)',
       'DashMedia {', 'playbackAdapter: playerAdapter',
       'showEqualizer: !root.queueExpanded',
       'id: queueHover', 'root.queueExpanded = true',
       'id: queueCollapseTimer',
       'Math.ceil(implicitHeight)', 'parent.height - parent.spacing - 108',
       'mediaColumnWidth: Math.min(380, Math.max(315, width * .29))')
expect(pages, 'function handleEscape(): bool', 'dashboardCanvas.cancelEditMode()',
       'musicPage.item?.restoreBrowserColumns()', 'orientation: Qt.Horizontal',
       'PagePolicy.advance(', 'GlobalStates.dashboardPageId',
       'PagePolicy.ordered(', 'musicPage.item?.panHorizontally(movement.x)')
assert 'orientation: Qt.Vertical' not in pages, 'vertical page navigation remains in body'
assert 'orientation: Qt.Vertical' not in header, 'vertical page navigation remains in header'
expect(dashboard, 'contentLoader.item?.handleEscape()', 'event.accepted = true')
expect(header, 'id: uptime', 'anchors.left: parent.left',
       'id: actions', 'anchors.right: parent.right', 'orientation: Qt.Horizontal',
       'root.horizontalWheel(event)', 'Keys.onLeftPressed:', 'Keys.onRightPressed:')
expect(module, 'readonly property bool hovered: hoverTracker.hovered',
       'onHoveredChanged: root.interaction(hovered ? .35 : -.15)')
expect(popup, 'readonly property bool moduleHoverActive: !!(',
       'root._liquidAnchor?.hovered', 'root._liquidAnchor?.feature?.containsMouse',
       'root.hoverTarget?.containsMouse',
       'root.moduleHoverActive || root._anchorHover.hovered || root.popupHovered')
assert "openSidebarRight" not in weather, "Weather click still opens Sidebar Right"
assert "sidebarRightRequestedWidget" not in weather, "Weather still routes to Sidebar Right"
print("Dashboard library tabs, Queue sizing, Esc and hover contracts: PASS")
