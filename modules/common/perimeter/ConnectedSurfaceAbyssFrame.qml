pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// ii production connected-popup renderer.
//
// The owner Bar/Screen Edge remains painted by its Top-layer window. This
// Overlay item keeps those owner rectangles only as Abyss SDF records, then
// clips field/input/shadow paint to the popup side of every ownership boundary.
// No helper window or per-corner patch geometry is introduced.
Item {
    id: root

    required property var geometry
    property color fillColor: "white"
    property color borderColor: "transparent"
    property real borderWidth: 0
    property real fuseDepth: PerimeterTokens.abyssFuseDepth
    property real externalFrameThickness: 10
    property real aaReach: 2
    // Optional raster-only overlap into the primary owner. Geometry, input and
    // shadow clipping stay on the real owner boundary; this only lets the Abyss
    // field cover fractional-scale/antialias seams for callers that opt in.
    property real ownerPaintOverlap: 0

    property bool joinTop: false
    property bool joinBottom: false
    property bool joinLeft: false
    property bool joinRight: false

    property bool shadowEnabled: false
    property real shadowExtent: 0
    property color shadowColor: "transparent"

    property bool hoverEnabled: false
    readonly property bool bodyHovered: bodyHover.hovered
    readonly property Item bodyItem: bodyProxy
    readonly property bool shaderCompiled: field.shaderCompiled
    readonly property string shaderLog: field.shaderLog

    readonly property bool horizontal:
        root.geometry?.edge === "top" || root.geometry?.edge === "bottom"
    readonly property rect output: root.geometry?.outputRect
        ?? Qt.rect(0, 0, root.width, root.height)
    readonly property rect body: root.geometry?.animatedBodyRect
        ?? Qt.rect(0, 0, 0, 0)
    readonly property real frameThickness:
        Math.max(0, Number(root.externalFrameThickness ?? 0))
    readonly property real fuse: Math.max(0, Number(root.fuseDepth ?? 0))
    readonly property bool tangentStartJoined:
        root.horizontal ? root.joinLeft : root.joinTop
    readonly property bool tangentEndJoined:
        root.horizontal ? root.joinRight : root.joinBottom
    readonly property bool cornerJoined:
        root.tangentStartJoined || root.tangentEndJoined

    visible: root.geometry?.valid === true
        && Number(root.geometry?.revealProgress ?? root.geometry?.progress ?? 0) > 0

    function clipExternalOwners(raw, primaryOverlap) {
        let left = Math.max(root.output.x, raw.x)
        let top = Math.max(root.output.y, raw.y)
        let right = Math.min(root.output.x + root.output.width,
            raw.x + raw.width)
        let bottom = Math.min(root.output.y + root.output.height,
            raw.y + raw.height)

        const seam = Number(root.geometry?.attachmentBoundary ?? 0)
        const overlap = Math.max(0, Number(primaryOverlap ?? 0))
        if (root.geometry?.edge === "top")
            top = Math.max(top, seam - overlap)
        else if (root.geometry?.edge === "bottom")
            bottom = Math.min(bottom, seam + overlap)
        else if (root.geometry?.edge === "left")
            left = Math.max(left, seam - overlap)
        else if (root.geometry?.edge === "right")
            right = Math.min(right, seam + overlap)

        if (root.horizontal && root.tangentStartJoined)
            left = Math.max(left, root.output.x + root.frameThickness)
        if (root.horizontal && root.tangentEndJoined)
            right = Math.min(right,
                root.output.x + root.output.width - root.frameThickness)
        if (!root.horizontal && root.tangentStartJoined)
            top = Math.max(top, root.output.y + root.frameThickness)
        if (!root.horizontal && root.tangentEndJoined)
            bottom = Math.min(bottom,
                root.output.y + root.output.height - root.frameThickness)

        return Qt.rect(left, top,
            Math.max(0, right - left), Math.max(0, bottom - top))
    }

    readonly property rect rawPaintBounds: {
        const b = root.body
        const tangentReach = root.fuse + root.aaReach
        // The tangent Screen Edge fillet curves past the body's free end.
        // Give it the same raster reach as the primary-owner fillet.
        const freeReach = root.cornerJoined
            ? root.fuse + root.aaReach : root.aaReach

        if (root.geometry?.edge === "top")
            return Qt.rect(b.x - tangentReach, b.y,
                b.width + tangentReach * 2, b.height + freeReach)
        if (root.geometry?.edge === "bottom")
            return Qt.rect(b.x - tangentReach, b.y - freeReach,
                b.width + tangentReach * 2, b.height + freeReach)
        if (root.geometry?.edge === "left")
            return Qt.rect(b.x, b.y - tangentReach,
                b.width + freeReach, b.height + tangentReach * 2)
        return Qt.rect(b.x - freeReach, b.y - tangentReach,
            b.width + freeReach, b.height + tangentReach * 2)
    }

    readonly property rect paintBounds:
        root.clipExternalOwners(root.rawPaintBounds, root.ownerPaintOverlap)
    // Input ownership never follows raster seam overlap. At tangent clamps the
    // SDF body deliberately welds underneath the physical Screen Edge, while
    // compositor input remains clipped to the real owner boundary.
    readonly property rect visibleBodyRect:
        root.clipExternalOwners(root.body, 0)

    // Keep the body at the primary seam so its owner contact can form a round
    // fillet. Only the short tangent weld sits underneath the Screen Edge;
    // content, input and shadow stay clipped to the real ownership boundaries.
    readonly property rect sdfBodyRect: {
        const b = root.body
        const weld = Math.max(0, Number(PerimeterTokens.abyssWeldDepth ?? 0))
        let left = b.x
        let top = b.y
        let right = b.x + b.width
        let bottom = b.y + b.height

        if (root.horizontal) {
            if (root.tangentStartJoined)
                left -= weld
            if (root.tangentEndJoined)
                right += weld
        } else {
            if (root.tangentStartJoined)
                top -= weld
            if (root.tangentEndJoined)
                bottom += weld
        }

        return Qt.rect(left, top,
            Math.max(0, right - left), Math.max(0, bottom - top))
    }

    readonly property rect ownerShapeRect: {
        const a = root.geometry?.anchorRect ?? Qt.rect(0, 0, 0, 0)
        const pad = root.fuse * 2
        if (root.geometry?.edge === "top" || root.geometry?.edge === "bottom")
            return Qt.rect(root.output.x - pad, a.y,
                root.output.width + pad * 2, a.height)
        return Qt.rect(a.x, root.output.y - pad,
            a.width, root.output.height + pad * 2)
    }

    readonly property var ownerShape: ({
        x: root.ownerShapeRect.x,
        y: root.ownerShapeRect.y,
        width: root.ownerShapeRect.width,
        height: root.ownerShapeRect.height,
        radius: 0,
        fuse: 0,
        id: "owner"
    })

    // Tangent owner records must not exist as painted field shapes unless the
    // popup/body actually reaches that tangent edge. StyledPopup's full-output
    // viewport hid these dormant records outside its paint bounds, but the
    // content-sized Sidebar adapter exposed them as stray horizontal bars.
    // Zero-size dormant records preserve stable shader indices without adding
    // material to the union.
    readonly property var frameStartShape: !root.tangentStartJoined
        ? ({
            x: 0, y: 0, width: 0, height: 0,
            radius: 0, fuse: 0, id: "frame-start"
        })
        : root.horizontal
            ? ({
                x: root.output.x,
                y: root.output.y - root.fuse * 2,
                width: root.frameThickness,
                height: root.output.height + root.fuse * 4,
                radius: 0,
                fuse: 0,
                id: "frame-start"
            })
            : ({
                x: root.output.x - root.fuse * 2,
                y: root.output.y,
                width: root.output.width + root.fuse * 4,
                height: root.frameThickness,
                radius: 0,
                fuse: 0,
                id: "frame-start"
            })

    readonly property var frameEndShape: !root.tangentEndJoined
        ? ({
            x: 0, y: 0, width: 0, height: 0,
            radius: 0, fuse: 0, id: "frame-end"
        })
        : root.horizontal
            ? ({
                x: root.output.x + root.output.width - root.frameThickness,
                y: root.output.y - root.fuse * 2,
                width: root.frameThickness,
                height: root.output.height + root.fuse * 4,
                radius: 0,
                fuse: 0,
                id: "frame-end"
            })
            : ({
                x: root.output.x - root.fuse * 2,
                y: root.output.y + root.output.height - root.frameThickness,
                width: root.output.width + root.fuse * 4,
                height: root.frameThickness,
                radius: 0,
                fuse: 0,
                id: "frame-end"
            })

    readonly property var popupPrimaryJoins: {
        const joins = ["owner"]
        if (root.tangentStartJoined)
            joins.push("frame-start")
        else if (root.tangentEndJoined)
            joins.push("frame-end")
        return joins
    }

    readonly property var popupShape: ({
        x: root.sdfBodyRect.x,
        y: root.sdfBodyRect.y,
        width: root.sdfBodyRect.width,
        height: root.sdfBodyRect.height,
        radius: Number(root.geometry?.outerRadius ?? 0),
        fuse: root.fuse,
        id: "popup",
        joins: root.popupPrimaryJoins
    })

    // The shader ABI permits two owner relations per shape. When the body spans
    // both tangent edges, duplicate its rounded record so the second contact
    // also has the primary owner and receives the same curved fillet.
    readonly property bool needsEndJoinAux:
        root.tangentStartJoined && root.tangentEndJoined
    readonly property var popupEndJoinShape: root.needsEndJoinAux
        ? ({
            x: root.sdfBodyRect.x,
            y: root.sdfBodyRect.y,
            width: root.sdfBodyRect.width,
            height: root.sdfBodyRect.height,
            radius: Number(root.geometry?.outerRadius ?? 0),
            fuse: root.fuse,
            id: "popup-end-join",
            joins: ["owner", "frame-end"]
        })
        : ({
            x: 0, y: 0, width: 0, height: 0,
            radius: 0, fuse: 0, id: "popup-end-join"
        })

    // A box shadow cannot follow the Abyss smooth-union contact fillets. Sample
    // the *same SDF silhouette* as the visible plate, excluding physical owners
    // before blurring and once more after blurring. The extra fuse reach gives
    // the contact shoulders and the complete blur enough transparent texture
    // margin even at fractional scale; it changes no visible/input geometry.
    readonly property real shadowTextureExtent:
        Math.max(0, root.shadowExtent) + root.fuse + root.aaReach + 2
    readonly property rect rawShadowBounds: Qt.rect(
        root.body.x - root.shadowTextureExtent,
        root.body.y - root.shadowTextureExtent,
        root.body.width + root.shadowTextureExtent * 2,
        root.body.height + root.shadowTextureExtent * 2)
    readonly property rect shadowMaskBounds:
        root.clipExternalOwners(root.rawShadowBounds, 0)
    readonly property rect shadowPaintBounds:
        root.clipExternalOwners(root.rawShadowBounds, 0)

    // Reuse the exact field instance/type that paints the production union.
    // This changes neither AbyssField.frag nor its compiled QSB, and avoids
    // inventing a second body/fillet geometry for elevation.
    ConnectedSurfaceAbyssField {
        id: shadowMaskField
        z: -101
        width: root.width
        height: root.height
        paintBounds: root.shadowMaskBounds
        shapes: field.shapes
        tint: root.shadowColor
        smoothing: root.fuse
        visible: false
    }

    // Source capture is bounded to the body + fillet + blur reach. Never blur
    // the entire output-sized owner, which would create a duplicated dark band
    // beneath the physical Screen Edge away from the popup.
    ShaderEffectSource {
        id: shadowTextureSource
        z: -100
        visible: false
        x: root.rawShadowBounds.x
        y: root.rawShadowBounds.y
        width: root.rawShadowBounds.width
        height: root.rawShadowBounds.height
        sourceItem: shadowMaskField
        sourceRect: root.rawShadowBounds
        hideSource: true
        live: true
        recursive: false
        smooth: true
    }

    // Blur the silhouette mask, not a rounded rectangle. The source texture
    // already has explicit transparent padding, so automatic effect padding
    // would shift the crop/scissor coordinates and risk clipped corners again.
    MultiEffect {
        id: blurredShadow
        z: -99
        visible: root.shadowEnabled
        x: root.rawShadowBounds.x
        y: root.rawShadowBounds.y
        width: root.rawShadowBounds.width
        height: root.rawShadowBounds.height
        source: shadowTextureSource
        blurEnabled: true
        blurMax: Math.max(2, Math.ceil(root.shadowExtent))
        blur: 1.0
        autoPaddingEnabled: false
    }

    ShaderEffectSource {
        id: isolatedShadow
        z: 0
        visible: root.shadowEnabled
            && root.shadowPaintBounds.width > 0
            && root.shadowPaintBounds.height > 0
        x: root.shadowPaintBounds.x
        y: root.shadowPaintBounds.y
        width: root.shadowPaintBounds.width
        height: root.shadowPaintBounds.height
        sourceItem: blurredShadow
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

    ConnectedSurfaceAbyssField {
        id: field
        z: 1
        width: root.width
        height: root.height
        paintBounds: root.paintBounds
        shapes: [
            root.ownerShape,
            root.frameStartShape,
            root.frameEndShape,
            root.popupShape,
            root.popupEndJoinShape
        ]
        tint: root.fillColor
        rimColor: root.borderColor
        rimWidth: root.borderWidth
        smoothing: root.fuse
    }

    // Geometry-only body proxy for hover ownership and the compositor input
    // region. It paints nothing; the Abyss field above owns the silhouette.
    Item {
        id: bodyProxy
        z: 2
        x: root.body.x
        y: root.body.y
        width: root.body.width
        height: root.body.height
        visible: root.visible && width > 0 && height > 0

        HoverHandler {
            id: bodyHover
            enabled: root.hoverEnabled && bodyProxy.visible
        }
    }
}
