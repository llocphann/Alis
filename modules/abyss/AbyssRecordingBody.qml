pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import "looks/AbyssGeometry.js" as Geometry

// Recording participates in the existing allocator, field and input mask.
// Its small hidden recovery target retains auto-hide without an idle window.
AbyssBodyHost {
    id: root
    property bool available: true
    property bool enabledPanel: true
    property bool targetOutput: true
    property var recordingStatus: RecorderStatus
    property var audioService: Audio
    property var stopAction: null
    property real alongCenter: -1
    property bool dragging: false
    property point dragOrigin: Qt.point(0,0)
    readonly property var recorder: contentItem.item?.recorder ?? null
    readonly property bool recording: root.recordingStatus.isRecording && root.targetOutput && root.enabledPanel
    readonly property bool recoverable: root.available && root.recording && !GlobalStates.screenLocked
        && (root.recorder?.autoHide ?? false) && !(root.recorder?.revealed ?? true)
    identity: "recording"
    edge: "top"
    padding: 10
    placementCanResize: false
    stableContentSize: true
    // Preserve the already-rendered Recording UI during its retract and let
    // the one-shot warm expiry release it after notification reveal settles.
    // It remains non-interactive immediately after recording ends.
    warmContent: true
    residentContent: root.recording
    includeEdgeConnection: true
    animatePlacementChanges: !root.dragging
    open: root.available && root.recording && !GlobalStates.screenLocked
        && (root.recorder?.revealed ?? false)
    span: (Geometry.horizontal(edge) ? (contentItem.item?.desiredWidth ?? 200)
        : (contentItem.item?.desiredHeight ?? 200))+padding*2
    depth: (Geometry.horizontal(edge) ? (contentItem.item?.desiredHeight ?? 30)
        : (contentItem.item?.desiredWidth ?? 30))+padding*2
    along: (alongCenter < 0 ? (Geometry.horizontal(edge) ? width : height)/2 : alongCenter)-span/2
    source: "content/AbyssRecordingContent.qml"
    function beginDrag(): void {
        const rect = root.targetRecord.content
        root.dragOrigin = Qt.point(rect.x+rect.width/2,rect.y+rect.height/2)
        root.dragging = true
    }
    function moveDrag(translation): void {
        if (!root.dragging) return
        const horizontal = Geometry.horizontal(root.edge)
        root.alongCenter = Math.max(0,Math.min(horizontal ? root.width : root.height,
            horizontal ? root.dragOrigin.x+translation.x : root.dragOrigin.y+translation.y))
    }
    function finishDrag(translation): void {
        if (!root.dragging) return
        const cx = Math.max(0,Math.min(root.width,root.dragOrigin.x+translation.x))
        const cy = Math.max(0,Math.min(root.height,root.dragOrigin.y+translation.y))
        const distances = [cy,root.width-cx,root.height-cy,cx]
        root.edge = ["top","right","bottom","left"][distances.indexOf(Math.min(...distances))]
        root.alongCenter = Geometry.horizontal(root.edge) ? cx : cy
        root.dragging = false
    }
    Connections {
        target: root.recordingStatus
        function onIsRecordingChanged(): void {
            if (root.recordingStatus.isRecording) { root.edge="top"; root.alongCenter=-1 }
            else root.dragging=false
        }
    }
    HoverHandler {
        id: bodyHover
        parent: root.hoverParent
        enabled: root.open
    }
    Binding {
        target: root.recorder
        property: "connectionHovered"
        value: bodyHover.hovered || wakeHover.hovered || root.dragging
        when: root.recorder !== null
    }
    Item {
        id: wakeTarget
        visible: root.recoverable
        readonly property real center: Geometry.horizontal(root.edge)
            ? root.targetRecord.content.x+root.targetRecord.content.width/2
            : root.targetRecord.content.y+root.targetRecord.content.height/2
        x: Geometry.horizontal(root.edge) ? center-18 : root.edge==="left" ? 0 : root.width-12
        y: Geometry.horizontal(root.edge) ? (root.edge==="top" ? 0 : root.height-12) : center-18
        width: Geometry.horizontal(root.edge) ? 36 : 12
        height: Geometry.horizontal(root.edge) ? 12 : 36
        readonly property Region inputRegion: Region {
            x: Math.floor(wakeTarget.x); y: Math.floor(wakeTarget.y)
            width: root.recoverable ? Math.ceil(wakeTarget.x+wakeTarget.width)-x : 0
            height: root.recoverable ? Math.ceil(wakeTarget.y+wakeTarget.height)-y : 0
        }
        HoverHandler { id: wakeHover; enabled: root.recoverable }
        AbyssParticipant {
            identity: "recordingWake"
            controller: root.controller
            inputBounds: root.recoverable ? Qt.rect(wakeTarget.x,wakeTarget.y,wakeTarget.width,wakeTarget.height) : Qt.rect(0,0,0,0)
            nativeInputRegion: root.recoverable ? wakeTarget.inputRegion : null
        }
    }
}
