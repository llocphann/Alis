import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.looks
import "looks/AbyssWave.js" as Wave

Item {
    id: root
    width: sampleCount; height: 1
    property real outputWidth: 1920
    property real outputHeight: 1080
    property bool presented: true
    property var records: []
    readonly property int sampleCount: AbyssStyle.quality === "performance" ? 128 : 256
    readonly property var parameters: Wave.parameters(Config.options?.abyss?.waves)
    property var simulation: null
    property var massKernels: new Map()
    property string mode: "SLEEPING"
    property int revision: 0
    property real crestPeak: 0
    property real _paintedCrestPeak: 0
    property real _prevPaintedCrestPeak: 0
    property real lastStep: 0
    readonly property bool running: ticker.running
    readonly property var texture: textureSource
    property bool wavesEnabled: Config.options?.abyss?.waves?.enabled ?? false
    property bool audioEnabled: false
    property bool idleDisturbance: false
    property int idlePoint: 0
    readonly property bool motionAllowed: presented && AbyssStyle.motionEnabled && wavesEnabled
        && !AbyssRenderPolicy.powerSaver && !GameMode.active && !GlobalStates.screenLocked
        && !RecorderStatus.isRecording
    readonly property bool audioAllowed: presented && AbyssStyle.motionEnabled && audioEnabled
    readonly property bool integrationAllowed: motionAllowed || audioAllowed
    signal configurationChanged()
    function reset(): void {
        massKernels = new Map()
        simulation = Wave.create(sampleCount,outputWidth,outputHeight,parameters)
        // Disarm the shader synchronously; a hidden/offscreen Canvas may not
        // produce another paint after its last animation clock has stopped.
        crestPeak = 0
        _paintedCrestPeak = 0
        _prevPaintedCrestPeak = 0
        // A disabled wave solver never consumes mass. The output field still
        // animates while Waves is off, so recalculating up to 256 mass samples
        // on every Recording/Notification geometry frame was wasted CPU work.
        // Resynchronize before the first enabled impulse/spectrum frame.
        if (integrationAllowed)
            Wave.setMassCached(simulation,records,massKernels)
        mode = "SLEEPING"
        revision++
        configurationChanged()
    }
    function impulse(edge, along, span, strength, mass = 1, channel = "module"): void {
        if (!motionAllowed || strength === 0) return
        if (!simulation) reset()
        const factor = channel === "module" ? (Math.abs(strength)<0.5 ? parameters.hover : parameters.press)
            : (parameters[channel] ?? 1)
        Wave.impulse(simulation,edge,along,span,strength*factor*AbyssStyle.motionIntensity,mass)
        if(channel === "open" || channel === "close")
            Wave.travel(simulation,edge,along,span,strength*factor*AbyssStyle.motionIntensity,mass)
        idleDisturbance = channel === "idle"
        lastStep = Date.now()
        mode = simulation.mode
        revision++
    }
    function feedSpectrum(edges,points,ceiling,strength,phase = 0): void {
        if(!audioAllowed) return
        if(!simulation) reset()
        if(!Wave.spectrum(simulation,edges,points,ceiling,strength*AbyssStyle.motionIntensity,phase)) return
        idleDisturbance=false
        revision++
    }
    function clearSpectrum(): void {
        if(!simulation || !simulation.hasSpectrum) return
        if(!integrationAllowed) { reset();return }
        if(Wave.spectrum(simulation,[],[],100,0)) {
            crestPeak=Wave.projectCrests(simulation,Appearance.effectsEnabled && AbyssStyle.quality !== "performance")
            revision++
        }
    }
    onAudioAllowedChanged: if(!audioAllowed) clearSpectrum()
    onMotionAllowedChanged: if(!motionAllowed && simulation) Wave.clearTravel(simulation)
    onIntegrationAllowedChanged: {
        if (!integrationAllowed)
            reset()
        else if (simulation)
            Wave.setMassCached(simulation,records,massKernels)
    }
    onOutputWidthChanged: reset()
    onOutputHeightChanged: reset()
    onSampleCountChanged: reset()
    onParametersChanged: {
        if (simulation) {
            simulation.parameters = parameters
            if(!parameters.popupTravel) Wave.clearTravel(simulation)
        }
        configurationChanged()
    }
    onRecordsChanged: if (simulation && integrationAllowed)
        Wave.setMassCached(simulation,records,massKernels)
    onRevisionChanged: samples.requestPaint()
    Component.onCompleted: reset()
    Timer {
        id: ticker
        interval: root.idleDisturbance ? 100 : AbyssStyle.quality === "performance" ? 33 : 16
        repeat: true
        running: root.integrationAllowed && root.mode !== "SLEEPING"
        onTriggered: {
            const now = Date.now()
            Wave.advance(root.simulation,Math.min(.05,(now-root.lastStep)/1000))
            root.lastStep = now
            root.mode = root.simulation.mode
            root.revision++
        }
    }
    Timer {
        interval: 8000;repeat:true
        running: root.motionAllowed && root.parameters.idle
        onTriggered: if (root.mode === "SLEEPING") {
            root.idlePoint = (root.idlePoint+1)%7
            root.impulse("top",root.outputWidth*(root.idlePoint+.5)/7,120,.04,1,"idle")
        }
    }
    // One tiny, explicitly updated texture; no desktop capture or time uniform.
    Canvas {
        id: samples
        width: root.sampleCount; height: 1
        renderTarget: Canvas.Image
        onAvailableChanged: if (available) requestPaint()
        onPainted: {
            root._prevPaintedCrestPeak = root._paintedCrestPeak
            root._paintedCrestPeak = root.crestPeak
            textureSource.scheduleUpdate()
        }
        onPaint: {
            if (!root.simulation || width <= 0) return
            root.crestPeak = Wave.projectCrests(root.simulation,Appearance.effectsEnabled && AbyssStyle.quality !== "performance")
            const ctx = getContext("2d")
            if (root.crestPeak <= 0) {
                ctx.fillStyle = "#000000"
                ctx.fillRect(0, 0, width, 1)
                return
            }
            // Run-length batch opaque fillRect spans so flat perimeter segments
            // collapse into single draw calls while keeping alpha=255 pixels.
            const crests = root.simulation.crests
            const whitewater = root.simulation.whitewater
            const inv256 = 65535 / 256
            let runStart = 0
            let runRgb = -1
            for (let i = 0; i < width; i++) {
                const value = Math.round(crests[i] * inv256)
                const foam = Math.round(whitewater[i] * 255)
                const rgb = ((value & 65535) << 8) | (foam & 255)
                if (rgb !== runRgb) {
                    if (runRgb >= 0) {
                        ctx.fillStyle = runRgb === 0
                            ? "#000000"
                            : "rgb(" + ((runRgb >> 16) & 255) + "," + ((runRgb >> 8) & 255) + "," + (runRgb & 255) + ")"
                        ctx.fillRect(runStart, 0, i - runStart, 1)
                    }
                    runStart = i
                    runRgb = rgb
                }
            }
            if (runRgb >= 0) {
                ctx.fillStyle = runRgb === 0
                    ? "#000000"
                    : "rgb(" + ((runRgb >> 16) & 255) + "," + ((runRgb >> 8) & 255) + "," + (runRgb & 255) + ")"
                ctx.fillRect(runStart, 0, width - runStart, 1)
            }
        }
    }
    ShaderEffectSource {
        id: textureSource
        // RG16 encodes height / 256; filtered Hermite sampling is monotone.
        readonly property real encodedHeightCeiling: 256
        // Tight upper bound on active crest height so AbyssField.vert only
        // shrinks its skipped transparent interior by the real wave height.
        // Keep a 1-frame high-water mark across GPU texture uploads so decay
        // or clearSpectrum() can never clip a crest still in textureSource.
        readonly property real _effectivePeak: Math.max(root.crestPeak, root._paintedCrestPeak, root._prevPaintedCrestPeak)
        readonly property real activePeakHeight: _effectivePeak > 0.01 ? Math.min(256, Math.ceil(_effectivePeak) + 2) : 0
        readonly property bool activeProfile: root.crestPeak > .01
        width: samples.width; height: samples.height
        x: -width; y: -height
        sourceItem: samples
        hideSource: true
        live: false
        smooth: true
        textureSize: Qt.size(root.sampleCount,1)
    }
}
