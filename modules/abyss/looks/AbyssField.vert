#version 440
// Prove a central rectangle has distance > 24 even after smooth union, waves
// and water displacement. Do this once per vertex, using the existing uniforms.
// Each primitive there is at least L=k+24+reserve+displacement away. A smooth
// union of any two distances >= L-k stays >= L-k (the smaller distance either
// stays unchanged or the correction is bounded by the gap to L-k). Thus all
// forty ordered folds remain transparent. The reserve also protects adjacent
// derivative quads: visible pixels retain their original derivatives.
layout(location=0) in vec4 qt_Vertex;
layout(location=1) in vec2 qt_MultiTexCoord0;
layout(location=0) out vec2 qt_TexCoord0;
layout(location=1) out vec4 clipBounds;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 viewport;
    vec4 renderRect;
    float interiorEnabled;
    float maskOnly;
    vec4 insets;
    vec4 zeroCorners;
    vec4 contactEdges;
    vec4 material;
    vec4 liquidContact;
    vec4 liquidContactNormal;
    vec4 liquidRipple;
    vec4 liquidRippleNormal;
    vec4 effects;
    vec4 contentMaterial;
    vec4 waveMaterial;
    vec4 wallpaperCrop;
    vec4 surface;
    vec4 raised;
    vec4 rim;
    vec4 shadow;
    vec4 glow;
    vec4 radii0;
    vec4 radii1;
    vec4 radii2;
    vec4 radii3;
    vec4 radii4;
    vec4 radii5;
    vec4 radii6;
    vec4 radii7;
    vec4 radii8;
    vec4 radii9;
    vec4 rect0; vec4 rect1; vec4 rect2; vec4 rect3;
    vec4 rect4; vec4 rect5; vec4 rect6; vec4 rect7;
    vec4 rect8; vec4 rect9; vec4 rect10; vec4 rect11;
    vec4 rect12; vec4 rect13; vec4 rect14; vec4 rect15;
    vec4 rect16; vec4 rect17; vec4 rect18; vec4 rect19;
    vec4 rect20; vec4 rect21; vec4 rect22; vec4 rect23;
    vec4 rect24; vec4 rect25; vec4 rect26; vec4 rect27;
    vec4 rect28; vec4 rect29; vec4 rect30; vec4 rect31;
    vec4 rect32; vec4 rect33; vec4 rect34; vec4 rect35;
    vec4 rect36; vec4 rect37; vec4 rect38; vec4 rect39;
};
bool finiteVector(vec4 v) { return all(lessThanEqual(abs(v),vec4(1e20))); }
vec4 interiorBounds() {
    if(interiorEnabled<.5 || maskOnly>.5 || !finiteVector(viewport) || !finiteVector(insets)
       || !finiteVector(material) || !finiteVector(waveMaterial) || !finiteVector(liquidContact)
       || !finiteVector(liquidContactNormal) || !finiteVector(liquidRipple) || !finiteVector(liquidRippleNormal))return vec4(0.0);
    float width=viewport.x,height=viewport.y,radius=material.x,k=max(.1,material.y);
    if(width<=0.0||height<=0.0||width>32768.0||height>32768.0||radius<0.0||radius>32768.0||material.y<0.0||material.y>32768.0)return vec4(0.0);
    // Numerical reserve plus the complete neighbouring derivative quad.
    float reach=24.0+k+16.0;
    if(waveMaterial.y>=.5&&waveMaterial.x>=1.0) {
        if(!(waveMaterial.w>0.0))return vec4(0.0);
        reach+=waveMaterial.w+1.0;
    }
    if(liquidContact.w>.001)reach+=18.0*abs(liquidContact.z)*liquidContact.w;
    if(liquidRipple.w>.001&&liquidRipple.z<1.0)reach+=23.04*max(.1,liquidRippleNormal.z)*liquidRipple.w*pow(1.0-liquidRipple.z,1.5);
    if(!(reach<=1e20))return vec4(0.0);
    // The workspace and every physical contact are covered by these strips.
    // Each body can be assigned to its cheapest strip, even if it is detached.
    vec4 depths=max(vec4(0.0),insets)+radius+reach;
    vec4 rectangles[40]=vec4[40](
        rect0,rect1,rect2,rect3,rect4,rect5,rect6,rect7,
        rect8,rect9,rect10,rect11,rect12,rect13,rect14,rect15,
        rect16,rect17,rect18,rect19,rect20,rect21,rect22,rect23,
        rect24,rect25,rect26,rect27,rect28,rect29,rect30,rect31,
        rect32,rect33,rect34,rect35,rect36,rect37,rect38,rect39);
    vec4 rounding[10]=vec4[10](
        radii0,radii1,radii2,radii3,radii4,
        radii5,radii6,radii7,radii8,radii9);
    for(int i=0;i<40;i++) {
        vec4 r=rectangles[i];float bodyRadius=rounding[i/4][i-(i/4)*4];
        if(r.z<=0.0||r.w<=0.0)continue;
        if(!all(lessThanEqual(abs(r),vec4(32768.0)))||!(abs(bodyRadius)<=32768.0))return vec4(0.0);
        vec4 sides=max(vec4(0.0),vec4(r.x+r.z,r.y+r.w,width-r.x,height-r.y));
        int side=0;
        for(int j=1;j<4;j++)if(sides[j]<sides[side])side=j;
        depths[side]=max(depths[side],sides[side]+reach);
    }
    if(depths.x+depths.z>=width||depths.y+depths.w>=height)return vec4(0.0);
    return vec4(depths.xy,viewport.xy-depths.zw);
}
void main() {
    qt_TexCoord0=qt_MultiTexCoord0;
    clipBounds=interiorBounds();
    gl_Position=qt_Matrix*qt_Vertex;
}
