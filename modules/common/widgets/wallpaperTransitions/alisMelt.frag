#version 440

// Abyss Liquid: a flowing organic front with live Material 3 theme colors.
// Two wallpaper samples, two bounded noise layers, no stripe quantization.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float time;
    vec2 aspectRatio;
    vec2 origin;
    vec4 liquidAccent;
    vec4 liquidDepth;
    vec4 liquidHighlight;
} ubuf;

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

// Arithmetic hash avoids multiple trigonometric operations per noise sample.
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

    // Exact endpoints preserve the wallpaper and prevent stuck tint frames.
    if (p <= 0.0001) {
        fragColor = texture(source1, uv) * ubuf.qt_Opacity;
        return;
    }
    if (p >= 0.9999) {
        fragColor = texture(source2, uv) * ubuf.qt_Opacity;
        return;
    }

    // Low-frequency warped waves create an irregular, cohesive liquid mass.
    float broad = noise2(uv * vec2(4.0, 2.6)
        + vec2(ubuf.time * 0.13, -ubuf.time * 0.09));
    float fine = noise2(uv * vec2(10.5, 5.3)
        + vec2(-ubuf.time * 0.21, ubuf.time * 0.15));
    float curl = sin(uv.x * 15.0 + sin(uv.y * 8.0 + ubuf.time * 0.6)
        + ubuf.time * 0.42) * 0.016;

    // The front moves fully offscreen at either endpoint, with rounded inlets
    // and slower eddies. All distortion vanishes as the animation settles.
    float activity = 4.0 * p * (1.0 - p);
    float displacement = ((broad - 0.5) * 0.21
        + (fine - 0.5) * 0.075 + curl) * activity;
    float signedFront = mix(-0.18, 1.18, p) - uv.y - displacement;
    float feather = 0.014 + 0.012 * fine;
    float reveal = smoothstep(-feather, feather, signedFront);

    // Refract only near the waterline: the rest of the image stays crisp.
    float membrane = exp(-abs(signedFront) * 19.0) * activity;
    vec2 refractOffset = vec2((fine - 0.5) * 0.013,
        (broad - 0.5) * 0.019) * membrane;
    vec4 outgoing = texture(source1, clamp(uv - refractOffset, 0.0, 1.0));
    vec4 incoming = texture(source2, clamp(uv + refractOffset * 0.55, 0.0, 1.0));
    vec4 scene = mix(outgoing, incoming, reveal);

    // Viscous tinted ink and a delicate meniscus; every color is theme-driven.
    float body = exp(-abs(signedFront - 0.032) * 20.0)
        * activity * 0.29;
    float rim = exp(-abs(signedFront) * 72.0) * activity;
    float glint = exp(-abs(signedFront + 0.021) * 84.0)
        * activity * (0.16 + 0.20 * fine);
    vec3 ink = mix(ubuf.liquidDepth.rgb, ubuf.liquidAccent.rgb,
        0.28 + 0.32 * broad);
    vec3 tinted = mix(scene.rgb, ink, clamp(body + rim * 0.14, 0.0, 0.45));
    tinted += ubuf.liquidAccent.rgb * (rim * 0.12);
    tinted += ubuf.liquidHighlight.rgb * glint * 0.09;

    fragColor = vec4(tinted, scene.a) * ubuf.qt_Opacity;
}
