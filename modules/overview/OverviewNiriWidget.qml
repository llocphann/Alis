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
import "NiriOverviewModel.js" as OverviewModel

Item {
    id: root
    required property var panelWindow
    property bool taskViewMode: false
    property bool embeddedSurface: false
    property bool presentationActive: GlobalStates.overviewOpen
    // Delay focus-indicator motion until the parent connected popup finishes
    // its reveal. Window previews settle directly from Niri geometry.
    property bool focusIndicatorAnimationReady: true
    property var preferredWorkspaceId: null
    signal presentationCloseRequested()

    function requestPresentationClose(): void {
        if (root.embeddedSurface)
            root.presentationCloseRequested()
        else
            GlobalStates.overviewOpen = false
    }

    readonly property var overviewOptions: Config.options?.overview ?? {}
    readonly property int overviewRows: taskViewMode ? 1 : (overviewOptions.rows ?? 3)
    readonly property int overviewColumns: taskViewMode ? 3 : (overviewOptions.columns ?? 1)
    readonly property real overviewScale: taskViewMode ? 0.27 : (overviewOptions.scale ?? 0.17)
    readonly property real overviewMaxPanelWidthRatio: taskViewMode ? 0.92 : (overviewOptions.maxPanelWidthRatio ?? 1.0)
    readonly property int overviewWorkspaceSpacing: taskViewMode ? 18 : (overviewOptions.workspaceSpacing ?? 5)
    readonly property int overviewWindowTileMargin: taskViewMode ? 12 : (overviewOptions.windowTileMargin ?? 6)
    readonly property int overviewScrollWorkspaceSteps: overviewOptions.scrollWorkspaceSteps ?? 2

    readonly property bool overviewFocusAnimEnabled: overviewOptions.focusAnimationEnable ?? true
    readonly property int overviewFocusAnimDurationMs: overviewOptions.focusAnimationDurationMs ?? 180
    readonly property bool overviewKeepOpenOnWindowClick: taskViewMode ? false : (overviewOptions.keepOverviewOpenOnWindowClick ?? true)
    readonly property bool overviewShowWorkspaceNumbers: taskViewMode ? true : (overviewOptions.showWorkspaceNumbers ?? true)

    readonly property string wallpaperPathRaw: Config.options?.background?.wallpaperPath ?? ""
    readonly property string wallpaperThumbnailPath: Config.options?.background?.thumbnailPath ?? wallpaperPathRaw

    readonly property int workspacesShown: root.overviewRows * root.overviewColumns
    readonly property string outputName: panelWindow?.screen?.name ?? ""
    readonly property var workspacesForOutput: NiriService.allWorkspaces
        .filter(workspace => workspace.output === root.outputName)
        .sort((a, b) => a.idx - b.idx)
    readonly property var outputWorkspaceNumbers: workspacesForOutput.map(workspace => workspace.idx)
    readonly property int currentWorkspaceNumber: {
        const activeWorkspace = workspacesForOutput.find(workspace => workspace.is_active)
        return activeWorkspace?.idx ?? (outputWorkspaceNumbers[0] ?? 1)
    }
    readonly property int currentWorkspaceSlot: {
        if (!outputWorkspaceNumbers || outputWorkspaceNumbers.length === 0)
            return 0;
        const idx = outputWorkspaceNumbers.indexOf(currentWorkspaceNumber);
        return idx >= 0 ? idx : 0;
    }
    readonly property int presentationWorkspaceSlot: {
        if (root.preferredWorkspaceId !== null
                && root.preferredWorkspaceId !== undefined) {
            const preferred = root.workspacesForOutput.findIndex(workspace =>
                String(workspace?.id ?? "") === String(root.preferredWorkspaceId))
            if (preferred >= 0)
                return preferred
        }
        return root.currentWorkspaceSlot
    }
    readonly property int totalWorkspacesForOutput: workspacesForOutput ? workspacesForOutput.length : 0
    readonly property int firstVisibleWorkspaceSlot: {
        const total = totalWorkspacesForOutput;
        if (total <= 0)
            return 0;
        const slots = workspacesShown <= 0 ? 1 : workspacesShown;
        const cur = Math.max(0, Math.min(presentationWorkspaceSlot, total - 1));
        // Keep physical preview slots stable inside a page. The previous
        // centered window made hovering slot 4 of a 1..5 strip shift the
        // viewport to 2..6, so the previews appeared to move under the pointer.
        // Only crossing a page boundary is allowed to replace the visible group.
        return Math.floor(cur / slots) * slots;
    }

    property real scale: root.overviewScale
    property real clampedPanelWidthRatio: {
        const r = root.overviewMaxPanelWidthRatio;
        return Math.max(0.1, Math.min(1.0, r));
    }
    property color activeBorderColor: Appearance.colors.colSecondary
    property bool focusAnimEnabled: root.overviewFocusAnimEnabled
    property int focusAnimDuration: root.overviewFocusAnimDurationMs
    property bool keepOverviewOpenOnWindowClick: root.overviewKeepOpenOnWindowClick
    property bool showWorkspaceNumber: root.overviewShowWorkspaceNumbers

    // Wallpaper de fondo a reutilizar en cada workspace
    property bool wallpaperIsVideo: wallpaperPathRaw.endsWith(".mp4")
                                    || wallpaperPathRaw.endsWith(".webm")
                                    || wallpaperPathRaw.endsWith(".mkv")
                                    || wallpaperPathRaw.endsWith(".avi")
                                    || wallpaperPathRaw.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? wallpaperThumbnailPath
                                                    : wallpaperPathRaw

    property var outputs: NiriService.outputs

    property var currentOutputInfo: (!outputName && Object.keys(outputs).length > 0)
                                    ? outputs[Object.keys(outputs)[0]]
                                    : outputs[outputName]

    property int logicalWidth: currentOutputInfo && currentOutputInfo.logical ? currentOutputInfo.logical.width : 1920
    property int logicalHeight: currentOutputInfo && currentOutputInfo.logical ? currentOutputInfo.logical.height : 1080
    property real logicalScale: currentOutputInfo && currentOutputInfo.logical && currentOutputInfo.logical.scale !== undefined
                                 ? currentOutputInfo.logical.scale : 1.0

    property real baseWorkspaceWidth: (logicalWidth * root.scale) / logicalScale
    property real baseWorkspaceHeight: (logicalHeight * root.scale) / logicalScale
    readonly property real workspaceAspectRatio:
        baseWorkspaceHeight <= 0 || baseWorkspaceWidth <= 0 ? 1 : baseWorkspaceHeight / baseWorkspaceWidth
    property real naturalWorkspaceImplicitWidth: {
        const cols = root.overviewColumns;
        const spacing = root.workspaceSpacing;
        const totalBase = baseWorkspaceWidth * cols + spacing * Math.max(0, cols - 1);
        const maxWidth = (panelWindow ? panelWindow.width : (logicalWidth / logicalScale)) * clampedPanelWidthRatio;
        if (cols <= 0 || totalBase <= maxWidth)
            return baseWorkspaceWidth;
        return (maxWidth - spacing * Math.max(0, cols - 1)) / cols;
    }
    property real naturalWorkspaceImplicitHeight: naturalWorkspaceImplicitWidth * workspaceAspectRatio
    property real workspaceImplicitWidth: {
        const cols = Math.max(1, root.overviewColumns);
        const rows = Math.max(1, root.overviewRows);
        const spacing = root.workspaceSpacing;
        const pad = (root.taskViewMode ? 16 : 10) * 2 + root.presentationMargin * 2;
        let w = root.naturalWorkspaceImplicitWidth;
        if (root.embeddedSurface && root.width > pad + spacing * (cols - 1) + 1) {
            w = Math.min(w, (root.width - pad - spacing * (cols - 1)) / cols);
        }
        if (root.embeddedSurface && root.height > pad + spacing * (rows - 1) + 1 && root.workspaceAspectRatio > 0) {
            const maxH = (root.height - pad - spacing * (rows - 1)) / rows;
            w = Math.min(w, maxH / root.workspaceAspectRatio);
        }
        return Math.max(1, w);
    }
    property real workspaceImplicitHeight: workspaceImplicitWidth * workspaceAspectRatio

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: root.taskViewMode ? 120 : 250
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: root.overviewWorkspaceSpacing

    // Context menu
    property bool contextVisible: false
    property var contextWindowData: null
    property real contextMenuX: 0
    property real contextMenuY: 0

    // Contador para suavizar el scroll de cambio de workspace
    property int wheelStepCounter: 0
    property int wheelStepsRequired: Math.max(1, root.overviewScrollWorkspaceSteps)

    // Drag state is transaction-owned. Keep the exact window id captured at
    // press time instead of reading a reactive delegate after workspace/model
    // updates; this guarantees that a drop can only move the window the user
    // actually grabbed.
    property int draggingWindowId: -1
    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    function resetDragState(): void {
        root.draggingWindowId = -1
        root.draggingFromWorkspace = -1
        root.draggingTargetWorkspace = -1
    }

    readonly property real presentationMargin:
        root.embeddedSurface ? 0 : Appearance.sizes.elevationMargin
    implicitWidth: Math.max(1, root.overviewColumns) * root.naturalWorkspaceImplicitWidth
        + Math.max(0, root.overviewColumns - 1) * root.workspaceSpacing
        + overviewBackground.padding * 2 + root.presentationMargin * 2
    implicitHeight: Math.max(1, root.overviewRows) * root.naturalWorkspaceImplicitHeight
        + Math.max(0, root.overviewRows - 1) * root.workspaceSpacing
        + overviewBackground.padding * 2 + root.presentationMargin * 2

    function openWindowContext(windowItem, mouseX, mouseY) {
        if (!windowItem || !windowItem.windowData) return
        contextWindowData = windowItem.windowData
        const pos = windowItem.mapToItem(windowSpace, mouseX, mouseY)
        contextMenuX = pos.x
        contextMenuY = pos.y
        contextVisible = true
    }

    function closeWindowContext() {
        contextVisible = false
        contextWindowData = null
    }

    Connections {
        target: root
        function onPresentationActiveChanged() {
            if (!root.presentationActive)
                root.closeWindowContext()
        }
    }





    // Scroll del mouse para subir/bajar de workspace en Niri
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
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

            const direction = deltaY < 0 ? 1 : -1

            const wsList = root.outputWorkspaceNumbers
            if (!wsList || wsList.length < 2)
                return

            const currentNumber = root.currentWorkspaceNumber
            const currentIndex = wsList.indexOf(currentNumber)
            const validIndex = currentIndex === -1 ? 0 : currentIndex
            const nextIndex = direction > 0
                    ? Math.min(validIndex + 1, wsList.length - 1)
                    : Math.max(validIndex - 1, 0)
            if (nextIndex === validIndex)
                return

            const nextWorkspace = root.workspacesForOutput[nextIndex]
            if (nextWorkspace)
                NiriService.switchToWorkspaceById(nextWorkspace.id)
        }
    }

    StyledRectangularShadow {
        target: overviewBackground
        visible: !root.embeddedSurface
    }

    Rectangle {
        id: overviewBackground
        property real padding: root.taskViewMode ? 16 : 10
        anchors.fill: parent
        anchors.margins: root.presentationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2
        radius: root.embeddedSurface ? 0 : (Appearance.rounding.large + padding)
        clip: false
        color: root.embeddedSurface ? "transparent"
            : Appearance.colors.colBackgroundSurfaceContainer
        border.width: root.embeddedSurface ? 0 : 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.68)

        Column {
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

                    Repeater {
                        model: root.overviewColumns
                        Rectangle {
                            id: workspace
                            required property int index
                            property int colIndex: index
                            property int workspaceIndex: root.firstVisibleWorkspaceSlot + row.index * root.overviewColumns + colIndex

                            property var workspaceObj: {
                                const wsList = root.workspacesForOutput
                                if (!wsList || wsList.length === 0)
                                    return null
                                if (workspaceIndex < 0 || workspaceIndex >= wsList.length)
                                    return null
                                return wsList[workspaceIndex]
                            }

                            // Número mostrado en el recuadro (1..N dentro del output actual)
                            property int workspaceValue: workspaceIndex + 1

                            property bool workspaceExists: workspaceObj !== null
                            property bool isActive: workspaceObj && workspaceObj.is_active
                            property color defaultWorkspaceColor: workspaceExists
                                ? Appearance.colors.colBackgroundSurfaceContainer
                                : ColorUtils.transparentize(
                                    Appearance.colors.colBackgroundSurfaceContainer, 0.3)
                            property color hoveredWorkspaceColor: ColorUtils.mix(
                                defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1)
                            property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                            property bool hoveredWhileDragging: false

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: "transparent"
                            clip: true

                            property bool workspaceAtLeft: colIndex === 0
                            property bool workspaceAtRight: colIndex === root.overviewColumns - 1
                            property bool workspaceAtTop: row.index === 0
                            property bool workspaceAtBottom: row.index === root.overviewRows - 1
                            property real largeWorkspaceRadius: Appearance.rounding.large
                            property real smallWorkspaceRadius: Appearance.rounding.verysmall
                            topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? largeWorkspaceRadius : smallWorkspaceRadius
                            topRightRadius: (workspaceAtRight && workspaceAtTop) ? largeWorkspaceRadius : smallWorkspaceRadius
                            bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? largeWorkspaceRadius : smallWorkspaceRadius
                            bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? largeWorkspaceRadius : smallWorkspaceRadius
                            border.width: 0
                            border.color: "transparent"

                            // Wallpaper de fondo recortado al workspace, con blur + dim para mejorar legibilidad
                            Image {
                                id: workspaceWallpaperSource
                                anchors.fill: parent
                                source: root.wallpaperPath
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                // Visible as unblurred fallback when effects are disabled
                                visible: !Appearance.effectsEnabled
                                layer.enabled: !Appearance.effectsEnabled
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: workspace.width
                                        height: workspace.height
                                        topLeftRadius: workspace.topLeftRadius
                                        topRightRadius: workspace.topRightRadius
                                        bottomLeftRadius: workspace.bottomLeftRadius
                                        bottomRightRadius: workspace.bottomRightRadius
                                    }
                                }
                            }

                            FastBlur {
                                anchors.fill: parent
                                source: workspaceWallpaperSource
                                visible: Appearance.effectsEnabled
                                radius: {
                                    if ((root.overviewOptions.backgroundBlurEnable ?? true) === false || !Appearance.effectsEnabled)
                                        return 0
                                    const r = root.overviewOptions.backgroundBlurRadius ?? 22
                                    return r * root.scale
                                }
                                transparentBorder: true
                                layer.enabled: Appearance.effectsEnabled
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: workspace.width
                                        height: workspace.height
                                        topLeftRadius: workspace.topLeftRadius
                                        topRightRadius: workspace.topRightRadius
                                        bottomLeftRadius: workspace.bottomLeftRadius
                                        bottomRightRadius: workspace.bottomRightRadius
                                    }
                                }
                            }

                            // Dim overlay encima del wallpaper (misma forma que el workspace)
                            Rectangle {
                                anchors.fill: parent
                                color: {
                                    const base = root.overviewOptions.backgroundDim ?? 35
                                    const delta = workspace.isActive ? -10 : 0 // activo un poco menos dim
                                    const v = base + delta
                                    const clamped = Math.max(0, Math.min(100, v))
                                    const a = clamped / 100
                                    return ColorUtils.transparentize(Appearance.colors.colLayer0Base, 1 - a)
                                }
                                topLeftRadius: workspace.topLeftRadius
                                topRightRadius: workspace.topRightRadius
                                bottomLeftRadius: workspace.bottomLeftRadius
                                bottomRightRadius: workspace.bottomRightRadius
                                border.width: 0
                            }

                            // Overlay de hover/drag (respeta esquinas redondeadas)
                            Rectangle {
                                anchors.fill: parent
                                color: (workspaceArea.containsMouse || hoveredWhileDragging)
                                       ? hoveredWorkspaceColor
                                       : "transparent"
                                opacity: (workspaceArea.containsMouse || hoveredWhileDragging) ? 0.25 : 0.0
                                topLeftRadius: workspace.topLeftRadius
                                topRightRadius: workspace.topRightRadius
                                bottomLeftRadius: workspace.bottomLeftRadius
                                bottomRightRadius: workspace.bottomRightRadius
                                Behavior on opacity {
                                    enabled: Appearance.animationsEnabled
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }
                            }

                            // Border Overlay
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: hoveredWhileDragging ? 2 : 1
                                // Usar este borde sólo para hover/drag.
                                // El estado activo se dibuja con focusedWorkspaceIndicator para evitar solapamientos.
                                border.color: hoveredWhileDragging
                                    ? hoveredBorderColor
                                    : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.74)
                                topLeftRadius: workspace.topLeftRadius
                                topRightRadius: workspace.topRightRadius
                                bottomLeftRadius: workspace.bottomLeftRadius
                                bottomRightRadius: workspace.bottomRightRadius
                            }

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
                                    if (root.draggingTargetWorkspace === -1 && workspace.workspaceObj) {
                                        root.requestPresentationClose()
                                        NiriService.switchToWorkspaceById(workspace.workspaceObj.id)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    if (root.draggingWindowId < 0)
                                        return
                                    root.draggingTargetWorkspace = workspace.workspaceObj?.id ?? -1
                                    hoveredWhileDragging = root.draggingTargetWorkspace >= 0
                                        && root.draggingFromWorkspace !== root.draggingTargetWorkspace
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (workspace.workspaceObj && root.draggingTargetWorkspace === workspace.workspaceObj.id)
                                        root.draggingTargetWorkspace = -1
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight
            
            property var windowItems: []
            
            function rebuildWindowItems() {
                windowItems = root.presentationActive
                    ? OverviewModel.buildWindowItems(
                        NiriService.windows || [],
                        root.workspacesForOutput || [],
                        root.firstVisibleWorkspaceSlot,
                        root.workspacesShown)
                    : []
                if (root.presentationActive && !root.taskViewMode
                        && root.overviewOptions.showPreviews !== false)
                    WindowPreviewService.warmForOverview(windowItems.map(record => record.id))
            }

            function refreshVisibleWindowPreviews(): void {
                if (!root.presentationActive)
                    return
                const ids = windowItems.map(record => record.id)
                if (!root.taskViewMode
                        && root.overviewOptions.showPreviews !== false) {
                    // The resident cache gives Overview an immediate first
                    // frame; refresh the visible IDs in the background so
                    // long-lived terminals do not show their creation-time
                    // snapshot forever.
                    WindowPreviewService.refreshForOverview(ids)
                } else {
                    WindowPreviewService.captureForTaskView(ids)
                }
            }

            Connections {
                target: NiriService
                enabled: root.presentationActive
                function onWindowsChanged() {
                    windowSpace.rebuildWindowItems()
                }
            }
            
            Connections {
                target: root
                function onWorkspacesForOutputChanged() {
                    windowSpace.rebuildWindowItems()
                }
                function onFirstVisibleWorkspaceSlotChanged() {
                    windowSpace.rebuildWindowItems()
                    windowSpace.refreshVisibleWindowPreviews()
                }
            }
            
            Connections {
                target: root
                function onPresentationActiveChanged() {
                    if (root.presentationActive) {
                        windowSpace.rebuildWindowItems()
                        windowSpace.refreshVisibleWindowPreviews()
                    } else {
                        root.resetDragState()
                        windowSpace.windowItems = []
                    }
                }
            }
            
            Component.onCompleted: {
                rebuildWindowItems()
                if (root.presentationActive)
                    refreshVisibleWindowPreviews()
            }

            Repeater {
                model: ScriptModel {
                    // Delegate identity is a primitive compositor window ID.
                    // Reflow updates the record, never the identity.
                    values: windowSpace.windowItems.map(record => record.id)
                }

                delegate: Item {
                    id: windowItem
                    required property int modelData
                    readonly property int windowId: modelData
                    readonly property var windowRecord:
                        OverviewModel.findWindowRecord(windowSpace.windowItems, windowItem.windowId)
                    readonly property var windowData: windowRecord?.window ?? null
                    readonly property int workspaceNumber: windowRecord?.workspaceNumber ?? 0
                    readonly property int workspaceSlot: windowRecord?.workspaceSlot ?? -1
                    readonly property int indexInWorkspace: windowRecord?.indexInWorkspace ?? 0
                    readonly property int windowCount: windowRecord?.windowCount ?? 1
                    readonly property int workspaceMaxCol: windowRecord?.maxCol ?? 1
                    readonly property int workspaceMaxRow: windowRecord?.maxRow ?? 1

                    readonly property int workspaceIndex: workspaceSlot - root.firstVisibleWorkspaceSlot
                    readonly property int workspaceColIndex: workspaceIndex % root.overviewColumns
                    readonly property int workspaceRowIndex: Math.floor(workspaceIndex / root.overviewColumns)
                    readonly property real xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    readonly property real yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex

                    function restoreOverviewPosition(): void {
                        // MouseArea.drag.target changes x/y imperatively.
                        windowItem.x = Qt.binding(function() {
                            return windowItem.baseX + windowItem.tileMargin
                        })
                        windowItem.y = Qt.binding(function() {
                            return windowItem.baseY + windowItem.tileMargin
                        })
                    }

                    Component.onDestruction: {
                        if (root.draggingWindowId === windowItem.windowId)
                            root.resetDragState()
                    }

                    readonly property var layoutPos: windowData?.layout?.pos_in_scrolling_layout ?? [1, 1]
                    readonly property int layoutCol: layoutPos.length >= 1 && layoutPos[0] ? layoutPos[0] : 1
                    readonly property int layoutRow: layoutPos.length >= 2 && layoutPos[1] ? layoutPos[1] : 1

                    readonly property int taskGridColumns: windowCount <= 1 ? 1
                        : windowCount <= 4 ? 2 : Math.ceil(Math.sqrt(windowCount))
                    readonly property int taskGridRows: Math.ceil(windowCount / taskGridColumns)
                    readonly property real tileWidth: root.workspaceImplicitWidth
                        / (root.taskViewMode ? taskGridColumns : workspaceMaxCol)
                    readonly property real tileHeight: root.workspaceImplicitHeight
                        / (root.taskViewMode ? taskGridRows : workspaceMaxRow)
                    readonly property real tileMargin: root.overviewWindowTileMargin * root.scale

                    readonly property real baseX: xOffset + (root.taskViewMode
                        ? (indexInWorkspace % taskGridColumns) * tileWidth
                        : (layoutCol - 1) * tileWidth)
                    readonly property real baseY: yOffset + (root.taskViewMode
                        ? Math.floor(indexInWorkspace / taskGridColumns) * tileHeight
                        : (layoutRow - 1) * tileHeight)

                    x: baseX + tileMargin
                    y: baseY + tileMargin
                    width: Math.max(10, tileWidth - 2 * tileMargin)
                    height: Math.max(10, tileHeight - 2 * tileMargin)
                    z: windowItem.Drag.active ? root.windowDraggingZ : root.windowZ

                    // A sibling may change Niri column when another window
                    // leaves. Never animate it as if it followed the drag.
                    // The unused heuristic toplevel match is also retired:
                    // this surface renders directly from exact Niri IDs.

                    property bool hovered: false
                    property bool pressed: false
                    readonly property bool isFocused: !!windowData && (windowData.is_focused
                                                                         || (NiriService.activeWindow
                                                                             && NiriService.activeWindow.id === windowData.id))

                    readonly property real windowRadius: Appearance.rounding.small

                    Rectangle {
                        anchors.fill: parent
                        radius: windowItem.windowRadius
                        color: root.taskViewMode ? Appearance.colors.colLayer1Base : "transparent"
                        border.width: windowItem.isFocused ? 2 : 0
                        border.color: windowItem.isFocused ? Appearance.colors.colLayer2Active : "transparent"

                        // Fondo de hover/pressed (sin contenido de ventana)
                        Rectangle {
                            anchors.fill: parent
                            // When focused, inset slightly so hover/press highlight doesn't cover the focus border
                            anchors.margins: windowItem.isFocused ? 2 : 0
                            radius: windowItem.windowRadius
                            color: windowItem.pressed
                                   ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.45)
                                   : windowItem.hovered
                                       ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.55)
                                       : "transparent"
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.7)
                            border.width: windowItem.hovered || windowItem.pressed ? 1 : 0
                        }

                        // Preview source is a binding on the current immutable
                        // window id and reactive cache; never retain another
                        // window's URL in delegate-local mutable state.
                        readonly property bool showPreviews: root.taskViewMode || Config.options?.overview?.showPreviews !== false
                        Image {
                            id: windowPreview
                            anchors.fill: parent
                            anchors.margins: 2
                            asynchronous: true
                            cache: true
                            // Keep the last decoded frame while a refreshed URL
                            // is loading. Overview refreshes visible windows on
                            // every open, and dropping the old texture during
                            // that async decode causes the icon/preview flash.
                            retainWhileLoading: true
                            property bool _everReady: false
                            // Decode parameters precede source assignment. In
                            // Overview they match the resident CPU image cache;
                            // TaskView continues to decode to its smaller tile.
                            sourceSize.width: root.taskViewMode
                                ? Math.max(1, Math.min(768, Math.ceil(windowItem.width * 2)))
                                : WindowPreviewService.overviewWarmDecodeWidth
                            sourceSize.height: root.taskViewMode
                                ? Math.max(1, Math.min(512, Math.ceil(windowItem.height * 2)))
                                : WindowPreviewService.overviewWarmDecodeHeight
                            fillMode: root.taskViewMode ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                            source: {
                                const cache = WindowPreviewService.previewCache
                                if (!parent.showPreviews || !windowItem.windowData
                                        || !cache?.[windowItem.windowId])
                                    return ""
                                return WindowPreviewService.getPreviewUrl(windowItem.windowId)
                            }
                            onStatusChanged: {
                                if (status === Image.Ready)
                                    _everReady = true
                            }
                            onSourceChanged: {
                                if (String(source).length === 0)
                                    _everReady = false
                            }
                            smooth: true
                            mipmap: true
                            visible: parent.showPreviews && _everReady
                            opacity: visible ? 1 : 0
                            Behavior on opacity {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }

                        // Icono de la app (fallback cuando no hay preview)
                        Image {
                            id: windowIcon
                            anchors.centerIn: parent
                            width: {
                                var size = Math.min(parent.width, parent.height) * (windowPreview.visible ? 0.25 : 0.35);
                                const min = root.overviewOptions.iconMinSize ?? 0;
                                const max = root.overviewOptions.iconMaxSize ?? 0;
                                if (min > 0) size = Math.max(size, min);
                                if (max > 0) size = Math.min(size, max);
                                return size;
                            }
                            height: width
                            source: windowItem.windowData
                                ? AppSearch.getIconSource(windowItem.windowData.app_id || windowItem.windowData.appId || "")
                                : ""
                            fillMode: Image.PreserveAspectFit
                            opacity: windowPreview.visible ? (root.taskViewMode ? 0 : 0.6) : 1.0
                            Behavior on opacity {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                            }
                            scale: windowItem.hovered ? 1.08 : 1.0
                            Behavior on scale {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }

                        MouseArea {
                            id: windowMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            drag.target: (windowMouseArea.pressedButtons & Qt.LeftButton) ? windowItem : null
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            property real pressX: 0
                            property real pressY: 0
                            onEntered: windowItem.hovered = true
                            onExited: windowItem.hovered = false
                            onPressed: (mouse) => {
                                if (!windowData)
                                    return
                                const point = windowMouseArea.mapToItem(windowSpace, mouse.x, mouse.y)
                                pressX = point.x
                                pressY = point.y
                                if (mouse.button !== Qt.LeftButton)
                                    return

                                const draggedId = windowItem.windowId
                                if (!Number.isFinite(draggedId) || draggedId < 0)
                                    return

                                root.draggingWindowId = draggedId
                                root.draggingTargetWorkspace = -1

                                windowItem.pressed = true
                                const ws = NiriService.workspaces[windowData.workspace_id]
                                root.draggingFromWorkspace = ws ? ws.id : -1
                                windowItem.Drag.active = true
                                windowItem.Drag.source = windowItem
                                windowItem.Drag.hotSpot.x = mouse.x
                                windowItem.Drag.hotSpot.y = mouse.y
                            }
                            onReleased: (event) => {
                                const point = windowMouseArea.mapToItem(windowSpace, event.x, event.y)
                                const isClick = Math.abs(point.x - pressX) <= 4
                                    && Math.abs(point.y - pressY) <= 4
                                if (event.button === Qt.RightButton) {
                                    if (isClick && windowData)
                                        root.openWindowContext(windowItem, event.x, event.y)
                                    return
                                }
                                if (event.button === Qt.MiddleButton) {
                                    if (isClick && windowData)
                                        NiriService.closeWindow(windowItem.windowId)
                                    return
                                }

                                const draggedWindowId = root.draggingWindowId
                                const fromWorkspace = root.draggingFromWorkspace
                                const targetWorkspace = root.draggingTargetWorkspace
                                windowItem.pressed = false
                                windowItem.Drag.active = false
                                windowItem.restoreOverviewPosition()
                                root.resetDragState()

                                if (draggedWindowId !== windowItem.windowId)
                                    return

                                if (targetWorkspace >= 0
                                        && targetWorkspace !== fromWorkspace
                                        && root.workspacesForOutput.some(ws => ws?.id === targetWorkspace)) {
                                    // Never apply an optimistic workspace slot.
                                    // NiriService.windows triggers the authoritative
                                    // projection refresh for this one window ID.
                                    NiriService.moveWindowToWorkspaceById(
                                        draggedWindowId, targetWorkspace, false)
                                } else if (isClick) {
                                    NiriService.focusWindow(draggedWindowId)
                                    if (!root.keepOverviewOpenOnWindowClick)
                                        root.requestPresentationClose()
                                }
                            }
                            onCanceled: {
                                windowItem.pressed = false
                                windowItem.Drag.active = false
                                windowItem.restoreOverviewPosition()
                                if (root.draggingWindowId === windowItem.windowId)
                                    root.resetDragState()
                            }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                visible: root.contextVisible
                z: root.windowZ + 50
                onClicked: root.closeWindowContext()
            }

            Rectangle {
                visible: root.contextVisible
                x: root.contextMenuX
                y: root.contextMenuY
                z: root.windowZ + 51
                width: col.implicitWidth
                height: col.implicitHeight
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer4
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.5)

                Column {
                    id: col
                    spacing: 0
                    topPadding: 4
                    bottomPadding: 4
                    leftPadding: 4
                    rightPadding: 4

                    RippleButton {
                        implicitWidth: contentItem.implicitWidth + 24
                        height: 32
                        buttonRadius: Appearance.rounding.small
                        buttonText: Translation.tr("Focus")
                        colBackgroundHover: Appearance.colors.colLayer4Hover
                        onClicked: {
                            if (!root.contextWindowData) return
                            NiriService.focusWindow(root.contextWindowData.id)
                            if (!root.keepOverviewOpenOnWindowClick)
                                root.requestPresentationClose()
                            root.closeWindowContext()
                        }
                    }

                    RippleButton {
                        implicitWidth: contentItem.implicitWidth + 24
                        height: 32
                        buttonRadius: Appearance.rounding.small
                        buttonText: Translation.tr("Close")
                        colBackgroundHover: Appearance.colors.colLayer4Hover
                        onClicked: {
                            if (!root.contextWindowData) return
                            NiriService.closeWindow(root.contextWindowData.id)
                            root.closeWindowContext()
                        }
                    }
                }
            }

            Rectangle {
                id: focusedWorkspaceIndicator
                readonly property int activeSlot: root.currentWorkspaceSlot
                readonly property int activeSlotInGroup: activeSlot - root.firstVisibleWorkspaceSlot
                readonly property int rowIndex: Math.floor(activeSlotInGroup / root.overviewColumns)
                readonly property int colIndex: activeSlotInGroup % root.overviewColumns

                x: (root.workspaceImplicitWidth + workspaceSpacing) * colIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * rowIndex
                z: root.windowZ
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"

                property bool workspaceAtLeft: colIndex === 0
                property bool workspaceAtRight: colIndex === root.overviewColumns - 1
                property bool workspaceAtTop: rowIndex === 0
                property bool workspaceAtBottom: rowIndex === root.overviewRows - 1
                property real largeWorkspaceRadius: Appearance.rounding.large
                property real smallWorkspaceRadius: Appearance.rounding.verysmall
                topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? largeWorkspaceRadius : smallWorkspaceRadius
                topRightRadius: (workspaceAtRight && workspaceAtTop) ? largeWorkspaceRadius : smallWorkspaceRadius
                bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? largeWorkspaceRadius : smallWorkspaceRadius
                bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? largeWorkspaceRadius : smallWorkspaceRadius

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
