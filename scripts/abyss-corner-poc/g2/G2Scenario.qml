pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

QtObject {
    id: root

    property var targetScreen: null
    property int readinessStableTicks: 0
    property real readinessLastWidth: -1
    property real readinessLastHeight: -1
    property bool readinessEmitted: false
    property int clickCount: 0

    function envReal(name, fallback) {
        const raw = Quickshell.env(name)
        if (raw === undefined || raw === null || String(raw).trim().length === 0)
            return fallback
        const value = Number(raw)
        return Number.isFinite(value) ? value : fallback
    }

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value))
    }

    // One composition-domain clip for every Overlay primitive: Abyss field,
    // input and shadow. Geometry stays full-output; only pixels/input already
    // owned by Top-layer Bar/Screen Edge surfaces are removed.
    function clipExternalOwners(raw) {
        let left = Math.max(0, raw.x)
        let top = Math.max(0, raw.y)
        let right = Math.min(root.outputWidth, raw.x + raw.width)
        let bottom = Math.min(root.outputHeight, raw.y + raw.height)

        if (root.edgeName === "top")
            top = Math.max(top, root.attachmentBoundary)
        else if (root.edgeName === "bottom")
            bottom = Math.min(bottom, root.attachmentBoundary)
        else if (root.edgeName === "left")
            left = Math.max(left, root.attachmentBoundary)
        else
            right = Math.min(right, root.attachmentBoundary)

        if (root.horizontal && root.atTangentStart)
            left = Math.max(left, root.frameThickness)
        if (root.horizontal && root.atTangentEnd)
            right = Math.min(right, root.outputWidth - root.frameThickness)
        if (!root.horizontal && root.atTangentStart)
            top = Math.max(top, root.frameThickness)
        if (!root.horizontal && root.atTangentEnd)
            bottom = Math.min(bottom, root.outputHeight - root.frameThickness)

        return Qt.rect(left, top,
            Math.max(0, right - left), Math.max(0, bottom - top))
    }

    readonly property string edgeName: {
        const value = String(Quickshell.env("ALIS_ABYSS_G2_EDGE") || "top").toLowerCase()
        return ["top", "bottom", "left", "right"].includes(value) ? value : "top"
    }
    readonly property real sourceT:
        root.clamp(root.envReal("ALIS_ABYSS_G2_SOURCE_T", 0.5), 0, 1)
    readonly property real progress:
        root.clamp(root.envReal("ALIS_ABYSS_G2_PROGRESS", 1), 0, 1)
    readonly property bool showGuides:
        String(Quickshell.env("ALIS_ABYSS_G2_GUIDES") || "1") !== "0"

    // Upstream-relative G1 values. G2 changes composition only, not morphology.
    readonly property real ownerThickness: 42
    readonly property real popupWidth: 360
    readonly property real popupHeight: 300
    readonly property real popupRadius: 30
    readonly property real fuse: 30
    readonly property real weld: 3
    readonly property real frameThickness: 10
    readonly property real shadowExtent: 15
    readonly property real tangentInset: Math.max(0, root.frameThickness - root.weld)
    readonly property bool horizontal: root.edgeName === "top" || root.edgeName === "bottom"

    readonly property real outputWidth: Number(root.targetScreen?.width ?? 0)
    readonly property real outputHeight: Number(root.targetScreen?.height ?? 0)
    readonly property real tangentExtent: root.horizontal
        ? root.outputWidth : root.outputHeight
    readonly property real popupTangentExtent: root.horizontal
        ? root.popupWidth : root.popupHeight
    readonly property real popupCrossExtent: root.horizontal
        ? root.popupHeight : root.popupWidth
    readonly property real tangentStart: {
        const raw = root.sourceT * root.tangentExtent - root.popupTangentExtent / 2
        return root.clamp(raw, root.tangentInset,
            Math.max(root.tangentInset,
                root.tangentExtent - root.popupTangentExtent - root.tangentInset))
    }
    readonly property bool atTangentStart:
        Math.abs(root.tangentStart - root.tangentInset) <= 0.01
    readonly property bool atTangentEnd:
        Math.abs(root.tangentStart + root.popupTangentExtent
            - (root.tangentExtent - root.tangentInset)) <= 0.01
    readonly property var popupJoins: {
        const joins = ["owner"]
        if (root.atTangentStart)
            joins.push("frame-start")
        else if (root.atTangentEnd)
            joins.push("frame-end")
        return joins
    }

    readonly property real attachmentBoundary:
        root.edgeName === "top" || root.edgeName === "left"
            ? root.ownerThickness
            : root.edgeName === "bottom"
                ? root.outputHeight - root.ownerThickness
                : root.outputWidth - root.ownerThickness

    readonly property rect restingPopupRect: {
        if (root.edgeName === "top")
            return Qt.rect(root.tangentStart,
                root.ownerThickness - root.weld,
                root.popupWidth, root.popupHeight)
        if (root.edgeName === "bottom")
            return Qt.rect(root.tangentStart,
                root.outputHeight - root.ownerThickness - root.popupHeight + root.weld,
                root.popupWidth, root.popupHeight)
        if (root.edgeName === "left")
            return Qt.rect(root.ownerThickness - root.weld,
                root.tangentStart,
                root.popupWidth, root.popupHeight)
        return Qt.rect(
            root.outputWidth - root.ownerThickness - root.popupWidth + root.weld,
            root.tangentStart,
            root.popupWidth, root.popupHeight)
    }

    readonly property real animationOffset: (1 - root.progress) * root.popupCrossExtent
    readonly property rect animatedPopupRect: {
        const body = root.restingPopupRect
        if (root.edgeName === "top")
            return Qt.rect(body.x, body.y - root.animationOffset, body.width, body.height)
        if (root.edgeName === "bottom")
            return Qt.rect(body.x, body.y + root.animationOffset, body.width, body.height)
        if (root.edgeName === "left")
            return Qt.rect(body.x - root.animationOffset, body.y, body.width, body.height)
        return Qt.rect(body.x + root.animationOffset, body.y, body.width, body.height)
    }

    // Expand only in the tangent direction by fuse reach. Cross-axis expansion
    // is AA-only: this makes progress=0 disappear completely behind the owner
    // instead of leaving a fuse tail after the body has slid underneath.
    readonly property real aaReach: 2
    readonly property rect rawPaintBounds: root.horizontal
        ? Qt.rect(root.animatedPopupRect.x - root.fuse - root.aaReach,
            root.animatedPopupRect.y - root.aaReach,
            root.animatedPopupRect.width + 2 * (root.fuse + root.aaReach),
            root.animatedPopupRect.height + 2 * root.aaReach)
        : Qt.rect(root.animatedPopupRect.x - root.aaReach,
            root.animatedPopupRect.y - root.fuse - root.aaReach,
            root.animatedPopupRect.width + 2 * root.aaReach,
            root.animatedPopupRect.height + 2 * (root.fuse + root.aaReach))

    readonly property rect paintBounds:
        root.clipExternalOwners(root.rawPaintBounds)

    readonly property rect visibleBodyRect:
        root.clipExternalOwners(root.animatedPopupRect)

    // RectangularShadow's material is larger than the nominal item by its blur
    // reach. Render that complete shadow into a private texture first, then
    // expose only this owner-clipped sourceRect. The displayed texture cannot
    // bleed back across a Top-layer owner boundary.
    readonly property real shadowTextureExtent: root.shadowExtent + 2
    readonly property rect rawShadowBounds: Qt.rect(
        root.animatedPopupRect.x - root.shadowTextureExtent,
        root.animatedPopupRect.y - root.shadowTextureExtent,
        root.animatedPopupRect.width + 2 * root.shadowTextureExtent,
        root.animatedPopupRect.height + 2 * root.shadowTextureExtent)
    readonly property rect shadowPaintBounds:
        root.clipExternalOwners(root.rawShadowBounds)

    readonly property rect revealRect: root.edgeName === "top"
        ? Qt.rect(0, root.attachmentBoundary,
            root.outputWidth, Math.max(0, root.outputHeight - root.attachmentBoundary))
        : root.edgeName === "bottom"
            ? Qt.rect(0, 0, root.outputWidth, root.attachmentBoundary)
        : root.edgeName === "left"
            ? Qt.rect(root.attachmentBoundary, 0,
                Math.max(0, root.outputWidth - root.attachmentBoundary), root.outputHeight)
        : Qt.rect(0, 0, root.attachmentBoundary, root.outputHeight)

    readonly property real moduleTangentExtent: 64
    readonly property real moduleTangentCenter: root.clamp(
        root.sourceT * root.tangentExtent,
        root.frameThickness + root.moduleTangentExtent / 2 + 2,
        root.tangentExtent - root.frameThickness - root.moduleTangentExtent / 2 - 2)
    readonly property rect moduleRect: {
        const tangentStart = root.moduleTangentCenter - root.moduleTangentExtent / 2
        const crossInset = 5
        const crossExtent = Math.max(8, root.ownerThickness - crossInset * 2)
        if (root.edgeName === "top")
            return Qt.rect(tangentStart, crossInset,
                root.moduleTangentExtent, crossExtent)
        if (root.edgeName === "bottom")
            return Qt.rect(tangentStart,
                root.outputHeight - root.ownerThickness + crossInset,
                root.moduleTangentExtent, crossExtent)
        if (root.edgeName === "left")
            return Qt.rect(crossInset, tangentStart,
                crossExtent, root.moduleTangentExtent)
        return Qt.rect(root.outputWidth - root.ownerThickness + crossInset,
            tangentStart, crossExtent, root.moduleTangentExtent)
    }

    readonly property var ownerShape: {
        const pad = root.fuse * 2
        if (root.edgeName === "top")
            return { x: -pad, y: 0, width: root.outputWidth + 2 * pad,
                height: root.ownerThickness, radius: 0, fuse: 0, id: "owner" }
        if (root.edgeName === "bottom")
            return { x: -pad, y: root.outputHeight - root.ownerThickness,
                width: root.outputWidth + 2 * pad, height: root.ownerThickness,
                radius: 0, fuse: 0, id: "owner" }
        if (root.edgeName === "left")
            return { x: 0, y: -pad, width: root.ownerThickness,
                height: root.outputHeight + 2 * pad, radius: 0, fuse: 0, id: "owner" }
        return { x: root.outputWidth - root.ownerThickness, y: -pad,
            width: root.ownerThickness, height: root.outputHeight + 2 * pad,
            radius: 0, fuse: 0, id: "owner" }
    }

    readonly property var frameStartShape: {
        const pad = root.fuse * 2
        return root.horizontal
            ? { x: 0, y: -pad, width: root.frameThickness,
                height: root.outputHeight + 2 * pad, radius: 0, fuse: 0,
                id: "frame-start" }
            : { x: -pad, y: 0, width: root.outputWidth + 2 * pad,
                height: root.frameThickness, radius: 0, fuse: 0,
                id: "frame-start" }
    }

    readonly property var frameEndShape: {
        const pad = root.fuse * 2
        return root.horizontal
            ? { x: root.outputWidth - root.frameThickness, y: -pad,
                width: root.frameThickness, height: root.outputHeight + 2 * pad,
                radius: 0, fuse: 0, id: "frame-end" }
            : { x: -pad, y: root.outputHeight - root.frameThickness,
                width: root.outputWidth + 2 * pad, height: root.frameThickness,
                radius: 0, fuse: 0, id: "frame-end" }
    }

    readonly property var popupShape: ({
        x: root.animatedPopupRect.x,
        y: root.animatedPopupRect.y,
        width: root.animatedPopupRect.width,
        height: root.animatedPopupRect.height,
        radius: root.popupRadius,
        fuse: root.fuse,
        id: "popup",
        joins: root.popupJoins
    })

    readonly property bool shadowTop: root.edgeName !== "top"
        && !(root.verticalJoinAtStart)
    readonly property bool shadowBottom: root.edgeName !== "bottom"
        && !(root.verticalJoinAtEnd)
    readonly property bool shadowLeft: root.edgeName !== "left"
        && !(root.horizontalJoinAtStart)
    readonly property bool shadowRight: root.edgeName !== "right"
        && !(root.horizontalJoinAtEnd)
    readonly property bool horizontalJoinAtStart: root.horizontal && root.atTangentStart
    readonly property bool horizontalJoinAtEnd: root.horizontal && root.atTangentEnd
    readonly property bool verticalJoinAtStart: !root.horizontal && root.atTangentStart
    readonly property bool verticalJoinAtEnd: !root.horizontal && root.atTangentEnd

    readonly property bool paintRespectsOwnerSeam:
        root.edgeName === "top"
            ? root.paintBounds.y >= root.attachmentBoundary - 0.01
        : root.edgeName === "bottom"
            ? root.paintBounds.y + root.paintBounds.height <= root.attachmentBoundary + 0.01
        : root.edgeName === "left"
            ? root.paintBounds.x >= root.attachmentBoundary - 0.01
        : root.paintBounds.x + root.paintBounds.width <= root.attachmentBoundary + 0.01
    readonly property bool paintRespectsTangentOwners:
        (!root.horizontal || !root.atTangentStart
            || root.paintBounds.x >= root.frameThickness - 0.01)
        && (!root.horizontal || !root.atTangentEnd
            || root.paintBounds.x + root.paintBounds.width
                <= root.outputWidth - root.frameThickness + 0.01)
        && (root.horizontal || !root.atTangentStart
            || root.paintBounds.y >= root.frameThickness - 0.01)
        && (root.horizontal || !root.atTangentEnd
            || root.paintBounds.y + root.paintBounds.height
                <= root.outputHeight - root.frameThickness + 0.01)
    readonly property bool shadowRespectsOwnerSeam:
        root.edgeName === "top"
            ? root.shadowPaintBounds.y >= root.attachmentBoundary - 0.01
        : root.edgeName === "bottom"
            ? root.shadowPaintBounds.y + root.shadowPaintBounds.height
                <= root.attachmentBoundary + 0.01
        : root.edgeName === "left"
            ? root.shadowPaintBounds.x >= root.attachmentBoundary - 0.01
        : root.shadowPaintBounds.x + root.shadowPaintBounds.width
            <= root.attachmentBoundary + 0.01
    readonly property bool shadowRespectsTangentOwners:
        (!root.horizontal || !root.atTangentStart
            || root.shadowPaintBounds.x >= root.frameThickness - 0.01)
        && (!root.horizontal || !root.atTangentEnd
            || root.shadowPaintBounds.x + root.shadowPaintBounds.width
                <= root.outputWidth - root.frameThickness + 0.01)
        && (root.horizontal || !root.atTangentStart
            || root.shadowPaintBounds.y >= root.frameThickness - 0.01)
        && (root.horizontal || !root.atTangentEnd
            || root.shadowPaintBounds.y + root.shadowPaintBounds.height
                <= root.outputHeight - root.frameThickness + 0.01)

    property QtObject ownerWindowObject: PanelWindow {
        id: ownerWindow
        screen: root.targetScreen
        visible: root.targetScreen !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "alis:abyss-g2-owner"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item { id: emptyOwnerInput; width: 0; height: 0; visible: false }
        mask: Region { item: emptyOwnerInput }

        Rectangle {
            x: root.ownerShape.x
            y: root.ownerShape.y
            width: root.ownerShape.width
            height: root.ownerShape.height
            color: "#f4c542"
        }
        Rectangle {
            x: root.frameStartShape.x
            y: root.frameStartShape.y
            width: root.frameStartShape.width
            height: root.frameStartShape.height
            color: "#f4c542"
        }
        Rectangle {
            x: root.frameEndShape.x
            y: root.frameEndShape.y
            width: root.frameEndShape.width
            height: root.frameEndShape.height
            color: "#f4c542"
        }

        // A fake Bar module lives entirely in the owner surface. If Overlay
        // painting crosses the seam this marker is visibly covered.
        Rectangle {
            x: root.moduleRect.x
            y: root.moduleRect.y
            width: root.moduleRect.width
            height: root.moduleRect.height
            radius: 8
            color: "#1c2329"
            border.width: 2
            border.color: "#70f0a8"
            Text {
                anchors.centerIn: parent
                text: root.horizontal ? "MODULE" : "M"
                color: "#70f0a8"
                font.pixelSize: root.horizontal ? 11 : 13
                rotation: root.horizontal ? 0 : -90
            }
        }

        Rectangle {
            visible: root.showGuides
            color: "#ff4fd8"
            x: root.edgeName === "right" ? root.attachmentBoundary
                : root.edgeName === "left" ? root.attachmentBoundary - 1 : 0
            y: root.edgeName === "bottom" ? root.attachmentBoundary
                : root.edgeName === "top" ? root.attachmentBoundary - 1 : 0
            width: root.horizontal ? root.outputWidth : 1
            height: root.horizontal ? 1 : root.outputHeight
        }
    }

    property QtObject popupWindowObject: PanelWindow {
        id: popupWindow
        screen: root.targetScreen
        visible: root.targetScreen !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        focusable: false
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "alis:abyss-g2-popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item {
            id: inputProxy
            x: root.visibleBodyRect.x
            y: root.visibleBodyRect.y
            width: root.visibleBodyRect.width
            height: root.visibleBodyRect.height
            visible: false
        }
        mask: Region {
            item: inputProxy
            radius: Math.min(root.popupRadius,
                inputProxy.width / 2, inputProxy.height / 2)
        }

        Item {
            id: revealViewport
            x: root.revealRect.x
            y: root.revealRect.y
            width: root.revealRect.width
            height: root.revealRect.height
            clip: true

            Item {
                id: fullOutputLayer
                x: -revealViewport.x
                y: -revealViewport.y
                width: popupWindow.width
                height: popupWindow.height

                // First render the complete blur into a bounded private
                // texture. Directly clipping RectangularShadow is insufficient:
                // its internal material extends beyond the nominal Item by the
                // blur reach. ShaderEffectSource.sourceRect turns the final
                // owner exclusion into an actual texture boundary.
                Item {
                    id: shadowTextureSource
                    z: -100
                    x: root.rawShadowBounds.x
                    y: root.rawShadowBounds.y
                    width: root.rawShadowBounds.width
                    height: root.rawShadowBounds.height
                    clip: true

                    RectangularShadow {
                        x: root.shadowTextureExtent
                        y: root.shadowTextureExtent
                        width: root.animatedPopupRect.width
                        height: root.animatedPopupRect.height
                        radius: root.popupRadius + root.shadowExtent * 0.75
                        blur: root.shadowExtent
                        spread: 0
                        offset: Qt.vector2d(0, 0)
                        color: Qt.rgba(0, 0, 0, 0.7)
                        cached: false
                    }
                }

                ShaderEffectSource {
                    id: isolatedShadow
                    z: 0
                    visible: root.visibleBodyRect.width > 0
                        && root.visibleBodyRect.height > 0
                        && root.shadowPaintBounds.width > 0
                        && root.shadowPaintBounds.height > 0
                    x: root.shadowPaintBounds.x
                    y: root.shadowPaintBounds.y
                    width: root.shadowPaintBounds.width
                    height: root.shadowPaintBounds.height
                    sourceItem: shadowTextureSource
                    sourceRect: Qt.rect(
                        root.shadowPaintBounds.x - root.rawShadowBounds.x,
                        root.shadowPaintBounds.y - root.rawShadowBounds.y,
                        root.shadowPaintBounds.width,
                        root.shadowPaintBounds.height)
                    hideSource: true
                    live: true
                    recursive: false
                    smooth: true
                }

                AbyssSplitField {
                    id: splitField
                    z: 1
                    width: popupWindow.width
                    height: popupWindow.height
                    paintBounds: root.paintBounds
                    shapes: [
                        root.ownerShape,
                        root.frameStartShape,
                        root.frameEndShape,
                        root.popupShape
                    ]
                    tint: "#f4c542"
                    smoothing: root.fuse
                }

                Rectangle {
                    z: 2
                    x: root.animatedPopupRect.x + 24
                    y: root.animatedPopupRect.y + 24
                    width: Math.max(0, root.animatedPopupRect.width - 48)
                    height: 46
                    radius: 12
                    color: "#20262c"
                    visible: root.visibleBodyRect.width > 0
                        && root.visibleBodyRect.height > 0
                    Text {
                        anchors.centerIn: parent
                        color: "white"
                        font.pixelSize: 13
                        text: "Overlay content · clicks " + root.clickCount
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.clickCount += 1
                    }
                }

                Rectangle {
                    z: 4
                    visible: root.showGuides
                    x: root.animatedPopupRect.x
                    y: root.animatedPopupRect.y
                    width: root.animatedPopupRect.width
                    height: root.animatedPopupRect.height
                    color: "transparent"
                    border.width: 2
                    border.color: "#57d3ff"
                    radius: root.popupRadius
                }

                Rectangle {
                    z: 5
                    visible: root.showGuides && root.paintBounds.width > 0
                        && root.paintBounds.height > 0
                    x: root.paintBounds.x
                    y: root.paintBounds.y
                    width: root.paintBounds.width
                    height: root.paintBounds.height
                    color: "transparent"
                    border.width: 1
                    border.color: "#70f0a8"
                }
            }
        }
    }

    readonly property bool outputGeometryReady: root.targetScreen !== null
        && splitField.shaderCompiled
        && ownerWindow.width > 0 && ownerWindow.height > 0
        && popupWindow.width > 0 && popupWindow.height > 0
        && Math.abs(ownerWindow.width - root.outputWidth) <= 0.5
        && Math.abs(ownerWindow.height - root.outputHeight) <= 0.5
        && Math.abs(popupWindow.width - root.outputWidth) <= 0.5
        && Math.abs(popupWindow.height - root.outputHeight) <= 0.5

    function readinessPayload() {
        const body = root.animatedPopupRect
        const paint = root.paintBounds
        const input = root.visibleBodyRect
        const shadow = root.shadowPaintBounds
        const module = root.moduleRect
        return {
            output: root.targetScreen?.name ?? "",
            outputX: Number(root.targetScreen?.x ?? 0),
            outputY: Number(root.targetScreen?.y ?? 0),
            outputWidth: Number(root.outputWidth),
            outputHeight: Number(root.outputHeight),
            devicePixelRatio: Number(popupWindow.devicePixelRatio),
            edge: root.edgeName,
            sourceT: Number(root.sourceT),
            progress: Number(root.progress),
            ownerThickness: Number(root.ownerThickness),
            frameThickness: Number(root.frameThickness),
            radius: Number(root.popupRadius),
            fuse: Number(root.fuse),
            weld: Number(root.weld),
            attachmentBoundary: Number(root.attachmentBoundary),
            popupX: Number(body.x),
            popupY: Number(body.y),
            popupWidth: Number(body.width),
            popupHeight: Number(body.height),
            restingPopupX: Number(root.restingPopupRect.x),
            restingPopupY: Number(root.restingPopupRect.y),
            animationOffset: Number(root.animationOffset),
            paintX: Number(paint.x),
            paintY: Number(paint.y),
            paintWidth: Number(paint.width),
            paintHeight: Number(paint.height),
            inputX: Number(input.x),
            inputY: Number(input.y),
            inputWidth: Number(input.width),
            inputHeight: Number(input.height),
            shadowX: Number(shadow.x),
            shadowY: Number(shadow.y),
            shadowWidth: Number(shadow.width),
            shadowHeight: Number(shadow.height),
            shadowIsolation: "texture-source-rect",
            shadowRespectsOwnerSeam: root.shadowRespectsOwnerSeam,
            shadowRespectsTangentOwners: root.shadowRespectsTangentOwners,
            moduleX: Number(module.x),
            moduleY: Number(module.y),
            moduleWidth: Number(module.width),
            moduleHeight: Number(module.height),
            joins: root.popupJoins,
            atTangentStart: root.atTangentStart,
            atTangentEnd: root.atTangentEnd,
            paintRespectsOwnerSeam: root.paintRespectsOwnerSeam,
            paintRespectsTangentOwners: root.paintRespectsTangentOwners,
            shadowTop: root.shadowTop,
            shadowBottom: root.shadowBottom,
            shadowLeft: root.shadowLeft,
            shadowRight: root.shadowRight,
            ownerLayer: "top",
            popupLayer: "overlay",
            inputPolicy: "visible-body-only",
            keyboardFocus: "none",
            shaderCompiled: splitField.shaderCompiled,
            shaderStatus: Number(splitField.shaderStatus),
            shaderLog: String(splitField.shaderLog || ""),
            geometryStable: root.outputGeometryReady,
            readinessStableTicks: root.readinessStableTicks
        }
    }

    function probeReadiness() {
        if (root.readinessEmitted)
            return
        if (!root.outputGeometryReady) {
            root.readinessStableTicks = 0
            root.readinessLastWidth = popupWindow.width
            root.readinessLastHeight = popupWindow.height
            return
        }

        const unchanged = Math.abs(popupWindow.width - root.readinessLastWidth) <= 0.5
            && Math.abs(popupWindow.height - root.readinessLastHeight) <= 0.5
        root.readinessStableTicks = unchanged ? root.readinessStableTicks + 1 : 1
        root.readinessLastWidth = popupWindow.width
        root.readinessLastHeight = popupWindow.height

        if (root.readinessStableTicks < 3)
            return

        root.readinessEmitted = true
        console.info("ALIS_ABYSS_G2", JSON.stringify(root.readinessPayload()))
        readinessTimer.stop()
    }

    property QtObject readinessTimerObject: Timer {
        id: readinessTimer
        interval: 50
        repeat: true
        running: true
        onTriggered: root.probeReadiness()
    }
}
