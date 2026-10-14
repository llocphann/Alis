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
    readonly property var session: Hadanion.session
    readonly property string outputName: host.outputName
    readonly property var extension: outputLoader.status === Loader.Ready ? outputLoader.item : null
    readonly property bool editing: extension?.editing ?? false
    readonly property bool curiosityOwned: extension?.curiosityOwned ?? false
    readonly property bool utilitiesVisitActive: extension?.utilitiesVisitActive ?? false
    readonly property bool dockHeld: extension?.dockHeld ?? false
    readonly property var waterLink: extension?.waterLink ?? null
    readonly property var inputRegions: extension?.inputRegions ?? []
    function yieldToUser(): void {if(extension) extension.yieldToUser()}
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
                    && Hadanion.outputSource.length>0)
                setSource(Hadanion.outputSource,{adapter:root})
        }
        onStatusChanged: if (status===Loader.Error) {
            console.warn("[Hadanion] QML output loader failed:",root.outputName,
                "source:",String(source))
            Hadanion.failLoad()
        }
        onActiveChanged: {
            if (active) ensureOutputSource()
            else source=""
        }
        Component.onCompleted: ensureOutputSource()
    }
    Component.onCompleted: Hadanion.registerOutput(root)
    Component.onDestruction: Hadanion.unregisterOutput(root)
}
