import QtQuick
import Quickshell
import qs.services
import "looks/AbyssWave.js" as Wave

// Only host handles and finite presentation outputs cross the optional API.
Item {
    id: root
    required property var host
    required property var hostLiquid
    required property var hostField
    required property var hostBar
    required property var hostLeftPanel
    required property var hostRightPanel
    required property var hostCorners
    required property var hostUtility
    required property var hostBarHover
    required property var hostRevealHover
    readonly property Item overlayParent: parent || root
    readonly property var waveFunctions: Wave
    readonly property var session: AlisCompanion.session
    readonly property string outputName: host.outputName
    readonly property var extension: outputLoader.status === Loader.Ready ? outputLoader.item : null
    readonly property bool editing: extension?.editing ?? false
    readonly property bool popupOpen: extension?.popupOpen ?? false
    readonly property bool motionBusy: extension?.motionBusy ?? false
    readonly property bool keyboardFocusOnDemand: extension?.keyboardFocusOnDemand ?? false
    readonly property bool curiosityOwned: extension?.curiosityOwned ?? false
    readonly property bool utilitiesVisitActive: extension?.utilitiesVisitActive ?? false
    readonly property bool dockHeld: extension?.dockHeld ?? false
    readonly property var waterLink: extension?.waterLink ?? null
    readonly property var talkCloudItem: extension?.talkCloudItem ?? null
    readonly property var pocketPaneItem: extension?.pocketPaneItem ?? null
    readonly property var inputRegions: extension?.inputRegions ?? []
    property var obstacleRects: []
    readonly property var _pocketObstacleItem: extension?.pocketPaneItem ?? null
    readonly property var _talkObstacleItem: (extension && (extension.talkCloudHovered || extension.editing))
        ? (extension.talkCloudItem ?? null) : null
    readonly property string _obstacleGeometryKey: {
        const parts = []
        for (const it of [root._pocketObstacleItem, root._talkObstacleItem]) {
            if (!it || !it.visible || it.width <= 0 || it.height <= 0 || (it.opacity ?? 1) <= 0.05) {
                parts.push("0")
                continue
            }
            parts.push([
                Math.round(Number(it.x) || 0),
                Math.round(Number(it.y) || 0),
                Math.round(Number(it.width) || 0),
                Math.round(Number(it.height) || 0)
            ].join(","))
        }
        return parts.join("|")
    }
    function _syncObstacleRects(): void {
        const ext = root.extension
        const out = []
        if (ext) {
            for (const it of [root._pocketObstacleItem, root._talkObstacleItem]) {
                if (!it || !it.visible || it.width <= 0 || it.height <= 0 || (it.opacity ?? 1) <= 0.05)
                    continue
                const pt = it.mapToItem(root, 0, 0)
                if (Number.isFinite(pt.x) && Number.isFinite(pt.y)) {
                    out.push({
                        x: Math.round(pt.x),
                        y: Math.round(pt.y),
                        width: Math.round(it.width),
                        height: Math.round(it.height)
                    })
                }
            }
        }
        const cur = root.obstacleRects
        if (cur.length === out.length && cur.every((r, i) =>
                r.x === out[i].x && r.y === out[i].y
                && r.width === out[i].width && r.height === out[i].height)) {
            return
        }
        root.obstacleRects = out
    }
    on_ObstacleGeometryKeyChanged: Qt.callLater(root._syncObstacleRects)
    onExtensionChanged: Qt.callLater(root._syncObstacleRects)
    function yieldToUser(): void {if(extension) extension.yieldToUser()}
    function handleEscape(): bool { return extension && typeof extension.handleEscape === "function" ? Boolean(extension.handleEscape()) : false }
    function requestCompanionChat(): void {if(extension) extension.requestCompanionChat()}
    function resetCompanionCast(): void {if(extension) extension.resetCompanionCast()}
    // An inactive output is different from a ready Companion session. Keep
    // the bounded Loader state inspectable over IPC instead of returning only
    // {active:false}, which hides early-activation and QML load failures.
    function companionStatus() {
        if (extension) return extension.status()
        const state=outputLoader.status===Loader.Null ? "null"
            : outputLoader.status===Loader.Loading ? "loading"
            : outputLoader.status===Loader.Error ? "error" : "ready"
        return {output:outputName,active:false,
            loader:{state:state,active:outputLoader.active,
                sourceSet:String(outputLoader.source).length>0,
                sessionReady:root.session!==null}}
    }
    Loader {
        id: outputLoader
        anchors.fill: parent
        active: root.session !== null
        // The output window may be instantiated after the shared session has
        // already reached Ready. In that case active starts true and
        // onActiveChanged need not run: setSource must also be initialized at
        // component completion, preserving the required adapter property.
        function ensureOutputSource(): void {
            if (active && status===Loader.Null && String(source).length===0
                    && AlisCompanion.outputSource.length>0)
                setSource(AlisCompanion.outputSource,{adapter:root})
        }
        onStatusChanged: if (status===Loader.Error) {
            console.warn("[Alis-Companion] QML output loader failed:",root.outputName,
                "source:",String(source))
            AlisCompanion.failLoad()
        }
        onActiveChanged: {
            if (active) ensureOutputSource()
            else source=""
        }
        Component.onCompleted: ensureOutputSource()
    }
    Component.onCompleted: AlisCompanion.registerOutput(root)
    Component.onDestruction: AlisCompanion.unregisterOutput(root)
}
