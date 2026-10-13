import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.overview
import qs.modules.abyss

Item {
    id: root
    property var participant: null
    readonly property bool taskView: GlobalStates.overviewMode === "taskview"
    readonly property bool editMode: !taskView && (overview.item?.editing ?? false)
    function handleEscape(): bool {
        return !root.taskView && (overview.item?.handleEscape?.() ?? false)
    }
    readonly property real topControlReserve: editor.desiredHeight+16
    readonly property bool applicationDragActive: overview.item?.applicationDragActive ?? false
    readonly property real desiredHeight: taskView ? Math.min(650,(participant?.height ?? 1080)*.5)
        : overview.item ? (overview.item.presentingSearch ? overview.item.searchOnlyHeight : overview.item.configuredHeight) : (participant?.height ?? 1080)*.72
    readonly property string sortingLease: "abyssOverview:"+(participant?.outputName ?? "")
    readonly property bool presentationVisible: participant?.visualResident ?? true
    property string heldLease: ""
    function synchronize(): void {
        const wanted = presentationVisible ? sortingLease : ""
        if (heldLease === wanted) return
        if (heldLease) CompositorService.setSortingConsumer(heldLease,false)
        heldLease = wanted
        if (heldLease) CompositorService.setSortingConsumer(heldLease,true)
    }
    onSortingLeaseChanged: synchronize()
    onPresentationVisibleChanged: synchronize()
    Component.onCompleted: synchronize()
    Component.onDestruction: if (heldLease) CompositorService.setSortingConsumer(heldLease,false)
    Loader {
        id: overview
        anchors.fill: parent
        sourceComponent: root.taskView ? (CompositorService.isNiri ? niri : hyprland) : dashboard
    }
    AbyssDashboardEditPopup {
        id: editor
        body: root.participant
        canvasController: root.taskView ? null : overview.item?.canvasController ?? null
    }
    Component {
        id: dashboard
        OverviewDashboard {
            anchors.fill: parent
            embeddedSurface: true
            externalEditToolbar: true
            warmContent: root.participant?.warmContent ?? false
            panelVisible: root.participant?.open ?? true
            popupPresented: root.participant?.open ?? true
            availableWidth: root.participant?.width ?? 1920
            availableHeight: root.participant?.height ?? 1080
            property bool completedClose: false
            Connections {
                target: root
                function onPresentationVisibleChanged(): void {
                    if (!root.presentationVisible) {
                        completedClose=true
                        cancelSearch()
                    }
                }
            }
            onPopupPresentedChanged: {
                syncReveal()
                if (popupPresented) {
                    if (completedClose) setSearchingText(GlobalStates.overviewSearchPrefix || "")
                    completedClose=false
                    Qt.callLater(focusSearchInput)
                }
            }
            Component.onCompleted: {
                if (GlobalStates.overviewSearchPrefix) setSearchingText(GlobalStates.overviewSearchPrefix)
                Qt.callLater(focusSearchInput)
            }
        }
    }
    Component {
        id: niri
        OverviewNiriWidget {
            anchors.centerIn: parent
            panelWindow: root.QsWindow.window
            embeddedSurface: true
            taskViewMode: true
            presentationActive: root.participant?.open ?? true
            onPresentationCloseRequested: GlobalStates.overviewOpen = false
        }
    }
    Component {
        id: hyprland
        OverviewWidget {
            anchors.centerIn: parent
            panelWindow: root.QsWindow.window
            embeddedSurface: true
            presentationActive: root.participant?.open ?? true
            onPresentationCloseRequested: GlobalStates.overviewOpen = false
        }
    }
}
