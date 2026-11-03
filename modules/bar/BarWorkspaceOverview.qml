pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.overview

// Workspace Overview opened from a Bar workspace hover.
//
// StyledPopup owns the layer-shell window, Bar attachment, slide-under motion,
// Screen Edge joins, shadow and hover bridge. The Overview widgets render only
// their content plane here so there is one connected surface, not a popup card
// nested inside another popup card.
StyledPopup {
    id: root

    required property bool dockHovered
    property string barPosition: "top"
    property bool verticalLayout: false
    readonly property bool effectiveVerticalLayout:
        root.verticalLayout || root._attachmentVertical
    property real attachmentThickness: -1
    property Item anchorItem
    property bool previewOpen: false
    property var workspaceId: null

    hoverTarget: root.anchorItem
    centerOnOutput: true
    attachmentEdgeOverride: root.barPosition
    attachmentThicknessOverride: root.attachmentThickness
    hoverActivates: false
    alternativeVisibleCondition: root.previewOpen
    popupBackgroundMargin: 0

    function close(): void {
        root.previewOpen = false
    }

    function showWorkspace(workspaceId: var, button: Item): void {
        root.workspaceId = workspaceId
        root.anchorItem = button
        WindowPreviewService.captureForTaskView()
        root.previewOpen = true
    }

    onAnchorItemChanged: {
        if (root.previewOpen && !root.anchorItem)
            root.close()
    }

    Item {
        id: overviewContent
        implicitWidth: overviewLoader.item?.implicitWidth ?? 1
        implicitHeight: overviewLoader.item?.implicitHeight ?? 1

        Timer {
            interval: Config.options?.overview?.workspaceHover?.closeDelayMs ?? 220
            running: root.previewOpen
                && !root.popupHovered
                && !root.dockHovered
            onTriggered: root.close()
        }

        Loader {
            id: overviewLoader
            anchors.fill: parent
            // Keep Overview content resident through StyledPopup's retract tail.
            // If this follows previewOpen, the renderer is destroyed the instant
            // close begins and the user sees content disappear/fade while only
            // the empty surface slides. root.presentationActive includes the reverse slide.
            active: root.presentationActive
            sourceComponent: CompositorService.isNiri ? niriOverview : hyprOverview
        }

        Component {
            id: niriOverview
            OverviewNiriWidget {
                panelWindow: root.presentationWindow
                    ?? root.anchorItem?.QsWindow?.window
                // Presentation lifetime follows the visual popup,
                // not semantic hover state, so close is a pure reverse slide.
                presentationActive: root.presentationActive
                embeddedSurface: true
                verticalLayout: root.effectiveVerticalLayout
                focusIndicatorAnimationReady:
                    root.requestedVisible && root.revealProgress >= 0.999
                preferredWorkspaceId: root.workspaceId
                onPresentationCloseRequested: root.close()
            }
        }

        Component {
            id: hyprOverview
            OverviewWidget {
                panelWindow: root.presentationWindow
                    ?? root.anchorItem?.QsWindow?.window
                // Keep previews/content alive until the slide-under
                // retract reaches the Bar and StyledPopup finally unmaps.
                presentationActive: root.presentationActive
                embeddedSurface: true
                verticalLayout: root.effectiveVerticalLayout
                focusIndicatorAnimationReady:
                    root.requestedVisible && root.revealProgress >= 0.999
                preferredWorkspaceId: root.workspaceId
                onPresentationCloseRequested: root.close()
            }
        }
    }
}
