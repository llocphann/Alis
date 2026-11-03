pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.perimeter
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

// Waffle keeps its own BarPopup API/palette, but presentation is now driven by
// the same connected-surface geometry used by ii. This avoids a second visual
// seam model while preserving Waffle callers, focus and hover-close behavior.
Loader {
    id: root

    required property var contentItem
    property real padding: Looks.radius.large - Looks.radius.medium
    property bool noSmoothClosing:
        !(Config.options?.waffles?.tweaks?.smootherMenuAnimations ?? true)
    property bool closeOnFocusLost: false
    property bool closeOnHoverLost: true
    property int closeOnHoverLostDelay: 300
    property bool anchorHovered: false
    signal focusCleared()

    readonly property bool _anyWafflePanelOpen: GlobalStates.searchOpen
        || GlobalStates.waffleActionCenterOpen
        || GlobalStates.waffleNotificationCenterOpen
        || GlobalStates.waffleWidgetsOpen
        || GlobalStates.waffleClipboardOpen
        || GlobalStates.waffleTaskViewOpen

    on_AnyWafflePanelOpenChanged: {
        if (root._anyWafflePanelOpen && root.active)
            root.active = false
    }

    property Item anchorItem: parent
    // Optional rect in anchorItem-local coordinates. Ownership/output remains
    // tied to the real Bar control; the rect only narrows tangent placement.
    property var anchorRect: null
    // Compatibility knobs retained for callers. visualMargin no longer creates
    // a detached gap; it controls only the free-side shadow extent.
    property real visualMargin: Looks.dp(12)
    readonly property bool barAtBottom:
        Config.options?.waffles?.bar?.bottom ?? false
    property bool popupBelow: false
    property real ambientShadowWidth: 1
    readonly property bool popupContainsMouse:
        root.item?.popupContainsMouse ?? false

    readonly property string _attachmentEdge:
        root.popupBelow ? "top" : (root.barAtBottom ? "bottom" : "top")
    readonly property var _anchorWindow: root.anchorItem
        ? root.anchorItem.QsWindow.window : null
    readonly property var _anchorScreen: root._anchorWindow
        ? root._anchorWindow.screen : null
    readonly property bool _anchorReady: root.anchorItem !== null
        && root._anchorWindow !== null
        && root._anchorScreen !== null
        && root.anchorItem.width > 0
        && root.anchorItem.height > 0
    readonly property real _barSurfaceThickness:
        Math.max(1, Number(root._anchorWindow?.height
            ?? Looks.scaledBar(48, root._anchorScreen)))
    readonly property real _screenEdgeThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
    readonly property real _popupScreenMargin: Math.max(0,
        root._screenEdgeThickness - PerimeterTokens.seamOverlap)

    function grabFocus() {
        if (item)
            item.grabFocus()
    }

    function close() {
        if (item)
            item.close()
        else
            root.active = false
    }

    function _anchorRect(outputWidth, outputHeight) {
        const target = root.anchorItem
        const host = target ? target.QsWindow : null
        const hostWindow = root._anchorWindow
        if (!target || !host || !hostWindow || !root._anchorScreen
                || target.width <= 0 || target.height <= 0
                || outputWidth <= 0 || outputHeight <= 0)
            return Qt.rect(0, 0, 0, 0)

        // Geometry reads keep transformed/scaled outputs reactive.
        target.x
        target.y
        target.width
        target.height
        hostWindow.windowTransform

        const localX = Number(root.anchorRect?.x ?? 0)
        const localY = Number(root.anchorRect?.y ?? 0)
        const localWidth = Math.max(1,
            Number(root.anchorRect?.width ?? target.width))
        const mapped = host.mapFromItem(target, localX, localY)
        const barY = root._attachmentEdge === "bottom"
            ? Math.max(0, outputHeight - root._barSurfaceThickness) : 0
        return Qt.rect(mapped.x, barY,
            localWidth, root._barSurfaceThickness)
    }

    active: false
    visible: active

    sourceComponent: PanelWindow {
        id: popupWindow

        screen: root._anchorScreen
        visible: root.active && root._anchorReady
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        focusable: root.closeOnFocusLost

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "quickshell:waffle-bar-popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus:
            root.closeOnFocusLost && root.active && !popupWindow.closing
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

        property real revealProgress: 0
        property bool closing: false
        property bool focusGrabRequested: false
        readonly property bool popupContainsMouse:
            frame.bodyHovered || popupHoverHandler.hovered
        property alias popupHoverArea: popupHoverHandler

        Timer {
            id: closeFallbackTimer
            interval: 260
            repeat: false
            onTriggered: {
                if (popupWindow.closing) {
                    closeAnim.stop()
                    popupWindow.closing = false
                    root.active = false
                }
            }
        }

        Component.onCompleted: {
            popupWindow.closing = false
            popupWindow.revealProgress = 0
            openAnim.restart()
        }

        function close() {
            popupWindow.focusGrabRequested = false
            if (root.noSmoothClosing || !Looks.transition.enabled) {
                closeFallbackTimer.stop()
                popupWindow.closing = false
                root.active = false
                return
            }
            if (popupWindow.closing) {
                closeFallbackTimer.restart()
                return
            }
            popupWindow.closing = true
            openAnim.stop()
            closeFallbackTimer.restart()
            closeAnim.restart()
        }

        function grabFocus() {
            popupWindow.focusGrabRequested = true
        }

        NumberAnimation {
            id: openAnim
            target: popupWindow
            property: "revealProgress"
            from: 0
            to: 1
            duration: Looks.transition.enabled
                ? Looks.transition.duration.medium : 0
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.decelerate
        }

        SequentialAnimation {
            id: closeAnim

            NumberAnimation {
                target: popupWindow
                property: "revealProgress"
                to: 0
                duration: Looks.transition.enabled
                    ? Looks.transition.duration.fast : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Looks.transition.easing.bezierCurve.accelerate
            }

            ScriptAction {
                script: {
                    closeFallbackTimer.stop()
                    popupWindow.closing = false
                    root.active = false
                }
            }
        }

        Shortcut {
            sequences: [StandardKey.Cancel]
            enabled: root.active
            onActivated: root.close()
        }

        CompositorFocusGrab {
            id: focusGrab
            active: (root.closeOnFocusLost || popupWindow.focusGrabRequested)
                && root.active
                && CompositorService.isHyprland
            windows: [popupWindow]
            onCleared: root.focusCleared()
        }

        Timer {
            interval: root.closeOnHoverLostDelay
            running: root.closeOnHoverLost
                && root.active
                && !popupWindow.popupContainsMouse
                && !root.anchorHovered
            onTriggered: root.close()
        }

        ConnectedSurfaceGeometry {
            id: geometry

            edge: root._attachmentEdge
            alignment: "center"
            outputRect: Qt.rect(0, 0, popupWindow.width, popupWindow.height)
            anchorRect: root._anchorRect(
                popupWindow.width, popupWindow.height)
            bodySize: Qt.size(
                Math.max(1, (root.contentItem?.implicitWidth ?? 0)
                    + root.padding * 2),
                Math.max(1, (root.contentItem?.implicitHeight ?? 0)
                    + root.padding * 2))
            outerRadius: Looks.radius.large
            screenMargin: root._popupScreenMargin
            connectorLength: 0
            progress: popupWindow.revealProgress
            devicePixelRatio: popupWindow.devicePixelRatio
        }

        QtObject {
            id: directEdgeAttachment

            readonly property rect body: geometry.bodyRect
            readonly property real epsilon:
                1 / Math.max(1, popupWindow.devicePixelRatio)
            readonly property real margin: geometry.effectiveScreenMargin
            readonly property bool atLeft:
                Math.abs(body.x - margin) <= epsilon
            readonly property bool atRight:
                Math.abs((popupWindow.width - margin)
                    - (body.x + body.width)) <= epsilon
            readonly property bool atTop:
                Math.abs(body.y - margin) <= epsilon
            readonly property bool atBottom:
                Math.abs((popupWindow.height - margin)
                    - (body.y + body.height)) <= epsilon
        }

        ConnectedSurfaceRevealClip {
            id: popupRevealClip
            geometry: geometry

            ConnectedSurfaceFrame {
                id: frame
                anchors.fill: parent
                geometry: geometry
                fillColor: Looks.colors.bg1Base
                borderColor: Looks.colors.bg2Border
                borderWidth: Math.max(0, root.ambientShadowWidth)
                connectorBorderWidth: 0
                connectorVisible: false
                // Keep hover ownership on the whole connected body (including
                // padding) while retaining popupHoverArea for old Waffle callers.
                hoverEnabled: root.active
                shadowEnabled: Looks.effectsEnabled
                    && root.visualMargin > 0
                shadowExtent: Math.max(0, root.visualMargin)
                shadowColor: Looks.colors.shadow
                joinTop: root._attachmentEdge === "top"
                    || directEdgeAttachment.atTop
                joinBottom: root._attachmentEdge === "bottom"
                    || directEdgeAttachment.atBottom
                joinLeft: directEdgeAttachment.atLeft
                joinRight: directEdgeAttachment.atRight
                shadowTop: !frame.joinTop
                shadowBottom: !frame.joinBottom
                shadowLeft: !frame.joinLeft
                shadowRight: !frame.joinRight
            }

            ConnectedSurfaceContentHost {
                id: contentHost
                geometry: geometry
                padding: root.padding
                opacity: 1
                children: [root.contentItem]

                HoverHandler {
                    id: popupHoverHandler
                    enabled: root.active
                }
            }
        }

        ConnectedSurfaceMask {
            id: connectedMask

            geometry: geometry
            bodyItem: frame.bodyItem
            connectorItem: frame.connectorItem
            inputEnabled: root.active && !popupWindow.closing && popupWindow.revealProgress > 0.01
        }

        mask: connectedMask

        PanelWindow {
            id: clickOutsideBackdrop

            screen: root._anchorScreen
            visible: popupWindow.visible
                && !popupWindow.closing
                && CompositorService.isNiri
                && root.closeOnFocusLost
            color: Qt.rgba(0, 0, 0, 1 / 255)
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace:
                "quickshell:waffle-bar-popup-backdrop"
            mask: Region {
                item: clickOutsideBackdrop.visible ? backdropMouseArea : emptyBackdropRegion
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Item {
                id: emptyBackdropRegion
                width: 0
                height: 0
            }

            MouseArea {
                id: backdropMouseArea
                anchors.fill: parent
                enabled: clickOutsideBackdrop.visible
                onClicked: root.close()
            }
        }
    }
}
