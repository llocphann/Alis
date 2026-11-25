import QtQuick
import QtQuick.Window
import qs.modules.common
import qs.services
import "AbyssGeometry.js" as Geometry

Item {
    id: root
    property string outputName: ""
    property real renderScale: 1
    readonly property bool wantsWallpaper: AbyssStyle.blurRadius > 0 || AbyssStyle.contentBlurRadius > 0 || AbyssStyle.refractionStrength > 0
    // Reuse the stable wallpaper-backdrop resolver. It is output-aware and gives
    // Image a safe still URL for video wallpapers instead of dropping to gray.
    readonly property string wallpaperUrl: wantsWallpaper
        ? WallpaperListener.wallpaperUrlForScreen(root.Window.window?.screen ?? null) : ""
    readonly property bool wallpaperReady: wallpaperImage.status === Image.Ready
    property var records: []
    // Opt in only from the owned full-screen perimeter; arbitrary callers retain
    // the full shader and its original observable reads.
    property bool boundInterior: false
    property var waveTexture: null
    property var waterLink: null
    property var edgeInsets: ({left:8,top:8,right:8,bottom:8})
    property var roundZeroCorners: ({})
    // Configured Edge widths, not module-expanded paint insets, own 0px choices.
    // Default retains the geometry-only fixture contract.
    property var cornerWidthInsets: root.edgeInsets
    readonly property var physicalContactEdges: Geometry.physicalContactMask(
        root.cornerWidthInsets ?? root.edgeInsets,root.roundZeroCorners)
    readonly property int capacity: 40
    // Qt's QSB reflection cache can render a recreated effect while its new
    // manager still reports Uncompiled. Gate input on a presented frame and
    // supported backend instead; malformed packages still report Error.
    property bool framePresented: false
    readonly property bool ready: framePresented && GraphicsInfo.api !== GraphicsInfo.Software
        && GraphicsInfo.api !== GraphicsInfo.Null && pass.status !== ShaderEffect.Error
    Window.onWindowChanged: root.framePresented = false
    Connections {
        target: root.Window.window
        enabled: !root.framePresented
        function onFrameSwapped(): void { root.framePresented = true }
    }
    readonly property string diagnostic: pass.log
    readonly property Component immersionComponent:Component {
        AbyssFieldImmersion {sourcePass:pass}
    }
    readonly property vector4d _zeroRect: Qt.vector4d(0,0,0,0)
    property int _prevRecordCount: 0
    function _syncRecordUniforms(): void {
        const recs = root.records ?? []
        const n = Math.min(recs.length, 40)
        const limit = Math.max(n, root._prevRecordCount)
        const defaultR = AbyssStyle.neckRadius
        for (let i = 0; i < limit; ++i) {
            const r = i < n ? recs[i]?.surface : null
            const v = r ? Qt.vector4d(r.x, r.y, r.width, r.height) : root._zeroRect
            const prop = "rect" + i
            if (pass[prop] !== v)
                pass[prop] = v
        }
        const groups = Math.ceil(limit / 4)
        for (let g = 0; g < groups; ++g) {
            const base = g * 4
            const r0 = base < n ? (recs[base]?.radius ?? defaultR) : defaultR
            const r1 = (base + 1) < n ? (recs[base + 1]?.radius ?? defaultR) : defaultR
            const r2 = (base + 2) < n ? (recs[base + 2]?.radius ?? defaultR) : defaultR
            const r3 = (base + 3) < n ? (recs[base + 3]?.radius ?? defaultR) : defaultR
            const rv = Qt.vector4d(r0, r1, r2, r3)
            const rprop = "radii" + g
            if (pass[rprop] !== rv)
                pass[rprop] = rv
        }
        root._prevRecordCount = n
    }
    onRecordsChanged: root._syncRecordUniforms()
    Connections {
        target: AbyssStyle
        function onNeckRadiusChanged(): void {
            root._prevRecordCount = 40
            root._syncRecordUniforms()
        }
    }
    Component.onCompleted: {
        root._prevRecordCount = 40
        root._syncRecordUniforms()
    }
    function packed(index) {
        const r = root.records[index]?.surface
        return r ? Qt.vector4d(r.x,r.y,r.width,r.height) : Qt.vector4d(0,0,0,0)
    }
    function packedRadii(group) {
        const first=group*4
        const radius=i=>root.records[i]?.radius ?? AbyssStyle.neckRadius
        return Qt.vector4d(radius(first),radius(first+1),radius(first+2),radius(first+3))
    }
    // Static texture provider; no offscreen pass or live screen capture.
    // cache: false stops QPixmapCache from pinning replaced 2K/4K wallpapers in RAM.
    Image {
        id: wallpaperImage
        visible: false
        asynchronous: true
        cache: false
        source: root.wallpaperUrl
        sourceSize.width: Math.min(2048,Math.ceil(root.width*root.renderScale))
        smooth: true
    }
    ShaderEffect {
        id: pass
        anchors.fill: parent
        vertexShader: Qt.resolvedUrl("AbyssField.vert.qsb")
        fragmentShader: Qt.resolvedUrl("AbyssField.frag.qsb")
        readonly property vector4d viewport: Qt.vector4d(root.width,root.height,0,0)
        readonly property vector4d renderRect:Qt.vector4d(0,0,root.width,root.height)
        readonly property real maskOnly:0
        readonly property real interiorEnabled: root.boundInterior && root.renderScale>=.5 ? 1 : 0
        readonly property var bodyTexture:wallpaperImage
        readonly property vector4d insets: Qt.vector4d(root.edgeInsets.left,root.edgeInsets.top,root.edgeInsets.right,root.edgeInsets.bottom)
        readonly property vector4d zeroCorners: {
            const flags=Geometry.zeroCornerMask(root.cornerWidthInsets ?? root.edgeInsets,root.roundZeroCorners)
            return Qt.vector4d(flags[0]?1:0,flags[1]?1:0,flags[2]?1:0,flags[3]?1:0)
        }
        readonly property vector4d contactEdges: {
            const flags=root.physicalContactEdges
            return Qt.vector4d(flags[0]?1:0,flags[1]?1:0,flags[2]?1:0,flags[3]?1:0)
        }
        readonly property vector4d material: Qt.vector4d(AbyssStyle.perimeterRadius,AbyssStyle.connectionDepth,AbyssStyle.neckRadius,AbyssStyle.highlightStrength)
        readonly property vector4d liquidContact: root.waterLink?.contact ?? Qt.vector4d(0,0,0,0)
        readonly property vector4d liquidContactNormal: root.waterLink?.contactNormal ?? Qt.vector4d(0,0,0,0)
        readonly property vector4d liquidRipple: root.waterLink?.ripple ?? Qt.vector4d(0,0,1,0)
        readonly property vector4d liquidRippleNormal: root.waterLink?.rippleNormal ?? Qt.vector4d(0,0,0,0)
        readonly property var wallpaper: wallpaperImage
        readonly property var waveSamples: root.waveTexture
        readonly property vector4d waveMaterial: Qt.vector4d(root.waveTexture?.width ?? 0,
            root.waveTexture?.activeProfile ? 1 : 0,Appearance.effectsEnabled ? 1 : 0,
            root.boundInterior ? (root.waveTexture?.activePeakHeight ?? root.waveTexture?.encodedHeightCeiling ?? 0) : 0)
        readonly property vector4d effects: Qt.vector4d(AbyssStyle.blurRadius,AbyssStyle.refractionStrength,root.wallpaperReady ? 1 : 0,0)
        readonly property vector4d contentMaterial: Qt.vector4d(AbyssStyle.contentOpacity,AbyssStyle.contentBlurRadius,0,0)
        readonly property vector4d wallpaperCrop: {
            const imageAspect = wallpaperImage.implicitWidth/Math.max(1,wallpaperImage.implicitHeight)
            const viewAspect = root.width/Math.max(1,root.height)
            const xScale = Math.min(1,viewAspect/Math.max(0.001,imageAspect))
            const yScale = Math.min(1,imageAspect/Math.max(0.001,viewAspect))
            return Qt.vector4d((1-xScale)/2,(1-yScale)/2,xScale,yScale)
        }
        readonly property color surface: AbyssStyle.surface
        readonly property color raised: AbyssStyle.surfaceRaised
        readonly property color rim: AbyssStyle.specular
        readonly property color shadow: AbyssStyle.shadow
        readonly property color glow: AbyssStyle.glow
        property vector4d radii0: Qt.vector4d(29,29,29,29)
        property vector4d radii1: Qt.vector4d(29,29,29,29)
        property vector4d radii2: Qt.vector4d(29,29,29,29)
        property vector4d radii3: Qt.vector4d(29,29,29,29)
        property vector4d radii4: Qt.vector4d(29,29,29,29)
        property vector4d radii5: Qt.vector4d(29,29,29,29)
        property vector4d radii6: Qt.vector4d(29,29,29,29)
        property vector4d radii7: Qt.vector4d(29,29,29,29)
        property vector4d radii8: Qt.vector4d(29,29,29,29)
        property vector4d radii9: Qt.vector4d(29,29,29,29)
        property vector4d rect0: Qt.vector4d(0,0,0,0)
        property vector4d rect1: Qt.vector4d(0,0,0,0)
        property vector4d rect2: Qt.vector4d(0,0,0,0)
        property vector4d rect3: Qt.vector4d(0,0,0,0)
        property vector4d rect4: Qt.vector4d(0,0,0,0)
        property vector4d rect5: Qt.vector4d(0,0,0,0)
        property vector4d rect6: Qt.vector4d(0,0,0,0)
        property vector4d rect7: Qt.vector4d(0,0,0,0)
        property vector4d rect8: Qt.vector4d(0,0,0,0)
        property vector4d rect9: Qt.vector4d(0,0,0,0)
        property vector4d rect10: Qt.vector4d(0,0,0,0)
        property vector4d rect11: Qt.vector4d(0,0,0,0)
        property vector4d rect12: Qt.vector4d(0,0,0,0)
        property vector4d rect13: Qt.vector4d(0,0,0,0)
        property vector4d rect14: Qt.vector4d(0,0,0,0)
        property vector4d rect15: Qt.vector4d(0,0,0,0)
        property vector4d rect16: Qt.vector4d(0,0,0,0)
        property vector4d rect17: Qt.vector4d(0,0,0,0)
        property vector4d rect18: Qt.vector4d(0,0,0,0)
        property vector4d rect19: Qt.vector4d(0,0,0,0)
        property vector4d rect20: Qt.vector4d(0,0,0,0)
        property vector4d rect21: Qt.vector4d(0,0,0,0)
        property vector4d rect22: Qt.vector4d(0,0,0,0)
        property vector4d rect23: Qt.vector4d(0,0,0,0)
        property vector4d rect24: Qt.vector4d(0,0,0,0)
        property vector4d rect25: Qt.vector4d(0,0,0,0)
        property vector4d rect26: Qt.vector4d(0,0,0,0)
        property vector4d rect27: Qt.vector4d(0,0,0,0)
        property vector4d rect28: Qt.vector4d(0,0,0,0)
        property vector4d rect29: Qt.vector4d(0,0,0,0)
        property vector4d rect30: Qt.vector4d(0,0,0,0)
        property vector4d rect31: Qt.vector4d(0,0,0,0)
        property vector4d rect32: Qt.vector4d(0,0,0,0)
        property vector4d rect33: Qt.vector4d(0,0,0,0)
        property vector4d rect34: Qt.vector4d(0,0,0,0)
        property vector4d rect35: Qt.vector4d(0,0,0,0)
        property vector4d rect36: Qt.vector4d(0,0,0,0)
        property vector4d rect37: Qt.vector4d(0,0,0,0)
        property vector4d rect38: Qt.vector4d(0,0,0,0)
        property vector4d rect39: Qt.vector4d(0,0,0,0)
        onStatusChanged: if (status === ShaderEffect.Error) console.error("[AbyssField]", log)
    }
}
