#version 440
// Abyss Edit Stage Frame: paints the Overview/Hot-Corners-synced wallpaper
// surround outside the shrunk Desktop Stage and smooth-unions (`fuse`) the
// outer Desktop Stage Abyss bezel with the external Customization Control Dock
// using exact AbyssStyle Screen Edges material parameters.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 viewport;         // (width, height, progress, wallpaperReady)
    vec4 stageRect;        // (x, y, width, height) of shrunk Desktop Stage
    vec4 dockRect;         // (x, y, width, height) of bottom external Control Dock + overlap
    vec4 leftDockRect;     // (x, y, width, height) of left external Control Dock + overlap
    vec4 rightDockRect;    // (x, y, width, height) of right external Control Dock + overlap
    vec4 shapeParams;      // (stageInnerRadius, bezel, dockRadius, neckSmoothness)
    vec4 materialParams;   // (highlightStrength, refractionStrength, backdropBlurTexels, dockBlurTexels)
    vec4 backdropTone;     // (dim, saturation, contrast, fitMode)
    vec4 backdropVignette;    // (vignetteIntensity, vignetteRadius, auroraOverlayAlpha, texWidth)
    vec4 wallpaperCrop;       // (cropX, cropY, cropW, cropH)
    vec4 wallpaperNextCrop;   // (cropX, cropY, cropW, cropH) for incoming preview wallpaper
    vec4 wallpaperTransition; // (mixProgress 0..1, nextReady 0|1, nextTexWidth, reserved)
    vec4 surface;             // premultiplied AbyssStyle.surfaceDeep @ surfaceOpacity
    vec4 dockSurface;         // premultiplied AbyssStyle.surfaceDeep @ contentOpacity
    vec4 raised;              // premultiplied AbyssStyle.surfaceRaised
    vec4 rim;                 // premultiplied AbyssStyle.specular
    vec4 shadow;              // premultiplied AbyssStyle.shadow
    vec4 glow;                // premultiplied AbyssStyle.glow
    vec4 auroraBase;          // premultiplied Appearance.colors.colLayer0Base
};

layout(binding = 1) uniform sampler2D wallpaper;
layout(binding = 2) uniform sampler2D wallpaperNext;

float roundedBox(vec2 p, vec4 rect, float radius) {
    float r = min(radius, min(rect.z, rect.w) * 0.5);
    vec2 q = abs(p - rect.xy - rect.zw * 0.5) - rect.zw * 0.5 + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float fuse(float a, float b, float k) {
    float s = max(0.5, k);
    float h = max(s - abs(a - b), 0.0) / s;
    return min(a, b) - h * h * s * 0.25;
}

vec3 sampleSingleWallpaperBlur(sampler2D tex, vec4 crop, float rawTexW, vec2 normUv, float radius, out float inBounds) {
    vec2 rawUv = crop.xy + normUv * crop.zw;
    if (backdropTone.w > 0.5 && (rawUv.x < 0.0 || rawUv.x > 1.0 || rawUv.y < 0.0 || rawUv.y > 1.0)) {
        inBounds = 0.0;
        return auroraBase.rgb / max(auroraBase.a, 0.0001);
    }
    inBounds = 1.0;
    vec2 baseUv = clamp(rawUv, vec2(0.002), vec2(0.998));
    if (radius <= 0.05)
        return texture(tex, baseUv).rgb;

    float texW = max(320.0, rawTexW);
    float texH = max(180.0, texW * 0.5625);
    vec2 texel = vec2(1.0 / texW, 1.0 / texH) * abs(crop.zw);
    vec2 d1 = texel * (radius * 0.42);
    vec2 d2 = texel * (radius * 0.85);
    vec2 d3 = texel * (radius * 1.32);
    vec2 minUv = vec2(0.002);
    vec2 maxUv = vec2(0.998);

    vec3 acc = texture(tex, baseUv).rgb * 0.16;
    acc += texture(tex, clamp(baseUv + vec2( d1.x,  d1.y), minUv, maxUv)).rgb * 0.105;
    acc += texture(tex, clamp(baseUv + vec2(-d1.x,  d1.y), minUv, maxUv)).rgb * 0.105;
    acc += texture(tex, clamp(baseUv + vec2( d1.x, -d1.y), minUv, maxUv)).rgb * 0.105;
    acc += texture(tex, clamp(baseUv + vec2(-d1.x, -d1.y), minUv, maxUv)).rgb * 0.105;
    acc += texture(tex, clamp(baseUv + vec2( d2.x,  0.0 ), minUv, maxUv)).rgb * 0.065;
    acc += texture(tex, clamp(baseUv + vec2(-d2.x,  0.0 ), minUv, maxUv)).rgb * 0.065;
    acc += texture(tex, clamp(baseUv + vec2( 0.0,   d2.y), minUv, maxUv)).rgb * 0.065;
    acc += texture(tex, clamp(baseUv + vec2( 0.0,  -d2.y), minUv, maxUv)).rgb * 0.065;
    acc += texture(tex, clamp(baseUv + vec2( d3.x,  d3.y), minUv, maxUv)).rgb * 0.04;
    acc += texture(tex, clamp(baseUv + vec2(-d3.x,  d3.y), minUv, maxUv)).rgb * 0.04;
    acc += texture(tex, clamp(baseUv + vec2( d3.x, -d3.y), minUv, maxUv)).rgb * 0.04;
    acc += texture(tex, clamp(baseUv + vec2(-d3.x, -d3.y), minUv, maxUv)).rgb * 0.04;
    return acc;
}

vec3 sampleWallpaperBlur(vec2 normUv, float radius, out float inBounds) {
    float inA = 1.0;
    vec3 colA = sampleSingleWallpaperBlur(wallpaper, wallpaperCrop, backdropVignette.w, normUv, radius, inA);
    float mixT = clamp(wallpaperTransition.x, 0.0, 1.0);
    if (mixT <= 0.0001 || wallpaperTransition.y < 0.5) {
        inBounds = inA;
        return colA;
    }
    float inB = 1.0;
    vec3 colB = sampleSingleWallpaperBlur(wallpaperNext, wallpaperNextCrop, wallpaperTransition.z, normUv, radius, inB);
    inBounds = mix(inA, inB, mixT);
    return mix(colA, colB, mixT);
}

vec3 applyBackdropGrading(vec3 rgb) {
    // Saturation (-1..1, matching Qt MultiEffect)
    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float satFactor = max(0.0, 1.0 + backdropTone.y);
    vec3 graded = mix(vec3(luma), rgb, satFactor);

    // Contrast (-1..1, matching Qt MultiEffect)
    float c = backdropTone.z;
    float contrastFactor = c >= 0.0 ? (1.0 / max(0.08, 1.0 - c * 0.85)) : (1.0 + c);
    graded = clamp((graded - 0.5) * contrastFactor + 0.5, 0.0, 1.0);

    // Aurora tint overlay vs legacy dim overlay (matching Backdrop.qml)
    float auroraAlpha = clamp(backdropVignette.z, 0.0, 1.0);
    if (auroraAlpha > 0.001) {
        vec3 auroraRgb = auroraBase.rgb / max(auroraBase.a, 0.0001);
        graded = mix(graded, auroraRgb, auroraAlpha);
    } else {
        graded *= (1.0 - clamp(backdropTone.x, 0.0, 1.0));
    }

    // Optional bottom vignette (matching Backdrop.qml:556-564)
    float vigIntensity = clamp(backdropVignette.x, 0.0, 1.0);
    if (vigIntensity > 0.001) {
        float vigStart = clamp(backdropVignette.y, 0.0, 0.99);
        float vigT = clamp((qt_TexCoord0.y - vigStart) / max(0.01, 1.0 - vigStart), 0.0, 1.0);
        graded *= (1.0 - vigT * vigIntensity);
    }
    return clamp(graded, 0.0, 1.0);
}

void main() {
    vec2 p = qt_TexCoord0 * viewport.xy;
    float progress = clamp(viewport.z, 0.0, 1.0);
    float innerRadius = shapeParams.x;
    float bezel = shapeParams.y;
    float dockRadius = shapeParams.z;
    float neckK = shapeParams.w;

    float dInner = roundedBox(p, stageRect, innerRadius);
    vec4 bezelRect = vec4(stageRect.xy - vec2(bezel), stageRect.zw + vec2(bezel * 2.0));
    float dBezel = roundedBox(p, bezelRect, innerRadius + bezel);
    float dDock = (dockRect.z > 1.0 && dockRect.w > 1.0)
        ? roundedBox(p, dockRect, dockRadius)
        : 1e6;
    float dLeft = (leftDockRect.z > 1.0 && leftDockRect.w > 1.0)
        ? roundedBox(p, leftDockRect, dockRadius)
        : 1e6;
    float dRight = (rightDockRect.z > 1.0 && rightDockRect.w > 1.0)
        ? roundedBox(p, rightDockRect, dockRadius)
        : 1e6;
    float dAllDocks = min(dDock, min(dLeft, dRight));
    float dOuter = fuse(dBezel, dAllDocks, neckK);

    // Evaluate derivatives in uniform control flow before early return.
    float aaInner = max(0.65, fwidth(dInner) * 0.65);
    float aaOuter = max(0.65, fwidth(dOuter) * 0.65);
    vec2 gradOuter = vec2(dFdx(dOuter), dFdy(dOuter));
    vec2 gradInner = vec2(dFdx(dInner), dFdy(dInner));

    float cutout = smoothstep(-aaInner, aaInner, dInner);
    if (progress <= 0.0001 || cutout <= 0.0001) {
        fragColor = vec4(0.0);
        return;
    }

    float inBounds = 1.0;
    vec3 fallbackBg = auroraBase.rgb / max(auroraBase.a, 0.0001);
    vec3 rawWall = viewport.w > 0.5
        ? sampleWallpaperBlur(qt_TexCoord0, materialParams.z, inBounds)
        : fallbackBg;
    vec3 surroundRgb = viewport.w > 0.5 ? applyBackdropGrading(rawWall) : fallbackBg;
    float surroundAlpha = progress;
    vec4 surround = vec4(surroundRgb * surroundAlpha, surroundAlpha);

    float frameCoverage = 1.0 - smoothstep(-aaOuter, aaOuter, dOuter);
    vec4 body = vec4(0.0);
    if (frameCoverage > 0.0001) {
        float dockBlend = smoothstep(-4.0, 14.0, dBezel);
        vec3 surfRgb = surface.rgb / max(surface.a, 0.0001);
        vec3 dockRgb = dockSurface.rgb / max(dockSurface.a, 0.0001);
        float panelAlpha = clamp(mix(surface.a, dockSurface.a, dockBlend), 0.0, 1.0);
        vec3 solidRgb = mix(surfRgb, dockRgb, dockBlend);

        vec2 nOuter = gradOuter / max(0.0001, length(gradOuter));
        float depthOuter = exp(-abs(dOuter) * 0.05);
        float refraction = materialParams.y;

        // Sample wallpaper glass behind bezel/dock only when translucent or refracting
        vec3 baseRgb = solidRgb;
        if (viewport.w > 0.5 && (panelAlpha < 0.999 || refraction > 0.01)) {
            vec2 refrOffset = nOuter * (refraction / max(vec2(1.0), viewport.xy)) * exp(-abs(dOuter) / 26.0);
            float glassInBounds = 1.0;
            vec3 glassRgb = sampleWallpaperBlur(qt_TexCoord0 + refrOffset, materialParams.w, glassInBounds);
            float refrTint = refraction > 0.01 ? min(0.14, refraction * 0.01) * depthOuter : 0.0;
            vec3 tintedSolid = mix(solidRgb, glassRgb, refrTint);
            baseRgb = mix(glassRgb, tintedSolid, panelAlpha);
        }

        float highlight = clamp(materialParams.x, 0.0, 1.0);
        if (highlight > 0.001) {
            vec3 raisedRgb = raised.rgb / max(raised.a, 0.0001);
            vec3 rimRgb = rim.rgb / max(rim.a, 0.0001);
            float facingOuter = clamp(dot(nOuter, normalize(vec2(-0.45, -0.85))) * 0.5 + 0.5, 0.0, 1.0);
            float reflOuter = exp(-abs(dOuter) * 0.20) * (0.12 + 0.38 * pow(facingOuter, 3.0)) * highlight;
            float specOuter = exp(-abs(dOuter) * 0.85) * pow(facingOuter, 4.0) * highlight;
            baseRgb = mix(baseRgb, raisedRgb, depthOuter * 0.30 * highlight + reflOuter);
            baseRgb += rimRgb * (specOuter * 0.68 + reflOuter * 0.26);

            vec2 nInner = -gradInner / max(0.0001, length(gradInner));
            float facingInner = clamp(dot(nInner, normalize(vec2(-0.45, -0.85))) * 0.5 + 0.5, 0.0, 1.0);
            float specInner = exp(-abs(dInner) * 1.1) * (0.16 + 0.38 * pow(facingInner, 3.0)) * highlight * (1.0 - dockBlend);
            baseRgb += rimRgb * specInner * 0.32;
        }

        // Body alpha: when panelAlpha < 1 and wallpaper is ready, we already composited
        // over glassRgb so the dock replaces surround cleanly without double-dimming.
        float bodyOpacity = (viewport.w > 0.5 ? max(panelAlpha, 0.999) : panelAlpha) * progress;
        if (panelAlpha <= 0.001 && highlight <= 0.001 && refraction <= 0.01) {
            body = vec4(0.0);
        } else {
            body = vec4(clamp(baseRgb, 0.0, 1.0) * bodyOpacity, bodyOpacity);
        }
    }

    float dPos = max(dOuter, 0.0);
    vec4 outside = (shadow * 1.35 * exp(-dPos / 14.0) + glow * exp(-dPos / 9.0)) * progress;
    outside *= smoothstep(-aaOuter, aaOuter, dOuter) * (1.0 - smoothstep(28.0, 44.0, dOuter));

    vec4 back = outside + surround * (1.0 - outside.a);
    float frameAlpha = frameCoverage * body.a;
    vec4 combined = body * frameCoverage + back * (1.0 - frameAlpha);
    fragColor = combined * cutout * qt_Opacity;
}
