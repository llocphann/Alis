pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Scope {
    id: root
    property bool embeddedMode: false
    property Item embeddedParent: null
    property bool presentationVisible: !GlobalStates.screenLocked
    property bool connectionHovered: false
    property var recordingStatus: RecorderStatus
    property var audioService: Audio
    property var stopAction: null
    property bool isVertical: false
    property bool collapsed: false
    readonly property bool autoHide: Config.options?.screenRecord?.recordingOsd?.autoHide ?? false
    readonly property string audioMode: recordingStatus.effectiveAudioMode
    readonly property bool usesSystemAudio: audioMode === "system" || audioMode === "both"
    readonly property bool usesMicrophone: audioMode === "microphone" || audioMode === "both"
    property bool revealed: true
    property bool controlsHovered: false
    readonly property bool osdTargetHovered: controlsHovered || connectionHovered
    property bool draggingControls: false
    // In embedded Abyss mode a "Recording saved" notification can arrive at
    // the same instant the recorder disappears. Retain *hidden* controls for
    // a bounded cool-down rather than destroying the Qt item tree on the
    // first frame of the toast. Native ii/Waffle teardown is unchanged.
    property bool controlsCooling: false
    // Minimized is a persistent choice; hovering only peeks at the controls.
    readonly property bool controlsExpanded: !collapsed || osdTargetHovered || draggingControls
    readonly property Item controls: controlsLoader.item
    readonly property var nativeWindow: osdLoader.item
    signal dragStarted()
    signal dragMoved(point translation)
    signal dragFinished(point translation)

    function hostControls(): void {
        if (!root.controls) return
        const host = root.embeddedMode ? root.embeddedParent : root.nativeWindow?.pill
        root.controls.parent = host ?? null
        if (!root.embeddedMode && root.nativeWindow) root.nativeWindow.positionInitially()
    }
    onEmbeddedParentChanged: hostControls()
    onEmbeddedModeChanged: hostControls()
    onOsdTargetHoveredChanged: {
        if (osdTargetHovered) {
            hideTimer.stop()
            // Hover changes while the connected host updates its input clip.
            // Reveal on the next turn, outside that host's open binding.
            Qt.callLater(() => { if (root.osdTargetHovered) root.revealed = true })
        }
        else startHideTimer()
    }
    onAutoHideChanged: {
        if (autoHide) startHideTimer()
        else { hideTimer.stop(); revealed = true }
    }
    onCollapsedChanged: {
        hideTimer.stop()
        revealed = true
        if (!collapsed) startHideTimer()
    }
    function expandControls(): void { root.collapsed = false; root.revealed = true }
    function minimizeControls(): void { root.collapsed = true; root.revealed = true }
    function startHideTimer(): void {
        if (autoHide && !collapsed && !osdTargetHovered && !draggingControls && recordingStatus.isRecording)
            hideTimer.restart()
    }
    function formatTime(totalSeconds: int): string {
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const seconds = totalSeconds % 60
        const pad = n => n < 10 ? "0" + n : "" + n
        if (hours > 0) return pad(hours) + ":" + pad(minutes) + ":" + pad(seconds)
        return pad(minutes) + ":" + pad(seconds)
    }
    function stopRecording(): void {
        if (root.stopAction) root.stopAction()
        else {
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"])
            root.recordingStatus.scheduleQuickCheck()
        }
    }
    onDragStarted: {
        draggingControls = true
        hideTimer.stop()
        if (nativeWindow) nativeWindow.pill.animatePosition = false
    }
    onDragFinished: {
        draggingControls = false
        if (nativeWindow) nativeWindow.snapToNearestEdge()
        startHideTimer()
    }
    Connections {
        target: root.recordingStatus
        function onIsRecordingChanged(): void {
            if (!root.recordingStatus.isRecording) {
                hideTimer.stop()
                root.draggingControls = false
                if (root.embeddedMode && root.controls) {
                    root.controlsCooling = true
                    controlsCoolDown.restart()
                }
                return
            }
            controlsCoolDown.stop()
            root.controlsCooling = false
            root.collapsed = false
            if (!root.embeddedMode) root.isVertical = false
            root.revealed = true
            root.startHideTimer()
        }
    }
    Component.onCompleted: root.startHideTimer()
    Timer {
        id: controlsCoolDown
        interval: 700
        repeat: false
        onTriggered: root.controlsCooling = false
    }
    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: if (root.autoHide && !root.collapsed && !root.osdTargetHovered && !root.draggingControls) root.revealed = false
    }
    Loader {
        id: controlsLoader
        active: root.recordingStatus.isRecording
            || (root.embeddedMode && root.controlsCooling)
        onLoaded: root.hostControls()
        sourceComponent: RecordingControls {
            owner: root
            width: implicitWidth
            height: implicitHeight
            anchors.centerIn: parent
            dragTarget: root.embeddedMode ? null : root.nativeWindow?.pill ?? null
            dragWidth: root.nativeWindow?.width ?? 0
            dragHeight: root.nativeWindow?.height ?? 0
            HoverHandler { onHoveredChanged: root.controlsHovered = hovered }
            Component.onDestruction: root.controlsHovered = false
        }
    }
    Loader {
        id: osdLoader
        active: root.recordingStatus.isRecording && !root.embeddedMode
        onLoaded: root.hostControls()
        sourceComponent: PanelWindow {
            id: osdWindow
            readonly property Item pill: nativePill
            visible: osdLoader.active && !GlobalStates.screenLocked
            screen: GlobalStates.primaryScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:recordingOsd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region { item: nativePill }
            readonly property real edgeMargin: Appearance.sizes.elevationMargin
            function positionInitially(): void {
                if (nativePill.positioned || !root.controls
                        || nativePill.width <= 12 || nativePill.height <= 12
                        || width < nativePill.width || height < nativePill.height) return
                nativePill.x = (width-nativePill.width)/2
                nativePill.y = edgeMargin
                nativePill.positioned = true
            }
            onWidthChanged: positionInitially()
            onHeightChanged: positionInitially()
            function snapToNearestEdge(): void {
                const margin = edgeMargin
                const pw = osdWindow.width
                const ph = osdWindow.height
                const pillW = pill.width
                const pillH = pill.height
                const cx = pill.x + pillW / 2
                const cy = pill.y + pillH / 2

                const distLeft = pill.x
                const distRight = pw - (pill.x + pillW)
                const distTop = pill.y
                const distBottom = ph - (pill.y + pillH)

                const minDist = Math.min(distLeft, distRight, distTop, distBottom)

                const wasVertical = root.isVertical
                const snapsToSide = (minDist === distLeft || minDist === distRight)
                root.isVertical = snapsToSide

                let targetX, targetY

                if (snapsToSide) {
                    targetX = (minDist === distLeft) ? margin : pw - pillW - margin
                    targetY = Math.max(margin, Math.min(ph - pillH - margin, pill.y))
                } else {
                    targetY = (minDist === distTop) ? margin : ph - pillH - margin
                    targetX = Math.max(margin, Math.min(pw - pillW - margin, pill.x))
                }

                if (root.isVertical !== wasVertical) {
                    Qt.callLater(() => {
                        const newPillW = pill.width
                        const newPillH = pill.height

                        let newX, newY
                        if (snapsToSide) {
                            newX = (minDist === distLeft) ? margin : pw - newPillW - margin
                            newY = Math.max(margin, Math.min(ph - newPillH - margin, cy - newPillH / 2))
                        } else {
                            newY = (minDist === distTop) ? margin : ph - newPillH - margin
                            newX = Math.max(margin, Math.min(pw - newPillW - margin, cx - newPillW / 2))
                        }

                        pill.animatePosition = true
                        pill.x = newX
                        pill.y = newY
                    })
                    return
                }

                pill.animatePosition = true
                pill.x = targetX
                pill.y = targetY
            }


            Item {
                id: nativePill
                property bool animatePosition: false
                property bool positioned: false
                width: (root.controls?.width ?? 0)+12
                height: (root.controls?.height ?? 0)+12
                onWidthChanged: osdWindow.positionInitially()
                onHeightChanged: osdWindow.positionInitially()
                opacity: root.autoHide && !root.revealed ? 0 : 1
                scale: root.autoHide && !root.revealed ? .5 : 1
                HoverHandler { onHoveredChanged: root.connectionHovered = hovered }
                GlassBackground {
                    id: pillBg
                    anchors.fill: parent
                    property point screenPos: mapToGlobal(0, 0)
                    screenX: screenPos.x
                    screenY: screenPos.y

                    fallbackColor: Appearance.zzzEverywhere ? Appearance.zzz.bg1 : Appearance.colors.colLayer2
                    alisColor: Appearance.alis.colLayer1
                    auroraTransparency: Appearance.aurora.popupTransparentize

                    radius: Appearance.zzzEverywhere ? Appearance.zzz.panelRadius : Appearance.rounding.large
                    border.width: Appearance.zzzEverywhere ? 1 : (Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : 1)
                    border.color: Appearance.zzzEverywhere ? Appearance.zzz.borderColor
                                : Appearance.angelEverywhere ? Appearance.angel.colCardBorder
                                : Appearance.alisEverywhere ? Appearance.alis.colBorder
                                : Appearance.colors.colOutlineVariant
                    Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
                    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                }


                Behavior on opacity { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveEnter.duration } }
                Behavior on scale { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveEnter.duration } }
                Behavior on x {
                    enabled: nativePill.animatePosition && Appearance.animationsEnabled
                    NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: nativePill.animatePosition && Appearance.animationsEnabled
                    NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    IpcHandler {
        target: "recordingOsd"
        function toggle(): void { if (root.recordingStatus.isRecording) root.stopRecording() }
        function show(): void { root.expandControls(); root.startHideTimer() }
        function hide(): void { root.minimizeControls() }
    }
}
