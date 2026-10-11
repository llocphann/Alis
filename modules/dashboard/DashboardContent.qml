pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.sidebarRight.events

Item {
    id: root

    property int screenWidth: 1920
    property int screenHeight: 1080
    property bool embeddedSurface: false
    property bool warmContent: false
    property bool presentationActive: GlobalStates.dashboardOpen || GlobalStates.overviewOpen

    property alias editMode: dashboardCanvas.editMode
    readonly property bool musicEnabled: Config.options?.dashboard?.music?.enable ?? true
    readonly property int currentPage: musicEnabled ? Math.max(0, Math.min(1, GlobalStates.dashboardPage)) : 0
    property var musicBackend: null
    property bool musicVisited: currentPage === 1
    onCurrentPageChanged: if (currentPage === 1)
        musicVisited = true
    onEditModeChanged: if (editMode)
        GlobalStates.dashboardPage = 0
    readonly property var canvasController: dashboardCanvas

    readonly property bool showHeader: Config.options?.dashboard?.showHeader ?? true

    property var _agendaEditEvent: null
    property var _agendaPrefillDate: null
    property bool _agendaDialogShown: false
    property bool _agendaDialogLoaded: false

    function handleEscape(): bool {
        if (_agendaDialogShown) {
            _agendaDialogShown = false
            return true
        }
        if (dashboardCanvas.editMode) {
            dashboardCanvas.cancelEditMode()
            return true
        }
        return currentPage === 1 && (musicPage.item?.restoreBrowserColumns() ?? false)
    }

    function openAgendaDialog(arg) {
        const isDate = arg instanceof Date;
        root._agendaEditEvent = (arg && !isDate) ? arg : null;
        root._agendaPrefillDate = isDate ? arg : null;
        root._agendaDialogLoaded = true;
        if (agendaDialogLoader.item) {
            if (root._agendaEditEvent) {
                agendaDialogLoader.item.loadEvent(root._agendaEditEvent);
            } else {
                agendaDialogLoader.item.resetForm();
                if (root._agendaPrefillDate)
                    agendaDialogLoader.item.eventDate = root._agendaPrefillDate;
            }
        }
        root._agendaDialogShown = true;
    }

    // Dashboard does not own a separate background renderer. Detached Dashboard
    // uses the same canonical Material layer-0 surface and shadow vocabulary as
    // existing ii popups/sidebars; the launcher-embedded form stays transparent
    // because OverviewDashboard already owns that same layer-0 surface.
    StyledRectangularShadow {
        target: background
        radius: background.radius
        // Detached Dashboard retains its own shadow owner, but shares the
        // physical Screen Edge elevation controls with connected surfaces.
        blur: Math.max(0, Math.min(32, Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
        spread: 0
        offset: Qt.vector2d(0, 0)
        color: Qt.alpha(Appearance.m3colors.m3shadow, Math.max(0, Math.min(1.0, Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70))))
        visible: !root.embeddedSurface && (Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true) && !Appearance.gameModeMinimal
    }

    Rectangle {
        id: background
        anchors.fill: parent
        clip: true
        color: root.embeddedSurface ? "transparent" : Appearance.colors.colLayer0
        radius: root.embeddedSurface ? 0 : Appearance.rounding.large
        border.width: 0
        border.color: "transparent"

        ColumnLayout {
            id: mainColumn
            readonly property bool compact: (Config.options?.dashboard?.appearance?.density ?? "comfortable") === "compact"
            anchors.fill: parent
            anchors.margins: root.embeddedSurface ? 0 : (compact ? 12 : 16)
            spacing: compact ? 8 : 12

            DashboardHeader {
                id: dashboardHeader
                Layout.fillWidth: true
                visible: root.showHeader || root.musicEnabled
                showActions: root.showHeader
                currentPage: root.currentPage
                pageCount: root.musicEnabled ? 2 : 1
                onPageRequested: index => GlobalStates.dashboardPage = index
                editMode: dashboardCanvas.editMode
                onEditModeRequested: {
                    if (dashboardCanvas.editMode)
                        dashboardCanvas.commitEditMode();
                    else
                        dashboardCanvas.beginEditMode();
                }
            }

            Item {
                id: pages
                objectName: "dashboardPages"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                // Editing must see the original workspace immediately, including
                // entry during an already running page transition.
                readonly property real slideProgress: root.editMode ? 0 : pagePosition
                property real pagePosition: root.currentPage
                Behavior on pagePosition {
                    enabled: root.presentationActive && Appearance.animationsEnabled && !root.editMode
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.OutCubic
                    }
                }
                DashboardCanvas {
                    id: dashboardCanvas
                    width: pages.width
                    height: pages.height
                    x: -pages.slideProgress * pages.width
                    visible: pages.slideProgress < 1
                    enabled: root.currentPage === 0
                    presentationActive: root.presentationActive && root.currentPage === 0
                    warmContent: root.warmContent
                    onRequestEventsDialog: event => root.openAgendaDialog(event)
                }
                Loader {
                    id: musicPage
                    width: pages.width
                    height: pages.height
                    x: (1 - pages.slideProgress) * pages.width
                    visible: pages.slideProgress > 0
                    enabled: root.currentPage === 1
                    active: root.musicEnabled && root.musicVisited && (root.presentationActive || root.warmContent)
                    sourceComponent: DashboardMusic {
                        backend: root.musicBackend ?? LocalMusic
                        presentationActive: root.presentationActive && root.currentPage === 1
                    }
                }
                // Handle page gestures above the canvas and its scrollable widgets.
                // Pointer handlers leave clicks and vertical scrolling to those widgets.
                Item {
                    anchors.fill: parent
                    z: 100
                    WheelHandler {
                        id: dashboardVerticalWheel
                        target: null
                        orientation: Qt.Vertical
                        // Rejected list events must reach the Flickable below.
                        blocking: false
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        enabled: root.presentationActive && root.musicEnabled && !root.editMode && !root._agendaDialogShown && !(musicPage.item?.playlistDialogVisible ?? false)
                        onWheel: event => {
                            const delta = event.pixelDelta.y || event.angleDelta.y / 3
                            if (!delta) return
                            if (root.currentPage === 1 && musicPage.item) {
                                const at = dashboardVerticalWheel.point.position
                                const local = musicPage.item.mapFromItem(pages, at.x, at.y)
                                if (!musicPage.item.acceptsPageWheel(local.x, local.y)) {
                                    event.accepted = false
                                    return // Preserve vertical scrolling inside music lists.
                                }
                            }
                            GlobalStates.dashboardPage = delta < 0 ? 1 : 0
                            event.accepted = true
                        }
                    }
                    WheelHandler {
                        target: null
                        orientation: Qt.Horizontal
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        enabled: root.presentationActive && root.musicEnabled && !root.editMode && !root._agendaDialogShown && !(musicPage.item?.playlistDialogVisible ?? false)
                        onWheel: event => {
                            const delta = event.pixelDelta.x || event.angleDelta.x / 3;
                            if (delta === 0)
                                return;
                            if (root.currentPage === 1 && musicPage.item?.panHorizontally(delta)) {
                                event.accepted = true;
                                return;
                            }
                            GlobalStates.dashboardPage = Math.max(0, Math.min(1, root.currentPage + (delta < 0 ? 1 : -1)));
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        Loader {
            id: agendaDialogLoader
            anchors.fill: parent
            z: 200
            active: root._agendaDialogLoaded
            sourceComponent: EventsDialog {}
            onLoaded: {
                item.show = Qt.binding(() => root._agendaDialogShown);
                if (root._agendaEditEvent) {
                    item.loadEvent(root._agendaEditEvent);
                } else {
                    item.resetForm();
                    if (root._agendaPrefillDate)
                        item.eventDate = root._agendaPrefillDate;
                }
                item.forceActiveFocus();
            }
            Connections {
                target: agendaDialogLoader.item
                function onDismiss() {
                    root._agendaDialogShown = false;
                }
            }
        }
    }
}
