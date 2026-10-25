#version 440
// Original Abyss field: inverse workspace opening unioned with edge deformations.
// One final distance owns fill, specular rim and shadow. No clock/time uniform.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(location=1) in vec4 clipBounds;
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
layout(binding=1) uniform sampler2D wallpaper;
layout(binding=2) uniform sampler2D waveSamples;
vec2 waveSample(float index) {
    vec4 encoded=texture(waveSamples,vec2((mod(index+waveMaterial.x,waveMaterial.x)+0.5)/waveMaterial.x,0.5));
    return encoded.a<0.5 ? vec2(0.0) : vec2((encoded.r*65280.0+encoded.g*255.0)/65535.0*256.0,encoded.b);
}
float crestSlope(float a, float b) {
    return a*b<=0.0 ? 0.0 : 2.0*a*b/(a+b);
}
vec2 waveAt(float arc) {
    float position=fract(arc/(2.0*(viewport.x+viewport.y)))*waveMaterial.x;
    float index=floor(position),t=fract(position);
    vec2 a=waveSample(index-1.0),b=waveSample(index),c=waveSample(index+1.0),e=waveSample(index+2.0);
    float delta=c.x-b.x;
    float start=crestSlope(b.x-a.x,delta),end=crestSlope(delta,e.x-c.x);
    // Monotone cubic Hermite: continuous tangent, zero slope at a crest and no
    // Catmull-Rom overshoot/trough. Explicit texel centers preserve corner wrap.
    float t2=t*t,t3=t2*t;
    float height=(2.0*t3-3.0*t2+1.0)*b.x+(t3-2.0*t2+t)*start
        +(-2.0*t3+3.0*t2)*c.x+(t3-t2)*end;
    return vec2(max(0.0,height),mix(b.y,c.y,t2*(3.0-2.0*t)));
}
vec2 waveProfile(vec2 p) {
    // Flat/disabled/settled outputs avoid all wave texture reads.
    if(waveMaterial.y<0.5 || waveMaterial.x<1.0) return vec2(0.0);
    vec4 distances=vec4(p.y,viewport.x-p.x,viewport.y-p.y,p.x);
    float nearest=min(min(distances.x,distances.y),min(distances.z,distances.w));
    vec4 rawWeights=exp(-max(vec4(0.0),distances-nearest)/28.0);
    vec4 clampedWeights=max(vec4(0.0),rawWeights-0.001);
    vec4 weights=clampedWeights*step(vec4(0.001),vec4(insets.y,insets.z,insets.w,insets.x));
    vec4 arcs=vec4(p.x,viewport.x+p.y,2.0*viewport.x+viewport.y-p.x,2.0*(viewport.x+viewport.y)-p.y);
    vec2 result=vec2(0.0);
    // Only nearby sides contribute; the corner blend shares the circular field.
    if(weights.x>0.0) result+=waveAt(arcs.x)*weights.x;
    if(weights.y>0.0) result+=waveAt(arcs.y)*weights.y;
    if(weights.z>0.0) result+=waveAt(arcs.z)*weights.z;
    if(weights.w>0.0) result+=waveAt(arcs.w)*weights.w;
    return result/max(0.000001,dot(clampedWeights,vec4(1.0)))*smoothstep(0.0,10.0,nearest);
}
// Local surface tension and two traveling crests are evaluated in the same
// distance/material pass. Zero uniforms preserve the resting field exactly.
vec2 waterInteraction(vec2 p) {
    float displacement=0.0,light=0.0;
    if(liquidContact.w>0.001) {
        vec2 offset=p-liquidContact.xy,n=liquidContactNormal.xy;
        float tangent=dot(offset,vec2(-n.y,n.x))/max(0.1,liquidContact.z);
        float depth=dot(offset,n)/max(0.1,liquidContact.z);
        if(abs(tangent)<72.0 && abs(depth)<48.0) {
            float neck=exp(-tangent*tangent/460.0-depth*depth/550.0)*liquidContact.w;
            if(liquidContactNormal.z>.5) {
                float radius=length(vec2(tangent,depth*2.2));
                float swirl=sin(radius*.32-liquidContactNormal.w*36.0);
                displacement-=liquidContact.z*neck*(14.0+swirl*4.0);
                light+=neck*(.24+swirl*.12);
            } else {
                displacement+=16.0*liquidContact.z*neck;
                light+=neck*.22;
            }
        }
    }
    if(liquidRipple.w>0.001 && liquidRipple.z<1.0) {
        vec2 offset=p-liquidRipple.xy,n=liquidRippleNormal.xy;
        float scale=max(0.1,liquidRippleNormal.z);
        float tangent=abs(dot(offset,vec2(-n.y,n.x)))/scale;
        float depth=dot(offset,n)/scale;
        if(tangent<220.0 && abs(depth)<36.0) {
            float phase=liquidRipple.z;
            float front=phase*240.0;
            float a=exp(-pow((tangent-front)/13.0,2.0));
            float b=exp(-pow((tangent-front+24.0)/16.0,2.0));
            float envelope=exp(-abs(depth)/12.0)*pow(1.0-phase,1.5)*liquidRipple.w;
            displacement+=(a-.28*b)*18.0*scale*envelope;
            light+=(a+b*.3)*envelope*.6;
        }
    }
    return vec2(displacement,light);
}
float roundedBox(vec2 p, vec4 rect, float radius) {
    float r = min(radius,min(rect.z,rect.w)*0.5);
    vec2 q = abs(p-rect.xy-rect.zw*0.5)-rect.zw*0.5+r;
    return length(max(q,0.0))+min(max(q.x,q.y),0.0)-r;
}
float fuse(float a, float b) {
    float k = max(0.1,material.y);
    float h = max(k-abs(a-b),0.0)/k;
    return min(a,b)-h*h*k*0.25;
}
float contactCorner(vec2 point,float start,float end,float radius) {
    if(radius<=0.0) return 1e20;
    float q=min(point.x-start+radius,end+radius-point.x);
    if(point.y<0.0)return length(vec2(min(q,0.0),point.y));
    if(point.y>radius)return min(length(vec2(min(q,0.0),point.y)),
        length(vec2(max(radius-q,0.0),point.y-radius)));
    if(q<0.0)return length(vec2(q,point.y));
    float circle=radius-length(vec2(q,point.y-radius));
    float clip=max(-q,max(-point.y,point.y-radius));
    return max(circle,clip);
}
float physicalContact(vec2 p,vec4 rect,float radius,float bodyRadius) {
    float d=1e20;
    float rounding=max(0.0,min(bodyRadius,min(rect.z,rect.w)*.5));
    if(contactEdges.x>.5 && rect.y<=0.0 && rect.y+rect.w>0.0)
        d=min(d,contactCorner(p,rect.x,rect.x+rect.z,max(0.0,min(radius,min(rect.z*.5,rect.y+rect.w-rounding)))));
    if(contactEdges.z>.5 && rect.y+rect.w>=viewport.y && rect.y<viewport.y)
        d=min(d,contactCorner(vec2(p.x,viewport.y-p.y),rect.x,rect.x+rect.z,max(0.0,min(radius,min(rect.z*.5,viewport.y-rect.y-rounding)))));
    if(contactEdges.w>.5 && rect.x<=0.0 && rect.x+rect.z>0.0)
        d=min(d,contactCorner(p.yx,rect.y,rect.y+rect.w,max(0.0,min(radius,min(rect.w*.5,rect.x+rect.z-rounding)))));
    if(contactEdges.y>.5 && rect.x+rect.z>=viewport.x && rect.x<viewport.x)
        d=min(d,contactCorner(vec2(p.y,viewport.x-p.x),rect.y,rect.y+rect.w,max(0.0,min(radius,min(rect.w*.5,viewport.x-rect.x-rounding)))));
    return d;
}
float record(float d, vec2 p, vec4 rect, float radius, bool boundPoint, float support) {
    if(rect.z <= 0.0 || rect.w <= 0.0) return d;
    // Conservative lower bound for the box and its physical contact support.
    // Only skip when the smooth union is exactly the current distance. The
    // 1px arithmetic margin is used within the finite coordinate domain below;
    // other inputs retain the original distance calculation.
    if(boundPoint && radius >= 0.0 && radius <= 32768.0
            && all(lessThanEqual(abs(rect),vec4(32768.0)))) {
        vec2 outside=max(rect.xy-p,p-rect.xy-rect.zw);
        float lowerBound=max(outside.x,outside.y)-material.x;
        if(lowerBound > d+support) return d;
    }
    return fuse(d,min(roundedBox(p,rect,radius),physicalContact(p,rect,material.x,radius)));
}
vec4 workspaceRect() {
    // A disabled Edge lies outside the render target, including its AA/rim
    // support. Local module/body records still join the field independently.
    vec4 edges=mix(vec4(-64.0),insets,step(vec4(0.001),insets));
    return vec4(edges.xy,viewport.xy-edges.xy-edges.zw);
}
float field(vec2 p) {
    bool boundPoint=material.x >= 0.0 && material.x <= 32768.0
        && material.y <= 32768.0
        && all(lessThanEqual(abs(p),vec2(32768.0)));
    float support=max(0.1,material.y)+1.0;
    vec4 hole=workspaceRect();
    float d=-roundedBox(p,hole,material.x);
    // Fold the same 40 slots in the same order without duplicating the
    // distance/control-flow program 40 times in the driver compiler.
    vec4 rectangles[40]=vec4[40](
        rect0,rect1,rect2,rect3,rect4,rect5,rect6,rect7,
        rect8,rect9,rect10,rect11,rect12,rect13,rect14,rect15,
        rect16,rect17,rect18,rect19,rect20,rect21,rect22,rect23,
        rect24,rect25,rect26,rect27,rect28,rect29,rect30,rect31,
        rect32,rect33,rect34,rect35,rect36,rect37,rect38,rect39);
    vec4 rounding[10]=vec4[10](
        radii0,radii1,radii2,radii3,radii4,
        radii5,radii6,radii7,radii8,radii9);
    for(int i=0;i<40;i++)
        // Avoid integer modulo: the Qt6 package also serves GLSL 1.20.
        d=record(d,p,rectangles[i],rounding[i/4][i-(i/4)*4],boundPoint,support);
    return d;
}
layout(binding=3) uniform sampler2D bodyTexture;
void main() {
    vec2 p=renderRect.xy+qt_TexCoord0*renderRect.zw;
    bool interior=maskOnly<.5 && p.x>clipBounds.x && p.y>clipBounds.y
        && p.x<clipBounds.z && p.y<clipBounds.w;
    vec2 wave=vec2(0.0),interaction=vec2(0.0);
    float d=1e6;
    if(!interior) {
        wave=waveProfile(p);
        interaction=waterInteraction(p);
        d=field(p)-wave.x-interaction.x;
    }
    // Derivatives are evaluated before any divergent early return.
    vec2 gradient=vec2(dFdx(d),dFdy(d));
    float aa=max(0.6,fwidth(d)*0.6);
    if(maskOnly>.5) {
        // Keep exactly the workspace side of the live liquid contour. The
        // bounded capture exists only while a body is sinking into that field.
        fragColor=texture(bodyTexture,qt_TexCoord0)*smoothstep(-aa,aa,d)*qt_Opacity;
        return;
    }
    if(d>24.0) { fragColor=vec4(0.0); return; }
    float coverage=1.0-smoothstep(-aa,aa,d);
    float depth=exp(-abs(d)*0.045);
    // Bodies occupy the workspace side of the resting Edge. Blend their
    // independent material into the same union pass at each attachment neck.
    float bodyBlend=smoothstep(0.0,24.0,-roundedBox(p,workspaceRect(),material.x));
    float opacity=mix(surface.a,contentMaterial.x,bodyBlend);
    float blurRadius=mix(effects.x,contentMaterial.y,bodyBlend);
    vec4 tint=vec4(surface.rgb/max(surface.a,0.0001)*opacity,opacity);
    vec4 body=mix(tint,raised*opacity,depth*0.38*material.w);
    if(effects.z>0.5 && coverage>0.0) {
        vec2 normal=gradient/max(0.0001,length(gradient));
        vec2 uv=qt_TexCoord0+normal*effects.y*exp(-abs(d)/30.0)/viewport.xy;
        uv=wallpaperCrop.xy+clamp(uv,0.0,1.0)*wallpaperCrop.zw;
        vec2 stepUv=blurRadius/viewport.xy*wallpaperCrop.zw;
        vec3 glass=texture(wallpaper,uv).rgb;
        if(blurRadius>0.0) {
            // Bounded five-tap wallpaper blur in the same silhouette pass.
            glass=glass*0.4+(texture(wallpaper,uv+vec2(stepUv.x,0)).rgb
                +texture(wallpaper,uv-vec2(stepUv.x,0)).rgb
                +texture(wallpaper,uv+vec2(0,stepUv.y)).rgb
                +texture(wallpaper,uv-vec2(0,stepUv.y)).rgb)*0.15;
        }
        // Strong absorption keeps typography readable; no live application
        // pixels are sampled. Missing/animated wallpaper uses the color body.
        body.rgb=mix(body.rgb,glass*opacity,0.075+depth*0.07);
    }
    vec2 normal=gradient/max(0.0001,length(gradient));
    float facing=clamp(dot(normal,normalize(vec2(-0.45,-0.85)))*0.5+0.5,0.0,1.0);
    float reflection=exp(-abs(d)*0.19)*(0.10+0.40*pow(facing,3.0))*material.w;
    float spec=exp(-abs(d)*0.8)*pow(facing,5.0)*material.w;
    body.rgb=mix(body.rgb,raised.rgb*body.a,reflection);
    body.rgb+=rim.rgb*body.a*(spec*0.65+reflection*0.32);
    // QColor uniforms arrive premultiplied. The local specular catch uses the
    // same light color while recovering its brightness at the liquid contact.
    body.rgb+=rim.rgb/max(rim.a,0.0001)*body.a*interaction.y*exp(-abs(d)/5.0)*material.w;
    body.rgb*=1.0-exp(-max(-d,0.0)*0.10)*(1.0-facing)*0.18*material.w;
    // A thin, broken foam band follows the same crest distance. Its phase is
    // driven by crest motion, not a wall-clock uniform, so sleeping stays static.
    float breaker=wave.y*waveMaterial.z*exp(-abs(d+1.2)/2.8);
    float lace=0.6+0.4*sin((p.x+p.y)*0.7+wave.x*0.12)*sin((p.x-p.y)*0.37);
    body.rgb=mix(body.rgb,vec3(0.86,0.97,1.0)*body.a,clamp(breaker*lace,0.0,0.85));
    body.a=opacity;
    vec4 outside=shadow*exp(-max(d,0.0)/5.0)+glow*exp(-max(d,0.0)/7.0);
    outside*=smoothstep(-aa,aa,d)*(1.0-smoothstep(16.0,24.0,d));
    float alpha=coverage*body.a;
    fragColor=(body*coverage+outside*(1.0-alpha))*qt_Opacity;
}
