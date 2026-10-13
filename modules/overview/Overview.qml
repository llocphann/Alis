import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.perimeter
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    Component.onCompleted: CompositorService.setSortingConsumer("overview", GlobalStates.overviewOpen)
    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            property bool _presentedOpen: false
            property string searchingText: ""
            readonly property bool taskViewMode: GlobalStates.overviewMode === "taskview"
            readonly property HyprlandMonitor monitor: CompositorService.isHyprland ? Hyprland.monitorFor(root.screen) : null
            property bool monitorIsFocused: CompositorService.isHyprland 
                ? (Hyprland.focusedMonitor?.id == monitor?.id)
                : (NiriService.currentOutput === root.screen?.name)
            readonly property bool activeScreenOnly: Config.options?.overview?.activeScreenOnly ?? true
            readonly property bool isTargetOutput:
                GlobalStates.overviewPresentationOutput === (root.modelData?.name ?? "")
            readonly property bool shouldShow: GlobalStates.overviewOpen
                && (taskViewMode ? isTargetOutput : (!activeScreenOnly || isTargetOutput))
            readonly property bool dashboardPresentationMode:
                !root.taskViewMode && root.searchingText === ""
            readonly property bool applicationsPresentationMode:
                !root.taskViewMode && root.searchingText !== ""
            readonly property string outputName: String(root.modelData?.name ?? "")
            readonly property bool iiFamily:
                (Config.options?.panelFamily ?? "ii") === "ii"
            readonly property bool bottomBarConfigured: root.iiFamily
                && !(Config.options?.bar?.vertical ?? false)
                && (Config.options?.bar?.bottom ?? false)
                && (Config.options?.enabledPanels ?? []).includes("iiBar")
                && GlobalStates.barOpen
            readonly property bool bottomBarTargetsOutput: {
                if (!root.bottomBarConfigured || root.outputName.length === 0)
                    return false
                const list = Config.options?.bar?.screenList ?? []
                if (!list || list.length === 0)
                    return true
                const matched = Quickshell.screens.filter(screen => {
                    const screenName = String(screen?.name ?? "")
                    return screenName.length > 0 && list.includes(screenName)
                })
                return matched.length === 0 || list.includes(root.outputName)
            }
            readonly property bool bottomBarOwnsEdge:
                root.bottomBarConfigured && root.bottomBarTargetsOutput
            readonly property real screenEdgeThickness: Math.max(1, Math.min(32,
                Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
            readonly property real bottomAttachmentThickness: root.bottomBarOwnsEdge
                ? Appearance.sizes.barHeight : root.screenEdgeThickness
            // Rest at the real inner boundary of the owning bottom Bar/Screen
            // Edge. The translated Dashboard then retracts behind that owner,
            // matching the same slide-under contract as connected popups.
            readonly property real bottomAttachmentY: root.height
                - root.bottomAttachmentThickness
            readonly property bool applicationDragActive:
                (dashboardPanel.item?.applicationDragActive ?? false)
                || (allAppsGridLoader.item?.applicationDragActive ?? false)
            screen: modelData

            function present(): void {
                _overviewCloseTimer.stop()
                visible = true
                Qt.callLater(() => {
                    if (!root.shouldShow)
                        return
                    root._presentedOpen = true
                    if (!root.isTargetOutput)
                        return
                    if (root.taskViewMode) {
                        overviewScope.dontAutoCancelSearch = false
                        dashboardPanel.item?.cancelSearch()
                        columnLayout.forceActiveFocus()
                    } else {
                        const prefix = GlobalStates.overviewSearchPrefix
                        if (prefix.length > 0) {
                            overviewScope.dontAutoCancelSearch = true
                            root.setSearchingText(prefix)
                        } else {
                            dashboardPanel.item?.cancelSearch()
                        }
                        dashboardPanel.item?.focusSearchInput()
                        root.maybeSwitchWorkspaceOnOpen()
                    }
                    delayedGrabTimer.start()
                })
            }

            function dismiss(): void {
                root._presentedOpen = false
                _overviewCloseTimer.restart()
            }

            Component.onCompleted: root.shouldShow ? root.present() : (root.visible = false)
            onShouldShowChanged: root.shouldShow ? root.present() : root.dismiss()

            Timer {
                id: _overviewCloseTimer
                // Cover the full exit animation (elementMoveExit scales with the
                // enterExit speed setting) plus a small margin so the window is
                // never torn down mid-close.
                interval: (Appearance.animation.elementMoveExit.duration + 40)
                onTriggered: root.visible = false
            }

            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            // Keyboard focus only on the monitor that should show
            WlrLayershell.keyboardFocus: root.shouldShow
                && !root.applicationDragActive
                && !GlobalStates.regionSelectorOpen
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            mask: Region {
                item: root.applicationDragActive ? emptyDragMask : overviewInputMask
            }

            Item {
                id: emptyDragMask
                width: 0
                height: 0
            }

            Item {
                id: overviewInputMask
                anchors.fill: parent
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Scrim de fondo: oscurece todo detrás del overview mientras está activo
            Rectangle {
                anchors.fill: parent
                z: -1
                color: {
                    const ov = Config.options?.overview ?? null
                    const v = (ov && ov.scrimDim !== undefined) ? ov.scrimDim : 35
                    const clamped = Math.max(0, Math.min(100, v))
                    const a = clamped / 100
                    return ColorUtils.transparentize(Appearance.colors.colLayer0Base, 1 - a)
                }
                // Dashboard is now a connected popup, not a full Overview scene.
                // Do not dim the wallpaper behind it; search/task-view presentation
                // still owns the ordinary Overview scrim.
                opacity: root.dashboardPresentationMode
                    ? 0 : (root._presentedOpen ? 1 : 0)
                visible: opacity > 0.001

                // The scrim fades a little slower than the content on the way out, so
                // the dimmed backdrop lingers under the dissolving panel instead of
                // snapping the desktop back before the surface has left.
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root._presentedOpen
                            ? Appearance.animation.elementMoveEnter.duration
                            : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root._presentedOpen
                            ? Appearance.animationCurves.standardDecel
                            : Appearance.animationCurves.standardAccel
                    }
                }
            }

            MouseArea {
                id: backdropClickArea
                anchors.fill: parent
                enabled: !root.applicationDragActive
                onClicked: mouse => {
                    // Cierra solo si el click es fuera del contenido visible
                    // Check the visible launcher/task surfaces, not columnLayout.
                    // because columnLayout fills the whole window height
                    const overviewPos = overviewLoader.item ? mapToItem(overviewLoader.item, mouse.x, mouse.y) : null
                    const inOverview = overviewLoader.item && overviewPos &&
                                       overviewPos.x >= 0 && overviewPos.x <= overviewLoader.item.width &&
                                       overviewPos.y >= 0 && overviewPos.y <= overviewLoader.item.height

                    const dashPos = dashboardPanel.visible ? mapToItem(dashboardPanel, mouse.x, mouse.y) : null
                    const inDashboard = dashboardPanel.visible && dashPos &&
                                        dashPos.x >= 0 && dashPos.x <= dashboardPanel.width &&
                                        dashPos.y >= 0 && dashPos.y <= dashboardPanel.height

                    const allAppsPos = allAppsGridLoader.item ? mapToItem(allAppsGridLoader.item, mouse.x, mouse.y) : null
                    const inAllApps = allAppsGridLoader.item && allAppsPos &&
                                      allAppsPos.x >= 0 && allAppsPos.x <= allAppsGridLoader.item.width &&
                                      allAppsPos.y >= 0 && allAppsPos.y <= allAppsGridLoader.item.height
                    
                    if (!inOverview && !inDashboard && !inAllApps) {
                        GlobalStates.overviewOpen = false
                    }
                }
            }

            // Focus grab for Hyprland (doesn't work on Niri)
            CompositorFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.shouldShow && root.isTargetOutput
                active: false
                onCleared: () => {
                    if (!active)
                        GlobalStates.overviewOpen = false;
                }
            }
            
            // For Niri: detect window focus changes to close overview (if configured)
            Connections {
                target: CompositorService.isNiri ? NiriService : null
                enabled: CompositorService.isNiri
                function onActiveWindowChanged() {
                    // Respect keepOverviewOpenOnWindowClick setting
                    const keepOpen = Config.options?.overview?.keepOverviewOpenOnWindowClick ?? true;
                    // If a window gets focus while overview is open, close it only if not configured to keep open
                    if (GlobalStates.overviewOpen && NiriService.activeWindow && !keepOpen) {
                        GlobalStates.overviewOpen = false;
                    }
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    CompositorService.setSortingConsumer("overview", GlobalStates.overviewOpen)
                    if (!GlobalStates.overviewOpen) {
                        // Al cerrar, limpiar completamente la búsqueda
                        dashboardPanel.item?.cancelSearch();
                        dashboardPanel.item?.disableExpandAnimation();
                        overviewScope.dontAutoCancelSearch = false;
                        GlobalStates.overviewSearchPrefix = "";
                    } else {
                        if (!overviewScope.dontAutoCancelSearch) {
                            dashboardPanel.item?.cancelSearch();
                        }
                    }
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!root.shouldShow || !grab.canBeActive)
                        return;
                    grab.active = GlobalStates.overviewOpen;
                }
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight

            function setSearchingText(text) {
                root.searchingText = text
                dashboardPanel.item?.setSearchingText(text)
                dashboardPanel.item?.focusFirstItem()
            }

            function maybeSwitchWorkspaceOnOpen() {
                const ov = Config.options?.overview ?? null;
                if (!ov || !ov.switchToWorkspaceOnOpen || !ov.switchWorkspaceIndex || ov.switchWorkspaceIndex <= 0)
                    return;

                if (CompositorService.isNiri) {
                    const screenName = root.modelData && root.modelData.name;
                    if (!screenName)
                        return;
                    const targetIdx = ov.switchWorkspaceIndex;
                    if (!targetIdx || targetIdx <= 0)
                        return;
                    const targetWorkspace = NiriService.allWorkspaces.find(workspace =>
                        workspace.output === screenName && workspace.idx === targetIdx)
                    if (targetWorkspace)
                        NiriService.switchToWorkspaceById(targetWorkspace.id)
                } else if (CompositorService.isHyprland) {
                    if (!root.isTargetOutput)
                        return;
                    const wsNumber = ov.switchWorkspaceIndex;
                    Hyprland.dispatch(`workspace ${wsNumber}`);
                }
            }

            Column {
                id: columnLayout

                // Shell desaturation effect
                layer.enabled: Appearance.shouldDesaturate("overlays") && columnLayout.visible
                layer.effect: ShellDesaturationEffect {}

                // Task View keeps its scene transition. Launcher mode never fades
                // or scales; the unified Dashboard owns the spatial slide.
                readonly property int motionDuration: root._presentedOpen
                    ? Appearance.animation.elementMoveEnter.duration
                    : Appearance.animation.elementMoveExit.duration
                readonly property var motionCurve: root._presentedOpen
                    ? Appearance.animation.elementMoveEnter.bezierCurve
                    : Appearance.animationCurves.emphasizedDecel
                property real openProgress: root._presentedOpen ? 1 : 0

                opacity: root.taskViewMode
                    ? (root._presentedOpen
                        ? Math.min(1, openProgress / 0.7)
                        : Math.max(0, (openProgress - 0.45) / 0.55))
                    : 1
                visible: openProgress > 0.001

                transform: [
                    Scale {
                        origin.x: columnLayout.width / 2
                        origin.y: columnLayout.height / 2
                        xScale: root.taskViewMode ? 0.94 + 0.06 * columnLayout.openProgress : 1
                        yScale: root.taskViewMode ? 0.94 + 0.06 * columnLayout.openProgress : 1
                    },
                    Translate {
                        y: root.taskViewMode ? (1 - columnLayout.openProgress) * 8 : 0
                    }
                ]

                Behavior on openProgress {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: columnLayout.motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: columnLayout.motionCurve
                    }
                }
                
                // Always center the overview vertically - this is the default behavior.
                // Never use verticalCenter anchor with dynamic Column - causes blur and erratic positioning.
                // Use top anchor with calculated topMargin to center instead.
                
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: {
                        const ov = Config?.options?.overview;
                        const respectBar = ov && ov.respectBar !== undefined ? ov.respectBar : true;
                        if (!root.taskViewMode
                                && dashboardPanel.visible && dashboardPanel.item) {
                            const rect = dashboardPanel.item.connectedSurfaceRect
                                ?? Qt.rect(0, 0, dashboardPanel.width, dashboardPanel.height)
                            const bodyBottomInColumn = dashboardPanel.y + rect.y + rect.height
                            return Math.round(Math.max(0,
                                root.bottomAttachmentY - bodyBottomInColumn))
                        }
                        
                        // Calculate bar/dock offset at top
                        const frameRadius = Math.max(0, Math.min(96,
                            Number(Config.options?.appearance?.screenEdge?.radius
                                ?? PerimeterTokens.frameRadius)))
                        let barOffset = 0;
                        if (respectBar && !(Config.options?.bar?.bottom ?? false)) {
                            barOffset = Appearance.sizes.barHeight + frameRadius;
                        }
                        const dock = Config.options?.dock;
                        if (dock?.enable && dock?.position === "top") {
                            barOffset += (dock.height ?? 60) + 20;
                        }
                        
                        // Calculate bar/dock offset at bottom
                        let bottomOffset = 8;
                        if (respectBar && (Config.options?.bar?.bottom ?? false)) {
                            bottomOffset += Appearance.sizes.barHeight + frameRadius;
                        }
                        if (dock?.enable && dock?.position === "bottom") {
                            bottomOffset += (dock.height ?? 60) + 20;
                        }
                        
                        // Center the content vertically in available space
                        const availableHeight = root.height - barOffset - bottomOffset;
                        const contentHeight = columnLayout.implicitHeight;
                        // Round to avoid subpixel positioning that causes blur
                        const centeredMargin = barOffset + Math.round(Math.max(0, (availableHeight - contentHeight) / 2));
                        return centeredMargin;
                    }
                }
                spacing: root.taskViewMode ? 0 : -8


                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (dashboardPanel.item?.editing
                                && dashboardPanel.item?.handleEscape()) {
                            event.accepted = true
                            return
                        }
                        GlobalStates.overviewOpen = false;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        if (!root.searchingText) {
                            if (CompositorService.isNiri) {
                                const outputName = root.screen?.name ?? ""
                                const workspaces = NiriService.allWorkspaces
                                    .filter(workspace => workspace.output === outputName)
                                    .sort((a, b) => a.idx - b.idx)
                                const currentIndex = workspaces.findIndex(workspace => workspace.is_active)
                                if (currentIndex > 0)
                                    NiriService.switchToWorkspaceById(workspaces[currentIndex - 1].id)
                            } else {
                                Hyprland.dispatch("workspace r-1");
                            }
                        }
                    } else if (event.key === Qt.Key_Right) {
                        if (!root.searchingText) {
                            if (CompositorService.isNiri) {
                                const outputName = root.screen?.name ?? ""
                                const workspaces = NiriService.allWorkspaces
                                    .filter(workspace => workspace.output === outputName)
                                    .sort((a, b) => a.idx - b.idx)
                                const currentIndex = workspaces.findIndex(workspace => workspace.is_active)
                                if (currentIndex >= 0 && currentIndex < workspaces.length - 1)
                                    NiriService.switchToWorkspaceById(workspaces[currentIndex + 1].id)
                            } else {
                                Hyprland.dispatch("workspace r+1");
                            }
                        }
                    }
                }

                Loader {
                    id: overviewLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property bool dashboardMode: true
                    readonly property bool allAppsGridEnabled: Config.options?.overview?.allAppsGrid ?? false
                    // Workspace Overview now belongs to Bar workspace hover.
                    // This full-screen loader remains only for explicit Task View.
                    active: root.shouldShow && root.taskViewMode
                    visible: active && (root.searchingText == "")
                    sourceComponent: CompositorService.isNiri ? niriComponent : hyprComponent
                }

                Loader {
                    id: allAppsGridLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property bool allAppsEnabled: Config.options?.overview?.allAppsGrid ?? false
                    readonly property bool dashboardMode: true
                    active: root.shouldShow && !root.taskViewMode && allAppsEnabled && !dashboardMode
                    visible: active && (root.searchingText == "")
                    sourceComponent: allAppsGridComponent
                }

                Component {
                    id: hyprComponent
                    OverviewWidget {
                        panelWindow: root
                        visible: (root.searchingText == "")
                    }
                }

                Component {
                    id: niriComponent
                    OverviewNiriWidget {
                        panelWindow: root
                        taskViewMode: root.taskViewMode
                        visible: (root.searchingText == "")
                    }
                }

                Component {
                    id: allAppsGridComponent
                    OverviewAllAppsGrid {
                        panelVisible: root.visible
                        availableHeight: Math.max(400, root.height * 0.78)
                        onAppLaunched: GlobalStates.overviewOpen = false
                    }
                }

                // One launcher surface owns Dashboard + search. It stays mapped
                // while typing so content can slide down as the body resizes.
                Loader {
                    id: dashboardPanel
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: !root.taskViewMode
                    visible: active && status === Loader.Ready
                        && (root._presentedOpen || (item?.revealProgress ?? 0) > 0.001)
                    opacity: 1
                    onLoaded: {
                        if (root.isTargetOutput && root._presentedOpen)
                            Qt.callLater(() => item?.focusSearchInput())
                    }
                    sourceComponent: Component {
                        OverviewDashboard {
                            panelVisible: root.visible
                            directBottomAttachment: true
                            popupPresented: root._presentedOpen
                            searchingText: root.searchingText
                            availableWidth: root.width
                            availableHeight: root.height
                            attachmentThickness: root.bottomAttachmentThickness
                            onSearchingTextChanged: if (searchingText !== root.searchingText) root.searchingText = searchingText
                        }
                    }
                }
            }
        }
    }

}
