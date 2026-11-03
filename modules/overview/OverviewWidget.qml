pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    required property var panelWindow
    property bool embeddedSurface: false
    property bool verticalLayout: false
    property bool presentationActive: GlobalStates.overviewOpen
    // Keep local spatial motion static during popup materialization; once fully
    // revealed, later workspace/window changes may animate normally.
    property bool focusIndicatorAnimationReady: true
    readonly property bool localGeometryAnimationReady:
        !root.embeddedSurface || root.focusIndicatorAnimationReady
    property var preferredWorkspaceId: null
    signal presentationCloseRequested()

    function requestPresentationClose(): void {
        if (root.embeddedSurface)
            root.presentationCloseRequested()
        else
            GlobalStates.overviewOpen = false
    }

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property var toplevels: ToplevelManager.toplevels
    readonly property int _configuredRows: Config.options?.overview?.rows ?? 2
    readonly property int _configuredColumns: Config.options?.overview?.columns ?? 5
    readonly property int overviewRows: verticalLayout && _configuredRows < _configuredColumns
        ? _configuredColumns : _configuredRows
    readonly property int overviewColumns: verticalLayout && _configuredRows < _configuredColumns
        ? _configuredRows : _configuredColumns
    readonly property int workspacesShown: root.overviewRows * root.overviewColumns
    readonly property int presentationWorkspaceId: {
        const preferred = Number(root.preferredWorkspaceId)
        if (isFinite(preferred) && preferred > 0)
            return Math.round(preferred)
        return root.monitor?.activeWorkspace?.id ?? 1
    }
    readonly property int workspaceGroup: Math.floor((root.presentationWorkspaceId - 1) / workspacesShown)
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor.name)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowAddresses: HyprlandData.addresses
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    property real scale: Config.options?.overview?.scale ?? 0.18
    property color activeBorderColor: Appearance.colors.colSecondary
    property bool focusAnimEnabled: Config.options?.overview?.focusAnimationEnable ?? true
    property int focusAnimDuration: Config.options?.overview?.focusAnimationDurationMs ?? 180
    property real clampedPanelWidthRatio: {
        const ov = Config.options?.overview;
        const r = ov && ov.maxPanelWidthRatio !== undefined ? ov.maxPanelWidthRatio : 1.0;
        return Math.max(0.1, Math.min(1.0, r));
    }

    property real baseWorkspaceWidth: (monitorData?.transform % 2 === 1) ?
        ((monitor.height - monitorData?.reserved[0] - monitorData?.reserved[2]) * root.scale / monitor.scale) :
        ((monitor.width - monitorData?.reserved[0] - monitorData?.reserved[2]) * root.scale / monitor.scale)
    property real baseWorkspaceHeight: (monitorData?.transform % 2 === 1) ?
        ((monitor.width - monitorData?.reserved[1] - monitorData?.reserved[3]) * root.scale / monitor.scale) :
        ((monitor.height - monitorData?.reserved[1] - monitorData?.reserved[3]) * root.scale / monitor.scale)
    property real workspaceImplicitWidth: {
        const cols = root.overviewColumns;
        const rows = root.overviewRows;
        const spacing = root.workspaceSpacing;
        const totalBase = baseWorkspaceWidth * cols + spacing * Math.max(0, cols - 1);
        const maxWidth = (panelWindow ? panelWindow.width : baseWorkspaceWidth * cols) * clampedPanelWidthRatio;
        let w = (cols <= 0 || totalBase <= maxWidth)
            ? baseWorkspaceWidth
            : (maxWidth - spacing * Math.max(0, cols - 1)) / cols;
        const aspect = baseWorkspaceHeight <= 0 || baseWorkspaceWidth <= 0 ? 1 : baseWorkspaceHeight / baseWorkspaceWidth;
        if (root.verticalLayout && rows > 0 && aspect > 0) {
            const availH = (panelWindow ? panelWindow.height : baseWorkspaceHeight * rows) * Math.min(clampedPanelWidthRatio, 0.82);
            const maxHPerRow = (availH - spacing * Math.max(0, rows - 1)) / rows;
            if (maxHPerRow > 0)
                w = Math.min(w, maxHPerRow / aspect);
        }
        return Math.max(1, w);
    }
    property real workspaceImplicitHeight: {
        const aspect = baseWorkspaceHeight <= 0 || baseWorkspaceWidth <= 0 ? 1 : baseWorkspaceHeight / baseWorkspaceWidth;
        return workspaceImplicitWidth * aspect;
    }
    property real largeWorkspaceRadius: Appearance.rounding.large
    property real smallWorkspaceRadius: Appearance.rounding.verysmall

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: 250 * monitor.scale
    property bool showWorkspaceNumber: !Config.options.overview
                                       || Config.options.overview.showWorkspaceNumbers !== false
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: Config.options.overview.workspaceSpacing

    // Contador para suavizar el scroll de cambio de workspace
    property int wheelStepCounter: 0
    property int wheelStepsRequired: (Config.options.overview && Config.options.overview.scrollWorkspaceSteps !== undefined)
                                     ? Math.max(1, Config.options.overview.scrollWorkspaceSteps)
                                     : 2

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    readonly property real presentationMargin:
        root.embeddedSurface ? 0 : Appearance.sizes.elevationMargin
    implicitWidth: overviewBackground.implicitWidth + root.presentationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + root.presentationMargin * 2

    // Scroll del mouse para subir/bajar de workspace en Hyprland
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: CompositorService.isHyprland
        onWheel: (event) => {
            let deltaY = event.angleDelta.y
            if (deltaY === 0)
                return

            if (Config.options?.bar?.workspaces?.invertScroll ?? false)
                deltaY = -deltaY

            // Requerir varios pasos de rueda antes de cambiar de workspace
            root.wheelStepCounter += 1
            if (root.wheelStepCounter < root.wheelStepsRequired)
                return
            root.wheelStepCounter = 0

            if (deltaY < 0)
                Hyprland.dispatch(`workspace r+1`)
            else if (deltaY > 0)
                Hyprland.dispatch(`workspace r-1`)
        }
    }

    property Component windowComponent: OverviewWindow {}
    property list<OverviewWindow> windowWidgets: []

    StyledRectangularShadow {
        target: overviewBackground
        visible: !root.embeddedSurface
    }
    Rectangle { // Background
        id: overviewBackground
        property real padding: 10
        anchors.fill: parent
        anchors.margins: root.presentationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2
        radius: root.embeddedSurface ? 0 : (root.largeWorkspaceRadius + padding)
        color: root.embeddedSurface ? "transparent"
            : Appearance.colors.colBackgroundSurfaceContainer
        border.width: root.embeddedSurface ? 0 : 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.68)

        Column { // Workspaces
            id: workspaceColumnLayout

            z: root.workspaceZ
            anchors.centerIn: parent
            spacing: workspaceSpacing
            
            Repeater {
                model: root.overviewRows
                delegate: Row {
                    id: row
                    required property int index
                    spacing: workspaceSpacing

                    Repeater { // Workspace repeater
                        model: root.overviewColumns
                        Rectangle { // Workspace
                            id: workspace
                            required property int index
                            property int colIndex: index
                            property int workspaceValue: root.workspaceGroup * root.workspacesShown + row.index * root.overviewColumns + colIndex + 1
                            property color defaultWorkspaceColor: ColorUtils.mix(
                                Appearance.colors.colBackgroundSurfaceContainer,
                                Appearance.colors.colSurfaceContainerHigh, 0.8)
                            property color hoveredWorkspaceColor: ColorUtils.mix(
                                defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1)
                            property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                            property bool hoveredWhileDragging: false

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor
                            property bool workspaceAtLeft: colIndex === 0
                            property bool workspaceAtRight: colIndex === root.overviewColumns - 1
                            property bool workspaceAtTop: row.index === 0
                            property bool workspaceAtBottom: row.index === root.overviewRows - 1
                            topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            topRightRadius: (workspaceAtRight && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            border.width: hoveredWhileDragging ? 2 : 1
                            border.color: hoveredWhileDragging
                                ? hoveredBorderColor
                                : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.74)

                            StyledText {
                                anchors.centerIn: parent
                                text: workspace.workspaceValue
                                font {
                                    pixelSize: root.workspaceNumberSize * root.scale
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.expressive
                                }
                                color: ColorUtils.transparentize(
                                    Appearance.colors.colOnLayer1, 0.7)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: root.showWorkspaceNumber
                            }

                            MouseArea {
                                id: workspaceArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onPressed: {
                                    if (root.draggingTargetWorkspace === -1) {
                                        root.requestPresentationClose()
                                        if (CompositorService.isHyprland)
                                            Hyprland.dispatch(`workspace ${workspace.workspaceValue}`)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = workspace.workspaceValue
                                    if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                    hoveredWhileDragging = true
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (root.draggingTargetWorkspace == workspace.workspaceValue) root.draggingTargetWorkspace = -1
                                }
                            }

                        }
                    }
                }
            }
        }
    }

    Item { // Windows & focused workspace indicator
        id: windowSpace
        anchors.centerIn: parent
        implicitWidth: workspaceColumnLayout.implicitWidth
        implicitHeight: workspaceColumnLayout.implicitHeight

        Repeater { // Window repeater
            model: ScriptModel {
                values: {
                    // console.log(JSON.stringify(ToplevelManager.toplevels.values.map(t => t), null, 2))
                    return [...ToplevelManager.toplevels.values.filter((toplevel) => {
                        const address = `0x${toplevel.HyprlandToplevel?.address}`
                        var win = windowByAddress[address]
                        const inWorkspaceGroup = (root.workspaceGroup * root.workspacesShown < win?.workspace?.id && win?.workspace?.id <= (root.workspaceGroup + 1) * root.workspacesShown)
                        return inWorkspaceGroup;
                    })].reverse()
                }
            }
            delegate: OverviewWindow {
                id: window
                required property var modelData
                property int monitorId: windowData?.monitor
                property var monitor: HyprlandData.monitors.find(m => m.id == monitorId)
                property var address: `0x${modelData.HyprlandToplevel.address}`
                toplevel: modelData
                monitorData: this.monitor
                scale: root.scale
                widgetMonitor: HyprlandData.monitors.find(m => m.id == root.monitor.id)
                windowData: windowByAddress[address]
                motionAnimationsEnabled: root.localGeometryAnimationReady

                property bool atInitPosition: (initX == x && initY == y)

                // Offset on the canvas. drag.target mutates x/y directly and
                // therefore detaches OverviewWindow's x:initX / y:initY bindings.
                // Hold the destination workspace briefly so the restored bindings
                // point at the target frame even before HyprlandData catches up.
                property int pendingOverviewWorkspace: -1
                readonly property int effectiveWorkspaceId:
                    pendingOverviewWorkspace > 0
                        ? pendingOverviewWorkspace
                        : (windowData?.workspace.id ?? 1)
                property int workspaceColIndex: (effectiveWorkspaceId - 1) % root.overviewColumns
                property int workspaceRowIndex: Math.floor((effectiveWorkspaceId - 1) % root.workspacesShown / root.overviewColumns)
                xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex
                property real xWithinWorkspaceWidget: Math.max((windowData?.at[0] - (monitor?.x ?? 0) - monitorData?.reserved[0]) * root.scale, 0)
                property real yWithinWorkspaceWidget: Math.max((windowData?.at[1] - (monitor?.y ?? 0) - monitorData?.reserved[1]) * root.scale, 0)

                function restoreOverviewPosition(): void {
                    window.x = Qt.binding(function() { return window.initX })
                    window.y = Qt.binding(function() { return window.initY })
                }

                // Radius
                property real minRadius: Appearance.rounding.small
                property bool workspaceAtLeft: workspaceColIndex === 0
                property bool workspaceAtRight: workspaceColIndex === root.overviewColumns - 1
                property bool workspaceAtTop: workspaceRowIndex === 0
                property bool workspaceAtBottom: workspaceRowIndex === root.overviewRows - 1
                property bool workspaceAtTopLeft: (workspaceAtLeft && workspaceAtTop) 
                property bool workspaceAtTopRight: (workspaceAtRight && workspaceAtTop) 
                property bool workspaceAtBottomLeft: (workspaceAtLeft && workspaceAtBottom) 
                property bool workspaceAtBottomRight: (workspaceAtRight && workspaceAtBottom) 
                property real distanceFromLeftEdge: xWithinWorkspaceWidget
                property real distanceFromRightEdge: root.workspaceImplicitWidth - (xWithinWorkspaceWidget + targetWindowWidth)
                property real distanceFromTopEdge: yWithinWorkspaceWidget
                property real distanceFromBottomEdge: root.workspaceImplicitHeight - (yWithinWorkspaceWidget + targetWindowHeight)
                property real distanceFromTopLeftCorner: Math.max(distanceFromLeftEdge, distanceFromTopEdge)
                property real distanceFromTopRightCorner: Math.max(distanceFromRightEdge, distanceFromTopEdge)
                property real distanceFromBottomLeftCorner: Math.max(distanceFromLeftEdge, distanceFromBottomEdge)
                property real distanceFromBottomRightCorner: Math.max(distanceFromRightEdge, distanceFromBottomEdge)
                topLeftRadius: Math.max((workspaceAtTopLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopLeftCorner, minRadius)
                topRightRadius: Math.max((workspaceAtTopRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopRightCorner, minRadius)
                bottomLeftRadius: Math.max((workspaceAtBottomLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomLeftCorner, minRadius)
                bottomRightRadius: Math.max((workspaceAtBottomRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomRightCorner, minRadius)

                Timer {
                    id: updateWindowPosition
                    interval: Config.options.hacks.arbitraryRaceConditionDelay
                    repeat: false
                    running: false
                    onTriggered: {
                        if (window.pendingOverviewWorkspace > 0
                                && window.windowData?.workspace.id
                                    === window.pendingOverviewWorkspace)
                            window.pendingOverviewWorkspace = -1
                        // Rebind rather than assign coordinates. A plain assignment
                        // would fix one frame but leave future workspace/layout
                        // changes detached from initX/initY again.
                        window.restoreOverviewPosition()
                    }
                }

                z: Drag.active ? root.windowDraggingZ : (root.windowZ + windowData?.floating)
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: hovered = true // For hover color change
                    onExited: hovered = false // For hover color change
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    drag.target: parent
                    onPressed: (mouse) => {
                        root.draggingFromWorkspace = windowData?.workspace.id
                        window.pressed = true
                        window.Drag.active = true
                        window.Drag.source = window
                        window.Drag.hotSpot.x = mouse.x
                        window.Drag.hotSpot.y = mouse.y
                        // console.log(`[OverviewWindow] Dragging window ${windowData?.address} from position (${window.x}, ${window.y})`)
                    }
                    onReleased: {
                        if (!CompositorService.isHyprland)
                            return
                        const targetWorkspace = root.draggingTargetWorkspace
                        window.pressed = false
                        window.Drag.active = false
                        root.draggingFromWorkspace = -1
                        if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                            window.pendingOverviewWorkspace = targetWorkspace
                            // Repair x/y immediately so the preview is contained by
                            // the destination workspace instead of retaining the raw
                            // drag coordinate above/below its frame.
                            window.restoreOverviewPosition()
                            Hyprland.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${window.windowData?.address}`)
                            updateWindowPosition.restart()
                        }
                        else {
                            window.pendingOverviewWorkspace = -1
                            if (!window.windowData.floating) {
                                window.restoreOverviewPosition()
                                return
                            }
                            // Floating windows still use the raw drop position to
                            // update compositor geometry. Restore the Overview
                            // bindings only after deriving that compositor target.
                            const percentageX = Math.round((window.x - xOffset) / root.workspaceImplicitWidth * 100)
                            const percentageY = Math.round((window.y - yOffset) / root.workspaceImplicitHeight * 100)
                            Hyprland.dispatch(`movewindowpixel exact ${percentageX}% ${percentageY}%, address:${window.windowData?.address}`)
                            window.restoreOverviewPosition()
                        }
                    }
                    onClicked: (event) => {
                        if (!windowData || !CompositorService.isHyprland) return;

                        if (event.button === Qt.LeftButton) {
                            root.requestPresentationClose()
                            Hyprland.dispatch(`focuswindow address:${windowData.address}`)
                            event.accepted = true
                        } else if (event.button === Qt.MiddleButton) {
                            Hyprland.dispatch(`closewindow address:${windowData.address}`)
                            event.accepted = true
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                        text: `${windowData.title}\n[${windowData.class}] ${windowData.xwayland ? "[XWayland] " : ""}`
                    }
                }

                Rectangle { // Focused workspace indicator
                    id: focusedWorkspaceIndicator
                    property int activeWorkspaceInGroup: monitor.activeWorkspace?.id - (root.workspaceGroup * root.workspacesShown)
                    property int rowIndex: Math.floor((activeWorkspaceInGroup - 1) / Config.options.overview.columns)
                    property int colIndex: (activeWorkspaceInGroup - 1) % Config.options.overview.columns

                // Pequeño inset para que el borde se alinee mejor con las esquinas redondeadas
                property real borderInset: 1

                x: (root.workspaceImplicitWidth + workspaceSpacing) * colIndex + borderInset
                y: (root.workspaceImplicitHeight + workspaceSpacing) * rowIndex + borderInset
                z: root.windowZ
                width: root.workspaceImplicitWidth - borderInset * 2
                height: root.workspaceImplicitHeight - borderInset * 2
                color: "transparent"
                property bool workspaceAtLeft: colIndex === 0
                property bool workspaceAtRight: colIndex === Config.options.overview.columns - 1
                property bool workspaceAtTop: rowIndex === 0
                property bool workspaceAtBottom: rowIndex === Config.options.overview.rows - 1
                property real baseLargeRadius: root.largeWorkspaceRadius
                property real baseSmallRadius: root.smallWorkspaceRadius
                property real largeWorkspaceRadius: Math.max(0, baseLargeRadius - borderInset)
                property real smallWorkspaceRadius: Math.max(0, baseSmallRadius - borderInset)
                topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? largeWorkspaceRadius : smallWorkspaceRadius
                topRightRadius: (workspaceAtRight && workspaceAtTop) ? largeWorkspaceRadius : smallWorkspaceRadius
                bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? largeWorkspaceRadius : smallWorkspaceRadius
                bottomRightRadius: (workspaceAtLeft && workspaceAtBottom) ? largeWorkspaceRadius : smallWorkspaceRadius
                border.width: 2
                border.color: root.activeBorderColor
                Behavior on x {
                    enabled: root.focusAnimEnabled
                        && root.focusIndicatorAnimationReady
                        && Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root.focusAnimDuration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                    }
                }
                Behavior on y {
                    enabled: root.focusAnimEnabled
                        && root.focusIndicatorAnimationReady
                        && Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root.focusAnimDuration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                    }
                }
                Behavior on topLeftRadius {
                    enabled: root.focusAnimEnabled
                        && root.focusIndicatorAnimationReady
                        && Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root.focusAnimDuration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                    }
                }
                Behavior on topRightRadius {
                    enabled: root.focusAnimEnabled
                        && root.focusIndicatorAnimationReady
                        && Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root.focusAnimDuration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                    }
                }
                Behavior on bottomLeftRadius {
                    enabled: root.focusAnimEnabled
                        && root.focusIndicatorAnimationReady
                        && Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root.focusAnimDuration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                    }
                }
                Behavior on bottomRightRadius {
                    enabled: root.focusAnimEnabled
                        && root.focusIndicatorAnimationReady
                        && Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root.focusAnimDuration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                    }
                }
            }
        }
    }
    }
}
