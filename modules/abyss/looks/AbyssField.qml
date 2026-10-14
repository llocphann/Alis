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
    Image {
        id: wallpaperImage
        visible: false
        asynchronous: true
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
            root.waveTexture?.activeProfile ? 1 : 0,Appearance.effectsEnabled ? 1 : 0,root.boundInterior ? root.waveTexture?.encodedHeightCeiling ?? 0 : 0)
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
        readonly property vector4d radii0: root.packedRadii(0)
        readonly property vector4d radii1: root.packedRadii(1)
        readonly property vector4d radii2: root.packedRadii(2)
        readonly property vector4d radii3: root.packedRadii(3)
        readonly property vector4d radii4: root.packedRadii(4)
        readonly property vector4d radii5: root.packedRadii(5)
        readonly property vector4d radii6: root.packedRadii(6)
        readonly property vector4d radii7: root.packedRadii(7)
        readonly property vector4d radii8: root.packedRadii(8)
        readonly property vector4d radii9: root.packedRadii(9)
        readonly property vector4d rect0: root.packed(0)
        readonly property vector4d rect1: root.packed(1)
        readonly property vector4d rect2: root.packed(2)
        readonly property vector4d rect3: root.packed(3)
        readonly property vector4d rect4: root.packed(4)
        readonly property vector4d rect5: root.packed(5)
        readonly property vector4d rect6: root.packed(6)
        readonly property vector4d rect7: root.packed(7)
        readonly property vector4d rect8: root.packed(8)
        readonly property vector4d rect9: root.packed(9)
        readonly property vector4d rect10: root.packed(10)
        readonly property vector4d rect11: root.packed(11)
        readonly property vector4d rect12: root.packed(12)
        readonly property vector4d rect13: root.packed(13)
        readonly property vector4d rect14: root.packed(14)
        readonly property vector4d rect15: root.packed(15)
        readonly property vector4d rect16: root.packed(16)
        readonly property vector4d rect17: root.packed(17)
        readonly property vector4d rect18: root.packed(18)
        readonly property vector4d rect19: root.packed(19)
        readonly property vector4d rect20: root.packed(20)
        readonly property vector4d rect21: root.packed(21)
        readonly property vector4d rect22: root.packed(22)
        readonly property vector4d rect23: root.packed(23)
        readonly property vector4d rect24: root.packed(24)
        readonly property vector4d rect25: root.packed(25)
        readonly property vector4d rect26: root.packed(26)
        readonly property vector4d rect27: root.packed(27)
        readonly property vector4d rect28: root.packed(28)
        readonly property vector4d rect29: root.packed(29)
        readonly property vector4d rect30: root.packed(30)
        readonly property vector4d rect31: root.packed(31)
        readonly property vector4d rect32: root.packed(32)
        readonly property vector4d rect33: root.packed(33)
        readonly property vector4d rect34: root.packed(34)
        readonly property vector4d rect35: root.packed(35)
        readonly property vector4d rect36: root.packed(36)
        readonly property vector4d rect37: root.packed(37)
        readonly property vector4d rect38: root.packed(38)
        readonly property vector4d rect39: root.packed(39)
        onStatusChanged: if (status === ShaderEffect.Error) console.error("[AbyssField]", log)
    }
}
