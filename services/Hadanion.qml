pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import "CompanionContextPolicy.js" as ContextPolicy

// Host API v1. The external package is never imported by the core shell.
Singleton {
    id: root
    property bool available: false
    property string version: ""
    property string diagnostic: "not-installed"
    property string packageRoot: ""
    property string sourceSha: ""
    property bool loadFailed: false
    property var outputs: []
    readonly property bool enabled: available && !loadFailed && Config.ready
        && Config.options?.panelFamily === "abyss"
        && Config.options?.abyss?.companion?.enabled === true
    readonly property var session: sessionLoader.status === Loader.Ready ? sessionLoader.item : null
    readonly property int contextApiVersion:1
    readonly property bool contextAvailable: root.enabled && root.session?.companionSessionVisible===true
        && Config.options?.abyss?.companion?.contextEnabled===true
        && (Config.options?.abyss?.companion?.contextFocusEnabled===true
            || Config.options?.abyss?.companion?.contextAiEnabled===true)
        && !GlobalStates.screenLocked && !Appearance.gameModeMinimal
        && !GameMode.hasFullscreenOnOutput(root.session?.companionTargetOutput ?? "")
        && !Notifications.notificationPolicyActive
    readonly property var contextSource: contextAvailable ? contextFeed : null
    readonly property string sessionSource: packageRoot + "/HadalisSession.qml"
    readonly property string outputSource: packageRoot + "/HadalisOutput.qml"
    readonly property string settingsSource: available ? packageRoot + "/modules/settings/CompanionConfig.qml" : ""

    function registerOutput(output): void {
        if (!outputs.includes(output)) outputs=outputs.concat([output])
    }
    function unregisterOutput(output): void { outputs=outputs.filter(item=>item!==output) }
    function refresh(): void {
        if (probe.running) return
        available=false
        loadFailed=false
        probe.running=true
    }
    function failLoad(): void {loadFailed=true;diagnostic="load-failed"}
    CompanionContext {
        id:contextFeed
        owner:root.session
        permitted:root.contextAvailable
        shareFocus:permitted && Config.options?.abyss?.companion?.contextFocusEnabled===true
        shareAi:permitted && Config.options?.abyss?.companion?.contextAiEnabled===true
        category:shareFocus ? ContextPolicy.category(ToplevelManager.activeToplevel?.appId ?? "") : "none"
        aiBusy:shareAi && Ai.busy
        aiWaiting:shareAi && Ai.waitingForApproval
    }
    Connections {
        target:contextFeed.shareAi ? Ai : null
        function onResponseFinished(): void {if(!Ai.waitingForApproval)contextFeed.finished()}
    }
    function chat(): void { if (session) session.chat() }
    function pocket(): void { if (session?.pocket) session.pocket() }
    function prop(kind): void { if (session?.previewProp) session.previewProp(kind) }
    function status(): string {
        if (session) return JSON.stringify(Object.assign(
            {available:available,version:version,sourceSha:sourceSha,diagnostic:diagnostic},
            JSON.parse(session.status())))
        return JSON.stringify({available:available,version:version,enabled:enabled,
            sourceSha:sourceSha,sessionVisible:false,diagnostic:diagnostic,backend:{ready:false},outputs:[]})
    }
    Loader {
        id: sessionLoader
        active: root.enabled
        onStatusChanged: if(status===Loader.Error) root.failLoad()
        onActiveChanged: {
            if (active) setSource(root.sessionSource,{host:root})
            else source=""
        }
    }
    Process {
        id: probe
        command: ["/usr/bin/python3",Quickshell.shellPath("scripts/hadanion-status.py"),Quickshell.shellPath("")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result=JSON.parse(text)
                    root.packageRoot=String(result.root ?? "")
                    root.sourceSha=String(result.sourceSha ?? "")
                    root.available=result.available===true
                    root.version=String(result.version ?? "")
                    root.diagnostic=String(result.diagnostic ?? "not-installed")
                } catch (_error) {root.available=false;root.diagnostic="invalid-package"}
            }
        }
    }
    // Preserve the existing keybind and command without requiring the package.
    IpcHandler {
        target: "wull"
        function chat(): void {root.chat()}
        function pocket(): void {root.pocket()}
        function prop(kind: string): void {root.prop(kind)}
        function previewProp(kind: string): void {root.prop(kind)}
        function status(): string {return root.status()}
    }
    IpcHandler {
        target: "hadanion"
        function refresh(): void {root.refresh()}
        function pocket(): void {root.pocket()}
        function prop(kind: string): void {root.prop(kind)}
        function previewProp(kind: string): void {root.prop(kind)}
        function status(): string {return root.status()}
    }
    Component.onCompleted: root.refresh()
}
