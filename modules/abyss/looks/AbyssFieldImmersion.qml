import QtQuick

// Finite body mask using the same distance field, waves and water contact.
// Shared uniforms and texture providers come from the existing full pass.
ShaderEffect {
    id:root
    required property var sourcePass
    property var bodyItem:null
    property rect bodySourceRect:Qt.rect(-48,-100,208,298)
    property real renderScale:1
    property vector4d renderRect:Qt.vector4d(0,0,width,height)
    readonly property real maskOnly:1
    fragmentShader:Qt.resolvedUrl("AbyssField.frag.qsb")
    readonly property var bodyTexture:bodySource
    readonly property vector4d viewport:sourcePass.viewport
    readonly property vector4d insets:sourcePass.insets
    readonly property vector4d zeroCorners:sourcePass.zeroCorners
    readonly property vector4d contactEdges:sourcePass.contactEdges
    readonly property vector4d material:sourcePass.material
    readonly property vector4d liquidContact:sourcePass.liquidContact
    readonly property vector4d liquidContactNormal:sourcePass.liquidContactNormal
    readonly property vector4d liquidRipple:sourcePass.liquidRipple
    readonly property vector4d liquidRippleNormal:sourcePass.liquidRippleNormal
    readonly property var wallpaper:sourcePass.wallpaper
    readonly property var waveSamples:sourcePass.waveSamples
    readonly property vector4d waveMaterial:sourcePass.waveMaterial
    readonly property vector4d effects:sourcePass.effects
    readonly property vector4d contentMaterial:sourcePass.contentMaterial
    readonly property vector4d wallpaperCrop:sourcePass.wallpaperCrop
    readonly property color surface:sourcePass.surface
    readonly property color raised:sourcePass.raised
    readonly property color rim:sourcePass.rim
    readonly property color shadow:sourcePass.shadow
    readonly property color glow:sourcePass.glow
    readonly property vector4d radii0:sourcePass.radii0
    readonly property vector4d radii1:sourcePass.radii1
    readonly property vector4d radii2:sourcePass.radii2
    readonly property vector4d radii3:sourcePass.radii3
    readonly property vector4d radii4:sourcePass.radii4
    readonly property vector4d radii5:sourcePass.radii5
    readonly property vector4d radii6:sourcePass.radii6
    readonly property vector4d radii7:sourcePass.radii7
    readonly property vector4d radii8:sourcePass.radii8
    readonly property vector4d radii9:sourcePass.radii9
    readonly property vector4d rect0:sourcePass.rect0
    readonly property vector4d rect1:sourcePass.rect1
    readonly property vector4d rect2:sourcePass.rect2
    readonly property vector4d rect3:sourcePass.rect3
    readonly property vector4d rect4:sourcePass.rect4
    readonly property vector4d rect5:sourcePass.rect5
    readonly property vector4d rect6:sourcePass.rect6
    readonly property vector4d rect7:sourcePass.rect7
    readonly property vector4d rect8:sourcePass.rect8
    readonly property vector4d rect9:sourcePass.rect9
    readonly property vector4d rect10:sourcePass.rect10
    readonly property vector4d rect11:sourcePass.rect11
    readonly property vector4d rect12:sourcePass.rect12
    readonly property vector4d rect13:sourcePass.rect13
    readonly property vector4d rect14:sourcePass.rect14
    readonly property vector4d rect15:sourcePass.rect15
    readonly property vector4d rect16:sourcePass.rect16
    readonly property vector4d rect17:sourcePass.rect17
    readonly property vector4d rect18:sourcePass.rect18
    readonly property vector4d rect19:sourcePass.rect19
    readonly property vector4d rect20:sourcePass.rect20
    readonly property vector4d rect21:sourcePass.rect21
    readonly property vector4d rect22:sourcePass.rect22
    readonly property vector4d rect23:sourcePass.rect23
    readonly property vector4d rect24:sourcePass.rect24
    readonly property vector4d rect25:sourcePass.rect25
    readonly property vector4d rect26:sourcePass.rect26
    readonly property vector4d rect27:sourcePass.rect27
    readonly property vector4d rect28:sourcePass.rect28
    readonly property vector4d rect29:sourcePass.rect29
    readonly property vector4d rect30:sourcePass.rect30
    readonly property vector4d rect31:sourcePass.rect31
    readonly property vector4d rect32:sourcePass.rect32
    readonly property vector4d rect33:sourcePass.rect33
    readonly property vector4d rect34:sourcePass.rect34
    readonly property vector4d rect35:sourcePass.rect35
    readonly property vector4d rect36:sourcePass.rect36
    readonly property vector4d rect37:sourcePass.rect37
    readonly property vector4d rect38:sourcePass.rect38
    readonly property vector4d rect39:sourcePass.rect39
    ShaderEffectSource {
        id:bodySource;visible:false;sourceItem:root.bodyItem;sourceRect:root.bodySourceRect
        hideSource:true;live:true;smooth:true
        textureSize:Qt.size(Math.max(1,Math.ceil(root.width*root.renderScale)),Math.max(1,Math.ceil(root.height*root.renderScale)))
    }
}
