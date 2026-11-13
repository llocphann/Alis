#version 440

// Pocket-Dots Wallpaper Transition (`contagio` mode 0 & `perfil` Outline Character mode 1),
// ported from diegoMalagrida/pocket-dots (`shaders/wallfx.frag`) for Alis WallpaperCrossfader.
// In Alis, `source1` and `source2` are pre-cropped screen-aspect ShaderEffectSource textures,
// while `fieldTex` and `lineTex` for `perfil` live in the uncropped new image space (`mapCrop`).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float wallfxMode;
    float sw;
    float sh;
    float fw;
    float fh;
    float lw;
    float lh;
    float wallfxGlow;
    float wallfxLineW;
    float wallfxSdRange;
    float wallfxSeed;
    vec4 mapCrop;
    vec4 wallfxEmber;
    vec4 wallfxInk;
} ubuf;

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;
layout(binding = 3) uniform sampler2D fieldTex;
layout(binding = 4) uniform sampler2D lineTex;

const float PI = 3.14159265;
const float CELL = 4.0;

float escena(float x) {
    x = clamp(x, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + ubuf.wallfxSeed * 13.17) * 43758.5453);
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec2 cam(vec2 uv, float z) {
    return clamp(0.5 + (uv - 0.5) / max(z, 0.001), 0.0, 1.0);
}

vec3 oldAt(vec2 uv) {
    return texture(source1, clamp(uv, 0.0, 1.0)).rgb;
}

vec3 newAt(vec2 uv, float z) {
    return texture(source2, cam(uv, z)).rgb;
}

vec2 mapUv(vec2 uv, float z) {
    return clamp(ubuf.mapCrop.xy + cam(uv, z) * ubuf.mapCrop.zw, 0.0, 1.0);
}

float s16(vec2 texel) {
    vec2 lSize = max(vec2(ubuf.lw, ubuf.lh), vec2(1.0));
    texel = clamp(texel, vec2(0.0), lSize - 1.0);
    vec4 f = texture(lineTex, (texel + 0.5) / lSize);
    return (floor(f.g * 255.0 + 0.5) * 256.0 + floor(f.b * 255.0 + 0.5)) / 65535.0;
}

float surface(vec2 tuv) {
    vec2 lSize = max(vec2(ubuf.lw, ubuf.lh), vec2(1.0));
    vec2 p = tuv * lSize - 0.5;
    vec2 i = floor(p);
    vec2 f = p - i;
    return mix(
        mix(s16(i), s16(i + vec2(1.0, 0.0)), f.x),
        mix(s16(i + vec2(0.0, 1.0)), s16(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float arrivalAt(vec2 c) {
    vec2 fSize = max(vec2(ubuf.fw, ubuf.fh), vec2(1.0));
    c = clamp(c, vec2(0.0), fSize - 1.0);
    vec4 f = texture(fieldTex, (c + 0.5) / fSize);
    return (floor(f.r * 255.0 + 0.5) * 256.0 + floor(f.g * 255.0 + 0.5)) / 65535.0;
}

vec3 contagion(vec2 uv, float t) {
    const float LIFE = 0.05;
    vec2 fSize = max(vec2(ubuf.fw, ubuf.fh), vec2(1.0));
    float energy = sin(PI * t);
    float T = escena(t) * (1.0 + LIFE + 0.01) - 0.01;
    float s = surface(uv);
    vec2 cell = floor(uv * fSize);
    float a = arrivalAt(cell);
    float flick = hash(cell);
    float eAlpha = max(0.0001, ubuf.wallfxEmber.a);
    vec3 emberRgb = ubuf.wallfxEmber.rgb / eAlpha;
    vec3 hot = mix(emberRgb, vec3(1.0), 0.18);
    vec3 c;
    if (a > T) {
        c = oldAt(uv);
        float ahead = a - T;
        if (flick > 0.985 && ahead < 0.02)
            c = mix(c, hot, (1.0 - ahead / 0.02) * 0.8 * ubuf.wallfxGlow * step(0.0, T));
    } else {
        c = newAt(uv, 1.0 + 0.025 * (1.0 - escena(t)));
        bool edge = max(
            max(arrivalAt(cell + vec2(1.0, 0.0)), arrivalAt(cell - vec2(1.0, 0.0))),
            max(arrivalAt(cell + vec2(0.0, 1.0)), arrivalAt(cell - vec2(0.0, 1.0)))
        ) > T;
        float life = clamp((T - a) / LIFE, 0.0, 1.0);
        float burn = (1.0 - life) * (1.0 - life) * (edge ? 1.0 : 0.55);
        c = mix(c, hot, burn * (0.55 + 0.45 * flick) * 0.85 * ubuf.wallfxGlow);
    }
    return c + emberRgb * 0.22 * ubuf.wallfxGlow * energy * exp(-abs(s - T) / 0.006);
}

vec3 outline(vec2 uv, float t) {
    float zCh = 1.0 + 0.03 * (1.0 - escena(t));
    float zBg = 1.0 + 0.015 * (1.0 - escena(t));
    vec4 f = texture(fieldTex, mapUv(uv, zCh));
    float denom = max(ubuf.fw * max(ubuf.mapCrop.z, 0.001), 1.0);
    float sdPx = (f.b * 2.0 - 1.0) * ubuf.wallfxSdRange * max(ubuf.sw, 1.0) * zCh / denom;
    float fwSd = max(fwidth(sdPx), 1e-3);
    float inside = clamp(0.5 - sdPx / fwSd, 0.0, 1.0);

    float back = escena(t / 0.18);
    vec3 st = oldAt(uv);
    st = mix(st, vec3(luma(st)), 0.25 * back) * (1.0 - 0.2 * back);

    vec2 grid = max(vec2(ubuf.sw, ubuf.sh) / CELL, vec2(1.0));
    vec2 cuv = (floor(uv * grid) + 0.5) / grid;

    float Ti = escena((t - 0.32) / 0.32) * 1.02 - 0.01;
    vec3 cIn = texture(fieldTex, mapUv(cuv, zCh)).g <= Ti ? newAt(uv, zCh) : st;

    float To = escena((t - 0.45) / 0.50) * 1.02 - 0.01;
    vec3 cOut = surface(mapUv(cuv, zBg)) <= To ? newAt(uv, zBg) : st;
    vec3 c = mix(cOut, cIn, inside);

    float drawP = escena((t - 0.02) / 0.33);
    float lp = texture(lineTex, mapUv(uv, zCh)).r;
    float fade = 1.0 - escena((t - 0.45) / 0.25);
    float iAlpha = max(0.0001, ubuf.wallfxInk.a);
    vec3 inkRgb = ubuf.wallfxInk.rgb / iAlpha;
    if (lp > 0.0 && lp <= drawP && fade > 0.0) {
        float d = abs(sdPx) - ubuf.wallfxLineW * 0.5;
        float core = clamp(0.5 - d / fwSd, 0.0, 1.0);
        c = mix(c, inkRgb, core * 0.75 * fade);
    }
    return c;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(ubuf.progress, 0.0, 1.0);
    if (p <= 0.0001) {
        fragColor = texture(source1, uv) * ubuf.qt_Opacity;
        return;
    }
    if (p >= 0.9999) {
        fragColor = texture(source2, uv) * ubuf.qt_Opacity;
        return;
    }
    vec3 c = ubuf.wallfxMode < 0.5 ? contagion(uv, p) : outline(uv, p);
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
