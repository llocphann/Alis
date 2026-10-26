pragma ComponentBehavior: Bound

import QtQuick

// Abyss adapter for an existing body that is already laid out by its feature.
//
// The caller supplies the visible body rectangle ending at the real owner seam.
// Only the SDF record extends underneath the owner by abyssWeldDepth. The shared
// Abyss frame clips field/shadow pixels back to the real owner boundary.
Item {
    id: root

    required property rect bodyRect
    required property string edge

    property rect outputRect: Qt.rect(0, 0, width, height)
    property real ownerThickness: 10
    // Tangent Screen Edge thickness can differ from the primary owner (for
    // example a top Bar joined to the right Screen Edge). Existing callers
    // inherit ownerThickness unless they explicitly provide the tangent frame.
    property real tangentFrameThickness: ownerThickness
    property real weldDepth: PerimeterTokens.abyssWeldDepth
    // Paint-only overlap into the primary owner. Keep zero by default so
    // existing callers preserve exact owner clipping unless they need to cover
    // a measured antialias seam.
    property real paintOverlap: 0
    property real bodyRadius: PerimeterTokens.popupRadius
    property real progress: 1

    property color fillColor: "white"
    property color borderColor: "transparent"
    property real borderWidth: 0
    property real fuseDepth: PerimeterTokens.abyssFuseDepth

    property bool shadowEnabled: false
    property real shadowExtent: 0
    property color shadowColor: "transparent"

    property bool joinTangentStart: false
    property bool joinTangentEnd: false

    readonly property bool horizontal:
        root.edge === "top" || root.edge === "bottom"
    readonly property real attachmentBoundary:
        root.edge === "top"
            ? root.outputRect.y + root.ownerThickness
        : root.edge === "bottom"
            ? root.outputRect.y + root.outputRect.height - root.ownerThickness
        : root.edge === "left"
            ? root.outputRect.x + root.ownerThickness
        : root.outputRect.x + root.outputRect.width - root.ownerThickness

    readonly property rect ownerRect: {
        if (root.edge === "top")
            return Qt.rect(root.outputRect.x, root.outputRect.y,
                root.outputRect.width, root.ownerThickness)
        if (root.edge === "bottom")
            return Qt.rect(root.outputRect.x, root.attachmentBoundary,
                root.outputRect.width, root.ownerThickness)
        if (root.edge === "left")
            return Qt.rect(root.outputRect.x, root.outputRect.y,
                root.ownerThickness, root.outputRect.height)
        return Qt.rect(root.attachmentBoundary, root.outputRect.y,
            root.ownerThickness, root.outputRect.height)
    }

    readonly property rect weldedBodyRect: {
        const b = root.bodyRect
        const weld = Math.max(0, root.weldDepth)
        if (root.edge === "top")
            return Qt.rect(b.x, b.y - weld, b.width, b.height + weld)
        if (root.edge === "bottom")
            return Qt.rect(b.x, b.y, b.width, b.height + weld)
        if (root.edge === "left")
            return Qt.rect(b.x - weld, b.y, b.width + weld, b.height)
        return Qt.rect(b.x, b.y, b.width + weld, b.height)
    }

    readonly property rect visibleBodyRect: frame.visibleBodyRect
    readonly property bool shaderCompiled: frame.shaderCompiled
    readonly property string shaderLog: frame.shaderLog

    QtObject {
        id: geometry
        readonly property bool valid:
            root.bodyRect.width > 0 && root.bodyRect.height > 0
                && root.ownerThickness > 0
                && ["top", "bottom", "left", "right"].includes(root.edge)
        readonly property string edge: root.edge
        readonly property rect outputRect: root.outputRect
        readonly property rect animatedBodyRect: root.weldedBodyRect
        readonly property rect anchorRect: root.ownerRect
        readonly property real attachmentBoundary: root.attachmentBoundary
        readonly property real outerRadius: root.bodyRadius
        readonly property real revealProgress: root.progress
        readonly property real progress: root.progress
    }

    ConnectedSurfaceAbyssFrame {
        id: frame
        anchors.fill: parent
        geometry: geometry
        fillColor: root.fillColor
        borderColor: root.borderColor
        borderWidth: root.borderWidth
        fuseDepth: root.fuseDepth
        externalFrameThickness: root.tangentFrameThickness
        ownerPaintOverlap: root.paintOverlap
        shadowEnabled: root.shadowEnabled
        shadowExtent: root.shadowExtent
        shadowColor: root.shadowColor

        joinLeft: root.horizontal && root.joinTangentStart
            || !root.horizontal && root.edge === "left"
        joinRight: root.horizontal && root.joinTangentEnd
            || !root.horizontal && root.edge === "right"
        joinTop: !root.horizontal && root.joinTangentStart
            || root.horizontal && root.edge === "top"
        joinBottom: !root.horizontal && root.joinTangentEnd
            || root.horizontal && root.edge === "bottom"
    }
}
