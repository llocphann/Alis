#version 440

// Abyss Liquid: one cohesive moving material, shared with AbyssField.
// The fluid's surface, raised layer, rim, shadow and glow are literally the
// Abyss Panel Style pigments; there is no independent wallpaper ink palette.
// Two bounded noise fields, no loops or additional render/texture passes.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float time;
    vec2 aspectRatio;
    vec2 origin;
    vec4 liquidSurface;
    vec4 liquidRaised;
    vec4 liquidRim;
    vec4 liquidShadow;
    vec4 liquidGlow;
    float liquidHighlightStrength;
    float liquidMotionIntensity;
} ubuf;

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

float hash12(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float noise2(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(cell);
    float b = hash12(cell + vec2(1.0, 0.0));
    float c = hash12(cell + vec2(0.0, 1.0));
    float d = hash12(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(ubuf.progress, 0.0, 1.0);

    // Untinted endpoint frames, including when an animation is interrupted.
    if (p <= 0.0001) {
        fragColor = texture(source1, uv) * ubuf.qt_Opacity;
        return;
    }
    if (p >= 0.9999) {
        fragColor = texture(source2, uv) * ubuf.qt_Opacity;
        return;
    }

    // The moving front is a warped, connected distance field, closer to an
    // Abyss panel membrane than a wipe or a collection of descending streaks.
    // Slow, low-frequency lobes create pooled areas; a small detail layer
    // splits the edge into rounded necks without breaking it into columns.
    float motion = clamp(ubuf.liquidMotionIntensity, 0.0, 1.0);
    float activity = 4.0 * p * (1.0 - p);
    float broad = noise2(uv * vec2(3.2, 2.4)
        + vec2(ubuf.time * 0.10, -ubuf.time * 0.08));
    float fine = noise2(uv * vec2(8.5, 5.0)
        + vec2(-ubuf.time * 0.16, ubuf.time * 0.12));
    float slowRoll = sin(uv.x * 10.0 + 2.3 * broad
        + ubuf.time * 0.35) * 0.009;
    float displacement = (0.20 * (broad - 0.5)
        + 0.054 * (fine - 0.5) + slowRoll)
        * activity * mix(0.65, 1.07, motion);
    float signedFront = mix(-0.19, 1.19, p) - uv.y - displacement;
    float feather = max(0.008, fwidth(signedFront) * 0.90 + 0.006);
    float reveal = smoothstep(-feather, feather, signedFront);

    // Match the Panel's edge-local refraction, not a displaced wallpaper.
    // Neither image has any translation away from the material contact line.
    float contact = exp(-abs(signedFront) * 26.0) * activity;
    vec2 refractOffset = vec2((fine - 0.5) * 0.004,
        (broad - 0.5) * 0.006) * contact;
    vec4 outgoing = texture(source1, clamp(uv - refractOffset, 0.0, 1.0));
    vec4 incoming = texture(source2, clamp(uv + refractOffset * 0.48, 0.0, 1.0));
    vec4 scene = mix(outgoing, incoming, reveal);

    // A dense sheet just behind the fluid front, and a weaker surrounding
    // layer. Both recede into the actual new wallpaper, never covering it all.
    float pool = smoothstep(-0.010, 0.040, signedFront)
        * (1.0 - smoothstep(0.15, 0.34, signedFront)) * activity;
    float depth = exp(-abs(signedFront - 0.058) * 13.0) * activity;
    float meniscus = exp(-abs(signedFront) * 69.0) * activity;
    float interiorFold = exp(-abs(signedFront - 0.085) * 24.0)
        * activity * (0.64 + 0.36 * broad);

    // QColor uniforms are premultiplied by Qt. Recover the opaque panel pigment
    // but use its alpha to respect the user's chosen Abyss surface opacity.
    float panelAlpha = clamp(ubuf.liquidSurface.a, 0.0, 1.0);
    vec3 panelColor = ubuf.liquidSurface.rgb / max(0.0001, panelAlpha);
    vec3 raisedColor = ubuf.liquidRaised.rgb;
    vec3 material = mix(panelColor, raisedColor,
        clamp(0.18 + 0.27 * broad + 0.18 * interiorFold, 0.0, 0.65));
    float materialAmount = clamp((0.40 * pool + 0.21 * depth)
        * panelAlpha, 0.0, 0.60);
    vec3 tinted = mix(scene.rgb, material, materialAmount);

    // The actual Abyss Panel uses a softer raised rim, a small directional
    // specular catch and a low-glow shadowed perimeter. Reuse that language.
    // Derivatives are evaluated before any branch-dependent shading.
    vec2 normal = normalize(vec2(dFdx(signedFront), dFdy(signedFront))
        + vec2(0.0001));
    float facing = clamp(dot(normal, normalize(vec2(-0.45, -0.85)))
        * 0.5 + 0.5, 0.0, 1.0);
    float highlight = clamp(ubuf.liquidHighlightStrength, 0.0, 1.0);
    float specular = meniscus * (0.15 + 0.34 * pow(facing, 3.0))
        * highlight;
    float fineCatch = exp(-abs(signedFront + 0.014) * 104.0)
        * activity * pow(facing, 5.0) * highlight;
    tinted = mix(tinted, raisedColor, interiorFold * 0.085 * highlight);
    tinted += ubuf.liquidRim.rgb * (0.23 * specular + 0.11 * fineCatch);
    // Shadow and glow uniforms are already premultiplied by their opacity.
    float shadowContact = exp(-abs(signedFront - 0.055) * 23.0) * activity;
    tinted = mix(tinted,
        ubuf.liquidShadow.rgb / max(0.0001, ubuf.liquidShadow.a),
        clamp(ubuf.liquidShadow.a * shadowContact * 0.24, 0.0, 0.16));
    tinted += ubuf.liquidGlow.rgb * meniscus * 0.20;

    fragColor = vec4(tinted, scene.a) * ubuf.qt_Opacity;
}
