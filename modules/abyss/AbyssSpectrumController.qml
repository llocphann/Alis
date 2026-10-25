pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

// One lease per participating output; CavaProcess shares one analyzer process.
// The spectrum drives the existing field texture and adds no drawing layer.
Item {
    id: root
    required property var waves
    property string outputName: ""
    property string barEdge: "top"
    property bool presented: true
    property bool playing: MprisController.isPlaying || YtMusic.isPlaying
    property var audioSource: null
    property real phase: 0
    property double lastFrameMs: 0
    readonly property var source: audioSource ?? cava
    readonly property var options: Config.options?.abyss?.spectrum
    readonly property bool configured: options?.configured ?? false
    readonly property bool spectrumEnabled: configured ? (options?.enabled ?? false) : (Config.options?.bar?.visualizer?.enable ?? false)
    readonly property real strength: Math.max(0,Math.min(4,options?.strength ?? .45))
    readonly property bool outputEnabled: (configured ? options?.multiMonitorMode : Config.options?.bar?.visualizer?.multiMonitorMode) === "all"
        || Quickshell.screens.length<=1 || outputName===(GlobalStates.primaryScreen?.name ?? Quickshell.screens[0]?.name ?? "")
    readonly property var edges: options?.edge === "all" ? ["top","right","bottom","left"]
        : [(["top","right","bottom","left"].includes(options?.edge) ? options.edge : barEdge)]
    readonly property bool wanted: spectrumEnabled && outputEnabled && presented && playing && strength>0
        && AbyssStyle.motionEnabled && !Appearance.gameModeMinimal
    readonly property bool held: cava.held
    Binding { target:root.waves;property:"audioEnabled";value:root.wanted }
    CavaProcess { id:cava;active:root.wanted && !root.audioSource;sampleCount:64 }
    function refreshSpectrum(frame = false): void {
        if(!waves || !source) return
        if(!wanted || !source.audioSignalActive) { lastFrameMs=0;waves.clearSpectrum();return }
        if(frame) lastFrameMs=Date.now()
        waves.feedSpectrum(edges,source.points,source.normalizationCeiling,strength,0)
    }
    Connections {
        target:root.source
        enabled:root.wanted
        ignoreUnknownSignals:true
        function onPointsChanged(): void { if(!root.source?.completeFrameClock) root.refreshSpectrum(true) }
        function onFramePublished(): void { root.refreshSpectrum(true) }
        function onAudioSignalActiveChanged(): void { root.refreshSpectrum() }
    }
    Connections {
        target:root.waves
        function onConfigurationChanged(): void { root.refreshSpectrum() }
        function onAudioAllowedChanged(): void { root.refreshSpectrum() }
    }
    onWantedChanged: refreshSpectrum()
    onSourceChanged: refreshSpectrum()
    onEdgesChanged: refreshSpectrum()
    onStrengthChanged: refreshSpectrum()
    Component.onCompleted: refreshSpectrum()
}
