import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.notificationCenter
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../abyss/looks/AbyssLayout.js" as ModuleLayout
import "../abyss/looks/AbyssGeometry.js" as Geometry

Scope {
    id: screenCorners
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    // Keyboard capture is exclusive across outputs. Hover previews can be
    // transient on more than one monitor, but once one Quick Notes editor is
    // clicked, keep every other bottom-left trigger dormant until it releases.
    property string quickNotesEditorOutput: ""

    function setQuickNotesEditorOutput(outputName, focused): void {
        const name = String(outputName ?? "")
        if (focused) {
            // Treat ownership like a compare-and-set. The visibility binding
            // normally prevents two outputs from entering editor mode at once,
            // but near-simultaneous clicks must not let the later signal steal
            // keyboard ownership from an already-focused popup.
            if (name && (!screenCorners.quickNotesEditorOutput
                    || screenCorners.quickNotesEditorOutput === name))
                screenCorners.quickNotesEditorOutput = name
            return
        }
        if (screenCorners.quickNotesEditorOutput === name)
            screenCorners.quickNotesEditorOutput = ""
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            const owner = screenCorners.quickNotesEditorOutput
            if (!owner)
                return
            const ownerStillConnected = Quickshell.screens.some(
                screen => String(screen?.name ?? "") === owner)
            if (!ownerStillConnected)
                screenCorners.quickNotesEditorOutput = ""
        }
    }

    property var actionForCorner: ({
        "topLeft": outputName => GlobalStates.toggleSidebarLeft(outputName),
        "bottomLeft": outputName => GlobalStates.toggleSidebarLeft(outputName),
        "topRight": outputName => GlobalStates.toggleSidebarRight(outputName),
        "bottomRight": outputName => GlobalStates.toggleSidebarRight(outputName)
    })

    component CornerPanelWindow: PanelWindow {
        id: cornerPanelWindow
        property var screen: QsWindow.window?.screen
        property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
        property bool fullscreen
        property string corner: ""
        readonly property bool isTopLeft: corner === "topLeft"
        readonly property bool isTopRight: corner === "topRight"
        readonly property bool isBottomLeft: corner === "bottomLeft"
        readonly property bool isBottomRight: corner === "bottomRight"
        readonly property bool isTop: isTopLeft || isTopRight
        readonly property bool isBottom: isBottomLeft || isBottomRight
        readonly property bool isLeft: isTopLeft || isBottomLeft
        readonly property bool isRight: isTopRight || isBottomRight

        Component.onDestruction: {
            screenCorners.setQuickNotesEditorOutput(
                cornerPanelWindow.outputName, false)
            GlobalStates.setNotificationCenterHoverOutput(
                cornerPanelWindow.outputName, false)
        }

        // Interaction-only corner windows. Physical rounding is owned exclusively
        // by ScreenEdges.qml's canonical full-screen frame.
        readonly property bool cornerOpenEnabled: Config?.options?.sidebar?.cornerOpen?.enable ?? false
        readonly property bool cornerOpenAtBottom: Config?.options?.sidebar?.cornerOpen?.bottom ?? false
        readonly property bool cornerOpenMatchesPosition: cornerOpenAtBottom === cornerPanelWindow.isBottom
        readonly property bool shouldShowCornerOpen: cornerOpenEnabled
            && cornerOpenMatchesPosition && !fullscreen
        readonly property string cornerName: cornerPanelWindow.corner
        readonly property string outputName: cornerPanelWindow.screen?.name ?? ""
        // Keep legacy corner anchors as an exact rollback path on every output
        // where its unified Abyss replacement is absent or disabled. The
        // module owns only the matching feature, never unrelated hot corners.
        function hasUnifiedEdgeReplacement(kind): bool {
            // The selectable Edgebar mode restores the mature physical
            // corner dwell target; module-hosted popups do not compete for it.
            return ModuleLayout.unifiedLauncherMode(
                Config.options?.abyss?.modules,kind) === "module"
                && GlobalStates.barOpen
                && (Config.options?.enabledPanels ?? []).includes("abyssBar")
                && Geometry.targets(outputName,Config.options?.bar?.screenList ?? [],
                    Quickshell.screens.map(screen => screen.name))
                && ModuleLayout.hasEnabledModule(
                    Config.options?.abyss?.modules,outputName,kind)
        }
        // Orbit was retired from the live graph. Only the compositor's real
        // overview hot corner keeps priority over shell corner interactions.
        readonly property bool niriOverviewOwnsCorner: CompositorService.isNiri
            && NiriService.isOverviewHotCornerActive(outputName, cornerName)
        readonly property bool cornerPopupInteractionBlocked:
            GlobalStates.screenLocked
            || GlobalStates.bootGreetingOpen
            || GlobalStates.crosshairOpen
            || GlobalStates.sidebarLeftOpen
            || GlobalStates.sidebarRightOpen
            || GlobalStates.mediaControlsOpen
            || GlobalStates.oskOpen
            || GlobalStates.overlayOpen
            || GlobalStates.overviewOpen
            || GlobalStates.altSwitcherOpen
            || GlobalStates.clipboardOpen
            || GlobalStates.settingsOverlayOpen
            || GlobalStates.settingsNativeDialogOpen
            || GlobalStates.regionSelectorOpen
            || GlobalStates.tilingOverlayPickerOpen
            || GlobalStates.tilingOverlayOsdOpen
            || GlobalStates.annotationEditorOpen
            || GlobalStates.sessionOpen
            || GlobalStates.wallpaperSelectorOpen
            || GlobalStates.wallpaperLauncherOpen
            || GlobalStates.widgetEditMode
            || GlobalStates.shellLayoutEditMode
            || GlobalStates.cheatsheetOpen
            || GlobalStates.coverflowSelectorOpen
            || GlobalStates.controlPanelOpen
            || GlobalStates.dashboardOpen
            || GlobalStates.searchOpen
        readonly property bool quickNotesInteractionBlocked:
            cornerPanelWindow.cornerPopupInteractionBlocked
            || GlobalStates.notificationCenterOpen
        readonly property bool notificationCenterInteractionBlocked:
            cornerPanelWindow.cornerPopupInteractionBlocked
            || screenCorners.quickNotesEditorOutput.length > 0
        readonly property string quickNotesMonitorMode:
            Config.options?.quickNotes?.monitorMode ?? "all"
        readonly property bool quickNotesMonitorAllowed:
            quickNotesMonitorMode !== "primary"
            || outputName === (GlobalStates.primaryScreen?.name ?? "")

        function quickNotesBarTargetsOutput(): bool {
            if (outputName.length === 0)
                return false
            const configured = Config.options?.bar?.screenList ?? []
            if (!configured || configured.length === 0)
                return true
            const connectedMatches = Quickshell.screens.filter(screen => {
                const name = String(screen?.name ?? "")
                return name.length > 0 && configured.includes(name)
            })
            return connectedMatches.length === 0 || configured.includes(outputName)
        }

        readonly property bool quickNotesBarVertical:
            Config.options?.bar?.vertical ?? false
        readonly property bool quickNotesBarTrailing:
            Config.options?.bar?.bottom ?? false
        readonly property string quickNotesBarPanelId:
            quickNotesBarVertical ? "iiVerticalBar" : "iiBar"
        readonly property bool quickNotesBarOwnsConfiguredEdge:
            GlobalStates.barOpen
            && !GlobalStates.widgetEditMode
            && (Config.options?.enabledPanels ?? []).includes(quickNotesBarPanelId)
            && !(Config.options?.bar?.autoHide?.enable ?? false)
            && cornerPanelWindow.quickNotesBarTargetsOutput()
        readonly property bool quickNotesBarOwnsBottom:
            quickNotesBarOwnsConfiguredEdge
            && !quickNotesBarVertical && quickNotesBarTrailing
        // The bottom-left corner remains bottom-attached even when a vertical
        // Bar owns the left edge. Switching attachment to left moves the body
        // towards the top because the tiny corner anchor has local y = 0.
        readonly property string quickNotesAttachmentEdge: "bottom"
        readonly property real quickNotesAttachmentThickness:
            quickNotesBarOwnsBottom ? Appearance.sizes.barHeight
            : Math.max(1, Math.min(32,
                Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))

        readonly property bool shouldShowQuickNotesCorner:
            (Config.options?.panelFamily ?? "ii") !== "waffle"
            && (Config.options?.quickNotes?.enable ?? true)
            && !cornerPanelWindow.hasUnifiedEdgeReplacement("notesTimers")
            && cornerPanelWindow.quickNotesMonitorAllowed
            && (screenCorners.quickNotesEditorOutput.length === 0
                || screenCorners.quickNotesEditorOutput === outputName)
            && cornerPanelWindow.isBottomLeft
            && !cornerPanelWindow.niriOverviewOwnsCorner
            && !cornerPanelWindow.quickNotesInteractionBlocked
            && !fullscreen

        function notificationCenterTargetsOutput(): bool {
            if (outputName.length === 0)
                return false
            const configured = Config.options?.notificationCenter?.screenList ?? []
            if (!configured || configured.length === 0)
                return true
            const connectedMatches = Quickshell.screens.filter(screen => {
                const name = String(screen?.name ?? "")
                return name.length > 0 && configured.includes(name)
            })
            return connectedMatches.length === 0 || configured.includes(outputName)
        }

        function notificationCenterBarTargetsOutput(): bool {
            if (outputName.length === 0)
                return false
            const configured = Config.options?.bar?.screenList ?? []
            if (!configured || configured.length === 0)
                return true
            const connectedMatches = Quickshell.screens.filter(screen => {
                const name = String(screen?.name ?? "")
                return name.length > 0 && configured.includes(name)
            })
            return connectedMatches.length === 0 || configured.includes(outputName)
        }

        readonly property bool notificationCenterExplicitForOutput:
            GlobalStates.notificationCenterExplicitOpen
            && GlobalStates.notificationCenterPresentationOutput === outputName
        readonly property bool notificationCenterAllowedInFullscreen:
            Config.options?.notificationCenter?.allowInFullscreen ?? false
        readonly property bool notificationCenterBarVertical:
            Config.options?.bar?.vertical ?? false
        readonly property bool notificationCenterBarTrailing:
            Config.options?.bar?.bottom ?? false
        readonly property string notificationCenterBarPanelId:
            notificationCenterBarVertical ? "iiVerticalBar" : "iiBar"
        readonly property bool notificationCenterBarOwnsConfiguredEdge:
            GlobalStates.barOpen
            && !GlobalStates.widgetEditMode
            && (Config.options?.enabledPanels ?? []).includes(
                notificationCenterBarPanelId)
            && !(Config.options?.bar?.autoHide?.enable ?? false)
            && cornerPanelWindow.notificationCenterBarTargetsOutput()
        readonly property bool notificationCenterBarOwnsRight:
            notificationCenterBarOwnsConfiguredEdge
            && notificationCenterBarVertical
            && notificationCenterBarTrailing
        readonly property bool notificationCenterBarOwnsBottom:
            notificationCenterBarOwnsConfiguredEdge
            && !notificationCenterBarVertical
            && notificationCenterBarTrailing
        readonly property string notificationCenterAttachmentEdge:
            notificationCenterBarOwnsRight ? "right" : "bottom"
        readonly property real notificationCenterAttachmentThickness:
            notificationCenterBarOwnsRight ? Appearance.sizes.verticalBarWidth
            : notificationCenterBarOwnsBottom ? Appearance.sizes.barHeight
            : Math.max(1, Math.min(32,
                Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
        readonly property bool shouldShowNotificationCenterCorner:
            (Config.options?.panelFamily ?? "ii") !== "waffle"
            && (Config.options?.notificationCenter?.enable ?? true)
            && (Config.options?.notificationCenter?.hoverEnable ?? true)
            && !cornerPanelWindow.hasUnifiedEdgeReplacement("notificationActivity")
            && cornerPanelWindow.notificationCenterTargetsOutput()
            && cornerPanelWindow.isBottomRight
            && !cornerPanelWindow.niriOverviewOwnsCorner
            && !cornerPanelWindow.notificationCenterInteractionBlocked
            && (!GlobalStates.notificationCenterExplicitOpen
                || cornerPanelWindow.notificationCenterExplicitForOutput)
            && (!fullscreen || notificationCenterAllowedInFullscreen)
        readonly property bool notificationCenterHostNeeded:
            (Config.options?.panelFamily ?? "ii") !== "waffle"
            && (Config.options?.notificationCenter?.enable ?? true)
            && !cornerPanelWindow.hasUnifiedEdgeReplacement("notificationActivity")
            && cornerPanelWindow.notificationCenterTargetsOutput()
            && cornerPanelWindow.isBottomRight
            && (!fullscreen || notificationCenterAllowedInFullscreen)
            && (cornerPanelWindow.shouldShowNotificationCenterCorner
                || cornerPanelWindow.notificationCenterExplicitForOutput
                || GlobalStates.notificationCenterHoverOutput === outputName)

        function reconcileNotificationCenterFullscreenPolicy(): void {
            if (fullscreen
                    && !cornerPanelWindow.notificationCenterAllowedInFullscreen
                    && cornerPanelWindow.notificationCenterExplicitForOutput)
                GlobalStates.closeNotificationCenter()
        }

        onFullscreenChanged:
            cornerPanelWindow.reconcileNotificationCenterFullscreenPolicy()
        onNotificationCenterExplicitForOutputChanged:
            cornerPanelWindow.reconcileNotificationCenterFullscreenPolicy()
        onNotificationCenterAllowedInFullscreenChanged:
            cornerPanelWindow.reconcileNotificationCenterFullscreenPolicy()

        // Explicit corner features own their physical corner before the legacy
        // sidebar trigger. This lets bottom-left become Quick Notes without
        // deleting the old corner-open compatibility settings.
        readonly property bool shouldShowSidebarCornerOpen: shouldShowCornerOpen
            && !niriOverviewOwnsCorner
            && !shouldShowQuickNotesCorner
            && !notificationCenterHostNeeded

        visible: (!fullscreen && (shouldShowSidebarCornerOpen
            || shouldShowQuickNotesCorner))
            || notificationCenterHostNeeded

        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            item: quickNotesCornerLoader.active ? quickNotesCornerLoader
                : (cornerPanelWindow.shouldShowNotificationCenterCorner
                    && notificationCenterCornerLoader.active)
                    ? notificationCenterCornerLoader
                : (sidebarCornerOpenInteractionLoader.active
                    ? sidebarCornerOpenInteractionLoader : null)
        }
        WlrLayershell.namespace: "quickshell:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        anchors {
            top: cornerPanelWindow.isTopLeft || cornerPanelWindow.isTopRight
            left: cornerPanelWindow.isBottomLeft || cornerPanelWindow.isTopLeft
            bottom: cornerPanelWindow.isBottomLeft || cornerPanelWindow.isBottomRight
            right: cornerPanelWindow.isTopRight || cornerPanelWindow.isBottomRight
        }
        margins {
            right: ((Config.options?.interactions?.deadPixelWorkaround?.enable ?? false) && cornerPanelWindow.anchors.right) * -1
            bottom: ((Config.options?.interactions?.deadPixelWorkaround?.enable ?? false) && cornerPanelWindow.anchors.bottom) * -1
        }

        implicitWidth: cornerWidget.implicitWidth
        implicitHeight: cornerWidget.implicitHeight

        Item {
            id: cornerWidget
            anchors.fill: parent

            // Size for corner open interaction area
            readonly property int cornerOpenWidth: Config.options?.sidebar?.cornerOpen?.cornerRegionWidth ?? 20
            readonly property int cornerOpenHeight: Config.options?.sidebar?.cornerOpen?.cornerRegionHeight ?? 20
            readonly property int quickNotesCornerSize: Math.max(4, Math.min(48,
                Config.options?.quickNotes?.cornerSize ?? 14))
            readonly property int notificationCenterCornerSize: Math.max(4, Math.min(48,
                Config.options?.notificationCenter?.cornerSize ?? 14))

            implicitWidth: Math.max(0,
                cornerPanelWindow.shouldShowSidebarCornerOpen ? cornerOpenWidth : 0,
                cornerPanelWindow.shouldShowQuickNotesCorner ? quickNotesCornerSize : 0,
                cornerPanelWindow.notificationCenterHostNeeded
                    ? notificationCenterCornerSize : 0)
            implicitHeight: Math.max(0,
                cornerPanelWindow.shouldShowSidebarCornerOpen ? cornerOpenHeight : 0,
                cornerPanelWindow.shouldShowQuickNotesCorner ? quickNotesCornerSize : 0,
                cornerPanelWindow.notificationCenterHostNeeded
                    ? notificationCenterCornerSize : 0)

            // Bottom-left Quick Notes uses a dwell-gated synthetic
            // containsMouse property. StyledPopup can therefore keep its normal
            // pointer bridge between the tiny corner anchor and the popup body
            // without opening on accidental high-speed corner passes.
            Loader {
                id: quickNotesCornerLoader
                active: cornerPanelWindow.shouldShowQuickNotesCorner
                onActiveChanged: {
                    if (!active)
                        screenCorners.setQuickNotesEditorOutput(
                            cornerPanelWindow.outputName, false)
                }
                anchors {
                    bottom: parent.bottom
                    left: parent.left
                }

                sourceComponent: Item {
                    id: quickNotesAnchor
                    implicitWidth: cornerWidget.quickNotesCornerSize
                    implicitHeight: cornerWidget.quickNotesCornerSize
                    property bool dwellReady: false
                    property bool containsMouse:
                        dwellReady && quickNotesHitArea.containsMouse

                    MouseArea {
                        id: quickNotesHitArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton

                        onEntered: {
                            if (quickNotesPopup.active) {
                                quickNotesDwellTimer.stop()
                                quickNotesAnchor.dwellReady = true
                            } else {
                                quickNotesDwellTimer.restart()
                            }
                        }
                        onExited: {
                            quickNotesDwellTimer.stop()
                            quickNotesAnchor.dwellReady = false
                        }
                    }

                    Timer {
                        id: quickNotesDwellTimer
                        interval: Math.max(1,
                            Config.options?.quickNotes?.hoverDelayMs ?? 220)
                        repeat: false
                        onTriggered: {
                            if (quickNotesHitArea.containsMouse)
                                quickNotesAnchor.dwellReady = true
                        }
                    }

                    QuickNotesPopup {
                        id: quickNotesPopup
                        anchorItem: quickNotesAnchor
                        cornerAttachmentEdge: cornerPanelWindow.quickNotesAttachmentEdge
                        cornerAttachmentThickness: cornerPanelWindow.quickNotesAttachmentThickness
                        onEditorFocusedChanged:
                            screenCorners.setQuickNotesEditorOutput(
                                cornerPanelWindow.outputName, editorFocused)
                    }
                }
            }

            // Bottom-right Notification Center mirrors the Quick Notes dwell
            // contract, but keeps history state separate from transient toasts.
            Loader {
                id: notificationCenterCornerLoader
                active: cornerPanelWindow.notificationCenterHostNeeded
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                }

                sourceComponent: Item {
                    id: notificationCenterAnchor
                    implicitWidth: cornerWidget.notificationCenterCornerSize
                    implicitHeight: cornerWidget.notificationCenterCornerSize
                    property bool dwellReady: false
                    property bool containsMouse:
                        dwellReady
                        && cornerPanelWindow.shouldShowNotificationCenterCorner
                        && notificationCenterHitArea.containsMouse

                    MouseArea {
                        id: notificationCenterHitArea
                        anchors.fill: parent
                        enabled: cornerPanelWindow.shouldShowNotificationCenterCorner
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton

                        onEntered: {
                            if (!enabled)
                                return
                            if (notificationCenterPopup.active) {
                                notificationCenterDwellTimer.stop()
                                notificationCenterAnchor.dwellReady = true
                            } else {
                                notificationCenterDwellTimer.restart()
                            }
                        }

                        onExited: {
                            notificationCenterDwellTimer.stop()
                            notificationCenterAnchor.dwellReady = false
                            notificationCenterPopup.rearmHoverIfIdle()
                        }
                    }

                    Timer {
                        id: notificationCenterDwellTimer
                        interval: Math.max(1,
                            Config.options?.notificationCenter?.hoverDelayMs ?? 220)
                        repeat: false
                        onTriggered: {
                            if (notificationCenterHitArea.enabled
                                    && notificationCenterHitArea.containsMouse)
                                notificationCenterAnchor.dwellReady = true
                        }
                    }

                    NotificationCenterPopup {
                        id: notificationCenterPopup
                        anchorItem: notificationCenterAnchor
                        outputName: cornerPanelWindow.outputName
                        hoverAllowed:
                            cornerPanelWindow.shouldShowNotificationCenterCorner
                        cornerAttachmentEdge:
                            cornerPanelWindow.notificationCenterAttachmentEdge
                        cornerAttachmentThickness:
                            cornerPanelWindow.notificationCenterAttachmentThickness
                    }
                }
            }

            Loader {
                id: sidebarCornerOpenInteractionLoader
                active: cornerPanelWindow.shouldShowSidebarCornerOpen
                anchors {
                    top: (cornerPanelWindow.isTopLeft || cornerPanelWindow.isTopRight) ? parent.top : undefined
                    bottom: (cornerPanelWindow.isBottomLeft || cornerPanelWindow.isBottomRight) ? parent.bottom : undefined
                    left: (cornerPanelWindow.isLeft) ? parent.left : undefined
                    right: (cornerPanelWindow.isTopRight || cornerPanelWindow.isBottomRight) ? parent.right : undefined
                }

                sourceComponent: FocusedScrollMouseArea {
                    id: mouseArea
                    implicitWidth: cornerWidget.cornerOpenWidth
                    implicitHeight: cornerWidget.cornerOpenHeight
                    hoverEnabled: true
                    onPositionChanged: {
                        // The top-right corner is click-only, even when legacy
                        // clicklessCornerEnd is enabled. Keep its volume scroll.
                        if (cornerPanelWindow.isTopRight) return;
                        if (Config.options?.sidebar?.cornerOpen?.clickless ?? false) return;
                        if (!(Config.options?.sidebar?.cornerOpen?.clicklessCornerEnd ?? false)) return;
                        const verticalOffset = Config.options?.sidebar?.cornerOpen?.clicklessCornerVerticalOffset ?? 10;
                        const correctX = (cornerPanelWindow.isRight && mouseArea.mouseX >= mouseArea.width - 2) || (cornerPanelWindow.isLeft && mouseArea.mouseX <= 2);
                        const correctY = (cornerPanelWindow.isTop && mouseArea.mouseY > verticalOffset || cornerPanelWindow.isBottom && mouseArea.mouseY < mouseArea.height - verticalOffset);
                        if (correctX && correctY)
                            screenCorners.actionForCorner[cornerPanelWindow.corner](cornerPanelWindow.screen?.name ?? "");
                    }
                    onEntered: {
                        if (!cornerPanelWindow.isTopRight && (Config.options?.sidebar?.cornerOpen?.clickless ?? false))
                            screenCorners.actionForCorner[cornerPanelWindow.corner](cornerPanelWindow.screen?.name ?? "");
                    }
                    onPressed: {
                        if (cornerPanelWindow.isTopRight || !(Config.options?.sidebar?.cornerOpen?.clickless ?? false)) {
                            screenCorners.actionForCorner[cornerPanelWindow.corner](cornerPanelWindow.screen?.name ?? "");
                            if (Config.options?.background?.effects?.ripple?.hotcorners ?? true) {
                                GlobalStates.requestRipple(0, 0, cornerPanelWindow.screen.name);
                            }
                        }
                    }
                    onScrollDown: {
                        if (!(Config.options?.sidebar?.cornerOpen?.valueScroll ?? false))
                            return;
                        if (cornerPanelWindow.isLeft)
                            cornerPanelWindow.brightnessMonitor.setBrightness(cornerPanelWindow.brightnessMonitor.brightness - 0.05);
                        else {
                            Audio.decrementVolume();
                        }
                    }
                    onScrollUp: {
                        if (!(Config.options?.sidebar?.cornerOpen?.valueScroll ?? false))
                            return;
                        if (cornerPanelWindow.isLeft)
                            cornerPanelWindow.brightnessMonitor.setBrightness(cornerPanelWindow.brightnessMonitor.brightness + 0.05);
                        else {
                            Audio.incrementVolume();
                        }
                    }
                    onMovedAway: {
                        if (!(Config.options?.sidebar?.cornerOpen?.valueScroll ?? false))
                            return;
                        if (cornerPanelWindow.isLeft)
                            GlobalStates.osdBrightnessOpen = false;
                        else
                            GlobalStates.osdVolumeOpen = false;
                    }

                    Loader {
                        active: Config.options?.sidebar?.cornerOpen?.visualize ?? false
                        anchors.fill: parent
                        sourceComponent: Rectangle {
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            property HyprlandMonitor monitor: CompositorService.isHyprland ? Hyprland.monitorFor(modelData) : null

            // Hide when fullscreen
            property list<HyprlandWorkspace> workspacesForMonitor: CompositorService.isHyprland
                ? Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
                : []
            property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
            property bool fullscreen: {
                if (CompositorService.isHyprland) {
                    return activeWorkspaceWithFullscreen != undefined;
                }
                // Corner windows are interaction-only and reserve no work area,
                // so they can safely follow automatic fullscreen detection.
                if (CompositorService.isNiri)
                    return GameMode.hasFullscreenOnOutput(modelData?.name ?? "")
                return false;
            }

            CornerPanelWindow {
                screen: modelData
                corner: "topLeft"
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: "topRight"
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: "bottomLeft"
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: "bottomRight"
                fullscreen: monitorScope.fullscreen
            }
        }
    }
}
