pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.functions

// Window preview popout shared by Bar taskbar apps and workspace hover.
//
// The outer surface is the same connected morph used by every other Bar popout;
// preview tiles remain content only. Workspace mode filters compositor-owned
// toplevels instead of creating a second preview/capture implementation.
StyledPopup {
    id: root

    required property bool dockHovered
    property string barPosition: "top"
    property bool verticalLayout: false
    property var appEntry
    property Item anchorItem
    property bool previewOpen: false
    property string previewMode: "app"
    property var workspaceId: null
    property var previewToplevels: []

    readonly property bool isVertical:
        verticalLayout || barPosition === "left" || barPosition === "right"
        || root._attachmentVertical

    hoverTarget: root.anchorItem
    hoverActivates: false
    alternativeVisibleCondition: root.previewOpen
    popupBackgroundMargin: 0

    function close(): void {
        root.previewOpen = false
    }

    function open(): void {
        if (root.previewToplevels.length === 0) {
            root.close()
            return
        }
        root.previewOpen = true
    }

    function show(appEntry: var, button: Item): void {
        root.previewMode = "app"
        root.workspaceId = null
        root.appEntry = appEntry
        root.anchorItem = button
        root.previewToplevels = appEntry?.toplevels ?? []
        if (root.previewToplevels.length === 0) {
            root.close()
            return
        }
        WindowPreviewService.captureForTaskView()
        root.open()
    }

    function showWorkspace(workspaceId: var, button: Item): void {
        root.previewMode = "workspace"
        root.appEntry = null
        root.workspaceId = workspaceId
        root.anchorItem = button
        root._refreshWorkspaceToplevels()
        if (root.previewToplevels.length === 0) {
            root.close()
            return
        }
        WindowPreviewService.captureForTaskView()
        root.open()
    }

    function _workspaceKeyMatches(candidate: var): bool {
        if (candidate === undefined || candidate === null
                || root.workspaceId === undefined || root.workspaceId === null)
            return false
        return String(candidate) === String(root.workspaceId)
    }

    function _workspaceToplevels(): var {
        if (CompositorService.isNiri) {
            // Niri's event stream is authoritative. Re-enrich the current
            // foreign-toplevel handles on demand so workspace hover also works
            // when the Bar taskbar itself is disabled and no sorting consumer
            // has populated CompositorService.sortedToplevels.
            const enriched = NiriService.sortToplevels(
                ToplevelManager.toplevels?.values ?? [])
            return enriched.filter(toplevel =>
                root._workspaceKeyMatches(toplevel?.niriWorkspaceId))
        }

        if (CompositorService.isHyprland) {
            const hyprlandToplevels = Hyprland.toplevels?.values ?? []
            const result = []
            for (const toplevel of hyprlandToplevels) {
                const ipcWorkspace = toplevel?.lastIpcObject?.workspace?.id
                const liveWorkspace = toplevel?.workspace?.id
                const candidate = ipcWorkspace ?? liveWorkspace
                if (!root._workspaceKeyMatches(candidate))
                    continue
                const wayland = toplevel?.wayland ?? null
                if (wayland)
                    result.push(wayland)
            }
            return result
        }

        return []
    }

    function _refreshWorkspaceToplevels(): void {
        if (root.previewMode !== "workspace")
            return
        root.previewToplevels = root._workspaceToplevels()
        if (root.previewOpen && root.previewToplevels.length === 0)
            root.close()
    }

    function _refreshAppToplevels(): void {
        if (root.previewMode !== "app" || !root.appEntry)
            return

        const appId = String(root.appEntry.appId ?? "").toLowerCase()
        if (appId.length === 0) {
            root.previewToplevels = root.appEntry.toplevels ?? []
            return
        }

        const sorted = CompositorService.sortedToplevels ?? []
        const allToplevels = sorted.length > 0
            ? sorted : (ToplevelManager.toplevels?.values ?? [])
        const current = allToplevels.filter(toplevel => {
            const id = AppSearch.resolveWindowIdentity(toplevel)
            return id && id.toLowerCase() === appId
        })
        root.previewToplevels = current

        if (root.previewOpen && current.length === 0)
            root.close()
        else if (current.length > 0)
            root.appEntry = Object.assign({}, root.appEntry, {
                toplevels: current
            })
    }

    function _refreshPreviewToplevels(): void {
        if (root.previewMode === "workspace")
            root._refreshWorkspaceToplevels()
        else
            root._refreshAppToplevels()
    }

    onAnchorItemChanged: {
        if (root.previewOpen && !root.anchorItem)
            root.close()
    }

    Item {
        id: previewContent

        // StyledPopup's default property is Item-only. Keep all non-visual
        // listeners inside the one visual content Item so QML never tries to
        // assign Connections objects to contentItem.
        Connections {
            target: ToplevelManager.toplevels
            function onValuesChanged(): void {
                root._refreshPreviewToplevels()
            }
        }

        Connections {
            target: CompositorService
            function onSortedToplevelsChanged(): void {
                if (root.previewMode === "app")
                    root._refreshAppToplevels()
            }
        }

        Connections {
            target: NiriService
            enabled: CompositorService.isNiri
            function onWindowsChanged(): void {
                root._refreshWorkspaceToplevels()
            }
            function onAllWorkspacesChanged(): void {
                root._refreshWorkspaceToplevels()
            }
        }

        Connections {
            target: Hyprland.toplevels
            enabled: CompositorService.isHyprland
            function onValuesChanged(): void {
                root._refreshWorkspaceToplevels()
            }
        }

        clip: true
        implicitWidth: root.isVertical
            ? Math.min(184, windowsLayout.implicitWidth)
            : windowsLayout.implicitWidth
        implicitHeight: root.isVertical
            ? windowsLayout.implicitHeight
            : Math.min(144, windowsLayout.implicitHeight)

        // Gives the pointer time to travel across the connected shoulder from
        // either a taskbar button or workspace button into the preview content.
        Timer {
            interval: 250
            running: root.previewOpen
                && !root.popupHovered && !root.dockHovered
            onTriggered: root.close()
        }

        GridLayout {
            id: windowsLayout

            anchors.centerIn: parent
            rowSpacing: 8
            columnSpacing: 8
            columns: root.isVertical ? 1 : -1
            rows: root.isVertical ? -1 : 1

            Repeater {
                model: ScriptModel {
                    values: root.previewToplevels
                }

                delegate: BarTaskbarWindowPreview {
                    required property var modelData

                    toplevel: modelData
                    onWindowActivated: {
                        if (!(Config.options?.dock?.keepPreviewOnClick ?? false))
                            root.close()
                    }
                }
            }
        }
    }
}
