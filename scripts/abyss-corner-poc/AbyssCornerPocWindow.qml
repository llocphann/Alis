pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var targetScreen: null

    function envReal(name, fallback) {
        const raw = Quickshell.env(name)
        if (raw === undefined || raw === null || String(raw).trim().length === 0)
            return fallback
        const value = Number(raw)
        return Number.isFinite(value) ? value : fallback
    }

    readonly property string edgeName: {
        const value = String(Quickshell.env("ALIS_ABYSS_POC_EDGE") || "top").toLowerCase()
        return ["top", "bottom", "left", "right"].includes(value) ? value : "top"
    }
    readonly property string geometryMode: {
        const value = String(Quickshell.env("ALIS_ABYSS_POC_MODE") || "card-owner").toLowerCase()
        return value === "edge-reach" ? value : "card-owner"
    }
    readonly property string profileName: {
        const value = String(Quickshell.env("ALIS_ABYSS_POC_PROFILE") || "diagnostic").toLowerCase()
        return value === "upstream-relative" ? value : "diagnostic"
    }
    readonly property bool upstreamRelative: root.profileName === "upstream-relative"
    readonly property real profileOwnerThickness: root.upstreamRelative ? 42 : 56
    readonly property real profilePopupWidth: root.upstreamRelative ? 360 : 380
    readonly property real profilePopupHeight: 300
    readonly property real profilePopupRadius: root.upstreamRelative ? 30 : 48
    readonly property real profileWeld: root.upstreamRelative ? 3 : 4
    readonly property real profileFuse: root.upstreamRelative ? 30 : 56

    readonly property bool horizontal: root.edgeName === "top" || root.edgeName === "bottom"
    readonly property real sourceT:
        Math.max(0, Math.min(1, root.envReal("ALIS_ABYSS_POC_SOURCE_T", 0.5)))
    readonly property real ownerThickness:
        Math.max(16, root.envReal("ALIS_ABYSS_POC_OWNER_THICKNESS", root.profileOwnerThickness))
    readonly property real popupWidth:
        Math.max(120, root.envReal("ALIS_ABYSS_POC_POPUP_WIDTH", root.profilePopupWidth))
    readonly property real popupHeight:
        Math.max(120, root.envReal("ALIS_ABYSS_POC_POPUP_HEIGHT", root.profilePopupHeight))
    readonly property real popupRadius:
        Math.max(0, root.envReal("ALIS_ABYSS_POC_POPUP_RADIUS", root.profilePopupRadius))
    readonly property real weld:
        Math.max(0, root.envReal("ALIS_ABYSS_POC_WELD", root.profileWeld))
    readonly property real fuse:
        Math.max(0, root.envReal("ALIS_ABYSS_POC_FUSE", root.profileFuse))
    readonly property real frameThickness:
        Math.max(1, root.envReal("ALIS_ABYSS_POC_FRAME_THICKNESS", 10))
    readonly property real tangentInset: Math.max(0, root.frameThickness - root.weld)
    readonly property bool showGuides:
        String(Quickshell.env("ALIS_ABYSS_POC_GUIDES") || "1") !== "0"

    // Component.onCompleted can fire before a layer-shell PanelWindow has its
    // final output geometry. G1 metadata must describe the pixels that grim
    // captures, so publish readiness only after full-output geometry has been
    // stable for several probes.
    property int readinessStableTicks: 0
    property real readinessLastWidth: -1
    property real readinessLastHeight: -1
    property bool readinessEmitted: false
    readonly property real readinessTolerance: 0.5
    readonly property bool outputGeometryReady: {
        const screenWidth = Number(root.screen?.width ?? 0)
        const screenHeight = Number(root.screen?.height ?? 0)
        return screenWidth > 0 && screenHeight > 0
            && root.width > 0 && root.height > 0
            && Math.abs(root.width - screenWidth) <= root.readinessTolerance
            && Math.abs(root.height - screenHeight) <= root.readinessTolerance
    }

    readonly property real semanticX: {
        if (root.edgeName === "left")
            return root.ownerThickness - root.weld
        if (root.edgeName === "right")
            return root.width - root.ownerThickness - root.popupWidth + root.weld
        const raw = root.sourceT * root.width - root.popupWidth / 2
        return Math.max(root.tangentInset,
            Math.min(root.width - root.popupWidth - root.tangentInset, raw))
    }
    readonly property real semanticY: {
        if (root.edgeName === "top")
            return root.ownerThickness - root.weld
        if (root.edgeName === "bottom")
            return root.height - root.ownerThickness - root.popupHeight + root.weld
        const raw = root.sourceT * root.height - root.popupHeight / 2
        return Math.max(root.tangentInset,
            Math.min(root.height - root.popupHeight - root.tangentInset, raw))
    }
    readonly property rect semanticPopup:
        Qt.rect(root.semanticX, root.semanticY, root.popupWidth, root.popupHeight)

    // Abyss Stage edge pieces grow only their field shape into the owner. Cards
    // such as Control Center instead use a small negative placement gap (weld).
    readonly property real edgeReach:
        Math.min(root.popupWidth, root.popupHeight) / 2 + 1
    readonly property rect fieldPopup: {
        let x = root.semanticPopup.x
        let y = root.semanticPopup.y
        let w = root.semanticPopup.width
        let h = root.semanticPopup.height
        if (root.geometryMode !== "edge-reach")
            return Qt.rect(x, y, w, h)
        if (root.edgeName === "top") {
            y -= root.edgeReach
            h += root.edgeReach
        } else if (root.edgeName === "bottom") {
            h += root.edgeReach
        } else if (root.edgeName === "left") {
            x -= root.edgeReach
            w += root.edgeReach
        } else {
            w += root.edgeReach
        }
        return Qt.rect(x, y, w, h)
    }

    readonly property var ownerShape: {
        const pad = root.fuse * 2
        if (root.edgeName === "top")
            return { x: -pad, y: 0, width: root.width + 2 * pad,
                height: root.ownerThickness, radius: 0, fuse: 0, id: "owner" }
        if (root.edgeName === "bottom")
            return { x: -pad, y: root.height - root.ownerThickness,
                width: root.width + 2 * pad, height: root.ownerThickness,
                radius: 0, fuse: 0, id: "owner" }
        if (root.edgeName === "left")
            return { x: 0, y: -pad, width: root.ownerThickness,
                height: root.height + 2 * pad, radius: 0, fuse: 0, id: "owner" }
        return { x: root.width - root.ownerThickness, y: -pad,
            width: root.ownerThickness, height: root.height + 2 * pad,
            radius: 0, fuse: 0, id: "owner" }
    }

    // The two tangent owners model Alis' physical Screen Edge at the clamp
    // extremes. They are ordinary field bodies, not corner helpers. A centered
    // popup joins only the primary owner; a clamped popup joins the primary
    // owner plus exactly one tangent Screen Edge through the QSB's second join.
    readonly property var frameStartShape: {
        const pad = root.fuse * 2
        return root.horizontal
            ? { x: 0, y: -pad, width: root.frameThickness,
                height: root.height + 2 * pad, radius: 0, fuse: 0,
                id: "frame-start" }
            : { x: -pad, y: 0, width: root.width + 2 * pad,
                height: root.frameThickness, radius: 0, fuse: 0,
                id: "frame-start" }
    }
    readonly property var frameEndShape: {
        const pad = root.fuse * 2
        return root.horizontal
            ? { x: root.width - root.frameThickness, y: -pad,
                width: root.frameThickness, height: root.height + 2 * pad,
                radius: 0, fuse: 0, id: "frame-end" }
            : { x: -pad, y: root.height - root.frameThickness,
                width: root.width + 2 * pad, height: root.frameThickness,
                radius: 0, fuse: 0, id: "frame-end" }
    }
    readonly property real joinEpsilon: 0.01
    readonly property bool atTangentStart: root.horizontal
        ? Math.abs(root.semanticPopup.x - root.tangentInset) <= root.joinEpsilon
        : Math.abs(root.semanticPopup.y - root.tangentInset) <= root.joinEpsilon
    readonly property bool atTangentEnd: root.horizontal
        ? Math.abs(root.semanticPopup.x + root.semanticPopup.width
            - (root.width - root.tangentInset)) <= root.joinEpsilon
        : Math.abs(root.semanticPopup.y + root.semanticPopup.height
            - (root.height - root.tangentInset)) <= root.joinEpsilon
    readonly property var popupJoins: {
        const joins = ["owner"]
        if (root.atTangentStart)
            joins.push("frame-start")
        else if (root.atTangentEnd)
            joins.push("frame-end")
        return joins
    }

    readonly property var popupShape: ({
        x: root.fieldPopup.x,
        y: root.fieldPopup.y,
        width: root.fieldPopup.width,
        height: root.fieldPopup.height,
        radius: root.popupRadius,
        fuse: root.fuse,
        id: "popup",
        joins: root.popupJoins
    })

    screen: root.targetScreen
    visible: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "alis:abyss-corner-poc"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
        id: emptyInput
        width: 0
        height: 0
        visible: false
    }
    mask: Region { item: emptyInput }

    AbyssCornerField {
        anchors.fill: parent
        shapes: [
            root.ownerShape,
            root.frameStartShape,
            root.frameEndShape,
            root.popupShape
        ]
        tint: "#f4c542"
        smoothing: root.fuse
    }

    // Diagnostic guides are not part of the field. They show the semantic
    // popup rect so hidden field overlap cannot be mistaken for content motion.
    Rectangle {
        visible: root.showGuides
        x: root.semanticPopup.x
        y: root.semanticPopup.y
        width: root.semanticPopup.width
        height: root.semanticPopup.height
        color: "transparent"
        border.width: 2
        border.color: "#57d3ff"
        radius: root.popupRadius
        z: 10
    }

    Rectangle {
        visible: root.showGuides
        color: "#ff4fd8"
        z: 11
        x: root.edgeName === "right" ? root.width - root.ownerThickness
            : root.edgeName === "left" ? root.ownerThickness - 1 : 0
        y: root.edgeName === "bottom" ? root.height - root.ownerThickness
            : root.edgeName === "top" ? root.ownerThickness - 1 : 0
        width: root.horizontal ? root.width : 1
        height: root.horizontal ? 1 : root.height
    }

    // Tangent Screen Edge seams. At sourceT 0.02/0.98 one of these becomes
    // the popup's second explicit join; at sourceT 0.50 both remain plain owners.
    Rectangle {
        visible: root.showGuides
        color: "#ff4fd8"
        z: 11
        x: root.horizontal ? root.frameThickness - 1 : 0
        y: root.horizontal ? 0 : root.frameThickness - 1
        width: root.horizontal ? 1 : root.width
        height: root.horizontal ? root.height : 1
    }
    Rectangle {
        visible: root.showGuides
        color: "#ff4fd8"
        z: 11
        x: root.horizontal ? root.width - root.frameThickness : 0
        y: root.horizontal ? 0 : root.height - root.frameThickness
        width: root.horizontal ? 1 : root.width
        height: root.horizontal ? root.height : 1
    }

    Text {
        visible: root.showGuides
        z: 12
        x: 18
        y: root.edgeName === "top" ? root.ownerThickness + 16 : 18
        color: "white"
        font.pixelSize: 16
        text: "Abyss v2.31 field · " + root.geometryMode
            + " · " + root.profileName
            + " · " + root.edgeName
            + " · fuse " + Math.round(root.fuse)
            + " · weld " + Math.round(root.weld)
    }

    // Keep the readiness payload plain-number JSON. The live capture harness
    // persists it beside each PNG and uses output-local geometry to make a
    // high-magnification junction crop without guessing compositor scale.
    function readinessPayload() {
        return {
            output: root.screen?.name ?? "",
            outputX: Number(root.screen?.x ?? 0),
            outputY: Number(root.screen?.y ?? 0),
            outputWidth: Number(root.width),
            outputHeight: Number(root.height),
            screenWidth: Number(root.screen?.width ?? 0),
            screenHeight: Number(root.screen?.height ?? 0),
            devicePixelRatio: Number(root.devicePixelRatio),
            mode: root.geometryMode,
            profile: root.profileName,
            edge: root.edgeName,
            sourceT: Number(root.sourceT),
            popupX: Number(root.semanticPopup.x),
            popupY: Number(root.semanticPopup.y),
            popupWidth: Number(root.semanticPopup.width),
            popupHeight: Number(root.semanticPopup.height),
            ownerThickness: Number(root.ownerThickness),
            frameThickness: Number(root.frameThickness),
            joins: root.popupJoins,
            atTangentStart: root.atTangentStart,
            atTangentEnd: root.atTangentEnd,
            radius: Number(root.popupRadius),
            fuse: Number(root.fuse),
            weld: Number(root.weld),
            reach: Number(root.edgeReach),
            geometryStable: root.outputGeometryReady,
            readinessStableTicks: root.readinessStableTicks
        }
    }

    function probeReadiness() {
        if (root.readinessEmitted)
            return

        const widthNow = Number(root.width)
        const heightNow = Number(root.height)
        if (!root.outputGeometryReady) {
            root.readinessStableTicks = 0
            root.readinessLastWidth = widthNow
            root.readinessLastHeight = heightNow
            return
        }

        const unchanged = Math.abs(widthNow - root.readinessLastWidth)
                <= root.readinessTolerance
            && Math.abs(heightNow - root.readinessLastHeight)
                <= root.readinessTolerance
        root.readinessStableTicks = unchanged ? root.readinessStableTicks + 1 : 1
        root.readinessLastWidth = widthNow
        root.readinessLastHeight = heightNow

        if (root.readinessStableTicks < 3)
            return

        root.readinessEmitted = true
        console.info("ALIS_ABYSS_POC", JSON.stringify(root.readinessPayload()))
        readinessTimer.stop()
    }

    Timer {
        id: readinessTimer
        interval: 50
        repeat: true
        running: true
        onTriggered: root.probeReadiness()
    }
}
