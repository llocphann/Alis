#version 440
// Real-time perceptual OKLab palette remap for auto-themed visible desktop windows
// inside the zoomed Change Wallpaper Desktop Stage.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uvRect;        // (u0, v0, uWidth, vHeight)
    vec4 tileSize;      // (widthPx, heightPx, cornerRadiusPx, themeMix)
    vec4 baseBg;        // (r, g, b, darkMode)
    vec4 targetBg;      // (r, g, b, darkMode)
    vec4 baseSurface;   // (r, g, b, autoThemed)
    vec4 targetSurface; // (r, g, b, 0)
    vec4 basePrimary;   // (r, g, b, 0)
    vec4 targetPrimary; // (r, g, b, 0)
};

layout(binding = 1) uniform sampler2D screenTex;

float roundedBox(vec2 p, vec2 size, float radius) {
    float r = min(radius, min(size.x, size.y) * 0.5);
    vec2 halfSize = size * 0.5;
    vec2 q = abs(p - halfSize) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 srgbToLinear(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    vec3 lo = c / 12.92;
    vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(lo, hi, step(vec3(0.04045), c));
}

vec3 linearToSrgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(vec3(0.0031308), c));
}

vec3 linearToOklab(vec3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    float l_ = pow(max(l, 0.0), 1.0 / 3.0);
    float m_ = pow(max(m, 0.0), 1.0 / 3.0);
    float s_ = pow(max(s, 0.0), 1.0 / 3.0);
    return vec3(
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    );
}

vec3 oklabToLinear(vec3 c) {
    float l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;
    return vec3(
         4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

void main() {
    vec2 sizePx = max(tileSize.xy, vec2(1.0));
    vec2 p = qt_TexCoord0 * sizePx;
    float sdf = roundedBox(p, sizePx, tileSize.z);
    float maskAlpha = 1.0 - smoothstep(-0.75, 0.75, sdf);
    if (maskAlpha <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 sampleUv = clamp(uvRect.xy + qt_TexCoord0 * uvRect.zw, vec2(0.0005), vec2(0.9995));
    vec4 src = texture(screenTex, sampleUv);
    float srcAlpha = clamp(src.a, 0.0, 1.0);
    vec3 rgb = srcAlpha > 0.001 ? clamp(src.rgb / srcAlpha, 0.0, 1.0) : vec3(0.0);

    float themeMix = clamp(tileSize.w, 0.0, 1.0);
    if (baseSurface.a > 0.5 && themeMix > 0.001 && srcAlpha > 0.01) {
        vec3 baseBgLab = linearToOklab(srgbToLinear(baseBg.rgb));
        vec3 targetBgLab = linearToOklab(srgbToLinear(targetBg.rgb));
        vec3 baseSurfLab = linearToOklab(srgbToLinear(baseSurface.rgb));
        vec3 targetSurfLab = linearToOklab(srgbToLinear(targetSurface.rgb));
        vec3 basePrimLab = linearToOklab(srgbToLinear(basePrimary.rgb));
        vec3 targetPrimLab = linearToOklab(srgbToLinear(targetPrimary.rgb));

        float paletteDist = length(targetSurfLab.yz - baseSurfLab.yz)
            + length(targetPrimLab.yz - basePrimLab.yz)
            + abs(targetBgLab.x - baseBgLab.x);

        if (paletteDist > 0.002) {
            vec3 pixLab = linearToOklab(srgbToLinear(rgb));
            vec2 pixAB = pixLab.yz;
            float pixChroma = length(pixAB);

            vec2 refBaseAB = (baseBgLab.yz + baseSurfLab.yz) * 0.5;
            vec2 refTargetAB = (targetBgLab.yz + targetSurfLab.yz) * 0.5;
            float baseNeutralRadius = max(0.035, length(refBaseAB) + 0.025);

            float distFromBaseNeutral = length(pixAB - refBaseAB);
            float neutralMask = (1.0 - smoothstep(0.020, 0.060, distFromBaseNeutral))
                * (1.0 - smoothstep(baseNeutralRadius, baseNeutralRadius + 0.040, pixChroma));
            float lumGuard = smoothstep(0.03, 0.14, pixLab.x) * (1.0 - smoothstep(0.91, 0.99, pixLab.x));

            float basePrimChroma = length(basePrimLab.yz);
            float accentMask = 0.0;
            vec2 accentTargetAB = pixAB;
            if (basePrimChroma > 0.015 && pixChroma > 0.015) {
                float cosSim = dot(pixAB / pixChroma, basePrimLab.yz / basePrimChroma);
                accentMask = smoothstep(0.68, 0.94, cosSim)
                    * smoothstep(0.018, 0.055, pixChroma)
                    * (1.0 - neutralMask * 0.5);
                float chromaRatio = clamp(pixChroma / max(basePrimChroma, 0.020), 0.35, 1.50);
                accentTargetAB = length(targetPrimLab.yz) > 0.010
                    ? targetPrimLab.yz * chromaRatio
                    : refTargetAB;
            }

            vec2 shiftedNeutralAB = pixAB + (refTargetAB - refBaseAB) * lumGuard;
            vec2 outAB = pixAB;
            outAB = mix(outAB, shiftedNeutralAB, neutralMask);
            outAB = mix(outAB, accentTargetAB, accentMask);

            bool isDarkBase = baseBg.a > 0.5;
            float surfaceBgBand = isDarkBase
                ? (1.0 - smoothstep(0.18, 0.48, pixLab.x))
                : smoothstep(0.62, 0.92, pixLab.x);
            float lumDelta = clamp(targetBgLab.x - baseBgLab.x, -0.035, 0.035) * surfaceBgBand * neutralMask;
            float outL = clamp(pixLab.x + lumDelta, 0.0, 1.0);

            vec3 remapped = linearToSrgb(oklabToLinear(vec3(outL, outAB)));
            rgb = mix(rgb, remapped, themeMix);
        }
    }

    float outAlpha = maskAlpha * srcAlpha;
    fragColor = vec4(rgb * outAlpha, outAlpha) * qt_Opacity;
}
