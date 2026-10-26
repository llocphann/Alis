import qs
import qs.services
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
    id: root
    property string protectionMessage: ""
    property bool initialized: false
    property var excludedScreenNames: []
    readonly property var targetScreens: {
        const list = Config.options?.osd?.screenList ?? []
        const screens = Quickshell.screens
        let selected = screens
        if (list && list.length > 0) {
            const matched = screens.filter(screen => {
                const screenName = screen?.name ?? ""
                return screenName.length > 0 && list.includes(screenName)
            })
            // Fallback safety: stale monitor names should never hide the OSD everywhere.
            selected = matched.length > 0 ? matched : screens
        }
        return selected.filter(screen => !root.excludedScreenNames.includes(screen?.name ?? ""))
    }
    property string currentIndicator: "volume"
    property bool _syncingOpenStates: false
    readonly property bool osdActive: GlobalStates.osdVolumeOpen || GlobalStates.osdBrightnessOpen || GlobalStates.osdMicOpen || GlobalStates.osdMediaOpen || GlobalStates.osdKeyboardLayoutOpen
    readonly property bool mediaOsdVisible: GlobalStates.osdMediaOpen
        && root.currentIndicator === "media"
    property bool _surfaceRetained: false
    property bool _visualOpen: false
    property real connectedOffsetScale: 1

    // Compact status OSDs use the same connected Bar/Screen Edge language as
    // ordinary ii popups. Media and Voice Search keep their specialized cards.
    readonly property bool connectedIndicator:
        ["volume", "brightness", "mic", "keyboardLayout"].includes(root.currentIndicator)
    readonly property bool _barVertical: Config.options?.bar?.vertical ?? false
    readonly property bool _barTrailing: Config.options?.bar?.bottom ?? false
    readonly property string _connectedAttachmentEdge: root._barVertical
        ? (root._barTrailing ? "right" : "left")
        : (root._barTrailing ? "bottom" : "top")
    readonly property real _screenEdgeThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
    readonly property bool _edgeShadowEnabled:
        Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
    readonly property real _edgeShadowExtent: Math.max(0, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
    readonly property real _edgeShadowOpacity: Math.max(0, Math.min(1.0,
        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))
    readonly property color _edgeShadowColor:
        Qt.alpha(Appearance.m3colors.m3shadow, root._edgeShadowOpacity)

    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "mic",
            sourceUrl: "indicators/MicIndicator.qml"
        },
        {
            id: "media",
            sourceUrl: "indicators/MediaIndicator.qml"
        },
        {
            id: "voiceSearch",
            sourceUrl: "indicators/VoiceSearchIndicator.qml"
        },
        {
            id: "keyboardLayout",
            sourceUrl: "indicators/KeyboardLayoutIndicator.qml"
        },
    ]

    function setOpenStates(volume, brightness, mic, media, keyboardLayout) {
        root._syncingOpenStates = true;
        GlobalStates.osdVolumeOpen = volume;
        GlobalStates.osdBrightnessOpen = brightness;
        GlobalStates.osdMicOpen = mic;
        GlobalStates.osdMediaOpen = media;
        GlobalStates.osdKeyboardLayoutOpen = keyboardLayout;
        root._syncingOpenStates = false;
        root._reconcilePresentation()
    }

    function hideOsd() {
        osdTimeout.stop();
        root.setOpenStates(false, false, false, false, false);
        root.protectionMessage = "";
    }

    function _reconcilePresentation(): void {
        if (root.osdActive) {
            osdReleaseTimer.stop()
            root._surfaceRetained = true
            Qt.callLater(() => {
                if (root.osdActive) {
                    root._visualOpen = true
                    root.connectedOffsetScale = 0
                }
            })
        } else if (root._surfaceRetained) {
            root._visualOpen = false
            root.connectedOffsetScale = 1
            osdReleaseTimer.restart()
        }
    }

    onOsdActiveChanged: {
        if (!root._syncingOpenStates)
            root._reconcilePresentation()
    }

    Component.onCompleted: {
        root._reconcilePresentation()
    }

    Behavior on connectedOffsetScale {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    function _targetsOutput(outputName, configuredList): bool {
        if (!outputName || outputName.length === 0)
            return false
        const list = configuredList ?? []
        if (!list || list.length === 0)
            return true
        const matched = Quickshell.screens.filter(screen => {
            const screenName = String(screen?.name ?? "")
            return screenName.length > 0 && list.includes(screenName)
        })
        if (matched.length === 0)
            return true
        return list.includes(outputName)
    }

    function _iiBarOwnsOutput(outputName): bool {
        if ((Config.options?.panelFamily ?? "ii") !== "ii")
            return false
        if (!GlobalStates.barOpen || GlobalStates.widgetEditMode)
            return false
        if (Config.options?.bar?.autoHide?.enable ?? false)
            return false
        const panelId = root._barVertical ? "iiVerticalBar" : "iiBar"
        if (!(Config.options?.enabledPanels ?? []).includes(panelId))
            return false
        return root._targetsOutput(
            outputName, Config.options?.bar?.screenList ?? [])
    }

    function _attachmentThicknessFor(outputName): real {
        if (root._iiBarOwnsOutput(outputName))
            return root._barVertical
                ? Appearance.sizes.verticalBarWidth
                : Appearance.sizes.barHeight
        return root._screenEdgeThickness
    }

    function _connectedAnchorRect(outputWidth, outputHeight, outputName,
                                  tangentExtent) {
        const thickness = root._attachmentThicknessFor(outputName)
        const extent = Math.max(1, Number(tangentExtent ?? 1))
        if (root._connectedAttachmentEdge === "top")
            return Qt.rect((outputWidth - extent) / 2, 0, extent, thickness)
        if (root._connectedAttachmentEdge === "bottom")
            return Qt.rect((outputWidth - extent) / 2,
                outputHeight - thickness, extent, thickness)
        if (root._connectedAttachmentEdge === "left")
            return Qt.rect(0, (outputHeight - extent) / 2, thickness, extent)
        return Qt.rect(outputWidth - thickness,
            (outputHeight - extent) / 2, thickness, extent)
    }

    Timer {
        id: osdReleaseTimer
        interval: Math.max(
            Appearance.animation.elementMoveExit.duration,
            Appearance.animation.elementMove.duration) + 60
        repeat: false
        onTriggered: {
            if (!root.osdActive)
                root._surfaceRetained = false
        }
    }

    function openIndicator(indicator, autoHide) {
        if (!initialized) return;
        root.currentIndicator = indicator;
        root.setOpenStates(
            indicator === "volume" || indicator === "voiceSearch",
            indicator === "brightness",
            indicator === "mic",
            indicator === "media",
            indicator === "keyboardLayout"
        );
        if (autoHide)
            osdTimeout.restart();
    }

    function triggerOsd() {
        root.openIndicator(root.currentIndicator, true);
    }

    Timer {
        id: initDelay
        interval: 1500
        running: true
        onTriggered: root.initialized = true
    }

    Timer {
        id: osdTimeout
        interval: root.currentIndicator === "media"
            ? (Config.options?.osd?.timeout ?? 2000) + 1000  // Longer for media
            : (Config.options?.osd?.timeout ?? 2000)
        repeat: false
        running: false
        onTriggered: {
            root.hideOsd();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready || GameMode.suppressNiriToast)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready || GameMode.suppressNiriToast)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkControlRequested(): void {
            if (!root.initialized || GameMode.suppressNiriToast) return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to mic volume/mute changes
        target: Audio
        function onMicVolumeChanged() {
            if (!root.initialized) return;
            root.currentIndicator = "mic";
            root.triggerOsd();
        }
        function onMicMutedChanged() {
            if (!root.initialized) return;
            root.currentIndicator = "mic";
            root.triggerOsd();
        }
    }

    Connections {
        target: GlobalStates
        function onOsdVolumeOpenChanged() {
            if (root._syncingOpenStates || !GlobalStates.osdVolumeOpen)
                return;
            root.currentIndicator = "volume";
            osdTimeout.restart();
        }
        function onOsdBrightnessOpenChanged() {
            if (root._syncingOpenStates || !GlobalStates.osdBrightnessOpen)
                return;
            root.currentIndicator = "brightness";
            osdTimeout.restart();
        }
        function onOsdMicOpenChanged() {
            if (root._syncingOpenStates || !GlobalStates.osdMicOpen)
                return;
            root.currentIndicator = "mic";
            osdTimeout.restart();
        }
        function onOsdMediaOpenChanged() {
            if (root._syncingOpenStates || !GlobalStates.osdMediaOpen)
                return;
            if (!(Config.options?.osd?.mediaEnabled ?? true)
                    || !MprisController.activePlayer) {
                GlobalStates.osdMediaOpen = false;
                return;
            }
            root.currentIndicator = "media";
            osdTimeout.restart();
        }
        function onOsdKeyboardLayoutOpenChanged() {
            if (root._syncingOpenStates || !GlobalStates.osdKeyboardLayoutOpen)
                return;
            root.currentIndicator = "keyboardLayout";
            osdTimeout.restart();
        }
        function onOsdMediaActionTriggered(action: string) {
            if (!root.mediaOsdVisible || !action.length)
                return;
            root.currentIndicator = "media";
            osdTimeout.restart();
        }
    }

    Connections {
        target: VoiceSearch
        function onRunningChanged() {
            if (VoiceSearch.running) {
                root.openIndicator("voiceSearch", false);
                osdTimeout.stop(); // Don't auto-hide while active
            } else {
                osdTimeout.restart();
            }
        }
    }

    Connections {
        target: KeyboardIndicators
        function onPopupSequenceChanged() {
            root.currentIndicator = "keyboardLayout";
            root.triggerOsd();
        }
    }

    Connections {
        target: MprisController
        function onTrackChanged(reverse: bool): void {
            if (root.mediaOsdVisible)
                osdTimeout.restart()
        }
    }

    Connections {
        target: MediaArtwork
        function onDisplaySourceChanged(): void {
            if (root.mediaOsdVisible)
                osdTimeout.restart()
        }
    }

    Loader {
        id: osdLoader
        active: root._surfaceRetained

        sourceComponent: Variants {
            model: root.targetScreens

            delegate: PanelWindow {
                id: osdRoot
                required property var modelData

                readonly property string outputName: String(modelData?.name ?? "")
                readonly property bool connectedHorizontal:
                    root._connectedAttachmentEdge === "top"
                    || root._connectedAttachmentEdge === "bottom"
                readonly property real connectedTangentExtent:
                    connectedHorizontal
                        ? connectedStatusContent.implicitWidth
                        : connectedStatusContent.implicitHeight

                screen: modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0

                WlrLayershell.namespace: "quickshell:onScreenDisplay"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                mask: root.connectedIndicator ? connectedMask : detachedMask

                ConnectedSurfaceGeometry {
                    id: connectedGeometry
                    edge: root._connectedAttachmentEdge
                    alignment: "center"
                    outputRect: Qt.rect(0, 0, osdRoot.width, osdRoot.height)
                    anchorRect: root._connectedAnchorRect(
                        osdRoot.width,
                        osdRoot.height,
                        osdRoot.outputName,
                        osdRoot.connectedTangentExtent)
                    bodySize: Qt.size(
                        Math.max(1, connectedStatusContent.implicitWidth),
                        Math.max(1, connectedStatusContent.implicitHeight))
                    outerRadius: PerimeterTokens.popupRadius
                    screenMargin: root._screenEdgeThickness
                    connectorLength: 0
                    seamOverlap: PerimeterTokens.abyssWeldDepth
                    progress: 1 - root.connectedOffsetScale
                    devicePixelRatio: osdRoot.devicePixelRatio
                }

                ConnectedSurfaceRevealClip {
                    geometry: connectedGeometry
                    visible: root.connectedIndicator

                    ConnectedSurfaceAbyssFrame {
                        id: statusFrame
                        anchors.fill: parent
                        geometry: connectedGeometry
                        fillColor: Appearance.colors.colLayer0
                        borderColor: Appearance.colors.colLayer0Border
                        borderWidth: 0
                        fuseDepth: PerimeterTokens.abyssFuseDepth
                        externalFrameThickness: root._screenEdgeThickness
                        shadowEnabled: root._edgeShadowEnabled
                            && root._edgeShadowExtent > 0
                            && root._edgeShadowOpacity > 0
                        shadowExtent: root._edgeShadowExtent
                        shadowColor: root._edgeShadowColor
                        joinTop: connectedGeometry.edge === "top"
                        joinBottom: connectedGeometry.edge === "bottom"
                        joinLeft: connectedGeometry.edge === "left"
                        joinRight: connectedGeometry.edge === "right"
                    }

                    ConnectedSurfaceContentHost {
                        geometry: connectedGeometry
                        padding: 0

                        Item {
                            id: connectedStatusContent
                            anchors.fill: parent
                            implicitWidth: Math.max(
                                connectedIndicatorLoader.implicitWidth,
                                protectionMessageWrapper.visible
                                    ? protectionMessageWrapper.implicitWidth : 0)
                            implicitHeight: connectedIndicatorLoader.implicitHeight
                                + (protectionMessageWrapper.visible
                                    ? protectionMessageWrapper.implicitHeight : 0)

                            Loader {
                                id: connectedIndicatorLoader
                                source: root.connectedIndicator
                                    ? (root.indicators.find(
                                        i => i.id === root.currentIndicator)?.sourceUrl ?? "")
                                    : ""
                                x: (parent.width - width) / 2
                                y: 0
                                onLoaded: {
                                    if (item)
                                        item.connectedSurface = true
                                }
                            }

                            Item {
                                id: protectionMessageWrapper
                                visible: root.protectionMessage !== ""
                                x: (parent.width - width) / 2
                                y: connectedIndicatorLoader.implicitHeight
                                width: visible
                                    ? protectionMessageBackground.implicitWidth : 0
                                height: visible
                                    ? protectionMessageBackground.implicitHeight : 0
                                implicitWidth: width
                                implicitHeight: height

                                StyledRectangularShadow {
                                    target: protectionMessageBackground
                                    visible: protectionMessageWrapper.visible
                                }

                                Rectangle {
                                    id: protectionMessageBackground
                                    anchors.fill: parent
                                    color: Appearance.colors.colError
                                    property real padding: 10
                                    implicitHeight:
                                        protectionMessageRowLayout.implicitHeight
                                        + padding * 2
                                    implicitWidth:
                                        protectionMessageRowLayout.implicitWidth
                                        + padding * 2
                                    radius: Appearance.rounding.normal

                                    RowLayout {
                                        id: protectionMessageRowLayout
                                        anchors.centerIn: parent
                                        MaterialSymbol {
                                            text: "dangerous"
                                            iconSize:
                                                Appearance.font.pixelSize.hugeass
                                            color: Appearance.colors.colOnError
                                        }
                                        StyledText {
                                            horizontalAlignment: Text.AlignHCenter
                                            color: Appearance.colors.colOnError
                                            wrapMode: Text.Wrap
                                            text: root.protectionMessage
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.connectedIndicator
                                hoverEnabled: true
                                onEntered: root.hideOsd()
                            }
                        }
                    }
                }

                ConnectedSurfaceBodyMask {
                    id: connectedMask
                    geometry: connectedGeometry
                    bodyItem: statusFrame.bodyItem
                    visibleBodyRect: statusFrame.visibleBodyRect
                    inputEnabled: root.connectedIndicator && root._visualOpen
                }

                Region {
                    id: detachedMask
                    item: detachedHost
                }

                Item {
                    id: detachedHost
                    readonly property bool entersFromTop:
                        !(Config.options?.bar?.bottom ?? false)
                    property real openProgress: root._visualOpen ? 1 : 0
                    width: detachedColumn.implicitWidth
                    height: detachedColumn.implicitHeight
                    x: (osdRoot.width - width) / 2
                    y: {
                        const restY = entersFromTop
                            ? Appearance.sizes.barHeight
                            : osdRoot.height - Appearance.sizes.barHeight - height
                        return restY + (1 - openProgress)
                            * (entersFromTop ? -12 : 12)
                    }
                    visible: !root.connectedIndicator && openProgress > 0.001
                    transformOrigin: entersFromTop ? Item.Top : Item.Bottom
                    scale: 0.94 + 0.06 * openProgress
                    opacity: openProgress

                    Behavior on openProgress {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: root._visualOpen
                                ? Appearance.animation.elementMoveEnter.duration
                                : Appearance.animation.elementMoveExit.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root._visualOpen
                                ? Appearance.animation.elementMoveEnter.bezierCurve
                                : Appearance.animationCurves.standardAccel
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.currentIndicator !== "media"
                        hoverEnabled: true
                        onEntered: root.hideOsd()
                    }

                    HoverHandler {
                        enabled: root.currentIndicator === "media"
                        onHoveredChanged: {
                            if (hovered)
                                osdTimeout.stop()
                            else if (root.mediaOsdVisible)
                                osdTimeout.restart()
                        }
                    }

                    ColumnLayout {
                        id: detachedColumn
                        anchors.fill: parent
                        Loader {
                            source: !root.connectedIndicator
                                ? (root.indicators.find(
                                    i => i.id === root.currentIndicator)?.sourceUrl ?? "")
                                : ""
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onOsdRequested(kind: string): void {
            if (kind === "current") root.triggerOsd()
            else root.openIndicator(kind,true)
        }
        function onOsdDismissed(): void { root.hideOsd() }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Item {
            GlobalShortcut {
                name: "osdVolumeTrigger"
                description: "Triggers volume OSD on press"

                onPressed: {
                    root.triggerOsd();
                }
            }
            GlobalShortcut {
                name: "osdVolumeHide"
                description: "Hides volume OSD on press"

                onPressed: {
                    GlobalStates.osdVolumeOpen = false;
                }
            }
        }
    }
}
